local Players = game:GetService("Players")

local FakeToolService = {
	Name = "FakeToolService",
	Priority = -65,
}

local function getOwnedContainer(player: Player, instance: Instance): string?
	local backpack = player:FindFirstChild("Backpack")
	if backpack and instance.Parent == backpack then
		return "Backpack"
	end

	local character = player.Character
	if character and instance.Parent == character then
		return "Character"
	end

	return nil
end

local function getArm(character: Model): BasePart?
	local rightHand = character:FindFirstChild("RightHand")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand
	end

	local rightArm = character:FindFirstChild("Right Arm")
	if rightArm and rightArm:IsA("BasePart") then
		return rightArm
	end

	return nil
end

local function prepareConfigParts(config: Configuration)
	for _, descendant in ipairs(config:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end
end

local function getConfigHandlePart(config: Configuration): BasePart?
	local directHandle = config:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end
	if directHandle and directHandle:IsA("Model") then
		return directHandle.PrimaryPart or directHandle:FindFirstChildWhichIsA("BasePart", true)
	end

	local nestedHandle = config:FindFirstChild("Handle", true)
	if nestedHandle and nestedHandle:IsA("BasePart") then
		return nestedHandle
	end
	if nestedHandle and nestedHandle:IsA("Model") then
		return nestedHandle.PrimaryPart or nestedHandle:FindFirstChildWhichIsA("BasePart", true)
	end

	return config:FindFirstChildWhichIsA("BasePart", true)
end

local function isFakeToolConfiguration(player: Player, config: Instance): boolean
	if not config:IsA("Configuration") then
		return false
	end

	return getOwnedContainer(player, config) ~= nil
end

local function ensureRemote(config: Configuration, name: string): RemoteEvent
	local remote = config:FindFirstChild(name)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if remote == nil then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = config
	end

	return remote :: RemoteEvent
end

local function getConfigBaseDamage(config: Configuration, defaultDamage: number): number
	local damageAttribute = config:GetAttribute("Damage")
	if typeof(damageAttribute) == "number" then
		return damageAttribute
	end

	local damageValue = config:FindFirstChild("Damage")
	if damageValue and damageValue:IsA("NumberValue") then
		return damageValue.Value
	end

	return defaultDamage
end

function FakeToolService:Init(runtime)
	self._runtime = runtime
	self._defaultDamage = runtime.Config.Weapons.DefaultDamage
	self._boundConfigs = setmetatable({}, {__mode = "k"})
	self._carryConns = setmetatable({}, {__mode = "k"})
end

function FakeToolService:_attachConfig(config: Configuration, character: Model)
	prepareConfigParts(config)

	local handle = getConfigHandlePart(config)
	local arm = getArm(character)
	if handle == nil or not handle:IsA("BasePart") or arm == nil then
		return
	end

	local existingWeld = arm:FindFirstChild("FakeRightGrip")
	if existingWeld then
		existingWeld:Destroy()
	end

	local weld = Instance.new("Weld")
	weld.Name = "FakeRightGrip"
	weld.Part0 = arm
	weld.Part1 = handle

	local gripValue = config:FindFirstChild("Grip")
	weld.C1 = gripValue and gripValue:IsA("CFrameValue") and gripValue.Value or CFrame.new()

	local rightHand = character:FindFirstChild("RightHand")
	if rightHand and rightHand:IsA("BasePart") then
		local attachment = rightHand:FindFirstChild("RightGripAttachment")
		weld.C0 = attachment and attachment:IsA("Attachment") and attachment.CFrame or CFrame.new(0, -0.5, 0)
	else
		weld.C0 = CFrame.new(0, -1, 0)
	end

	weld.Parent = arm
end

function FakeToolService:_unequipAll(player: Player, keepConfig: Configuration?)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if character == nil or backpack == nil then
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Configuration") and child ~= keepConfig and isFakeToolConfiguration(player, child) then
			child.Parent = backpack
		end
	end

	local arm = getArm(character)
	if arm then
		local weld = arm:FindFirstChild("FakeRightGrip")
		if weld then
			weld:Destroy()
		end
	end
end

function FakeToolService:_handleEquip(player: Player, config: Configuration): boolean
	if not config:IsA("Configuration") or not isFakeToolConfiguration(player, config) then
		return false
	end
	if player:GetAttribute("CarryingAnimal") then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character == nil or humanoid == nil or humanoid.Health <= 0 then
		return false
	end

	humanoid:UnequipTools()
	self:_unequipAll(player, config)

	config.Parent = character
	self:_attachConfig(config, character)

	player:SetAttribute("IsArmed", true)

	return true
end

function FakeToolService:_handleUnequip(player: Player, config: Configuration): boolean
	if not config:IsA("Configuration") then
		return false
	end

	local ownedContainer = getOwnedContainer(player, config)
	if ownedContainer == nil and (player.Character == nil or config.Parent ~= player.Character) then
		return false
	end

	self:_unequipAll(player)

	local backpack = player:FindFirstChild("Backpack")
	if backpack and config.Parent == player.Character then
		config.Parent = backpack
	end

	player:SetAttribute("IsArmed", false)
	return true
end

function FakeToolService:_bindConfig(player: Player, config: Configuration)
	if self._boundConfigs[config] or not config:IsA("Configuration") or getOwnedContainer(player, config) == nil then
		return
	end
	self._boundConfigs[config] = true

	local equipRemote = ensureRemote(config, "Equipped")
	local unequipRemote = ensureRemote(config, "Unequipped")

	equipRemote.OnServerEvent:Connect(function(requestingPlayer)
		if requestingPlayer ~= player then
			return
		end

		self:_handleEquip(player, config)
	end)

	unequipRemote.OnServerEvent:Connect(function(requestingPlayer)
		if requestingPlayer ~= player then
			return
		end

		self:_handleUnequip(player, config)
	end)
end

function FakeToolService:BindConfig(player: Player, config: Configuration)
	if not config:IsA("Configuration") then
		return
	end

	-- Ensure configs restored from datastore are bindable immediately.
	local ownedContainer = getOwnedContainer(player, config)
	if ownedContainer == nil then
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			config.Parent = backpack
		end
	end

	self:_bindConfig(player, config)
end

function FakeToolService:EquipConfig(player: Player, config: Configuration)
	if not config:IsA("Configuration") then
		return
	end

	if self:_handleEquip(player, config) then
		return
	end

	task.spawn(function()
		local deadline = os.clock() + 5
		while os.clock() <= deadline do
			if config.Parent == nil then
				return
			end

			if self:_handleEquip(player, config) then
				return
			end

			task.wait(0.15)
		end
	end)
end

function FakeToolService:_scanPlayerContainers(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Configuration") then
				self:_bindConfig(player, child)
			end
		end
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Configuration") then
				self:_bindConfig(player, child)
			end
		end
	end
end

function FakeToolService:_bindPlayer(player: Player)
	local function bindContainer(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Configuration") then
				self:_bindConfig(player, child)
			end
		end)
	end

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack")
	bindContainer(backpack)

	local function onCharacterAdded(character: Model)
		bindContainer(character)
		self:_scanPlayerContainers(player)
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function(character)
		local backpackRef = player:FindFirstChild("Backpack")
		if backpackRef then
			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Configuration") and isFakeToolConfiguration(player, child) then
					child.Parent = backpackRef
				end
			end
		end

		player:SetAttribute("IsArmed", false)
	end)

	-- Hard-disable fake tool equip while carrying.
	if self._carryConns[player] == nil then
		self._carryConns[player] = player:GetAttributeChangedSignal("CarryingAnimal"):Connect(function()
			if player:GetAttribute("CarryingAnimal") == true then
				-- Unequip any attached configurations + standard tools.
				self:_unequipAll(player)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:UnequipTools()
				end
				player:SetAttribute("IsArmed", false)
			end
		end)
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end

	self:_scanPlayerContainers(player)
end

function FakeToolService:_handleActionRemote(player: Player, action, config)
	if type(action) ~= "string" or not config or not config:IsA("Configuration") then
		return
	end

	if not isFakeToolConfiguration(player, config) then
		return
	end

	if action == "Equip" then
		self:_handleEquip(player, config)
	elseif action == "Unequip" then
		self:_handleUnequip(player, config)
	end
end

function FakeToolService:Start()
	local remotes = self._runtime and self._runtime.Remotes
	local actionRemote = remotes and remotes.GetFakeToolRemote and remotes:GetFakeToolRemote()
	if actionRemote then
		actionRemote.OnServerEvent:Connect(function(player, action, config)
			self:_handleActionRemote(player, action, config)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_bindPlayer(player)
	end)
end

return FakeToolService
