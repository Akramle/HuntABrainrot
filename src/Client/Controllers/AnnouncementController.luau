local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AnnouncementController = {
	Name = "AnnouncementController",
}

local RAINBOW_COLORS = {
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 127, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(0, 0, 255),
	Color3.fromRGB(75, 0, 130),
	Color3.fromRGB(148, 0, 211)
}

local ANNOUNCEMENT_GAP = 0.08 -- Reduced gap
local ANNOUNCEMENT_START_Y = 0.12 -- Slightly lower start

function AnnouncementController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._pGui = self._player:WaitForChild("PlayerGui")
	self._announcementRemote = runtime.Remotes:GetAnnouncementRemote()
	self._screenEffects = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ScreenEffects"))
	
	self._activeAnnouncements = {}
	self._camera = workspace.CurrentCamera
	
	self._template = nil
end

function AnnouncementController:_getRainbowColor(tick)
	local t = tick % #RAINBOW_COLORS
	local index = math.floor(t) + 1
	local nextIndex = (index % #RAINBOW_COLORS) + 1
	local alpha = t % 1
	
	local color = RAINBOW_COLORS[index]
	local nextColor = RAINBOW_COLORS[nextIndex]
	
	return color:Lerp(nextColor, alpha)
end

function AnnouncementController:_getTemplate()
	if self._template then return self._template end
	
	local assets = ReplicatedStorage:WaitForChild("Assets", 5)
	local guiFolder = assets and assets:WaitForChild("Gui", 2)
	local template = guiFolder and (guiFolder:FindFirstChild("Announcment") or guiFolder:FindFirstChild("Announcement"))
	
	if template then
		self._template = template
		return template
	end
	
	-- Fallback if no template: Centered and smaller
	local frame = Instance.new("Frame")
	frame.Name = "Announcment"
	frame.Size = UDim2.new(0.6, 0, 0.06, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundTransparency = 1
	
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = frame
	
	self._template = frame
	return frame
end

function AnnouncementController:_applyPovEffect()
	local originalFov = self._camera.FieldOfView
	
	-- FOV Kick
	local fovTweenIn = TweenService:Create(self._camera, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {FieldOfView = originalFov - 12})
	local fovTweenOut = TweenService:Create(self._camera, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {FieldOfView = originalFov})
	
	fovTweenIn:Play()
	fovTweenIn.Completed:Connect(function()
		fovTweenOut:Play()
	end)
	
	-- Screen Shake
	task.spawn(function()
		local startTime = os.clock()
		local duration = 0.4
		local intensity = 0.4
		
		while os.clock() - startTime < duration do
			local elapsed = os.clock() - startTime
			local currentIntensity = intensity * (1 - (elapsed / duration))
			local offset = Vector3.new(
				math.random(-100, 100) / 100 * currentIntensity,
				math.random(-100, 100) / 100 * currentIntensity,
				math.random(-100, 100) / 100 * currentIntensity
			)
			self._camera.CFrame = self._camera.CFrame * CFrame.new(offset)
			task.wait(0.033)
		end
	end)
end

function AnnouncementController:UpdateStackPositions()
	for i, data in ipairs(self._activeAnnouncements) do
		local targetY = ANNOUNCEMENT_START_Y + (i - 1) * ANNOUNCEMENT_GAP
		local targetPos = UDim2.new(0.5, 0, targetY, 0) -- Centered X
		
		if data.Frame.Position ~= targetPos then
			TweenService:Create(data.Frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = targetPos}):Play()
		end
	end
end

function AnnouncementController:ShowDivineAnnouncement()
	local template = self:_getTemplate()
	local screenGui = self._pGui:FindFirstChild("AnnouncementGui")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "AnnouncementGui"
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 1000
		screenGui.Parent = self._pGui
	end
	
	local frame = template:Clone()
	frame.AnchorPoint = Vector2.new(0.5, 0) -- Ensure centered anchor
	local label = frame:IsA("TextLabel") and frame or frame:FindFirstChildWhichIsA("TextLabel", true)
	if not label then return end
	
	-- Stacking logic
	table.insert(self._activeAnnouncements, {
		Frame = frame,
		Label = label,
		AddedAt = os.clock()
	})
	
	local stackIndex = #self._activeAnnouncements
	local targetY = ANNOUNCEMENT_START_Y + (stackIndex - 1) * ANNOUNCEMENT_GAP
	local targetPos = UDim2.new(0.5, 0, targetY, 0)
	
	frame.Position = UDim2.new(0.5, 0, -0.2, 0) -- Start off-screen centered
	frame.Rotation = -8
	frame.Parent = screenGui
	
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	
	local uiScale = label:FindFirstChildWhichIsA("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = label
	end
	uiScale.Scale = 0
	
	-- Juicier Pop-in
	TweenService:Create(frame, TweenInfo.new(0.8, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Position = targetPos, Rotation = 0}):Play()
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0, TextStrokeTransparency = 0}):Play()
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	
	-- POV and Effects
	self:_applyPovEffect()
	self._screenEffects.DivineFlash(self._player)
	
	pcall(function()
		local soundEvent = ReplicatedStorage:WaitForChild("RuntimeRemotes"):FindFirstChild("SoundAction")
		if soundEvent then
			soundEvent:FireServer("PlayGlobal", {SoundName = "DivineSpawn"})
		end
	end)
	
	-- Rainbow & Wobble Thread
	local thread = task.spawn(function()
		local startTime = os.clock()
		while true do
			local elapsed = os.clock() - startTime
			local rainbowColor = self:_getRainbowColor(elapsed * 2.5)
			local hex = rainbowColor:ToHex()
			
			label.Text = string.format([[A <font color="#%s">DEVINE-LEVEL</font> Brainrot has entered this realm.]], hex)
			
			-- Addictive Wobble & Pulse
			local wobble = math.sin(elapsed * 8) * 2
			frame.Rotation = wobble
			
			local pulse = 1 + math.sin(elapsed * 12) * 0.04
			uiScale.Scale = pulse
			
			task.wait(0.033)
		end
	end)
	
	-- Cleanup task
	task.delay(7, function()
		task.cancel(thread)
		
		-- Remove from active list
		for i, data in ipairs(self._activeAnnouncements) do
			if data.Frame == frame then
				table.remove(self._activeAnnouncements, i)
				break
			end
		end
		
		-- Slide remaining ones up
		self:UpdateStackPositions()
		
		-- Fade out and destroy
		TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = frame.Position + UDim2.new(0.8, 0, 0, 0)}):Play() -- Slide off right
		TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0}):Play()
		local fade = TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 1, TextStrokeTransparency = 1})
		fade.Completed:Connect(function()
			frame:Destroy()
		end)
		fade:Play()
	end)
end

function AnnouncementController:Start()
	if self._announcementRemote then
		self._announcementRemote.OnClientEvent:Connect(function(action, data)
			if action == "DivineSpawn" then
				self:ShowDivineAnnouncement()
			end
		end)
	end
end

return AnnouncementController
