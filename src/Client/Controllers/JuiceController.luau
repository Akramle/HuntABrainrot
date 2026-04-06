local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local JuiceController = {
	Name = "JuiceController",
	Priority = 0,
}

-- // THE JUICE SETTINGS //
local POP_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SETTLE_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_INFO = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

function JuiceController:Init(runtime)
	self._runtime = runtime
	self._interactionStates = {}
	self._rotationLoops = {}
	self._rotationConnection = nil
end

-- // LAYOUT FIX //
function JuiceController:_applyLayoutFix(item)
	local parent = item.Parent
	if not parent then return end

	if item:GetAttribute("no_wrapper") then
		return
	end

	local hasLayout = parent:FindFirstChildWhichIsA("UIListLayout") or parent:FindFirstChildWhichIsA("UIGridLayout")
	if hasLayout and parent.Name ~= "JuiceWrapper" then
		local wrapper = Instance.new("Frame")
		wrapper.Name = parent.Name
		wrapper.BackgroundTransparency = 1
		wrapper.Size = item.Size
		wrapper.LayoutOrder = item.LayoutOrder
		wrapper.ZIndex = item.ZIndex
		wrapper.Parent = parent

		item.Size = UDim2.fromScale(1, 1)
		item.Position = UDim2.fromScale(0.5, 0.5)
		item.AnchorPoint = Vector2.new(0.5, 0.5)
		item.Parent = wrapper
	end
end

function JuiceController:_getOrCreateState(item)
	if not self._interactionStates[item] then
		self:_applyLayoutFix(item)

		local uiScale = item:FindFirstChildWhichIsA("UIScale")

		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Scale = 1 -- Explicitly set default
			uiScale.Parent = item
		end

		self._interactionStates[item] = {
			isHovering = false,
			isClicking = false,
			baseScale = uiScale.Scale, -- Read the definitive value here
			hoverTarget = item:GetAttribute("target") or 1.08,
			clickTarget = item:GetAttribute("click_target") or 0.95,
			baseRotation = item.Rotation,
			baseZIndex = item.ZIndex,
			hoverTilt = 0,
			clickTilt = 0,
			uiScale = uiScale,
			connections = {},
		}
	end
	return self._interactionStates[item]
end

function JuiceController:_updateTransform(item)
	local state = self._interactionStates[item]
	if not state then return end

	local targetScale = state.baseScale
	local targetRotation = state.baseRotation
	local tweenInfo = SETTLE_INFO

	-- Priority: Click > Hover > Idle
	if state.isClicking then
		targetScale = state.baseScale * state.clickTarget
		targetRotation = state.baseRotation + state.clickTilt
		tweenInfo = PUNCH_INFO
	elseif state.isHovering then
		targetScale = state.baseScale * state.hoverTarget
		targetRotation = state.baseRotation + state.hoverTilt
		tweenInfo = POP_INFO
	end

	-- ZIndex elevation
	local targetZIndex = (state.isHovering or state.isClicking) and (state.baseZIndex + 100) or state.baseZIndex
	item.ZIndex = targetZIndex
	if item.Parent and item.Parent.Name == "JuiceWrapper" then
		item.Parent.ZIndex = targetZIndex
	end

	-- Scale Tween
	TweenService:Create(state.uiScale, tweenInfo, {Scale = targetScale}):Play()

	-- Rotation Tween
	if not self._rotationLoops[item] then
		TweenService:Create(item, tweenInfo, {Rotation = targetRotation}):Play()
	end
end

-- // CLICK LOGIC //
function JuiceController:_setupInteractiveClick(item)
	local state = self:_getOrCreateState(item)

	if state.connections.clickDown then state.connections.clickDown:Disconnect() end
	if state.connections.clickUp then state.connections.clickUp:Disconnect() end
	if state.connections.clickLeave then state.connections.clickLeave:Disconnect() end

	local clickProvider = nil
	if item:IsA("GuiButton") then
		clickProvider = item
	else
		local innerButton = item:FindFirstChildWhichIsA("GuiButton", true)
		if innerButton then
			clickProvider = innerButton
		end
	end

	local function triggerClickDown()
		state.isClicking = true
		local direction = state.hoverTilt >= 0 and 1 or -1
		local extraCrunch = math.random(30, 60) / 10
		state.clickTilt = state.hoverTilt + (extraCrunch * direction)
		self:_updateTransform(item)

		local soundController = self._runtime:GetController("SoundController")
		if soundController then
			soundController:PlayLocal("UIClick")
		end
	end

	if clickProvider then
		state.connections.clickDown = clickProvider.MouseButton1Down:Connect(function()
			triggerClickDown()
		end)

		state.connections.clickUp = clickProvider.MouseButton1Up:Connect(function()
			state.isClicking = false
			self:_updateTransform(item)
		end)

		state.connections.clickLeave = clickProvider.MouseLeave:Connect(function()
			if state.isClicking then
				state.isClicking = false
				self:_updateTransform(item)
			end
		end)
	else
		item.Active = true

		state.connections.clickDown = item.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				triggerClickDown()

				local releaseConn
				releaseConn = UserInputService.InputEnded:Connect(function(endInput)
					if endInput.UserInputType == input.UserInputType then
						state.isClicking = false
						self:_updateTransform(item)

						if releaseConn then 
							releaseConn:Disconnect() 
							releaseConn = nil
						end
					end
				end)
			end
		end)
	end
end

-- // HOVER LOGIC //
function JuiceController:SetupHover(item)
	local state = self:_getOrCreateState(item)

	if state.connections.hoverEnter then state.connections.hoverEnter:Disconnect() end
	if state.connections.hoverLeave then state.connections.hoverLeave:Disconnect() end

	state.connections.hoverEnter = item.MouseEnter:Connect(function()
		state.isHovering = true
		state.hoverTilt = math.random(-25, 25) / 10 
		self:_updateTransform(item)

		local soundController = self._runtime:GetController("SoundController")
		if soundController then
			soundController:PlayLocal("UIHover", {randomPitch = true})
		end
	end)

	state.connections.hoverLeave = item.MouseLeave:Connect(function()
		state.isHovering = false
		if state.isClicking then
			state.isClicking = false
		end
		self:_updateTransform(item)
	end)

	self:_setupInteractiveClick(item)
end

-- // CLEANUP //
function JuiceController:RemoveHover(item)
	local state = self._interactionStates[item]
	if state then
		for _, conn in pairs(state.connections) do
			conn:Disconnect()
		end

		state.isHovering = false
		state.isClicking = false
		self:_updateTransform(item)
		self._interactionStates[item] = nil
	end
end

-- // ROTATION EFFECTS //
function JuiceController:_stopRotationLoop(item)
	if self._rotationLoops[item] then
		self._rotationLoops[item].running = false
		self._rotationLoops[item] = nil
	end

	if self._rotationConnection and not next(self._rotationLoops) then
		self._rotationConnection:Disconnect()
		self._rotationConnection = nil
	end
end

function JuiceController:_ensureRotationLoop()
	if self._rotationConnection and self._rotationConnection.Connected then
		return
	end

	self._rotationConnection = RunService.Heartbeat:Connect(function(dt)
		local hasAny = false

		for item, loop in pairs(self._rotationLoops) do
			if not loop.running or item.Parent == nil then
				self._rotationLoops[item] = nil
			else
				hasAny = true

				if loop.mode == "spin" then
					item.Rotation += loop.speed * dt * 60
				elseif loop.mode == "wiggle" then
					loop.elapsed += dt
					item.Rotation = loop.baseRotation + math.sin(loop.elapsed * loop.omega) * loop.angle
				elseif loop.mode == "glitch" then
					loop.nextChange -= dt
					if loop.nextChange <= 0 then
						item.Rotation = math.random(-180, 180)
						loop.nextChange = math.random() * 0.2 + 0.1
					end
				end
			end
		end

		if not hasAny and self._rotationConnection then
			self._rotationConnection:Disconnect()
			self._rotationConnection = nil
		end
	end)
end

function JuiceController:SetupSpin(item)
	self:_stopRotationLoop(item)
	local target = tonumber(item:GetAttribute("target")) or 2
	local loop = {
		running = true,
		mode = "spin",
		speed = target,
	}
	self._rotationLoops[item] = loop
	self:_ensureRotationLoop()
end

function JuiceController:SetupWiggle(item)
	self:_stopRotationLoop(item)
	local angle = tonumber(item:GetAttribute("angle")) or 10
	local duration = math.max(0.05, tonumber(item:GetAttribute("speed")) or 0.5)
	local loop = {
		running = true,
		mode = "wiggle",
		angle = angle,
		elapsed = 0,
		omega = math.pi / duration,
		baseRotation = item.Rotation,
	}
	self._rotationLoops[item] = loop
	self:_ensureRotationLoop()
end

function JuiceController:SetupGlitch(item)
	self:_stopRotationLoop(item)
	local loop = {
		running = true,
		mode = "glitch",
		nextChange = 0,
	}
	self._rotationLoops[item] = loop
	self:_ensureRotationLoop()
end

function JuiceController:RemoveRotation(item)
	self:_stopRotationLoop(item)
	local state = self._interactionStates[item]
	item.Rotation = state and state.baseRotation or 0
end

function JuiceController:Start()
	local function safeSetup(tag, method)
		for _, item in ipairs(CollectionService:GetTagged(tag)) do
			self[method](self, item)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(item)
			self[method](self, item)
		end)
	end

	safeSetup("hover_effect", "SetupHover")
	safeSetup("spin_effect", "SetupSpin")
	safeSetup("wiggle_effect", "SetupWiggle")
	safeSetup("glitch_effect", "SetupGlitch")

	CollectionService:GetInstanceRemovedSignal("hover_effect"):Connect(function(item) self:RemoveHover(item) end)
	CollectionService:GetInstanceRemovedSignal("spin_effect"):Connect(function(item) self:RemoveRotation(item) end)
	CollectionService:GetInstanceRemovedSignal("wiggle_effect"):Connect(function(item) self:RemoveRotation(item) end)
	CollectionService:GetInstanceRemovedSignal("glitch_effect"):Connect(function(item) self:RemoveRotation(item) end)
end

return JuiceController
