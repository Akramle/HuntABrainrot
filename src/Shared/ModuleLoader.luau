local ModuleLoader = {}
ModuleLoader.__index = ModuleLoader

local function collectModuleScripts(root: Instance, recursive: boolean): {ModuleScript}
	local scripts = {}
	local source = recursive and root:GetDescendants() or root:GetChildren()

	for _, child in ipairs(source) do
		if child:IsA("ModuleScript") then
			table.insert(scripts, child)
		end
	end

	return scripts
end

local function sortRecords(a, b)
	if a.Priority == b.Priority then
		return a.Path < b.Path
	end

	return a.Priority < b.Priority
end

function ModuleLoader.new(options)
	local self = setmetatable({}, ModuleLoader)
	self._registry = options and options.registry or {}
	self._contextName = options and options.contextName or "Runtime"
	return self
end

function ModuleLoader:LoadFolder(root: Instance, context, options)
	assert(root and root:IsA("Instance"), "[ModuleLoader] LoadFolder requires a valid root Instance")

	local recursive = if options and options.recursive ~= nil then options.recursive else false
	local records = {}
	local runtime = context or {}

	for _, moduleScript in ipairs(collectModuleScripts(root, recursive)) do
		local ok, loadedModule = pcall(require, moduleScript)
		if not ok then
			error(string.format("[%s] Failed to require %s: %s", self._contextName, moduleScript:GetFullName(), tostring(loadedModule)))
		end

		if type(loadedModule) ~= "table" then
			error(string.format("[%s] %s must return a table", self._contextName, moduleScript:GetFullName()))
		end

		local moduleName = loadedModule.Name or moduleScript.Name
		if self._registry[moduleName] ~= nil then
			error(string.format("[%s] Duplicate module name '%s'", self._contextName, moduleName))
		end

		loadedModule.Name = moduleName
		self._registry[moduleName] = loadedModule

		table.insert(records, {
			Module = loadedModule,
			Priority = loadedModule.Priority or 0,
			Path = moduleScript:GetFullName(),
		})
	end

	runtime.Registry = self._registry
	if runtime.Get == nil then
		function runtime:Get(name)
			return self.Registry[name]
		end
	end

	table.sort(records, sortRecords)

	for _, record in ipairs(records) do
		local init = record.Module.Init
		if type(init) == "function" then
			local ok, err = pcall(function()
				record.Module:Init(runtime)
			end)
			if not ok then
				error(string.format("[%s] Init failed for %s: %s", self._contextName, record.Path, tostring(err)))
			end
		end
	end

	for _, record in ipairs(records) do
		local start = record.Module.Start
		if type(start) == "function" then
			local ok, err = pcall(function()
				record.Module:Start(runtime)
			end)
			if not ok then
				error(string.format("[%s] Start failed for %s: %s", self._contextName, record.Path, tostring(err)))
			end
		end
	end

	return self._registry, records
end

return ModuleLoader
