local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StatCalculator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StatCalculator"))

local SwordService = {
	Name = "SwordService",
	Priority = -75,
}

function SwordService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	-- Create Events folder if it doesn't exist
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder == nil then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = ReplicatedStorage
	end
	
	-- Create EquipSword remote if it doesn't exist
	self._equipSwordRemote = eventsFolder:FindFirstChild("EquipSword")
	if self._equipSwordRemote == nil then
		self._equipSwordRemote = Instance.new("RemoteEvent")
		self._equipSwordRemote.Name = "EquipSword"
		self._equipSwordRemote.Parent = eventsFolder
	end
end

function SwordService:_findSwordTemplate(swordName: string)
	local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
	if toolsFolder == nil then return nil end
	
	local swordsFolder = toolsFolder:FindFirstChild("Swords")
	if swordsFolder == nil then return nil end
	
	return swordsFolder:FindFirstChild(swordName)
end

function SwordService:_updatePlayerDamage(player: Player)
	local stats = player:FindFirstChild("Stats")
	if not stats then return end
	
	local swords = stats:FindFirstChild("Swords")
	local currentSword = swords and swords:FindFirstChild("CurrentSword")
	if not currentSword or currentSword.Value == "" then return end
	
	local ownedSwords = stats:FindFirstChild("OwnedSwords")
	local swordLevelVal = ownedSwords and ownedSwords:FindFirstChild(currentSword.Value)
	local level = swordLevelVal and swordLevelVal.Value or 1
	
	local template = self:_findSwordTemplate(currentSword.Value)
	local baseDamage = StatCalculator.GetTemplateBaseDamage(template, 1) 
	
	local calculatedDamage = StatCalculator.CalculateSwordDamage(baseDamage, level, currentSword.Value, self._config)
	
	-- Force the correct damage based on calculation to prevent illegal/outdated values
	player:SetAttribute("Damage", calculatedDamage)
end

function SwordService:_setupPlayerListeners(player: Player)
	local stats = player:WaitForChild("Stats", 10)
	if not stats then return end
	
	local swords = stats:WaitForChild("Swords", 5)
	local ownedSwords = stats:WaitForChild("OwnedSwords", 5)
	if not swords or not ownedSwords then return end
	
	local currentSword = swords:WaitForChild("CurrentSword", 5)
	
	local function update()
		self:_updatePlayerDamage(player)
	end
	
	currentSword.Changed:Connect(update)
	
	for _, child in ipairs(ownedSwords:GetChildren()) do
		if child:IsA("IntValue") then
			child.Changed:Connect(update)
		end
	end
	
	ownedSwords.ChildAdded:Connect(function(child)
		if child:IsA("IntValue") then
			child.Changed:Connect(update)
			update()
		end
	end)
	
	-- Immediate check on load to ensure no illegal values
	update()
end

function SwordService:_giveSword(player: Player, swordName: string)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	local stats = player:FindFirstChild("Stats")
	local ownedSwords = stats and stats:FindFirstChild("OwnedSwords")
	
	if character == nil or backpack == nil or ownedSwords == nil then return end
	
	local savedSwordLevel = ownedSwords:FindFirstChild(swordName)
	if savedSwordLevel == nil then return end
	
	local template = self:_findSwordTemplate(swordName)
	if template == nil then
		warn("[SwordService] Could not find sword template: " .. tostring(swordName))
		return
	end
	
	-- Remove existing swords
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") or child:IsA("Configuration") then
			if child:GetAttribute("Damage") ~= nil or child:FindFirstChild("Damage") ~= nil or child.Name == swordName then
				child:Destroy()
			end
		end
	end
	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") or child:IsA("Configuration") then
			if child:GetAttribute("Damage") ~= nil or child:FindFirstChild("Damage") ~= nil or child.Name == swordName then
				child:Destroy()
			end
		end
	end
	
	-- Give new sword
	local clone = template:Clone()
	
	-- Find the existing Level IntValue from the template
	local toolLevelVal = clone:FindFirstChild("Level")
	if toolLevelVal == nil then
		toolLevelVal = Instance.new("IntValue")
		toolLevelVal.Name = "Level"
		toolLevelVal.Parent = clone
	end
	
	-- Only set the tool's level if the saved level is valid
	if savedSwordLevel.Value > 0 then
		toolLevelVal.Value = savedSwordLevel.Value
	else
		toolLevelVal.Value = 1
		savedSwordLevel.Value = 1
	end
	
	-- Two-way sync: if the tool's level goes up, save it to Stats immediately so DataService sees it
	toolLevelVal.Changed:Connect(function(newVal)
		if savedSwordLevel and savedSwordLevel.Parent then
			if savedSwordLevel.Value ~= newVal then
				savedSwordLevel.Value = newVal
			end
		end
		
		-- Recalculate player damage immediately upon level change using centralized StatCalculator
		local baseDamage = StatCalculator.GetTemplateBaseDamage(template, 1) 
		local calculatedDamage = StatCalculator.CalculateSwordDamage(baseDamage, newVal, swordName, self._config)
		player:SetAttribute("Damage", calculatedDamage)
	end)

	clone.Parent = backpack
	
	-- Automatically equip it
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and clone:IsA("Tool") then
		humanoid:EquipTool(clone)
	end
end

function SwordService:_handlePlayerSpawn(player: Player)
	local stats = player:WaitForChild("Stats", 10)
	if stats == nil then return end
	
	local swords = stats:WaitForChild("Swords", 5)
	if swords == nil then return end
	
	local currentSword = swords:WaitForChild("CurrentSword", 5)
	if currentSword == nil or currentSword.Value == "" then return end
	
	-- Small delay to let default loading/inventory finish
	task.delay(1, function()
		if player.Parent ~= nil and player.Character ~= nil then
			self:_giveSword(player, currentSword.Value)
		end
	end)
end

function SwordService:Start()
	self._equipSwordRemote.OnServerEvent:Connect(function(player, swordName)
		if type(swordName) ~= "string" then return end
		
		local stats = player:FindFirstChild("Stats")
		local ownedSwords = stats and stats:FindFirstChild("OwnedSwords")
		local swords = stats and stats:FindFirstChild("Swords")
		local currentSword = swords and swords:FindFirstChild("CurrentSword")
		
		if ownedSwords == nil or currentSword == nil then return end
		
		-- Verify player owns the sword
		if ownedSwords:FindFirstChild(swordName) == nil then
			warn(player.Name .. " attempted to equip an unowned sword: " .. swordName)
			return
		end
		
		currentSword.Value = swordName
		self:_giveSword(player, swordName)
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		self:_setupPlayerListeners(player)
		player.CharacterAdded:Connect(function()
			self:_handlePlayerSpawn(player)
		end)
		if player.Character then
			self:_handlePlayerSpawn(player)
		end
	end
	
	Players.PlayerAdded:Connect(function(player)
		self:_setupPlayerListeners(player)
		player.CharacterAdded:Connect(function()
			self:_handlePlayerSpawn(player)
		end)
	end)
end

return SwordService
