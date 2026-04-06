local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local DataService = {
	Name = "DataService",
	Priority = -70,
}

local VALUE_CLASS_NAMES = {
	BoolValue = true,
	IntValue = true,
	NumberValue = true,
	StringValue = true,
	Vector3Value = true,
	CFrameValue = true,
	Color3Value = true,
}

local TREE_CONTAINER_CLASSES = {
	Folder = true,
	Configuration = true,
}

local INVENTORY_SUPPORTED_CLASSES = {
	Folder = true,
	Configuration = true,
	Model = true,
	Tool = true,
	Part = true,
	MeshPart = true,
	Attachment = true,
	WeldConstraint = true,
	Weld = true,
	SpecialMesh = true,
	Decal = true,
	Texture = true,
	BoolValue = true,
	IntValue = true,
	NumberValue = true,
	StringValue = true,
	Vector3Value = true,
	CFrameValue = true,
	Color3Value = true,
}

local function encodeValue(value)
	local valueType = typeof(value)
	if valueType == "number" or valueType == "string" or valueType == "boolean" then
		return {
			type = valueType,
			value = value,
		}
	elseif valueType == "Vector3" then
		return {
			type = "Vector3",
			value = {value.X, value.Y, value.Z},
		}
	elseif valueType == "Color3" then
		return {
			type = "Color3",
			value = {value.R, value.G, value.B},
		}
	elseif valueType == "CFrame" then
		return {
			type = "CFrame",
			value = {value:GetComponents()},
		}
	end

	return nil
end

local function decodeValue(encoded)
	if type(encoded) ~= "table" then
		return nil
	end

	if encoded.type == "number" or encoded.type == "string" or encoded.type == "boolean" then
		return encoded.value
	elseif encoded.type == "Vector3" and type(encoded.value) == "table" then
		return Vector3.new(encoded.value[1] or 0, encoded.value[2] or 0, encoded.value[3] or 0)
	elseif encoded.type == "Color3" and type(encoded.value) == "table" then
		return Color3.new(encoded.value[1] or 0, encoded.value[2] or 0, encoded.value[3] or 0)
	elseif encoded.type == "CFrame" and type(encoded.value) == "table" then
		return CFrame.new(table.unpack(encoded.value))
	end

	return nil
end

local function compareRelativePath(pathA, pathB)
	if type(pathA) == "string" or type(pathB) == "string" then
		return tostring(pathA) == tostring(pathB)
	end

	if type(pathA) ~= "table" or type(pathB) ~= "table" then
		return false
	end
	if #pathA ~= #pathB then
		return false
	end

	for index, segmentA in ipairs(pathA) do
		local segmentB = pathB[index]
		if type(segmentA) ~= "table" or type(segmentB) ~= "table" then
			return false
		end
		if segmentA.name ~= segmentB.name or segmentA.className ~= segmentB.className then
			return false
		end
		if (tonumber(segmentA.index) or 1) ~= (tonumber(segmentB.index) or 1) then
			return false
		end
	end

	return true
end

local function removeAnimalFromBaseSnapshot(baseSnapshot, padPath)
	if type(baseSnapshot) ~= "table" then
		return false
	end

	local pads = baseSnapshot.pads
	if type(pads) ~= "table" then
		return false
	end

	local changed = false
	if pads[1] ~= nil then
		for _, padData in ipairs(pads) do
			if type(padData) == "table" and compareRelativePath(padData.path, padPath) then
				padData.animal = nil
				changed = true
				break
			end
		end
	else
		for key, padData in pairs(pads) do
			local currentPath = if type(padData) == "table" and padData.path ~= nil then padData.path else key
			if compareRelativePath(currentPath, padPath) then
				if type(padData) == "table" then
					padData.animal = nil
				end
				changed = true
				break
			end
		end
	end

	return changed
end

local function serializeAttributes(instance: Instance)
	local attributes = {}
	for name, value in pairs(instance:GetAttributes()) do
		local encoded = encodeValue(value)
		if encoded ~= nil then
			attributes[name] = encoded
		end
	end

	return attributes
end

local function applyAttributes(instance: Instance, attributes)
	for name, encoded in pairs(attributes or {}) do
		local value = decodeValue(encoded)
		if value ~= nil then
			instance:SetAttribute(name, value)
		end
	end
end

local function serializeTreeNode(instance: Instance)
	local node = {
		className = instance.ClassName,
		name = instance.Name,
		attributes = serializeAttributes(instance),
		children = {},
	}

	if VALUE_CLASS_NAMES[instance.ClassName] then
		local encodedValue = encodeValue(instance.Value)
		if encodedValue ~= nil then
			node.value = encodedValue
		end
	end

	for _, child in ipairs(instance:GetChildren()) do
		if TREE_CONTAINER_CLASSES[child.ClassName] or VALUE_CLASS_NAMES[child.ClassName] then
			table.insert(node.children, serializeTreeNode(child))
		end
	end

	return node
end

local function syncTreeNode(instance: Instance, node)
	applyAttributes(instance, node.attributes)

	if VALUE_CLASS_NAMES[node.className] and node.value ~= nil then
		local decodedValue = decodeValue(node.value)
		if decodedValue ~= nil then
			instance.Value = decodedValue
		end
	end

	local expectedChildren = {}
	for _, childNode in ipairs(node.children or {}) do
		if type(childNode) == "table" and type(childNode.name) == "string" and type(childNode.className) == "string" then
			local child = instance:FindFirstChild(childNode.name)
			if child and child.ClassName ~= childNode.className then
				child:Destroy()
				child = nil
			end

			if child == nil then
				child = Instance.new(childNode.className)
				child.Name = childNode.name
				child.Parent = instance
			end

			expectedChildren[child] = true
			syncTreeNode(child, childNode)
		end
	end

	for _, child in ipairs(instance:GetChildren()) do
		if child.Name == "UnlockedAreas" or child.Name == "Merchant" or child.Name == "Rebirths" or child.Name == "Diamonds" or child.Name == "Bucks" or child.Name == "BaseUpgrade" then continue end

		if (TREE_CONTAINER_CLASSES[child.ClassName] or VALUE_CLASS_NAMES[child.ClassName]) and not expectedChildren[child] then
			child:Destroy()
		end
	end
end

local function isInventorySerializable(instance: Instance): boolean
	if INVENTORY_SUPPORTED_CLASSES[instance.ClassName] then
		return true
	end

	return false
end

local function collectInventoryNodes(root: Instance, idMap, ordered)
	if not isInventorySerializable(root) then
		return
	end

	idMap[root] = #ordered + 1
	table.insert(ordered, root)

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("RemoteEvent") or child:IsA("Script") or child:IsA("LocalScript") then
			continue
		end

		collectInventoryNodes(child, idMap, ordered)
	end
end

local function serializeInventoryNode(instance: Instance, idMap)
	local node = {
		id = idMap[instance],
		className = instance.ClassName,
		name = instance.Name,
		attributes = serializeAttributes(instance),
		tags = CollectionService:GetTags(instance),
		properties = {},
		children = {},
	}

	if instance:IsA("Tool") then
		node.properties.CanBeDropped = instance.CanBeDropped
		node.properties.RequiresHandle = instance.RequiresHandle
		node.properties.Grip = encodeValue(instance.Grip)
		node.properties.TextureId = instance.TextureId
	elseif instance:IsA("BasePart") then
		node.properties.Size = encodeValue(instance.Size)
		node.properties.CFrame = encodeValue(instance.CFrame)
		node.properties.Color = encodeValue(instance.Color)
		node.properties.Material = instance.Material.Name
		node.properties.Transparency = instance.Transparency
		node.properties.Reflectance = instance.Reflectance
		node.properties.Anchored = instance.Anchored
		node.properties.CanCollide = instance.CanCollide
		node.properties.CanTouch = instance.CanTouch
		node.properties.CanQuery = instance.CanQuery
		node.properties.CastShadow = instance.CastShadow
		node.properties.Massless = instance.Massless
		if instance:IsA("Part") then
			node.properties.Shape = instance.Shape.Name
		elseif instance:IsA("MeshPart") then
			node.properties.MeshId = instance.MeshId
			node.properties.TextureID = instance.TextureID
		end
	elseif instance:IsA("Attachment") then
		node.properties.CFrame = encodeValue(instance.CFrame)
	elseif instance:IsA("SpecialMesh") then
		node.properties.MeshType = instance.MeshType.Name
		node.properties.MeshId = instance.MeshId
		node.properties.TextureId = instance.TextureId
		node.properties.Scale = encodeValue(instance.Scale)
		node.properties.Offset = encodeValue(instance.Offset)
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		node.properties.Texture = instance.Texture
		node.properties.Transparency = instance.Transparency
		node.properties.Face = instance.Face.Name
		if instance:IsA("Decal") then
			node.properties.Color3 = encodeValue(instance.Color3)
		else
			node.properties.Color3 = encodeValue(instance.Color3)
		end
	elseif VALUE_CLASS_NAMES[instance.ClassName] then
		node.properties.Value = encodeValue(instance.Value)
	elseif instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart and idMap[primaryPart] then
			node.properties.PrimaryPartId = idMap[primaryPart]
		end
	elseif instance:IsA("WeldConstraint") then
		if instance.Part0 and idMap[instance.Part0] then
			node.properties.Part0Id = idMap[instance.Part0]
		end
		if instance.Part1 and idMap[instance.Part1] then
			node.properties.Part1Id = idMap[instance.Part1]
		end
	elseif instance:IsA("Weld") then
		if instance.Part0 and idMap[instance.Part0] then
			node.properties.Part0Id = idMap[instance.Part0]
		end
		if instance.Part1 and idMap[instance.Part1] then
			node.properties.Part1Id = idMap[instance.Part1]
		end
		node.properties.C0 = encodeValue(instance.C0)
		node.properties.C1 = encodeValue(instance.C1)
	end

	for _, child in ipairs(instance:GetChildren()) do
		if idMap[child] then
			table.insert(node.children, serializeInventoryNode(child, idMap))
		end
	end

	return node
end

local function trySetProperty(instance: Instance, propertyName: string, value)
	return pcall(function()
		instance[propertyName] = value
	end)
end

local function applyInventoryProperties(instance: Instance, props)
	props = props or {}

	if instance:IsA("Tool") then
		trySetProperty(instance, "CanBeDropped", props.CanBeDropped ~= false)
		trySetProperty(instance, "RequiresHandle", props.RequiresHandle ~= false)
		trySetProperty(instance, "TextureId", props.TextureId or "")
		local grip = decodeValue(props.Grip)
		if grip then
			trySetProperty(instance, "Grip", grip)
		end
	elseif instance:IsA("BasePart") then
		local size = decodeValue(props.Size)
		local cframe = decodeValue(props.CFrame)
		local color = decodeValue(props.Color)
		if size then
			trySetProperty(instance, "Size", size)
		end
		if cframe then
			trySetProperty(instance, "CFrame", cframe)
		end
		if color then
			trySetProperty(instance, "Color", color)
		end
		if props.Material and Enum.Material[props.Material] then
			trySetProperty(instance, "Material", Enum.Material[props.Material])
		end
		trySetProperty(instance, "Transparency", props.Transparency or 0)
		trySetProperty(instance, "Reflectance", props.Reflectance or 0)
		trySetProperty(instance, "Anchored", props.Anchored == true)
		trySetProperty(instance, "CanCollide", props.CanCollide == true)
		trySetProperty(instance, "CanTouch", props.CanTouch ~= false)
		trySetProperty(instance, "CanQuery", props.CanQuery ~= false)
		trySetProperty(instance, "CastShadow", props.CastShadow ~= false)
		trySetProperty(instance, "Massless", props.Massless == true)
		if instance:IsA("Part") and props.Shape and Enum.PartType[props.Shape] then
			trySetProperty(instance, "Shape", Enum.PartType[props.Shape])
		elseif instance:IsA("MeshPart") then
			trySetProperty(instance, "MeshId", props.MeshId or "")
			trySetProperty(instance, "TextureID", props.TextureID or "")
		end
	elseif instance:IsA("Attachment") then
		local attachmentCFrame = decodeValue(props.CFrame)
		if attachmentCFrame then
			trySetProperty(instance, "CFrame", attachmentCFrame)
		end
	elseif instance:IsA("SpecialMesh") then
		if props.MeshType and Enum.MeshType[props.MeshType] then
			trySetProperty(instance, "MeshType", Enum.MeshType[props.MeshType])
		end
		trySetProperty(instance, "MeshId", props.MeshId or "")
		trySetProperty(instance, "TextureId", props.TextureId or "")
		local scale = decodeValue(props.Scale)
		local offset = decodeValue(props.Offset)
		if scale then
			trySetProperty(instance, "Scale", scale)
		end
		if offset then
			trySetProperty(instance, "Offset", offset)
		end
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		trySetProperty(instance, "Texture", props.Texture or "")
		trySetProperty(instance, "Transparency", props.Transparency or 0)
		if props.Face and Enum.NormalId[props.Face] then
			trySetProperty(instance, "Face", Enum.NormalId[props.Face])
		end
		local color3 = decodeValue(props.Color3)
		if color3 then
			trySetProperty(instance, "Color3", color3)
		end
	elseif VALUE_CLASS_NAMES[instance.ClassName] then
		local decodedValue = decodeValue(props.Value)
		if decodedValue ~= nil then
			trySetProperty(instance, "Value", decodedValue)
		end
	end
end

local function restoreInventoryTree(parent: Instance, node, idToInstance, pendingRefs)
	if type(node) ~= "table" or type(node.className) ~= "string" then
		return nil
	end

	local instance = Instance.new(node.className)
	instance.Name = node.name or instance.Name
	applyInventoryProperties(instance, node.properties)
	applyAttributes(instance, node.attributes)
	instance.Parent = parent

	for _, tag in ipairs(node.tags or {}) do
		CollectionService:AddTag(instance, tag)
	end

	idToInstance[node.id] = instance
	table.insert(pendingRefs, {
		instance = instance,
		node = node,
	})

	for _, childNode in ipairs(node.children or {}) do
		restoreInventoryTree(instance, childNode, idToInstance, pendingRefs)
	end

	return instance
end

local function resolveInventoryRefs(pendingRefs, idToInstance)
	for _, entry in ipairs(pendingRefs) do
		local instance = entry.instance
		local props = entry.node.properties or {}

		if instance:IsA("Model") and props.PrimaryPartId then
			local primaryPart = idToInstance[props.PrimaryPartId]
			if primaryPart and primaryPart:IsA("BasePart") then
				instance.PrimaryPart = primaryPart
			end
		elseif instance:IsA("WeldConstraint") then
			local part0 = idToInstance[props.Part0Id]
			local part1 = idToInstance[props.Part1Id]
			if part0 and part0:IsA("BasePart") then
				instance.Part0 = part0
			end
			if part1 and part1:IsA("BasePart") then
				instance.Part1 = part1
			end
		elseif instance:IsA("Weld") then
			local part0 = idToInstance[props.Part0Id]
			local part1 = idToInstance[props.Part1Id]
			if part0 and part0:IsA("BasePart") then
				instance.Part0 = part0
			end
			if part1 and part1:IsA("BasePart") then
				instance.Part1 = part1
			end

			local c0 = decodeValue(props.C0)
			local c1 = decodeValue(props.C1)
			if c0 then
				instance.C0 = c0
			end
			if c1 then
				instance.C1 = c1
			end
		end
	end
end

local function serializeInventoryTree(root: Instance)
	local idMap = {}
	local ordered = {}
	collectInventoryNodes(root, idMap, ordered)
	if idMap[root] == nil then
		return nil
	end

	return serializeInventoryNode(root, idMap)
end

function DataService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._dataStore = DataStoreService:GetDataStore(runtime.Config.Data.StoreName)
	self._loadedProfiles = {}
	self._loadingPlayers = {}
	self._sessionLoaded = {}
	self._inventoryLayouts = {}
	self._inventoryLayoutRemote = nil
end

function DataService:_getKey(player: Player): string
	return tostring(player.UserId)
end

function DataService:RemovePlacedAnimalFromSavedBase(ownerUserId: number, padPath)
	if type(ownerUserId) ~= "number" or padPath == nil then
		return false
	end

	for player, loadedProfile in pairs(self._loadedProfiles) do
		if player.UserId == ownerUserId and type(loadedProfile) == "table" then
			removeAnimalFromBaseSnapshot(loadedProfile.base, padPath)
		end
	end

	local success, err = pcall(function()
		self._dataStore:UpdateAsync(tostring(ownerUserId), function(snapshot)
			if type(snapshot) ~= "table" then
				return snapshot
			end

			if removeAnimalFromBaseSnapshot(snapshot.base, padPath) then
				snapshot.savedAt = os.time()
			end

			return snapshot
		end)
	end)

	if not success then
		warn(string.format("[DataService] Failed removing stolen animal for %s: %s", tostring(ownerUserId), tostring(err)))
	end

	return success
end

function DataService:_waitForBase(player: Player, timeoutSeconds: number)
	local baseService = self._runtime:GetService("BaseService")
	local deadline = os.clock() + timeoutSeconds

	while os.clock() <= deadline do
		local base = baseService and baseService:GetPlayerBase(player)
		if base then
			return base
		end

		task.wait(0.1)
	end

	return nil
end

function DataService:_waitForCharacter(player: Player, timeoutSeconds: number)
	local deadline = os.clock() + timeoutSeconds

	while os.clock() <= deadline do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid then
			return character
		end

		task.wait(0.1)
	end

	return player.Character
end

function DataService:_serializeFolder(root: Instance)
	return serializeTreeNode(root)
end

function DataService:_restoreFolder(root: Instance, snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	syncTreeNode(root, snapshot)
end

function DataService:_grantStarterInventory(player: Player)
	local starterFolder = ServerStorage:FindFirstChild("Starter")
	if starterFolder == nil or not starterFolder:IsA("Folder") then
		return
	end

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 10)
	if backpack == nil then
		return
	end

	for _, child in ipairs(starterFolder:GetDescendants()) do
		if not (child:IsA("Tool") or child:IsA("Configuration")) then
			continue
		end
		if child.Parent ~= starterFolder and not child.Parent:IsA("Folder") then
			continue
		end

		local existing = backpack:FindFirstChild(child.Name)
		if existing and (existing:IsA("Tool") or existing:IsA("Configuration")) and existing.ClassName == child.ClassName then
			continue
		end

		local clone = child:Clone()
		clone.Parent = backpack
	end
end

function DataService:_hasSavedInventoryItems(backpackItems): boolean
	if type(backpackItems) ~= "table" then
		return false
	end

	for _, itemData in ipairs(backpackItems) do
		if type(itemData) == "table" and type(itemData.kind) == "string" and type(itemData.name) == "string" then
			return true
		end
	end

	return false
end

function DataService:_isPlayerInventoryInstance(player: Player, instance: Instance): boolean
	if instance == nil or not (instance:IsA("Tool") or instance:IsA("Configuration")) then
		return false
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack and instance.Parent == backpack then
		return true
	end

	local character = player.Character
	if character and instance.Parent == character then
		return true
	end

	return false
end

function DataService:_recordInventoryLayout(player: Player, layoutData)
	if type(layoutData) ~= "table" then
		return
	end

	local normalized = {}
	local seenInstances = {}

	for _, entry in ipairs(layoutData) do
		if #normalized >= 300 then
			break
		end

		if type(entry) ~= "table" then
			continue
		end

		local slot = tonumber(entry.slot)
		local instance = entry.instance
		if type(slot) ~= "number" or instance == nil then
			continue
		end
		if seenInstances[instance] then
			continue
		end
		if not self:_isPlayerInventoryInstance(player, instance) then
			continue
		end

		seenInstances[instance] = true
		table.insert(normalized, {
			slot = math.max(1, math.floor(slot)),
			instance = instance,
		})
	end

	table.sort(normalized, function(a, b)
		if a.slot == b.slot then
			return tostring(a.instance) < tostring(b.instance)
		end
		return a.slot < b.slot
	end)

	self._inventoryLayouts[player] = normalized
end

function DataService:_snapshotBackpack(player: Player)
	local items = {}
	local animalService = self._runtime:GetService("AnimalService")
	local seenInstances = {}
	local nextSlot = 1

	local function addItem(instance: Instance, location: string, slotNumber: number?)
		if seenInstances[instance] then
			return
		end

		local itemData = animalService and animalService:SerializeInventoryItem(instance)
		if itemData ~= nil then
			itemData.location = location
			if type(slotNumber) == "number" then
				itemData.slot = math.max(1, math.floor(slotNumber))
			end
			table.insert(items, itemData)
			seenInstances[instance] = true
		end
	end

	local layout = self._inventoryLayouts[player]
	if type(layout) == "table" and #layout > 0 then
		for _, entry in ipairs(layout) do
			local instance = entry.instance
			if self:_isPlayerInventoryInstance(player, instance) then
				local location = if instance.Parent == player.Character then "Character" else "Backpack"
				local slot = tonumber(entry.slot) or nextSlot
				addItem(instance, location, slot)
				nextSlot = math.max(nextSlot, math.floor(slot) + 1)
			end
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") or child:IsA("Configuration") then
				addItem(child, "Backpack", nextSlot)
				nextSlot += 1
			end
		end
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") or child:IsA("Configuration") then
				addItem(child, "Character", nextSlot)
				nextSlot += 1
			end
		end
	end

	return items
end

function DataService:_clearInventory(player: Player)
	local animalService = self._runtime:GetService("AnimalService")

	local function shouldClear(child: Instance): boolean
		if not (child:IsA("Tool") or child:IsA("Configuration")) then
			return false
		end

		return animalService ~= nil and animalService:SerializeInventoryItem(child) ~= nil
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if shouldClear(child) then
				child:Destroy()
			end
		end
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if shouldClear(child) then
				child:Destroy()
			end
		end
	end
end

function DataService:_restoreBackpack(player: Player, backpackItems): number
	if type(backpackItems) ~= "table" then
		return 0
	end

	self:_clearInventory(player)

	local animalService = self._runtime:GetService("AnimalService")
	local orderedItems = {}
	local restoredCount = 0

	for _, itemData in ipairs(backpackItems) do
		if type(itemData) == "table" then
			table.insert(orderedItems, itemData)
		end
	end

	table.sort(orderedItems, function(a, b)
		local aSlot = tonumber(a.slot)
		local bSlot = tonumber(b.slot)
		if aSlot and bSlot then
			if aSlot == bSlot then
				return tostring(a.name or "") < tostring(b.name or "")
			end
			return aSlot < bSlot
		end
		if aSlot then
			return true
		end
		if bSlot then
			return false
		end
		return false
	end)

	for _, itemData in ipairs(orderedItems) do
		if animalService and animalService:RestoreInventoryItem(player, itemData) then
			restoredCount += 1
			continue
		end
	end

	return restoredCount
end

function DataService:_buildSnapshot(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stats = player:FindFirstChild("Stats")
	local baseService = self._runtime:GetService("BaseService")

	return {
		version = 3,
		savedAt = os.time(),
		leaderstats = leaderstats and self:_serializeFolder(leaderstats) or nil,
		stats = stats and self:_serializeFolder(stats) or nil,
		base = baseService and baseService:GetSnapshot(player) or nil,
		backpack = self:_snapshotBackpack(player),
	}
end

function DataService:SavePlayer(player: Player)
	if player == nil or not player:IsA("Player") then
		return false
	end

	local snapshot = self:_buildSnapshot(player)
	local success, err = pcall(function()
		self._dataStore:UpdateAsync(self:_getKey(player), function()
			return snapshot
		end)
	end)

	if success then
		self._loadedProfiles[player] = snapshot
	end

	if not success then
		warn(string.format("[DataService] Save failed for %s: %s", player.Name, tostring(err)))
	end

	return success
end

function DataService:LoadPlayer(player: Player)
	if self._loadingPlayers[player] or self._sessionLoaded[player] then
		return
	end
	self._loadingPlayers[player] = true

	player:WaitForChild("leaderstats")
	player:WaitForChild("Stats")
	player:WaitForChild("Backpack")
	self:_waitForBase(player, 10)

	local loadedData
	local success, err = pcall(function()
		loadedData = self._dataStore:GetAsync(self:_getKey(player))
	end)

	if not success then
		warn(string.format("[DataService] Load failed for %s: %s", player.Name, tostring(err)))
		self._loadingPlayers[player] = nil
		return
	end

	if type(loadedData) ~= "table" then
		self:_waitForCharacter(player, 10)
		self:_grantStarterInventory(player)

		self._sessionLoaded[player] = true
		self._loadingPlayers[player] = nil
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local stats = player:FindFirstChild("Stats")
	if leaderstats and loadedData.leaderstats then
		self:_restoreFolder(leaderstats, loadedData.leaderstats)
	end
	if stats and loadedData.stats then
		self:_restoreFolder(stats, loadedData.stats)
	end

	local baseService = self._runtime:GetService("BaseService")
	if baseService and loadedData.base then
		baseService:RestoreSnapshot(player, loadedData.base)
	end

	if self:_hasSavedInventoryItems(loadedData.backpack) then
		self:_waitForCharacter(player, 10)
		local restoredCount = self:_restoreBackpack(player, loadedData.backpack)
		if restoredCount <= 0 then
			self:_grantStarterInventory(player)
		end
	else
		self:_waitForCharacter(player, 10)
		self:_grantStarterInventory(player)
	end

	self._loadedProfiles[player] = loadedData
	self._sessionLoaded[player] = true
	self._loadingPlayers[player] = nil
end

function DataService:Start()
	self._inventoryLayoutRemote = self._runtime.Remotes:GetInventoryLayoutRemote()
	self._inventoryLayoutRemote.OnServerEvent:Connect(function(player, layoutData)
		self:_recordInventoryLayout(player, layoutData)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:LoadPlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			self:LoadPlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:SavePlayer(player)

		local baseService = self._runtime:GetService("BaseService")
		if baseService and type(baseService.ReleasePlayer) == "function" then
			baseService:ReleasePlayer(player)
		end

		self._loadedProfiles[player] = nil
		self._loadingPlayers[player] = nil
		self._sessionLoaded[player] = nil
		self._inventoryLayouts[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(self._config.Data.AutoSaveInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				self:SavePlayer(player)
			end
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			self:SavePlayer(player)
		end
	end)
end

return DataService
