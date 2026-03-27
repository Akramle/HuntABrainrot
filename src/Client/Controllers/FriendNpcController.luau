local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local FriendNpcController = {
	Name = "FriendNpcController",
	Priority = 10,
}

local IDLE_ANIMATIONS = {
	"rbxassetid://110827513253097",
	"rbxassetid://76662287081933",
	"rbxassetid://140216265113335",
}

local FALLBACK_IDS = {1, 156, 20162, 10214224}

function FriendNpcController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._friendIds = {}
end

function FriendNpcController:_getFriends()
	local success, result = pcall(function()
		return Players:GetFriendsAsync(self._player.UserId)
	end)

	if not success then
		warn("[FriendNpcController] Failed to fetch friends:", result)
		return FALLBACK_IDS
	end

	local ids = {}
	local page = result

	while true do
		for _, item in ipairs(page:GetCurrentPage()) do
			table.insert(ids, item.Id)
		end

		if page.IsFinished or #ids >= 100 then
			break
		end

		local ok = pcall(function() page:AdvanceToNextPageAsync() end)
		if not ok then break end
	end

	if #ids == 0 then return FALLBACK_IDS end
	return ids
end

function FriendNpcController:_applyFriendToLocalNpc(npc: Model, userId: number)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local success, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)

	if success and description then
		-- Applying locally on the client only affects this player's view
		pcall(function()
			humanoid:ApplyDescription(description)
		end)
	end

	-- Play random idle animation locally
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animId = IDLE_ANIMATIONS[math.random(1, #IDLE_ANIMATIONS)]
	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play()
end

function FriendNpcController:_setupNpc(npc: Model)
	if #self._friendIds == 0 then return end
	
	-- We create a local-only visual override
	-- Original NPC remains for physics/logic, but we hide its parts locally
	-- and create a local clone for visual representation.
	
	local randomFriendId = self._friendIds[math.random(1, #self._friendIds)]

	-- 1. Copy the "Toggle" prompt before doing anything
	local togglePrompt = npc:FindFirstChild("Toggle", true)
	local promptClone = nil
	if togglePrompt and togglePrompt:IsA("ProximityPrompt") then
		promptClone = togglePrompt:Clone()
	end

	-- 2. Hide the original NPC's visual parts for this client
	for _, part in ipairs(npc:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.Transparency = 1
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
			end
		end
	end

	-- 3. Create a Local Clone for visuals
	npc.Archivable = true
	local localVisual = npc:Clone()
	npc.Archivable = false
	
	-- Clear prompts and scripts from local visual to avoid double triggers/logic
	for _, child in ipairs(localVisual:GetDescendants()) do
		if child:IsA("LuaSourceContainer") or child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end

	-- Show parts of the local visual
	for _, part in ipairs(localVisual:GetDescendants()) do
		if part:IsA("BasePart") or part:IsA("Decal") then
			if part.Name == "HumanoidRootPart" then
				part.Transparency = 1
			else
				part.Transparency = 0
			end
		end
	end

	localVisual.Name = "LocalVisual"
	localVisual.Parent = npc
	
	-- Remove the NPC tag from the visual clone to avoid recursive setup
	CollectionService:RemoveTag(localVisual, "NPC")

	-- 4. Weld the local visual to the original NPC
	local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
	local localRoot = localVisual:FindFirstChild("HumanoidRootPart") or localVisual.PrimaryPart
	if root and localRoot then
		localRoot.Anchored = false
		localRoot.CanCollide = false
		localRoot.CFrame = root.CFrame
		
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = localRoot
		weld.Parent = localRoot
	end

	-- 5. Restore the Prompt on the original NPC (keep it visible/interactive)
	-- Ensure the original prompt is still enabled and visible
	if togglePrompt then
		togglePrompt.Enabled = true
		-- Keep transparency of the part it's in if needed, but prompts usually don't care
	end

	-- 6. Skin the Local Visual
	self:_applyFriendToLocalNpc(localVisual, randomFriendId)
end

function FriendNpcController:Start()
	task.spawn(function()
		self._friendIds = self:_getFriends()
		
		local function onNpcAdded(npc: Model)
			if npc:IsA("Model") then
				-- Wait for NPC to be fully loaded
				npc:WaitForChild("Humanoid", 10)
				self:_setupNpc(npc)
			end
		end

		for _, npc in ipairs(CollectionService:GetTagged("NPC")) do
			onNpcAdded(npc)
		end

		CollectionService:GetInstanceAddedSignal("NPC"):Connect(onNpcAdded)
	end)
end

return FriendNpcController
