local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local EventController = {
	Name = "EventController",
	Priority = -10,
}

function EventController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetEventRemote()
	self._activeGui = nil
	self._activeMusic = nil
end

local function fadeGui(guiObj, fadeIn, duration)
	local targetTransparency = fadeIn and 0 or 1
	for _, child in ipairs(guiObj:GetDescendants()) do
		if child:IsA("GuiObject") then
			if fadeIn and child.Name == "bg" then continue end
			
			local props = {}
			if child:IsA("Frame") or child:IsA("ScrollingFrame") or child:IsA("TextBox") or child:IsA("TextLabel") or child:IsA("TextButton") then
				if child.BackgroundTransparency ~= 1 or not fadeIn then
					props.BackgroundTransparency = targetTransparency
				end
			end
			if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
				props.TextTransparency = targetTransparency
				props.TextStrokeTransparency = targetTransparency
			end
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				props.ImageTransparency = targetTransparency
			end
			if child:IsA("UIStroke") then
				props.Transparency = targetTransparency
			end
			
			if next(props) then
				TweenService:Create(child, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
			end
		end
	end
end

function EventController:StartEvent(eventName: string, duration: number)
	local musicController = self._runtime:GetController("MusicController")
	if musicController then
		musicController:SetEventActive(true)
	end

	local rsEvents = ReplicatedStorage:WaitForChild("ActiveEvents", 5)
	local eventData = rsEvents and rsEvents:WaitForChild(eventName, 5)
	if not eventData then return end
	
	-- 1. SFX Sequence (Timeline based)
	local sfxFolder = eventData:FindFirstChild("SFX")
	if sfxFolder then
		task.spawn(function()
			local sfxList = sfxFolder:GetChildren()
			-- Sort numerically by name
			table.sort(sfxList, function(a, b) 
				return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0) 
			end)

			local startTime = os.clock()
			for _, sfxTemplate in ipairs(sfxList) do
				local timestamp = tonumber(sfxTemplate.Name)
				if timestamp and sfxTemplate:IsA("Sound") then
					-- Calculate how long to wait until this specific timestamp
					local elapsed = os.clock() - startTime
					local waitTime = timestamp - elapsed

					if waitTime > 0 then
						task.wait(waitTime)
					end

					local sfx = sfxTemplate:Clone()
					sfx.Parent = game:GetService("SoundService")
					sfx:Play()
					-- Use a fixed long duration for Debris to avoid cutting off sounds
					Debris:AddItem(sfx, 15)
				end
			end
		end)
	end

	
	-- 2. Music
	local musicFolder = eventData:FindFirstChild("Music")
	if musicFolder then
		task.spawn(function()
			task.wait(math.random(10, 16) / 10) -- 1.0 to 1.6 seconds
			for _, musicTemplate in ipairs(musicFolder:GetChildren()) do
				if musicTemplate:IsA("Sound") then
					local music = musicTemplate:Clone()
					music.Parent = game:GetService("SoundService")
					music:Play()
					self._activeMusic = music
					-- Don't destroy immediately, wait for EndEvent or duration
					break -- Play only first one
				end
			end
		end)
	end
	
	-- 3. Gui Fade In/Out
	local guiFolder = eventData:FindFirstChild("Gui")
	if guiFolder then
		local pGui = self._player:WaitForChild("PlayerGui")
		for _, guiTemplate in ipairs(guiFolder:GetChildren()) do
			if guiTemplate:IsA("ScreenGui") or guiTemplate:IsA("GuiObject") then
				local clone = guiTemplate:Clone()
				clone.Parent = pGui
				
				-- Hide initially to fade in
				for _, child in ipairs(clone:GetDescendants()) do
					if child:IsA("GuiObject") and child.Name ~= "bg" then
						if child:IsA("Frame") or child:IsA("ScrollingFrame") then child.BackgroundTransparency = 1 end
						if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
							child.TextTransparency = 1
							child.TextStrokeTransparency = 1
							child.BackgroundTransparency = 1
						end
						if child:IsA("ImageLabel") or child:IsA("ImageButton") then
							child.ImageTransparency = 1
							child.BackgroundTransparency = 1
						end
						if child:IsA("UIStroke") then
							child.Transparency = 1
						end
					end
				end
				
				if clone:IsA("ScreenGui") then clone.Enabled = true end
				
				self._activeGui = clone
				
				-- Fade In (1s)
				fadeGui(clone, true, 1)
				
				-- Schedule Fade Out after 3s (Total 4s including fade in)
				task.delay(3, function()
					if self._activeGui == clone then
						fadeGui(clone, false, 1)
						task.delay(1, function()
							if clone.Parent then clone:Destroy() end
						end)
					end
				end)
			end
		end
	end
	
	-- 4. Animate Objects
	task.spawn(function()
		local CollectionService = game:GetService("CollectionService")
		local eventObjects = CollectionService:GetTagged("ActiveEventAsset")
		for _, obj in ipairs(eventObjects) do
			-- SKIP Tornados and UFOs: They have their own server-driven movement
			if CollectionService:HasTag(obj, "TornadoObject") or CollectionService:HasTag(obj, "UFOObject") then continue end

			if obj:IsA("Model") and obj.PrimaryPart then
				local pp = obj.PrimaryPart
				local originalCFrame = pp.CFrame
				-- Infinite gentle float and spin
				local tweenInfo = TweenService:Create(pp, TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					CFrame = originalCFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(45), 0)
				})
				tweenInfo:Play()
			elseif obj:IsA("BasePart") then
				local originalCFrame = obj.CFrame
				local tweenInfo = TweenService:Create(obj, TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					CFrame = originalCFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.rad(45), 0)
				})
				tweenInfo:Play()
			end
		end
	end)
end

function EventController:EndEvent(eventName: string)
	local musicController = self._runtime:GetController("MusicController")
	if musicController then
		musicController:SetEventActive(false)
	end

	if self._activeMusic then
		local tween = TweenService:Create(self._activeMusic, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Volume = 0})
		tween:Play()
		tween.Completed:Connect(function()
			if self._activeMusic then
				self._activeMusic:Destroy()
				self._activeMusic = nil
			end
		end)
	end
end

function EventController:Start()
	self._remote.OnClientEvent:Connect(function(action, data)
		if action == "StartEvent" then
			self:StartEvent(data.EventName, data.Duration)
		elseif action == "EndEvent" then
			self:EndEvent(data.EventName)
		elseif action == "TornadoPush" then
			local char = self._player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChild("Humanoid")
			if hrp and hum and data.Force then
				hum:ChangeState(Enum.HumanoidStateType.Freefall)
				hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, data.Force, hrp.AssemblyLinearVelocity.Z)
			end
		end
	end)
end

return EventController