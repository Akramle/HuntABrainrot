local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModuleLoader = require(ReplicatedStorage:WaitForChild("ModuleLoader"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteRegistry"))

local runtime = {
	Config = {},
	Remotes = RemoteRegistry,
	Controllers = {},
	Player = Players.LocalPlayer,
}

-- 1. Load Local Shared Config
for k, v in pairs(GameConfig) do
	runtime.Config[k] = v
end

-- 2. Fetch Sanitized Config from Server
local configRemote = RemoteRegistry:GetConfigRemote()
local serverConfig = configRemote:InvokeServer()
if serverConfig then
	for k, v in pairs(serverConfig) do
		runtime.Config[k] = v
	end
end

function runtime:GetController(name)
	return self.Controllers[name]
end

-- 3. Initialize Controllers
local loader = ModuleLoader.new({
	contextName = "Client",
	registry = runtime.Controllers,
})

loader:LoadFolder(script.Parent:WaitForChild("Controllers"), runtime)
