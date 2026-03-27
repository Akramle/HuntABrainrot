local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local MessagingService = game:GetService("MessagingService")

local GLOBAL_EVENT_TOPIC = "GlobalGameEvent"

local EventService = {
	Name = "EventService",
	Priority = -15,
}

function EventService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	
	-- Safely get the remote
	local ok, remote = pcall(function()
		return runtime.Remotes:GetEventRemote()
	end)
	
	if ok then
		self._remote = remote
	else
		warn("[EventService] Failed to get EventRemote:", remote)
	end
	
	self._activeEvent = nil
	self._originalLighting = {}
	self._eventLoop = nil
	self._eventEndTask = nil

	-- Create a hidden folder for backing up lighting children
	self._backupLightingFolder = Instance.new("Folder")
	self._backupLightingFolder.Name = "OriginalLightingAssets"
	self._backupLightingFolder.Parent = ServerStorage
end

local function applyLighting(targetLighting, backupFolder)
	if not targetLighting then return end
	local currentLightingProps = {}
	
	local propsToSync = {"Ambient", "Brightness", "ColorShift_Bottom", "ColorShift_Top", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "OutdoorAmbient", "ShadowSoftness", "ClockTime", "GeographicLatitude", "ExposureCompensation"}
	
	-- Store original props
	for _, prop in ipairs(propsToSync) do
		pcall(function() currentLightingProps[prop] = Lighting[prop] end)
	end
	
	-- Apply new from the target (which might be a Configuration or Folder with attributes/children)
	for _, prop in ipairs(propsToSync) do
		pcall(function() 
			local val = targetLighting:FindFirstChild(prop)
			if val then
				Lighting[prop] = val.Value
			elseif targetLighting:GetAttribute(prop) ~= nil then
				Lighting[prop] = targetLighting:GetAttribute(prop)
			end
		end)
	end

	-- MOVE current children to backup (instead of just cloning)
	for _, child in ipairs(Lighting:GetChildren()) do
		if not child:IsA("Script") then
			child.Parent = backupFolder
		end
	end

	-- Add event children
	for _, child in ipairs(targetLighting:GetChildren()) do
		if not child:IsA("ValueBase") then
			local clone = child:Clone()
			CollectionService:AddTag(clone, "ActiveEventAsset")
			clone.Parent = Lighting
		end
	end
	
	return currentLightingProps
end

local function restoreLighting(props, backupFolder)
	if not props then return end
	for prop, val in pairs(props) do
		pcall(function() Lighting[prop] = val end)
	end

	-- Restore children from backup
	if backupFolder then
		for _, child in ipairs(backupFolder:GetChildren()) do
			child.Parent = Lighting
		end
	end
end

local function cleanUpEventAssets(tag)
	for _, obj in ipairs(CollectionService:GetTagged(tag)) do
		obj:Destroy()
	end
end

function EventService:TriggerEvent(eventName: string)
	if self._activeEvent then
		warn("[EventService] Trigger failed: An event is already active:", self._activeEvent)
		return false, "An event is already active: " .. self._activeEvent
	end

	local eventConfig = self._config.Events[eventName]
	if not eventConfig then
		warn("[EventService] Trigger failed: No config found for event:", eventName)
		return false, "No configuration found for event: " .. eventName
	end
	
	local durationRange = eventConfig.DurationRange or {40, 70}

	local eventsFolder = ServerStorage:FindFirstChild("Events")
	if not eventsFolder then 
		warn("[EventService] Trigger failed: Events folder not found in ServerStorage")
		return false, "Events folder not found in ServerStorage" 
	end

	local eventFolder = eventsFolder:FindFirstChild(eventName)
	if not eventFolder then 
		warn("[EventService] Trigger failed: Event folder not found for", eventName)
		return false, "Event '" .. eventName .. "' not found in ServerStorage.Events" 
	end

	self._activeEvent = eventName
	self._activeEventStartTime = os.clock()
	local duration = math.random(durationRange[1], durationRange[2])
	local eventTag = "ActiveEventAsset"
	
	-- 1. Lighting
	local lightingFolder = eventFolder:FindFirstChild("Lighting")
	if lightingFolder then
		self._originalLighting = applyLighting(lightingFolder, self._backupLightingFolder)
	end
	
	-- 2. Objects
	local objectFolder = eventFolder:FindFirstChild("Object")
	if objectFolder then
		for _, obj in ipairs(objectFolder:GetChildren()) do
			local clone = obj:Clone()
			CollectionService:AddTag(clone, eventTag)
			clone.Parent = Workspace
		end
	end

	-- 2.5 Functional Objects (Tornado specific)
	local functionalFolder = eventFolder:FindFirstChild("Functional")
	if functionalFolder and eventName == "Tornado" then
		local tornadoTemplate = functionalFolder:FindFirstChildWhichIsA("BasePart")
		if tornadoTemplate then
			local countRange = eventConfig.TornadosPerArea or {2, 5}
			
			local function spawnTornadosInPart(parentPart, count)
				if not parentPart:IsA("BasePart") then return end
				for i = 1, count do
					local tornado = tornadoTemplate:Clone()
					tornado.Name = "SmallTornado"
					CollectionService:AddTag(tornado, eventTag)
					CollectionService:AddTag(tornado, "TornadoObject")
					
					-- Random position within area
					local areaSize = parentPart.Size
					local areaCF = parentPart.CFrame
					local randomPos = areaCF * CFrame.new(
						math.random(-areaSize.X/2, areaSize.X/2),
						-areaSize.Y/2 + (tornado.Size.Y/2), -- Place on ground
						math.random(-areaSize.Z/2, areaSize.Z/2)
					)
					
					tornado.CFrame = randomPos
					tornado.Parent = Workspace
					
					-- Start smooth autonomous movement
					task.spawn(function()
						self:_startTornadoMovement(tornado, parentPart)
					end)
				end
			end

			-- Spawn in Areas
			local areas = Workspace:FindFirstChild("Areas")
			if areas then
				for _, area in ipairs(areas:GetChildren()) do
					spawnTornadosInPart(area, math.random(countRange[1], countRange[2]))
				end
			end

			-- Spawn in SafeZones (Chance based, e.g., 1-2 per zone)
			for _, safeZone in ipairs(CollectionService:GetTagged("SafeZone")) do
				spawnTornadosInPart(safeZone, math.random(1, 2))
			end
		end
	end

	-- 2.6 Functional Objects (Abduction specific)
	local functionalFolder = eventFolder:FindFirstChild("Functional")
	if functionalFolder and eventName == "Abduction" then
		local ufoTemplate = functionalFolder:FindFirstChild("UFO")
		if ufoTemplate then
			local countRange = eventConfig.UFOsPerArea or {1, 3}
			local areas = Workspace:FindFirstChild("Areas")
			if areas then
				for _, area in ipairs(areas:GetChildren()) do
					if not area:IsA("BasePart") then continue end
					local numUFOs = math.random(countRange[1], countRange[2])
					for i = 1, numUFOs do
						local ufo = ufoTemplate:Clone()
						ufo.Name = "UFO"
						CollectionService:AddTag(ufo, eventTag)
						CollectionService:AddTag(ufo, "UFOObject")
						
						-- Anchor all parts
						for _, part in ipairs(ufo:GetDescendants()) do
							if part:IsA("BasePart") then
								part.Anchored = true
							end
						end
						
						-- Get size for ground positioning
						local modelSize = ufo:GetExtentsSize()
						
						-- Random position within area (On Ground)
						local areaSize = area.Size
						local areaCF = area.CFrame
						local localPos = Vector3.new(
							math.random(-areaSize.X/2, areaSize.X/2),
							-areaSize.Y/2 + (modelSize.Y/2), 
							math.random(-areaSize.Z/2, areaSize.Z/2)
						)
						local worldPos = areaCF:PointToWorldSpace(localPos)
						
						-- Use original template rotation, only change position
						ufo:PivotTo(CFrame.new(worldPos) * ufoTemplate:GetPivot().Rotation)
						ufo.Parent = Workspace
						
						task.spawn(function()
							self:_startUFOMovement(ufo, area)
						end)
					end
				end
			end
		end
	end
	
	-- 3. Particles
	local particlesFolder = eventFolder:FindFirstChild("Particles")
	if particlesFolder then
		local mapParticles = particlesFolder:FindFirstChild("MapParticles")
		if mapParticles then
			local areas = Workspace:FindFirstChild("Areas")
			if areas then
				for _, area in ipairs(areas:GetChildren()) do
					for _, p in ipairs(mapParticles:GetChildren()) do
						local clone = p:Clone()
						CollectionService:AddTag(clone, eventTag)
						clone.Parent = area
					end
				end
			end
		end
		
		local playerParticles = particlesFolder:FindFirstChild("PlayersPrticles")
		if playerParticles then
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				if char and char:FindFirstChild("HumanoidRootPart") then
					for _, p in ipairs(playerParticles:GetChildren()) do
						local clone = p:Clone()
						CollectionService:AddTag(clone, eventTag)
						clone.Parent = char.HumanoidRootPart
					end
				end
			end
		end
	end
	
	-- 4. Replicate data for clients
	local rsEvents = ReplicatedStorage:FindFirstChild("ActiveEvents")
	if not rsEvents then
		rsEvents = Instance.new("Folder")
		rsEvents.Name = "ActiveEvents"
		rsEvents.Parent = ReplicatedStorage
	end
	rsEvents:ClearAllChildren()
	
	local clientEventData = Instance.new("Folder")
	clientEventData.Name = eventName
	
	local sfxFolder = eventFolder:FindFirstChild("SFX")
	if sfxFolder then sfxFolder:Clone().Parent = clientEventData end
	
	local musicFolder = eventFolder:FindFirstChild("Music")
	if musicFolder then musicFolder:Clone().Parent = clientEventData end
	
	local guiFolder = eventFolder:FindFirstChild("Gui")
	if guiFolder then guiFolder:Clone().Parent = clientEventData end
	
	clientEventData.Parent = rsEvents
	
	if self._remote then
		self._remote:FireAllClients("StartEvent", {EventName = eventName, Duration = duration})
	end
	
	self._runtime:GetService("NotificationService"):NotifyAll(string.format("%s event has started!", eventName:upper()), "Announcement")
	
	-- 5. Server Logic Loop
	local tickThread = task.spawn(function()
		while self._activeEvent == eventName do
			self:_onEventTick(eventName)
			task.wait(0.1)
		end
	end)
	
	-- 6. End Event Task
	self._eventEndTask = task.delay(duration, function()
		self:EndEvent()
		task.cancel(tickThread)
	end)
	
	return true
end

function EventService:_startUFOMovement(ufo, area)
	if not ufo.Parent or self._activeEvent ~= "Abduction" then return end

	local sucker = ufo:FindFirstChild("Sucker", true)
	if not sucker then return end

	local eventConfig = self._config.Events.Abduction
	local areaSize = area.Size
	local areaCF = area.CFrame
	local modelSize = ufo:GetExtentsSize()
	
	-- 1. Setup Path (Bezier Points)
	local startPivot = ufo:GetPivot()
	local startPos = startPivot.Position
	
	-- Target on ground
	local targetPosLocal = Vector3.new(
		math.random(-areaSize.X/2, areaSize.X/2),
		-areaSize.Y/2 + (modelSize.Y/2), 
		math.random(-areaSize.Z/2, areaSize.Z/2)
	)
	local targetPos = (areaCF * CFrame.new(targetPosLocal)).Position

	-- Control point for "curvy" movement (midpoint + random offset)
	local midPoint = startPos:Lerp(targetPos, 0.5)
	local curveIntensity = eventConfig.CurveIntensity or 15
	local controlPos = midPoint + Vector3.new(
		math.random(-curveIntensity, curveIntensity),
		0, -- Keep it on the ground plane
		math.random(-curveIntensity, curveIntensity)
	)

	local dist = (startPos - targetPos).Magnitude
	if dist < 5 then
		task.wait(0.5)
		self:_startUFOMovement(ufo, area)
		return
	end

	local speed = eventConfig.TravelSpeed or 10
	local duration = dist / speed

	-- 2. Movement Loop (Bezier)
	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	
	local tween = TweenService:Create(alpha, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = 1})
	
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not ufo.Parent or self._activeEvent ~= "Abduction" then
			connection:Disconnect()
			return
		end
		
		local t = alpha.Value
		
		-- Quadratic Bezier: (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
		local currentPos = (1-t)^2 * startPos + 2*(1-t)*t * controlPos + t^2 * targetPos
		
		-- Tangent (Direction): 2(1-t)(P1-P0) + 2t(P2-P1)
		local tangent = 2*(1-t)*(controlPos - startPos) + 2*t*(targetPos - controlPos)
		
		if tangent.Magnitude > 0.001 then
			-- lookAt uses -Z as front.
			local lookCF = CFrame.lookAt(currentPos, currentPos + tangent)
			local frontOffset = eventConfig.ModelFrontOffset or 90
			local finalCF = lookCF * CFrame.Angles(0, math.rad(frontOffset), 0)
			ufo:PivotTo(finalCF)
		else
			ufo:PivotTo(CFrame.new(currentPos) * ufo:GetPivot().Rotation)
		end
		
		-- Scanning logic: Animals
		local animalsFolder = Workspace:FindFirstChild("Animals")
		local scanRadius = eventConfig.ScanRadius or 6
		for _, animal in ipairs(CollectionService:GetTagged("Animal")) do
			if not animal:GetAttribute("IsAbducted") and animal:IsDescendantOf(animalsFolder) then
				local animalPos = animal:GetPivot().Position
				local distXZ = (Vector2.new(animalPos.X, animalPos.Z) - Vector2.new(currentPos.X, currentPos.Z)).Magnitude
				
				if distXZ < scanRadius then 
					connection:Disconnect()
					tween:Cancel()
					alpha:Destroy()
					self:_handleAbduction(ufo, animal, area)
					return
				end
			end
		end

		-- Scanning logic: Players
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			
			if hrp and hum and hum.Health > 0 and not char:GetAttribute("IsAbducted") then
				local playerPos = hrp.Position
				local distXZ = (Vector2.new(playerPos.X, playerPos.Z) - Vector2.new(currentPos.X, currentPos.Z)).Magnitude
				
				if distXZ < scanRadius then
					connection:Disconnect()
					tween:Cancel()
					alpha:Destroy()
					self:_handlePlayerAbduction(ufo, player, area)
					return
				end
			end
		end
	end)

	local completedConn
	completedConn = tween.Completed:Connect(function(playbackState)
		completedConn:Disconnect()
		if connection.Connected then connection:Disconnect() end
		-- Only start new movement if it actually completed its path (was not cancelled by an abduction)
		if playbackState == Enum.PlaybackState.Completed and ufo.Parent and self._activeEvent == "Abduction" then
			alpha:Destroy()
			self:_startUFOMovement(ufo, area)
		end
	end)
	
	tween:Play()
end

function EventService:_handlePlayerAbduction(ufo, player, area)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local sucker = ufo:FindFirstChild("Sucker", true)
	local eventConfig = self._config.Events.Abduction

	if not sucker or not hrp then 
		self:_startUFOMovement(ufo, area)
		return 
	end

	char:SetAttribute("IsAbducted", true)
	hrp.Anchored = true -- Freeze the player

	-- Use World-Space Verticality to avoid part rotation issues
	local suckerPos = sucker.Position
	local suckerSize = sucker.Size
	-- Use the largest dimension as the beam length
	local beamLength = math.max(suckerSize.X, suckerSize.Y, suckerSize.Z)
	local halfHeight = beamLength / 2
	
	local startRotation = char:GetPivot().Rotation
	
	-- Vertical movement in world space, centered on the Sucker part
	local startCFrame = CFrame.new(suckerPos.X, suckerPos.Y - halfHeight, suckerPos.Z) * startRotation
	local endCFrame = CFrame.new(suckerPos.X, suckerPos.Y + halfHeight, suckerPos.Z) * startRotation
	
	-- Snap to bottom initially
	char:PivotTo(startCFrame)

	-- Pull player from bottom to top of Sucker for configured duration
	local liftDuration = eventConfig.LiftDuration or 10
	local abductVal = Instance.new("CFrameValue")
	abductVal.Value = startCFrame
	local abductTween = TweenService:Create(abductVal, TweenInfo.new(liftDuration, Enum.EasingStyle.Linear), {Value = endCFrame})
	
	local abductConn = abductVal.Changed:Connect(function(nc)
		if char.Parent then
			char:PivotTo(nc)
		end
	end)
	
	abductTween:Play()
	abductTween.Completed:Wait()
	
	abductConn:Disconnect()
	abductVal:Destroy()

	if char.Parent and char:GetAttribute("IsAbducted") then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0 -- Kill the player
		end
	end

	-- Resume movement
	if ufo.Parent and self._activeEvent == "Abduction" then
		self:_startUFOMovement(ufo, area)
	end
end

function EventService:_handleAbduction(ufo, animal, area)
	local sucker = ufo:FindFirstChild("Sucker", true)
	if not sucker or not animal.Parent then 
		self:_startUFOMovement(ufo, area)
		return 
	end

	local animalService = self._runtime:GetService("AnimalService")
	local eventConfig = self._config.Events.Abduction
	animal:SetAttribute("IsAbducted", true)
	
	-- Mutation chance from config
	local mutationChance = eventConfig.MutationChance or 0.7
	if math.random() <= mutationChance then
		animalService:ApplyAlienMutation(animal)
	end

	-- Use World-Space Verticality to avoid part rotation issues
	local suckerPos = sucker.Position
	local suckerSize = sucker.Size
	-- Use the largest dimension as the beam length
	local beamLength = math.max(suckerSize.X, suckerSize.Y, suckerSize.Z)
	local halfHeight = beamLength / 2
	
	local startRotation = animal:GetPivot().Rotation
	
	-- Vertical movement in world space, centered on the Sucker part
	local startCFrame = CFrame.new(suckerPos.X, suckerPos.Y - halfHeight, suckerPos.Z) * startRotation
	local endCFrame = CFrame.new(suckerPos.X, suckerPos.Y + halfHeight, suckerPos.Z) * startRotation
	
	-- Snap to bottom initially
	animal:PivotTo(startCFrame)

	-- Pull animal upward from bottom to top of Sucker for configured duration
	local liftDuration = eventConfig.LiftDuration or 10
	local abductVal = Instance.new("CFrameValue")
	abductVal.Value = startCFrame
	local abductTween = TweenService:Create(abductVal, TweenInfo.new(liftDuration, Enum.EasingStyle.Linear), {Value = endCFrame})
	
	local abductConn = abductVal.Changed:Connect(function(nc)
		if animal.Parent then
			animal:PivotTo(nc)
		end
	end)
	
	abductTween:Play()
	abductTween.Completed:Wait()
	
	abductConn:Disconnect()
	abductVal:Destroy()

	if animal.Parent and animal:GetAttribute("IsAbducted") then
		-- Gravity Drop Effect: Raycast to the ground before death/drop
		local currentPos = animal:GetPivot().Position
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {animal, ufo}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		
		local result = Workspace:Raycast(currentPos, Vector3.new(0, -500, 0), raycastParams)
		if result then
			-- Instantly teleport to ground (simulating the end of a gravity drop)
			animal:PivotTo(CFrame.new(result.Position) * animal:GetPivot().Rotation)
		end
		
		animalService:_handleAnimalDeath(animal, nil)
	end

	-- Resume movement
	if ufo.Parent and self._activeEvent == "Abduction" then
		self:_startUFOMovement(ufo, area)
	end
end

function EventService:_startTornadoMovement(tornado, parentPart)
	if not tornado.Parent or self._activeEvent ~= "Tornado" then return end

	local areaSize = parentPart.Size
	local areaCF = parentPart.CFrame
	local targetPos = (areaCF * CFrame.new(
		math.random(-areaSize.X/2, areaSize.X/2),
		-areaSize.Y/2 + (tornado.Size.Y/2),
		math.random(-areaSize.Z/2, areaSize.Z/2)
	)).Position

	local dist = (tornado.Position - targetPos).Magnitude
	local speed = 12 -- Studs per second
	local duration = dist / speed

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
	-- Include a constant rotation in the tween goal
	local targetCFrame = CFrame.new(targetPos) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	
	local tween = TweenService:Create(tornado, tweenInfo, {CFrame = targetCFrame})
	
	local connection
	connection = tween.Completed:Connect(function()
		connection:Disconnect()
		if tornado.Parent and self._activeEvent == "Tornado" then
			self:_startTornadoMovement(tornado, parentPart)
		end
	end)
	
	tween:Play()

	-- Secondary loop for continuous spinning while moving
	task.spawn(function()
		while tornado.Parent and self._activeEvent == "Tornado" and tween.PlaybackState == Enum.PlaybackState.Playing do
			tornado.CFrame *= CFrame.Angles(0, 0.25, 0)
			task.wait()
		end
	end)
end

function EventService:_onEventTick(eventName)
	local animalService = self._runtime:GetService("AnimalService")
	local effectsService = self._runtime:GetService("ClientEffectsService")
	if not animalService then return end
	
	local eventConfig = self._config.Events[eventName]
	if not eventConfig then return end

	local mutationChance = (eventConfig.MutationChancePerSecond or 0.25) / 10 -- Convert per-second chance to per-tick (0.1s)
	local damageRange = eventConfig.ShrineDamageRange or {1, 5}

	-- 1. Apply Particles to all animals (generic for any event)
	self:_applyEventParticlesToAll(eventName)

	-- 2. Tornado Logic (Touch ONLY - Movement is now autonomous)
	if eventName == "Tornado" then
		local tornados = CollectionService:GetTagged("TornadoObject")
		
		for _, tornado in ipairs(tornados) do
			-- Touch Logic: Players
			local pushForce = eventConfig.PlayerPushForce or 140
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				
				if hrp then
					local xzDist = (Vector2.new(hrp.Position.X, hrp.Position.Z) - Vector2.new(tornado.Position.X, tornado.Position.Z)).Magnitude
					local yDist = math.abs(hrp.Position.Y - tornado.Position.Y)
					
					-- Cylinder check: 8 studs horizontal radius, 25 studs vertical half-height
					if xzDist < 8 and yDist < 25 then
						-- Cooldown to prevent "random" physics jitter from spamming pushes
						local lastPush = player:GetAttribute("LastTornadoPush") or 0
						if os.clock() - lastPush > 0.5 then
							player:SetAttribute("LastTornadoPush", os.clock())
							if self._remote then
								self._remote:FireClient(player, "TornadoPush", {Force = pushForce})
							end
						end
					end
				end
			end

			-- Touch Logic: Animals (Twistborn Mutation)
			local mutationChanceOnTouch = eventConfig.MutationChanceOnTouch or 0.5
			for _, animal in ipairs(CollectionService:GetTagged("Animal")) do
				local animalPart = animal:FindFirstChild("HumanoidRootPart") or (if animal:IsA("Model") then animal.PrimaryPart else nil)
				if animalPart then
					local xzDist = (Vector2.new(animalPart.Position.X, animalPart.Position.Z) - Vector2.new(tornado.Position.X, tornado.Position.Z)).Magnitude
					local yDist = math.abs(animalPart.Position.Y - tornado.Position.Y)
					
					if xzDist < 9 and yDist < 25 then
						if not animal:GetAttribute("IsTwistborn") and math.random() <= (mutationChanceOnTouch / 5) then -- Divided because tick is fast
							animalService:ApplyTwistbornMutation(animal)
						end
					end
				end
			end
		end
	end

	-- 3. Process all animals for mutations and damage
	for _, animal in ipairs(CollectionService:GetTagged("Animal")) do
		-- CRITICAL SECURITY: Only affect WILD animals (in Animals folder) or PLACED animals (in Bases folder)
		-- This prevents equipped tools (in Character) or inventory tools from being affected.
		local isInAnimalsFolder = animal:IsDescendantOf(Workspace:FindFirstChild("Animals") or Workspace)
		local isInBasesFolder = animal:IsDescendantOf(Workspace:FindFirstChild("Bases") or Workspace)
		
		if not (isInAnimalsFolder or isInBasesFolder) or animal:IsA("Tool") then
			continue
		end
		
		-- Also ensure it's not a drop
		local isDrop = animal.Parent and animal.Parent.Name == "Drops"
		if isDrop then continue end
		
		local isDead = animal:GetAttribute("IsDead")
		local isPlaced = animal:GetAttribute("Placed")

		-- Mutation Chance
		if math.random() <= mutationChance then
			if eventName == "Shrine" then
				if not animal:GetAttribute("IsMalevolent") then
					animalService:ApplyMalevolentMutation(animal)
				end
			elseif eventName == "Rain" then
				if not animal:GetAttribute("IsSoaked") then
					animalService:ApplySoakedMutation(animal)
				end
			end
		end

		-- Damage Logic (Wild animals ONLY for Shrine)
		if eventName == "Shrine" and not isPlaced then
			local health = animal:GetAttribute("Health")
			if health and health > 0 then
				local damage = math.random(damageRange[1], damageRange[2])
				local newHealth = math.max(0, health - damage)
				animal:SetAttribute("Health", newHealth)
				
				local maxHealth = animal:GetAttribute("MaxHealth") or 1
				animalService:_updateHealthBar(animal, newHealth, maxHealth, true)
				
				-- Play hit effects (including the squish animation)
				if effectsService then
					local worldPart = animal:FindFirstChild("HumanoidRootPart") or animal.PrimaryPart
					if worldPart then
						effectsService:EmitToNearby(worldPart.Position, self._config.Effects.Names.ShrineHit, {
							animal = animal,
							position = worldPart.Position,
							damage = damage,
							maxHealth = maxHealth,
						})
					end
				end

				if newHealth <= 0 then
					animalService:_handleAnimalDeath(animal, nil)
				end
			end
		end
	end
end

function EventService:_applyEventParticlesToAnimal(animal, eventName, ignoreWorkspaceCheck)
	-- CRITICAL FILTER: Only affect WILD or PLACED animals.
	-- 1. Ignore Tools (inventory/equipped)
	if animal:IsA("Tool") then return end
	
	-- 2. Ignore Drops
	local isDrop = animal.Parent and animal.Parent.Name == "Drops"
	if isDrop then return end

	-- 3. Check Workspace (unless explicitly ignored during setup)
	if not ignoreWorkspaceCheck and not animal:IsDescendantOf(Workspace) then return end

	local tag = eventName .. "ParticlesApplied"
	local sessionTag = tag .. "_" .. (self._activeEventStartTime or 0)

	if not animal:GetAttribute(sessionTag) then
		local eventsFolder = ServerStorage:FindFirstChild("Events")
		local eventFolder = eventsFolder and eventsFolder:FindFirstChild(eventName)
		local particlesFolder = eventFolder and eventFolder:FindFirstChild("Particles")
		local animalParticles = particlesFolder and particlesFolder:FindFirstChild("AnimalsParticles")
		
		if animalParticles then
			-- Try multiple ways to find a valid VFX parent
			local vfx = animal:FindFirstChild("VfxInstance", true) 
				or animal:FindFirstChild("VFX") 
				or animal:FindFirstChild("HumanoidRootPart") 
				or (if animal:IsA("Model") then animal.PrimaryPart else nil)
				or animal:FindFirstChildWhichIsA("BasePart", true)
			
			if vfx then
				animal:SetAttribute(sessionTag, true)
				for _, pTemplate in ipairs(animalParticles:GetChildren()) do
					local p = pTemplate:Clone()
					CollectionService:AddTag(p, "ActiveEventAsset")
					p.Parent = vfx
				end
			end
		end
	end
end

function EventService:ApplyActiveEventToAnimal(animal)
	if not self._activeEvent then return end
	local eventName = self._activeEvent
	local animalService = self._runtime:GetService("AnimalService")
	if not animalService then return end

	-- 1. Apply Particles (ignoreWorkspaceCheck = true)
	-- Retry a few times if the vfx part isn't found immediately (can happen during fast placement)
	task.spawn(function()
		local retries = 5
		while retries > 0 do
			local tag = eventName .. "ParticlesApplied"
			local sessionTag = tag .. "_" .. (self._activeEventStartTime or 0)
			
			if animal:GetAttribute(sessionTag) then break end
			
			self:_applyEventParticlesToAnimal(animal, eventName, true)
			
			if animal:GetAttribute(sessionTag) then break end
			
			retries -= 1
			task.wait(0.1)
		end
	end)

	-- 2. Mutation Chance (One-shot 25% check for newly placed animals)
	-- Prevent rerolling by checking if this animal instance already rolled for the current event
	local sessionStartTime = self._activeEventStartTime or 0
	if animal:GetAttribute("MutationRollSession") == sessionStartTime then
		return
	end
	
	-- Mark as rolled for this session
	animal:SetAttribute("MutationRollSession", sessionStartTime)

	local oneShotChance = 0.25

	if math.random() <= oneShotChance then
		if eventName == "Shrine" then
			if not animal:GetAttribute("IsMalevolent") then
				animalService:ApplyMalevolentMutation(animal)
			end
		elseif eventName == "Rain" then
			if not animal:GetAttribute("IsSoaked") then
				animalService:ApplySoakedMutation(animal)
			end
		end
	end
end

function EventService:GetActiveEvent()
	return self._activeEvent
end

function EventService:_applyEventParticlesToAll(eventName)
	for _, animal in ipairs(CollectionService:GetTagged("Animal")) do
		self:_applyEventParticlesToAnimal(animal, eventName)
	end
end

function EventService:EndEvent(eventName: string?)
	if not self._activeEvent then return end
	
	-- If a specific event name is provided, only stop if it matches
	if eventName and self._activeEvent ~= eventName then
		return
	end
	
	local activeEventName = self._activeEvent
	self._activeEvent = nil
	
	if self._eventEndTask then
		if self._eventEndTask ~= coroutine.running() then
			pcall(function() task.cancel(self._eventEndTask) end)
		end
		self._eventEndTask = nil
	end
	
	-- Restore Lighting
	restoreLighting(self._originalLighting, self._backupLightingFolder)
	
	-- Clean up objects and particles
	cleanUpEventAssets("ActiveEventAsset")
	
	local rsEvents = ReplicatedStorage:FindFirstChild("ActiveEvents")
	if rsEvents then rsEvents:ClearAllChildren() end
	
	if self._remote then
		self._remote:FireAllClients("EndEvent", {EventName = activeEventName})
	end
end

function EventService:TriggerGlobalEvent(eventName: string, action: string?)
	action = action or "Start"
	
	local success, err = pcall(function()
		MessagingService:PublishAsync(GLOBAL_EVENT_TOPIC, {
			Action = action,
			EventName = eventName
		})
	end)
	
	if not success then
		warn("[EventService] Failed to publish global event:", err)
		return false, err
	end
	
	return true
end

function EventService:Start()
	pcall(function()
		MessagingService:SubscribeAsync(GLOBAL_EVENT_TOPIC, function(message)
			local data = message.Data
			if type(data) ~= "table" then return end
			
			local action = data.Action
			local eventName = data.EventName
			
			if action == "Start" then
				self:TriggerEvent(eventName)
			elseif action == "Stop" then
				self:EndEvent(eventName)
			end
		end)
	end)

	-- Automated Event Loop
	task.spawn(function()
		while true do
			local eventConfig = self._config.Events
			local interval = eventConfig and eventConfig.EventInterval or 60
			task.wait(interval)
			
			if not self._activeEvent then
				-- Try to pick an event based on weights
				local possibleEvents = {}
				for eventName, config in pairs(eventConfig) do
					if type(config) == "table" and config.Chance then
						table.insert(possibleEvents, {Name = eventName, Chance = config.Chance})
					end
				end
				
				if #possibleEvents > 0 then
					-- Simple approach: Roll for each until one succeeds or all fail
					-- (Could be changed to weighted random if many events are added)
					for _, eventData in ipairs(possibleEvents) do
						if math.random() <= eventData.Chance then
							self:TriggerEvent(eventData.Name)
							break
						end
					end
				end
			end
		end
	end)
end

return EventService
