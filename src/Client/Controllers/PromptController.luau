local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PromptController = {
	Name = "PromptController",
	Priority = 2,
}

local function getBaseFromDescendant(descendant, bases)
	local current = descendant
	while current and current.Parent ~= bases do
		current = current.Parent
	end

	if current and current:IsA("Folder") then
		return current
	end

	return nil
end

function PromptController:Init(runtime)
	self._player = Players.LocalPlayer
	self._bases = Workspace:WaitForChild("Bases")
	self._stealPromptRemote = runtime.Remotes:GetStealPromptRemote()
	self._pendingProducts = {}
	self._movementLock = nil
end

function PromptController:_refreshPrompts()
	for _, descendant in ipairs(self._bases:GetDescendants()) do
		if not descendant:IsA("ProximityPrompt") then
			continue
		end

		local role = descendant:GetAttribute("VisibilityRole")
		if role ~= "OwnerOnly" and role ~= "VisitorOnly" then
			continue
		end

		local base = getBaseFromDescendant(descendant, self._bases)
		if base == nil then
			continue
		end

		local promptActive = descendant:GetAttribute("PromptActive") ~= false
		local isOwner = base.Name == self._player.Name
		local shouldEnable = promptActive
			and ((role == "OwnerOnly" and isOwner) or (role == "VisitorOnly" and not isOwner))

		if descendant.Enabled ~= shouldEnable then
			descendant.Enabled = shouldEnable
		end
	end
end

function PromptController:_setMovementLocked(isLocked)
	local character = self._player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	if isLocked then
		if self._movementLock ~= nil then
			return
		end

		self._movementLock = {
			WalkSpeed = humanoid.WalkSpeed,
			AutoRotate = humanoid.AutoRotate,
			UseJumpPower = humanoid.UseJumpPower,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
		}

		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		if humanoid.UseJumpPower then
			humanoid.JumpPower = 0
		else
			humanoid.JumpHeight = 0
		end

		self._wsConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if humanoid.WalkSpeed ~= 0 then
				humanoid.WalkSpeed = 0
			end
		end)
		return
	end

	if self._movementLock == nil then
		return
	end

	if self._wsConnection then
		self._wsConnection:Disconnect()
		self._wsConnection = nil
	end

	humanoid.WalkSpeed = self._movementLock.WalkSpeed
	humanoid.AutoRotate = self._movementLock.AutoRotate
	-- Restore whichever jump mode the humanoid was already using.
	if self._movementLock.UseJumpPower then
		humanoid.JumpPower = self._movementLock.JumpPower
	else
		humanoid.JumpHeight = self._movementLock.JumpHeight
	end
	self._movementLock = nil
end

function PromptController:Start()
	if self._started then
		return
	end
	self._started = true

	self._stealPromptRemote.OnClientEvent:Connect(function(action, productId)
		if typeof(productId) ~= "number" then
			return
		end

		if action ~= "PromptPurchase" then
			return
		end

		self._pendingProducts[productId] = true
		self:_setMovementLocked(true)
		MarketplaceService:PromptProductPurchase(self._player, productId)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		if userId ~= self._player.UserId then
			return
		end
		if self._pendingProducts[productId] ~= true then
			return
		end

		self._pendingProducts[productId] = nil
		self:_setMovementLocked(false)
		self._stealPromptRemote:FireServer("PromptFinished", productId, isPurchased == true)
	end)

	self._player.CharacterAdded:Connect(function()
		self._movementLock = nil
	end)

	task.spawn(function()
		while true do
			self:_refreshPrompts()
			task.wait(0.15)
		end
	end)
end

return PromptController
