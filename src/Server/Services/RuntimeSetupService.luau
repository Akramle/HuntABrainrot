local Workspace = game:GetService("Workspace")

local RuntimeSetupService = {
	Name = "RuntimeSetupService",
	Priority = -100,
}

local function ensureFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder :: Folder
end

function RuntimeSetupService:Init(runtime)
	local animalsFolder = ensureFolder(Workspace, "Animals")
	for _, rarity in ipairs(runtime.Config.Animals.RarityOrder) do
		ensureFolder(animalsFolder, rarity)
	end

	local dropsFolder = ensureFolder(Workspace, "Drops")
	local remotes = runtime.Remotes
	remotes:GetEffectsRemote()
	remotes:GetFakeToolRemote()
	remotes:GetStealPromptRemote()
	remotes:GetCarryAnimalRemote()

	runtime.WorldFolders = {
		Animals = animalsFolder,
		Drops = dropsFolder,
	}
end

return RuntimeSetupService
