local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local StatCalculator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StatCalculator"))
local SafeZoneHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SafeZoneHelper"))

local AnimalService = {
	Name = "AnimalService",
	Priority = -40,
}

local function getPrimaryPart(target)
	if target == nil then
		return nil
	end

	if target:IsA("BasePart") then
		return target
	end

	if target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function isPartVisible(part: BasePart): boolean
	if part.Transparency < 0.95 then
		return true
	end

	-- Sometimes a fully transparent part is still visually represented by a mesh/decal.
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") or child:IsA("DataModelMesh") then
			return true
		end
	end

	return false
end

local function getLowestVisiblePoint(instance: Instance): Vector3?
	local lowestY = math.huge
	local lowestPoint = nil

	local parts = if instance:IsA("BasePart") then {instance} else instance:GetDescendants()

	for _, part in ipairs(parts) do
		if part:IsA("BasePart") and isPartVisible(part) then
			local cf = part.CFrame
			local size = part.Size

			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh and (mesh:IsA("SpecialMesh") or mesh:IsA("BlockMesh") or mesh:IsA("CylinderMesh")) then
				size = size * mesh.Scale
				cf = cf * CFrame.new(mesh.Offset)
			end

			local sx, sy, sz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
			local corners = {
				cf * Vector3.new( sx,  sy,  sz),
				cf * Vector3.new( sx,  sy, -sz),
				cf * Vector3.new( sx, -sy,  sz),
				cf * Vector3.new( sx, -sy, -sz),
				cf * Vector3.new(-sx,  sy,  sz),
				cf * Vector3.new(-sx,  sy, -sz),
				cf * Vector3.new(-sx, -sy,  sz),
				cf * Vector3.new(-sx, -sy, -sz),
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

local function getLowestAnyPoint(instance: Instance): Vector3?
	local lowestY = math.huge
	local lowestPoint = nil

	local parts = if instance:IsA("BasePart") then {instance} else instance:GetDescendants()

	for _, part in ipairs(parts) do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local size = part.Size

			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh and (mesh:IsA("SpecialMesh") or mesh:IsA("BlockMesh") or mesh:IsA("CylinderMesh")) then
				size = size * mesh.Scale
				cf = cf * CFrame.new(mesh.Offset)
			end

			local sx, sy, sz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
			local corners = {
				cf * Vector3.new( sx,  sy,  sz),
				cf * Vector3.new( sx,  sy, -sz),
				cf * Vector3.new( sx, -sy,  sz),
				cf * Vector3.new( sx, -sy, -sz),
				cf * Vector3.new(-sx,  sy,  sz),
				cf * Vector3.new(-sx,  sy, -sz),
				cf * Vector3.new(-sx, -sy,  sz),
				cf * Vector3.new(-sx, -sy, -sz),
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

local function raycastDownToVisiblePart(origin: Vector3, distance: number, ignored: {Instance}): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local ignoreList = table.clone(ignored or {})
	local direction = Vector3.new(0, -math.abs(distance), 0)

	for _ = 1, 24 do
		params.FilterDescendantsInstances = ignoreList
		local hit = Workspace:Raycast(origin, direction, params)
		if hit == nil then
			return nil
		end

		local hitPart = hit.Instance
		if hitPart == Workspace.Terrain then
			return hit
		end
		if hitPart:IsA("BasePart") and isPartVisible(hitPart) then
			return hit
		end

		table.insert(ignoreList, hitPart)
	end

	return nil
end

local function setNoCollision(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.Massless = true
		instance.Anchored = false
	end
	for _, d in ipairs(instance:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			d.Anchored = false
		end
	end
end

function AnimalService:_destroyCarriedVisualFromData(data)
	if type(data) ~= "table" then
		return
	end
	local model = data.carriedModel
	if model and model.Parent then
		model:Destroy()
	end
	data.carriedModel = nil

	local handle = data.carriedHandle
	if handle and handle.Parent then
		handle:Destroy()
	end
	data.carriedHandle = nil
end

function AnimalService:_destroyCarriedVisual(player: Player)
	local data = self._carriedAnimals[player]
	self:_destroyCarriedVisualFromData(data)
end

function AnimalService:_attachCarriedVisual(
	player: Player,
	animalName: string,
	animalRarity: string,
	savedAttributes: table,
	savedTags: table,
	sourceAnimal: Instance?
)
	self:_destroyCarriedVisual(player)

	local character = player.Character
	if character == nil then return end

	local arm = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if arm == nil or not arm:IsA("BasePart") then
		return
	end

	local resolvedRarity = animalRarity
	local visual = nil

	if sourceAnimal and sourceAnimal:IsA("Instance") then
		visual = sourceAnimal:Clone()
		local sourceRarity = sourceAnimal:GetAttribute("Rarity")
		if type(sourceRarity) == "string" and sourceRarity ~= "" then
			resolvedRarity = sourceRarity
		end

		-- Carry visuals should not include world interaction/despawn UI from drops.
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then
				descendant:Destroy()
			elseif descendant:IsA("BillboardGui") and descendant.Name == "DespawnTimerGui" then
				descendant:Destroy()
			end
		end
	else
		local template
		template, resolvedRarity = self:_findAnimalTemplateByName(animalName, animalRarity)
		if template == nil then
			return
		end
		visual = template:Clone()
	end

	-- Keep the real name so _playIdleAnimation can find the right animation folder.
	visual.Name = animalName
	visual:SetAttribute("IsCarriedVisual", true)
	for attributeName, attributeValue in pairs(savedAttributes or {}) do
		visual:SetAttribute(attributeName, attributeValue)
	end
	visual:SetAttribute("DropSpawnedAt", nil)
	visual:SetAttribute("DropAnimationOffset", nil)
	visual:SetAttribute("Rarity", tostring(resolvedRarity))

	-- applyCollectionTags is defined later in this module; call through self to avoid Luau forward-reference lints.
	AnimalService._applyCollectionTags(visual, savedTags)
	setNoCollision(visual)

	local primary = getPrimaryPart(visual)
	if primary == nil then
		visual:Destroy()
		return
	end
	if visual:IsA("Model") and visual.PrimaryPart == nil then
		visual.PrimaryPart = primary
	end

	-- Create a hidden Handle part to match tool behavior
	local handle = Instance.new("Part")
	handle.Name = "CarriedHandle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = character

	visual.Parent = character

	-- Position handle and visual relative to each other (180 degree rotation)
	if visual:IsA("Model") then
		handle.CFrame = visual:GetPivot() * CFrame.Angles(0, math.rad(180), 0)
	else
		handle.CFrame = primary.CFrame * CFrame.Angles(0, math.rad(180), 0)
	end

	local visualWeld = Instance.new("WeldConstraint")
	visualWeld.Part0 = handle
	visualWeld.Part1 = primary
	visualWeld.Parent = handle

	-- Weld handle to arm using same logic as FakeToolService
	local armWeld = Instance.new("Weld")
	armWeld.Name = "CarriedAnimalWeld"
	armWeld.Part0 = arm
	armWeld.Part1 = handle

	-- Match tool Grip logic
	armWeld.C1 = CFrame.new(-1.05, 0, 0) * CFrame.Angles(math.rad(-90), math.rad(180), 0)
	
	if arm.Name == "RightHand" then
		local attachment = arm:FindFirstChild("RightGripAttachment")
		armWeld.C0 = attachment and attachment:IsA("Attachment") and attachment.CFrame or CFrame.new(0, -0.5, 0)
	else
		armWeld.C0 = CFrame.new(0, -1, 0)
	end

	armWeld.Parent = handle

	-- Make it look alive.
	self:_applyMutationVisuals(visual)
	-- Some rigs need a short tick after parenting before animation plays reliably.
	task.defer(function()
		if visual.Parent then
			self:_playIdleAnimation(visual)
		end
	end)

	local data = self._carriedAnimals[player]
	if type(data) == "table" then
		data.carriedModel = visual
		data.carriedHandle = handle
	end
end

local function getInteractionPart(target)
	if target == nil then
		return nil
	end

	local vfxInstance = target:FindFirstChild("VfxInstance", true)
	if vfxInstance and vfxInstance:IsA("BasePart") then
		return vfxInstance
	end

	return getPrimaryPart(target)
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

local function getSiblingIndex(instance: Instance): number
	local parent = instance.Parent
	if parent == nil then
		return 1
	end

	local index = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == instance.Name and child.ClassName == instance.ClassName then
			index += 1
			if child == instance then
				return index
			end
		end
	end

	return 1
end

local function getRelativePath(root: Instance, target: Instance)
	local parts = {}
	local current = target

	while current and current ~= root do
		table.insert(parts, 1, {
			name = current.Name,
			className = current.ClassName,
			index = getSiblingIndex(current),
		})
		current = current.Parent
	end

	if current ~= root then
		return nil
	end

	return parts
end

local function resolvePlacementObjects(pad: Instance, placePartOverride: Instance?, placerOverride: Instance?)
	local placePart = nil
	local placerPrompt = nil

	if placePartOverride then
		if placePartOverride:IsA("BasePart") then
			placePart = placePartOverride
		elseif placePartOverride:IsA("Model") then
			placePart = placePartOverride.PrimaryPart or placePartOverride:FindFirstChildWhichIsA("BasePart", true)
		elseif placePartOverride:IsA("ProximityPrompt") then
			placerPrompt = placePartOverride
		end
	end

	if placerOverride then
		if placerOverride:IsA("ProximityPrompt") then
			placerPrompt = placerOverride
		elseif placerOverride:IsA("BasePart") then
			placePart = placePart or placerOverride
			placerPrompt = placerOverride:FindFirstChildWhichIsA("ProximityPrompt")
		elseif placerOverride:IsA("Model") then
			placePart = placePart or placerOverride.PrimaryPart or placerOverride:FindFirstChildWhichIsA("BasePart", true)
			placerPrompt = placerOverride:FindFirstChildWhichIsA("ProximityPrompt", true)
		end
	end

	local placerInstance = pad:FindFirstChild("Placer", true)
	if placerPrompt == nil then
		if placerInstance and placerInstance:IsA("ProximityPrompt") then
			placerPrompt = placerInstance
		elseif placerInstance and placerInstance:IsA("BasePart") then
			placerPrompt = placerInstance:FindFirstChildWhichIsA("ProximityPrompt")
		elseif placerInstance and placerInstance:IsA("Model") then
			placerPrompt = placerInstance:FindFirstChildWhichIsA("ProximityPrompt", true)
		end
	end

	if placerPrompt == nil then
		placerPrompt = pad:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	if placePart == nil then
		if placerPrompt and placerPrompt.Parent and placerPrompt.Parent:IsA("BasePart") then
			placePart = placerPrompt.Parent
		elseif placerInstance and placerInstance:IsA("BasePart") then
			placePart = placerInstance
		elseif placerInstance and placerInstance:IsA("Model") then
			placePart = placerInstance.PrimaryPart or placerInstance:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	return placePart, placerPrompt
end

local function applyCollectionTags(instance: Instance, tags)
	if type(tags) ~= "table" then
		return
	end

	local existing = {}
	for _, tagName in ipairs(CollectionService:GetTags(instance)) do
		existing[tagName] = true
	end

	for _, tagName in ipairs(tags) do
		if type(tagName) == "string" and not existing[tagName] then
			CollectionService:AddTag(instance, tagName)
			existing[tagName] = true
		end
	end
end

-- Expose for earlier carry-visual code without forward-reference warnings.
AnimalService._applyCollectionTags = applyCollectionTags

local function getRandomInRange(rangeData)
	if type(rangeData) ~= "table" then
		return 0
	end

	local minValue = tonumber(rangeData[1]) or 0
	local maxValue = tonumber(rangeData[2]) or minValue
	if minValue > maxValue then
		minValue, maxValue = maxValue, minValue
	end

	return math.random(math.floor(minValue), math.floor(maxValue))
end

local function rollWeightedLevel(levelingConfig)
	if type(levelingConfig) ~= "table" then
		return 1
	end

	local minLevel = math.max(1, math.floor(tonumber(levelingConfig.MinLevel) or 1))
	local maxLevel = math.max(minLevel, math.floor(tonumber(levelingConfig.MaxLevel) or minLevel))
	local weightPower = math.max(1, tonumber(levelingConfig.WeightPower) or 2)
	local levelRange = maxLevel - minLevel + 1

	-- random()^power biases toward low numbers when power > 1.
	local weightedRoll = math.random() ^ weightPower
	local levelOffset = math.floor(weightedRoll * levelRange)
	return math.clamp(minLevel + levelOffset, minLevel, maxLevel)
end

local function scaleStatByLevel(baseValue, level, alpha)
	local safeBaseValue = math.max(0, tonumber(baseValue) or 0)
	local safeLevel = math.max(1, tonumber(level) or 1)
	local safeAlpha = math.max(0, tonumber(alpha) or 1)
	return math.floor((safeBaseValue * (safeLevel ^ safeAlpha)) + 0.5)
end

local function getProjectedLevel(baseLevelValue, upgradeLevelValue)
	local baseLevel = math.max(1, math.floor(tonumber(baseLevelValue) or 1))
	local upgradeLevel = math.max(0, math.floor(tonumber(upgradeLevelValue) or 0))
	return baseLevel + upgradeLevel
end

function AnimalService:Init(runtime)
	self._config = runtime.Config
	self._runtime = runtime
	self._bases = Workspace:WaitForChild("Bases", 10)
	local assets = ServerStorage:WaitForChild("Assets", 10)
	self._animalsStorage = assets:WaitForChild("Animals", 10)
	self._toolsStorage = ReplicatedStorage:FindFirstChild("Tools")
	self._animations = assets:WaitForChild("Animations", 10)
	self._workspaceAnimals = runtime.WorldFolders.Animals
	self._dropsFolder = runtime.WorldFolders.Drops

	self._tagsFolder = assets:WaitForChild("AnimalsTags", 10)
	self._particlesFolder = assets:WaitForChild("Particles", 10)
	self._effects = runtime:GetService("ClientEffectsService")
	self._sounds = runtime:GetService("SoundService")
	self._playerCooldowns = {}
	self._healthBarHideTimers = {}
	self._initializedAnimals = setmetatable({}, {__mode = "k"})
	self._boundPlacers = setmetatable({}, {__mode = "k"})
	self._wildDespawnTimers = setmetatable({}, {__mode = "k"})
	self._stealPromptRemote = runtime.Remotes:GetStealPromptRemote()
	self._pendingSteals = {}
	self._dropDespawnTimers = setmetatable({}, {__mode = "k"})

	-- Carrying capture flow (safe-zone delivery)
	self._carryActionRemote = runtime.Remotes:GetCarryAnimalRemote()
	self._carriedAnimals = setmetatable({}, {__mode = "k"}) -- [player] = carriedPayload
	self._carrySafeZoneThreads = setmetatable({}, {__mode = "k"}) -- [player] = thread

	-- Ensure the announcement remote exists immediately for clients
	self._announcementRemote = runtime.Remotes:GetAnnouncementRemote()

	-- Replicate UI Template from ServerStorage to ReplicatedStorage
	task.spawn(function()
		local guiFolder = self._animalsStorage:FindFirstChild("Gui")
		if guiFolder then
			local template = guiFolder:FindFirstChild("Announcment") or guiFolder:FindFirstChild("Announcement")
			if template then
				local sharedAssets = ReplicatedStorage:FindFirstChild("Assets")
				if not sharedAssets then
					sharedAssets = Instance.new("Folder")
					sharedAssets.Name = "Assets"
					sharedAssets.Parent = ReplicatedStorage
				end
				local sharedGui = sharedAssets:FindFirstChild("Gui")
				if not sharedGui then
					sharedGui = Instance.new("Folder")
					sharedGui.Name = "Gui"
					sharedGui.Parent = sharedAssets
				end
				if not sharedGui:FindFirstChild(template.Name) then
					local clone = template:Clone()
					clone.Parent = sharedGui
				end
			end
		end
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local handledDecision = self:_processStealReceipt(receiptInfo)
		if handledDecision ~= nil then
			return handledDecision
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function AnimalService:_setPlacedAnimalPromptState(prompts, isActive)
	for _, prompt in ipairs(prompts or {}) do
		if prompt and prompt.Parent and prompt:IsA("ProximityPrompt") then
			prompt:SetAttribute("PromptActive", isActive)
			prompt.Enabled = isActive
		end
	end
end

function AnimalService:_clearPendingSteal(playerUserId, reactivatePrompts)
	local pending = self._pendingSteals[playerUserId]
	if pending == nil then
		return
	end

	if reactivatePrompts and pending.animal and pending.animal.Parent then
		self:_setPlacedAnimalPromptState(pending.prompts, true)
	end

	self._pendingSteals[playerUserId] = nil
end

function AnimalService:_findPendingStealByAnimal(animal)
	for playerUserId, pending in pairs(self._pendingSteals) do
		if pending.animal == animal then
			return playerUserId, pending
		end
	end

	return nil, nil
end

function AnimalService:_claimPlacedAnimal(player, clone, placePart, placer, prompts, equipToCharacter, isSteal, victimPlayer)
	if clone == nil or clone.Parent == nil then
		return false
	end

	self:_setPlacedAnimalPromptState(prompts, false)

	local worldPart = getPrimaryPart(clone)
	if worldPart then
		self._effects:EmitToPlayer(player, self._config.Effects.Names.AnimalPickup, {
			target = clone,
			player = player,
			style = "shrink",
		})
		
		if isSteal then
			self._sounds:PlayForPlayer(player, "AnimalStolen", { randomPitch = true })
			if victimPlayer and victimPlayer:IsA("Player") then
				self._sounds:PlayForPlayer(victimPlayer, "AnimalStolen", { randomPitch = true })
				self._runtime:GetService("NotificationService"):NotifyPlayer(victimPlayer, string.format("Your %s was stolen by %s!", clone.Name, player.Name), "Warning")
			end
		else
			self._sounds:PlayForPlayer(player, "AnimalPickedUpFromBase", { randomPitch = true })
		end
	end

	task.delay(0.22, function()
		if clone.Parent == nil then
			return
		end

		self:_giveAnimalTool(
			player,
			clone.Name,
			clone:GetAttribute("Rarity"),
			clone:GetAttributes(),
			CollectionService:GetTags(clone),
			equipToCharacter
		)
		clone:Destroy()

		local full = placePart:FindFirstChild("Full") or (placer and placer:FindFirstChild("Full"))
		if full and full:IsA("BoolValue") then
			full.Value = false
		end
		
		-- Refresh placers for the player who claimed it
		self:_togglePlayerPlacers(player, player:GetAttribute("HasAnimal") == true)
		
		-- If it was a steal, also refresh for the victim
		if isSteal and victimPlayer then
			self:_togglePlayerPlacers(victimPlayer, victimPlayer:GetAttribute("HasAnimal") == true)
		end
	end)

	return true
end

function AnimalService:_processStealReceipt(receiptInfo)
	local monetizationConfig = self._config and self._config.Monetization
	local stealProductId = monetizationConfig and monetizationConfig.StealAnimalProductId
	if receiptInfo.ProductId ~= stealProductId then
		return nil
	end

	local pending = self._pendingSteals[receiptInfo.PlayerId]
	if pending == nil then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local victimPlayer = if pending.ownerUserId then Players:GetPlayerByUserId(pending.ownerUserId) else nil

	self._pendingSteals[receiptInfo.PlayerId] = nil
	pending.completed = true

	local dataService = self._runtime and self._runtime:GetService("DataService")
	if dataService and type(dataService.RemovePlacedAnimalFromSavedBase) == "function" then
		dataService:RemovePlacedAnimalFromSavedBase(pending.ownerUserId, pending.padPath)
	end

	if pending.animal == nil or pending.animal.Parent == nil then
		local animalData = pending.animalData
		if type(animalData) == "table" then
			self:_giveAnimalTool(
				player,
				animalData.name,
				animalData.rarity,
				animalData.attributes or {},
				animalData.tags or {},
				true
			)

			self._sounds:PlayForPlayer(player, "AnimalStolen", { randomPitch = true })
			if victimPlayer and victimPlayer:IsA("Player") then
				self._sounds:PlayForPlayer(victimPlayer, "AnimalStolen", { randomPitch = true })
			end

			local full = pending.placePart and pending.placePart:FindFirstChild("Full")
			if full and full:IsA("BoolValue") then
				full.Value = false
			end
			if pending.placer then
				pending.placer.Enabled = false
			end
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	pending.animal:SetAttribute("PendingStealResolved", true)
	self:_claimPlacedAnimal(player, pending.animal, pending.placePart, pending.placer, pending.prompts, true, true, victimPlayer)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function AnimalService:_playIdleAnimation(animal: Instance)
	local animationController = animal:FindFirstChild("AnimationController") or animal:FindFirstChild("AnimationController", true)
	if animationController == nil then
		-- Fallback to Humanoid if it exists, or create an AnimationController
		animationController = animal:FindFirstChildOfClass("Humanoid")
		if not animationController then
			animationController = Instance.new("AnimationController")
			animationController.Name = "AnimationController"
			animationController.Parent = animal
		end
	end

	local animator = animationController:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = animationController
	end

	local targetAnimationName = animal.Name
	if animal:GetAttribute("IsLuckyBlock") then
		targetAnimationName = "LuckyBlock"
	end

	local animationFolder = nil
	for _, rarityFolder in ipairs(self._animations:GetChildren()) do
		local found = rarityFolder:FindFirstChild(targetAnimationName)
		if found then
			animationFolder = found
			break
		end
		
		if targetAnimationName == "LuckyBlock" and rarityFolder.Name == "LuckyBlock" then
			animationFolder = rarityFolder
			break
		end
	end

	local idleAnimation = animationFolder and animationFolder:FindFirstChild("idle")
	if idleAnimation == nil or not idleAnimation:IsA("Animation") then
		return
	end

	animal:SetAttribute("IdleAnimationId", idleAnimation.AnimationId)

	for _, playingTrack in ipairs(animator:GetPlayingAnimationTracks()) do
		local animation = playingTrack.Animation
		if animation and animation.AnimationId == idleAnimation.AnimationId then
			return
		end
	end

	local track = animator:LoadAnimation(idleAnimation)
	track.Looped = true
	track:Play()
end

function AnimalService:_findAnimalTemplateByName(animalName, rarityHint)
	if type(animalName) ~= "string" then
		return nil, nil
	end

	if type(rarityHint) == "string" then
		local rarityFolder = self._animalsStorage:FindFirstChild(rarityHint)
		local template = rarityFolder and rarityFolder:FindFirstChild(animalName)
		if template then
			return template, rarityHint
		end
	end

	for _, rarityFolder in ipairs(self._animalsStorage:GetChildren()) do
		local template = rarityFolder:FindFirstChild(animalName)
		if template then
			return template, rarityFolder.Name
		end
	end

	return nil, nil
end

function AnimalService:_findToolTemplate(toolName, classNameHint)
	if self._toolsStorage == nil or type(toolName) ~= "string" then
		return nil
	end

	local fallback = nil
	for _, descendant in ipairs(self._toolsStorage:GetDescendants()) do
		if descendant.Name ~= toolName then
			continue
		end
		if not (descendant:IsA("Tool") or descendant:IsA("Configuration")) then
			continue
		end
		if type(classNameHint) == "string" then
			if descendant.ClassName == classNameHint then
				return descendant
			end
			if fallback == nil then
				fallback = descendant
			end
		else
			return descendant
		end
	end

	return fallback
end

function AnimalService:_serializeTemplateToolChildren(item)
	if self._config == nil or self._config.Weapons == nil then
		return nil
	end
	if not CollectionService:HasTag(item, self._config.Weapons.Tag) then
		return nil
	end

	local damageValue = item:FindFirstChild("Damage")
	if damageValue and damageValue:IsA("NumberValue") then
		return {
			Damage = damageValue.Value,
		}
	end

	return nil
end

function AnimalService:_restoreTemplateToolChildren(item, savedChildren)
	if type(savedChildren) ~= "table" then
		return
	end

	local damage = tonumber(savedChildren.Damage)
	if damage == nil then
		return
	end

	local damageValue = item:FindFirstChild("Damage")
	if damageValue and not damageValue:IsA("NumberValue") then
		damageValue:Destroy()
		damageValue = nil
	end
	if damageValue == nil then
		damageValue = Instance.new("NumberValue")
		damageValue.Name = "Damage"
		damageValue.Parent = item
	end

	damageValue.Value = damage
end

function AnimalService:_getHealthColor(percent)
	if percent < 0.2 then
		return Color3.fromRGB(255, 40, 40)
	elseif percent < 0.5 then
		return Color3.fromRGB(255, 160, 20)
	end

	return Color3.fromRGB(55, 220, 85)
end

function AnimalService:_setBarTransparency(background, targetTransparency, duration)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local instant = duration <= 0

	for _, child in ipairs(background:GetChildren()) do
		local goals = {}
		if child:IsA("Frame") then
			goals.BackgroundTransparency = targetTransparency
		elseif child:IsA("TextLabel") then
			goals.TextTransparency = targetTransparency
			goals.TextStrokeTransparency = targetTransparency == 0 and 0.5 or 1
		elseif child:IsA("UIStroke") then
			goals.Transparency = targetTransparency
		end

		if instant then
			for property, value in pairs(goals) do
				child[property] = value
			end
		else
			if next(goals) then
				TweenService:Create(child, tweenInfo, goals):Play()
			end
		end

		local uiStroke = child:FindFirstChildOfClass("UIStroke")
		if uiStroke then
			if instant then
				uiStroke.Transparency = targetTransparency
			else
				TweenService:Create(uiStroke, tweenInfo, {Transparency = targetTransparency}):Play()
			end
		end
	end
end

function AnimalService:_createHealthBarGui(animal)
	local adornee = getPrimaryPart(animal)
	if adornee == nil then
		return nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBarGui"
	gui.Size = UDim2.new(5, 0, 0.9, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 50
	gui.Adornee = adornee
	gui.Parent = animal

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.new(0.5, 0, 0.5, 0)
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	background.BackgroundTransparency = 1
	background.BorderSizePixel = 0
	background.Parent = gui
	Instance.new("UICorner", background).CornerRadius = UDim.new(0.5, 0)

	local backgroundStroke = Instance.new("UIStroke")
	backgroundStroke.Color = Color3.new(0, 0, 0)
	backgroundStroke.Thickness = 2
	backgroundStroke.Transparency = 1
	backgroundStroke.Parent = background

	local trailingFill = Instance.new("Frame")
	trailingFill.Name = "TrailingFill"
	trailingFill.Size = UDim2.new(1, 0, 1, 0)
	trailingFill.BackgroundColor3 = Color3.fromRGB(255, 210, 40)
	trailingFill.BackgroundTransparency = 1
	trailingFill.BorderSizePixel = 0
	trailingFill.ZIndex = 2
	trailingFill.Parent = background
	Instance.new("UICorner", trailingFill).CornerRadius = UDim.new(0.5, 0)

	local flashFill = Instance.new("Frame")
	flashFill.Name = "FlashFill"
	flashFill.Size = UDim2.new(1, 0, 1, 0)
	flashFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flashFill.BackgroundTransparency = 1
	flashFill.BorderSizePixel = 0
	flashFill.ZIndex = 3
	flashFill.Parent = background
	Instance.new("UICorner", flashFill).CornerRadius = UDim.new(0.5, 0)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(55, 220, 85)
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.ZIndex = 4
	fill.Parent = background
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, 0, 0.45, 0)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 1
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 5
	gloss.Parent = background
	Instance.new("UICorner", gloss).CornerRadius = UDim.new(0.5, 0)

	local text = Instance.new("TextLabel")
	text.Name = "HealthText"
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextTransparency = 1
	text.TextStrokeTransparency = 1
	text.ZIndex = 6
	text.Parent = background

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.Parent = text

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.Parent = text

	return gui
end

function AnimalService:_createDespawnTimerGui(animal)
	local adornee = getPrimaryPart(animal)
	if adornee == nil then return nil end

	local gui = Instance.new("BillboardGui")
	gui.Name = "DespawnTimerGui"
	gui.Size = UDim2.new(2.5, 0, 2.5, 0)
	gui.StudsOffset = Vector3.new(0, 3.5, 0) -- Above the health bar
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	gui.Parent = animal

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "TimerLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 60, 60)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = frame

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0
	uiScale.Parent = frame

	return gui, uiScale
end

function AnimalService:_showHealthBar(animal)
	local gui = animal:FindFirstChild("HealthBarGui")
	local background = gui and gui:FindFirstChild("Background")
	if background == nil then
		return
	end

	local hideThread = self._healthBarHideTimers[animal]
	if hideThread then
		task.cancel(hideThread)
	end

	if background.BackgroundTransparency >= 0.9 then
		background.BackgroundTransparency = 0
		background.Size = UDim2.new(0.5, 0, 0.4, 0)
		self:_setBarTransparency(background, 0, 0)
		TweenService:Create(background, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0),
		}):Play()
	end

	self._healthBarHideTimers[animal] = task.delay(3, function()
		if animal.Parent == nil then
			return
		end

		local currentGui = animal:FindFirstChild("HealthBarGui")
		local currentBackground = currentGui and currentGui:FindFirstChild("Background")
		if currentBackground then
			TweenService:Create(currentBackground, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
				Size = UDim2.new(0.8, 0, 0.6, 0),
			}):Play()
			self:_setBarTransparency(currentBackground, 1, 0.4)
		end

		self._healthBarHideTimers[animal] = nil
	end)
end

function AnimalService:_updateHealthBar(animal, currentHealth, maxHealth, isDamage)
	local gui = animal:FindFirstChild("HealthBarGui") or self:_createHealthBarGui(animal)
	if gui == nil then
		return
	end

	local background = gui:WaitForChild("Background")
	local fill = background:WaitForChild("Fill")
	local trailingFill = background:WaitForChild("TrailingFill")
	local flashFill = background:WaitForChild("FlashFill")
	local text = background:WaitForChild("HealthText")
	local gloss = background:FindFirstChild("Gloss")

	-- Safety defaults
	currentHealth = tonumber(currentHealth) or 0
	maxHealth = tonumber(maxHealth) or 1

	local healthPercent = math.clamp(currentHealth / math.max(maxHealth, 1), 0, 1)
	local fillColor = self:_getHealthColor(healthPercent)

	if isDamage then
		self:_showHealthBar(animal)
		self:_setBarTransparency(background, 0, 0)
		if gloss and gloss:IsA("Frame") then
			gloss.BackgroundTransparency = 0.7
		end

		flashFill.Size = UDim2.new(math.min(healthPercent + 0.05, 1), 0, 1, 0)
		flashFill.BackgroundTransparency = 0.1
		TweenService:Create(flashFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(fill, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(healthPercent, 0, 1, 0),
			BackgroundColor3 = fillColor,
		}):Play()
		TweenService:Create(trailingFill, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = UDim2.new(healthPercent, 0, 1, 0),
		}):Play()

		TweenService:Create(background, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(1.12, 0, 1.35, 0),
		}):Play()
		task.delay(0.07, function()
			if background.Parent then
				TweenService:Create(background, TweenInfo.new(0.22, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
					Size = UDim2.new(1, 0, 1, 0),
				}):Play()
			end
		end)
	else
		fill.Size = UDim2.new(healthPercent, 0, 1, 0)
		trailingFill.Size = UDim2.new(healthPercent, 0, 1, 0)
		fill.BackgroundColor3 = fillColor
	end

	text.Text = NumberFormatter:Format(currentHealth, "Letters") .. " / " .. NumberFormatter:Format(maxHealth, "Letters")
end

function AnimalService:_refreshTagText(tagGui, animalName, rarity, cost, revenue, level)
	local costLabel = tagGui:FindFirstChild("Cost", true)
	local nameLabel = tagGui:FindFirstChild("Name", true)
	local revenueLabel = tagGui:FindFirstChild("Revenue", true)
	local levelLabel = tagGui:FindFirstChild("Level", true)
	local rarityLabel = tagGui:FindFirstChild("Rarity", true) or tagGui:FindFirstChild("RarityLabel", true)

	if costLabel and costLabel:IsA("TextLabel") then
		costLabel.Text = "$" .. NumberFormatter:Format(cost, "Letters")
		costLabel.LayoutOrder = 1
		costLabel.Visible = true
	end
	if levelLabel and levelLabel:IsA("TextLabel") then
		levelLabel.Text = "lvl " .. tostring(math.max(1, math.floor(tonumber(level) or 1)))
		levelLabel.LayoutOrder = 2
	end
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = animalName
		nameLabel.LayoutOrder = 3
	end
	if revenueLabel and revenueLabel:IsA("TextLabel") then
		revenueLabel.Text = "$" .. NumberFormatter:Format(revenue, "Letters") .. "/s"
		revenueLabel.LayoutOrder = 4
	end
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Text = tostring(rarity or "")
		rarityLabel.LayoutOrder = -75
		rarityLabel.Parent = tagGui -- Move to top level for sibling ordering with Gold/Mutations
	end
end

function AnimalService:_getAnimalDisplayLevel(animal)
	return getProjectedLevel(animal:GetAttribute("Level"), animal:GetAttribute("UpgradeLevel"))
end

function AnimalService:_recalculateAnimalStats(animal)
	local baseRevenue = animal:GetAttribute("BaseRevenue")
	if not baseRevenue then return end

	local level = animal:GetAttribute("Level") or 1
	local upgradeLevel = animal:GetAttribute("UpgradeLevel") or 0
	local mutations = {
		IsGold = animal:GetAttribute("IsGold") == true,
		IsMalevolent = animal:GetAttribute("IsMalevolent") == true,
		IsSoaked = animal:GetAttribute("IsSoaked") == true,
		IsTwistborn = animal:GetAttribute("IsTwistborn") == true,
		IsAlien = animal:GetAttribute("IsAlien") == true
	}

	local stats = StatCalculator.CalculateAnimalStats(baseRevenue, level, upgradeLevel, mutations, self._config)

	animal:SetAttribute("Revenue", stats.Revenue)
	animal:SetAttribute("Cost", stats.Cost)
	animal:SetAttribute("UpgradeCost", stats.UpgradeCost)

	-- Update existing upgrade prompt text if it's placed
	local upgradePart = animal:FindFirstChild("UpgradePart")
	local upgradePrompt = upgradePart and upgradePart:FindFirstChildOfClass("ProximityPrompt")
	if upgradePrompt then
		upgradePrompt.ObjectText = "-$" .. NumberFormatter:Format(stats.UpgradeCost, "Letters")
	end
end

function AnimalService:ApplyMalevolentMutation(animal)
	if animal:GetAttribute("IsMalevolent") then return end

	local maxHealth = animal:GetAttribute("MaxHealth")
	if not maxHealth then return end -- Not initialized yet

	animal:SetAttribute("IsMalevolent", true)

	self:_recalculateAnimalStats(animal)

	self:_applyMutationVisuals(animal)
	self:_refreshAnimalTag(animal)

	-- Update health bar (MaxHealth no longer changes, but we refresh UI)
	local health = animal:GetAttribute("Health")
	self:_updateHealthBar(animal, health, animal:GetAttribute("MaxHealth"), false)
end

function AnimalService:ApplySoakedMutation(animal)
	if animal:GetAttribute("IsSoaked") then return end

	local maxHealth = animal:GetAttribute("MaxHealth")
	if not maxHealth then return end -- Not initialized yet

	animal:SetAttribute("IsSoaked", true)

	self:_recalculateAnimalStats(animal)

	self:_applyMutationVisuals(animal)
	self:_refreshAnimalTag(animal)

	-- Update health bar (MaxHealth no longer changes, but we refresh UI)
	local health = animal:GetAttribute("Health")
	self:_updateHealthBar(animal, health, animal:GetAttribute("MaxHealth"), false)
end

function AnimalService:ApplyTwistbornMutation(animal)
	if animal:GetAttribute("IsTwistborn") then return end

	local maxHealth = animal:GetAttribute("MaxHealth")
	if not maxHealth then return end -- Not initialized yet

	animal:SetAttribute("IsTwistborn", true)

	self:_recalculateAnimalStats(animal)

	self:_applyMutationVisuals(animal)
	self:_refreshAnimalTag(animal)

	-- Update health bar
	local health = animal:GetAttribute("Health")
	self:_updateHealthBar(animal, health, animal:GetAttribute("MaxHealth"), false)
end

function AnimalService:ApplyAlienMutation(animal)
	if animal:GetAttribute("IsAlien") then return end

	local maxHealth = animal:GetAttribute("MaxHealth")
	if not maxHealth then return end -- Not initialized yet

	animal:SetAttribute("IsAlien", true)

	self:_recalculateAnimalStats(animal)

	self:_applyMutationVisuals(animal)
	self:_refreshAnimalTag(animal)

	-- Update health bar
	local health = animal:GetAttribute("Health")
	self:_updateHealthBar(animal, health, animal:GetAttribute("MaxHealth"), false)
end
function AnimalService:_applyMutationVisuals(animal)
	-- Try to find a valid VFX parent part. Essential for particles to appear.
	local vfxInstance = animal:FindFirstChild("VfxInstance", true) 
		or animal:FindFirstChild("VFX") 
		or animal:FindFirstChild("HumanoidRootPart")
		or (if animal:IsA("Model") then animal.PrimaryPart else nil)
		or animal:FindFirstChildWhichIsA("BasePart", true)
		
	if not vfxInstance then 
		warn("[AnimalService] Could not find VFX instance for", animal.Name)
		return 
	end

	local mutations = {
		Gold = animal:GetAttribute("IsGold") == true,
		Malevolent = animal:GetAttribute("IsMalevolent") == true,
		Soaked = animal:GetAttribute("IsSoaked") == true,
		Twistborn = animal:GetAttribute("IsTwistborn") == true,
		Alien = animal:GetAttribute("IsAlien") == true
	}

	-- Apply Particles for each active mutation
	if self._particlesFolder then
		local mutationsParticles = self._particlesFolder:FindFirstChild("Mutations")
		if mutationsParticles then
			for mutationName, isActive in pairs(mutations) do
				if isActive then
					-- Folder names in ServerStorage: "Gold", "Malevolent", "Soaked"
					local specificMutationFolder = mutationsParticles:FindFirstChild(mutationName)
					if specificMutationFolder then
						for _, pTemplate in ipairs(specificMutationFolder:GetChildren()) do
							-- Avoid double-applying particles
							local exists = false
							for _, existing in ipairs(vfxInstance:GetChildren()) do
								if (existing.Name == pTemplate.Name) and (existing.ClassName == pTemplate.ClassName) then
									exists = true
									break
								end
							end
							
							if not exists then
								local clone = pTemplate:Clone()
								clone.Parent = vfxInstance
								if clone:IsA("ParticleEmitter") then
									clone.Enabled = true
								end
							end
						end
					end
				end
			end
		end
	end

	-- Apply Visual Styles
	if mutations.Gold then
		for _, descendant in ipairs(animal:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Color = Color3.fromRGB(255, 215, 0)
				descendant.Material = Enum.Material.Glacier
				
				if descendant:IsA("MeshPart") then
					-- Delete SurfaceAppearance if it exists
					local surfaceAppearance = descendant:FindFirstChildWhichIsA("SurfaceAppearance")
					if surfaceAppearance then
						surfaceAppearance:Destroy()
					end
					
					-- Apply the specific gold texture ID if it's a MeshPart
					if descendant.TextureID ~= "" then
						descendant.TextureID = "rbxassetid://7750076"
					end
				end
			end
		end
	end
	
	-- Note: Soaked material/transparency removed per user request
	
	if mutations.Malevolent then
		-- Optional: Add specific part colors/materials for Malevolent if desired
	end
end

function AnimalService:_refreshAnimalTag(animal)
	local tagGui = animal:FindFirstChild("AnimalTag", true)
	if not tagGui or not tagGui:IsA("BillboardGui") then return end

	local rarity = animal:GetAttribute("Rarity")
	if type(rarity) ~= "string" or rarity == "" then
		return
	end
	local baseTag = self._tagsFolder:FindFirstChild(rarity)
	local baseSize = baseTag and baseTag.Size or UDim2.fromScale(4, 2.5)

	self:_refreshTagText(
		tagGui,
		animal.Name,
		rarity,
		animal:GetAttribute("Cost") or 0,
		animal:GetAttribute("Revenue") or 0,
		self:_getAnimalDisplayLevel(animal)
	)

	local mainFrame = tagGui:FindFirstChildWhichIsA("Frame", true)
	local mutationsFolder = self._tagsFolder:FindFirstChild("Mutations")
	
	local isGold = animal:GetAttribute("IsGold") == true
	local activeIconMutations = {}
	if animal:GetAttribute("IsMalevolent") then table.insert(activeIconMutations, "Malevolent") end
	if animal:GetAttribute("IsSoaked") then table.insert(activeIconMutations, "Soaked") end
	if animal:GetAttribute("IsTwistborn") then table.insert(activeIconMutations, "Twistborn") end
	if animal:GetAttribute("IsAlien") then table.insert(activeIconMutations, "Alien") end
	local hasMutations = #activeIconMutations > 0

	-- Calculate multiplier to avoid stretching
	local extraHeight = 0
	local rarityScale = 0.20
	local goldScale = 0.25
	local mutationsScale = 0.35
	
	extraHeight += rarityScale -- Rarity is always shown
	if isGold then extraHeight += goldScale end
	if hasMutations then extraHeight += mutationsScale end
	local multiplier = 1 + extraHeight

	tagGui.Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset, baseSize.Y.Scale * multiplier, baseSize.Y.Offset)
	
	-- Ensure a layout exists to stack components without stretching them
	local layout = tagGui:FindFirstChildWhichIsA("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 0)
		layout.Parent = tagGui
	end

	if mainFrame then
		mainFrame.Size = UDim2.fromScale(1, 1 / multiplier)
		mainFrame.LayoutOrder = 0
		mainFrame.Parent = tagGui
	end

	-- Handle Rarity size
	local rarityLabel = tagGui:FindFirstChild("Rarity", true) or tagGui:FindFirstChild("RarityLabel", true)
	if rarityLabel and rarityLabel:IsA("TextLabel") then
		rarityLabel.Size = UDim2.fromScale(1, rarityScale / multiplier)
		rarityLabel.Visible = true
	end

	-- Handle "Gold" specifically
	local goldLabel = tagGui:FindFirstChild("GoldLabel")
	if isGold then
		if not goldLabel then
			local goldLabelTemplate = mutationsFolder and mutationsFolder:FindFirstChild("Gold")
			if goldLabelTemplate then
				goldLabel = goldLabelTemplate:Clone()
				goldLabel.Name = "GoldLabel"
				goldLabel.LayoutOrder = -50
				goldLabel.Parent = tagGui
			end
		end
		if goldLabel then
			goldLabel.Visible = true
			goldLabel.Size = UDim2.fromScale(1, goldScale / multiplier)
		end
	elseif goldLabel then
		goldLabel.Visible = false
	end

	-- Handle actual Mutations (Icons)
	local mutationsFrame = tagGui:FindFirstChild("MutationsFrame")
	if hasMutations then
		if not mutationsFrame then
			local template = mutationsFolder and mutationsFolder:FindFirstChild("Mutations")
			if template then
				mutationsFrame = template:Clone()
				mutationsFrame.Name = "MutationsFrame"
				mutationsFrame.Parent = tagGui
			end
		end

		if mutationsFrame then
			mutationsFrame.Visible = true
			mutationsFrame.LayoutOrder = -100
			mutationsFrame.Size = UDim2.fromScale(1, mutationsScale / multiplier) 
			mutationsFrame.BackgroundTransparency = 1
			
			local grid = mutationsFrame:FindFirstChildWhichIsA("UIGridLayout")
			if grid then
				grid.CellSize = UDim2.fromScale(0.18, 0.85)
				grid.CellPadding = UDim2.fromScale(0.02, 0)
				grid.StartCorner = Enum.StartCorner.TopLeft
				grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
				grid.VerticalAlignment = Enum.VerticalAlignment.Center
			end

			local iconsFolder = mutationsFolder and mutationsFolder:FindFirstChild("Icons")
			if iconsFolder then
				for _, mutationName in ipairs(activeIconMutations) do
					local iconName = mutationName .. "Icon"
					if not mutationsFrame:FindFirstChild(iconName) then
						local iconTemplate = iconsFolder:FindFirstChild(mutationName)
						if iconTemplate then
							local icon = iconTemplate:Clone()
							icon.Name = iconName
							if icon:IsA("GuiObject") then
								icon.Size = UDim2.fromScale(1, 1)
							end
							icon.Parent = mutationsFrame
						end
					end
				end
			end
		end
	elseif mutationsFrame then
		mutationsFrame.Visible = false
	end
end

function AnimalService:_attachAnimalTag(animal, rarity)
	local baseTag = self._tagsFolder:FindFirstChild(rarity)
	if baseTag == nil then
		return
	end

	local tagClone = baseTag:Clone()
	tagClone.Name = "AnimalTag"
	tagClone.Parent = animal:FindFirstChild("VfxInstance") or animal
	
	-- Reset size to default to prevent cropping/massive expansion
	-- BillboardGui Size should ideally come from the template, but we ensure it's reasonable
	tagClone.Size = baseTag.Size 
	tagClone.StudsOffset = Vector3.new(0, 0, 0)
	tagClone.ClipsDescendants = false

	local mainFrame = tagClone:FindFirstChildWhichIsA("Frame", true)
	if mainFrame then
		mainFrame.Size = UDim2.fromScale(1, 1)
		mainFrame.Position = UDim2.fromScale(0.5, 0.5)
		mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		mainFrame.ClipsDescendants = false

		local innerLayout = mainFrame:FindFirstChildWhichIsA("UIListLayout")
		if not innerLayout then
			innerLayout = Instance.new("UIListLayout")
			innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
			innerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			innerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			innerLayout.Padding = UDim.new(0, 0)
			innerLayout.Parent = mainFrame
		end
	end

	self:_refreshAnimalTag(animal)
end

function AnimalService:_togglePlayerPlacers(player, isEquipping)
	local stats = player:FindFirstChild("Stats")
	local baseLevelVal = stats and stats:FindFirstChild("BaseLevel")
	local baseLevel = baseLevelVal and baseLevelVal.Value or 1

	for _, placer in ipairs(CollectionService:GetTagged("Placer")) do
		local base = getBaseFromDescendant(placer, self._bases)
		if base and base.Name == player.Name then
			local placePart = placer.Parent
			local pad = placePart and placePart.Parent
			
			-- Check if the pad is on a locked level
			local isLocked = false
			if pad then
				local levelFolder = pad.Parent and pad.Parent.Parent
				if levelFolder then
					local padLevel = tonumber(levelFolder.Name)
					if padLevel and padLevel > baseLevel then
						isLocked = true
					end
				end
			end

			local full = placePart and placePart:FindFirstChild("Full")
			if isLocked then
				placer.Enabled = false
			else
				placer.Enabled = isEquipping and not (full and full:IsA("BoolValue") and full.Value)
			end
		end
	end
end

function AnimalService:_buildAnimalTool(player, animalName, animalRarity, savedAttributes, savedTags)
	local template, resolvedRarity = self:_findAnimalTemplateByName(animalName, animalRarity)
	if template == nil then
		return nil
	end

	local visual = template:Clone()
	for attributeName, attributeValue in pairs(savedAttributes) do
		visual:SetAttribute(attributeName, attributeValue)
	end
	visual:SetAttribute("Rarity", tostring(resolvedRarity))

	local tool = Instance.new("Tool")
	tool.Name = animalName
	tool.CanBeDropped = false
	CollectionService:AddTag(tool, "Animal")
	applyCollectionTags(tool, savedTags)

	for attributeName, attributeValue in pairs(savedAttributes) do
		tool:SetAttribute(attributeName, attributeValue)
	end
	tool:SetAttribute("Rarity", tostring(resolvedRarity))

	local idleAnimationId = nil
	local animationFolder = nil
	
	local targetAnimationName = animalName
	if tool:GetAttribute("IsLuckyBlock") then
		targetAnimationName = "LuckyBlock"
	end
	
	for _, rarityFolder in ipairs(self._animations:GetChildren()) do
		local found = rarityFolder:FindFirstChild(targetAnimationName)
		if found then
			animationFolder = found
			break
		end
		if targetAnimationName == "LuckyBlock" and rarityFolder.Name == "LuckyBlock" then
			animationFolder = rarityFolder
			break
		end
	end

	local idleAnimation = animationFolder and animationFolder:FindFirstChild("idle")
	if idleAnimation and idleAnimation:IsA("Animation") and idleAnimation.AnimationId ~= "" then
		idleAnimationId = idleAnimation.AnimationId
	end
	if idleAnimationId then
		tool:SetAttribute("IdleAnimationId", idleAnimationId)
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.Anchored = false
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	visual.Name = animalName
	visual.Parent = tool
	if idleAnimationId then
		visual:SetAttribute("IdleAnimationId", idleAnimationId)
	end

	local visualPrimary = getPrimaryPart(visual)
	if visual:IsA("Model") then
		handle.CFrame = visual:GetPivot() * CFrame.Angles(0, math.rad(180), 0)
	elseif visualPrimary then
		handle.CFrame = visualPrimary.CFrame * CFrame.Angles(0, math.rad(180), 0)
	end

	if visual:IsA("BasePart") then
		visual.Anchored = false
		visual.CanCollide = false
		visual.Massless = true
	end

	for _, part in ipairs(visual:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end

	if visualPrimary then
		if visual:IsA("Model") and visual.PrimaryPart == nil then
			visual.PrimaryPart = visualPrimary
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = visualPrimary
		weld.Parent = handle
	end

	self:_attachAnimalTag(visual, animalRarity)
	self:_applyMutationVisuals(visual)
	self:_playIdleAnimation(visual)

	tool.Grip = CFrame.new(-1.05, 0, 0) * CFrame.Angles(math.rad(-90), math.rad(180), 0)

	tool.Equipped:Connect(function()
		-- While carrying a captured animal, the player is not allowed to equip anything.
		if player:GetAttribute("CarryingAnimal") then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:UnequipTools()
			end
			return
		end

		player:SetAttribute("HasAnimal", true)
		self:_togglePlayerPlacers(player, true)
		self:_playIdleAnimation(visual)
	end)

	tool.Unequipped:Connect(function()
		player:SetAttribute("HasAnimal", false)
		self:_togglePlayerPlacers(player, false)
	end)

	tool.Destroying:Connect(function()
		local equipped = player.Character ~= nil and tool.Parent == player.Character
		if equipped then
			player:SetAttribute("HasAnimal", false)
			self:_togglePlayerPlacers(player, false)
		end
	end)

	return tool
end

function AnimalService:_giveAnimalTool(player, animalName, animalRarity, savedAttributes, savedTags, equipToCharacter)
	local tool = self:_buildAnimalTool(player, animalName, animalRarity, savedAttributes, savedTags)
	if tool == nil then
		return nil
	end

	local backpack = player:WaitForChild("Backpack")
	tool.Parent = backpack

	if equipToCharacter == true and player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:EquipTool(tool)
		end
	end

	return tool
end

function AnimalService:_dropAnimal(animalName, animalRarity, animalPivot, savedAttributes, savedTags, dropOptions)
	local rarityFolder = self._animalsStorage:FindFirstChild(animalRarity)
	local template = rarityFolder and rarityFolder:FindFirstChild(animalName)
	if template == nil then
		return
	end

	local droppable = template:Clone()
	for attributeName, attributeValue in pairs(savedAttributes or {}) do
		droppable:SetAttribute(attributeName, attributeValue)
	end
	droppable:SetAttribute("DropSpawnedAt", Workspace:GetServerTimeNow())
	droppable:SetAttribute("DropAnimationOffset", math.random() * 10)

	if droppable:IsA("BasePart") then
		droppable.Anchored = true
		droppable.CanCollide = false
	end

	for _, part in ipairs(droppable:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	-- Robust Scaling: Store intended scale
	local baseScale = droppable:GetScale()
	droppable:SetAttribute("BaseScale", baseScale)

	droppable.Parent = self._dropsFolder

	-- If we already snapped to a floor hit point, do not add legacy Y-offset.
	local fromGroundHit = type(dropOptions) == "table" and dropOptions.fromGroundHit == true
	local finalPivot = fromGroundHit and animalPivot or (animalPivot * CFrame.new(0, 1.5, 0))
	droppable:PivotTo(finalPivot)

	-- Iterative snapping loop from SpawnService logic
	local ignore = {self._dropsFolder, droppable}
	
	-- Exclude Enemies from drop raycast
	for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
		table.insert(ignore, enemy)
	end

	if type(dropOptions) == "table" and type(dropOptions.ignoreInstances) == "table" then
		for _, instance in ipairs(dropOptions.ignoreInstances) do
			if typeof(instance) == "Instance" then
				table.insert(ignore, instance)
			end
		end
	end

	for step = 1, 15 do
		local lowestPoint = getLowestVisiblePoint(droppable)
		if not lowestPoint then break end

		local floorRayOrigin = lowestPoint + Vector3.new(0, 10, 0)
		local floorRay = raycastDownToVisiblePart(floorRayOrigin, 20, ignore)
		
		if floorRay then
			local penetration = floorRay.Position.Y - lowestPoint.Y
			if penetration > 0.01 then
				-- It's inside the ground! Push the whole model up by the exact penetration amount
				droppable:PivotTo(droppable:GetPivot() + Vector3.new(0, penetration + 0.01, 0))
			else
				break -- It is completely clear of the floor!
			end
		else
			break
		end
	end

	-- Preserve any CollectionService tags we were given (e.g. special weapon tags).
	if type(savedTags) == "table" then
		for _, tagName in ipairs(savedTags) do
			if type(tagName) == "string" then
				CollectionService:AddTag(droppable, tagName)
			end
		end
	end

	self:_attachAnimalTag(droppable, animalRarity)
	self:_applyMutationVisuals(droppable)
	task.defer(function()
		if droppable.Parent then
			self:_playIdleAnimation(droppable)
		end
	end)

	local promptParent = getInteractionPart(droppable)
	if promptParent == nil then
		return
	end

	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.ActionText = "Pick up"
	proximityPrompt.ObjectText = animalName
	proximityPrompt.HoldDuration = 0.35
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.MaxActivationDistance = 10
	proximityPrompt.Parent = promptParent

	local pickedUp = false
	
	-- Drop Despawn Timer (Fixed 30s)
	local despawnDelay = 30
	
	local function triggerDespawn()
		if pickedUp or droppable.Parent == nil then return end
		pickedUp = true
		proximityPrompt.Enabled = false
		
		self._effects:EmitToNearby(getPrimaryPart(droppable).Position, self._config.Effects.Names.AnimalDespawn, {
			animal = droppable
		})
		task.delay(0.35, function()
			if droppable.Parent then droppable:Destroy() end
		end)
	end

	self._dropDespawnTimers[droppable] = task.spawn(function()
		local startTime = os.clock()
		local countdownStart = math.max(1, despawnDelay - 5)
		
		-- Wait until it's time to show the countdown
		while (os.clock() - startTime) < countdownStart do
			if pickedUp or droppable.Parent == nil then return end
			task.wait(0.1)
		end
		
		local gui, uiScale = self:_createDespawnTimerGui(droppable)
		if not gui then return end
		local label = gui.Frame.TimerLabel
		
		TweenService:Create(uiScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		
		local remaining = math.ceil(despawnDelay - (os.clock() - startTime))
		while remaining > 0 do
			if pickedUp or droppable.Parent == nil then break end
			label.Text = tostring(remaining)
			
			uiScale.Scale = 1.3
			TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1}):Play()
			
			local redFactor = (6 - remaining) / 5
			label.TextColor3 = Color3.fromRGB(255, 60 * (1 - redFactor), 60 * (1 - redFactor))
			
			task.wait(1)
			remaining = math.ceil(despawnDelay - (os.clock() - startTime))
		end
		
		triggerDespawn()
	end)

	proximityPrompt.Triggered:Connect(function(player)
		if pickedUp then
			return
		end

		-- If the player is already carrying something (or hiding), ignore this pickup.
		if player:GetAttribute("CarryingAnimal") or player:GetAttribute("IsHiding") then
			return
		end

		pickedUp = true
		proximityPrompt.Enabled = false
		
		-- Cancel despawn timer if picked up
		if self._dropDespawnTimers[droppable] then
			task.cancel(self._dropDespawnTimers[droppable])
			self._dropDespawnTimers[droppable] = nil
		end

		local worldPart = getPrimaryPart(droppable)
		if worldPart then
			self._effects:EmitToPlayer(player, self._config.Effects.Names.AnimalPickup, {
				target = droppable,
				player = player,
				style = "flyToPlayer",
			})
			self._sounds:PlayForPlayer(player, "AnimalPickup", { randomPitch = true })
		end

		-- Switch to "carrying" state: player must walk to safe zone to receive the inventory tool.
		self:_startCarryingAnimal(
			player,
			animalName,
			animalRarity,
			droppable:GetAttributes(),
			CollectionService:GetTags(droppable),
			droppable
		)
		task.delay(0.22, function()
			if droppable.Parent == nil then
				return
			end
			droppable:Destroy()
		end)
	end)
end

function AnimalService:_cancelCarryWatcher(player: Player)
	local thread = self._carrySafeZoneThreads and self._carrySafeZoneThreads[player]
	if thread then
		pcall(function()
			if thread ~= coroutine.running() then
				task.cancel(thread)
			end
		end)
		self._carrySafeZoneThreads[player] = nil
	end
end

function AnimalService:_unequipForCarry(player: Player)
	-- Unequip standard Tools.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end

	-- Unequip FakeToolService configurations immediately (if available).
	local fakeToolService = self._runtime and self._runtime:GetService("FakeToolService")
	if fakeToolService and type(fakeToolService._unequipAll) == "function" then
		pcall(function()
			fakeToolService:_unequipAll(player)
		end)
	end

	-- Hard lock combat/placement while carrying.
	player:SetAttribute("IsArmed", false)
	player:SetAttribute("HasAnimal", false)
	self:_togglePlayerPlacers(player, false)
end

function AnimalService:_startCarryingAnimal(
	player: Player,
	animalName: string,
	animalRarity: string,
	savedAttributes: table,
	savedTags: table,
	sourceAnimal: Instance?
)
	-- Prevent double-pickup.
	if player:GetAttribute("CarryingAnimal") then
		return false
	end
	if player:GetAttribute("IsHiding") then
		return false
	end
	if type(animalName) ~= "string" or type(animalRarity) ~= "string" then
		return false
	end

	-- Capture last known position for later dropping.
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local lastPos = hrp and hrp.Position or Vector3.zero

	self._carriedAnimals[player] = {
		animalName = animalName,
		animalRarity = animalRarity,
		attributes = savedAttributes or {},
		tags = savedTags or {},
		lastPosition = lastPos,
		carriedModel = nil,
	}

	-- Signal the rest of the game to enter the "carrying" state:
	-- - server: unequip/lock combat
	-- - client: hide UI and show Drop button
	player:SetAttribute("CarryingAnimal", true)

	self:_unequipForCarry(player)
	self:_attachCarriedVisual(player, animalName, animalRarity, savedAttributes, savedTags, sourceAnimal)

	-- Start safe-zone watcher to grant the inventory tool.
	self:_cancelCarryWatcher(player)
	self._carrySafeZoneThreads[player] = task.spawn(function()
		while player.Parent ~= nil and player:GetAttribute("CarryingAnimal") == true do
			local char = player.Character
			local rootPart = char and char:FindFirstChild("HumanoidRootPart")

			if rootPart then
				local data = self._carriedAnimals[player]
				if data then
					data.lastPosition = rootPart.Position
				end

				if not player:GetAttribute("IsHiding") and SafeZoneHelper.isInSafeZone(rootPart.Position) then
					self:_grantCarriedAnimalToPlayer(player)
					return
				end
			end

			task.wait(0.2)
		end
	end)

	return true
end

function AnimalService:_grantCarriedAnimalToPlayer(player: Player)
	local data = self._carriedAnimals[player]
	-- Always clear carry state, even if payload is missing.
	player:SetAttribute("CarryingAnimal", false)
	self._carriedAnimals[player] = nil

	-- Remove carried visual immediately.
	self:_destroyCarriedVisualFromData(data)

	self:_cancelCarryWatcher(player)

	if type(data) == "table" and type(data.animalName) == "string" and type(data.animalRarity) == "string" then
		-- Grant into inventory (Backpack). Player can equip + place from there.
		local tool = self:_giveAnimalTool(player, data.animalName, data.animalRarity, data.attributes, data.tags, false)

		-- Auto-equip the newly granted tool.
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and tool and tool.Parent then
			pcall(function()
				humanoid:EquipTool(tool)
			end)
		end

		-- Ask client inventory UI to force it into hotbar slot 2.
		if self._carryActionRemote and tool then
			self._carryActionRemote:FireClient(player, "ForceHotbarSlot", { instance = tool, slot = 2 })
		end
		
		-- Play delivery effects
		self._effects:EmitToPlayer(player, self._config.Effects.Names.AnimalDelivered)
		self._sounds:PlayForPlayer(player, "AnimalPlaced", { randomPitch = true })
	end
end

function AnimalService:DropCarriedAnimal(player: Player)
	if player == nil or not player:IsA("Player") then
		return
	end
	if not player:GetAttribute("CarryingAnimal") then
		return
	end

	local data = self._carriedAnimals[player]

	-- Stop watcher first so we don't double-grant while dropping.
	self:_cancelCarryWatcher(player)

	player:SetAttribute("CarryingAnimal", false)
	self._carriedAnimals[player] = nil

	-- Remove carried visual before dropping.
	self:_destroyCarriedVisualFromData(data)

	if type(data) == "table" and type(data.animalName) == "string" and type(data.animalRarity) == "string" then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local pivot = hrp and hrp.CFrame or CFrame.new(data.lastPosition or Vector3.zero)

		-- Snap to ground: raycast down and place the drop at the hit position.
		local origin = (hrp and hrp.Position) or (data.lastPosition or Vector3.zero)
		local ignore = {self._dropsFolder}
		if char then table.insert(ignore, char) end
		
		-- Exclude Enemies
		for _, enemy in ipairs(CollectionService:GetTagged("Enemy")) do
			table.insert(ignore, enemy)
		end

		local hit = raycastDownToVisiblePart(origin + Vector3.new(0, 6, 0), 500, ignore)
		if hit then
			pivot = CFrame.new(hit.Position) * (pivot - pivot.Position)
		end

		self:_dropAnimal(
			data.animalName,
			data.animalRarity,
			pivot,
			data.attributes,
			data.tags,
			{
				fromGroundHit = hit ~= nil,
				ignoreInstances = ignore,
			}
		)
	end
end

function AnimalService:_setupPlacedAnimalOptions(clone, base, pad, placePart, placer)
	local upgradeLevel = math.max(0, math.floor(tonumber(clone:GetAttribute("UpgradeLevel")) or 0))
	local baseLevel = math.max(1, math.floor(tonumber(clone:GetAttribute("Level")) or 1))
	clone:SetAttribute("UpgradeLevel", upgradeLevel)
	clone:SetAttribute("Level", baseLevel)

	if clone:GetAttribute("BaseRevenue") == nil then
		local revenue = clone:GetAttribute("Revenue") or 1
		local alpha = tonumber(self._config.Animals.Leveling.Alpha) or 1
		local currentTotalLevel = baseLevel + upgradeLevel
		
		-- Factor out mutations if they exist to find the true BaseRevenue
		local multiplier = 1
		if clone:GetAttribute("IsGold") then multiplier *= 4 end
		if clone:GetAttribute("IsMalevolent") then multiplier *= 10 end
		if clone:GetAttribute("IsSoaked") then multiplier *= 1.5 end
		
		local rawRevenue = revenue / multiplier
		local baseRevenue = math.floor((rawRevenue / (currentTotalLevel ^ alpha)) + 0.5)
		clone:SetAttribute("BaseRevenue", math.max(1, baseRevenue))
	end

	self:_recalculateAnimalStats(clone)

	local primaryPart = getPrimaryPart(clone)
	if primaryPart == nil then
		return
	end

	local grabPart = Instance.new("Part")
	grabPart.Name = "GrabPart"
	grabPart.Size = Vector3.new(1.5, 1.5, 1.5)
	grabPart.Transparency = 1
	grabPart.CanCollide = false
	grabPart.Massless = true
	grabPart.CFrame = clone:GetPivot() * CFrame.new(0, 1.5, 0)
	grabPart.Parent = clone

	local grabWeld = Instance.new("WeldConstraint")
	grabWeld.Part0 = primaryPart
	grabWeld.Part1 = grabPart
	grabWeld.Parent = grabPart

	local grabPrompt = Instance.new("ProximityPrompt")
	grabPrompt.Name = "GrabPrompt"
	grabPrompt.ActionText = "Grab"
	grabPrompt.ObjectText = clone.Name
	grabPrompt.KeyboardKeyCode = Enum.KeyCode.F
	grabPrompt.HoldDuration = 0.5
	grabPrompt.MaxActivationDistance = 8
	grabPrompt:SetAttribute("VisibilityRole", "OwnerOnly")
	grabPrompt:SetAttribute("PromptActive", true)
	grabPrompt.Parent = grabPart

	local animalPrompts = {grabPrompt}

	if not clone:GetAttribute("IsLuckyBlock") then
		local upgradePart = Instance.new("Part")
		upgradePart.Name = "UpgradePart"
		upgradePart.Size = Vector3.new(1.5, 1.5, 1.5)
		upgradePart.Transparency = 1
		upgradePart.CanCollide = false
		upgradePart.Massless = true
		upgradePart.CFrame = clone:GetPivot() * CFrame.new(0, 5.5, 0)
		upgradePart.Parent = clone

		local upgradeWeld = Instance.new("WeldConstraint")
		upgradeWeld.Part0 = primaryPart
		upgradeWeld.Part1 = upgradePart
		upgradeWeld.Parent = upgradePart

		local upgradePrompt = Instance.new("ProximityPrompt")
		upgradePrompt.Name = "UpgradePrompt"
		upgradePrompt.ActionText = "Upgrade"
		upgradePrompt.ObjectText = "-$" .. NumberFormatter:Format(clone:GetAttribute("UpgradeCost") or 0, "Letters")
		upgradePrompt.KeyboardKeyCode = Enum.KeyCode.E
		upgradePrompt.HoldDuration = 0.5
		upgradePrompt.MaxActivationDistance = 8
		upgradePrompt:SetAttribute("VisibilityRole", "OwnerOnly")
		upgradePrompt:SetAttribute("PromptActive", true)
		upgradePrompt.Parent = upgradePart

		local stealPrompt = Instance.new("ProximityPrompt")
		stealPrompt.Name = "StealPrompt"
		stealPrompt.ActionText = "Steal"
		stealPrompt.ObjectText = clone.Name
		stealPrompt.HoldDuration = 0.5
		stealPrompt.MaxActivationDistance = 8
		stealPrompt:SetAttribute("VisibilityRole", "VisitorOnly")
		stealPrompt:SetAttribute("PromptActive", true)
		stealPrompt.Parent = grabPart

		table.insert(animalPrompts, upgradePrompt)
		table.insert(animalPrompts, stealPrompt)

		stealPrompt.Triggered:Connect(function(player)
			if player.Name == base.Name then
				return
			end
			if self._pendingSteals[player.UserId] ~= nil then
				return
			end
			if self:_findPendingStealByAnimal(clone) ~= nil then
				return
			end

			local ownerPlayer = Players:FindFirstChild(base.Name)

			self._pendingSteals[player.UserId] = {
				animal = clone,
				placePart = placePart,
				placer = placer,
				prompts = animalPrompts,
				ownerUserId = if ownerPlayer and ownerPlayer:IsA("Player") then ownerPlayer.UserId else nil,
				padPath = getRelativePath(base, pad),
				animalData = {
					name = clone.Name,
					rarity = clone:GetAttribute("Rarity"),
					attributes = clone:GetAttributes(),
					tags = CollectionService:GetTags(clone),
				},
			}
			self:_setPlacedAnimalPromptState(animalPrompts, false)
			self._stealPromptRemote:FireClient(player, "PromptPurchase", self._config.Monetization.StealAnimalProductId)
		end)

		upgradePrompt.Triggered:Connect(function(player)
			if player.Name ~= base.Name then
				return
			end

			local leaderstats = player:FindFirstChild("leaderstats")
			local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
			local currentUpgradeCost = clone:GetAttribute("UpgradeCost") or 0
			if bucks == nil or not bucks:IsA("IntValue") or bucks.Value < currentUpgradeCost then
				return
			end

			bucks.Value -= currentUpgradeCost

			local currentUpgradeLevel = clone:GetAttribute("UpgradeLevel") or 0
			clone:SetAttribute("UpgradeLevel", currentUpgradeLevel + 1)

			self:_recalculateAnimalStats(clone)
			self:_refreshAnimalTag(clone)

			local worldPart = getPrimaryPart(clone)
			if worldPart then
				self._effects:EmitToPlayer(player, self._config.Effects.Names.AnimalUpgrade, {
					animal = clone,
					position = worldPart.Position,
				})
				self._sounds:PlayForPlayer(player, "AnimalUpgrade", { randomPitch = true })
			end
		end)
	end

	grabPrompt.Triggered:Connect(function(player)
		if player.Name ~= base.Name then
			return
		end
		if self:_findPendingStealByAnimal(clone) ~= nil then
			return
		end

		self:_claimPlacedAnimal(player, clone, placePart, placer, animalPrompts)
	end)

	clone.Destroying:Connect(function()
		for playerUserId, pending in pairs(self._pendingSteals) do
			if pending.animal == clone then
				pending.animal = nil
				pending.prompts = nil
			end
		end
	end)
end

function AnimalService:_createPlacedAnimal(base, pad, animalData, placePartOverride, placerOverride)
	if type(animalData) ~= "table" then
		return nil
	end

	local rarity = animalData.rarity
	local name = animalData.name
	local attributes = animalData.attributes or {}
	if type(rarity) ~= "string" or type(name) ~= "string" then
		return nil
	end

	local template, resolvedRarity = self:_findAnimalTemplateByName(name, rarity)
	if template == nil then
		return nil
	end

	local placePart, placerPrompt = resolvePlacementObjects(pad, placePartOverride, placerOverride)

	if placePart == nil or placerPrompt == nil then
		return nil
	end

	local clone = template:Clone()
	
	for attributeName, attributeValue in pairs(attributes) do
		-- DO NOT carry over event session tags. 
		-- This ensures that if it's placed during an event, it will get NEW particles and a NEW mutation roll.
		if not string.find(attributeName, "ParticlesApplied") and attributeName ~= "MutationRollSession" then
			clone:SetAttribute(attributeName, attributeValue)
		end
	end
	clone:SetAttribute("Rarity", tostring(resolvedRarity))
	clone:SetAttribute("Placed", true)
	
	if not CollectionService:HasTag(clone, "Animal") then
		CollectionService:AddTag(clone, "Animal")
	end

	-- Pre-calculate and set MaxHealth early so EventService doesn't skip it
	local rarityStats = self._config.Animals.Stats[tostring(resolvedRarity)]
	if rarityStats then
		local baseLevel = math.max(1, math.floor(tonumber(clone:GetAttribute("Level")) or 1))
		local levelingConfig = self._config.Animals.Leveling or {}
		local alpha = tonumber(levelingConfig.Alpha) or 1
		local baseHealth = getRandomInRange(rarityStats.Health)
		local health = math.max(1, scaleStatByLevel(baseHealth, baseLevel, alpha))
		
		-- Mutation health multipliers removed

		clone:SetAttribute("MaxHealth", health)
		if clone:GetAttribute("Health") == nil then
			clone:SetAttribute("Health", health)
		end

		-- Ensure BaseRevenue is rolled if it doesn't exist (e.g. rolled from Lucky Block)
		if clone:GetAttribute("BaseRevenue") == nil then
			local baseRevenue = getRandomInRange(rarityStats.Revenue)
			clone:SetAttribute("BaseRevenue", baseRevenue)
		end
	end
	
	applyCollectionTags(clone, animalData.tags)

	-- Robust Scaling: Store the intended base scale for the client, but do NOT scale down here
	-- Scaling on server during replication causes 'tiny parts' on high-ping clients
	local baseScale = clone:GetScale()
	clone:SetAttribute("BaseScale", baseScale)

	clone:PivotTo(placePart.CFrame)
	local animalFolder = pad:FindFirstChild("Animal")
	if animalFolder == nil then
		animalFolder = Instance.new("Folder")
		animalFolder.Name = "Animal"
		animalFolder.Parent = pad
	end
	clone.Parent = animalFolder

	local targetPart = getPrimaryPart(clone)
	if targetPart then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = placePart
		weld.Part1 = targetPart
		weld.Parent = clone
	end

	self:_playIdleAnimation(clone)

	if not clone:GetAttribute("IsLuckyBlock") then
		self:_attachAnimalTag(clone, resolvedRarity)
		self:_applyMutationVisuals(clone)
		self:_refreshAnimalTag(clone)
	end

	-- Apply active event effects/mutations immediately if an event is running
	local eventService = self._runtime:GetService("EventService")
	if eventService then
		eventService:ApplyActiveEventToAnimal(clone)
	end

	local full = placePart:FindFirstChild("Full") or (placerPrompt and placerPrompt:FindFirstChild("Full"))
	if full and full:IsA("BoolValue") then
		full.Value = true
	end
	placerPrompt.Enabled = false
	self:_setupPlacedAnimalOptions(clone, base, pad, placePart, placerPrompt)

	if targetPart then
		self._effects:EmitToNearby(targetPart.Position, self._config.Effects.Names.AnimalSpawn, {
			animal = clone
		})

		self._sounds:PlayOnServer("AnimalPlaced", {
			randomPitch = true,
			parent = targetPart,
		})
	end

	return clone
end

function AnimalService:SerializePlacedAnimal(animal)
	if animal == nil or animal.Parent == nil then
		return nil
	end

	local rarity = animal:GetAttribute("Rarity")
	if typeof(rarity) ~= "string" then
		return nil
	end

	return {
		name = animal.Name,
		rarity = rarity,
		attributes = animal:GetAttributes(),
		tags = CollectionService:GetTags(animal),
	}
end

function AnimalService:RestorePlacedAnimal(base, pad, animalData)
	return self:_createPlacedAnimal(base, pad, animalData)
end

function AnimalService:SerializeInventoryItem(item)
	local _, rarity = self:_findAnimalTemplateByName(item.Name, item:GetAttribute("Rarity"))
	if rarity then
		return {
			kind = "AnimalTool",
			name = item.Name,
			rarity = rarity,
			attributes = item:GetAttributes(),
			tags = CollectionService:GetTags(item),
		}
	end

	if self:_findToolTemplate(item.Name) then
		return {
			kind = "TemplateTool",
			name = item.Name,
			className = item.ClassName,
			savedChildren = self:_serializeTemplateToolChildren(item),
		}
	end

	return nil
end

function AnimalService:RestoreInventoryItem(player: Player, itemData)
	if type(itemData) ~= "table" then
		return nil
	end

	local backpack = player:WaitForChild("Backpack")
	local wantsEquipped = itemData.location == "Character"

	if itemData.kind == "AnimalTool" then
		local tool = self:_buildAnimalTool(player, itemData.name, itemData.rarity, itemData.attributes or {}, itemData.tags or {})
		if tool then
			tool.Parent = backpack
			if wantsEquipped and player.Character then
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:EquipTool(tool)
				end
			end
			return true
		end
	end

	if itemData.kind == "TemplateTool" then
		local template = self:_findToolTemplate(itemData.name, itemData.className)
		if template then
			local clone = template:Clone()
			self:_restoreTemplateToolChildren(clone, itemData.savedChildren)
			clone.Parent = backpack
			local fakeToolService = self._runtime and self._runtime:GetService("FakeToolService")
			if clone:IsA("Configuration") then
				if fakeToolService and type(fakeToolService.BindConfig) == "function" then
					fakeToolService:BindConfig(player, clone)
				end
				if wantsEquipped and fakeToolService and type(fakeToolService.EquipConfig) == "function" then
					fakeToolService:EquipConfig(player, clone)
				end
			elseif wantsEquipped and player.Character then
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:EquipTool(clone)
				end
			end
			return true
		end
	end

	if itemData.kind == "InstanceTree" and type(itemData.tree) == "table" and type(itemData.tree.name) == "string" then
		local legacyAnimal = {
			kind = "AnimalTool",
			name = itemData.tree.name,
			rarity = itemData.rarity,
			attributes = itemData.attributes or {},
			tags = itemData.tags or {},
		}
		if self:RestoreInventoryItem(player, legacyAnimal) then
			return true
		end

		local legacyTemplate = self:_findToolTemplate(itemData.tree.name, itemData.tree.className)
		if legacyTemplate then
			local clone = legacyTemplate:Clone()
			self:_restoreTemplateToolChildren(clone, itemData.savedChildren)
			clone.Parent = backpack
			local fakeToolService = self._runtime and self._runtime:GetService("FakeToolService")
			if clone:IsA("Configuration") then
				if fakeToolService and type(fakeToolService.BindConfig) == "function" then
					fakeToolService:BindConfig(player, clone)
				end
				if wantsEquipped and fakeToolService and type(fakeToolService.EquipConfig) == "function" then
					fakeToolService:EquipConfig(player, clone)
				end
			elseif wantsEquipped and player.Character then
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:EquipTool(clone)
				end
			end
			return true
		end
	end

	return nil
end

function AnimalService:_bindPlacer(placer)
	if self._boundPlacers[placer] then
		return
	end
	self._boundPlacers[placer] = true
	placer.Enabled = false

	local placePart = placer.Parent
	local full = placePart and placePart:FindFirstChild("Full")

	placer.Triggered:Connect(function(player)
		local base = getBaseFromDescendant(placer, self._bases)
		if base == nil or base.Name ~= player.Name or player:GetAttribute("IsHiding") then
			return
		end
		if full and full:IsA("BoolValue") and full.Value then
			return
		end
		
		-- Check if pad is on a locked level
		local pad = placePart and placePart.Parent
		local levelFolder = pad and pad.Parent and pad.Parent.Parent
		if levelFolder then
			local padLevel = tonumber(levelFolder.Name)
			local stats = player:FindFirstChild("Stats")
			local baseLevelVal = stats and stats:FindFirstChild("BaseLevel")
			local baseLevel = baseLevelVal and baseLevelVal.Value or 1
			if padLevel and padLevel > baseLevel then
				return
			end
		end

		local character = player.Character
		if character == nil then
			return
		end

		local animalTool = character:FindFirstChildWhichIsA("Tool")
		if animalTool == nil or not CollectionService:HasTag(animalTool, "Animal") then
			return
		end

		local visual = animalTool:FindFirstChild(animalTool.Name)
		if visual == nil then
			return
		end

		local clone = visual:Clone()
		for attributeName, attributeValue in pairs(animalTool:GetAttributes()) do
			-- DO NOT carry over event particle session tags to the base animal
			-- This ensures that if it's placed during an event, it will get NEW particles
			if not string.find(attributeName, "ParticlesApplied") then
				clone:SetAttribute(attributeName, attributeValue)
			end
		end
		for _, tagName in ipairs(CollectionService:GetTags(animalTool)) do
			CollectionService:AddTag(clone, tagName)
		end

		animalTool:Destroy()
		player:SetAttribute("HasAnimal", false)
		self:_togglePlayerPlacers(player, false)

		local pad = placePart.Parent
		self:_createPlacedAnimal(base, pad, {
			name = clone.Name,
			rarity = clone:GetAttribute("Rarity"),
			attributes = clone:GetAttributes(),
		}, placePart, placer)
		clone:Destroy()
	end)
end

function AnimalService:_setupWildAnimal(animal, isManual)
	if self._initializedAnimals[animal] then
		return
	end

	-- For admin-spawned animals, we might call this before they are fully parented 
	-- or they might be parented slightly differently.
	local hasMutation = animal:GetAttribute("Mutation") ~= nil
	if not isManual and not hasMutation then
		if animal.Parent == nil or animal.Parent.Parent ~= self._workspaceAnimals then
			return
		end
	end

	if not CollectionService:HasTag(animal, "Animal") then
		CollectionService:AddTag(animal, "Animal")
	end

	local rarity = animal:GetAttribute("Rarity") or (animal.Parent and animal.Parent.Name)
	if not rarity then return end

	local rarityStats = self._config.Animals.Stats[rarity]
	if rarityStats == nil then
		return
	end

	self._initializedAnimals[animal] = true
	animal:SetAttribute("Rarity", rarity)
	animal:SetAttribute("Placed", false)

	local levelingConfig = self._config.Animals.Leveling or {}
	local level = animal:GetAttribute("Level") or rollWeightedLevel(levelingConfig)
	local alpha = tonumber(levelingConfig.Alpha) or 1

	local baseHealth = getRandomInRange(rarityStats.Health)
	local baseRevenue = getRandomInRange(rarityStats.Revenue)

	local health = math.max(1, scaleStatByLevel(baseHealth, level, alpha))

	local mutation = animal:GetAttribute("Mutation")
	if not mutation then
		local mutationsConfig = self._config.Animals.Mutations or {}
		local goldChance = mutationsConfig.Gold or 0

		if math.random() <= goldChance then
			animal:SetAttribute("IsGold", true)
		end
	else
		-- Handle legacy or pre-set Mutation attribute
		if mutation == "Gold" then animal:SetAttribute("IsGold", true)
		elseif mutation == "Malevolent" then animal:SetAttribute("IsMalevolent", true)
		elseif mutation == "Soaked" then animal:SetAttribute("IsSoaked", true)
		end
	end

	animal:SetAttribute("Level", level)
	animal:SetAttribute("MaxHealth", health)
	animal:SetAttribute("Health", health)
	animal:SetAttribute("BaseRevenue", baseRevenue)
	
	self:_recalculateAnimalStats(animal)

	if rarity == "Devine" then
		if self._announcementRemote then
			self._announcementRemote:FireAllClients("DivineSpawn")
		end
	end

	self:_attachAnimalTag(animal, rarity)
	self:_applyMutationVisuals(animal)
	self:_updateHealthBar(animal, health, health, false)

	-- Spawn Animation
	self._effects:EmitToNearby(getPrimaryPart(animal).Position, self._config.Effects.Names.AnimalSpawn, {
		animal = animal
	})

	-- Despawn Timer
	local despawnDelay = math.random(self._config.Spawning.WildDespawnTimeMin, self._config.Spawning.WildDespawnTimeMax)
	
	local function triggerDespawn()
		if animal.Parent == nil then return end
		self._effects:EmitToNearby(getPrimaryPart(animal).Position, self._config.Effects.Names.AnimalDespawn, {
			animal = animal
		})
		task.delay(0.35, function()
			if animal.Parent then animal:Destroy() end
		end)
	end

	self._wildDespawnTimers[animal] = task.delay(despawnDelay - 10, function()
		if animal.Parent == nil then triggerDespawn() return end
		
		local gui, uiScale = self:_createDespawnTimerGui(animal)
		local label = gui.Frame.TimerLabel
		
		-- Pop in timer
		TweenService:Create(uiScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		
		for i = 10, 1, -1 do
			if animal.Parent == nil then break end
			label.Text = tostring(i)
			
			-- Pulse effect
			uiScale.Scale = 1.3
			TweenService:Create(uiScale, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1}):Play()
			
			-- Color shift to more intense red
			local redFactor = (11 - i) / 10
			label.TextColor3 = Color3.fromRGB(255, 60 * (1 - redFactor), 60 * (1 - redFactor))
			
			task.wait(1)
		end
		
		triggerDespawn()
	end)

	local interactionPart = getInteractionPart(animal)
	if interactionPart == nil then
		return
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 8
	clickDetector.Parent = interactionPart

	clickDetector.MouseClick:Connect(function(player)
		if not player:GetAttribute("IsArmed")
			or player:GetAttribute("IsHiding")
			or player:GetAttribute("CarryingAnimal") then
			return
		end
		
		local areaService = self._runtime:GetService("AreaService")
		if areaService then
			local animalArea = areaService:GetAreaFromPosition(animal:GetPivot().Position)
			if not areaService:HasAreaUnlocked(player, animalArea) then
				return
			end
		end

		local now = os.clock()
		if self._playerCooldowns[player] and (now - self._playerCooldowns[player]) < self._config.Combat.AttackCooldown then
			return
		end
		self._playerCooldowns[player] = now
		
		local damage = player:GetAttribute("Damage") or self._config.Weapons.DefaultDamage
		local isImmune = false

		-- Check for allowed rarities based on equipped sword
		local stats = player:FindFirstChild("Stats")
		local swords = stats and stats:FindFirstChild("Swords")
		local currentSwordVal = swords and swords:FindFirstChild("CurrentSword")
		local swordName = currentSwordVal and currentSwordVal.Value or "Default"
		
		local swordUpgradeConfig = self._config.Upgrades.Swords[swordName] or self._config.Upgrades.Swords["Default"]
		if swordUpgradeConfig and swordUpgradeConfig.AllowedRarities then
			local allowed = false
			for _, allowedRarity in ipairs(swordUpgradeConfig.AllowedRarities) do
				if allowedRarity == rarity then
					allowed = true
					break
				end
			end
			if not allowed then
				isImmune = true
				damage = 0
			end
		end

		local maxHealth = animal:GetAttribute("MaxHealth") or 1
		local newHealth = math.max(0, (animal:GetAttribute("Health") or maxHealth) - damage)
		
		if not isImmune then
			animal:SetAttribute("Health", newHealth)
		end

		local worldPart = getPrimaryPart(animal)
		if worldPart then
			self._effects:EmitToPlayer(player, self._config.Effects.Names.AnimalHit, {
				animal = animal,
				position = worldPart.Position,
				damage = if isImmune then "IMMUNE" else damage,
				maxHealth = maxHealth,
			})
		end
		
		if not isImmune then
			self:_updateHealthBar(animal, newHealth, maxHealth, true)
		end

		if not isImmune and newHealth <= 0 then
			self:_handleAnimalDeath(animal, player)
		else
			local worldPart = getPrimaryPart(animal)
			self._sounds:PlayNearby(worldPart.Position, "AnimalHit", {
				randomPitch = true,
				parent = worldPart,
			})
		end
	end)

	animal.Destroying:Connect(function()
		self._initializedAnimals[animal] = nil
		self._healthBarHideTimers[animal] = nil
	end)
end

function AnimalService:_handleAnimalDeath(animal, player)
	if animal.Parent == nil or animal:GetAttribute("IsDead") then return end
	animal:SetAttribute("IsDead", true)
	
	local rarity = animal:GetAttribute("Rarity")
	if not rarity then
		rarity = animal.Parent and animal.Parent.Name
		if rarity == "Animals" then rarity = "Common" end -- Fallback
	end
	local savedAttributes = animal:GetAttributes()
	local worldPart = getPrimaryPart(animal)
	
	-- Cancel despawn timer if it's dead
	if self._wildDespawnTimers[animal] then
		task.cancel(self._wildDespawnTimers[animal])
		self._wildDespawnTimers[animal] = nil
	end

	if worldPart then
		if player then
			self._effects:EmitToPlayer(player, self._config.Effects.Names.AnimalDeath, {
				animal = animal,
				position = worldPart.Position,
			})
		else
			self._effects:EmitToNearby(worldPart.Position, self._config.Effects.Names.AnimalDeath, {
				animal = animal,
				position = worldPart.Position,
			})
		end
		self._sounds:PlayOnServer("AnimalDeath")
		
		local animalSounds = game:GetService("ServerStorage"):FindFirstChild("Assets") and game:GetService("ServerStorage").Assets:FindFirstChild("AnimalSounds")
		if animalSounds then
			local soundName = animal.Name
			if animal:GetAttribute("IsLuckyBlock") then
				soundName = "Lucky Block"
			end

			local specificSound = animalSounds:FindFirstChild(soundName)
			if specificSound and specificSound:IsA("Sound") then
				local soundPart = Instance.new("Part")
				soundPart.Name = "DeathSoundPart_" .. soundName
				soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
				soundPart.Transparency = 1
				soundPart.CanCollide = false
				soundPart.Anchored = true
				soundPart.CFrame = worldPart.CFrame
				soundPart.Parent = game:GetService("Workspace")
				
				local soundClone = specificSound:Clone()
				soundClone.Parent = soundPart
				soundClone:Play()
				
				game:GetService("Debris"):AddItem(soundPart, math.max(2, soundClone.TimeLength + 0.5))
			end
		end
	end

	task.delay(0.1, function()
		if animal.Parent then
			self:_dropAnimal(animal.Name, rarity, animal:GetPivot(), savedAttributes, CollectionService:GetTags(animal))
			animal:Destroy()
		end
	end)
end

function AnimalService:Start()
	self._stealPromptRemote.OnServerEvent:Connect(function(player, action, productId, didPurchase)
		if action ~= "PromptFinished" then
			return
		end
		if productId ~= self._config.Monetization.StealAnimalProductId then
			return
		end
		if didPurchase == true then
			return
		end

		self:_clearPendingSteal(player.UserId, true)
	end)

	-- Drop button for the safe-zone delivery mechanic.
	self._carryActionRemote.OnServerEvent:Connect(function(player, action)
		if action == "Drop" then
			self:DropCarriedAnimal(player)
		end
	end)

	-- If the player dies / respawns while carrying, drop the carried animal.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			if player:GetAttribute("CarryingAnimal") then
				self:DropCarriedAnimal(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			if player:GetAttribute("CarryingAnimal") then
				self:DropCarriedAnimal(player)
			end
		end)
	end

	for _, placer in ipairs(CollectionService:GetTagged("Placer")) do
		self:_bindPlacer(placer)
	end

	CollectionService:GetInstanceAddedSignal("Placer"):Connect(function(placer)
		self:_bindPlacer(placer)
	end)

	for _, rarityFolder in ipairs(self._workspaceAnimals:GetChildren()) do
		for _, animal in ipairs(rarityFolder:GetChildren()) do
			self:_setupWildAnimal(animal)
		end
	end

	self._workspaceAnimals.DescendantAdded:Connect(function(instance)
		self:_setupWildAnimal(instance)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._playerCooldowns[player] = nil
		self:_clearPendingSteal(player.UserId, true)

		-- Clean up carrying state so watcher threads don't linger.
		if player:GetAttribute("CarryingAnimal") then
			self:_cancelCarryWatcher(player)
			self._carriedAnimals[player] = nil
			player:SetAttribute("CarryingAnimal", false)
		end
	end)
end

return AnimalService
