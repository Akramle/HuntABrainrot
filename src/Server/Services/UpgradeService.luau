local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatCalculator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StatCalculator"))

local UpgradeService = {
	Name = "UpgradeService",
	Priority = -25,
}

local function getDistance(part1, part2)
	if not part1 or not part2 then return math.huge end
	return (part1.Position - part2.Position).Magnitude
end

function UpgradeService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetUpgradeRemote()
	self._guiTemplate = ServerStorage:WaitForChild("Assets"):WaitForChild("Gui"):WaitForChild("UpgradeGui")
end

function UpgradeService:UpdatePlayerWalkspeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid then
		local stats = player:FindFirstChild("Stats")
		if stats then
			local upgrades = stats:FindFirstChild("Upgrades")
			local wsLevelVal = upgrades and upgrades:FindFirstChild("Walkspeed")
			local level = wsLevelVal and wsLevelVal.Value or 1
			-- Do not override hiding service walkspeed if they are hiding
			if player:GetAttribute("IsHiding") then return end
			
			local gearBonus = player:GetAttribute("GearWalkspeedBonus") or 0
			local baseWS = StatCalculator.CalculateWalkspeed(level, self._config, gearBonus)
			
			-- Carrying uses a fixed movement speed.
			if player:GetAttribute("CarryingAnimal") then
				baseWS = 19
			end
			
			humanoid.WalkSpeed = baseWS
		end
	end
end

function UpgradeService:_handleUpgradeShopPrompt(prompt: ProximityPrompt, player: Player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local shopPart = prompt.Parent
	if not shopPart or not shopPart:IsA("BasePart") then return end
	
	-- Verify distance
	if getDistance(rootPart, shopPart) > (prompt.MaxActivationDistance + 5) then
		warn("[UpgradeService] Player " .. player.Name .. " is too far from UpgradeShop.")
		return
	end
	
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end
	
	-- If they already have one, don't spawn another one
	if playerGui:FindFirstChild("UpgradeGui") then return end
	
	local newGui = self._guiTemplate:Clone()
	newGui.Parent = playerGui
	
	-- Tell the client to hook it up
	self._remote:FireClient(player, "BindGui")
end

function UpgradeService:Start()
	-- Handle Walkspeed applying on spawn
	Players.PlayerAdded:Connect(function(player)
		player:GetAttributeChangedSignal("CarryingAnimal"):Connect(function()
			self:UpdatePlayerWalkspeed(player)
		end)
		
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				task.wait(0.5) -- Small delay to ensure Roblox defaults don't override
				self:UpdatePlayerWalkspeed(player)
			end
		end)
	end)
	
	for _, player in ipairs(Players:GetPlayers()) do
		player:GetAttributeChangedSignal("CarryingAnimal"):Connect(function()
			self:UpdatePlayerWalkspeed(player)
		end)
		
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid then
				task.wait(0.5)
				self:UpdatePlayerWalkspeed(player)
			end
		end)
		if player.Character then
			task.spawn(function()
				task.wait(0.5)
				self:UpdatePlayerWalkspeed(player)
			end)
		end
	end

	-- Listen for prompt triggers
	for _, shop in ipairs(CollectionService:GetTagged("UpgradeShop")) do
		local prompt = shop:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				self:_handleUpgradeShopPrompt(prompt, player)
			end)
		end
	end

	CollectionService:GetInstanceAddedSignal("UpgradeShop"):Connect(function(shop)
		local prompt = shop:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				self:_handleUpgradeShopPrompt(prompt, player)
			end)
		end
	end)
	
	-- Handle remote requests from Client
	self._remote.OnServerEvent:Connect(function(player, action)
		local leaderstats = player:FindFirstChild("leaderstats")
		local stats = player:FindFirstChild("Stats")
		
		if not leaderstats or not stats then 
			warn("[UpgradeService] " .. player.Name .. " missing leaderstats or Stats")
			return 
		end
		
		local bucks = leaderstats:FindFirstChild("Bucks")
		if not bucks then 
			warn("[UpgradeService] " .. player.Name .. " missing Bucks")
			return 
		end
		
		if action == "UpgradeWalkspeed" then
			local upgrades = stats:FindFirstChild("Upgrades")
			if not upgrades then
				upgrades = Instance.new("Folder")
				upgrades.Name = "Upgrades"
				upgrades.Parent = stats
			end
			
			local wsLevelVal = upgrades:FindFirstChild("Walkspeed")
			if not wsLevelVal then 
				wsLevelVal = Instance.new("IntValue")
				wsLevelVal.Name = "Walkspeed"
				wsLevelVal.Value = 1
				wsLevelVal.Parent = upgrades
			end
			
			local currentLevel = wsLevelVal.Value
			if currentLevel >= self._config.Upgrades.Walkspeed.MaxLevel then return end
			
			local cost = math.floor(self._config.Upgrades.Walkspeed.BaseCost * (self._config.Upgrades.Walkspeed.CostMultiplier ^ (currentLevel - 1)))
			
			if bucks.Value >= cost then
				bucks.Value -= cost
				wsLevelVal.Value += 1
				self:UpdatePlayerWalkspeed(player)
				
				-- Trigger PlayerUpgrade effect
				local effectsRemote = self._runtime.Remotes:GetEffectsRemote()
				if effectsRemote then
					effectsRemote:FireClient(player, self._config.Effects.Names.PlayerUpgrade, {})
				end
			else
				self._runtime:GetService("NotificationService"):NotifyPlayer(player, "Not enough Bucks!", "Warning")
				warn("[UpgradeService] " .. player.Name .. " insufficient funds. Has: " .. tostring(bucks.Value) .. " Needs: " .. tostring(cost))
			end
			
		elseif action == "CloseGui" then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local gui = playerGui:FindFirstChild("UpgradeGui")
				if gui then
					gui:Destroy()
				end
			end
			
		elseif action == "UpgradeSword" then
			local swords = stats:FindFirstChild("Swords")
			local currentSwordVal = swords and swords:FindFirstChild("CurrentSword")
			local swordName = currentSwordVal and currentSwordVal.Value
			if not swordName or swordName == "" then return end
			
			local ownedSwords = stats:FindFirstChild("OwnedSwords")
			local swordLvlVal = ownedSwords and ownedSwords:FindFirstChild(swordName)
			if not swordLvlVal then return end
			
			local currentLevel = swordLvlVal.Value
			local config = self._config.Upgrades.Swords[swordName] or self._config.Upgrades.Swords["Default"]
			
			if currentLevel >= config.MaxLevel then return end
			
			local cost = math.floor(config.BaseCost * (config.CostMultiplier ^ (currentLevel - 1)))
			
			if bucks.Value >= cost then
				bucks.Value -= cost
				swordLvlVal.Value += 1
				
				-- If equipped, update the tool's level value too
				local character = player.Character
				if character then
					local tool = character:FindFirstChild(swordName)
					if tool then
						local lvlNode = tool:FindFirstChild("Level")
						if lvlNode then lvlNode.Value = swordLvlVal.Value end
					end
				end
				local backpack = player:FindFirstChild("Backpack")
				if backpack then
					local tool = backpack:FindFirstChild(swordName)
					if tool then
						local lvlNode = tool:FindFirstChild("Level")
						if lvlNode then lvlNode.Value = swordLvlVal.Value end
					end
				end
				
				-- Trigger PlayerUpgrade effect
				local effectsRemote = self._runtime.Remotes:GetEffectsRemote()
				if effectsRemote then
					effectsRemote:FireClient(player, self._config.Effects.Names.PlayerUpgrade, {})
				end
			end
		end
	end)
end

return UpgradeService
