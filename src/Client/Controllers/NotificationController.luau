local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local NotificationController = {
	Name = "NotificationController",
	Priority = 5,
}

local NOTIF_WIDTH = 0.25
local NOTIF_HEIGHT = 0.08
local NOTIF_SPACING = 0.01
local NOTIF_START_X = 1.2
local NOTIF_END_X = 0.73
local NOTIF_START_Y = 0.85

function NotificationController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._pGui = self._player:WaitForChild("PlayerGui")
	self._remote = runtime.Remotes:GetNotificationRemote()
	self._activeNotifications = {}
end

function NotificationController:_createNotifUI(message: string, nType: string)
	local screenGui = self._pGui:FindFirstChild("NotificationGui")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "NotificationGui"
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 5000
		screenGui.Parent = self._pGui
	end

	local main = Instance.new("CanvasGroup")
	main.Name = "Notif"
	main.Size = UDim2.fromScale(NOTIF_WIDTH, NOTIF_HEIGHT)
	main.Position = UDim2.fromScale(NOTIF_START_X, NOTIF_START_Y)
	main.BackgroundColor3 = nType == "Warning" and Color3.fromRGB(60, 20, 20) or Color3.fromRGB(20, 20, 30)
	main.BackgroundTransparency = 0.2
	main.GroupTransparency = 1
	main.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = main

	local stroke = Instance.new("UIStroke")
	stroke.Color = nType == "Warning" and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(80, 80, 255)
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = main

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(0.2, 1)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.FredokaOne
	icon.Text = nType == "Warning" and "⚠️" or "🔔"
	icon.TextSize = 24
	icon.Parent = main

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Message"
	textLabel.Size = UDim2.new(0.75, 0, 1, 0)
	textLabel.Position = UDim2.fromScale(0.2, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.Text = message
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextScaled = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.RichText = true
	textLabel.Parent = main

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.2, 0)
	padding.PaddingBottom = UDim.new(0.2, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = textLabel

	return main
end

function NotificationController:UpdateStackPositions()
	for i, data in ipairs(self._activeNotifications) do
		local targetY = NOTIF_START_Y - (i - 1) * (NOTIF_HEIGHT + NOTIF_SPACING)
		local targetPos = UDim2.fromScale(NOTIF_END_X, targetY)
		
		TweenService:Create(data.Frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = targetPos}):Play()
	end
end

function NotificationController:ShowNotification(message: string, nType: string)
	local frame = self:_createNotifUI(message, nType)
	
	local data = {
		Frame = frame,
		AddedAt = os.clock()
	}
	table.insert(self._activeNotifications, 1, data) -- Newest on bottom (first in list)
	
	self:UpdateStackPositions()

	-- Animation In
	TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()

	task.delay(5, function()
		-- Remove from active list
		for i, d in ipairs(self._activeNotifications) do
			if d == data then
				table.remove(self._activeNotifications, i)
				break
			end
		end
		
		self:UpdateStackPositions()
		
		-- Animation Out
		local tween = TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = frame.Position + UDim2.fromScale(0.5, 0),
			GroupTransparency = 1
		})
		tween.Completed:Connect(function()
			frame:Destroy()
		end)
		tween:Play()
	end)
end

function NotificationController:Start()
	self._remote.OnClientEvent:Connect(function(message, nType, data)
		self:ShowNotification(message, nType)
	end)
end

return NotificationController
