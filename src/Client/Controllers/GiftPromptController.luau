local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local GiftPromptController = {
	Name = "GiftPromptController",
	Priority = 10,
}

function GiftPromptController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetGiftRemote()
	self._prompts = {} -- [player] = ProximityPrompt
end

function GiftPromptController:_createPrompt(targetPlayer: Player)
	if targetPlayer == self._player then return end
	
	local character = targetPlayer.Character
	if not character then return end
	
	local hrp = character:WaitForChild("HumanoidRootPart", 5)
	if not hrp then return end
	
	-- Cleanup existing if any
	if self._prompts[targetPlayer] then
		self._prompts[targetPlayer]:Destroy()
	end
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Gift Animal"
	prompt.ObjectText = targetPlayer.Name
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Enabled = false -- Default disabled, we toggle it locally
	prompt.Parent = hrp
	
	prompt.Triggered:Connect(function()
		self._remote:FireServer("RequestGift", targetPlayer)
	end)
	
	self._prompts[targetPlayer] = prompt
end

function GiftPromptController:_updatePromptsVisibility()
	local canGift = (self._player:GetAttribute("HasAnimal") == true) or (self._player:GetAttribute("CarryingAnimal") == true)
	
	for player, prompt in pairs(self._prompts) do
		if prompt.Parent then
			prompt.Enabled = canGift
		else
			self._prompts[player] = nil
		end
	end
end

function GiftPromptController:Start()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= self._player then
			player.CharacterAdded:Connect(function()
				task.wait(1) -- Wait for HRP
				self:_createPrompt(player)
			end)
			if player.Character then self:_createPrompt(player) end
		end
	end
	
	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(1)
			self:_createPrompt(player)
		end)
	end)
	
	-- Clean up on leaving
	Players.PlayerRemoving:Connect(function(player)
		if self._prompts[player] then
			self._prompts[player]:Destroy()
			self._prompts[player] = nil
		end
	end)
	
	-- Monitor state to toggle prompts
	self._player:GetAttributeChangedSignal("HasAnimal"):Connect(function()
		self:_updatePromptsVisibility()
	end)
	
	self._player:GetAttributeChangedSignal("CarryingAnimal"):Connect(function()
		self:_updatePromptsVisibility()
	end)
	
	-- Initial check
	self:_updatePromptsVisibility()
	
	-- Periodic cleanup/re-sync
	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= self._player and not self._prompts[player] then
					if player.Character then self:_createPrompt(player) end
				end
			end
			self:_updatePromptsVisibility()
			task.wait(5)
		end
	end)
end

return GiftPromptController
