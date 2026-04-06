local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BaseUpgradeController = {
	Name = "BaseUpgradeController",
	Priority = 0,
}

local function getBaseFromDescendant(descendant: Instance, bases: Instance): Instance?
	local current = descendant
	while current and current.Parent ~= bases do
		current = current.Parent
	end
	return current
end

function BaseUpgradeController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetBaseUpgradeRemote()
	self._watchedBases = {}
	self._baseConnections = {}
	self._guiEnabledState = setmetatable({}, {__mode = "k"})
end

function BaseUpgradeController:_isLocalPlayerOwner(base: Instance): boolean
	local config = base:FindFirstChild("Config")
	local ownerValue = config and config:FindFirstChild("PlayerUsername")
	if ownerValue and ownerValue:IsA("StringValue") and ownerValue.Value ~= "" then
		return ownerValue.Value == self._player.Name
	end
	return base.Name == self._player.Name
end

function BaseUpgradeController:_setLocalEnabledState(desc, shouldEnable: boolean)
	if shouldEnable then
		local previousEnabled = self._guiEnabledState[desc]
		if previousEnabled ~= nil then
			desc.Enabled = previousEnabled
			self._guiEnabledState[desc] = nil
		end
		return
	end

	if self._guiEnabledState[desc] == nil then
		self._guiEnabledState[desc] = desc.Enabled
	end
	desc.Enabled = false
end

function BaseUpgradeController:_applyUpgradeLocalVisibility(upgradeProp: Instance, bases: Instance)
	local base = getBaseFromDescendant(upgradeProp, bases)
	if not base then return end

	local isOwner = self:_isLocalPlayerOwner(base)

	for _, desc in ipairs(upgradeProp:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.LocalTransparencyModifier = isOwner and 0 or 1
		elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") or desc:IsA("ProximityPrompt") then
			self:_setLocalEnabledState(desc, isOwner)
		end
	end
end

function BaseUpgradeController:_bindUpgradeButton(base: Instance, levelStr: string)
	local levelFolder = base:FindFirstChild(levelStr)
	if not levelFolder then return end

	local upgradeProp = levelFolder:FindFirstChild("Upgrade")
	if not upgradeProp then return end

	local screen = upgradeProp:FindFirstChild("Screen")
	local surfaceGui = screen and screen:FindFirstChild("SurfaceGui")
	local btn = surfaceGui and surfaceGui:FindFirstChild("btn", true)

	if btn and btn:IsA("GuiButton") then
		if not btn:GetAttribute("BaseUpgradeBound") then
			btn:SetAttribute("BaseUpgradeBound", true)
			
			btn.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if self:_isLocalPlayerOwner(base) then
						-- The button is inside levelStr (e.g. "1"), so we are requesting to unlock levelStr + 1 (e.g. 2)
						self._remote:FireServer(tonumber(levelStr) + 1)
					end
				end
			end)
		end
	end
end

function BaseUpgradeController:_bindAllUpgradeButtons(base: Instance)
	for i = 1, 5 do
		self:_bindUpgradeButton(base, tostring(i))
	end
end

function BaseUpgradeController:_applyBaseUpgradeVisibility(base: Instance, bases: Instance)
	for _, desc in ipairs(base:GetDescendants()) do
		if desc.Name == "Upgrade" then
			self:_applyUpgradeLocalVisibility(desc, bases)
		end
	end
end

function BaseUpgradeController:_unwatchBase(base: Instance)
	local connections = self._baseConnections[base]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	self._baseConnections[base] = nil
	self._watchedBases[base] = nil
end

function BaseUpgradeController:_watchBase(base: Instance, bases: Instance)
	if self._watchedBases[base] then
		return
	end
	self._watchedBases[base] = true

	local connections = {}
	self._baseConnections[base] = connections

	self:_bindAllUpgradeButtons(base)
	self:_applyBaseUpgradeVisibility(base, bases)

	table.insert(connections, base:GetPropertyChangedSignal("Name"):Connect(function()
		self:_applyBaseUpgradeVisibility(base, bases)
	end))

	local config = base:FindFirstChild("Config")
	local ownerValue = config and config:FindFirstChild("PlayerUsername")
	if ownerValue and ownerValue:IsA("StringValue") then
		table.insert(connections, ownerValue:GetPropertyChangedSignal("Value"):Connect(function()
			self:_applyBaseUpgradeVisibility(base, bases)
		end))
	end

	if config then
		table.insert(connections, config.ChildAdded:Connect(function(child)
			if child.Name == "PlayerUsername" and child:IsA("StringValue") then
				table.insert(connections, child:GetPropertyChangedSignal("Value"):Connect(function()
					self:_applyBaseUpgradeVisibility(base, bases)
				end))
				self:_applyBaseUpgradeVisibility(base, bases)
			end
		end))
	end

	table.insert(connections, base.DescendantAdded:Connect(function(desc)
		if desc.Name == "Upgrade" then
			local levelFolder = desc.Parent
			if levelFolder then
				self:_bindUpgradeButton(base, levelFolder.Name)
			end
			self:_applyUpgradeLocalVisibility(desc, bases)
			return
		end

		local parent = desc.Parent
		if parent and parent.Name == "Upgrade" then
			self:_applyUpgradeLocalVisibility(parent, bases)
		end
	end))

	table.insert(connections, base.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_unwatchBase(base)
		end
	end))
end

function BaseUpgradeController:Start()
	-- Wait for bases folder
	local bases = Workspace:WaitForChild("Bases", 10)
	if not bases then return end

	for _, base in ipairs(bases:GetChildren()) do
		if base:IsA("Model") or base:IsA("Folder") then
			self:_watchBase(base, bases)
		end
	end

	bases.ChildAdded:Connect(function(base)
		if base:IsA("Model") or base:IsA("Folder") then
			self:_watchBase(base, bases)
		end
	end)

	bases.ChildRemoved:Connect(function(base)
		self:_unwatchBase(base)
	end)
end

return BaseUpgradeController
