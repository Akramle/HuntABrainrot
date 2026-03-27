local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TextChatService = game:GetService("TextChatService")
local CollectionService = game:GetService("CollectionService")

local StatCalculator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StatCalculator"))

local AdminService = {
	Name = "AdminService",
	Priority = -20,
}

local function isAdmin(player: Player, config: table): boolean
	if RunService:IsStudio() and player.UserId <= 0 then
		return true
	end
	if player.UserId == game.CreatorId then
		return true
	end
	if config.Admins and config.Admins[player.UserId] then
		return true
	end
	return false
end

local function sendFeedback(player: Player, message: string, isError: boolean)
	local colorHex = isError and "#FF5555" or "#55FF55"
	local prefix = isError and "[Admin Error]: " or "[Admin]: "
	
	local remote = ReplicatedStorage:WaitForChild("RuntimeRemotes"):FindFirstChild("AdminAction")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, "Feedback", {Message = prefix .. message, Color = colorHex})
	end
end

local function getTargetPlayer(targetName: string): Player?
	if not targetName or targetName == "" then return nil end
	targetName = targetName:lower()
	
	for _, p in ipairs(Players:GetPlayers()) do
		if string.sub(p.Name:lower(), 1, #targetName) == targetName then
			return p
		end
		if p.DisplayName and string.sub(p.DisplayName:lower(), 1, #targetName) == targetName then
			return p
		end
	end
	return nil
end

function AdminService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetAdminRemote()
	self._animalsStorage = ServerStorage:WaitForChild("Assets"):WaitForChild("Animals")
	
	local templatesFolder = ReplicatedStorage:FindFirstChild("AdminAnimalTemplates")
	if not templatesFolder then
		templatesFolder = Instance.new("Folder")
		templatesFolder.Name = "AdminAnimalTemplates"
		templatesFolder.Parent = ReplicatedStorage
		
		for _, rarityFolder in ipairs(self._animalsStorage:GetChildren()) do
			local rFolder = Instance.new("Folder")
			rFolder.Name = rarityFolder.Name
			rFolder.Parent = templatesFolder
			
			for _, animal in ipairs(rarityFolder:GetChildren()) do
				local clone = animal:Clone()
				for _, descendant in ipairs(clone:GetDescendants()) do
					if descendant:IsA("Script") or descendant:IsA("LocalScript") then
						descendant:Destroy()
					end
				end
				clone.Parent = rFolder
			end
		end
	end
end

function AdminService:_calculateAnimalAttributes(rarity: string)
	local rarityStats = self._config.Animals.Stats[rarity]
	local attributes = { Level = 1, UpgradeLevel = 0 }
	
	if rarityStats then
		local baseRevenue = math.random(rarityStats.Revenue[1], rarityStats.Revenue[2])
		local health = math.random(rarityStats.Health[1], rarityStats.Health[2])
		
		attributes.MaxHealth = health
		attributes.Health = health
		attributes.BaseRevenue = baseRevenue
		
		local stats = StatCalculator.CalculateAnimalStats(baseRevenue, 1, 0, {}, self._config)
		attributes.Revenue = stats.Revenue
		attributes.Cost = stats.Cost
		attributes.UpgradeCost = stats.UpgradeCost
	end
	return attributes
end

function AdminService:ExecuteCommand(admin: Player, command: string, args: {string})
	command = command:lower()
	
	if command == "cmds" then
		local commandList = {
			"/cmds - Show this list",
			"/randomize <player> - Randomize base animals",
			"/kill <player>",
			"/explode <player>",
			"/fling <player>",
			"/giant <player>",
			"/give <player> - Select animal to give",
			"/spawn_wild [player] - Spawn wild near target",
			"/spawn_gold [player] - Spawn golden near target",
			"/fill_base <player> - Select animal to fill base",
			"/clear_player <player> - Clear inventory and base",
			"/freeze <player>",
			"/unfreeze <player>",
			"/unlock_areas <player>",
			"/add_bucks <player> <amount>",
			"/reset_bucks <player>",
			"/spawn_devine [player] - Spawn Devine near target or random",
			"/event <name> - Trigger a global event (e.g., Shrine)",
			"/event stop <name> - Stop an active global event",
			"/reset_data <player> - Hard reset stats/base",
			"/kick <player>"
		}
		for _, cmdText in ipairs(commandList) do
			sendFeedback(admin, cmdText, false)
		end
		return
	end
	
	if command == "randomize" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		
		local baseService = self._runtime:GetService("BaseService")
		local animalService = self._runtime:GetService("AnimalService")
		if baseService and animalService then
			local base = baseService:GetPlayerBase(target)
			if base then
				local allTemplates = {}
				for _, rarityFolder in ipairs(self._animalsStorage:GetChildren()) do
					for _, animal in ipairs(rarityFolder:GetChildren()) do
						table.insert(allTemplates, {name = animal.Name, rarity = rarityFolder.Name})
					end
				end
				
				local pads = {}
				for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
					if pad:IsDescendantOf(base) then table.insert(pads, pad) end
				end
				
				for _, pad in ipairs(pads) do
					local animalFolder = pad:FindFirstChild("Animal")
					if animalFolder then animalFolder:ClearAllChildren() end
					
					local template = allTemplates[math.random(1, #allTemplates)]
					local attributes = self:_calculateAnimalAttributes(template.rarity)
					animalService:_createPlacedAnimal(base, pad, {
						name = template.name,
						rarity = template.rarity,
						attributes = attributes,
						tags = {}
					})
				end
				sendFeedback(admin, "Randomized base for " .. target.Name, false)
			else
				sendFeedback(admin, target.Name .. " has no base", true)
			end
		end

	elseif command == "kill" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		if target.Character then target.Character:BreakJoints() end
		sendFeedback(admin, "Killed " .. target.Name, false)

	elseif command == "explode" then
		local target = getTargetPlayer(args[1])
		if not target or not target.Character then return sendFeedback(admin, "Player or character not found", true) end
		local root = target.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local ex = Instance.new("Explosion")
			ex.Position = root.Position
			ex.Parent = Workspace
			target.Character:BreakJoints()
			sendFeedback(admin, "Exploded " .. target.Name, false)
		end

	elseif command == "fling" then
		local target = getTargetPlayer(args[1])
		if not target or not target.Character then return sendFeedback(admin, "Player not found", true) end
		local root = target.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Velocity = Vector3.new(math.random(-1000, 1000), 1000, math.random(-1000, 1000))
			sendFeedback(admin, "Flung " .. target.Name, false)
		end

	elseif command == "giant" then
		local target = getTargetPlayer(args[1])
		if not target or not target.Character then return sendFeedback(admin, "Player not found", true) end
		local hum = target.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			local scaleValues = {"BodyDepthScale", "BodyHeightScale", "BodyProportionScale", "BodyWidthScale", "HeadScale"}
			for _, valName in ipairs(scaleValues) do
				local val = hum:FindFirstChild(valName)
				if val and val:IsA("NumberValue") then
					val.Value *= 3
				end
			end
			sendFeedback(admin, "Made " .. target.Name .. " a giant", false)
		end

	elseif command == "give" then
		local target = getTargetPlayer(args[1])
		if not target then
			return sendFeedback(admin, "Error: Player not found (Usage: /give <name>)", true)
		end
		self._remote:FireClient(admin, "OpenPicker", {Mode = "give", Target = target.Name})
		sendFeedback(admin, "Opening animal picker for " .. target.Name .. "...", false)

	elseif command == "spawn_wild" then
		local target = getTargetPlayer(args[1]) or admin
		self._remote:FireClient(admin, "OpenPicker", {Mode = "spawn_wild", Target = target.Name})
		sendFeedback(admin, "Opening animal picker (spawning near " .. target.Name .. ")...", false)

	elseif command == "fill_base" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Usage: /fill_base <player>", true) end
		self._remote:FireClient(admin, "OpenPicker", {Mode = "fill_base", Target = target.Name})
		sendFeedback(admin, "Opening animal picker to fill " .. target.Name .. "'s base...", false)

	elseif command == "clear_player" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		
		target.Backpack:ClearAllChildren()
		if target.Character then
			for _, tool in ipairs(target.Character:GetChildren()) do
				if tool:IsA("Tool") then tool:Destroy() end
			end
		end
		
		local baseService = self._runtime:GetService("BaseService")
		if baseService then
			local base = baseService:GetPlayerBase(target)
			if base then
				for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
					if pad:IsDescendantOf(base) then
						local animalFolder = pad:FindFirstChild("Animal")
						if animalFolder then animalFolder:ClearAllChildren() end
						local fullVal = pad:FindFirstChild("Full")
						if fullVal then fullVal.Value = false end
						local placer = pad:FindFirstChild("Placer")
						if placer and placer:IsA("ProximityPrompt") then placer.Enabled = true end
					end
				end
			end
		end
		sendFeedback(admin, "Cleared " .. target.Name .. "'s inventory and base", false)

	elseif command == "freeze" or command == "unfreeze" then
		local target = getTargetPlayer(args[1])
		if not target or not target.Character then return sendFeedback(admin, "Player not found", true) end
		local root = target.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = (command == "freeze")
			sendFeedback(admin, (command == "freeze" and "Frozen " or "Unfrozen ") .. target.Name, false)
		end

	elseif command == "unlock_areas" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		local stats = target:FindFirstChild("Stats")
		local unlocked = stats and stats:FindFirstChild("UnlockedAreas")
		if unlocked then
			local areas = Workspace:FindFirstChild("Areas")
			if areas then
				for _, area in ipairs(areas:GetChildren()) do
					local val = unlocked:FindFirstChild(area.Name)
					if not val then
						val = Instance.new("BoolValue")
						val.Name = area.Name
						val.Parent = unlocked
					end
					val.Value = true
				end
			end
			sendFeedback(admin, "Unlocked all areas for " .. target.Name, false)
		end

	elseif command == "add_bucks" then
		local target = getTargetPlayer(args[1])
		local amount = tonumber(args[2])
		if not target or not amount then return sendFeedback(admin, "Usage: /add_bucks <player> <amount>", true) end
		
		local bucks = target:FindFirstChild("leaderstats") and target.leaderstats:FindFirstChild("Bucks")
		if bucks then
			bucks.Value += amount
			sendFeedback(admin, "Added " .. amount .. " Bucks to " .. target.Name, false)
		end

	elseif command == "reset_bucks" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		
		local bucks = target:FindFirstChild("leaderstats") and target.leaderstats:FindFirstChild("Bucks")
		if bucks then
			bucks.Value = 0
			sendFeedback(admin, "Reset Bucks for " .. target.Name, false)
		end

	elseif command == "spawn_devine" then
		local target = getTargetPlayer(args[1])
		self:SpawnDevineAnimal(target)
		if target then
			sendFeedback(admin, "Spawned Devine near " .. target.Name, false)
		else
			sendFeedback(admin, "Spawned Devine at random location", false)
		end

	elseif command == "event" then
		local action = "Start"
		local eventName = args[1]
		
		if eventName == "stop" then
			action = "Stop"
			eventName = args[2]
		end
		
		if not eventName then
			return sendFeedback(admin, "Usage: /event <name> or /event stop <name>", true)
		end
		
		local eventService = self._runtime:GetService("EventService")
		if eventService then
			local success, result = pcall(function()
				return eventService:TriggerGlobalEvent(eventName, action)
			end)
			
			if success then
				if result == true then
					sendFeedback(admin, "Triggered Global Event " .. action .. ": " .. eventName, false)
				else
					sendFeedback(admin, "Failed: " .. tostring(result), true)
				end
			else
				sendFeedback(admin, "Critical Error: " .. tostring(result), true)
			end
		else
			sendFeedback(admin, "EventService not found", true)
		end

	elseif command == "reset_data" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		
		local leaderstats = target:FindFirstChild("leaderstats")
		if leaderstats then
			local bucks = leaderstats:FindFirstChild("Bucks")
			if bucks then bucks.Value = 0 end
		end
		
		local stats = target:FindFirstChild("Stats")
		if stats then
			local multiplier = stats:FindFirstChild("Multiplier")
			if multiplier then multiplier.Value = 1 end
			
			local swords = stats:FindFirstChild("Swords")
			if swords then
				local currentSword = swords:FindFirstChild("CurrentSword")
				if currentSword then currentSword.Value = "Wooden Sword" end
			end
			
			local ownedSwords = stats:FindFirstChild("OwnedSwords")
			if ownedSwords then
				ownedSwords:ClearAllChildren()
				local wooden = Instance.new("IntValue")
				wooden.Name = "Wooden Sword"
				wooden.Value = 1
				wooden.Parent = ownedSwords
			end
			
			local upgrades = stats:FindFirstChild("Upgrades")
			if upgrades then
				for _, upg in ipairs(upgrades:GetChildren()) do
					if upg:IsA("IntValue") or upg:IsA("NumberValue") then
						upg.Value = 1
					end
				end
			end
			
			local unlockedAreas = stats:FindFirstChild("UnlockedAreas")
			if unlockedAreas then
				unlockedAreas:ClearAllChildren()
				local plains = Instance.new("BoolValue")
				plains.Name = "Plains"
				plains.Value = true
				plains.Parent = unlockedAreas
			end
		end
		
		local baseService = self._runtime:GetService("BaseService")
		if baseService then
			local base = baseService:GetPlayerBase(target)
			if base then
				for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
					if pad:IsDescendantOf(base) then
						-- Use BaseService if it has a public reset method, otherwise manual
						local animalFolder = pad:FindFirstChild("Animal")
						if animalFolder then animalFolder:ClearAllChildren() end
						
						local attributes = {"StoredCash", "Full", "IsOccupied"}
						for _, attr in ipairs(attributes) do
							pad:SetAttribute(attr, (attr == "StoredCash" and 0 or false))
						end

						local collector = pad:FindFirstChild("Collector")
						if collector then
							collector:SetAttribute("StoredCash", 0)
						end

						local placer = pad:FindFirstChild("Placer")
						if placer then
							local fullVal = placer:FindFirstChild("Full")
							if fullVal then fullVal.Value = false end
							if placer:IsA("ProximityPrompt") then placer.Enabled = false end
						end
					end
				end
			end
		end
		
		target.Backpack:ClearAllChildren()
		if target.Character then
			for _, tool in ipairs(target.Character:GetChildren()) do
				if tool:IsA("Tool") then tool:Destroy() end
			end
		end

		-- Give default sword after 0.2s
		task.delay(0.2, function()
			if not target.Parent then return end
			local swordService = self._runtime:GetService("SwordService")
			if swordService then
				swordService:_giveSword(target, "Wooden Sword")
			end
		end)
		
		sendFeedback(admin, "Surgically reset " .. target.Name .. " to new player state", false)

	elseif command == "spawn_gold" then
		local target = getTargetPlayer(args[1]) or admin
		self._remote:FireClient(admin, "OpenPicker", {Mode = "spawn_wild", Target = target.Name, Mutation = "Gold"})
		sendFeedback(admin, "Opening animal picker (spawning GOLD near " .. target.Name .. ")...", false)

	elseif command == "kick" then
		local target = getTargetPlayer(args[1])
		if not target then return sendFeedback(admin, "Player not found", true) end
		target:Kick("Kicked by admin: " .. admin.Name)
		sendFeedback(admin, "Kicked " .. target.Name, false)
	end
end

function AdminService:GiveAnimalToPlayer(target: Player, rarity: string, animalName: string)
	local animalService = self._runtime:GetService("AnimalService")
	if not animalService then return end
	
	local attributes = self:_calculateAnimalAttributes(rarity)
	animalService:_giveAnimalTool(target, animalName, rarity, attributes, {}, true)
	sendFeedback(target, "You were given a " .. animalName .. " by an admin", false)
end

function AdminService:SpawnAnimalNearPlayer(target: Player, rarity: string, animalName: string)
	local rarityFolder = self._animalsStorage:FindFirstChild(rarity)
	local template = rarityFolder and rarityFolder:FindFirstChild(animalName)
	if not template then return end

	local character = target.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local clone = template:Clone()
	clone:SetAttribute("Rarity", rarity)
	
	local animalService = self._runtime:GetService("AnimalService")
	if animalService and type(animalService.SetupAnimal) == "function" then
		animalService:SetupAnimal(clone)
	end
	
	local spawnCFrame = rootPart.CFrame * CFrame.new(0, 0, -5)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {character, clone}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = Workspace:Raycast(spawnCFrame.Position + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rayParams)
	if result then
		spawnCFrame = CFrame.new(result.Position) * CFrame.Angles(0, select(2, spawnCFrame:ToEulerAnglesYXZ()), 0)
	end
	
	clone:PivotTo(spawnCFrame)
	
	local targetFolder = Workspace:FindFirstChild("Animals") and Workspace.Animals:FindFirstChild(rarity)
	if targetFolder then
		clone.Parent = targetFolder
	else
		clone.Parent = Workspace:FindFirstChild("Animals") or Workspace
	end
end

function AdminService:SpawnGoldAnimalNearPlayer(target: Player, rarity: string, animalName: string)
	local rarityFolder = self._animalsStorage:FindFirstChild(rarity)
	local template = rarityFolder and rarityFolder:FindFirstChild(animalName)
	if not template then return end

	local character = target.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local clone = template:Clone()
	clone:SetAttribute("Rarity", rarity)
	clone:SetAttribute("Mutation", "Gold")
	
	local animalService = self._runtime:GetService("AnimalService")
	if animalService and type(animalService.SetupAnimal) == "function" then
		animalService:SetupAnimal(clone)
	end
	
	local spawnCFrame = rootPart.CFrame * CFrame.new(0, 0, -5)
	
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {character, clone}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local result = Workspace:Raycast(spawnCFrame.Position + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rayParams)
	if result then
		spawnCFrame = CFrame.new(result.Position) * CFrame.Angles(0, select(2, spawnCFrame:ToEulerAnglesYXZ()), 0)
	end
	
	clone:PivotTo(spawnCFrame)

	local targetFolder = Workspace:FindFirstChild("Animals") and Workspace.Animals:FindFirstChild(rarity)
	if targetFolder then
		clone.Parent = targetFolder
	else
		clone.Parent = Workspace:FindFirstChild("Animals") or Workspace
	end
end

function AdminService:SpawnDevineAnimal(target: Player?)
	local rarity = "Devine"
	local rarityFolder = self._animalsStorage:FindFirstChild(rarity)
	if not rarityFolder then return end
	
	local animalChoices = rarityFolder:GetChildren()
	if #animalChoices == 0 then return end
	
	local selectedTemplate = animalChoices[math.random(1, #animalChoices)]
	local clone = selectedTemplate:Clone()
	clone:SetAttribute("Rarity", rarity)
	
	local animalService = self._runtime:GetService("AnimalService")
	local spawnService = self._runtime:GetService("SpawnService")
	
	if animalService and type(animalService.SetupAnimal) == "function" then
		animalService:SetupAnimal(clone)
	end
	
	local spawnCFrame = nil
	
	if target and target.Character then
		local rootPart = target.Character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			spawnCFrame = rootPart.CFrame * CFrame.new(0, 0, -5)
			
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = {target.Character, clone}
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			
			local result = Workspace:Raycast(spawnCFrame.Position + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rayParams)
			if result then
				spawnCFrame = CFrame.new(result.Position) * CFrame.Angles(0, select(2, spawnCFrame:ToEulerAnglesYXZ()), 0)
			end
		end
	end
	
	if not spawnCFrame and spawnService then
		-- Fallback to random spawn in a random area
		local spawnAreas = Workspace:FindFirstChild("SpawnAreas")
		if spawnAreas then
			local areas = spawnAreas:GetChildren()
			if #areas > 0 then
				local randomArea = areas[math.random(1, #areas)]
				if randomArea:IsA("BasePart") then
					-- We need to put it in Workspace for _getValidSpawnCFrame to work properly with raycasts
					clone.Parent = Workspace
					-- Use SpawnService's helper to find a valid spot
					spawnCFrame = spawnService:_getValidSpawnCFrame(randomArea, clone)
				end
			end
		end
	end
	
	if spawnCFrame then
		clone:PivotTo(spawnCFrame)
		local targetFolder = Workspace:FindFirstChild("Animals") and Workspace.Animals:FindFirstChild(rarity)
		if targetFolder then
			clone.Parent = targetFolder
		else
			clone.Parent = Workspace:FindFirstChild("Animals") or Workspace
		end
	else
		clone:Destroy()
	end
end

function AdminService:FillPlayerBaseWithAnimal(target: Player, rarity: string, animalName: string)
	local baseService = self._runtime:GetService("BaseService")
	local animalService = self._runtime:GetService("AnimalService")
	if not baseService or not animalService then return end
	
	local base = baseService:GetPlayerBase(target)
	if not base then return end
	
	local attributes = self:_calculateAnimalAttributes(rarity)
	
	for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
		if pad:IsDescendantOf(base) then
			local animalFolder = pad:FindFirstChild("Animal")
			if animalFolder then animalFolder:ClearAllChildren() end
			
			animalService:_createPlacedAnimal(base, pad, {
				name = animalName,
				rarity = rarity,
				attributes = attributes,
				tags = {}
			})
		end
	end
end

function AdminService:Start()
	local function checkAndSetAdmin(p)
		if isAdmin(p, self._config) then
			p:SetAttribute("IsAdmin", true)
		end
	end

	Players.PlayerAdded:Connect(checkAndSetAdmin)
	for _, p in ipairs(Players:GetPlayers()) do checkAndSetAdmin(p) end

	self._remote.OnServerEvent:Connect(function(player, action, data)
		if not isAdmin(player, self._config) then return end
		
		if action == "Command" then
			local cmd = data.Command
			local args = data.Args
			if type(cmd) == "string" and type(args) == "table" then
				task.spawn(function()
					self:ExecuteCommand(player, cmd, args)
				end)
			end
		elseif action == "SpawnWild" then
			local targetName = data.Target
			local target = if targetName then getTargetPlayer(targetName) else player
			if target then
				if data.Mutation == "Gold" then
					self:SpawnGoldAnimalNearPlayer(target, data.Rarity, data.AnimalName)
					sendFeedback(player, "Spawned GOLD " .. data.AnimalName .. " near " .. target.Name, false)
				else
					self:SpawnAnimalNearPlayer(target, data.Rarity, data.AnimalName)
					sendFeedback(player, "Spawned " .. data.AnimalName .. " near " .. target.Name, false)
				end
			end
		elseif action == "GiveAnimal" then
			local targetName = data.Target
			local target = if targetName then getTargetPlayer(targetName) else player
			if target then
				self:GiveAnimalToPlayer(target, data.Rarity, data.AnimalName)
				sendFeedback(player, "Gave " .. data.AnimalName .. " to " .. target.Name, false)
			end
		elseif action == "FillBase" then
			local targetName = data.Target
			local target = if targetName then getTargetPlayer(targetName) else player
			if target then
				self:FillPlayerBaseWithAnimal(target, data.Rarity, data.AnimalName)
				sendFeedback(player, "Filled " .. target.Name .. "'s base with " .. data.AnimalName, false)
			end
		elseif action == "SpawnGold" or action == "spawn_gold" then
			local targetName = data.Target
			local target = if targetName then getTargetPlayer(targetName) else player
			if target then
				self:SpawnGoldAnimalNearPlayer(target, data.Rarity, data.AnimalName)
				sendFeedback(player, "Spawned GOLD " .. data.AnimalName .. " near " .. target.Name, false)
			end
		end
	end)
end

return AdminService
