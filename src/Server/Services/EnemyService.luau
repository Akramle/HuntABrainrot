local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SafeZoneHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SafeZoneHelper"))

local EnemyService = {
  Name = "EnemyService",
  Priority = -10,
}

-- Standard R15 Animation IDs
local ANIM_NAMES = { 
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
}

local ANIM_TABLE = {}
for name, fileList in pairs(ANIM_NAMES) do
  ANIM_TABLE[name] = { count = 0, totalWeight = 0 }
  for idx, anim in pairs(fileList) do
    ANIM_TABLE[name][idx] = {}
    local animObj = Instance.new("Animation")
    animObj.Name = name
    animObj.AnimationId = anim.id
    ANIM_TABLE[name][idx].anim = animObj
    ANIM_TABLE[name][idx].weight = anim.weight
    ANIM_TABLE[name].count = ANIM_TABLE[name].count + 1
    ANIM_TABLE[name].totalWeight = ANIM_TABLE[name].totalWeight + anim.weight
  end
end

-- Default configuration (can be overridden by attributes)
local DEFAULT_CONFIG = {
  ENEMY_SCALE = 1,
  DETECTION_RADIUS = 50,
  FIELD_OF_VIEW = 120,
  WANDER_RADIUS = 20,
  DAMAGE_PERCENTAGE = 0.2,
  LAUNCH_FORCE = 500,
  STUN_DURATION = 3,
  SPEED = 16,
  SHOW_ZONES = false, -- Set to false to hide debugging radii
}

function EnemyService:Init(runtime)
  self._runtime = runtime
  self._config = runtime.Config
  self._enemies = {} -- [instance] = state_table
end

function EnemyService:isInSafeZone(position)
  return SafeZoneHelper.isInSafeZone(position)
end

local function isPartVisible(part: BasePart): boolean
  if part.Transparency < 0.95 then return true end
  for _, child in ipairs(part:GetChildren()) do
    if child:IsA("Decal") or child:IsA("Texture") or child:IsA("DataModelMesh") then
      return true
    end
  end
  return false
end

function EnemyService:_setupEnemy(npc: Model)
  local humanoid = npc:FindFirstChildOfClass("Humanoid")
  local rootPart = npc:FindFirstChild("HumanoidRootPart")
  if not humanoid or not rootPart then return end

  -- Enforce Server Network Ownership to prevent jitter from client physics overrides
  if rootPart:CanSetNetworkOwnership() then
    rootPart:SetNetworkOwner(nil)
  end

  -- Set Collision Group
  for _, descendant in ipairs(npc:GetDescendants()) do
    -- Disable conflicting animation scripts
    if descendant:IsA("LuaSourceContainer") and (descendant.Name == "Animate" or descendant.Name == "EnemyAnimator") then
        if descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant.Enabled = false
        end
    end
  end

  -- Load configuration from attributes or defaults
  local config = {}
  for key, defaultValue in pairs(DEFAULT_CONFIG) do
    local val = npc:GetAttribute(key)
    config[key] = if val ~= nil then val else defaultValue
  end

  -- Apply scale
  local previousExtentsY = npc:GetExtentsSize().Y
  npc:ScaleTo(config.ENEMY_SCALE)
  humanoid.WalkSpeed = config.SPEED
  
  -- Increase HipHeight slightly for high-speed stability to prevent floor clipping
  humanoid.HipHeight = humanoid.HipHeight + 0.2

  -- GROUND ALIGNMENT: Prevent getting stuck after scaling
  task.defer(function()
    if not npc.Parent or not rootPart.Parent then return end
    
    local currentExtentsY = npc:GetExtentsSize().Y
    local diffY = currentExtentsY - previousExtentsY
    
    if diffY > 0.1 then
      npc:PivotTo(npc:GetPivot() + Vector3.new(0, (diffY / 2) + 1, 0))
    end
  end)

  -- ANIMATION SETUP
  local tracks = {}
  for name, set in pairs(ANIM_TABLE) do
    tracks[name] = {}
    for i = 1, set.count do
      local track = humanoid:LoadAnimation(set[i].anim)
      track.Priority = Enum.AnimationPriority.Core
      tracks[name][i] = { track = track, weight = set[i].weight }
    end
    tracks[name].totalWeight = set.totalWeight
    tracks[name].count = set.count
  end

  local animState = {
    currentAnim = "",
    currentAnimTrack = nil,
    pose = "Standing",
    lastSpeed = 0,
    smoothedSpeed = 0
  }

  local function playAnim(animName, transitionTime, animSpeed)
    local set = tracks[animName]
    if not set or set.count == 0 then return end
    
    if animState.currentAnimTrack and animState.currentAnim == animName then
      if animSpeed and math.abs(animState.lastSpeed - animSpeed) > 0.05 then
        animState.currentAnimTrack:AdjustSpeed(animSpeed)
        animState.lastSpeed = animSpeed
      end
      return 
    end

    local roll = math.random(1, set.totalWeight) 
    local idx = 1
    while (roll > set[idx].weight) do
      roll = roll - set[idx].weight
      idx = idx + 1
    end
    
    local track = set[idx].track

    if animState.currentAnimTrack then 
      animState.currentAnimTrack:Stop(transitionTime) 
    end

    track:Play(transitionTime)
    if animSpeed then
      track:AdjustSpeed(animSpeed)
      animState.lastSpeed = animSpeed
    end
    
    animState.currentAnimTrack = track
    animState.currentAnim = animName
  end

  local animConnections = {
    humanoid.Died:Connect(function() 
      if animState.currentAnimTrack then animState.currentAnimTrack:Stop() end
      animState.pose = "Dead" 
    end),
    humanoid.Jumping:Connect(function() playAnim("jump", 0.1, 1) animState.pose = "Jumping" end),
    humanoid.Climbing:Connect(function() playAnim("climb", 0.1, 1) animState.pose = "Climbing" end),
    humanoid.FreeFalling:Connect(function(active) 
      -- Only set falling pose if we are genuinely high in the air
      if active then
        local rayOrigin = rootPart.Position
        local rayDirection = Vector3.new(0, -10, 0)
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {npc}
        params.FilterType = Enum.RaycastFilterType.Exclude
        local res = Workspace:Raycast(rayOrigin, rayDirection, params)
        if res and (rayOrigin.Y - res.Position.Y) > 5 then
          playAnim("fall", 0.2, 1) 
          animState.pose = "FreeFall" 
        end
      end
    end),
    humanoid.Seated:Connect(function() playAnim("sit", 0.5, 1) animState.pose = "Seated" end)
  }
  
  playAnim("idle", 0.1, 1)

  -- Setup Pathfinding
  local path = PathfindingService:CreatePath({
    AgentRadius = 2 * config.ENEMY_SCALE,
    AgentHeight = 5 * config.ENEMY_SCALE,
    AgentCanJump = true,
    AgentCanClimb = false,
    Costs = {
      SafeZone = math.huge -- Forces algorithm to route around SafeZones
    }
  })

  -- Internal state
  local scaledWanderRadius = config.WANDER_RADIUS * math.sqrt(config.ENEMY_SCALE)
  local scaledDetectionRadius = config.DETECTION_RADIUS * config.ENEMY_SCALE

  local state = {
    npc = npc,
    humanoid = humanoid,
    rootPart = rootPart,
    config = config,
    startPosition = rootPart.Position,
    canAttack = true,
    isOnCooldown = false,
    isWandering = false,
    targetPosition = nil,
    wanderTimer = 0,
    lastUpdate = 0,
    enemyHeight = npc:GetExtentsSize().Y,
    floorOffset = humanoid.HipHeight + (rootPart.Size.Y / 2) - 0.5,
    animState = animState,
    animConnections = animConnections,
    playAnim = playAnim,
    tracks = tracks,
    path = path,
    waypoints = nil,
    currentWaypointIndex = 0,
    lastPathTime = 0,
    currentMoveTarget = nil,
    scaledWanderRadius = scaledWanderRadius,
    scaledDetectionRadius = scaledDetectionRadius,
  }

  -- Setup Touch Detection
  local touchConnections = {}
  for _, part in ipairs(npc:GetChildren()) do
    if part:IsA("BasePart") then
      local conn = part.Touched:Connect(function(hit)
        self:_onEnemyTouched(npc, hit)
      end)
      table.insert(touchConnections, conn)
    end
  end
  state.touchConnections = touchConnections
  
  -- Visualization Setup
  if config.SHOW_ZONES then
    -- Wander Zone (Anchored Cylinder at Spawn)
    local wanderVis = Instance.new("Part")
    wanderVis.Name = "WanderRadiusVis"
    wanderVis.Shape = Enum.PartType.Cylinder
    wanderVis.Size = Vector3.new(50, state.scaledWanderRadius * 2, state.scaledWanderRadius * 2)
    wanderVis.Color = Color3.new(0, 0.5, 1)
    wanderVis.Transparency = 0.9
    wanderVis.Material = Enum.Material.Neon
    wanderVis.CanCollide = false
    wanderVis.CanQuery = false
    wanderVis.CanTouch = false
    wanderVis.Anchored = true
    wanderVis.CastShadow = false
    -- Rotate 90 degrees so the cylinder stands upright
    wanderVis.CFrame = CFrame.new(state.startPosition) * CFrame.Angles(0, 0, math.pi/2)
    wanderVis.Parent = npc

    -- Detection Zone (Welded Sphere on Enemy)
    local detectVis = Instance.new("Part")
    detectVis.Name = "DetectionRadiusVis"
    detectVis.Shape = Enum.PartType.Ball
    detectVis.Size = Vector3.new(state.scaledDetectionRadius * 2, state.scaledDetectionRadius * 2, state.scaledDetectionRadius * 2)
    detectVis.Color = Color3.new(1, 0, 0)
    detectVis.Transparency = 0.9
    detectVis.Material = Enum.Material.Neon
    detectVis.CanCollide = false
    detectVis.CanQuery = false
    detectVis.CanTouch = false
    detectVis.Massless = true
    detectVis.CastShadow = false
    detectVis.CFrame = rootPart.CFrame
    detectVis.Parent = npc

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rootPart
    weld.Part1 = detectVis
    weld.Parent = detectVis
    
    state.visuals = {wanderVis, detectVis}
  end

  self._enemies[npc] = state

  npc.Destroying:Connect(function()
    self:_cleanupEnemy(npc)
  end)
end

function EnemyService:_cleanupEnemy(npc)
  local state = self._enemies[npc]
  if not state then return end

  if state.touchConnections then
    for _, conn in ipairs(state.touchConnections) do
      conn:Disconnect()
    end
  end
  
  if state.visuals then
    for _, v in ipairs(state.visuals) do
      if v then v:Destroy() end
    end
  end

  self._enemies[npc] = nil
end

function EnemyService:_onEnemyTouched(npc, hit)
  local state = self._enemies[npc]
  if not state or not state.canAttack then return end

  local character = hit.Parent
  if not character then return end
  
  local targetHumanoid = character:FindFirstChild("Humanoid")
  local targetRoot = character:FindFirstChild("HumanoidRootPart")

  if targetHumanoid and targetRoot and targetHumanoid ~= state.humanoid and targetHumanoid.Health > 0 then
    local player = Players:GetPlayerFromCharacter(character)
    if not player or player:GetAttribute("IsHiding") or character:GetAttribute("IsAbducted") then return end
    if not player:GetAttribute("CarryingAnimal") then return end

    state.canAttack = false
    state.isOnCooldown = true 
    state.waypoints = nil -- Cancel pathing while attacking
    state.currentMoveTarget = nil

    targetHumanoid:TakeDamage(targetHumanoid.MaxHealth * state.config.DAMAGE_PERCENTAGE)
    self:_applyRagdoll(character, 1)

    local soundService = self._runtime:GetService("SoundService")
    if soundService then
      soundService:PlayForPlayer(player, "EnemyHit")
    end

    -- NEW: Instead of clearing inventory, drop carried animal
    local animalService = self._runtime:GetService("AnimalService")
    if animalService then
      if player:GetAttribute("CarryingAnimal") then
        animalService:DropCarriedAnimal(player)
      end
    end

    local launchDirection = (targetRoot.Position - state.rootPart.Position).Unit
    launchDirection = (launchDirection + Vector3.new(0, 1, 0)).Unit 
    targetRoot.AssemblyLinearVelocity = launchDirection * state.config.LAUNCH_FORCE

    -- Enemy cooldown is STUN_DURATION
    task.delay(state.config.STUN_DURATION, function()
      if self._enemies[npc] then
        state.canAttack = true
        state.isOnCooldown = false
      end
    end)
  end
end

function EnemyService:_applyRagdoll(character, duration)
  local targetHumanoid = character:FindFirstChild("Humanoid")
  local rootPart = character:FindFirstChild("HumanoidRootPart")
  if not targetHumanoid or not rootPart then return end

  for _, part in ipairs(character:GetDescendants()) do
    if part:IsA("BasePart") then
      part:SetNetworkOwner(nil)
    end
  end

  targetHumanoid.AutoRotate = false
  targetHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
  
  local storedMotors = {}
  local ragdollConstraints = {}

  for _, desc in ipairs(character:GetDescendants()) do
    if desc:IsA("Motor6D") and desc.Name ~= "Root" and desc.Name ~= "Neck" and not desc:FindFirstAncestorWhichIsA("Accessory") then
      local a0 = desc.Part0:FindFirstChild(desc.Name .. "RigAttachment")
      local a1 = desc.Part1:FindFirstChild(desc.Name .. "RigAttachment")

      if a0 and a1 then
        desc.Enabled = false
        
        local socket = Instance.new("BallSocketConstraint")
        socket.Attachment0 = a0
        socket.Attachment1 = a1
        socket.LimitsEnabled = true
        socket.TwistLimitsEnabled = true
        
        local n = desc.Name
        if string.find(n, "Shoulder") then
          socket.UpperAngle = 110
          socket.TwistLowerAngle = -80
          socket.TwistUpperAngle = 80
        elseif string.find(n, "Hip") then
          socket.UpperAngle = 90
          socket.TwistLowerAngle = -45
          socket.TwistUpperAngle = 45
        elseif string.find(n, "Knee") then
          socket.UpperAngle = 5
          socket.TwistLowerAngle = -10
          socket.TwistUpperAngle = 10
        elseif string.find(n, "Elbow") then
          socket.UpperAngle = 5
          socket.TwistLowerAngle = -10
          socket.TwistUpperAngle = 10
        else
          socket.UpperAngle = 45
          socket.TwistLowerAngle = -45
          socket.TwistUpperAngle = 45
        end
        
        socket.MaxFrictionTorque = 0.5
        socket.Parent = desc.Parent
        
        table.insert(storedMotors, desc)
        table.insert(ragdollConstraints, socket)
      end
    end
    
    if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" and desc.Name ~= "Head" and not desc:FindFirstAncestorWhichIsA("Accessory") then
      desc.CanCollide = true
      local noCol = Instance.new("NoCollisionConstraint")
      noCol.Part0 = rootPart
      noCol.Part1 = desc
      noCol.Parent = desc
      table.insert(ragdollConstraints, noCol)
    end
  end

  task.delay(duration, function()
    if targetHumanoid and targetHumanoid.Health > 0 then
      for _, obj in ipairs(ragdollConstraints) do
        obj:Destroy()
      end
      
      for _, motor in ipairs(storedMotors) do
        motor.Enabled = true
      end
      
      targetHumanoid.AutoRotate = true
      targetHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
      
      local player = Players:GetPlayerFromCharacter(character)
      if player then
        for _, part in ipairs(character:GetDescendants()) do
          if part:IsA("BasePart") then
            part:SetNetworkOwner(player)
          end
        end
      end
    end
  end)
end

function EnemyService:_isNearLedge(state)
  local moveDir = state.humanoid.MoveDirection
  if moveDir.Magnitude < 0.1 then
    moveDir = state.rootPart.CFrame.LookVector
  end

  local rayOrigin = state.rootPart.Position + (moveDir * (12 * (state.config.ENEMY_SCALE / 5))) 
  local rayDirection = Vector3.new(0, -state.enemyHeight - 10, 0)

  local raycastParams = RaycastParams.new()
  raycastParams.FilterDescendantsInstances = {state.npc}
  raycastParams.FilterType = Enum.RaycastFilterType.Exclude

  local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
  return raycastResult == nil
end

function EnemyService:_findNearestPlayer(state)
  local nearestTarget = nil
  local shortestDistance = state.scaledDetectionRadius
  local enemyPos = state.rootPart.Position
  local spawnPos = state.startPosition

  for _, player in ipairs(Players:GetPlayers()) do
    -- Enemies should only target players carrying an animal.
    if not player:GetAttribute("CarryingAnimal") then
      continue
    end

    local character = player.Character
    if character and character:FindFirstChild("Humanoid") and character:FindFirstChild("HumanoidRootPart") then
      if character.Humanoid.Health > 0 and not player:GetAttribute("IsHiding") and not character:GetAttribute("IsAbducted") then
        local playerPos = character.HumanoidRootPart.Position
        
        if self:isInSafeZone(playerPos) then continue end

        -- Ensure player is within the wander radius of the enemy's spawn
        local pTarget = Vector2.new(playerPos.X, playerPos.Z)
        local pStart = Vector2.new(spawnPos.X, spawnPos.Z)
        if (pTarget - pStart).Magnitude > state.scaledWanderRadius then
          continue
        end

        local distance = (playerPos - enemyPos).Magnitude
        if distance <= shortestDistance then
          shortestDistance = distance
          nearestTarget = character
        end
      end
    end
  end
  return nearestTarget
end

function EnemyService:_setupSafeZoneModifiers()
  local function addModifier(zone)
    if zone:IsA("BasePart") and not zone:FindFirstChild("SafeZoneModifier") then
      local modifier = Instance.new("PathfindingModifier")
      modifier.Name = "SafeZoneModifier"
      modifier.Label = "SafeZone" 
      modifier.PassThrough = false
      modifier.Parent = zone
    end
  end

  for _, zone in ipairs(CollectionService:GetTagged("SafeZone")) do
    addModifier(zone)
  end

  CollectionService:GetInstanceAddedSignal("SafeZone"):Connect(addModifier)
end

function EnemyService:Start()
  self:_setupSafeZoneModifiers()

  for _, npc in ipairs(CollectionService:GetTagged("Enemy")) do
    self:_setupEnemy(npc)
  end

  CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(npc)
    if npc:IsA("Model") then
      self:_setupEnemy(npc)
    end
  end)

  RunService.Heartbeat:Connect(function(dt)
    local now = os.clock()
    for npc, state in pairs(self._enemies) do
      self:_updateEnemyMovement(state)
      self:_updateEnemyAnimation(state)

      if now - state.lastUpdate >= 0.1 then
        state.lastUpdate = now
        self:_updateEnemyAI(state, dt)
      end
    end
  end)
end

function EnemyService:_updateEnemyMovement(state)
  if state.waypoints and state.currentWaypointIndex <= #state.waypoints then
    local nextWaypoint = state.waypoints[state.currentWaypointIndex]
    
    local p1 = state.rootPart.Position
    local p2 = nextWaypoint.Position
    local flatDistance = (Vector3.new(p1.X, 0, p1.Z) - Vector3.new(p2.X, 0, p2.Z)).Magnitude

    if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
      state.humanoid.Jump = true
    end

    self:_smartMoveTo(state, nextWaypoint.Position)

    local threshold = math.max(4, state.humanoid.WalkSpeed * 0.1)
    if flatDistance < threshold then
      state.currentWaypointIndex += 1
    end
  end
end

function EnemyService:_updateEnemyAnimation(state)
  local animState = state.animState
  if animState.pose == "Dead" or animState.pose == "Jumping" or animState.pose == "Climbing" then
    return
  end

  local velocity = state.rootPart.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
  local speed = velocity.Magnitude

  animState.smoothedSpeed = (animState.smoothedSpeed * 0.9) + (speed * 0.1)
  local activeSpeed = animState.smoothedSpeed
  local playAnim = state.playAnim

  if activeSpeed > 3.0 then
    local animName = if activeSpeed > 32 then "run" else "walk"
    local animSpeed = math.clamp(if animName == "run" then activeSpeed / 32 else activeSpeed / 16, 0.5, 3.0)
    
    if animState.pose ~= "Running" or math.abs(animState.lastSpeed - animSpeed) > 0.15 or animState.currentAnim ~= animName then
      playAnim(animName, 0.2, animSpeed)
      animState.pose = "Running"
    end
  else
    if activeSpeed < 1.5 and animState.pose ~= "Standing" then
      playAnim("idle", 0.2, 1)
      animState.pose = "Standing"
      animState.lastSpeed = 0
    end
  end
end

function EnemyService:_smartMoveTo(state, position)
  if not state.currentMoveTarget or (state.currentMoveTarget - position).Magnitude > 0.5 then
    state.currentMoveTarget = position
    state.humanoid:MoveTo(position)
  end
end

function EnemyService:_updateEnemyAI(state, dt)
  local rootPos = state.rootPart.Position
  local pEnemy = Vector2.new(rootPos.X, rootPos.Z)
  local pStart = Vector2.new(state.startPosition.X, state.startPosition.Z)
  local distFromSpawn = (pEnemy - pStart).Magnitude

  -- Hard Leash: Enemy must never be physically outside the WANDER_RADIUS
  if distFromSpawn > state.scaledWanderRadius then
    state.isWandering = false
    state.targetPosition = nil
    state.waypoints = nil
    self:_smartMoveTo(state, state.startPosition)
    return
  end

  if self:isInSafeZone(rootPos) or self:_isNearLedge(state) then
    state.isWandering = false
    state.targetPosition = nil
    state.waypoints = nil
    self:_smartMoveTo(state, state.startPosition)
    return
  end

  local target = if not state.isOnCooldown then self:_findNearestPlayer(state) else nil

  if target then
    -- Player is inside DETECTION_ZONE and WANDER_RADIUS: Chase them
    state.isWandering = false
    state.targetPosition = nil
    state.waypoints = nil 
    
    local targetPos = target.HumanoidRootPart.Position
    self:_smartMoveTo(state, targetPos)
  else
    -- Player left DETECTION_ZONE (or no target): Stop chasing immediately and Wander
    if not state.isWandering then
      state.isWandering = true
      state.wanderTimer = 0
      
      -- Immediately halt movement towards the lost target to prevent coasting
      state.currentMoveTarget = nil
      state.waypoints = nil
      state.humanoid:MoveTo(state.rootPart.Position)
      
      self:_setNewWanderTarget(state)
    else
      state.wanderTimer += 0.1
      if state.wanderTimer >= 8 or not state.waypoints then
        state.wanderTimer = 0
        self:_setNewWanderTarget(state)
      end
    end
  end
end

function EnemyService:_setNewWanderTarget(state)
  local attempts = 0
  local success = false

  while attempts < 5 and not success do
    attempts += 1
    local angle = math.random() * math.pi * 2
    local r = math.sqrt(math.random()) * state.scaledWanderRadius
    local randomX = math.cos(angle) * r
    local randomZ = math.sin(angle) * r
    local targetPos = state.startPosition + Vector3.new(randomX, 0, randomZ)

    if not self:isInSafeZone(targetPos) then
      local pcallSuccess, _ = pcall(function()
        state.path:ComputeAsync(state.rootPart.Position, targetPos)
      end)

      if pcallSuccess and state.path.Status == Enum.PathStatus.Success then
        state.targetPosition = targetPos
        state.waypoints = state.path:GetWaypoints()
        state.currentWaypointIndex = 2
        success = true
      end
    end
  end

  if not success then
    state.targetPosition = nil
    state.waypoints = nil
    state.currentMoveTarget = nil
  end
end

return EnemyService
