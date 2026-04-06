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

function CodeController:BindUI()
	print("[CodeController] Binding Code logic...")
	
	local main = self._pGui:WaitForChild("Main", 20)
	local tabs = main and main:WaitForChild("Tabs", 10)
	local codesTab = tabs and tabs:FindFirstChild("Codes")
	
	if not codesTab then return end

	local redeemFrame = codesTab:FindFirstChild("RedeemFrame")
	local redeemBtn = redeemFrame and redeemFrame:FindFirstChild("btn")
	local inputFrame = codesTab:FindFirstChild("InputFrame")
	local inputField = inputFrame and inputFrame:FindFirstChild("input")

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
	self:BindUI()
end

return CodeController
