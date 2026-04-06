local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ScreenEffects = {}

local activeParticles = {}
local updateConnection = nil
local MAX_ACTIVE_PARTICLES = 220

local COLORS = {
  Confetti = {
    Color3.fromRGB(255, 69, 58),
    Color3.fromRGB(48, 209, 88),
    Color3.fromRGB(10, 132, 255),
    Color3.fromRGB(255, 214, 10),
    Color3.fromRGB(255, 159, 10),
    Color3.fromRGB(191, 90, 242),
    Color3.fromRGB(255, 55, 95),
  },
  Divine = {
    Color3.fromRGB(255, 255, 255), -- White
    Color3.fromRGB(255, 240, 150), -- Bright Golden
    Color3.fromRGB(255, 215, 0),   -- Pure Gold
    Color3.fromRGB(220, 180, 255), -- Pale Purple
  }
}

local function randomVignetteColor()
  local hue = math.random()
  local saturation = math.random(45, 80) / 100
  local value = math.random(75, 100) / 100
  return Color3.fromHSV(hue, saturation, value)
end

local function startUpdateLoop()
  if updateConnection then return end
  updateConnection = RunService.RenderStepped:Connect(function(deltaTime)
    if #activeParticles == 0 then
      updateConnection:Disconnect()
      updateConnection = nil
      return
    end

    for i = #activeParticles, 1, -1 do
      local p = activeParticles[i]
      
      p.Life -= deltaTime
      local age = p.MaxLife - p.Life
      local alpha = p.Life / p.MaxLife

      if p.Type == "Confetti" then
        p.VelocityY += p.Gravity * deltaTime
        p.VelocityX *= (1 - (p.Drag * deltaTime))
        p.X += p.VelocityX * deltaTime
        p.Y += p.VelocityY * deltaTime
        p.TumbleTime += deltaTime * p.TumbleSpeed
        local scaleY = math.abs(math.cos(p.TumbleTime))
        p.Rotation += p.RotationSpeed * deltaTime
        
        local currentScale = 1
        if age < 0.1 then currentScale = age / 0.1 end
        if p.Life <= 0.5 then currentScale = alpha * 2 end

        p.Element.Position = UDim2.new(0, p.X, 0, p.Y)
        p.Element.Rotation = p.Rotation
        p.Element.Size = UDim2.new(0, p.SizeX * currentScale, 0, (p.SizeY * scaleY) * currentScale)
        p.Element.BackgroundTransparency = 1 - alpha

      elseif p.Type == "DivineRay" then
        -- Rotate
        p.Element.Rotation += p.RotationSpeed * deltaTime
        
        -- Explosive scale easing (starts fast, slows down)
        local progress = 1 - alpha
        local easeOutQuint = 1 - math.pow(1 - progress, 5)
        
        local scale = p.BaseScale + (p.TargetScale - p.BaseScale) * easeOutQuint
        p.Element.Size = UDim2.new(p.BaseSize.X.Scale, 0, scale, 0)
        
        -- Fade out smoothly over its life
        p.Element.BackgroundTransparency = 1 - (alpha * p.MaxOpacity)
      end

      if p.Life <= 0 then
        p.Element:Destroy()
        table.remove(activeParticles, i)
      end
    end
  end)
end

local function canSpawnParticle()
	return #activeParticles < MAX_ACTIVE_PARTICLES
end

local function getScreenGui(player)
  local playerGui = player:WaitForChild("PlayerGui")
  local gui = playerGui:FindFirstChild("ScreenEffectsGui")
  if not gui then
    gui = Instance.new("ScreenGui")
    gui.Name = "ScreenEffectsGui"
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.Parent = playerGui
  end
  return gui
end

function ScreenEffects.ConfettiBurst(player, amount)
  local gui = getScreenGui(player)
  local screenWidth = gui.AbsoluteSize.X
  amount = amount or 100
  if #activeParticles >= MAX_ACTIVE_PARTICLES then
    return
  end
  amount = math.min(amount, MAX_ACTIVE_PARTICLES - #activeParticles)
  
  for i = 1, amount do
    if not canSpawnParticle() then
      break
    end
    local isLeft = i <= (amount / 2)
    local originX = isLeft and 0 or screenWidth
    local originY = 0
    
    local p = Instance.new("Frame")
    p.AnchorPoint = Vector2.new(0.5, 0.5)
    p.BorderSizePixel = 0
    p.BackgroundColor3 = COLORS.Confetti[math.random(1, #COLORS.Confetti)]
    p.Parent = gui
    
    local angle = math.rad(isLeft and math.random(-80, -10) or math.random(-170, -100))
    local force = math.random(600, 1800)
    local life = math.random(12, 24) / 10

    table.insert(activeParticles, {
      Type = "Confetti",
      Element = p,
      X = originX, Y = originY,
      VelocityX = math.cos(angle) * force,
      VelocityY = math.sin(angle) * force,
      Gravity = math.random(900, 1600),
      Drag = math.random(3, 6),
      Rotation = math.random(0, 360),
      RotationSpeed = math.random(-400, 400),
      TumbleTime = math.random() * math.pi,
      TumbleSpeed = math.random(8, 20),
      SizeX = math.random(10, 20), SizeY = math.random(10, 20),
      Life = life, MaxLife = life
    })
  end
  startUpdateLoop()
end

function ScreenEffects.DivineFlash(player)
  local gui = getScreenGui(player)
  
  -- 1. Center Shockwave (Expanding ring)
  local shockwave = Instance.new("Frame")
  shockwave.AnchorPoint = Vector2.new(0.5, 0.5)
  shockwave.Position = UDim2.new(0.5, 0, 0.5, 0)
  shockwave.Size = UDim2.new(0, 0, 0, 0) -- Starts at 0
  shockwave.SizeConstraint = Enum.SizeConstraint.RelativeXX
  shockwave.BackgroundColor3 = COLORS.Divine[1] -- White center
  shockwave.ZIndex = 9
  shockwave.Parent = gui

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(1, 0)
  corner.Parent = shockwave

  local aspect = Instance.new("UIAspectRatioConstraint")
  aspect.Parent = shockwave

  -- Tween shockwave explosively
  TweenService:Create(shockwave, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
    Size = UDim2.new(1.5, 0, 1.5, 0),
    BackgroundTransparency = 1
  }):Play()
  task.delay(0.5, function() shockwave:Destroy() end)

  -- 2. Main Screen Flash
  local flash = Instance.new("Frame")
  flash.Size = UDim2.new(1, 0, 1, 0)
  flash.BackgroundColor3 = Color3.new(1, 1, 1)
  flash.BackgroundTransparency = 1
  flash.ZIndex = 10
  flash.Parent = gui
  
  -- Snappy flash in
  TweenService:Create(flash, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 0.1}):Play()
  task.delay(0.05, function()
    -- Slow, satisfying fade out
    TweenService:Create(flash, TweenInfo.new(1.2, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
    task.delay(1.2, function() flash:Destroy() end)
  end)

  -- 3. Divine Rays
  local numRays = math.random(14, 18)
  for i = 1, numRays do
    if not canSpawnParticle() then
      break
    end
    local ray = Instance.new("Frame")
    ray.AnchorPoint = Vector2.new(0.5, 0.5)
    ray.Position = UDim2.new(0.5, 0, 0.5, 0)
    
    -- Randomize ray thickness for variety
    local thickness = math.random(2, 12) / 100 
    ray.Size = UDim2.new(thickness, 0, 0.1, 0)
    ray.BackgroundColor3 = COLORS.Divine[math.random(1, #COLORS.Divine)]
    ray.BackgroundTransparency = 0
    ray.BorderSizePixel = 0
    ray.Rotation = (360 / numRays) * i + math.random(-10, 10)
    ray.ZIndex = 8
    ray.Parent = gui

    -- Add a gradient so rays fade out at the edges like real light
    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 1),    -- Transparent top
      NumberSequenceKeypoint.new(0.4, 0),  -- Solid middle
      NumberSequenceKeypoint.new(0.6, 0),  -- Solid middle
      NumberSequenceKeypoint.new(1, 1)     -- Transparent bottom
    })
    gradient.Parent = ray
    
    local life = math.random(15, 25) / 10 -- 1.5s to 2.5s
    table.insert(activeParticles, {
      Type = "DivineRay",
      Element = ray,
      BaseSize = ray.Size,
      BaseScale = 0.1,
      TargetScale = math.random(15, 30) / 10, -- How far the ray shoots out (1.5x to 3x screen size)
      MaxOpacity = math.random(5, 8) / 10,
      RotationSpeed = math.random(-15, 15),
      Life = life, MaxLife = life
    })
  end
  
  startUpdateLoop()
end

function ScreenEffects.CameraPop(player, intensity)
  intensity = intensity or 12
  local camera = Workspace.CurrentCamera
  if not camera then return end

  local oldFov = camera.FieldOfView
  TweenService:Create(camera, TweenInfo.new(0.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {FieldOfView = oldFov + intensity}):Play()
  task.delay(0.1, function()
    TweenService:Create(camera, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {FieldOfView = oldFov}):Play()
  end)
end

function ScreenEffects.VignettePulse(player)
  local gui = getScreenGui(player)
  gui.DisplayOrder = 1000 -- Ensure it's on top of everything
  
  local color = randomVignetteColor()
  local targetTransparency = 0 -- Fully visible

  local vignette = Instance.new("ImageLabel")
  vignette.Name = "VignettePulse"
  vignette.BackgroundTransparency = 1
  -- Updated asset ID
  vignette.Image = "rbxassetid://18720640102"
  vignette.ImageColor3 = color
  vignette.ImageTransparency = 1
  vignette.Size = UDim2.fromScale(1, 1)
  vignette.Position = UDim2.fromScale(0.5, 0.5)
  vignette.AnchorPoint = Vector2.new(0.5, 0.5)
  vignette.ScaleType = Enum.ScaleType.Stretch
  vignette.ZIndex = 100
  vignette.Visible = true
  vignette.Parent = gui

  -- Animate in
  TweenService:Create(vignette, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
    ImageTransparency = targetTransparency,
  }):Play()

  -- Fade out
  task.delay(0.2, function()
    TweenService:Create(vignette, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
      ImageTransparency = 1,
    }):Play()
  end)

  -- Cleanup
  task.delay(1.1, function()
    if vignette.Parent then
      vignette:Destroy()
    end
  end)
end

function ScreenEffects.RewardEffect(player, config)
  config = config or {}
  if config.CameraPop ~= false then
    ScreenEffects.CameraPop(player, config.CameraIntensity)
  end
  if config.Vignette ~= false then
    ScreenEffects.VignettePulse(player)
  end
  if config.Confetti then
    ScreenEffects.ConfettiBurst(player, config.ConfettiAmount or 80)
  end
end

return ScreenEffects
