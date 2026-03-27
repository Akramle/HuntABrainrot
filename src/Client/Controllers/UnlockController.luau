local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScreenEffects = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ScreenEffects"))

local UnlockController = {
	Name = "UnlockController",
	Priority = 5,
}

local CAMERA = workspace.CurrentCamera
local DEFAULT_FOV = 70
local ZOOM_FOV = 55
local BLUR_SIZE = 15

function UnlockController:Init(runtime)
	self._player = Players.LocalPlayer
	self._runtime = runtime
	self._unlockRemote = nil
	self._movementLock = nil
	self._blur = nil
	self._hiddenUnlockers = {}
end

function UnlockController:_hideUnlocker(model)
	if not model then return end
	if model.Parent then
		self._hiddenUnlockers[model] = model.Parent
		model.Parent = nil
	end
end

function UnlockController:_showUnlockerForArea(areaName)
	for model, originalParent in pairs(self._hiddenUnlockers) do
		local areaVal = model:FindFirstChild("Area")
		if areaVal and areaVal.Value == areaName then
			model.Parent = originalParent
			self._hiddenUnlockers[model] = nil
		end
	end
end

function UnlockController:_setMovementLocked(isLocked)
	local character = self._player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then return end

	if isLocked then
		if self._movementLock ~= nil then return end
		self._movementLock = {
			WalkSpeed = humanoid.WalkSpeed,
			AutoRotate = humanoid.AutoRotate,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
			UseJumpPower = humanoid.UseJumpPower,
		}
		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		if humanoid.UseJumpPower then
			humanoid.JumpPower = 0
		else
			humanoid.JumpHeight = 0
		end

		self._wsConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if humanoid.WalkSpeed ~= 0 then
				humanoid.WalkSpeed = 0
			end
		end)
	else
		if self._movementLock == nil then return end

		if self._wsConnection then
			self._wsConnection:Disconnect()
			self._wsConnection = nil
		end

		humanoid.WalkSpeed = self._movementLock.WalkSpeed
		humanoid.AutoRotate = self._movementLock.AutoRotate
		if self._movementLock.UseJumpPower then
			humanoid.JumpPower = self._movementLock.JumpPower
		else
			humanoid.JumpHeight = self._movementLock.JumpHeight
		end
		self._movementLock = nil
	end
end

function UnlockController:_applyEffects(active)
	self:_setMovementLocked(active)
	
	-- Toggle Main HUD visibility
	local playerGui = self._player:FindFirstChild("PlayerGui")
	local mainHud = playerGui and playerGui:FindFirstChild("Main")
	if mainHud and mainHud:IsA("ScreenGui") then
		for _, child in ipairs(mainHud:GetChildren()) do
			if child:IsA("GuiObject") and child.Name ~= "CoinsFrame" then
				child.Visible = not active
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

function UnlockController:_hookUpGui(screenGui: ScreenGui)
	if screenGui.Name ~= "AlertGui" then return end
	
	local main = screenGui:FindFirstChild("main")
	if not main then return end
	
	local acceptBtn = main:FindFirstChild("btn")
	local buyFrame = main:FindFirstChild("BuyFrame")
	local backFrame = main:FindFirstChild("BackFrame")
	local closeBtn = backFrame and backFrame:FindFirstChild("btn")
	local resultLabel = main:FindFirstChild("result")
	
	-- Initial state for juice
	local uiScale = main:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = main
	end
	
	uiScale.Scale = 0.5
	main.BackgroundTransparency = 1
	
	self:_applyEffects(true)
	
	-- Pop-in animation
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()

	local function closeGui()
		self:_applyEffects(false)
		TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.7 }):Play()
		local tween = TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
		tween.Completed:Connect(function()
			screenGui:Destroy()
		end)
		tween:Play()
	end
	
	if acceptBtn then
		acceptBtn.MouseButton1Click:Connect(function()
			local areaName = screenGui:GetAttribute("AreaName")
			local price = screenGui:GetAttribute("Price")
			local unlockerRefObj = screenGui:FindFirstChild("UnlockerRef")
			local unlockerRef = unlockerRefObj and unlockerRefObj.Value
			
			if not areaName or not price then 
				closeGui()
				return 
			end
			
			local success = self._unlockRemote:InvokeServer(areaName, price)
			if success then
				if resultLabel then
					resultLabel.Text = "AREA UNLOCKED!"
					resultLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
				end
				
				-- Trigger confetti burst
				ScreenEffects.ConfettiBurst(self._player)
				
				-- Feedback scale juice
				TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
				task.delay(0.2, function()
					if uiScale.Parent then
						TweenService:Create(uiScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 1}):Play()
					end
				end)

				if unlockerRef and unlockerRef.Parent then
					self:_hideUnlocker(unlockerRef)
				end

				
				task.delay(1.2, function()
					closeGui()
				end)
			else
				if resultLabel then
					resultLabel.Text = "NOT ENOUGH BUCKS!"
					resultLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
					
					-- Shake juice
					local originalPos = main.Position
					task.spawn(function()
						for i = 1, 6 do
							main.Position = originalPos + UDim2.fromOffset(math.random(-10, 10), math.random(-5, 5))
							task.wait(0.05)
						end
						main.Position = originalPos
					end)

					task.delay(2, function()
						if resultLabel.Parent and resultLabel.Text == "NOT ENOUGH BUCKS!" then
							resultLabel.Text = ""
						end
					end)
				end
			end
		end)
	end
	
	if closeBtn then
		closeBtn.MouseButton1Click:Connect(closeGui)
	elseif backFrame and backFrame:IsA("GuiButton") then
		backFrame.MouseButton1Click:Connect(closeGui)
	end
end

function UnlockController:Start()
	self._unlockRemote = self._runtime.Remotes:GetAreaUnlockRemote()
	
	local playerGui = self._player:WaitForChild("PlayerGui")
	
	playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") and child.Name == "AlertGui" then
			self:_hookUpGui(child)
		end
	end)
	
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name == "AlertGui" then
			self:_hookUpGui(child)
		end
	end

	local stats = self._player:WaitForChild("Stats")
	local unlockedAreas = stats:WaitForChild("UnlockedAreas")
	
	local function checkUnlocker(model)
		local areaVal = model:FindFirstChild("Area")
		if areaVal and unlockedAreas:FindFirstChild(areaVal.Value) then
			self:_hideUnlocker(model)
		end
	end

	for _, model in ipairs(CollectionService:GetTagged("Unlocker")) do
		checkUnlocker(model)
	end

	CollectionService:GetInstanceAddedSignal("Unlocker"):Connect(checkUnlocker)
	
	unlockedAreas.ChildAdded:Connect(function(areaBool)
		for _, model in ipairs(CollectionService:GetTagged("Unlocker")) do
			local areaVal = model:FindFirstChild("Area")
			if areaVal and areaVal.Value == areaBool.Name then
				self:_hideUnlocker(model)
			end
		end
	end)
	
	unlockedAreas.ChildRemoved:Connect(function(areaBool)
		self:_showUnlockerForArea(areaBool.Name)
	end)
end

return UnlockController
