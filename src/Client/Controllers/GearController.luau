local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local GearController = {
	Name = "GearController",
	Priority = 0,
}

local CAMERA = workspace.CurrentCamera
local DEFAULT_FOV = 70
local ZOOM_FOV = 55
local BLUR_SIZE = 15
local DEFAULT_GRAVITY = workspace.Gravity

function GearController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetGearRemote()
	self._movementLock = nil
	self._blur = nil
	self._cooldowns = {}
end

function GearController:_setMovementLocked(isLocked)
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

function GearController:_applyEffects(active)
	self:_setMovementLocked(active)
	
	local playerGui = self._player:FindFirstChild("PlayerGui")
	local mainHud = playerGui and playerGui:FindFirstChild("Main")
	if mainHud and mainHud:IsA("ScreenGui") then
		local isCarrying = self._player:GetAttribute("CarryingAnimal") == true
		for _, child in ipairs(mainHud:GetChildren()) do
			if child:IsA("GuiObject") and child.Name ~= "CoinsFrame" then
				if active then
					child.Visible = false
				else
					if isCarrying then
						child.Visible = (child.Name == "DropBtn")
					else
						child.Visible = (child.Name ~= "DropBtn")
					end
				end
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

function GearController:_bindGui(gui: ScreenGui)
	local main = gui:WaitForChild("Main")
	local backFrame = main:WaitForChild("BackFrame")
	local closeBtn = backFrame:WaitForChild("btn")
	local content = main:WaitForChild("Content")
	local scrollingFrame = content:WaitForChild("ScrollingFrame")
	
	local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
	local uiScale = main:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", main)

	local function setupGearItem(itemFrame, gearName, gearConfig)
		local btnFrame = itemFrame:WaitForChild("btnFrame")
		local buyBtn = btnFrame:WaitForChild("button")
		local priceLabel = buyBtn:FindFirstChildOfClass("TextLabel")
		
		if priceLabel then
			priceLabel.Text = NumberFormatter:Format(gearConfig.Price, "Letters")
		end
		
		buyBtn.MouseButton1Click:Connect(function()
			self._remote:FireServer("BuyGear", gearName)
		end)
	end

	-- Identify existing gear items or populate from config
	local template = scrollingFrame:FindFirstChild("Template")
	if template then
		template.Visible = false
		for gearName, gearConfig in pairs(self._config.Gear) do
			local item = template:Clone()
			item.Name = gearName
			item.Visible = true
			item.Parent = scrollingFrame
			setupGearItem(item, gearName, gearConfig)
		end
	else
		for _, item in ipairs(scrollingFrame:GetChildren()) do
			if item:IsA("Frame") and self._config.Gear[item.Name] then
				setupGearItem(item, item.Name, self._config.Gear[item.Name])
			end
		end
	end

	closeBtn.MouseButton1Click:Connect(function()
		self:_applyEffects(false)
		local tween = TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.7})
		TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
		tween.Completed:Connect(function()
			self._remote:FireServer("CloseGui")
		end)
		tween:Play()
	end)

	gui.Enabled = true
	uiScale.Scale = 0.5
	main.BackgroundTransparency = 1
	self:_applyEffects(true)
	
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
end

function GearController:_updateLocalWalkspeed(bonus)
	local humanoid = self._player.Character and self._player.Character:FindFirstChild("Humanoid")
	if humanoid then
		-- Fixed carrying speed or hiding state should always take priority
		if self._player:GetAttribute("IsHiding") then
			humanoid.WalkSpeed = 0
			return
		end
		
		if self._player:GetAttribute("CarryingAnimal") then
			humanoid.WalkSpeed = 19
			return
		end

		local StatCalculator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StatCalculator"))
		local stats = self._player:FindFirstChild("Stats")
		local upgrades = stats and stats:FindFirstChild("Upgrades")
		local wsLevelVal = upgrades and upgrades:FindFirstChild("Walkspeed")
		local level = wsLevelVal and wsLevelVal.Value or 1
		humanoid.WalkSpeed = StatCalculator.CalculateWalkspeed(level, self._config, bonus)
	end
end

function GearController:_onToolEquipped(tool: Tool)
	local gearName = tool.Name
	local gearConfig = self._config.Gear[gearName]
	if not gearConfig then return end

	-- Coil logic
	if gearName == "Speed Coil" then
		self._remote:FireServer("EquipGear", gearName)
		self:_updateLocalWalkspeed(gearConfig.SpeedBoost)
	elseif gearName == "Gravity Coil" then
		workspace.Gravity = DEFAULT_GRAVITY * gearConfig.GravityMultiplier
	end

	-- Activation logic
	if gearConfig.Cooldown then
		tool.Activated:Connect(function()
			local now = os.clock()
			local lastUse = self._cooldowns[gearName] or 0
			if now - lastUse < gearConfig.Cooldown then return end
			self._cooldowns[gearName] = now

			-- Animation
			local handle = tool:FindFirstChild("Handle")
			local animNode = handle and handle:FindFirstChild("Anim")
			if animNode and animNode:IsA("Animation") then
				local humanoid = self._player.Character and self._player.Character:FindFirstChild("Humanoid")
				local animator = humanoid and humanoid:FindFirstChild("Animator")
				if animator then
					local track = animator:LoadAnimation(animNode)
					track:Play()
				end
			end

			-- Hit detection (Client side prediction/help)
			local target = nil
			local mouse = self._player:GetMouse()
			local targetPart = mouse.Target
			if targetPart and targetPart.Parent:FindFirstChild("Humanoid") then
				target = targetPart.Parent
			elseif targetPart and targetPart.Parent.Parent:FindFirstChild("Humanoid") then
				target = targetPart.Parent.Parent
			end

			self._remote:FireServer("ActivateGear", gearName, target)
		end)
	end
end

function GearController:_onToolUnequipped(tool: Tool)
	local gearName = tool.Name
	local gearConfig = self._config.Gear[gearName]
	
	if gearName == "Speed Coil" then
		self._remote:FireServer("UnequipGear", gearName)
		self:_updateLocalWalkspeed(0)
	elseif gearName == "Gravity Coil" then
		workspace.Gravity = DEFAULT_GRAVITY
	end
end

function GearController:Start()
	self._remote.OnClientEvent:Connect(function(action)
		if action == "BindGui" then
			local playerGui = self._player:WaitForChild("PlayerGui")
			local gui = playerGui:WaitForChild("GearGui")
			if gui then
				self:_bindGui(gui)
			end
		end
	end)

	local function bindCharacter(character: Model)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				self:_onToolEquipped(child)
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				self:_onToolUnequipped(child)
			end
		end)
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then self:_onToolEquipped(child) end
		end
	end

	self._player.CharacterAdded:Connect(bindCharacter)
	if self._player.Character then
		bindCharacter(self._player.Character)
	end
end

return GearController
