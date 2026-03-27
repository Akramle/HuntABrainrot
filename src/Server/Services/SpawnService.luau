local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local SpawnService = {
	Name = "SpawnService",
	Priority = -30,
}

-- Checks if a part should be considered "Visible"
local function isPartVisible(part: BasePart): boolean
	if part.Transparency < 0.95 then return true end
	-- Sometimes builders use 100% transparent parts but put a Decal, Texture, or Mesh on them
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") or child:IsA("DataModelMesh") then
			return true
		end
	end
	return false
end

-- Finds the absolute lowest world-space coordinate of any visible part in the model
local function getLowestVisiblePoint(instance: Instance): Vector3?
	local lowestY = math.huge
	local lowestPoint = nil

	local parts = if instance:IsA("BasePart") then {instance} else instance:GetDescendants()
	
	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and isPartVisible(part) then
			local cf = part.CFrame
			local size = part.Size

			-- Account for SpecialMeshes resizing the visual part
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh and (mesh:IsA("SpecialMesh") or mesh:IsA("BlockMesh") or mesh:IsA("CylinderMesh")) then
				size = size * mesh.Scale
				cf = cf * CFrame.new(mesh.Offset)
			end

			local sx, sy, sz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
			
			-- The 8 corners of the part in 3D space
			local corners = {
				cf * Vector3.new( sx,  sy,  sz),
				cf * Vector3.new( sx,  sy, -sz),
				cf * Vector3.new( sx, -sy,  sz),
				cf * Vector3.new( sx, -sy, -sz),
				cf * Vector3.new(-sx,  sy,  sz),
				cf * Vector3.new(-sx,  sy, -sz),
				cf * Vector3.new(-sx, -sy,  sz),
				cf * Vector3.new(-sx, -sy, -sz)
			}

			for _, corner in ipairs(corners) do
				if corner.Y < lowestY then 
					lowestY = corner.Y 
					lowestPoint = corner
				end
			end
		end
	end

	return lowestPoint
end

local function rollRarity(pool)
	local roll = math.random() * 100
	local cumulative = 0

	for _, rarity in ipairs(pool) do
		cumulative += rarity.chance
		if roll <= cumulative then
			return rarity.name
		end
	end

	return pool[1].name
end

function SpawnService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._spawnAreas = Workspace:WaitForChild("SpawnAreas", 10)
	local assets = ServerStorage:WaitForChild("Assets", 10)
	self._animalsStorage = assets:WaitForChild("Animals", 10)
	self._animations = assets:WaitForChild("Animations", 10)
	self._workspaceAnimals = runtime.WorldFolders.Animals
	self._folderReferences = {}
	self._areaData = {}

	for _, rarity in ipairs(self._config.Animals.RarityOrder) do
		self._folderReferences[rarity] = self._animalsStorage:FindFirstChild(rarity)
	end

	for _, areaName in ipairs({"Common", "Uncommon", "Rare", "Legendary", "Mythical"}) do
		table.insert(self._areaData, {
			part = self._spawnAreas:FindFirstChild(areaName),
			pool = self._config.Animals.SpawnPools[areaName],
			count = 0,
		})
	end
end

function SpawnService:_getValidSpawnCFrame(areaPart: BasePart, animalModel: Instance): CFrame?
	local size = areaPart.Size
	local areaCFrame = areaPart.CFrame

	for _ = 1, 5 do
		local randomX = (math.random() - 0.5) * size.X
		local randomZ = (math.random() - 0.5) * size.Z
		local rayOrigin = (areaCFrame * CFrame.new(randomX, size.Y / 2, randomZ)).Position
		local rayDirection = Vector3.new(0, -size.Y - 100, 0)

		local rayParams = RaycastParams.new()
		-- THE FIX: We MUST include the animalModel here, otherwise the floor raycast hits the animal's own back and launches it into the sky!
		rayParams.FilterDescendantsInstances = {self._spawnAreas, self._workspaceAnimals, animalModel}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
		if result == nil then continue end

		local rotation = CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		local candidateCFrame = CFrame.new(result.Position) * rotation
		
		-- Place it at the raw floor position
		animalModel:PivotTo(candidateCFrame)

		-- Keep moving it up until the lowest visible point stops touching the floor
		for step = 1, 15 do
			local lowestPoint = getLowestVisiblePoint(animalModel)
			if not lowestPoint then break end

			-- Start 10 studs above the lowest point to ensure we are above the floor
			local floorRayOrigin = lowestPoint + Vector3.new(0, 10, 0)
			local floorRay = Workspace:Raycast(floorRayOrigin, Vector3.new(0, -20, 0), rayParams)
			
			if floorRay then
				local penetration = floorRay.Position.Y - lowestPoint.Y
				if penetration > 0.01 then
					-- It's inside the ground! Push the whole model up by the exact penetration amount
					animalModel:PivotTo(animalModel:GetPivot() + Vector3.new(0, penetration + 0.01, 0))
				else
					break -- It is completely clear of the floor!
				end
			else
				break
			end
		end

		-- Overlap Check using a Radius instead of a BoundingBox to ignore massive invisible hitboxes
		local overlapParams = OverlapParams.new()
		overlapParams.FilterDescendantsInstances = {self._workspaceAnimals}
		overlapParams.FilterType = Enum.RaycastFilterType.Include

		local overlappingParts = Workspace:GetPartBoundsInRadius(animalModel:GetPivot().Position, self._config.Spawning.ClearanceBuffer, overlapParams)
		
		if #overlappingParts == 0 then
			return animalModel:GetPivot()
		end
	end

	return nil
end

function SpawnService:_playIdleAnimation(animal: Instance)
	local animationController = animal:FindFirstChild("AnimationController")
	if animationController == nil then return end

	local animator = animationController:FindFirstChild("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = animationController
	end

	local animationFolder = nil
	for _, rarityFolder in ipairs(self._animations:GetChildren()) do
		local found = rarityFolder:FindFirstChild(animal.Name)
		if found then
			animationFolder = found
			break
		end
	end
	
	local idleAnimation = animationFolder and animationFolder:FindFirstChild("idle")
	if idleAnimation and idleAnimation:IsA("Animation") then
		local track = animator:LoadAnimation(idleAnimation)
		track:Play()
	end
end

function SpawnService:_spawnAnimal(data)
	if data.part == nil or data.count >= self._config.Spawning.MaxAnimalsPerArea then return end

	local rarityName = rollRarity(data.pool)
	local sourceFolder = self._folderReferences[rarityName]
	if sourceFolder == nil then return end

	local animalChoices = sourceFolder:GetChildren()
	if #animalChoices == 0 then return end

	local selectedTemplate = animalChoices[math.random(1, #animalChoices)]
	local newAnimal = selectedTemplate:Clone()
	
	data.count += 1
	newAnimal.Destroying:Connect(function()
		data.count = math.max(0, data.count - 1)
	end)

	-- 1. Put it in the Workspace high in the sky so the animation can play unseen
	newAnimal.Parent = Workspace
	newAnimal:PivotTo(CFrame.new(0, 100000, 0))

	-- 2. Play the animation
	self:_playIdleAnimation(newAnimal)

	-- 3. Wait exactly 0.05 seconds for the physical limbs to move into their animated pose
	task.wait(0.05)
	if not newAnimal.Parent then return end

	-- 4. Calculate the perfect floor alignment based on the new animated limb positions
	local spawnCFrame = self:_getValidSpawnCFrame(data.part, newAnimal)
	
	if spawnCFrame == nil then
		newAnimal:Destroy()
		return
	end

	-- 5. Move it to the perfect spot and parent it properly
	newAnimal:PivotTo(spawnCFrame)
	local targetFolder = self._workspaceAnimals:FindFirstChild(rarityName) or self._workspaceAnimals
	
	-- Malevolent Mutation Chance (20%) during Shrine event
	local eventService = self._runtime:GetService("EventService")
	if eventService and eventService._activeEvent == "Shrine" then
		if math.random() <= 0.2 then
			newAnimal:SetAttribute("Mutation", "Malevolent")
		end
	end

	newAnimal.Parent = targetFolder
	
	-- Setup visuals and tags if it has a mutation
	local animalService = self._runtime:GetService("AnimalService")
	if animalService then
		animalService:_applyMutationVisuals(newAnimal)
		animalService:_refreshAnimalTag(newAnimal)
	end
end

function SpawnService:_startSpawner(data)
	if data.part == nil then return end

	for _ = 1, self._config.Spawning.InitialSpawnCount do
		self:_spawnAnimal(data)
	end

	task.spawn(function()
		while true do
			task.wait(math.random(self._config.Spawning.SpawnTimeMin, self._config.Spawning.SpawnTimeMax))
			self:_spawnAnimal(data)
		end
	end)
end

function SpawnService:Start()
	for _, data in ipairs(self._areaData) do
		self:_startSpawner(data)
	end
end

return SpawnService