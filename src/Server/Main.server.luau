local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ModuleLoader = require(ReplicatedStorage:WaitForChild("ModuleLoader"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local ServerConfig = require(script.Parent:WaitForChild("Config"):WaitForChild("ServerConfig"))
local RemoteRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RemoteRegistry"))

-- Merge Configs for Server
local Config = {}
for k, v in pairs(GameConfig) do Config[k] = v end
for k, v in pairs(ServerConfig) do
	if type(v) == "table" and type(Config[k]) == "table" then
		for subK, subV in pairs(v) do
			Config[k][subK] = subV
		end
	else
		Config[k] = v
	end
end

local runtime = {
	Config = table.freeze(Config),
	Remotes = RemoteRegistry,
	Services = {},
}

function runtime:GetService(name)
	return self.Services[name]
end

local loader = ModuleLoader.new({
	contextName = "Server",
	registry = runtime.Services,
})

loader:LoadFolder(ServerScriptService:WaitForChild("Services"), runtime)
