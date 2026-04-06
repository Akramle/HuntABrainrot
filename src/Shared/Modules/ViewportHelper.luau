local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ViewportHelper = {}

local DEFAULT_OPTIONS = {
	Zoom = 1.15,
	CamPitch = -15,
	CamYaw = 35,
	LookAtYOffset = 0,
	Ambient = Color3.new(1, 1, 1),
	LightColor = Color3.new(1, 1, 1),
	OutlineColor = Color3.fromRGB(255, 255, 255),
	OutlineTransparency = 0,
	FieldOfView = 70,
	SpinSpeed = 0,
	AutoPlayAnimation = true,
}

local states = setmetatable({}, { __mode = "k" })
local spinConnection = nil

local function mergeOptions(options)
	local merged = table.clone(DEFAULT_OPTIONS)
	if type(options) == "table" then
		for k, v in pairs(options) do
			merged[k] = v
		end
	end
	return merged
end

local function getInstancePivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end
	return nil
end

local function pivotInstance(instance, targetCFrame)
	if instance:IsA("Model") then
		instance:PivotTo(targetCFrame)
	elseif instance:IsA("BasePart") then
		instance.CFrame = targetCFrame
	end
end

local function getViewportParts(root)
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function getNumberAttribute(source, attributeName, fallback)
	if source == nil then return fallback end
	local value = source:GetAttribute(attributeName)
	if value == nil then return fallback end
	local num = tonumber(value)
	if num == nil then return fallback end
	return num
end

local function resolveDisplayClone(source)
	if source:IsA("Tool") then
		local sourceVisual = source:FindFirstChild(source.Name)
		if sourceVisual and (sourceVisual:IsA("Model") or sourceVisual:IsA("BasePart")) then
			return sourceVisual:Clone(), sourceVisual
		end

		local handleVisual = source:FindFirstChild("Handle", true)
		if handleVisual and (handleVisual:IsA("Model") or handleVisual:IsA("BasePart")) then
			return handleVisual:Clone(), handleVisual
		end
	end

	if source:IsA("Configuration") then
		local handleVisual = source:FindFirstChild("Handle", true)
		if handleVisual and (handleVisual:IsA("Model") or handleVisual:IsA("BasePart")) then
			return handleVisual:Clone(), handleVisual
		end

		for _, descendant in ipairs(source:GetDescendants()) do
			if descendant:IsA("Model") or descendant:IsA("BasePart") then
				return descendant:Clone(), descendant
			end
		end
	end

	if source:IsA("Model") or source:IsA("BasePart") then
		return source:Clone(), source
	end

	return source:Clone(), nil
end

local function alignDisplay(displayClone, source, sourceVisual)
	if source == nil then return end

	local displayPivot = getInstancePivot(displayClone)
	if displayPivot == nil then return end

	if (source:IsA("Configuration") or source:IsA("Tool")) and not CollectionService:HasTag(source, "Animal") then
		local gripRotation = CFrame.new()
		local gripValue = source:FindFirstChild("Grip")
		if gripValue and gripValue:IsA("CFrameValue") then
			local gripCFrame = gripValue.Value
			gripRotation = (gripCFrame - gripCFrame.Position):Inverse()
		elseif source:IsA("Tool") then
			gripRotation = (source.Grip - source.Grip.Position):Inverse()
		end

		local modelRotX = getNumberAttribute(source, "ViewportModelRotX", 0)
		local modelRotY = getNumberAttribute(source, "ViewportModelRotY", 90)
		local modelRotZ = getNumberAttribute(source, "ViewportModelRotZ", 0)
		local previewRotation = gripRotation * CFrame.Angles(math.rad(modelRotX), math.rad(modelRotY), math.rad(modelRotZ))
		pivotInstance(displayClone, CFrame.new(displayPivot.Position) * previewRotation)
		return
	end

	if sourceVisual == nil then return end
	if not CollectionService:HasTag(source, "Animal") then return end

	local handle = source:FindFirstChild("Handle")
	if handle == nil or not handle:IsA("BasePart") then return end

	local sourcePivot = getInstancePivot(sourceVisual)
	if sourcePivot == nil then return end

	local sourceRotation = sourcePivot - sourcePivot.Position
	local handleRotation = handle.CFrame - handle.CFrame.Position
	local visualFromHandle = handleRotation:ToObjectSpace(sourceRotation)
	pivotInstance(displayClone, CFrame.new(displayPivot.Position) * visualFromHandle)
end

local function sanitizeClone(displayClone)
	for _, child in ipairs(displayClone:GetDescendants()) do
		if child:IsA("Script")
			or child:IsA("LocalScript")
			or child:IsA("Sound")
			or child:IsA("BillboardGui")
			or child:IsA("ProximityPrompt")
			or child:IsA("Trail")
			or child:IsA("ParticleEmitter")
			or child:IsA("Animator")
		then
			child:Destroy()
		elseif child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
		end
	end
end

local function resolveIdleAnimationId(displayClone, source)
	if source then
		local sourceIdle = source:GetAttribute("IdleAnimationId")
		if typeof(sourceIdle) == "string" and sourceIdle ~= "" then
			return sourceIdle
		end
	end

	local cloneIdle = displayClone:GetAttribute("IdleAnimationId")
	if typeof(cloneIdle) == "string" and cloneIdle ~= "" then
		return cloneIdle
	end

	local visualModel = displayClone:FindFirstChildWhichIsA("Model")
	local visualIdle = visualModel and visualModel:GetAttribute("IdleAnimationId")
	if typeof(visualIdle) == "string" and visualIdle ~= "" then
		return visualIdle
	end

	return nil
end

local function playIdleAnimation(displayClone, source)
	local idleAnimationId = resolveIdleAnimationId(displayClone, source)
	if typeof(idleAnimationId) ~= "string" or idleAnimationId == "" then
		return nil, nil
	end

	local animator = displayClone:FindFirstChildWhichIsA("Animator", true)
	if animator == nil then
		local humanoid = displayClone:FindFirstChildWhichIsA("Humanoid", true)
		if humanoid then
			animator = humanoid:FindFirstChildOfClass("Animator")
			if animator == nil then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
		end
	end

	if animator == nil then
		local animationController = displayClone:FindFirstChild("AnimationController", true)
		if animationController == nil then
			local model = displayClone:IsA("Model") and displayClone or displayClone:FindFirstChildWhichIsA("Model")
			if model then
				animationController = Instance.new("AnimationController")
				animationController.Parent = model
			end
		end

		if animationController then
			animator = animationController:FindFirstChildOfClass("Animator")
			if animator == nil then
				animator = Instance.new("Animator")
				animator.Parent = animationController
			end
		end
	end

	if animator == nil then
		return nil, nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = idleAnimationId
	animation.Parent = displayClone

	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play()
	return track, animation
end

local function ensureSpinConnection()
	if spinConnection and spinConnection.Connected then
		return
	end

	spinConnection = RunService.Heartbeat:Connect(function(dt)
		local hasActive = false

		for viewport, state in pairs(states) do
			if viewport.Parent == nil then
				states[viewport] = nil
				continue
			end

			local renderModel = state.renderModel
			local speed = state.spinSpeed or 0
			if renderModel and renderModel.Parent and speed ~= 0 then
				hasActive = true
				state.spinAngle = (state.spinAngle or 0) + (speed * dt)
				local basePivot = state.spinBasePivot or renderModel:GetPivot()
				state.spinBasePivot = basePivot
				renderModel:PivotTo(CFrame.Angles(0, state.spinAngle, 0) * basePivot)
			end
		end

		if not hasActive and spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
	end)
end

local function clearAnimationState(state)
	if state.idleTrack then
		pcall(function()
			state.idleTrack:Stop()
		end)
		state.idleTrack = nil
	end

	if state.idleAnimation and state.idleAnimation.Parent then
		state.idleAnimation:Destroy()
	end
	state.idleAnimation = nil
end

local function ensureState(viewport)
	local state = states[viewport]
	if state == nil then
		state = {}
		states[viewport] = state
	end

	local worldModel = viewport:FindFirstChildWhichIsA("WorldModel")
	if worldModel == nil then
		worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport
	end
	state.worldModel = worldModel

	local camera = viewport.CurrentCamera
	if not (camera and camera.Parent == viewport) then
		camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end
	state.camera = camera

	return state
end

function ViewportHelper.ClearViewport(viewport)
	if typeof(viewport) ~= "Instance" or not viewport:IsA("ViewportFrame") then
		return
	end

	local state = states[viewport]
	if state == nil then
		return
	end

	clearAnimationState(state)
	state.spinSpeed = 0
	state.spinAngle = 0
	state.spinBasePivot = nil
	state.source = nil
	state.renderModel = nil
	state.displayClone = nil

	if state.worldModel and state.worldModel.Parent then
		state.worldModel:ClearAllChildren()
	end
end

function ViewportHelper.DestroyViewport(viewport, destroyViewport)
	if typeof(viewport) ~= "Instance" or not viewport:IsA("ViewportFrame") then
		return
	end

	ViewportHelper.ClearViewport(viewport)
	states[viewport] = nil

	if destroyViewport == true then
		viewport:Destroy()
	end
end

function ViewportHelper.SetSpin(viewport, spinSpeed)
	if typeof(viewport) ~= "Instance" or not viewport:IsA("ViewportFrame") then
		return
	end

	local state = states[viewport]
	if state == nil then
		return
	end

	local speed = tonumber(spinSpeed) or 0
	local previousSpeed = state.spinSpeed or 0
	state.spinSpeed = speed
	if speed ~= 0 and previousSpeed == 0 then
		state.spinAngle = 0
		state.spinBasePivot = state.renderModel and state.renderModel:GetPivot() or nil
	elseif speed == 0 then
		state.spinAngle = 0
		state.spinBasePivot = nil
	end

	if speed ~= 0 then
		ensureSpinConnection()
	end
end

function ViewportHelper.UpdateCamera(viewport, options)
	if typeof(viewport) ~= "Instance" or not viewport:IsA("ViewportFrame") then
		return
	end

	local state = states[viewport]
	if state == nil or state.renderModel == nil then
		return
	end

	local merged = mergeOptions(state.options)
	if type(options) == "table" then
		for k, v in pairs(options) do
			merged[k] = v
		end
	end
	state.options = merged

	local camera = state.camera
	local renderModel = state.renderModel
	local displayClone = state.displayClone
	local source = state.source

	camera.FieldOfView = merged.FieldOfView

	local modelCFrame, modelSize = renderModel:GetBoundingBox()
	local maxDim = math.max(modelSize.X, modelSize.Y, modelSize.Z)

	if displayClone then
		for _, part in ipairs(getViewportParts(displayClone)) do
			local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
			if mesh then
				local trueSizeX = part.Size.X * mesh.Scale.X
				local trueSizeY = part.Size.Y * mesh.Scale.Y
				local trueSizeZ = part.Size.Z * mesh.Scale.Z
				maxDim = math.max(maxDim, trueSizeX, trueSizeY, trueSizeZ)
			end
		end
	end

	if maxDim < 0.5 then
		maxDim = 1
	end

	local fov = math.rad(camera.FieldOfView)
	local distance = (maxDim / 2) / math.tan(fov / 2)

	local zoomMult = source and getNumberAttribute(source, "ViewportZoom", merged.Zoom) or merged.Zoom
	local camPitch = source and getNumberAttribute(source, "ViewportCamX", merged.CamPitch) or merged.CamPitch
	local camYaw = source and getNumberAttribute(source, "ViewportCamY", merged.CamYaw) or merged.CamYaw

	distance = distance * zoomMult

	local lookAtYOffset = merged.LookAtYOffset
	if source and CollectionService:HasTag(source, "Animal") then
		local attrOffset = source:GetAttribute("ViewportLookAtY")
		if attrOffset ~= nil then
			lookAtYOffset = tonumber(attrOffset) or lookAtYOffset
		else
			lookAtYOffset = -1.7
		end
	end

	local baseLookAt = modelCFrame.Position
	local lookAt = baseLookAt + Vector3.new(0, lookAtYOffset, 0)
	local camOffset = CFrame.Angles(math.rad(camPitch), math.rad(camYaw), 0) * Vector3.new(0, 0, distance)
	camera.CFrame = CFrame.lookAt(baseLookAt + camOffset, lookAt)
end

function ViewportHelper.SetupViewport(viewport, source, options)
	if typeof(viewport) ~= "Instance" or not viewport:IsA("ViewportFrame") then
		return nil
	end

	local state = ensureState(viewport)
	state.options = mergeOptions(options)

	viewport.Ambient = state.options.Ambient
	viewport.LightColor = state.options.LightColor

	ViewportHelper.ClearViewport(viewport)

	if typeof(source) ~= "Instance" then
		return viewport, nil
	end

	local displayClone, sourceVisual = resolveDisplayClone(source)
	if not displayClone then
		return viewport, nil
	end

	local renderModel = Instance.new("Model")
	renderModel.Name = "RenderModel"
	renderModel.Parent = state.worldModel
	displayClone.Parent = renderModel

	sanitizeClone(displayClone)
	alignDisplay(displayClone, source, sourceVisual)

	local renderPivot = renderModel:GetPivot()
	renderModel:PivotTo(renderPivot - renderPivot.Position)

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = state.options.OutlineColor
	highlight.OutlineTransparency = state.options.OutlineTransparency
	highlight.Parent = renderModel

	state.renderModel = renderModel
	state.displayClone = displayClone
	state.source = source

	if state.options.AutoPlayAnimation ~= false then
		local track, animation = playIdleAnimation(displayClone, source)
		state.idleTrack = track
		state.idleAnimation = animation
	end

	ViewportHelper.UpdateCamera(viewport)
	ViewportHelper.SetSpin(viewport, state.options.SpinSpeed or 0)

	return viewport, displayClone
end

function ViewportHelper.SetSource(viewport, source, options)
	return ViewportHelper.SetupViewport(viewport, source, options)
end

function ViewportHelper.CreateViewport(parentFrame, options)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0

	if type(options) == "table" then
		if options.Size then viewport.Size = options.Size end
		if options.Position then viewport.Position = options.Position end
		if options.AnchorPoint then viewport.AnchorPoint = options.AnchorPoint end
		if options.BackgroundTransparency ~= nil then viewport.BackgroundTransparency = options.BackgroundTransparency end
		if options.BackgroundColor3 ~= nil then viewport.BackgroundColor3 = options.BackgroundColor3 end
		if options.Name ~= nil then viewport.Name = tostring(options.Name) end
	end

	if parentFrame then
		viewport.Parent = parentFrame
	end

	return viewport
end

function ViewportHelper.BuildViewport(source, parentFrame, options)
	local viewport = ViewportHelper.CreateViewport(parentFrame, options)
	ViewportHelper.SetupViewport(viewport, source, options)
	return viewport
end

return ViewportHelper
