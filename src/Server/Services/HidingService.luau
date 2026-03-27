local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local HidingService = {
	Name = "HidingService",
	Priority = -15,
}

function HidingService:Init(runtime)
	self._runtime = runtime
	self._remote = runtime.Remotes:GetHidingRemote()
	self._spots = {} -- [model] = player
	self._playerHidingSpots = {} -- [player] = model
end

function HidingService:_setupHidingSpot(model)
	if self._spots[model] ~= nil then return end

	local interactPart = model:FindFirstChild("Interact")
	if not interactPart then return end

	local prompt = interactPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end

	self._spots[model] = false -- false means empty
	
	prompt.Triggered:Connect(function(player)
		local character = player.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		local currentSpotForPlayer = self._playerHidingSpots[player]

		-- Player is already hiding in THIS spot -> Leave
		if currentSpotForPlayer == model then
			self:_leaveHidingSpot(player, model, prompt)
			return
		end

		-- Spot is occupied by someone else
		if self._spots[model] then
			return
		end

		-- Player is hiding somewhere else, leave that one first
		if currentSpotForPlayer then
			local oldPrompt = currentSpotForPlayer:FindFirstChild("Interact"):FindFirstChildWhichIsA("ProximityPrompt")
			self:_leaveHidingSpot(player, currentSpotForPlayer, oldPrompt)
		end

		-- Enter this spot
		self:_enterHidingSpot(player, model, prompt)
	end)
end

function HidingService:_enterHidingSpot(player, model, prompt)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Mark as occupied
	self._spots[model] = player
	self._playerHidingSpots[player] = model

	-- Update Prompt
	prompt.ActionText = "Leave"
	prompt.ObjectText = "Hiding Spot"

	-- Position Player inside the hole (only head above)
	local targetCFrame = model.PrimaryPart and model.PrimaryPart.CFrame or model:GetPivot()
	rootPart.CFrame = targetCFrame * CFrame.new(0, -1.5, 0)
	rootPart.Anchored = true
	
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		-- Prevent fall animation by forcing platform stand / physics state
		humanoid.PlatformStand = true
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	player:SetAttribute("IsHiding", true)
	self._remote:FireClient(player, true, model)
end

function HidingService:_leaveHidingSpot(player, model, prompt)
	if self._spots[model] ~= player then return end

	-- Mark as empty
	self._spots[model] = false
	self._playerHidingSpots[player] = nil

	-- Restore Prompt
	if prompt then
		prompt.ActionText = "Hide"
		prompt.ObjectText = "Hole"
	end

	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			rootPart.Anchored = false
			-- Pop them slightly up so they don't clip inside the hole mesh
			rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 3, 0)
		end
		
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			local upgradeService = self._runtime:GetService("UpgradeService")
			if upgradeService then
				player:SetAttribute("IsHiding", false) -- Set before update to allow WS to be applied
				upgradeService:UpdatePlayerWalkspeed(player)
			else
				humanoid.WalkSpeed = 16 
			end
			
			humanoid.JumpPower = 50
			-- Restore normal state
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	self._remote:FireClient(player, false, model)
end

function HidingService:Start()
	for _, model in ipairs(CollectionService:GetTagged("HidingSpot")) do
		self:_setupHidingSpot(model)
	end

	CollectionService:GetInstanceAddedSignal("HidingSpot"):Connect(function(model)
		self:_setupHidingSpot(model)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local spot = self._playerHidingSpots[player]
		if spot then
			local prompt = spot:FindFirstChild("Interact") and spot.Interact:FindFirstChildWhichIsA("ProximityPrompt")
			self:_leaveHidingSpot(player, spot, prompt)
		end
	end)
end

return HidingService