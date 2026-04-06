local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local BaseService = {
	Name = "BaseService",
	Priority = -50,
}

local EMPTY_COLLECTOR_COLOR = Color3.new(0.294118, 0.592157, 0.294118)
local FULL_COLLECTOR_COLOR = Color3.new(0.215686, 1, 0)
local PAD_OUTLINE_NAME = "RarityOutline"
local PAD_RARITY_VISUALS = {
	Common = {Color = Color3.fromRGB(200, 200, 200), Thickness = 0.04},
	Uncommon = {Color = Color3.fromRGB(85, 255, 127), Thickness = 0.05},
	Rare = {Color = Color3.fromRGB(85, 170, 255), Thickness = 0.06},
	Legendary = {Color = Color3.fromRGB(255, 215, 0), Thickness = 0.07},
	Mythical = {Color = Color3.fromRGB(255, 85, 127), Thickness = 0.08},
	Devine = {Color = Color3.fromRGB(170, 0, 255), Thickness = 0.1},
}

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

local function findByLegacyRelativePath(root: Instance, path: string): Instance?
	local current = root
	for segment in string.gmatch(path, "[^/]+") do
		current = current and current:FindFirstChild(segment)
		if current == nil then
			return nil
		end
	end

	return current
end

local function findByRelativePath(root: Instance, path): Instance?
	if type(path) == "string" then
		return findByLegacyRelativePath(root, path)
	end

	if type(path) ~= "table" then
		return nil
	end

	local current = root
	for _, segment in ipairs(path) do
		if type(segment) ~= "table" or type(segment.name) ~= "string" then
			return nil
		end

		local targetIndex = tonumber(segment.index) or 1
		local targetClassName = segment.className
		local currentIndex = 0
		local found = nil

		for _, child in ipairs(current:GetChildren()) do
			if child.Name == segment.name and (type(targetClassName) ~= "string" or child.ClassName == targetClassName) then
				currentIndex += 1
				if currentIndex == targetIndex then
					found = child
					break
				end
			end
		end

		if found == nil then
			return nil
		end

		current = found
	end

	return current
end

local function getBaseFromDescendant(descendant: Instance, bases: Instance): Model | Folder | nil
	local current = descendant
	while current and current.Parent ~= bases do
		current = current.Parent
	end

	if current and (current:IsA("Folder") or current:IsA("Model")) then
		return current
	end

	return nil
end

local function getPadAnimal(pad: Instance): Instance?
	local animalFolder = pad:FindFirstChild("Animal")
	if animalFolder == nil then
		local nestedFolder = pad:FindFirstChild("Animal", true)
		if nestedFolder and nestedFolder:IsA("Folder") then
			animalFolder = nestedFolder
		end
	end

	if animalFolder == nil then
		return nil
	end

	return animalFolder:GetChildren()[1]
end

local function getPadPlacePart(pad: Instance): BasePart?
	local placer = pad:FindFirstChild("Placer", true)
	if placer then
		local placerParent = placer.Parent
		local parentPad = placerParent and placerParent:FindFirstChild("Pad")
		if parentPad and parentPad:IsA("BasePart") then
			return parentPad
		end

		if placer:IsA("BasePart") then
			return placer
		end
		if placer:IsA("ProximityPrompt") and placer.Parent and placer.Parent:IsA("BasePart") then
			return placer.Parent
		end
		if placer:IsA("Model") then
			return placer.PrimaryPart or placer:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	return pad:FindFirstChildWhichIsA("BasePart")
end

local function getPadStoredCash(pad: Instance): number
	local storedCash = pad:GetAttribute("StoredCash")
	if typeof(storedCash) == "number" then
		return storedCash
	end

	local collector = pad:FindFirstChild("Collector")
	local collectorCash = collector and collector:GetAttribute("StoredCash")
	if typeof(collectorCash) == "number" then
		return collectorCash
	end

	return 0
end

local function resolveBaseOwner(base: Folder, playerBases)
	if type(playerBases) == "table" then
		for player, ownedBase in pairs(playerBases) do
			if ownedBase == base then
				return player
			end
		end
	end

	local config = base:FindFirstChild("Config")
	local ownerValue = config and config:FindFirstChild("PlayerUsername")
	if ownerValue and ownerValue:IsA("StringValue") then
		local owner = Players:FindFirstChild(ownerValue.Value)
		if owner and owner:IsA("Player") then
			return owner
		end
	end

	local ownerByName = Players:FindFirstChild(base.Name)
	if ownerByName and ownerByName:IsA("Player") then
		return ownerByName
	end

	return nil
end

local function getBaseMultiplier(base: Folder, playerBases): number
	local owner = resolveBaseOwner(base, playerBases)
	if owner then
		local stats = owner:FindFirstChild("Stats")
		local multiplier = stats and stats:FindFirstChild("Multiplier")
		if multiplier and multiplier:IsA("NumberValue") then
			local value = tonumber(multiplier.Value) or 1
			if value > 0 then
				return value
			end
		end
	end

	return 1
end

local function setPadStoredCash(pad: Instance, amount: number)
	amount = tonumber(amount) or 0
	pad:SetAttribute("StoredCash", amount)

	local collector = pad:FindFirstChild("Collector")
	if collector and collector:IsA("BasePart") then
		collector:SetAttribute("StoredCash", amount)
	end
end

function BaseService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._bases = Workspace:WaitForChild("Bases")
	self._playerBases = {}
	self._playerConnections = {}
	self._boundPads = setmetatable({}, {__mode = "k"})
	self._effects = runtime:GetService("ClientEffectsService")
	self._sounds = runtime:GetService("SoundService")
	self._padEffectName = runtime.Config.Effects.Names.PadCollected
end

function BaseService:GetPlayerBase(player: Player): Model | Folder | nil
	return self._playerBases[player]
end

function BaseService:_findEmptyBase(): Model | Folder | nil
	for _, base in ipairs(self._bases:GetChildren()) do
		if not base:IsA("Folder") and not base:IsA("Model") then
			continue
		end

		local config = base:FindFirstChild("Config")
		local owned = config and config:FindFirstChild("Owned")
		if owned and owned:IsA("BoolValue") and owned.Value == false then
			return base
		end
	end

	return nil
end

function BaseService:_disconnectPlayerConnections(player: Player)
	local connections = self._playerConnections[player]
	if connections == nil then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	self._playerConnections[player] = nil
end

function BaseService:_setMultiplierLabel(base: Folder, multiplierValue: number, attemptsLeft: number?)
	attemptsLeft = attemptsLeft or 3
	local extras = base:FindFirstChild("Extras") or base:FindFirstChild("Extras", true)
	local multiplierSurface = extras and (extras:FindFirstChild("Multiplier") or extras:FindFirstChild("Multiplier", true))
	if multiplierSurface == nil then
		multiplierSurface = base:FindFirstChild("Multiplier", true)
	end
	local surfaceGui = multiplierSurface and multiplierSurface:FindFirstChildWhichIsA("SurfaceGui", true)
	local label = surfaceGui and surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = "x" .. tostring(multiplierValue)
	elseif attemptsLeft > 0 then
		task.delay(0.5, function()
			if base and base.Parent then
				self:_setMultiplierLabel(base, multiplierValue, attemptsLeft - 1)
			end
		end)
	end
end

function BaseService:_applyOwnedVisuals(player: Player, base: Folder)
	local extras = base:WaitForChild("Extras")
	local ceiling = base:WaitForChild("Ceiling")
	local sign = extras:WaitForChild("Sign"):WaitForChild("Sign"):WaitForChild("SurfaceGui")

	local unowned = sign:WaitForChild("unowned")
	local owned = sign:WaitForChild("owned")
	unowned.GroupTransparency = 1
	owned.GroupTransparency = 0

	local playerDisplayName = owned:WaitForChild("content"):WaitForChild("name")
	playerDisplayName.Text = player.DisplayName

	local playerUsername = owned:WaitForChild("content"):WaitForChild("username")
	playerUsername.Text = "(@" .. player.Name .. ")"

	local playerPfp = owned:WaitForChild("pfp")
	playerPfp.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=420&h=420"

	local billboard = ceiling:WaitForChild("Player"):WaitForChild("content")
	billboard.GroupTransparency = 0

	local name = billboard:WaitForChild("name")
	name.Text = player.DisplayName

	local pfpButton = billboard:WaitForChild("pfp")
	if pfpButton:IsA("ImageButton") or pfpButton:IsA("ImageLabel") then
		pfpButton.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=420&h=420"
	end

	local stats = player:FindFirstChild("Stats")
	local multiplier = stats and stats:FindFirstChild("Multiplier")
	self:_setMultiplierLabel(base, (multiplier and multiplier.Value) or 1)
end

function BaseService:_bindMultiplierUpdates(player: Player, base: Model | Folder, connections)
	task.spawn(function()
		local stats = player:FindFirstChild("Stats") or player:WaitForChild("Stats", 5)
		if stats == nil then
			return
		end

		local multiplier = stats:FindFirstChild("Multiplier") or stats:WaitForChild("Multiplier", 5)
		if multiplier and multiplier:IsA("NumberValue") then
			self:_setMultiplierLabel(base, multiplier.Value)
			if type(connections) == "table" then
				table.insert(connections, multiplier.Changed:Connect(function(value)
					self:_setMultiplierLabel(base, value)
				end))
			end
		end
	end)
end

function BaseService:_applyUnownedVisuals(base: Model | Folder)
	local extras = base:FindFirstChild("Extras")
	local ceiling = base:FindFirstChild("Ceiling")
	if extras == nil or ceiling == nil then
		return
	end

	local sign = extras:FindFirstChild("Sign")
	sign = sign and sign:FindFirstChild("Sign")
	sign = sign and sign:FindFirstChild("SurfaceGui")
	if sign then
		local unowned = sign:FindFirstChild("unowned")
		local owned = sign:FindFirstChild("owned")
		if unowned then
			unowned.GroupTransparency = 0
		end
		if owned then
			owned.GroupTransparency = 1
		end
	end

	local billboard = ceiling:FindFirstChild("Player")
	billboard = billboard and billboard:FindFirstChild("content")
	if billboard then
		billboard.GroupTransparency = 1
	end

	self:_setMultiplierLabel(base, 1)
end

function BaseService:ResetBase(player: Player)
	local base = self:GetPlayerBase(player)
	if not base then return end

	for levelNum = 1, 5 do
		local levelFolder = base:FindFirstChild(tostring(levelNum))
		if levelFolder then
			local pads = levelFolder:FindFirstChild("Pads")
			if pads then
				for _, pad in ipairs(pads:GetChildren()) do
					-- Remove animal
					local animalFolder = pad:FindFirstChild("Animal")
					if animalFolder then
						animalFolder:ClearAllChildren()
					end
					
					-- Reset pad state
					self:_resetPad(pad)
				end
			end
		end
	end
	
	-- Refresh visual for the whole base
	self:_applyOwnedVisuals(player, base)
end

function BaseService:_resetPad(pad: Instance)
	setPadStoredCash(pad, 0)

	local placer = pad:FindFirstChild("Placer")
	local full = placer and placer:FindFirstChild("Full")
	if full and full:IsA("BoolValue") then
		full.Value = false
	end
	if placer and placer:IsA("ProximityPrompt") then
		placer.Enabled = false
	end

	local collector = pad:FindFirstChild("Collector")
	if collector and collector:IsA("BasePart") then
		collector.Color = EMPTY_COLLECTOR_COLOR
		local surfaceGui = collector:FindFirstChild("SurfaceGui")
		local label = surfaceGui and surfaceGui:FindFirstChild("TextLabel")
		if label and label:IsA("TextLabel") then
			label.Text = "Empty"
		end
	end

	local animalFolder = pad:FindFirstChild("Animal")
	if animalFolder == nil then
		local nestedFolder = pad:FindFirstChild("Animal", true)
		if nestedFolder and nestedFolder:IsA("Folder") then
			animalFolder = nestedFolder
		end
	end

	if animalFolder then
		animalFolder:Destroy()
	end

	local placePart = getPadPlacePart(pad)
	local outline = placePart and placePart:FindFirstChild(PAD_OUTLINE_NAME)
	if outline and outline:IsA("SelectionBox") then
		outline:Destroy()
	end
end

function BaseService:_releaseBase(player: Player)
	local base = self._playerBases[player]
	if base == nil or base.Parent == nil then
		return
	end

	local config = base:FindFirstChild("Config")
	local owned = config and config:FindFirstChild("Owned")
	local playerName = config and config:FindFirstChild("PlayerName")
	local playerUsername = config and config:FindFirstChild("PlayerUsername")
	if owned and owned:IsA("BoolValue") then
		owned.Value = false
	end
	if playerName and playerName:IsA("StringValue") then
		playerName.Value = ""
	end
	if playerUsername and playerUsername:IsA("StringValue") then
		playerUsername.Value = ""
	end

	self:_applyUnownedVisuals(base)

	for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
		if pad:IsDescendantOf(base) then
			self:_resetPad(pad)
		end
	end

	local originalName = base:GetAttribute("OriginalName")
	if typeof(originalName) == "string" and originalName ~= "" then
		base.Name = originalName
	end

	self._playerBases[player] = nil
end

function BaseService:ReleasePlayer(player: Player)
	self:_disconnectPlayerConnections(player)
	self:_releaseBase(player)
end

function BaseService:_assignBase(player: Player)
	local base = self:_findEmptyBase()
	if base == nil then
		player:Kick("No available base")
		return
	end

	if base:GetAttribute("OriginalName") == nil then
		base:SetAttribute("OriginalName", base.Name)
	end

	local config = base:FindFirstChild("Config")
	if config == nil then
		return
	end

	local owned = config:FindFirstChild("Owned")
	local playerName = config:FindFirstChild("PlayerName")
	local playerUsername = config:FindFirstChild("PlayerUsername")
	if owned and owned:IsA("BoolValue") then
		owned.Value = true
	end
	if playerName and playerName:IsA("StringValue") then
		playerName.Value = player.DisplayName
	end
	if playerUsername and playerUsername:IsA("StringValue") then
		playerUsername.Value = player.Name
	end

	local spawnLocation = base:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("SpawnLocation") then
		player.RespawnLocation = spawnLocation
	end

	self:_applyOwnedVisuals(player, base)
	base.Name = player.Name

	for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
		if pad:IsDescendantOf(base) then
			self:_resetPad(pad)
		end
	end

	local connections = {}
	self._playerConnections[player] = connections

	local function onCharacterAdded(character: Model)
		if spawnLocation and spawnLocation:IsA("SpawnLocation") then
			task.defer(function()
				character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
			end)
		end

		local humanoid = character:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 24
	end

	table.insert(connections, player.CharacterAdded:Connect(onCharacterAdded))

	self:_bindMultiplierUpdates(player, base, connections)

	if player.Character then
		onCharacterAdded(player.Character)
	end

	self._playerBases[player] = base
end

function BaseService:_updatePadVisual(pad: Instance)
	local currentGross = getPadStoredCash(pad)
	local animal = getPadAnimal(pad)
	local hasAnimal = animal ~= nil

	local placer = pad:FindFirstChild("Placer")
	local full = placer and placer:FindFirstChild("Full")
	local collector = pad:FindFirstChild("Collector")
	if collector and collector:IsA("BasePart") then
		collector.Color = (full and full:IsA("BoolValue") and full.Value) and FULL_COLLECTOR_COLOR or EMPTY_COLLECTOR_COLOR

		local surfaceGui = collector:FindFirstChild("SurfaceGui")
		local label = surfaceGui and surfaceGui:FindFirstChild("TextLabel")
		if label and label:IsA("TextLabel") then
			if currentGross > 0 then
				label.Text = "$" .. NumberFormatter:Format(currentGross, "Letters")
			elseif hasAnimal then
				label.Text = "$0"
			else
				label.Text = "Empty"
			end
		end
	end

	local placePart = getPadPlacePart(pad)
	if placePart == nil then
		return
	end

	local existingOutline = placePart:FindFirstChild(PAD_OUTLINE_NAME)
	local rarity = hasAnimal and animal:GetAttribute("Rarity") or nil
	local visual = (typeof(rarity) == "string" and PAD_RARITY_VISUALS[rarity]) or nil
	if visual == nil then
		if existingOutline and existingOutline:IsA("SelectionBox") then
			existingOutline:Destroy()
		end
		return
	end

	local outline = existingOutline
	if outline == nil or not outline:IsA("SelectionBox") then
		if outline ~= nil then
			outline:Destroy()
		end
		outline = Instance.new("SelectionBox")
		outline.Name = PAD_OUTLINE_NAME
		outline.SurfaceTransparency = 1
		outline.Parent = placePart
	end

	outline.Adornee = placePart
	outline.Color3 = visual.Color
	outline.LineThickness = visual.Thickness
end

function BaseService:_bindPad(pad: Instance)
	if self._boundPads[pad] then
		return
	end
	self._boundPads[pad] = true

	if pad:GetAttribute("StoredCash") == nil then
		setPadStoredCash(pad, 0)
	else
		setPadStoredCash(pad, getPadStoredCash(pad))
	end
	self:_updatePadVisual(pad)

	local collector = pad:WaitForChild("Collector")
	local debounce = false

	collector.Touched:Connect(function(hit)
		if debounce then
			return
		end

		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player == nil then
			return
		end

		local base = getBaseFromDescendant(pad, self._bases)
		if base == nil then
			return
		end

		local config = base:FindFirstChild("Config")
		local ownerValue = config and config:FindFirstChild("PlayerUsername")
		if ownerValue == nil or not ownerValue:IsA("StringValue") or ownerValue.Value ~= player.Name then
			return
		end

		local currentCash = getPadStoredCash(pad)
		if currentCash <= 0 then
			return
		end

		debounce = true
		setPadStoredCash(pad, 0)

		local leaderstats = player:FindFirstChild("leaderstats")
		local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
		if bucks and bucks:IsA("IntValue") then
			bucks.Value += currentCash
		end

		self._sounds:PlayForPlayer(player, "CashCollected")

		self:_updatePadVisual(pad)
		self._effects:EmitToPlayer(player, self._padEffectName, {
			collector = collector,
			amount = currentCash,
		})

		task.delay(0.25, function()
			debounce = false
		end)
	end)
end

function BaseService:_tickPads()
	while true do
		for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
			local currentGross = getPadStoredCash(pad)
			local animal = getPadAnimal(pad)
			if animal and not animal:GetAttribute("IsLuckyBlock") then
				local base = getBaseFromDescendant(pad, self._bases)
				local multiplier = base and getBaseMultiplier(base, self._playerBases) or 1
				local revenue = animal:GetAttribute("Revenue") or 0
				currentGross += revenue * multiplier
				setPadStoredCash(pad, currentGross)
			end

			self:_updatePadVisual(pad)
		end

		task.wait(1)
	end
end

function BaseService:Start()
	for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
		self:_bindPad(pad)
	end

	CollectionService:GetInstanceAddedSignal("Pad"):Connect(function(pad)
		self:_bindPad(pad)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:_assignBase(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_assignBase(player)
	end)

	task.spawn(function()
		self:_tickPads()
	end)
end

function BaseService:GetSnapshot(player: Player)
	local base = self._playerBases[player]
	if base == nil then
		return nil
	end

	local animalService = self._runtime and self._runtime:GetService("AnimalService")
	local snapshot = {
		pads = {},
	}

	for _, pad in ipairs(CollectionService:GetTagged("Pad")) do
		if not pad:IsDescendantOf(base) then
			continue
		end

		local path = getRelativePath(base, pad)
		if path == nil then
			continue
		end

		local padData = {
			path = path,
			storedCash = getPadStoredCash(pad),
		}

		local animal = getPadAnimal(pad)
		if animal and animal:GetAttribute("PendingStealResolved") == true then
			animal = nil
		end
		if animal and animalService then
			padData.animal = animalService:SerializePlacedAnimal(animal)
		end

		table.insert(snapshot.pads, padData)
	end

	return snapshot
end

function BaseService:RestoreSnapshot(player: Player, snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	local base = self._playerBases[player]
	if base == nil then
		return
	end

	local animalService = self._runtime and self._runtime:GetService("AnimalService")
	local padsSnapshot = snapshot.pads or {}

	local function restorePad(path, padData)
		if type(padData) ~= "table" then
			return
		end

		local pad = findByRelativePath(base, path)
		if pad == nil then
			return
		end

		setPadStoredCash(pad, tonumber(padData.storedCash) or 0)

		if padData.animal and animalService then
			animalService:RestorePlacedAnimal(base, pad, padData.animal)
		end

		self:_updatePadVisual(pad)
	end

	if padsSnapshot[1] ~= nil then
		for _, padData in ipairs(padsSnapshot) do
			restorePad(padData.path, padData)
		end
	else
		for path, padData in pairs(padsSnapshot) do
			restorePad(path, padData)
		end
	end
end

return BaseService
