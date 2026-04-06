local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local LuckyBlockService = {
	Name = "LuckyBlockService",
	Priority = -25,
}

function LuckyBlockService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetLuckyBlockRemote()
	self._bases = Workspace:WaitForChild("Bases", 10)
	
	self._trackedBlocks = {}
end

local function getBaseFromDescendant(descendant, bases)
	local current = descendant
	while current and current.Parent ~= bases do
		current = current.Parent
	end

	if current and (current:IsA("Folder") or current:IsA("Model")) then
		return current
	end

	return nil
end

function LuckyBlockService:_setupLuckyBlock(animal)
	if not animal:GetAttribute("IsLuckyBlock") or animal:GetAttribute("IsRolling") then return end
	if self._trackedBlocks[animal] then return end

	local base = getBaseFromDescendant(animal, self._bases)
	if not base then return end
	
	-- We only track placed lucky blocks
	if not animal:GetAttribute("Placed") then return end

	local lbConfig = self._config.Animals.LuckyBlocks[animal.Name]
	if not lbConfig then return end

	-- Ensure TimeElapsed exists and account for offline progress once.
	local persistedElapsed = animal:GetAttribute("TimeElapsed")
	if typeof(persistedElapsed) ~= "number" then
		persistedElapsed = 0
	end
	local lastPlacedTime = animal:GetAttribute("PlacedTime")
	local now = os.time()
	if lastPlacedTime and typeof(lastPlacedTime) == "number" and lastPlacedTime > 0 then
		local offlineProgress = now - lastPlacedTime
		if offlineProgress > 0 then
			persistedElapsed += offlineProgress
		end
	end

	animal:SetAttribute("TimeElapsed", persistedElapsed)
	animal:SetAttribute("PlacedTime", now)

	local promptPart = animal:FindFirstChild("GrabPart")
	if not promptPart then
		-- Wait for GrabPart to be created by AnimalService
		promptPart = animal:WaitForChild("GrabPart", 10)
	end
	if not promptPart then return end

	-- Find standard Grab prompt
	local grabPrompt = promptPart:WaitForChild("GrabPrompt", 10)
	
	self._trackedBlocks[animal] = {
		base = base,
		grabPrompt = grabPrompt,
		promptPart = promptPart,
		waitTime = lbConfig.WaitTime,
		baseElapsed = persistedElapsed,
		placedStart = now,
		lastReplicatedTimeLeft = nil,
		lastPersistStamp = now,
	}
end

function LuckyBlockService:_rollLuckyBlock(player, animal)
	local lbConfig = self._config.Animals.LuckyBlocks[animal.Name]
	if not lbConfig then return end
	
	animal:SetAttribute("IsRolling", true)
	
	-- Cleanup prompts for rolling
	local data = self._trackedBlocks[animal]
	if data then
		if data.rollPrompt then data.rollPrompt:Destroy() data.rollPrompt = nil end
		if data.grabPrompt then data.grabPrompt.Parent = nil end
	end

	-- Pick the rarity to roll
	local allowedRarities = lbConfig.RollRarities or {"Common"}
	local chosenRarity = allowedRarities[math.random(1, #allowedRarities)]
	
	-- Pick an animal from that rarity
	local spawnService = self._runtime:GetService("SpawnService")
	local sourceFolder = spawnService and spawnService._folderReferences[chosenRarity]
	local newAnimalTemplate = nil
	if sourceFolder then
		local choices = sourceFolder:GetChildren()
		if #choices > 0 then
			newAnimalTemplate = choices[math.random(1, #choices)]
		end
	end
	
	if not newAnimalTemplate then
		animal:SetAttribute("IsRolling", false)
		return
	end

	local animalPivot = animal:GetPivot()

	-- Inform client to play rolling animation
	self._remote:FireAllClients("StartRoll", {
		luckyBlock = animal,
		resultRarity = chosenRarity,
		resultAnimalName = newAnimalTemplate.Name
	})

	-- Wait for the client animation to finish rolling (~6 seconds)
	task.delay(6, function()
		if not animal.Parent then return end
		
		local base = getBaseFromDescendant(animal, self._bases)
		local pad = animal.Parent and animal.Parent.Parent
		if base and pad then
			local animalService = self._runtime:GetService("AnimalService")
			if animalService then
				-- Replace the block with the new animal
				local placerPart = pad:FindFirstChild("Placer", true)
				local placerPrompt = placerPart and placerPart:FindFirstChildWhichIsA("ProximityPrompt")

				if placerPart and placerPrompt then
					local rollLevel = 1
					local levelingConfig = self._config.Animals.Leveling
					if type(levelingConfig) == "table" then
						local minLevel = math.max(1, math.floor(tonumber(levelingConfig.MinLevel) or 1))
						local maxLevel = math.max(minLevel, math.floor(tonumber(levelingConfig.MaxLevel) or minLevel))
						local weightPower = math.max(1, tonumber(levelingConfig.WeightPower) or 2)
						local levelRange = maxLevel - minLevel + 1
						rollLevel = minLevel + math.floor(levelRange * (math.random() ^ weightPower))
					end

					local createdAnimal = animalService:_createPlacedAnimal(base, pad, {
						name = newAnimalTemplate.Name,
						rarity = chosenRarity,
						attributes = { Level = rollLevel },
						tags = {}
					}, placerPart, placerPrompt)
					
					if createdAnimal then
						-- Force stats recalculation and tag refresh to ensure no 0s
						animalService:_recalculateAnimalStats(createdAnimal)
						animalService:_refreshAnimalTag(createdAnimal)
						
						-- Preserve the orientation exactly
						createdAnimal:PivotTo(animalPivot)
					end
				end
			end
		end
		
		animal:Destroy()
	end)
end

function LuckyBlockService:Start()
	self._remote.OnServerEvent:Connect(function(player, action, data)
		if action == "PlayAnimalSound" then
			local animalName = data.AnimalName
			local position = data.Position
			if animalName and position then
				local animalSounds = ServerStorage:FindFirstChild("Assets") and ServerStorage.Assets:FindFirstChild("AnimalSounds")
				if animalSounds then
					local specificSound = animalSounds:FindFirstChild(animalName)
					if specificSound and specificSound:IsA("Sound") then
						local soundPart = Instance.new("Part")
						soundPart.Name = "AnimalSoundPart_" .. animalName
						soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
						soundPart.Transparency = 1
						soundPart.CanCollide = false
						soundPart.Anchored = true
						soundPart.CFrame = CFrame.new(position)
						soundPart.Parent = Workspace
						
						local soundClone = specificSound:Clone()
						soundClone.Parent = soundPart
						soundClone:Play()
						
						game:GetService("Debris"):AddItem(soundPart, math.max(2, soundClone.TimeLength + 0.5))
					end
				end
			end
		end
	end)

	-- Watch for new animals being placed
	if self._bases then
		self._bases.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Model") and descendant:GetAttribute("IsLuckyBlock") then
				task.defer(function() -- wait for it to be fully placed
					if descendant.Parent then
						self:_setupLuckyBlock(descendant)
					end
				end)
			end
		end)
		
		-- Setup any already existing ones
		for _, base in ipairs(self._bases:GetChildren()) do
			for _, desc in ipairs(base:GetDescendants()) do
				if desc:IsA("Model") and desc:GetAttribute("IsLuckyBlock") then
					self:_setupLuckyBlock(desc)
				end
			end
		end
	end
	
	-- Tracker Loop
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for animal, data in pairs(self._trackedBlocks) do
				if animal.Parent == nil then
					self._trackedBlocks[animal] = nil
					continue
				end
				
				if animal:GetAttribute("IsRolling") then continue end

				local isPlaced = animal:GetAttribute("Placed") == true
				
				if isPlaced then
					if data.placedStart == nil then
						data.placedStart = now
						animal:SetAttribute("PlacedTime", now)
					end

					local elapsed = data.baseElapsed + math.max(0, now - data.placedStart)
					local timeLeft = math.max(0, data.waitTime - elapsed)
					local replicatedTimeLeft = math.ceil(timeLeft)

					if data.lastReplicatedTimeLeft ~= replicatedTimeLeft then
						data.lastReplicatedTimeLeft = replicatedTimeLeft
						animal:SetAttribute("TimeLeft", replicatedTimeLeft)
					end

					-- Persist coarsely to avoid per-second replication spam.
					if (now - data.lastPersistStamp) >= 10 then
						data.lastPersistStamp = now
						data.baseElapsed = elapsed
						data.placedStart = now
						animal:SetAttribute("TimeElapsed", data.baseElapsed)
						animal:SetAttribute("PlacedTime", now)
					end
					
					if timeLeft <= 0 then
						-- READY: Hide Grab, Show Roll
						if data.grabPrompt and data.grabPrompt.Parent ~= nil then
							data.grabPrompt.Parent = nil
						end
						
						if not data.rollPrompt or data.rollPrompt.Parent == nil then
							local rollPrompt = Instance.new("ProximityPrompt")
							rollPrompt.Name = "RollPrompt"
							rollPrompt.ActionText = "Roll"
							rollPrompt.ObjectText = animal.Name
							rollPrompt.HoldDuration = 0.5
							rollPrompt.MaxActivationDistance = 8
							rollPrompt:SetAttribute("VisibilityRole", "OwnerOnly")
							rollPrompt.Parent = data.promptPart
							data.rollPrompt = rollPrompt
							
							rollPrompt.Triggered:Connect(function(player)
								if player.Name ~= data.base.Name then return end
								if animal:GetAttribute("IsRolling") then return end
								
								self:_rollLuckyBlock(player, animal)
							end)
						end
					else
						-- NOT READY: Hide Roll, Show Grab
						if data.rollPrompt then
							data.rollPrompt:Destroy()
							data.rollPrompt = nil
						end
						
						if data.grabPrompt and data.grabPrompt.Parent == nil then
							data.grabPrompt.Parent = data.promptPart
						end
					end
				else
					if data.placedStart ~= nil then
						local elapsed = data.baseElapsed + math.max(0, now - data.placedStart)
						data.baseElapsed = elapsed
						data.placedStart = nil
						data.lastPersistStamp = now
						animal:SetAttribute("TimeElapsed", data.baseElapsed)
					end

					-- Grabbed/Held: Ensure PlacedTime is cleared so it resets on next placement
					animal:SetAttribute("PlacedTime", nil)
					
					-- Hide Roll prompt if it exists
					if data.rollPrompt then
						data.rollPrompt:Destroy()
						data.rollPrompt = nil
					end
				end
			end
		end
	end)
end

return LuckyBlockService
