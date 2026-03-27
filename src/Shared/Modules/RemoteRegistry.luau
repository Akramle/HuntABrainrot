local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteRegistry = {}

local function ensureFolder()
	local folder = ReplicatedStorage:FindFirstChild("RuntimeRemotes")
	if folder == nil and RunService:IsServer() then
		folder = Instance.new("Folder")
		folder.Name = "RuntimeRemotes"
		folder.Parent = ReplicatedStorage
	end
	return (folder or ReplicatedStorage:WaitForChild("RuntimeRemotes")) :: Folder
end

local function ensureRemoteEvent(folder: Instance, remoteName: string): RemoteEvent
	local remote = folder:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteEvent") and RunService:IsServer() then
		remote:Destroy()
		remote = nil
	end

	if remote == nil and RunService:IsServer() then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
	end

	return (remote or folder:WaitForChild(remoteName)) :: RemoteEvent
end

local function ensureRemoteFunction(folder: Instance, remoteName: string): RemoteFunction
	local remote = folder:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteFunction") and RunService:IsServer() then
		remote:Destroy()
		remote = nil
	end

	if remote == nil and RunService:IsServer() then
		remote = Instance.new("RemoteFunction")
		remote.Name = remoteName
		remote.Parent = folder
	end

	return (remote or folder:WaitForChild(remoteName)) :: RemoteFunction
end

function RemoteRegistry:GetEffectsRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "GameplayEffects")
end

function RemoteRegistry:GetFakeToolRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "FakeToolAction")
end

function RemoteRegistry:GetInventoryLayoutRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "InventoryLayoutSync")
end

function RemoteRegistry:GetStealPromptRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "StealAnimalPrompt")
end

function RemoteRegistry:GetSoundRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "SoundAction")
end

function RemoteRegistry:GetAdminRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "AdminAction")
end

function RemoteRegistry:GetHidingRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "HidingAction")
end

function RemoteRegistry:GetCarryAnimalRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "CarryAnimalAction")
end

function RemoteRegistry:GetUpgradeRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "UpgradeEvent")
end

function RemoteRegistry:GetAreaUnlockRemote()
	local folder = ensureFolder()
	return ensureRemoteFunction(folder, "AreaUnlockAction")
end

function RemoteRegistry:GetConfigRemote()
	local folder = ensureFolder()
	return ensureRemoteFunction(folder, "GetConfigInfo")
end

function RemoteRegistry:GetAnnouncementRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "AnnouncementAction")
end

function RemoteRegistry:GetEventRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "EventAction")
end

function RemoteRegistry:GetCodeRemote()
	local folder = ensureFolder()
	return ensureRemoteFunction(folder, "CodeRedeemAction")
end

function RemoteRegistry:GetNotificationRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "NotificationAction")
end

function RemoteRegistry:GetGearRemote()
	local folder = ensureFolder()
	return ensureRemoteEvent(folder, "GearAction")
end

return RemoteRegistry
