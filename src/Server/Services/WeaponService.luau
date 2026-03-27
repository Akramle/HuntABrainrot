local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local WeaponService = {
	Name = "WeaponService",
	Priority = -60,
}

local function findToolOwner(tool: Tool): Player?
	local parent = tool.Parent
	if parent == nil then
		return nil
	end

	if parent:IsA("Backpack") then
		local owner = parent.Parent
		if owner and owner:IsA("Player") then
			return owner
		end
	elseif parent:IsA("Model") then
		return Players:GetPlayerFromCharacter(parent)
	end

	return nil
end

function WeaponService:Init(runtime)
	self._tag = runtime.Config.Weapons.Tag
	self._defaultDamage = runtime.Config.Weapons.DefaultDamage
	self._boundTools = setmetatable({}, {__mode = "k"})
end

function WeaponService:_applyWeaponState(player: Player, tool: Tool)
	-- While carrying a captured animal, the player must not be able to attack.
	if player:GetAttribute("CarryingAnimal") then
		player:SetAttribute("IsArmed", false)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
		return
	end

	player:SetAttribute("IsArmed", true)
end

function WeaponService:_resetWeaponState(player: Player)
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and CollectionService:HasTag(child, self._tag) then
				self:_applyWeaponState(player, child)
				return
			end
		end
	end

	player:SetAttribute("IsArmed", false)
end
function WeaponService:_bindTool(tool: Tool)
	if self._boundTools[tool] then
		return
	end
	self._boundTools[tool] = true

	tool.Equipped:Connect(function()
		local player = findToolOwner(tool)
		if player then
			self:_applyWeaponState(player, tool)
		end
	end)

	tool.Unequipped:Connect(function()
		local player = findToolOwner(tool)
		if player then
			self:_resetWeaponState(player)
		end
	end)

	tool.Destroying:Connect(function()
		local player = findToolOwner(tool)
		self._boundTools[tool] = nil
		if player then
			task.defer(function()
				self:_resetWeaponState(player)
			end)
		end
	end)
end

function WeaponService:Start()
	for _, instance in ipairs(CollectionService:GetTagged(self._tag)) do
		if instance:IsA("Tool") then
			self:_bindTool(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(self._tag):Connect(function(instance)
		if instance:IsA("Tool") then
			self:_bindTool(instance)
		end
	end)

	local function bindPlayer(player: Player)
		player.CharacterRemoving:Connect(function()
			self:_resetWeaponState(player)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
end

return WeaponService
