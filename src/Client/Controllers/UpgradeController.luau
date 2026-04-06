local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local UpgradeController = {
	Name = "UpgradeController",
	Priority = 0,
}

local CAMERA = workspace.CurrentCamera
local DEFAULT_FOV = 70
local ZOOM_FOV = 55
local BLUR_SIZE = 15

function UpgradeController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetUpgradeRemote()
	self._movementLock = nil
	self._blur = nil
end

function UpgradeController:_setMovementLocked(isLocked)
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

		-- Sticky freeze: prevent server or other scripts from unfreezing while menu is open
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

function UpgradeController:_applyEffects(active)
	self:_setMovementLocked(active)
	
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

function UpgradeController:_bindGui(gui: ScreenGui)
	local main = gui:WaitForChild("Main")
	
	local backFrame = main:WaitForChild("BackFrame")
	local closeBtn = backFrame:FindFirstChildOfClass("TextButton") or backFrame
	
	local swordPanel = main:WaitForChild("SwordPanel")
	local speedPanel = main:WaitForChild("SpeedPanel")
	
	local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
	local player = self._player
	
	local uiScale = main:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = main
	end
	
	local StatCalculator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StatCalculator"))

	local function updateSwordUI()
		if not swordPanel or not swordPanel.Parent then return end
		
		local stats = player:WaitForChild("Stats")
		local swordVal = stats:WaitForChild("Swords")
		local currentSword = swordVal:FindFirstChild("CurrentSword") and swordVal.CurrentSword.Value or swordVal.Value
		local ownedSwords = stats:FindFirstChild("OwnedSwords")
		local levelVal = ownedSwords and ownedSwords:FindFirstChild(currentSword) or swordVal:FindFirstChild("Level")
		local level = levelVal and levelVal.Value or 1

		local config = self._config.Upgrades.Swords[currentSword] or self._config.Upgrades.Swords.Default
		local cost = math.floor(config.BaseCost * (config.CostMultiplier ^ (level - 1)))

		-- Get damage from player attribute
		local damage = player:GetAttribute("Damage") or 0

		local btnFrame = swordPanel:FindFirstChild("BtnFrame")
		if not btnFrame then return end
		local upgradeBtn = btnFrame:FindFirstChild("btn")
		if not upgradeBtn then return end
		local priceLabel = upgradeBtn:FindFirstChild("price")
		
		local lvlFrame = swordPanel:FindFirstChild("LvlFrame")
		local lvlLabel = lvlFrame and lvlFrame:FindFirstChild("lvl")
		
		local dmgFrame = swordPanel:FindFirstChild("DmgFrame")
		local dmgLabel = dmgFrame and dmgFrame:FindFirstChild("dmg")
		
		if priceLabel and (priceLabel:IsA("TextLabel") or priceLabel:IsA("TextBox")) then 
			priceLabel.Text = NumberFormatter:Format(cost, "Letters") 
		end
		if lvlLabel and (lvlLabel:IsA("TextLabel") or lvlLabel:IsA("TextBox")) then 
			lvlLabel.Text = string.format("%d/%d", level, config.MaxLevel) 
		end
		if dmgLabel and (dmgLabel:IsA("TextLabel") or dmgLabel:IsA("TextBox")) then 
			dmgLabel.Text = NumberFormatter:Format(damage, "Letters")
		end
		
		if level >= config.MaxLevel then
			if priceLabel and (priceLabel:IsA("TextLabel") or priceLabel:IsA("TextBox")) then 
				priceLabel.Text = "MAX" 
			end
		end
	end

	local function updateSpeedUI()
		if not speedPanel or not speedPanel.Parent then return end

		local stats = player:WaitForChild("Stats")
		local upgrades = stats:WaitForChild("Upgrades")
		local wsLevelVal = upgrades:WaitForChild("Walkspeed")
		local level = wsLevelVal and wsLevelVal.Value or 1
		
		local config = self._config.Upgrades.Walkspeed
		local cost = math.floor(config.BaseCost * (config.CostMultiplier ^ (level - 1)))
		local currentSpeed = StatCalculator.CalculateWalkspeed(level, self._config)
		
		local btnFrame = speedPanel:FindFirstChild("BtnFrame")
		if not btnFrame then return end
		local upgradeBtn = btnFrame:FindFirstChild("btn")
		if not upgradeBtn then return end
		local priceLabel = upgradeBtn:FindFirstChild("price")
		
		local lvlFrame = speedPanel:FindFirstChild("LvlFrame")
		local lvlLabel = lvlFrame and lvlFrame:FindFirstChild("lvl")
		
		local speedFrame = speedPanel:FindFirstChild("SpeedFrame")
		local speedLabel = speedFrame and speedFrame:FindFirstChild("speed")
		
		if priceLabel and (priceLabel:IsA("TextLabel") or priceLabel:IsA("TextBox")) then 
			priceLabel.Text = NumberFormatter:Format(cost, "Letters") 
		end
		if lvlLabel and (lvlLabel:IsA("TextLabel") or lvlLabel:IsA("TextBox")) then 
			lvlLabel.Text = string.format("%d/%d", level, config.MaxLevel) 
		end
		if speedLabel and (speedLabel:IsA("TextLabel") or speedLabel:IsA("TextBox")) then 
			speedLabel.Text = NumberFormatter:Format(currentSpeed, "Letters")
		end
		
		if level >= config.MaxLevel then
			if priceLabel and (priceLabel:IsA("TextLabel") or priceLabel:IsA("TextBox")) then 
				priceLabel.Text = "MAX" 
			end
		end
	end

	local sBtnFrame = swordPanel:FindFirstChild("BtnFrame")
	local sBtn = sBtnFrame and sBtnFrame:FindFirstChild("btn")
	if sBtn and sBtn:IsA("GuiButton") then
		sBtn.MouseButton1Click:Connect(function()
			local stats = player:FindFirstChild("Stats")
			if not stats then return end
			local swordVal = stats:FindFirstChild("Swords")
			local currentSword = swordVal and (swordVal:FindFirstChild("CurrentSword") and swordVal.CurrentSword.Value or swordVal.Value) or "Default"
			local ownedSwords = stats:FindFirstChild("OwnedSwords")
			local levelVal = ownedSwords and ownedSwords:FindFirstChild(currentSword) or (swordVal and swordVal:FindFirstChild("Level"))
			local level = levelVal and levelVal.Value or 1
			local config = self._config.Upgrades.Swords[currentSword] or self._config.Upgrades.Swords.Default
			
			if level < config.MaxLevel then
				self._remote:FireServer("UpgradeSword")
			end
		end)
	end
	
	local spBtnFrame = speedPanel:FindFirstChild("BtnFrame")
	local spBtn = spBtnFrame and spBtnFrame:FindFirstChild("btn")
	if spBtn and spBtn:IsA("GuiButton") then
		spBtn.MouseButton1Click:Connect(function()
			local stats = player:FindFirstChild("Stats")
			if not stats then return end
			local upgrades = stats:FindFirstChild("Upgrades")
			local wsLevelVal = upgrades and upgrades:FindFirstChild("Walkspeed")
			local level = wsLevelVal and wsLevelVal.Value or 1
			local config = self._config.Upgrades.Walkspeed
			
			if level < config.MaxLevel then
				self._remote:FireServer("UpgradeWalkspeed")
			end
		end)
	end


	if closeBtn then
		closeBtn.MouseButton1Click:Connect(function()
			self:_applyEffects(false)
			local tween = TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.7})
			TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
			tween.Completed:Connect(function()
				self._remote:FireServer("CloseGui")
			end)
			tween:Play()
		end)
	end

	local stats = player:WaitForChild("Stats")
	stats:WaitForChild("Swords").Changed:Connect(updateSwordUI)
	local ownedSwords = stats:FindFirstChild("OwnedSwords")
	if ownedSwords then
		ownedSwords.ChildAdded:Connect(updateSwordUI)
		ownedSwords.DescendantAdded:Connect(updateSwordUI)
		ownedSwords.DescendantRemoving:Connect(updateSwordUI)
		for _, child in ipairs(ownedSwords:GetChildren()) do
			child.Changed:Connect(updateSwordUI)
		end
	else
		stats.Swords:WaitForChild("Level").Changed:Connect(updateSwordUI)
	end
	stats:WaitForChild("Upgrades"):WaitForChild("Walkspeed").Changed:Connect(function(newLevel)
		updateSpeedUI()
		if self._movementLock then
			self._movementLock.WalkSpeed = StatCalculator.CalculateWalkspeed(newLevel, self._config)
		end
	end)
	
	updateSwordUI()
	updateSpeedUI()
	
	-- Play pop-in effects immediately when bound
	gui.Enabled = true
	uiScale.Scale = 0.5
	main.BackgroundTransparency = 1
	self:_applyEffects(true)
	
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
end

function UpgradeController:Start()
	self._remote.OnClientEvent:Connect(function(action)
		if action == "BindGui" then
			local playerGui = self._player:WaitForChild("PlayerGui")
			local gui = playerGui:WaitForChild("UpgradeGui")
			if gui then
				self:_bindGui(gui)
			end
		end
	end)
end

return UpgradeController
