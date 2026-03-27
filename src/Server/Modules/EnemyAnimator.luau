local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")
local pose = "Standing"

local HumanoidHipHeight = 2
local EMOTE_TRANSITION_TIME = 0.1

local currentAnim = ""
local currentAnimInstance = nil
local currentAnimTrack = nil
local currentAnimKeyframeHandler = nil
local currentAnimSpeed = 1.0

local runAnimTrack = nil
local runAnimKeyframeHandler = nil

local PreloadedAnims = {}
local animTable = {}

-- Standard R15 Animation IDs
local animNames = { 
	idle = {	
		{ id = "http://www.roblox.com/asset/?id=507766666", weight = 1 },
		{ id = "http://www.roblox.com/asset/?id=507766951", weight = 1 },
		{ id = "http://www.roblox.com/asset/?id=507766388", weight = 9 }
	},
	walk = { { id = "http://www.roblox.com/asset/?id=507777826", weight = 10 } }, 
	run = { { id = "http://www.roblox.com/asset/?id=507767714", weight = 10 } }, 
	jump = { { id = "http://www.roblox.com/asset/?id=507765000", weight = 10 } }, 
	fall = { { id = "http://www.roblox.com/asset/?id=507767968", weight = 10 } }, 
	climb = { { id = "http://www.roblox.com/asset/?id=507765644", weight = 10 } }, 
	sit = { { id = "http://www.roblox.com/asset/?id=2506281703", weight = 10 } },	
	toolnone = { { id = "http://www.roblox.com/asset/?id=507768375", weight = 10 } },
}

local emoteNames = { dance = true, dance2 = true, dance3 = true, wave = false, point = false }

math.randomseed(tick())

local function getRigScale()
	return Character:GetScale()
end

function configureAnimationSet(name, fileList)
	if (animTable[name] ~= nil) then
		for _, connection in pairs(animTable[name].connections) do connection:disconnect() end
	end

	animTable[name] = { count = 0, totalWeight = 0, connections = {} }

	-- Fallback to defaults (NPCs usually don't need the Folder-based override but we keep it simple)
	for idx, anim in pairs(fileList) do
		animTable[name][idx] = {}
		animTable[name][idx].anim = Instance.new("Animation")
		animTable[name][idx].anim.Name = name
		animTable[name][idx].anim.AnimationId = anim.id
		animTable[name][idx].weight = anim.weight
		animTable[name].count = animTable[name].count + 1
		animTable[name].totalWeight = animTable[name].totalWeight + anim.weight
	end

	-- Preload
	for idx = 1, animTable[name].count do
		local animObj = animTable[name][idx].anim
		if not PreloadedAnims[animObj.AnimationId] then
			Humanoid:LoadAnimation(animObj)
			PreloadedAnims[animObj.AnimationId] = true
		end
	end
end

function stopAllAnimations()
	currentAnim = ""
	currentAnimInstance = nil
	if currentAnimKeyframeHandler then currentAnimKeyframeHandler:disconnect() end
	if currentAnimTrack then
		currentAnimTrack:Stop()
		currentAnimTrack:Destroy()
		currentAnimTrack = nil
	end
	if runAnimTrack then
		runAnimTrack:Stop()
		runAnimTrack:Destroy()
		runAnimTrack = nil
	end
	return "idle"
end

function rollAnimation(animName)
	local roll = math.random(1, animTable[animName].totalWeight) 
	local idx = 1
	while (roll > animTable[animName][idx].weight) do
		roll = roll - animTable[animName][idx].weight
		idx = idx + 1
	end
	return idx
end

local function switchToAnim(anim, animName, transitionTime, humanoid, animSpeed)
	if (anim ~= currentAnimInstance or (currentAnimTrack and currentAnim == animName)) then
		if currentAnimInstance ~= anim then
			if currentAnimTrack then currentAnimTrack:Stop(transitionTime) currentAnimTrack:Destroy() end
			if runAnimTrack then runAnimTrack:Stop(transitionTime) runAnimTrack:Destroy() end

			currentAnimTrack = humanoid:LoadAnimation(anim)
			currentAnimTrack.Priority = Enum.AnimationPriority.Core
			currentAnimTrack:Play(transitionTime)
			currentAnim = animName
			currentAnimInstance = anim

			if currentAnimKeyframeHandler then currentAnimKeyframeHandler:disconnect() end
			currentAnimKeyframeHandler = currentAnimTrack.KeyframeReached:Connect(function(frameName)
				if frameName == "End" and not currentAnimTrack.Looped then
					playAnimation("idle", 0.1, Humanoid, 1)
				end
			end)
		end

		if animSpeed and currentAnimTrack then
			currentAnimTrack:AdjustSpeed(animSpeed)
		end
	end
end

function playAnimation(animName, transitionTime, humanoid, animSpeed) 	
	local idx = rollAnimation(animName)
	switchToAnim(animTable[animName][idx].anim, animName, transitionTime, humanoid, animSpeed)
end

-------------------------------------------------------------------------------------------
-- STATE UPDATES (Optimized for NPC Logic)

function onRunning(speed)
	if speed > 0.5 then
		local animName = if speed > 32 then "run" else "walk"
		local animSpeed = if animName == "run" then speed / 32 else speed / 16
		playAnimation(animName, 0.2, Humanoid, animSpeed)
		pose = "Running"
	else
		playAnimation("idle", 0.2, Humanoid, 1)
		pose = "Standing"
	end
end

function onDied() pose = "Dead" end
function onJumping() playAnimation("jump", 0.1, Humanoid, 1) pose = "Jumping" end
function onClimbing(speed) playAnimation("climb", 0.1, Humanoid, 1) pose = "Climbing" end
function onFreeFall() playAnimation("fall", 0.2, Humanoid, 1) pose = "FreeFall" end
function onSeated() playAnimation("sit", 0.5, Humanoid, 1) pose = "Seated" end

-- Initialization
for name, fileList in pairs(animNames) do 
	configureAnimationSet(name, fileList)
end

Humanoid.Running:Connect(onRunning)
Humanoid.Died:Connect(onDied)
Humanoid.Jumping:Connect(onJumping)
Humanoid.Climbing:Connect(onClimbing)
Humanoid.FreeFalling:Connect(onFreeFall)
Humanoid.Seated:Connect(onSeated)

-- Play initial idle
playAnimation("idle", 0.1, Humanoid)

-- Simple NPC loop to maintain state if movement stops abruptly
task.spawn(function()
	while Character.Parent do
		local velocity = RootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		if velocity.Magnitude < 0.1 and pose == "Running" then
			onRunning(0)
		end
		task.wait(0.2)
	end
end)