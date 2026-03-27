local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScreenEffects = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ScreenEffects"))

local CodeController = {
	Name = "CodeController",
	Priority = 15,
}

local BLUR_SIZE = 15

function CodeController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._pGui = self._player:WaitForChild("PlayerGui")
	self._remote = runtime.Remotes:GetCodeRemote()
	self._blur = nil
end

function CodeController:_shakeCamera()
	local camera = workspace.CurrentCamera
	task.spawn(function()
		for i = 1, 8 do
			local offset = Vector3.new(math.random(-1, 1) * 0.2, math.random(-1, 1) * 0.2, 0)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			task.wait(0.02)
		end
	end)
end

function CodeController:_setGroupTransparency(obj: GuiObject, transparency: number)
	if obj:IsA("CanvasGroup") then
		TweenService:Create(obj, TweenInfo.new(0.3), {GroupTransparency = transparency}):Play()
	else
		-- Recursive fallback to hide content while maintaining layout position
		local function apply(target)
			if target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox") then
				TweenService:Create(target, TweenInfo.new(0.3), {TextTransparency = transparency}):Play()
			end
			if target:IsA("ImageLabel") or target:IsA("ImageButton") then
				TweenService:Create(target, TweenInfo.new(0.3), {ImageTransparency = transparency}):Play()
			end
			if target:IsA("Frame") or target:IsA("ScrollingFrame") then
				local original = target:GetAttribute("OrigBT") or target.BackgroundTransparency
				if not target:GetAttribute("OrigBT") then target:SetAttribute("OrigBT", original) end
				local targetBT = (transparency == 1) and 1 or original
				TweenService:Create(target, TweenInfo.new(0.3), {BackgroundTransparency = targetBT}):Play()
			end
			if target:IsA("UIStroke") then
				TweenService:Create(target, TweenInfo.new(0.3), {Transparency = transparency}):Play()
			end
			for _, c in ipairs(target:GetChildren()) do apply(c) end
		end
		apply(obj)
	end
end

function CodeController:_setEffectsActive(active: boolean)
	local targetBlur = active and BLUR_SIZE or 0
	if active then
		if not self._blur then
			self._blur = Instance.new("BlurEffect")
			self._blur.Size = 0
			self._blur.Parent = Lighting
		end
	end

	if self._blur then
		local blurTween = TweenService:Create(self._blur, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = targetBlur})
		if not active then
			blurTween.Completed:Connect(function()
				if not active and self._blur then
					self._blur:Destroy()
					self._blur = nil
				end
			end)
		end
		blurTween:Play()
	end

	local main = self._pGui:FindFirstChild("Main")
	if main then
		-- Handle all top-level elements in Main
		for _, child in ipairs(main:GetChildren()) do
			if child:IsA("GuiObject") then
				if child.Name == "Buttons" then
					-- Handle individual buttons/wrappers inside
					for _, btnNode in ipairs(child:GetChildren()) do
						if btnNode:IsA("GuiObject") then
							local isCodesBtn = (btnNode.Name == "CodesBtn") or btnNode:FindFirstChild("CodesBtn", true) ~= nil
							if not isCodesBtn then
								self:_setGroupTransparency(btnNode, active and 1 or 0)
							end
						end
					end
				elseif child.Name ~= "Tabs" and child.Name ~= "CoinsFrame" then
					-- Hide other sidebar/HUD elements
					child.Visible = not active
				end
			end
		end
	end
end

function CodeController:BindUI()
	print("[CodeController] Binding UI...")
	
	local main = self._pGui:WaitForChild("Main", 20)
	local buttons = main and main:WaitForChild("Buttons", 10)
	local tabs = main and main:WaitForChild("Tabs", 10)
	
	if not buttons or not tabs then return end
	
	local codesBtn = buttons:FindFirstChild("CodesBtn", true)
	local codesTab = tabs:WaitForChild("Codes", 10)
	
	if not codesBtn or not codesTab then return end

	-- Initial Setup
	local scale = codesTab:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", codesTab)
	scale.Scale = 0
	codesTab.Visible = false
	
	if codesTab:IsA("CanvasGroup") then
		codesTab.GroupTransparency = 1
	end
	
	local backBtn = codesTab:FindFirstChild("btn", true)
	local redeemFrame = codesTab:FindFirstChild("RedeemFrame")
	local redeemBtn = redeemFrame and redeemFrame:FindFirstChild("btn")
	local inputFrame = codesTab:FindFirstChild("InputFrame")
	local inputField = inputFrame and inputFrame:FindFirstChild("input")

	local isAnimating = false
	local function setTabVisible(visible: boolean)
		if isAnimating then return end
		if visible == codesTab.Visible then return end
		
		isAnimating = true
		
		if visible then
			codesTab.Visible = true
			self:_setEffectsActive(true)
			if codesTab:IsA("CanvasGroup") then
				TweenService:Create(codesTab, TweenInfo.new(0.3), {GroupTransparency = 0}):Play()
			end
			local t = TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
			t.Completed:Connect(function() isAnimating = false end)
			t:Play()
		else
			self:_setEffectsActive(false)
			if codesTab:IsA("CanvasGroup") then
				TweenService:Create(codesTab, TweenInfo.new(0.3), {GroupTransparency = 1}):Play()
			end
			local tween = TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
			tween.Completed:Connect(function()
				codesTab.Visible = false
				isAnimating = false
			end)
			tween:Play()
		end
	end

	codesBtn.MouseButton1Click:Connect(function()
		setTabVisible(not codesTab.Visible)
	end)

	if backBtn and backBtn:IsA("GuiButton") then
		backBtn.MouseButton1Click:Connect(function()
			setTabVisible(false)
		end)
	end

	if redeemBtn and redeemBtn:IsA("GuiButton") and inputField and inputField:IsA("TextBox") then
		redeemBtn.MouseButton1Click:Connect(function()
			local code = inputField.Text
			if code == "" then return end
			
			local success, message = self._remote:InvokeServer(code)
			local notif = self._runtime:GetController("NotificationController")
			
			if success then
				if notif then 
					notif:ShowNotification(tostring(message or "Code Redeemed!"), "Announcement") 
				end
				
				-- Trigger existing confetti handler
				if ScreenEffects and ScreenEffects.ConfettiBurst then
					ScreenEffects.ConfettiBurst(self._player)
				end
				
				inputField.Text = ""
			else
				if notif then 
					notif:ShowNotification(tostring(message or "Invalid Code"), "Warning") 
				end
				self:_shakeCamera()
			end
		end)
	end
end

function CodeController:Start()
	-- Wait for UI instead of polling infinitely
	task.spawn(function()
		local main = self._pGui:WaitForChild("Main")
		if main then
			local buttons = main:WaitForChild("Buttons")
			if buttons then
				local connection
				local function checkButton()
					local btn = buttons:FindFirstChild("CodesBtn", true)
					if btn and not btn:GetAttribute("CodeControllerBound") then
						btn:SetAttribute("CodeControllerBound", true)
						self:BindUI()
						if connection then
							connection:Disconnect()
							connection = nil
						end
					end
				end

				checkButton()
				if not buttons:FindFirstChild("CodesBtn", true) or not buttons:FindFirstChild("CodesBtn", true):GetAttribute("CodeControllerBound") then
					connection = buttons.DescendantAdded:Connect(checkButton)
				end
			end
		end
	end)
end

return CodeController
