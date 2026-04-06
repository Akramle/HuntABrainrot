local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ScreenEffects = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ScreenEffects"))
local ViewportHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ViewportHelper"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local MerchantController = {
	Name = "MerchantController",
	Priority = 0,
}

local CAMERA = workspace.CurrentCamera
local DEFAULT_FOV = 70
local ZOOM_FOV = 55
local BLUR_SIZE = 15

local RARITY_SETTINGS = GameConfig.RaritySettings

function MerchantController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetMerchantRemote()
	
	self._movementLock = nil
	self._blur = nil
	self._playSellFeedback = nil
end

function MerchantController:_setMovementLocked(isLocked)
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
			if humanoid.WalkSpeed ~= 0 then humanoid.WalkSpeed = 0 end
		end)
	else
		if self._movementLock == nil then return end
		if self._wsConnection then self._wsConnection:Disconnect() self._wsConnection = nil end
		humanoid.WalkSpeed = self._movementLock.WalkSpeed
		humanoid.AutoRotate = self._movementLock.AutoRotate
		if self._movementLock.UseJumpPower then humanoid.JumpPower = self._movementLock.JumpPower else humanoid.JumpHeight = self._movementLock.JumpHeight end
		self._movementLock = nil
	end
end

function MerchantController:_applyEffects(active)
	self:_setMovementLocked(active)
	
	local playerGui = self._player:WaitForChild("PlayerGui")
	local mainHud = playerGui:FindFirstChild("Main")
	if mainHud then
		-- In Merchant GUI, we do NOT hide the inventory buttons (per request),
		-- but we might want to hide others like CoinsFrame if they overlap.
		-- Actually, user said: "this gui does not hide the inventory"
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

function MerchantController:_bindGui(gui: ScreenGui)
	local main = gui:WaitForChild("Main")
	local backFrame = main:WaitForChild("BackFrame")
	local closeBtn = backFrame:WaitForChild("btn")
	local sellAllSection = main:WaitForChild("SellAll")
	local sellAnimalSection = main:WaitForChild("SellAnimal")
	local animalIcon = sellAnimalSection:WaitForChild("AnimalIcon")
	local viewport = animalIcon:WaitForChild("ViewportFrame")
	local defaultIcon = animalIcon:WaitForChild("icon")
	local gradient = sellAnimalSection:WaitForChild("UIGradient")
	local sellBtn = sellAnimalSection:WaitForChild("SellBtn")
	
	local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
	local uiScale = main:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", main)
	
	local stats = self._player:WaitForChild("Stats")
	local merchantFolder = stats:WaitForChild("Merchant")
	local sellAllUnlocked = merchantFolder:WaitForChild("SellAllUnlocked")

	local lastAnimalName = ""

	local function applyPop(obj)
		if obj:IsA("GuiObject") and obj.AnchorPoint ~= Vector2.new(0.5, 0.5) then
			local oldAP = obj.AnchorPoint
			local newAP = Vector2.new(0.5, 0.5)
			
			-- Adjust position to compensate for anchor point change
			obj.Position = UDim2.new(
				obj.Position.X.Scale + ((newAP.X - oldAP.X) * obj.Size.X.Scale),
				obj.Position.X.Offset + ((newAP.X - oldAP.X) * obj.Size.X.Offset),
				obj.Position.Y.Scale + ((newAP.Y - oldAP.Y) * obj.Size.Y.Scale),
				obj.Position.Y.Offset + ((newAP.Y - oldAP.Y) * obj.Size.Y.Offset)
			)
			obj.AnchorPoint = newAP
		end

		local scale = obj:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = obj
		end
		scale.Scale = 0.7
		TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end

	local function applyPulse(obj: GuiObject, peakScale: number?)
		local scale = obj:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = obj
		end
		scale.Scale = 1
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = peakScale or 1.08
		}):Play()
		task.delay(0.12, function()
			if scale and scale.Parent then
				TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1
				}):Play()
			end
		end)
	end

	local function playSellFeedback(payload)
		if not gui or not gui.Parent then return end

		local sellType = (payload and payload.SellType) or "SellAnimal"
		local isSellAll = sellType == "SellAll"
		local isUnlock = sellType == "SellAllUnlock"
		local isSellAllRelated = isSellAll or isUnlock

		ScreenEffects.RewardEffect(self._player, {
			CameraIntensity = isUnlock and 18 or (isSellAll and 16 or 12),
			Confetti = false,
			ConfettiAmount = 0,
		})

		applyPulse(main, 1.03)
		if isSellAllRelated then
			applyPulse(sellAllSection, 1.05)
			applyPulse(sellAllSection:WaitForChild("SellBtn"), 1.09)
			local quantityLabel = sellAllSection:FindFirstChild("Quantity")
			if quantityLabel and quantityLabel:IsA("GuiObject") then
				applyPulse(quantityLabel, 1.1)
			end
		else
			applyPulse(sellAnimalSection, 1.05)
			applyPulse(sellBtn, 1.09)
			local amountLabel = animalIcon:FindFirstChild("amount")
			if amountLabel and amountLabel:IsA("GuiObject") and amountLabel.Visible then
				applyPulse(amountLabel, 1.1)
			end
		end

		local soundController = self._runtime:GetController("SoundController")
		if soundController then
			soundController:PlayLocal("Sell", {randomPitch = true})
		end
	end

	self._playSellFeedback = playSellFeedback

	local function refreshUI()
		if not gui or not gui.Parent then return end
		
		-- 1. Sell All Section
		local isUnlocked = sellAllUnlocked.Value
		sellAllSection:WaitForChild("SellBtn").Visible = isUnlocked
		sellAllSection:WaitForChild("txt").Visible = isUnlocked
		sellAllSection:WaitForChild("buyBucks").Visible = not isUnlocked
		sellAllSection:WaitForChild("buyRBX").Visible = not isUnlocked
		sellAllSection:WaitForChild("txt2").Visible = not isUnlocked
		
		local totalValue = 0
		local animalCount = 0
		local backpack = self._player:FindFirstChild("Backpack")
		if backpack then
			for _, tool in ipairs(backpack:GetChildren()) do
				if CollectionService:HasTag(tool, "Animal") then
					totalValue += (tool:GetAttribute("Cost") or 0)
					animalCount += 1
				end
			end
		end
		local char = self._player.Character
		if char then
			for _, child in ipairs(char:GetChildren()) do
				if child:IsA("Tool") and CollectionService:HasTag(child, "Animal") then
					totalValue += (child:GetAttribute("Cost") or 0)
					animalCount += 1
				end
			end
		end

		if isUnlocked then
			sellAllSection.SellBtn:WaitForChild("price").Text = NumberFormatter:Format(totalValue, "Letters")
		end

		local quantityLabel = sellAllSection:FindFirstChild("Quantity")
		if quantityLabel and quantityLabel:IsA("TextLabel") then
			quantityLabel.Text = tostring(animalCount) .. " Brainrots"
		end
		
		-- 2. Sell Animal Section (Equipped Tool)
		local equippedAnimal = nil
		if char then
			for _, child in ipairs(char:GetChildren()) do
				if child:IsA("Tool") and CollectionService:HasTag(child, "Animal") then
					equippedAnimal = child
					break
				end
			end
		end
		
		local currentName = equippedAnimal and equippedAnimal.Name or "None"
		local hasChanged = (currentName ~= lastAnimalName)
		lastAnimalName = currentName

		local amountLabel = animalIcon:FindFirstChild("amount")

		if equippedAnimal then
			local rarity = equippedAnimal:GetAttribute("Rarity") or "Common"
			local info = RARITY_SETTINGS[rarity]
			local color = info and info.Top or Color3.new(1,1,1)
			local darkColor = info and info.Bottom or Color3.new(color.R * 0.7, color.G * 0.7, color.B * 0.7)
			
			local isLuckyBlock = equippedAnimal:GetAttribute("IsLuckyBlock")

			if hasChanged then
				TweenService:Create(animalIcon, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = color}):Play()
				gradient.Color = ColorSequence.new(color, darkColor)
				
				applyPop(sellAnimalSection:WaitForChild("name"))
				applyPop(sellAnimalSection:WaitForChild("rarity"))
				applyPop(sellAnimalSection:WaitForChild("level"))
				applyPop(sellAnimalSection:WaitForChild("revenue"))
				applyPop(sellBtn:WaitForChild("price"))
				if amountLabel then applyPop(amountLabel) end
			end

			-- Specific count for this animal type
			local speciesCount = 0
			if backpack then
				for _, t in ipairs(backpack:GetChildren()) do
					if t.Name == equippedAnimal.Name and CollectionService:HasTag(t, "Animal") then
						speciesCount += 1
					end
				end
			end
			if char then
				for _, t in ipairs(char:GetChildren()) do
					if t.Name == equippedAnimal.Name and CollectionService:HasTag(t, "Animal") then
						speciesCount += 1
					end
				end
			end
			if amountLabel and amountLabel:IsA("TextLabel") then
				amountLabel.Text = "x" .. tostring(speciesCount)
				amountLabel.Visible = true
			end

			sellAnimalSection:WaitForChild("name").Text = equippedAnimal.Name or "Unknown"
			sellAnimalSection:WaitForChild("rarity").Text = isLuckyBlock and "Lucky Block" or rarity
			
			local level = (equippedAnimal:GetAttribute("Level") or 1) + (equippedAnimal:GetAttribute("UpgradeLevel") or 0)
			sellAnimalSection:WaitForChild("level").Text = isLuckyBlock and "-" or "lvl: " .. tostring(level)
			
			local revenue = equippedAnimal:GetAttribute("Revenue") or 0
			sellAnimalSection:WaitForChild("revenue").Text = isLuckyBlock and "-" or NumberFormatter:Format(revenue, "Letters") .. "/s"
			
			local cost = equippedAnimal:GetAttribute("Cost") or 0
			
			if isLuckyBlock then
				sellBtn:WaitForChild("price").Text = "Cannot Sell"
				sellBtn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
				sellBtn.Active = false
				sellBtn.Interactable = false
			else
				sellBtn:WaitForChild("price").Text = NumberFormatter:Format(cost, "Letters")
				sellBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				sellBtn.Active = true
				sellBtn.Interactable = true
			end
			
			-- Viewport logic
			if hasChanged then
				defaultIcon.Visible = false
				viewport.Visible = true
				ViewportHelper.SetupViewport(viewport, equippedAnimal, {
					SpinSpeed = 1.2,
					FieldOfView = 25
				})
			end
		else
			if hasChanged then
				TweenService:Create(animalIcon, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = Color3.new(1,1,1)}):Play()
				gradient.Color = ColorSequence.new(Color3.new(1,1,1))
				
				applyPop(sellAnimalSection:WaitForChild("name"))
				applyPop(sellAnimalSection:WaitForChild("rarity"))
				applyPop(sellAnimalSection:WaitForChild("level"))
				applyPop(sellAnimalSection:WaitForChild("revenue"))
				applyPop(sellBtn:WaitForChild("price"))
			end

			sellAnimalSection:WaitForChild("name").Text = "Hold an animal..."
			sellAnimalSection:WaitForChild("rarity").Text = "loading..."
			sellAnimalSection:WaitForChild("level").Text = "loading..."
			sellAnimalSection:WaitForChild("revenue").Text = "loading..."
			sellBtn:WaitForChild("price").Text = "0"
			ViewportHelper.ClearViewport(viewport)
			viewport.Visible = false
			defaultIcon.Visible = true
		end
	end
	
	-- Connect buttons
	sellAllSection.SellBtn.btn.MouseButton1Click:Connect(function()
		self._remote:FireServer("SellAll")
	end)
	sellAllSection.buyBucks.btn.MouseButton1Click:Connect(function()
		self._remote:FireServer("UnlockSellAllBucks")
	end)
	sellAllSection.buyRBX.btn.MouseButton1Click:Connect(function()
		self._remote:FireServer("UnlockSellAllRBX")
	end)
	sellAnimalSection.SellBtn.btn.MouseButton1Click:Connect(function()
		self._remote:FireServer("SellAnimal")
	end)
	
	closeBtn.MouseButton1Click:Connect(function()
		self:_applyEffects(false)
		local tween = TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.7})
		TweenService:Create(main, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
		tween.Completed:Connect(function()
			self._remote:FireServer("CloseGui")
		end)
		tween:Play()
	end)
	
	sellAllUnlocked.Changed:Connect(refreshUI)
	
	local char = self._player.Character or self._player.CharacterAdded:Wait()
	char.ChildAdded:Connect(refreshUI)
	char.ChildRemoved:Connect(refreshUI)
	
	local backpack = self._player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(refreshUI)
	backpack.ChildRemoved:Connect(refreshUI)
	
	refreshUI()
	
	gui.Enabled = true
	uiScale.Scale = 0.5
	main.BackgroundTransparency = 1
	self:_applyEffects(true)
	
	TweenService:Create(uiScale, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(main, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()

	gui.Destroying:Connect(function()
		if self._playSellFeedback == playSellFeedback then
			self._playSellFeedback = nil
		end
	end)
end

function MerchantController:Start()
	self._remote.OnClientEvent:Connect(function(action, payload)
		if action == "OpenGui" then
			local playerGui = self._player:WaitForChild("PlayerGui")
			local gui = playerGui:WaitForChild("MerchantGui")
			if gui then
				self:_bindGui(gui)
			end
		elseif action == "SellSuccess" then
			if self._playSellFeedback then
				self._playSellFeedback(payload)
			else
				local sellType = (payload and payload.SellType) or "SellAnimal"
				local isSellAll = sellType == "SellAll"
				local isUnlock = sellType == "SellAllUnlock"
				ScreenEffects.RewardEffect(self._player, {
					CameraIntensity = isUnlock and 18 or (isSellAll and 16 or 12),
					Confetti = false,
					ConfettiAmount = 0
				})
				local soundController = self._runtime:GetController("SoundController")
				if soundController then
					soundController:PlayLocal("Sell", {randomPitch = true})
				end
			end
		elseif action == "Refresh" then
			-- Logic for refresh is already tied to attribute/value changes, 
			-- but we can trigger it manually if needed.
		end
	end)
end

return MerchantController
