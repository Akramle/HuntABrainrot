local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local ScreenEffects = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ScreenEffects"))

local EffectsController = {
	Name = "EffectsController",
	Priority = 0,
}

local function getPrimaryPart(target)
	if target == nil then return nil end
	if target:IsA("BasePart") then return target end
	if target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

function EffectsController:Init(runtime)
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetEffectsRemote()
	self._dropsFolder = Workspace:WaitForChild("Drops")
	self._runtime = runtime
	self._modelBaseScales = setmetatable({}, {__mode = "k"})
	self._partBaseSizes = setmetatable({}, {__mode = "k"})
	self._modelBaseCFrames = setmetatable({}, {__mode = "k"})
	self._activeScaleDrivers = setmetatable({}, {__mode = "k"})
	self._activePartTweens = setmetatable({}, {__mode = "k"})
	self._dropAnimations = setmetatable({}, {__mode = "k"})
	self._dropSpinConnection = nil
	self._shakeConnection = nil
	self._shakeUntil = 0
	self._shakeStrength = 0
	self._lastRockSpawnByAnimal = setmetatable({}, {__mode = "k"})
	self._activeFloatingTexts = 0
	self._maxFloatingTexts = 24
	self._lastFloatingTextAt = 0
	self._lastDeliveredEffectAt = 0
	self._lastAnimalHitFxAt = 0
end

function EffectsController:_ensureDropSpinLoop()
	if self._dropSpinConnection and self._dropSpinConnection.Connected then
		return
	end

	self._dropSpinConnection = RunService.Heartbeat:Connect(function(dt)
		local hasDrops = false
		for drop, spinSpeed in pairs(self._dropAnimations) do
			if drop and drop.Parent then
				hasDrops = true
				drop:PivotTo(drop:GetPivot() * CFrame.Angles(0, math.rad(spinSpeed * dt), 0))
			else
				self._dropAnimations[drop] = nil
			end
		end

		if not hasDrops and self._dropSpinConnection then
			self._dropSpinConnection:Disconnect()
			self._dropSpinConnection = nil
		end
	end)
end

function EffectsController:_shakeCamera(intensity, duration)
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local now = os.clock()
	self._shakeUntil = math.max(self._shakeUntil, now + duration)
	self._shakeStrength = math.max(self._shakeStrength, intensity)

	if self._shakeConnection and self._shakeConnection.Connected then
		return
	end

	self._shakeConnection = RunService.RenderStepped:Connect(function(dt)
		if camera ~= Workspace.CurrentCamera then
			camera = Workspace.CurrentCamera
			if not camera then
				if self._shakeConnection then
					self._shakeConnection:Disconnect()
					self._shakeConnection = nil
				end
				self._shakeStrength = 0
				self._shakeUntil = 0
				return
			end
		end

		local t = os.clock()
		if t >= self._shakeUntil or self._shakeStrength <= 0.001 then
			if self._shakeConnection then
				self._shakeConnection:Disconnect()
				self._shakeConnection = nil
			end
			self._shakeStrength = 0
			return
		end

		local fade = math.clamp((self._shakeUntil - t) / 0.2, 0, 1)
		local currentIntensity = self._shakeStrength * fade
		local offset = Vector3.new(
			(math.random() - 0.5) * 2 * currentIntensity,
			(math.random() - 0.5) * 2 * currentIntensity,
			(math.random() - 0.5) * 2 * currentIntensity
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset)

		local decay = math.max(0, 1 - (dt * 10))
		self._shakeStrength *= decay
	end)
end

function EffectsController:_screenFlash(color, duration, maxTransparency)
	local player = self._runtime.Player
	local pGui = player:FindFirstChild("PlayerGui")
	if not pGui then return end
	
	local screenGui = pGui:FindFirstChild("HitFlashGui") or Instance.new("ScreenGui")
	screenGui.Name = "HitFlashGui"
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 10000
	screenGui.Parent = pGui
	
	local flash = screenGui:FindFirstChild("Flash") or Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = screenGui
	
	flash.BackgroundTransparency = maxTransparency
	TweenService:Create(flash, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
end

function EffectsController:_flashHighlight(target, color, startingTransparency, duration)
	if target == nil or target.Parent == nil then return end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = startingTransparency
	highlight.OutlineTransparency = 1
	highlight.Parent = target

	TweenService:Create(highlight, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
	}):Play()
	Debris:AddItem(highlight, duration + 0.05)
end

function EffectsController:_spawnFloatingText(worldPosition, text, textColor, strokeColor, size, riseHeight, lifetime, extraOptions)
	local now = os.clock()
	if self._activeFloatingTexts >= self._maxFloatingTexts then
		return
	end
	if (now - self._lastFloatingTextAt) < 0.02 then
		return
	end
	self._lastFloatingTextAt = now
	self._activeFloatingTexts += 1

	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	
	extraOptions = extraOptions or {}
	local spreadMult = extraOptions.spreadMultiplier or 1
	
	local randomOffset = Vector3.new(
		(math.random() - 0.5) * 2.5 * spreadMult,
		(math.random() - 0.5) * 1 * spreadMult,
		(math.random() - 0.5) * 2.5 * spreadMult
	)
	attachment.WorldPosition = worldPosition + randomOffset

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(size * 4, 0, size, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = attachment
	billboard.Parent = attachment

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 0, 0, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = extraOptions.flashWhite and Color3.new(1, 1, 1) or textColor
	label.TextStrokeColor3 = strokeColor
	label.TextStrokeTransparency = 0
	label.Font = (math.random() > 0.5) and Enum.Font.FredokaOne or Enum.Font.GothamBlack
	label.TextScaled = true
	
	local initialRotation = (math.random() - 0.5) * 55
	label.Rotation = initialRotation
	label.Parent = billboard
	
	TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 1, 0),
		Rotation = initialRotation * 0.15
	}):Play()

	if extraOptions.flashWhite then
		task.delay(0.06, function()
			if label.Parent then
				TweenService:Create(label, TweenInfo.new(0.15), {TextColor3 = textColor}):Play()
			end
		end)
	end

	local targetPosition = attachment.WorldPosition + Vector3.new(
		(math.random() - 0.5) * 3.5 * spreadMult, 
		riseHeight, 
		(math.random() - 0.5) * 3.5 * spreadMult
	)
	
	TweenService:Create(attachment, TweenInfo.new(lifetime, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		WorldPosition = targetPosition,
	}):Play()

	local rockTween = TweenService:Create(label, TweenInfo.new(lifetime * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Rotation = initialRotation * -0.3
	})
	rockTween:Play()

	task.delay(lifetime * 0.6, function()
		if label.Parent then
			rockTween:Cancel()
			TweenService:Create(label, TweenInfo.new(lifetime * 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
				Size = UDim2.new(0, 0, 0, 0),
				Rotation = initialRotation * 2.5 
			}):Play()
		end
	end)

	Debris:AddItem(attachment, lifetime + 0.1)
	task.delay(lifetime + 0.15, function()
		self._activeFloatingTexts = math.max(0, self._activeFloatingTexts - 1)
	end)
end

function EffectsController:_playModelScaleSequence(model, steps, options)
	if model == nil or not model:IsA("Model") or model.Parent == nil then return end

	local baseScale = self._modelBaseScales[model]
	if baseScale == nil then
		baseScale = model:GetAttribute("BaseScale") or model:GetScale()
		if baseScale <= 0 then baseScale = 1 end
		self._modelBaseScales[model] = baseScale
	end

	local baseCFrame = self._modelBaseCFrames[model]
	if baseCFrame == nil and options and options.cframeTarget then
		baseCFrame = model:GetPivot()
		self._modelBaseCFrames[model] = baseCFrame
	end

	if self._activeScaleDrivers[model] then
		self._activeScaleDrivers[model]:Disconnect()
		self._activeScaleDrivers[model] = nil
	end
	
	local startingMult = (options and options.startScaleMultiplier) or 1
	model:ScaleTo(baseScale * startingMult)

	local scaleValue = Instance.new("NumberValue")
	scaleValue.Value = baseScale * startingMult

	-- REPLICATION FIX: If new parts arrive during the tween, force them to the current scale
	-- This prevents 'giant' or 'tiny' parts caused by inconsistent local scale states
	local descConnection = model.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			model:ScaleTo(scaleValue.Value)
		end
	end)

	local cframeValue = nil
	local connection = nil
	if options and options.cframeTarget then
		cframeValue = Instance.new("CFrameValue")
		cframeValue.Value = model:GetPivot()

		connection = RunService.Heartbeat:Connect(function()
			if model.Parent == nil then return end
			model:PivotTo(cframeValue.Value)
			model:ScaleTo(scaleValue.Value)
		end)
		self._activeScaleDrivers[model] = connection
	else
		connection = scaleValue.Changed:Connect(function(value)
			if model.Parent then model:ScaleTo(value) end
		end)
		self._activeScaleDrivers[model] = connection
	end

	task.spawn(function()
		for _, step in ipairs(steps) do
			if model.Parent == nil then break end
			local tween = TweenService:Create(scaleValue, TweenInfo.new(step.duration, step.style, step.direction), {
				Value = baseScale * step.scale,
			})
			tween:Play()
			if step.cframe and cframeValue then
				TweenService:Create(cframeValue, TweenInfo.new(step.duration, step.style, step.direction), {
					Value = step.cframe,
				}):Play()
			end
			tween.Completed:Wait()
		end

		if self._activeScaleDrivers[model] == connection then
			if connection then connection:Disconnect() end
			self._activeScaleDrivers[model] = nil
			if options == nil or options.restore ~= false then
				if model.Parent then
					model:ScaleTo(baseScale)
					if baseCFrame then model:PivotTo(baseCFrame) end
				end
			end
		end
		descConnection:Disconnect()
		scaleValue:Destroy()
		if cframeValue then cframeValue:Destroy() end
	end)
end

function EffectsController:_playPartSizeSequence(part, steps, options)
	if part == nil or not part:IsA("BasePart") or part.Parent == nil then return end

	local baseSize = self._partBaseSizes[part] or part.Size
	self._partBaseSizes[part] = baseSize

	local startingMult = (options and options.startScaleMultiplier) or 1
	part.Size = baseSize * startingMult

	task.spawn(function()
		for _, step in ipairs(steps) do
			if part.Parent == nil then break end
			local sizeGoal = step.size or baseSize * step.scale
			local tween = TweenService:Create(part, TweenInfo.new(step.duration, step.style, step.direction), {
				Size = sizeGoal,
			})
			tween:Play()
			tween.Completed:Wait()
		end
		if options == nil or options.restore ~= false then
			if part.Parent then part.Size = baseSize end
		end
	end)
end

function EffectsController:_spawnFlyingRocks(worldPosition, animalModel)
	if not animalModel then return end
	
	local refPart = nil
	local maxVolume = 0
	for _, part in ipairs(animalModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 0.5 and part.Name ~= "HumanoidRootPart" then
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > maxVolume then
				maxVolume = volume
				refPart = part
			end
		end
	end
	
	if not refPart then return end
	local color = refPart.Color
	local material = refPart.Material
	
	-- Main Rocks + Micro Debris
	local rockCount = math.random(4, 7)
	for i = 1, rockCount do
		local isMicro = (i > 4)
		local rock = Instance.new("Part")
		rock.Name = "DebrisRock"
		local s = isMicro and math.random(2, 4)/10 or math.random(6, 12)/10
		rock.Size = Vector3.new(s, s, s)
		rock.Position = worldPosition + Vector3.new(0, 0.5, 0)
		rock.Color = color
		rock.Material = material
		rock.CanCollide = true
		rock.CanTouch = false
		rock.Massless = true
		rock.Shape = (math.random() > 0.5) and Enum.PartType.Block or Enum.PartType.Ball
		rock.Parent = Workspace.Terrain
		
		local force = isMicro and 45 or 30
		rock.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * force,
			math.random(20, 45),
			(math.random() - 0.5) * force
		)
		rock.AssemblyAngularVelocity = Vector3.new(math.random(-30, 30), math.random(-30, 30), math.random(-30, 30))
		
		Debris:AddItem(rock, 2.5)
		task.delay(1.5, function()
			if rock.Parent then
				TweenService:Create(rock, TweenInfo.new(0.5), {Transparency = 1}):Play()
			end
		end)
	end
end

function EffectsController:_handleAnimalHit(payload)
	local damage = payload.damage or 0
	local maxHealth = math.max(payload.maxHealth or 1, 1)
	local target = getPrimaryPart(payload.animal)
	local worldPosition = payload.position or (target and target.Position) or Vector3.zero
	local now = os.clock()
	local allowFullFx = (now - self._lastAnimalHitFxAt) >= 0.05
	if allowFullFx then
		self._lastAnimalHitFxAt = now
	end

	-- Juice: Camera Shake & Flash
	local damageNum = tonumber(damage) or 0
	if allowFullFx then
		local shakeIntensity = 0.15 + (math.min(damageNum / 100, 1) * 0.4)
		self:_shakeCamera(shakeIntensity, 0.12)
		self:_screenFlash(Color3.new(1, 1, 1), 0.1, 0.92)
	end

	if payload.animal then
		if allowFullFx then
			-- Intense Pure White Flash
			self:_flashHighlight(payload.animal, Color3.new(1, 1, 1), 0, 0.15)
			
			-- Exaggerated Squish
			if payload.animal:IsA("Model") then
				self:_playModelScaleSequence(payload.animal, {
					{duration = 0.04, style = Enum.EasingStyle.Quart, direction = Enum.EasingDirection.Out, scale = 0.4},
					{duration = 0.1, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out, scale = 1.4},
					{duration = 0.2, style = Enum.EasingStyle.Elastic, direction = Enum.EasingDirection.Out, scale = 1},
				})
			end
			
			local lastRockSpawn = self._lastRockSpawnByAnimal[payload.animal] or 0
			if (os.clock() - lastRockSpawn) >= 0.2 then
				self._lastRockSpawnByAnimal[payload.animal] = os.clock()
				self:_spawnFlyingRocks(worldPosition, payload.animal)
			end
		end
	end

	local animationController = self._runtime and self._runtime:GetController("PlayerAnimationController")
	if animationController and type(animationController.PlayHitAnimation) == "function" then
		animationController:PlayHitAnimation()
	end

	-- Damage Text
	local text, color, stroke, size, riseHeight, duration
	local options = { spreadMultiplier = 1 }
	if typeof(damage) == "string" and damage == "IMMUNE" then
		text, color, stroke, size, riseHeight, duration = "IMMUNE", Color3.fromRGB(200, 200, 200), Color3.fromRGB(50, 50, 50), 1.2, 2.5, 0.6
	else
		local isMassive = damageNum > (maxHealth * 0.15)
		local isHeavy = damageNum > (maxHealth * 0.05)
		text = NumberFormatter:Format(damageNum, "Letters")
		color, stroke, size, riseHeight, duration = Color3.fromRGB(255, 65, 65), Color3.fromRGB(100, 0, 0), 1.4, 3.5, 0.75
		if isMassive then
			text = "💥" .. text .. "💥"
			color, stroke, size, riseHeight, duration = Color3.fromRGB(255, 45, 45), Color3.fromRGB(120, 0, 0), 2.2, 8, 1.3
			options.flashWhite, options.spreadMultiplier = true, 2
		elseif isHeavy then
			text = "💫" .. text .."💫"
			color, stroke, size, riseHeight, duration = Color3.fromRGB(255, 140, 20), Color3.fromRGB(120, 40, 0), 1.6, 5.5, 0.95
			options.flashWhite, options.spreadMultiplier = true, 1.5
		end
	end
	self:_spawnFloatingText(worldPosition, text, color, stroke, size, riseHeight, duration, options)
end

function EffectsController:_handleAnimalDeath(payload)
	if payload.animal then
		self:_flashHighlight(payload.animal, Color3.fromRGB(255, 50, 50), 0.05, 0.22)
	end
end

function EffectsController:_handleAnimalUpgrade(payload)
	if payload.animal then
		self:_flashHighlight(payload.animal, Color3.fromRGB(255, 230, 90), 0.1, 0.3)
		self:_playModelScaleSequence(payload.animal, {
			{duration = 0.1, style = Enum.EasingStyle.Sine, direction = Enum.EasingDirection.Out, scale = 1.4},
			{duration = 0.4, style = Enum.EasingStyle.Elastic, direction = Enum.EasingDirection.Out, scale = 1},
		})
	end
end

function EffectsController:_handleAnimalSpawn(payload)
	local animal = payload.animal
	if animal == nil or animal.Parent == nil then return end
	
	-- Robust wait for model to replicate its parts in high-ping scenarios
	task.spawn(function()
		local start = os.clock()
		local lastExtentsSize = Vector3.zero
		local stableCount = 0
		
		-- Wait until extents size is stable (no new parts arriving for a few checks)
		-- or timeout after 3 seconds
		while os.clock() - start < 3 do
			if animal.Parent == nil then return end
			local currentSize = animal:GetExtentsSize()
			
			if currentSize.Magnitude > 0 then
				if (currentSize - lastExtentsSize).Magnitude < 0.1 then
					stableCount += 1
				else
					stableCount = 0
				end
			end
			
			if stableCount >= 3 then break end
			lastExtentsSize = currentSize
			task.wait(0.15)
		end
		
		if animal.Parent == nil then return end

		if animal:IsA("Model") then
			-- Prioritize the server-provided BaseScale attribute
			local baseScale = animal:GetAttribute("BaseScale") or animal:GetScale()
			
			-- Sanity check: if scale is zero or extremely weird, default to 1
			if baseScale <= 0 or baseScale > 10 then
				baseScale = 1
			end
			
			self._modelBaseScales[animal] = baseScale
			self:_playModelScaleSequence(animal, {
				{duration = 0.8, style = Enum.EasingStyle.Elastic, direction = Enum.EasingDirection.Out, scale = 1},
			}, { restore = true, startScaleMultiplier = 0.01 })
		end
	end)
end

function EffectsController:_handleAnimalDespawn(payload)
	if payload.animal and payload.animal:IsA("Model") then
		self:_playModelScaleSequence(payload.animal, {
			{duration = 0.3, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.In, scale = 0.01},
		}, { restore = false })
	end
end

function EffectsController:_handleAnimalPickup(payload)
	if typeof(payload) ~= "table" then return end
	local target = payload.target
	if typeof(target) ~= "Instance" then return end
	if not target.Parent then return end
	if self._dropAnimations[target] then
		self._dropAnimations[target] = nil
	end
	if target:IsA("Model") then
		self:_playModelScaleSequence(target, {
			{duration = 0.2, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.In, scale = 0.01},
		}, { restore = false })
	end
end

function EffectsController:_handlePadCollected(payload)
	local collector = payload.collector
	if not collector or not collector:IsA("BasePart") then return end
	local baseSize = collector.Size
	self:_flashHighlight(collector, Color3.new(1, 1, 1), 0.2, 0.25)
	self:_playPartSizeSequence(collector, {
		{duration = 0.08, style = Enum.EasingStyle.Sine, direction = Enum.EasingDirection.Out, size = Vector3.new(baseSize.X * 1.15, baseSize.Y * 0.4, baseSize.Z * 1.15)},
		{duration = 0.35, style = Enum.EasingStyle.Elastic, direction = Enum.EasingDirection.Out, size = baseSize},
	})
	self:_spawnFloatingText(collector.Position + Vector3.new((math.random()-0.5)*2, 1, (math.random()-0.5)*2), "+$" .. NumberFormatter:Format(payload.amount or 0, "Letters"), Color3.fromRGB(85, 255, 127), Color3.fromRGB(0, 85, 0), 1.5, 7.0, 1.3, { spreadMultiplier = 1.5, flashWhite = true })
end

function EffectsController:_handleShrineHit(payload)
	local animal = payload.animal
	if not animal or not animal.Parent then return end
	local target = getPrimaryPart(animal)
	local worldPosition = payload.position or (target and target.Position) or Vector3.zero
	self:_flashHighlight(animal, Color3.new(1, 1, 1), 0.1, 0.18)
	if animal:IsA("Model") then
		local baseCFrame = self._modelBaseCFrames[animal] or animal:GetPivot()
		self._modelBaseCFrames[animal] = baseCFrame
		local tilt = math.rad(math.random(12, 22))
		local tilts = {CFrame.Angles(tilt,0,0), CFrame.Angles(-tilt,0,0), CFrame.Angles(0,0,tilt), CFrame.Angles(0,0,-tilt)}
		local randomTilt = tilts[math.random(1, #tilts)]
		self:_playModelScaleSequence(animal, {
			{duration = 0.06, style = Enum.EasingStyle.Quart, direction = Enum.EasingDirection.Out, scale = 0.6, cframe = baseCFrame * randomTilt},
			{duration = 0.2, style = Enum.EasingStyle.Elastic, direction = Enum.EasingDirection.Out, scale = 1, cframe = baseCFrame},
		}, { cframeTarget = true })
	end
	self:_spawnFloatingText(worldPosition, NumberFormatter:Format(payload.damage or 0, "Letters"), Color3.fromRGB(255, 100, 100), Color3.fromRGB(50, 0, 0), 1.0, 2.5, 0.6, { spreadMultiplier = 0.8 })
end

function EffectsController:_handlePlayerUpgrade()
	ScreenEffects.RewardEffect(self._runtime.Player, {
		CameraIntensity = 15,
		Confetti = false
	})
	
	local soundController = self._runtime:GetController("SoundController")
	if soundController then
		soundController:PlayLocal("Buy", { volume = 0.6 })
	end
end

function EffectsController:_handleAnimalDelivered()
	local now = os.clock()
	if (now - self._lastDeliveredEffectAt) < 1 then
		return
	end
	self._lastDeliveredEffectAt = now

	ScreenEffects.RewardEffect(self._runtime.Player, {
		CameraIntensity = 12,
		Confetti = true,
		ConfettiAmount = 30
	})
	local soundController = self._runtime:GetController("SoundController")
	if soundController then
		soundController:PlayLocal("AnimalDelivered")
	end
end

function EffectsController:_handleEffect(effectName, payload)
	if effectName == self._config.Effects.Names.AnimalHit then self:_handleAnimalHit(payload)
	elseif effectName == self._config.Effects.Names.ShrineHit then self:_handleShrineHit(payload)
	elseif effectName == self._config.Effects.Names.AnimalDeath then self:_handleAnimalDeath(payload)
	elseif effectName == self._config.Effects.Names.AnimalPickup then self:_handleAnimalPickup(payload)
	elseif effectName == self._config.Effects.Names.AnimalUpgrade then self:_handleAnimalUpgrade(payload)
	elseif effectName == self._config.Effects.Names.PadCollected then self:_handlePadCollected(payload)
	elseif effectName == self._config.Effects.Names.AnimalSpawn then self:_handleAnimalSpawn(payload)
	elseif effectName == self._config.Effects.Names.AnimalDelivered then self:_handleAnimalDelivered()
	elseif effectName == self._config.Effects.Names.AnimalDespawn then self:_handleAnimalDespawn(payload)
	elseif effectName == self._config.Effects.Names.PlayerUpgrade then self:_handlePlayerUpgrade()
	elseif effectName == "ConfettiBurst" then ScreenEffects.RewardEffect(self._runtime.Player, { Confetti = true, ConfettiAmount = payload.amount }) end
end

function EffectsController:Start()
	self._dropsFolder.ChildAdded:Connect(function(drop)
		if not drop:IsA("Model") then return end
		
		-- 1. POP ANIMATION
		-- Wait a tiny bit for the model to be fully ready/cloned
		task.defer(function()
			if not drop.Parent then return end
			
			local originalScale = drop:GetScale()
			drop:ScaleTo(0.01)
			
			local scaleVal = Instance.new("NumberValue")
			scaleVal.Value = 0.01
			scaleVal.Name = "DropScale"
			scaleVal.Parent = drop
			
			scaleVal.Changed:Connect(function(val)
				if drop.Parent then
					drop:ScaleTo(val)
				end
			end)
			
			TweenService:Create(scaleVal, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Value = originalScale}):Play()
			
			-- 2. SLOW SPINNING (single shared heartbeat loop)
			self._dropAnimations[drop] = 60
			drop.Destroying:Connect(function()
				self._dropAnimations[drop] = nil
			end)
			self:_ensureDropSpinLoop()
		end)
	end)

	self._remote.OnClientEvent:Connect(function(effectName, payload)
		self:_handleEffect(effectName, payload or {})
	end)
end

return EffectsController
