-- src/Client/Controllers/SwordController.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local SwordController = {
	Name = "SwordController",
	Priority = 0,
}

local CAMERA = workspace.CurrentCamera
local DEFAULT_FOV = 70
local ZOOM_FOV = 55
local BLUR_SIZE = 15

function SwordController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")

	self._swordsGuiRemote = runtime.Remotes:GetSwordsGuiRemote()
	self._purchaseSwordRemote = runtime.Remotes:GetPurchaseSwordRemote()
	self._equipSwordRemote = runtime.Remotes:GetEquipSwordRemote()

	self._movementLock = nil
	self._blur = nil
	self._originalColors = {}
end

function SwordController:_setMovementLocked(isLocked)
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

function SwordController:_applyEffects(active)
	self:_setMovementLocked(active)
	
	local mainHud = self._playerGui and self._playerGui:FindFirstChild("Main")
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

function SwordController:_bindGui(gui: ScreenGui)
	local main = gui:WaitForChild("Main")
	local backFrame = main:WaitForChild("BackFrame")
	local closeBtn = backFrame:WaitForChild("btn")
	local content = main:WaitForChild("Content")
	local scrollingFrame = content:WaitForChild("ScrollingFrame")

	local uiScale = main:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = main
	end

	local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
	local player = self._player
	local stats = player:WaitForChild("Stats")
	local ownedSwords = stats:WaitForChild("OwnedSwords")
	local currentSword = stats:WaitForChild("Swords"):WaitForChild("CurrentSword")

	local function updateAllSwordCards()
		if not scrollingFrame or not scrollingFrame.Parent then return end

		local swordConfigs = self._config.Upgrades.Swords
		for swordName, swordConfig in pairs(swordConfigs) do
			if swordName == "Default" then continue end
			
			local card = scrollingFrame:FindFirstChild(swordName)
			if not card then continue end

			local btnFrame = card:FindFirstChild("btnFrame")
			if not btnFrame then continue end
			local button = btnFrame:FindFirstChild("button")
			if not button then continue end
			local textLabel = button:FindFirstChild("TextLabel")
			local imageLabel = button:FindFirstChild("ImageLabel")
			local dmgStat = card:FindFirstChild("dmgStat")
			if not dmgStat then continue end
			local dmgLabel = dmgStat:FindFirstChild("dmg")
			if not dmgLabel then continue end

			if not self._originalColors[swordName] then
				self._originalColors[swordName] = btnFrame.BackgroundColor3
			end

			local isOwned = ownedSwords:FindFirstChild(swordName) ~= nil
			local isEquipped = (currentSword.Value == swordName)

			-- Update Damage Stat
			dmgLabel.Text = NumberFormatter:Format(swordConfig.BaseDamage, "Letters")

			if isOwned then
				if imageLabel then imageLabel.Visible = false end
				textLabel.Size = UDim2.new(1, 0, 1, 0)

				if isEquipped then
					textLabel.Text = "Equipped"
					btnFrame.BackgroundColor3 = Color3.fromRGB(120, 120, 120) -- Gray
				else
					textLabel.Text = "Equip"
					btnFrame.BackgroundColor3 = self._originalColors[swordName]
				end
			else
				if imageLabel then imageLabel.Visible = true end
				textLabel.Size = UDim2.new(0.7, 0, 1, 0)
				textLabel.Text = NumberFormatter:Format(swordConfig.Cost, "Letters")
				btnFrame.BackgroundColor3 = self._originalColors[swordName]
			end
		end
	end

	for _, card in ipairs(scrollingFrame:GetChildren()) do
		if card:IsA("GuiObject") and self._config.Upgrades.Swords[card.Name] then
			local btnFrame = card:WaitForChild("btnFrame")
			local button = btnFrame:WaitForChild("button")
			button.MouseButton1Click:Connect(function()
				local swordName = card.Name
				local isOwned = ownedSwords:FindFirstChild(swordName) ~= nil
				local isEquipped = (currentSword.Value == swordName)

				if isOwned then
					if not isEquipped then
						self._equipSwordRemote:FireServer(swordName)
					end
				else
					self._purchaseSwordRemote:FireServer(swordName)
				end
			end)
		end
	end
	
	closeBtn.MouseButton1Click:Connect(function()
		self:_applyEffects(false)
		local tween = TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.7})
		TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
		tween.Completed:Connect(function()
			self._swordsGuiRemote:FireServer("CloseGui")
		end)
		tween:Play()
	end)

	ownedSwords.ChildAdded:Connect(updateAllSwordCards)
	ownedSwords.ChildRemoved:Connect(updateAllSwordCards)
	currentSword.Changed:Connect(updateAllSwordCards)
	
	updateAllSwordCards()

	gui.Enabled = true
	uiScale.Scale = 0.5
	main.BackgroundTransparency = 1
	self:_applyEffects(true)
	
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
end

function SwordController:Start()
	self._swordsGuiRemote.OnClientEvent:Connect(function(action)
		if action == "BindGui" then
			local gui = self._playerGui:WaitForChild("SwordsGui")
			if gui then
				self:_bindGui(gui)
			end
		end
	end)
end

return SwordController
