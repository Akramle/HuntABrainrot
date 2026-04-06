local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local GiftController = {
	Name = "GiftController",
	Priority = 0,
}

local CAMERA = workspace.CurrentCamera
local DEFAULT_FOV = 70
local ZOOM_FOV = 55
local BLUR_SIZE = 15

function GiftController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetGiftRemote()
	self._blur = nil
end

function GiftController:_applyEffects(active)
	-- Movement is NOT blocked for GiftGui as per request
	
	local playerGui = self._player:FindFirstChild("PlayerGui")
	local mainHud = playerGui and playerGui:FindFirstChild("Main")
	if mainHud and mainHud:IsA("ScreenGui") then
		if active then
			if not self._mainSnapshot then
				self._mainSnapshot = {}
				for _, child in ipairs(mainHud:GetChildren()) do
					if child:IsA("GuiObject") and child.Name ~= "CoinsFrame" and child.Name ~= "Bucks" and child.Name ~= "FriendsFrame" and child.Name ~= "DiamondsFrame" then
						self._mainSnapshot[child] = child.Visible
						child.Visible = false
					end
				end
			end
		else
			if self._mainSnapshot then
				for child, wasVisible in pairs(self._mainSnapshot) do
					if child and child.Parent then
						child.Visible = wasVisible
					end
				end
				self._mainSnapshot = nil
			end
		end
	end
	
	local targetFov = active and ZOOM_FOV or DEFAULT_FOV
	local targetBlur = active and BLUR_SIZE or 0
	
	if active then
		if not self._blur then
			self._blur = Instance.new("BlurEffect")
			self._blur.Size = 0
			self._blur.Parent = Lighting
		end
	end
	
	TweenService:Create(CAMERA, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = targetFov}):Play()
	
	if self._blur then
		local blurTween = TweenService:Create(self._blur, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = targetBlur})
		blurTween.Completed:Connect(function()
			if not active and self._blur then
				self._blur:Destroy()
				self._blur = nil
			end
		end)
		blurTween:Play()
	end
end

function GiftController:_bindGui(gui: ScreenGui, data)
	local main = gui:WaitForChild("Main")
	local acceptFrame = main:WaitForChild("AcceptFrame")
	local acceptBtn = acceptFrame:WaitForChild("btn")
	local declineFrame = main:WaitForChild("DeclineFrame")
	local declineBtn = declineFrame:WaitForChild("btn")
	local backFrame = main:WaitForChild("BackFrame")
	local backBtn = backFrame:WaitForChild("btn")
	local textLabel = main:FindFirstChildOfClass("TextLabel")
	
	if textLabel then
		textLabel.Text = string.format("%s has sent you %s", data.senderName, data.animalName)
	end
	
	local uiScale = main:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", main)
	
	local function close(action)
		self:_applyEffects(false)
		local tween = TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.7})
		TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
		tween.Completed:Connect(function()
			if action then
				self._remote:FireServer(action)
			end
			gui:Destroy()
		end)
		tween:Play()
	end

	acceptBtn.MouseButton1Click:Connect(function()
		close("Accept")
	end)
	
	declineBtn.MouseButton1Click:Connect(function()
		close("Decline")
	end)
	
	backBtn.MouseButton1Click:Connect(function()
		close("Back")
	end)

	gui.Enabled = true
	uiScale.Scale = 0.5
	main.BackgroundTransparency = 1
	self:_applyEffects(true)
	
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
end

function GiftController:Start()
	self._remote.OnClientEvent:Connect(function(action, data)
		if action == "OpenGiftGui" then
			local playerGui = self._player:WaitForChild("PlayerGui")
			local gui = playerGui:FindFirstChild("GiftGui")
			if not gui then
				-- Template is cloned by Server into PlayerGui in this project's pattern
				-- Let's wait for it
				gui = playerGui:WaitForChild("GiftGui", 5)
			end
			
			if gui then
				self:_bindGui(gui, data)
			end
		end
	end)
end

return GiftController
