local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LuckyBlockController = {
	Name = "LuckyBlockController",
	Priority = 0,
}

local function formatTime(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%02dh:%02dm:%02ds", h, m, s)
end

function LuckyBlockController:Init(runtime)
	self._runtime = runtime
	self._remote = runtime.Remotes:GetLuckyBlockRemote()
	self._rollingBlocks = {}
	self._trackedBlocks = {}
	self._trackedConnections = {}
end

function LuckyBlockController:_playIdleAnimation(animal: Instance, originalTemplate: Instance)
	-- Cloning an active Animator breaks it in Roblox, so we must destroy any existing ones and recreate it
	for _, oldAnimator in ipairs(animal:GetDescendants()) do
		if oldAnimator:IsA("Animator") then
			oldAnimator:Destroy()
		end
	end

	local controller = animal:FindFirstChildOfClass("AnimationController")
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Parent = animal
	end
	
	local animator = Instance.new("Animator")
	animator.Parent = controller

	local animId = animal:GetAttribute("IdleAnimationId")
	
	if not animId and originalTemplate then
		animId = originalTemplate:GetAttribute("IdleAnimationId")
		if not animId then
			-- Try to extract it from the original template's playing tracks
			local origAnimator = originalTemplate:FindFirstChildWhichIsA("Animator", true)
			if origAnimator then
				for _, track in ipairs(origAnimator:GetPlayingAnimationTracks()) do
					if track.Animation and track.Animation.AnimationId ~= "" then
						animId = track.Animation.AnimationId
						break
					end
				end
			end
		end
	end

	-- Find the shared lucky block animation or use the extracted one
	local idleAnimation = Instance.new("Animation")
	idleAnimation.AnimationId = animId or "rbxassetid://134122126546788" -- Fallback
	
	local track = animator:LoadAnimation(idleAnimation)
	track.Looped = true
	track:Play()
end

local function isPartVisible(part: BasePart): boolean
	if part.Transparency > 0.95 then
		-- Sometimes a fully transparent part is still visually represented by a mesh/decal.
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Decal") or child:IsA("Texture") or child:IsA("DataModelMesh") then
				return true
			end
		end
		return false
	end
	return true
end

function LuckyBlockController:_tintBlack(model, transparency)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			-- IGNORE invisible parts and VfxInstance
			if not isPartVisible(part) or part.Name == "VfxInstance" or part.Name == "FakeRootPart" or part.Name == "RootPart" then
				continue
			end

			if not part:GetAttribute("OriginalColor") then
				part:SetAttribute("OriginalColor", part.Color)
				part:SetAttribute("OriginalMaterial", part.Material)
				part:SetAttribute("OriginalTransparency", part.Transparency)
			end
			part.Color = Color3.new(0, 0, 0)
			part.Material = Enum.Material.Neon
			
			if transparency then
				part.Transparency = transparency
			end
			
			if part:IsA("MeshPart") then
				if not part:GetAttribute("OriginalTexture") then
					part:SetAttribute("OriginalTexture", part.TextureID)
				end
				part.TextureID = ""

				-- SurfaceAppearance overrides TextureID, so we MUST move it to see the black texture
				local sa = part:FindFirstChildWhichIsA("SurfaceAppearance")
				if sa then
					local backup = part:FindFirstChild("SABackup")
					if not backup then
						backup = Instance.new("Folder")
						backup.Name = "SABackup"
						backup.Parent = part
					end
					sa.Parent = backup
				end
			end
		elseif part:IsA("SpecialMesh") then
			if not part:GetAttribute("OriginalTextureId") then
				part:SetAttribute("OriginalTextureId", part.TextureId)
			end
			part.TextureId = ""
		elseif part:IsA("Decal") or part:IsA("Texture") then
			if not part:GetAttribute("OriginalTransparency") then
				part:SetAttribute("OriginalTransparency", part.Transparency)
			end
			part.Transparency = 1
		end
	end
end

function LuckyBlockController:_untintBlack(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local origColor = part:GetAttribute("OriginalColor")
			if origColor then
				TweenService:Create(part, TweenInfo.new(1), {Color = origColor}):Play()
			end
			
			local origTrans = part:GetAttribute("OriginalTransparency")
			if origTrans then
				TweenService:Create(part, TweenInfo.new(1), {Transparency = origTrans}):Play()
			end

			local origMat = part:GetAttribute("OriginalMaterial")
			if origMat then
				part.Material = origMat
			end
			if part:IsA("MeshPart") then
				local origTexture = part:GetAttribute("OriginalTexture")
				if origTexture then
					part.TextureID = origTexture
				end

				local backup = part:FindFirstChild("SABackup")
				if backup then
					local sa = backup:FindFirstChildWhichIsA("SurfaceAppearance")
					if sa then
						sa.Parent = part
					end
					backup:Destroy()
				end
			end
		elseif part:IsA("SpecialMesh") then
			local origTextureId = part:GetAttribute("OriginalTextureId")
			if origTextureId then
				part.TextureId = origTextureId
			end
		elseif part:IsA("Decal") or part:IsA("Texture") then
			local origTrans = part:GetAttribute("OriginalTransparency")
			if origTrans then
				TweenService:Create(part, TweenInfo.new(1), {Transparency = origTrans}):Play()
			end
		end
	end
end

function LuckyBlockController:_playRollingAnimation(luckyBlock, resultAnimalName)
	if not luckyBlock or not luckyBlock.Parent then return end

	local pivot = luckyBlock:GetPivot()
	-- Try to get the actual slot alignment
	local pad = luckyBlock.Parent and luckyBlock.Parent.Parent
	if pad then
		local placer = pad:FindFirstChild("Placer", true)
		local placePart = placer and (placer:IsA("BasePart") and placer or placer.Parent)
		if placePart and placePart:IsA("BasePart") then
			pivot = placePart.CFrame
		end
	end
	
	-- Hide the actual lucky block box
	for _, part in ipairs(luckyBlock:GetDescendants()) do
		if part:IsA("BasePart") then
			TweenService:Create(part, TweenInfo.new(0.3), {Transparency = 1}):Play()
		elseif part:IsA("Decal") or part:IsA("Texture") then
			TweenService:Create(part, TweenInfo.new(0.3), {Transparency = 1}):Play()
		elseif part:IsA("ProximityPrompt") or part:IsA("BillboardGui") then
			part.Enabled = false
		end
	end

	-- Get all available animal models for the rolling pool from clean templates
	local dummyPool = {}
	local templates = ReplicatedStorage:FindFirstChild("AdminAnimalTemplates")
	if templates then
		for _, rarityFolder in ipairs(templates:GetChildren()) do
			for _, animalTemplate in ipairs(rarityFolder:GetChildren()) do
				if animalTemplate:IsA("Model") then
					table.insert(dummyPool, animalTemplate)
				end
			end
		end
	end
	
	-- Fallback to workspace if templates aren't ready (less clean but works)
	if #dummyPool == 0 then
		local animals = CollectionService:GetTagged("Animal")
		for _, a in ipairs(animals) do
			if a ~= luckyBlock and a:IsA("Model") and a.PrimaryPart and not a:IsA("Tool") then
				table.insert(dummyPool, a)
			end
		end
	end
	
	if #dummyPool == 0 then return end -- Failsafe

	local currentDummy = nil
	local rollDuration = 4.0 -- Faster, more intense roll
	local startTime = os.clock()
	local speed = 0.02
	local soundController = self._runtime:GetController("SoundController")

	task.spawn(function()
		-- Spawn Flash Particle Part for the entire duration
		local flashTemplate = ReplicatedStorage:FindFirstChild("Flash")
		local flashInst = nil
		if flashTemplate and flashTemplate:IsA("BasePart") then
			flashInst = flashTemplate:Clone()
			flashInst.CFrame = pivot * CFrame.new(0, 5, 0)
			flashInst.Parent = Workspace
		end

		while os.clock() - startTime < rollDuration do
			local elapsed = os.clock() - startTime
			-- Slow down over time for a roulette feel
			local progress = elapsed / rollDuration
			local easeOut = 1 - (1 - progress) ^ 4 -- Less aggressive easing
			-- Start with speed 0 (minimum wait time, 60fps) and ease into 0.3 seconds between ticks
			speed = 0.0 + easeOut * 0.3

			if currentDummy then
				currentDummy:Destroy()
			end

			local randomTemplate = dummyPool[math.random(1, #dummyPool)]
			currentDummy = randomTemplate:Clone()
			
			local root = currentDummy.PrimaryPart or currentDummy:FindFirstChild("HumanoidRootPart") or currentDummy:FindFirstChildWhichIsA("BasePart")
			if root then root.Anchored = true end
			
			-- Clean up dummies and fix anchoring so animations play
			for _, part in ipairs(currentDummy:GetDescendants()) do
				if part:IsA("BasePart") then
					part.CanCollide = false
					if part ~= root then
						part.Anchored = false
					end
				elseif part:IsA("BillboardGui") or part:IsA("ProximityPrompt") then
					part:Destroy()
				end
			end

			self:_tintBlack(currentDummy, 0)
			
			-- Position exactly in the slot, no rotation, no hover
			currentDummy:PivotTo(pivot)
			currentDummy.Parent = Workspace
			self:_playIdleAnimation(currentDummy, randomTemplate)
			
			-- Pulse effect (Scale up slightly then normal)
			local originalScale = currentDummy:GetScale()
			currentDummy:ScaleTo(originalScale * 0.6)
			
			local scaleVal = Instance.new("NumberValue")
			scaleVal.Value = originalScale * 0.6
			scaleVal.Parent = currentDummy
			scaleVal.Changed:Connect(function(val)
				if currentDummy.Parent then
					currentDummy:ScaleTo(val)
				end
			end)
			
			-- Clamp tween speed so it still visually pulses even when going blazingly fast
			local tweenTime = math.max(0.05, speed * 0.8)
			TweenService:Create(scaleVal, TweenInfo.new(tweenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = originalScale * 1.25}):Play()

			if soundController then
				-- Pitch builds up to create extreme tension
				local pitch = 1.0 + (easeOut * 1.5)
				soundController:PlayLocal("UIHover", {randomPitch = false, volume = 0.7 + (easeOut * 0.5), pitch = pitch})
			end

			task.wait(speed)
		end

		if currentDummy then
			currentDummy:Destroy()
		end

		-- Final Reveal: Find the model that matches resultAnimalName
		local finalTemplate = nil
		for _, a in ipairs(dummyPool) do
			if a.Name == resultAnimalName then
				finalTemplate = a
				break
			end
		end
		
		-- If we couldn't find the exact model, search all tagged models or fallback
		if not finalTemplate then
			for _, a in ipairs(CollectionService:GetTagged("Animal")) do
				if a.Name == resultAnimalName and a:IsA("Model") then
					finalTemplate = a
					break
				end
			end
		end
		
		if not finalTemplate then finalTemplate = dummyPool[math.random(1, #dummyPool)] end

		local finalDummy = finalTemplate:Clone()
		local finalRoot = finalDummy.PrimaryPart or finalDummy:FindFirstChild("HumanoidRootPart") or finalDummy:FindFirstChildWhichIsA("BasePart")
		if finalRoot then finalRoot.Anchored = true end

		for _, part in ipairs(finalDummy:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				if part ~= finalRoot then
					part.Anchored = false
				end
			elseif part:IsA("BillboardGui") or part:IsA("ProximityPrompt") then
				part:Destroy()
			end
		end
		
		self:_tintBlack(finalDummy, 0)
		
		-- Place perfectly in slot
		finalDummy:PivotTo(pivot)
		finalDummy.Parent = Workspace
		self:_playIdleAnimation(finalDummy, finalTemplate)
		
		-- Thud sound for the black silhouette landing
		if soundController then
			soundController:PlayLocal("AnimalPlaced", {randomPitch = false, volume = 1.0, pitch = 0.8})
		end
		
		local originalScale = finalDummy:GetScale()
		local scaleVal = Instance.new("NumberValue")
		scaleVal.Value = originalScale * 0.1
		scaleVal.Parent = finalDummy
		scaleVal.Changed:Connect(function(val)
			if finalDummy.Parent then
				finalDummy:ScaleTo(val)
			end
		end)
		
		-- Massive bounce effect starting from the pivot
		TweenService:Create(scaleVal, TweenInfo.new(1.0, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Value = originalScale}):Play()
		
		task.wait(1.0)
		
		-- THE REAL REVEAL
		-- Fade to normal colors
		self:_untintBlack(finalDummy)
		
		-- Play the animal's specific sound from ServerStorage via remote
		self._remote:FireServer("PlayAnimalSound", {
			AnimalName = resultAnimalName,
			Position = pivot.Position
		})
		
		-- Epic Sounds
		if soundController then
			soundController:PlayLocal("Buy", {randomPitch = false, volume = 2.0, pitch = 0.9})
			soundController:PlayLocal("AnimalUpgrade", {randomPitch = false, volume = 1.5, pitch = 1.0})
		end
		
		-- Heavy Camera Pop
		local screenEffects = require(ReplicatedStorage.Modules.ScreenEffects)
		if screenEffects then
			screenEffects.CameraPop(game.Players.LocalPlayer, 35)
			screenEffects.VignettePulse(game.Players.LocalPlayer)
			-- Add Effects
			screenEffects.RewardEffect(game.Players.LocalPlayer, {
				CameraIntensity = 0, -- Handled above
				Confetti = false,
				ConfettiAmount = 0
			})
		end
		
		-- Flash effect on the pad (white ball)
		local flashPart = Instance.new("Part")
		flashPart.Size = Vector3.new(0.5, 0.5, 0.5)
		flashPart.CFrame = pivot
		flashPart.Anchored = true
		flashPart.CanCollide = false
		flashPart.Transparency = 0
		flashPart.Color = Color3.new(1, 1, 1)
		flashPart.Material = Enum.Material.Neon
		flashPart.Shape = Enum.PartType.Ball
		flashPart.Parent = Workspace
		
		TweenService:Create(flashPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = Vector3.new(20, 20, 20), Transparency = 1}):Play()
		task.delay(0.5, function()
			if flashPart then flashPart:Destroy() end
		end)

		-- Clean up the ongoing flash particle part
		if flashInst then
			flashInst:Destroy()
		end

		-- Stay for a moment before letting the real server-side animal take over
		task.wait(1.5)
		if finalDummy then
			finalDummy:Destroy()
		end
	end)
end

function LuckyBlockController:Start()
	self._remote.OnClientEvent:Connect(function(action, data)
		if action == "StartRoll" then
			self:_playRollingAnimation(data.luckyBlock, data.resultAnimalName)
		end
	end)

	local function updateLuckyBlockTag(animal)
		if not animal.Parent then return end
		if not animal:GetAttribute("IsLuckyBlock") or not animal:GetAttribute("Placed") then return end

		local tag = animal:FindFirstChild("Tag") or animal:FindFirstChild("AnimalTag")
		if not tag then return end

		local timeLabel = tag:FindFirstChild("Time", true) or tag:FindFirstChild("TimerLabel", true)
		if not timeLabel then
			local revenueLabel = tag:FindFirstChild("Revenue", true)
			if revenueLabel and revenueLabel:IsA("TextLabel") then
				revenueLabel.Name = "Time"
				timeLabel = revenueLabel
			end
		end

		if timeLabel and timeLabel:IsA("TextLabel") then
			local timeLeft = animal:GetAttribute("TimeLeft") or 0
			if timeLeft > 0 then
				timeLabel.Text = formatTime(math.ceil(timeLeft))
				timeLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
			else
				timeLabel.Text = "READY!"
				timeLabel.TextColor3 = Color3.fromRGB(50, 255, 100)
			end
		end

		local costLabel = tag:FindFirstChild("Cost", true)
		if costLabel and costLabel:IsA("TextLabel") then
			costLabel.Visible = false
		end
	end

	local function untrack(animal)
		self._trackedBlocks[animal] = nil
		local conns = self._trackedConnections[animal]
		if conns then
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			self._trackedConnections[animal] = nil
		end
	end

	local function track(animal)
		if self._trackedBlocks[animal] then return end
		if not animal:IsA("Model") then return end
		if not animal:GetAttribute("IsLuckyBlock") then return end
		self._trackedBlocks[animal] = true

		local conns = {}
		self._trackedConnections[animal] = conns

		table.insert(conns, animal:GetAttributeChangedSignal("TimeLeft"):Connect(function()
			updateLuckyBlockTag(animal)
		end))
		table.insert(conns, animal:GetAttributeChangedSignal("Placed"):Connect(function()
			updateLuckyBlockTag(animal)
		end))
		table.insert(conns, animal.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				untrack(animal)
			end
		end))
		table.insert(conns, animal.DescendantAdded:Connect(function(desc)
			if desc.Name == "Tag" or desc.Name == "AnimalTag" then
				updateLuckyBlockTag(animal)
			end
		end))

		updateLuckyBlockTag(animal)
	end

	for _, animal in ipairs(CollectionService:GetTagged("Animal")) do
		track(animal)
	end

	CollectionService:GetInstanceAddedSignal("Animal"):Connect(function(animal)
		track(animal)
	end)
end

return LuckyBlockController
