local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local PlayerAnimationController = {
	Name = "PlayerAnimationController",
	Priority = 1,
}

function PlayerAnimationController:Init(runtime)
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._hitAnimation = Instance.new("Animation")
	self._hitAnimation.AnimationId = runtime.Config.Combat.HitAnimationId
	self._holdAnimation = Instance.new("Animation")
	self._holdAnimation.AnimationId = runtime.Config.Combat.HoldAnimationId
	self._hitTrack = nil
	self._holdTrack = nil
	self._characterConnections = {}
end

function PlayerAnimationController:_disconnectCharacterConnections()
	for _, connection in ipairs(self._characterConnections) do
		connection:Disconnect()
	end

	table.clear(self._characterConnections)
end

function PlayerAnimationController:_getAnimator(character: Model)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator
end

function PlayerAnimationController:_stopTrack(trackName: string)
	local track = self[trackName]
	if track then
		track:Stop()
		track:Destroy()
		self[trackName] = nil
	end
end

function PlayerAnimationController:_playTrack(
	trackName: string,
	animation: Animation,
	priority: Enum.AnimationPriority,
	fadeTime: number?,
	looped: boolean?
)
	local character = self._player.Character
	local animator = self:_getAnimator(character)
	if animator == nil then
		return nil
	end

	self:_stopTrack(trackName)

	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped == true
	track:Play(fadeTime or 0.1)
	self[trackName] = track

	return track
end

function PlayerAnimationController:_hasEquippedAnimalTool(character: Model): boolean
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			if CollectionService:HasTag(child, "Animal") then
				return true
			end

			local rarity = child:GetAttribute("Rarity")
			if typeof(rarity) == "string" and rarity ~= "" then
				return true
			end
		end
	end

	return false
end

function PlayerAnimationController:RefreshHoldAnimation()
	local character = self._player.Character
	if character == nil then
		self:_stopTrack("_holdTrack")
		return
	end

	if self._player:GetAttribute("CarryingAnimal") == true or self:_hasEquippedAnimalTool(character) then
		self:_playTrack("_holdTrack", self._holdAnimation, Enum.AnimationPriority.Action4, 0.1, true)
	else
		self:_stopTrack("_holdTrack")
	end
end

function PlayerAnimationController:PlayHitAnimation()
	self:_playTrack("_hitTrack", self._hitAnimation, Enum.AnimationPriority.Action4, 0.05, false)
end

function PlayerAnimationController:_bindCharacter(character: Model)
	self:_disconnectCharacterConnections()

	local function bindTool(tool: Tool)
		table.insert(self._characterConnections, tool.Equipped:Connect(function()
			self:RefreshHoldAnimation()
		end))
		table.insert(self._characterConnections, tool.Unequipped:Connect(function()
			self:RefreshHoldAnimation()
		end))
		table.insert(self._characterConnections, tool:GetAttributeChangedSignal("Rarity"):Connect(function()
			self:RefreshHoldAnimation()
		end))
	end

	table.insert(self._characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") or child:IsA("Configuration") then
			if child:IsA("Tool") then
				bindTool(child)
			end
			self:RefreshHoldAnimation()
		end
	end))

	table.insert(self._characterConnections, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") or child:IsA("Configuration") then
			self:RefreshHoldAnimation()
		end
	end))

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end

	self:RefreshHoldAnimation()
end

function PlayerAnimationController:Start()
	if self._started then
		return
	end
	self._started = true

	self._player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end)

	-- Carry state should affect hold animation even without equipped tools.
	self._player:GetAttributeChangedSignal("CarryingAnimal"):Connect(function()
		self:RefreshHoldAnimation()
	end)

	self._player.CharacterRemoving:Connect(function()
		self:_disconnectCharacterConnections()
		self:_stopTrack("_holdTrack")
		self:_stopTrack("_hitTrack")
	end)

	if self._player.Character then
		self:_bindCharacter(self._player.Character)
	end
end

return PlayerAnimationController
