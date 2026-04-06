local InventoryController = {
  Name = "InventoryController",
  Priority = 10,
}

function InventoryController:Init(runtime)
  self._runtime = runtime
  self._config = runtime.Config
end

function InventoryController:Start()
  if self._started then
    return
  end
  self._started = true

  local renderUI, toggleInventory, syncDataAndRender, setupConnections

  local Players = game:GetService("Players")
  local CollectionService = game:GetService("CollectionService")
  local ReplicatedStorage = game:GetService("ReplicatedStorage")
  local StarterGui = game:GetService("StarterGui")
  local UserInputService = game:GetService("UserInputService")
  local TweenService = game:GetService("TweenService")
  local RunService = game:GetService("RunService")
  local carryRemote = self._runtime.Remotes:GetCarryAnimalRemote()
  local GameConfig = self._config
  local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
  local ViewportHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ViewportHelper"))

  local player = Players.LocalPlayer
  local pGui = player:WaitForChild("PlayerGui")
  local backpack = player:WaitForChild("Backpack")

  local inventoryLayoutRemote = nil

  local function getInventoryLayoutRemote()
    if inventoryLayoutRemote and inventoryLayoutRemote.Parent then
      return inventoryLayoutRemote
    end

    local remotesFolder = ReplicatedStorage:FindFirstChild(GameConfig.Remotes.FolderName)
    if remotesFolder == nil then
      return nil
    end

    local remote = remotesFolder:FindFirstChild(GameConfig.Remotes.InventoryLayoutEvent)
    if remote and remote:IsA("RemoteEvent") then
      inventoryLayoutRemote = remote
      return remote
    end

    return nil
  end

  -----------------------------------------------------------
  -- 1. Configuration & Styling
  -----------------------------------------------------------
  local CONFIG = {
    HotbarSlots = GameConfig.Inventory.HotbarSlots or 10,
    TweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),

    -- Cartoony Simulator Style
    Color_SlotBg       = Color3.fromRGB(0, 170, 255),    -- Default bright blue
    Color_SlotBgBottom = Color3.fromRGB(0, 100, 200),    -- Default darker bottom
    Color_SlotHover    = Color3.fromRGB(50, 200, 255),   -- Brighter blue on hover
    Color_SlotEquipped = Color3.fromRGB(255, 170, 0),    -- Bright orange/yellow for equipped background
    Color_EquipBorder  = Color3.fromRGB(255, 255, 0),    -- Bright yellow border when equipped
    Color_Outline      = Color3.fromRGB(255, 255, 255),
    Color_Stroke       = Color3.fromRGB(0, 0, 0),        -- Pitch black thick strokes
    Stroke_Thickness   = 4,                              -- Universal thick borders

    -- Simulator Rarity Settings (Top and Bottom colors for gradients)
    RaritySettings = GameConfig.RaritySettings,

    HotbarHeightScale  = 0.11,
    HotbarWidthScale   = 0.8,
    InventorySizeScale = Vector2.new(0.7, 0.6),

    LongPressDuration  = 0.3,
    EquipCooldown      = 0.25,
  }

  local animalsFolder = ReplicatedStorage:WaitForChild("Animals", 5)
  local animalImages = animalsFolder and animalsFolder:WaitForChild("Images", 5)

  local function getAnimalImage(name)
    if not animalImages then return nil end
    local decal = animalImages:FindFirstChild(name)
    if decal and decal:IsA("Decal") then
      return decal.Texture
    end
    return nil
  end

  local function getMutatedName(tool)
    local name = tool.Name
    local mutations = {}
    if tool:GetAttribute("IsGold") then table.insert(mutations, "Gold") end
    if tool:GetAttribute("IsSoaked") then table.insert(mutations, "Soaked") end
    if tool:GetAttribute("IsMalevolent") then table.insert(mutations, "Malevolent") end
    if tool:GetAttribute("IsTwistborn") then table.insert(mutations, "Twistborn") end
    if tool:GetAttribute("IsAlien") then table.insert(mutations, "Alien") end
    
    if #mutations > 0 then
      return "[" .. table.concat(mutations, ", ") .. "] " .. name
    end
    return name
  end

  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

  -----------------------------------------------------------
  -- 2. Custom Equip/Unequip Logic for Fake Tools
  -----------------------------------------------------------
  local currentFakeToolAnimTrack = nil
  local lastEquipTime = 0
  local fakeToolActionRemote = nil
  local inventoryLayoutRemote = nil

  local function getFakeToolActionRemote()
    return self._runtime.Remotes:GetFakeToolRemote()
  end

  local function getInventoryLayoutRemote()
    return self._runtime.Remotes:GetInventoryLayoutRemote()
  end

  local function unequipEverything(char, human)
    if human and human.Parent then
      human:UnequipTools()
    end

    for _, child in ipairs(char:GetChildren()) do
      if child:IsA("Configuration") then
        local actionRemote = getFakeToolActionRemote()
        if actionRemote then
          pcall(function()
            actionRemote:FireServer("Unequip", child)
          end)
        end

        local unequipRemote = child:FindFirstChild("Unequipped")
        if unequipRemote and unequipRemote:IsA("RemoteEvent") then
          pcall(function() unequipRemote:FireServer() end)
        end
      end
    end
  end

  local function equipFakeTool(fakeConfig, char, human)
    local actionRemote = getFakeToolActionRemote()
    if actionRemote then
      pcall(function()
        actionRemote:FireServer("Equip", fakeConfig)
      end)
    end

    local equipRemote = fakeConfig:FindFirstChild("Equipped")
    if equipRemote and equipRemote:IsA("RemoteEvent") then
      pcall(function()
        equipRemote:FireServer()
      end)
    end
  end

  local function toggleTool(toolOrConfig)
    if player:GetAttribute("CarryingAnimal") then
      return
    end
    if tick() - lastEquipTime < CONFIG.EquipCooldown then return end
    lastEquipTime = tick()

    local char = player.Character
    local human = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not human or human.Health <= 0 then return end

    local isCurrentlyEquipped = toolOrConfig.Parent == char

    unequipEverything(char, human)

    if not isCurrentlyEquipped then
      if toolOrConfig:IsA("Tool") then
        human:EquipTool(toolOrConfig)
      elseif toolOrConfig:IsA("Configuration") then
        equipFakeTool(toolOrConfig, char, human)
      end
    end
  end

  -----------------------------------------------------------
  -- 3. ViewportFrame Builder & Rarity Helper
  -----------------------------------------------------------
  local function getRarityInfo(tool)
    if not tool then return nil end
    local rarity = tool:GetAttribute("Rarity")
    if rarity and CONFIG.RaritySettings[rarity] then
      return CONFIG.RaritySettings[rarity]
    end
    return nil
  end

  local function buildViewport(tool, parentFrame)
    return ViewportHelper.BuildViewport(tool, parentFrame, {
      OutlineColor = CONFIG.Color_Outline
    })
  end

  -----------------------------------------------------------
  -- 4. UI Structure (Styled to match Image 1)
  -----------------------------------------------------------
  local screenGui = Instance.new("ScreenGui")
  screenGui.Name = "ModernStylizedInventory"
  screenGui.ResetOnSpawn = false
  screenGui.IgnoreGuiInset = true
  screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  screenGui.Parent = pGui

  local dragGui = Instance.new("ScreenGui")
  dragGui.Name = "DragGui"
  dragGui.ResetOnSpawn = false
  dragGui.IgnoreGuiInset = true
  dragGui.DisplayOrder = 999 
  dragGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  dragGui.Parent = pGui

  local hotbarFrame = Instance.new("Frame")
  hotbarFrame.Name = "Hotbar"
  hotbarFrame.Size = UDim2.fromScale(CONFIG.HotbarWidthScale, CONFIG.HotbarHeightScale)
  hotbarFrame.Position = UDim2.fromScale((1 - CONFIG.HotbarWidthScale)/2, 0.87)
  hotbarFrame.BackgroundTransparency = 1
  hotbarFrame.Parent = screenGui

  local hotbarLayout = Instance.new("UIListLayout")
  hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
  hotbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
  hotbarLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
  hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
  hotbarLayout.Padding = UDim.new(0, 10)
  hotbarLayout.Parent = hotbarFrame

  local invMenu = Instance.new("CanvasGroup")
  invMenu.Name = "InventoryMenu"
  invMenu.Size = UDim2.fromScale(CONFIG.InventorySizeScale.X, CONFIG.InventorySizeScale.Y)
  -- Start below screen for bottom-to-top slide
  invMenu.Position = UDim2.fromScale((1 - CONFIG.InventorySizeScale.X)/2, 1.2)
  -- Clean transparent simulator menu style
  invMenu.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
  invMenu.BackgroundTransparency = 0.5 
  invMenu.GroupTransparency = 1
  invMenu.Visible = false
  invMenu.Parent = screenGui

  local invCorner = Instance.new("UICorner")
  invCorner.CornerRadius = UDim.new(0, 8) -- Cleaner, sharper rounding
  invCorner.Parent = invMenu

  local invMenuStroke = Instance.new("UIStroke")
  invMenuStroke.Color = CONFIG.Color_Stroke
  invMenuStroke.Thickness = 2 -- Thick outer border
  invMenuStroke.Parent = invMenu

  local topBar = Instance.new("Frame")
  topBar.Name = "TopBar"
  topBar.Size = UDim2.new(1, -60, 0, 45)
  topBar.Position = UDim2.new(0, 30, 0, 20)
  topBar.BackgroundTransparency = 1
  topBar.Parent = invMenu

  local searchBox = Instance.new("TextBox")
  searchBox.Name = "SearchBox"
  searchBox.Size = UDim2.new(0.65, 0, 1, 0)
  searchBox.Position = UDim2.new(0, 0, 0, 0)
  searchBox.BackgroundColor3 = Color3.fromRGB(0, 0, 0) -- Dark transparent background
  searchBox.BackgroundTransparency = 0.6
  searchBox.Text = ""
  searchBox.PlaceholderText = "Search items..."
  searchBox.PlaceholderColor3 = Color3.fromRGB(200, 200, 200)
  searchBox.TextColor3 = Color3.fromRGB(255, 255, 255)
  searchBox.Font = Enum.Font.FredokaOne
  searchBox.TextSize = 22
  searchBox.ClearTextOnFocus = false
  searchBox.Parent = topBar

  local searchCorner = Instance.new("UICorner")
  searchCorner.CornerRadius = UDim.new(0, 6)
  searchCorner.Parent = searchBox

  local searchStroke = Instance.new("UIStroke")
  searchStroke.Color = CONFIG.Color_Stroke
  searchStroke.Thickness = 1.2
  searchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  searchStroke.Parent = searchBox

  local searchPadding = Instance.new("UIPadding")
  searchPadding.PaddingLeft = UDim.new(0, 15)
  searchPadding.Parent = searchBox

  local sortBtn = Instance.new("TextButton")
  sortBtn.Name = "SortButton"
  sortBtn.Size = UDim2.new(0.3, 0, 1, 0)
  sortBtn.Position = UDim2.new(1, 0, 0, 0)
  sortBtn.AnchorPoint = Vector2.new(1, 0)
  sortBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0) -- Dark transparent background
  sortBtn.BackgroundTransparency = 0.6
  sortBtn.Text = "Sort: Default"
  sortBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
  sortBtn.Font = Enum.Font.FredokaOne
  sortBtn.TextSize = 20
  sortBtn.AutoButtonColor = false
  sortBtn.Parent = topBar

  local sortCorner = Instance.new("UICorner")
  sortCorner.CornerRadius = UDim.new(0, 6)
  sortCorner.Parent = sortBtn

  local sortStroke = Instance.new("UIStroke")
  sortStroke.Color = CONFIG.Color_Stroke
  sortStroke.Thickness = 1.3
  sortStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
  sortStroke.Parent = sortBtn

  local sortTextStroke = Instance.new("UIStroke")
  sortTextStroke.Color = CONFIG.Color_Stroke
  sortTextStroke.Thickness = 1
  sortTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
  sortTextStroke.Parent = sortBtn

  local SCROLLBAR_THICKNESS = 10

  local invScrollingWrapper = Instance.new("CanvasGroup")
  invScrollingWrapper.Name = "ScrollingWrapper"
  invScrollingWrapper.Size = UDim2.new(1, -60, 1, -100)
  invScrollingWrapper.Position = UDim2.new(0, 30, 0, 85)
  invScrollingWrapper.BackgroundTransparency = 1
  invScrollingWrapper.Parent = invMenu

  local invScrolling = Instance.new("ScrollingFrame")
  invScrolling.Size = UDim2.fromScale(1, 1)
  invScrolling.Position = UDim2.fromScale(0, 0)
  invScrolling.BackgroundTransparency = 1
  invScrolling.ScrollBarThickness = SCROLLBAR_THICKNESS
  invScrolling.ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255) 
  invScrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
  invScrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
  invScrolling.ScrollingEnabled = true
  invScrolling.Parent = invScrollingWrapper

  local scrollPadding = Instance.new("UIPadding")
  scrollPadding.PaddingTop    = UDim.new(0, 15)
  scrollPadding.PaddingBottom = UDim.new(0, 6)
  scrollPadding.PaddingLeft   = UDim.new(0, 8)
  scrollPadding.PaddingRight  = UDim.new(0, SCROLLBAR_THICKNESS + 8)
  scrollPadding.Parent = invScrolling

  local invGrid = Instance.new("UIGridLayout")
  invGrid.SortOrder = Enum.SortOrder.LayoutOrder
  invGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
  invGrid.Parent = invScrolling

  local function updateGrid()
    local totalPaddingH = 6 + SCROLLBAR_THICKNESS + 8
    local width = invScrolling.AbsoluteSize.X - totalPaddingH
    if width <= 0 then return end
    local columns = 5
    local padding = 12
    local cellSize = math.floor((width - (padding * (columns - 1))) / columns)
    invGrid.CellSize = UDim2.fromOffset(cellSize, cellSize)
    invGrid.CellPadding = UDim2.fromOffset(padding, padding)
  end
  invScrolling:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGrid)
  task.defer(updateGrid)

  -----------------------------------------------------------
  -- 5. Drag & Long-Press State
  -----------------------------------------------------------
  local slotsMapping      = {}
  local slotContents      = {}
  local inventoryOpen     = false
  local isDragging        = false
  local draggedObjectData = nil
  local dragVisualClone   = nil
  local lastDropTime      = 0

  local longPressThread   = nil
  local longPressPending  = false
  local longPressSlotData = nil
  local layoutSyncPending = false

  local function pushSlotLayoutToServer()
    local remote = getInventoryLayoutRemote()
    if remote == nil then return end

    local payload = {}
    for slotIndex, tool in pairs(slotContents) do
      if tool and (tool:IsA("Tool") or tool:IsA("Configuration")) then
        table.insert(payload, { slot = slotIndex, instance = tool })
      end
    end

    table.sort(payload, function(a, b) return a.slot < b.slot end)
    remote:FireServer(payload)
  end

  local function queueLayoutSync()
    if layoutSyncPending then return end
    layoutSyncPending = true
    task.delay(0.2, function()
      layoutSyncPending = false
      pushSlotLayoutToServer()
    end)
  end

  local function cancelLongPress()
    longPressPending  = false
    longPressSlotData = nil
    if longPressThread then
      pcall(task.cancel, longPressThread)
      longPressThread = nil
    end
  end

  local function beginDrag(slotData, inputPos)
    if player:GetAttribute("CarryingAnimal") then
      return
    end
    longPressThread   = nil
    longPressPending  = false
    longPressSlotData = nil

    if isDragging or not slotContents[slotData.Index] then return end

    isDragging = true
    draggedObjectData = slotData
    invScrolling.ScrollingEnabled = false

    local slot = slotData.Button
    local slotSize = slot.AbsoluteSize
    local tool = slotContents[slotData.Index]

    local ghost = Instance.new("Frame")
    ghost.Name = "DragGhost"
    ghost.Size = UDim2.fromOffset(slotSize.X, slotSize.Y)
    ghost.AnchorPoint = Vector2.new(0.5, 0.5)
    ghost.Position = UDim2.fromOffset(inputPos.X, inputPos.Y)
    ghost.BackgroundColor3 = slot.BackgroundColor3
    ghost.BorderSizePixel = 0
    ghost.Parent = dragGui 

    local ghostCorner = Instance.new("UICorner")
    ghostCorner.CornerRadius = UDim.new(0, 0)
    ghostCorner.Parent = ghost

    local ghostStroke = Instance.new("UIStroke")
    ghostStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    ghostStroke.Parent = ghost

    local rInfo = getRarityInfo(tool)
    ghostStroke.Thickness = CONFIG.Stroke_Thickness
    ghostStroke.Color = CONFIG.Color_Stroke

    if rInfo then
      ghost.BackgroundColor3 = rInfo.Top
      ghost.BackgroundTransparency = 0.6
    else
      ghost.BackgroundColor3 = Color3.new(0, 0, 0)
      ghost.BackgroundTransparency = 0.85
    end

    if tool then
      local animalImage = getAnimalImage(tool.Name)
      local displayItem = nil
      
      if animalImage then
        local img = Instance.new("ImageLabel")
        img.Name = "ItemImage"
        img.Size = UDim2.fromScale(0.8, 0.8)
        img.Position = UDim2.fromScale(0.5, 0.5)
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.BackgroundTransparency = 1
        img.Image = animalImage
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = ghost
        displayItem = img
      else
        displayItem = buildViewport(tool, ghost)
      end

      if displayItem then
        local ghostName = slotData.NameLabel:Clone()
        ghostName.Text = getMutatedName(tool)
        ghostName.Parent = ghost
      else
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Text = getMutatedName(tool)
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.Font = Enum.Font.FredokaOne
        lbl.TextScaled = true
        lbl.TextWrapped = true
        
        local textSt = Instance.new("UIStroke")
        textSt.Color = Color3.new(0,0,0)
        textSt.Thickness = 1
        textSt.Parent = lbl

        local tc = Instance.new("UITextSizeConstraint")
        tc.MaxTextSize = 16
        tc.MinTextSize = 8
        tc.Parent = lbl
        lbl.Parent = ghost
      end
    end

    dragVisualClone = ghost

    slot.BackgroundTransparency = 1 -- fully transparent while dragging
    slotData.Stroke.Transparency = 0.6
    slotData.NameLabel.TextTransparency = 0.5
    if slotData.NameLabel:FindFirstChildOfClass("UIStroke") then
      slotData.NameLabel:FindFirstChildOfClass("UIStroke").Transparency = 0.5
    end

    for _, child in ipairs(slot:GetChildren()) do
      if child:IsA("ViewportFrame") then 
        child.ImageTransparency = 0.5 
      elseif child:IsA("ImageLabel") and child.Name == "ItemImage" then
        child.ImageTransparency = 0.5
      end
    end
    slot.TextTransparency = 0.5
  end

  -----------------------------------------------------------
  -- 6. Slot Dynamic Scaling & Rendering
  -----------------------------------------------------------
  local function createSlot(isHotbar, index)
    local placeholder = Instance.new("Frame")
    placeholder.Name = "Slot_" .. index
    placeholder.BackgroundTransparency = 1
    placeholder.LayoutOrder = index
    if isHotbar then
      placeholder.Size = UDim2.fromScale(1, 1)
      local aspect = Instance.new("UIAspectRatioConstraint")
      aspect.AspectRatio = 1
      aspect.DominantAxis = Enum.DominantAxis.Height
      aspect.Parent = placeholder
    end

    local slot = Instance.new("TextButton")
    slot.Size = UDim2.fromScale(1, 1)
    slot.AnchorPoint = Vector2.new(0.5, 0.5)
    slot.Position = UDim2.fromScale(0.5, 0.5)
    slot.BackgroundColor3 = Color3.new(0, 0, 0)
    slot.BackgroundTransparency = 0.85 -- transparent clean look
    slot.Text = ""
    slot.AutoButtonColor = false
    slot.ZIndex = 1
    slot.Parent = placeholder

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 0) -- Match the sharp look in the image
    corner.Parent = slot

    local stroke = Instance.new("UIStroke")
    stroke.Color = CONFIG.Color_Stroke
    stroke.Thickness = 3 -- Thick simulator-style borders
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = slot

    local itemNameLabel = Instance.new("TextLabel")
    itemNameLabel.Name = "ItemName"
    itemNameLabel.Size = UDim2.fromScale(1, 0.28)
    itemNameLabel.Position = UDim2.fromScale(0.5, 0.98)
    itemNameLabel.AnchorPoint = Vector2.new(0.5, 1)
    itemNameLabel.BackgroundTransparency = 1
    itemNameLabel.Font = Enum.Font.FredokaOne
    itemNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    itemNameLabel.TextScaled = true
    itemNameLabel.Visible = false
    itemNameLabel.ZIndex = 3
    itemNameLabel.Parent = slot

    local nameStroke = Instance.new("UIStroke")
    nameStroke.Color = Color3.fromRGB(0, 0, 0)
    nameStroke.Thickness = 1
    nameStroke.Parent = itemNameLabel

    local nameConstraint = Instance.new("UITextSizeConstraint")
    nameConstraint.MaxTextSize = 16
    nameConstraint.MinTextSize = 6
    nameConstraint.Parent = itemNameLabel

    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = slot

    -- Animal Stats Container
    local statsContainer = Instance.new("Frame")
    statsContainer.Name = "StatsContainer"
    statsContainer.Size = UDim2.fromScale(1, 0.4)
    -- Fix Overlap: Shift it down to 0.25 if it's a hotbar slot so it clears the number label
    statsContainer.Position = isHotbar and UDim2.fromScale(0.5, 0.25) or UDim2.fromScale(0.5, 0.05)
    statsContainer.AnchorPoint = Vector2.new(0.5, 0)
    statsContainer.BackgroundTransparency = 1
    statsContainer.Visible = false
    statsContainer.ZIndex = 3
    statsContainer.Parent = slot

    local statsLayout = Instance.new("UIListLayout")
    statsLayout.FillDirection = Enum.FillDirection.Vertical
    statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    statsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    statsLayout.Padding = UDim.new(0, 2)
    statsLayout.Parent = statsContainer

    local function createStatLabel(name, color)
      local lbl = Instance.new("TextLabel")
      lbl.Name = name
      lbl.Size = UDim2.new(1, 0, 0, 14)
      lbl.BackgroundTransparency = 1
      lbl.Font = Enum.Font.FredokaOne
      lbl.Text = ""
      lbl.TextColor3 = color
      lbl.TextXAlignment = Enum.TextXAlignment.Left
      lbl.TextScaled = true
      
      local s = Instance.new("UIStroke")
      s.Color = Color3.fromRGB(0, 0, 0)
      s.Thickness = 1
      s.Parent = lbl
      
      local constraint = Instance.new("UITextSizeConstraint")
      constraint.MaxTextSize = 14
      constraint.MinTextSize = 8
      constraint.Parent = lbl
      
      lbl.Parent = statsContainer
      return lbl
    end

    local revenueLabel = createStatLabel("RevenueLabel", Color3.fromRGB(100, 255, 100))
    local costLabel = createStatLabel("CostLabel", Color3.fromRGB(255, 220, 50))

    local slotData = {
      Placeholder  = placeholder,
      Button       = slot,
      Stroke       = stroke,
      NameLabel    = itemNameLabel,
      StatsContainer = statsContainer,
      RevenueLabel = revenueLabel,
      CostLabel    = costLabel,
      HasRarity    = false,
      BaseColor    = Color3.new(0, 0, 0),
      UIScale      = uiScale,
      IsHotbar     = isHotbar,
      Index        = index,
      RenderedTool = nil,
      Equipped     = false
    }

    if isHotbar then
      local label = Instance.new("TextLabel")
      label.Size = UDim2.fromScale(0.25, 0.25)
      label.Position = UDim2.new(0, 4, 0, 4) -- Tighter to top left
      label.AnchorPoint = Vector2.new(0, 0)
      label.BackgroundTransparency = 1
      label.Text = (index == 10) and "0" or tostring(index)
      label.TextColor3 = Color3.fromRGB(255, 255, 255)
      label.Font = Enum.Font.FredokaOne
      label.TextXAlignment = Enum.TextXAlignment.Left
      label.TextYAlignment = Enum.TextYAlignment.Top
      label.TextScaled = true
      label.ZIndex = 4
      
      local ls = Instance.new("UIStroke")
      ls.Color = Color3.fromRGB(0, 0, 0)
      ls.Thickness = 1
      ls.Parent = label
      
      label.Parent = slot
    end

    local HoverTweenInfoIn = TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
    local HoverTweenInfoOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    slot.MouseEnter:Connect(function()
      TweenService:Create(slot, HoverTweenInfoIn, { Rotation = (math.random() - 0.5) * 6 }):Play()
      TweenService:Create(uiScale, HoverTweenInfoIn, {Scale = 1.15}):Play()
    end)

    slot.MouseLeave:Connect(function()
      TweenService:Create(slot, HoverTweenInfoOut, { Rotation = 0 }):Play()
      TweenService:Create(uiScale, HoverTweenInfoOut, {Scale = 1}):Play()
    end)

    slot.MouseButton1Down:Connect(function()
      TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.9}):Play()
    end)

    slot.MouseButton1Up:Connect(function()
      TweenService:Create(uiScale, HoverTweenInfoIn, {Scale = 1.15}):Play()
    end)

    slot.MouseButton1Click:Connect(function()
      if tick() - lastDropTime < 0.15 then return end
      local currentTool = slotContents[index]
      if currentTool and not isDragging then
        toggleTool(currentTool)
      end
    end)

    slot.InputBegan:Connect(function(input)
      local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
      local isTouch = input.UserInputType == Enum.UserInputType.Touch

      if not (isMouse or isTouch) then return end
      if not inventoryOpen or not slotContents[index] then return end

      if isMouse then
        beginDrag(slotData, input.Position)
      elseif isTouch then
        cancelLongPress()

        longPressPending  = true
        longPressSlotData = slotData
        local startPos    = input.Position

        local moveConn
        moveConn = UserInputService.InputChanged:Connect(function(moved)
          if moved ~= input then return end
          if (moved.Position - startPos).Magnitude > 12 then
            cancelLongPress()
            moveConn:Disconnect()
          end
        end)

        longPressThread = task.delay(CONFIG.LongPressDuration, function()
          if longPressPending and longPressSlotData == slotData then
            moveConn:Disconnect()
            beginDrag(slotData, input.Position)
          end
        end)
      end
    end)

    table.insert(slotsMapping, slotData)
    return slotData
  end

  for i = 1, CONFIG.HotbarSlots do 
    createSlot(true, i).Placeholder.Parent = hotbarFrame 
  end

  local function ensureCapacity()
    local maxIndex = 10 
    for i, tool in pairs(slotContents) do
      if tool and i > maxIndex then
        maxIndex = i
      end
    end

    local inventoryUsed = math.max(0, maxIndex - 10)
    local requiredInventorySlots = math.ceil(inventoryUsed / 5) * 5 + 5
    local targetTotalSlots = 10 + requiredInventorySlots

    while #slotsMapping < targetTotalSlots do
      local nextIdx = #slotsMapping + 1
      createSlot(false, nextIdx).Placeholder.Parent = invScrolling
    end

    while #slotsMapping > targetTotalSlots do
      local lastIdx = #slotsMapping
      if slotsMapping[lastIdx] then
        slotsMapping[lastIdx].Placeholder:Destroy()
        table.remove(slotsMapping, lastIdx)
        slotContents[lastIdx] = nil
      end
    end
  end

  local function renderUI()
    for i, slotData in ipairs(slotsMapping) do
      local tool = slotContents[i]

      if slotData.RenderedTool ~= tool then
        slotData.RenderedTool = tool

        for _, child in ipairs(slotData.Button:GetChildren()) do
          if child:IsA("ViewportFrame") then
            ViewportHelper.DestroyViewport(child, true)
          elseif child:IsA("ImageLabel") or (child:IsA("UITextSizeConstraint") and child.Name ~= "ItemName") then
            child:Destroy()
          end
        end

        if tool then
          local rInfo = getRarityInfo(tool)
          slotData.HasRarity = rInfo ~= nil

          if rInfo then
            slotData.BaseColor = rInfo.Top
          else
            slotData.BaseColor = Color3.new(0, 0, 0)
          end

          slotData.NameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

          local animalImage = getAnimalImage(tool.Name)
          local displayItem = nil
          
          if animalImage then
            local img = Instance.new("ImageLabel")
            img.Name = "ItemImage"
            img.Size = UDim2.fromScale(0.8, 0.8)
            img.Position = UDim2.fromScale(0.5, 0.45)
            img.AnchorPoint = Vector2.new(0.5, 0.5)
            img.BackgroundTransparency = 1
            img.Image = animalImage
            img.ScaleType = Enum.ScaleType.Fit
            img.Parent = slotData.Button
            displayItem = img
          else
            displayItem = buildViewport(tool, slotData.Button)
          end

          if displayItem then
            slotData.Button.Text = ""
            slotData.NameLabel.Text = getMutatedName(tool)
            slotData.NameLabel.Visible = true
          else
            slotData.Button.Text = getMutatedName(tool)
            slotData.Button.TextColor3 = Color3.fromRGB(255, 255, 255)
            slotData.Button.Font = Enum.Font.FredokaOne
            slotData.Button.TextScaled = true
            slotData.Button.TextWrapped = true

            local textStroke = Instance.new("UIStroke")
            textStroke.Thickness = 1
            textStroke.Parent = slotData.Button

            local sizeConstraint = Instance.new("UITextSizeConstraint")
            sizeConstraint.MaxTextSize = 16
            sizeConstraint.MinTextSize = 8
            sizeConstraint.Parent = slotData.Button
            slotData.NameLabel.Visible = false
          end

          if CollectionService:HasTag(tool, "Animal") then
              local revenue = tool:GetAttribute("Revenue") or 0
              local cost = tool:GetAttribute("Cost") or 0

              slotData.RevenueLabel.Text = "Rev: " .. NumberFormatter:Format(revenue, "Letters") .. "/s"
              slotData.CostLabel.Text = "Cost: " .. NumberFormatter:Format(cost, "Letters")

              if slotData.IsHotbar then
                  slotData.RevenueLabel.Visible = false
                  slotData.CostLabel.Visible = false
              else
                  slotData.RevenueLabel.Visible = true
                  slotData.CostLabel.Visible = true
              end

              slotData.StatsContainer.Visible = true
          else
              slotData.StatsContainer.Visible = false
          end
        else
          slotData.HasRarity = false
          slotData.BaseColor = Color3.new(0, 0, 0)

          slotData.Button.Text = ""
          slotData.NameLabel.Visible = false
          slotData.StatsContainer.Visible = false
        end
      end

      -- Check equipped state dynamically every render to handle visual pops
      local isEquipped = tool and (tool.Parent == player.Character)
      if isEquipped ~= slotData.Equipped then
          slotData.Equipped = isEquipped
          
          -- Pop out effect for Equipped Tools
          local tweenTargetY = isEquipped and 0.35 or 0.5 
          TweenService:Create(slotData.Button, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
              Position = UDim2.fromScale(0.5, tweenTargetY)
          }):Play()
      end

      -- Apply colors independently from the equipped status check so swapped slots update correctly!
      if isEquipped then
          slotData.Stroke.Color = CONFIG.Color_EquipBorder
          slotData.Button.BackgroundColor3 = CONFIG.Color_SlotEquipped
          slotData.Button.BackgroundTransparency = 0.5
      else
          slotData.Stroke.Color = CONFIG.Color_Stroke
          if slotData.HasRarity then
             slotData.Button.BackgroundColor3 = slotData.BaseColor
             slotData.Button.BackgroundTransparency = 0.6
          else
             slotData.Button.BackgroundColor3 = Color3.new(0, 0, 0)
             slotData.Button.BackgroundTransparency = 0.85
          end
      end

      slotData.Button.TextTransparency = 0
      slotData.Stroke.Transparency = 0

      local query = searchBox.Text:lower()  
      local matchesSearch = true
      if query ~= "" and tool and not tool.Name:lower():find(query) then
        matchesSearch = false
      end

      if slotData.IsHotbar then
        if tool then
          slotData.Placeholder.Visible = true
        else
          slotData.Placeholder.Visible = inventoryOpen
        end
      else
        if query ~= "" then
          slotData.Placeholder.Visible = tool ~= nil and matchesSearch
        else
          if tool then
            slotData.Placeholder.Visible = true
          else
            slotData.Placeholder.Visible = true
          end
        end
      end
    end
  end

  local RarityValues = {
    Devine = 6, Mythical = 5, Legendary = 4, Rare = 3, Uncommon = 2, Common = 1
  }

  local function getToolSortValue(tool)
    local isFake = tool:IsA("Configuration") and 1 or 0
    local rarityStr = tool:GetAttribute("Rarity") or "Common"
    local rarityVal = RarityValues[rarityStr] or 0
    return isFake, rarityVal, tool.Name
  end

  local function syncDataAndRender()
    local allTools = {}
    local currentOwned = {}
    local bp  = player:FindFirstChild("Backpack")
    local char = player.Character

    if bp then 
      for _, t in ipairs(bp:GetChildren()) do 
        if t:IsA("Tool") or t:IsA("Configuration") then 
          table.insert(allTools, t) 
          currentOwned[t] = true
        end 
      end 
    end
    if char then 
      for _, t in ipairs(char:GetChildren()) do 
        if t:IsA("Tool") or t:IsA("Configuration") then 
          table.insert(allTools, t) 
          currentOwned[t] = true
        end 
      end 
    end

    for i, tool in pairs(slotContents) do
      if tool and not currentOwned[tool] then
        slotContents[i] = nil
      end
    end

    table.sort(allTools, function(a, b)
      local fakeA, rarA, nameA = getToolSortValue(a)
      local fakeB, rarB, nameB = getToolSortValue(b)

      if fakeA ~= fakeB then return fakeA > fakeB
      elseif rarA ~= rarB then return rarA > rarB
      else return nameA < nameB end
    end)

    for _, tool in ipairs(allTools) do
      local found = false
      for i, existingTool in pairs(slotContents) do 
        if existingTool == tool then found = true; break end 
      end
      if not found then
        local targetIdx = 1
        while slotContents[targetIdx] ~= nil do
          targetIdx = targetIdx + 1
        end
        slotContents[targetIdx] = tool
      end
    end

    ensureCapacity()
    renderUI()
    queueLayoutSync()
  end

  -- Server can request slot placement for newly granted animals.
  if carryRemote then
    carryRemote.OnClientEvent:Connect(function(action, payload)
      if action ~= "ForceHotbarSlot" then
        return
      end
      if type(payload) ~= "table" then
        return
      end

      local tool = payload.instance
      local slot = tonumber(payload.slot)
      if tool == nil or slot == nil then
        return
      end
      if slot < 1 or slot > CONFIG.HotbarSlots then
        return
      end

      -- Shift whatever is currently in that hotbar slot to the next available slot.
      local existing = slotContents[slot]
      if existing and existing ~= tool then
        local targetIdx = 1
        while slotContents[targetIdx] ~= nil do
          targetIdx += 1
        end
        slotContents[targetIdx] = existing
      end

      -- Remove tool from any other slot so we don't duplicate it.
      for i, t in pairs(slotContents) do
        if t == tool and i ~= slot then
          slotContents[i] = nil
        end
      end

      slotContents[slot] = tool
      ensureCapacity()
      renderUI()
      queueLayoutSync()
    end)
  end

  -----------------------------------------------------------
  -- 7. Drag Tracking & Drop
  -----------------------------------------------------------
  UserInputService.InputChanged:Connect(function(input)
    if isDragging and dragVisualClone then
      if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        dragVisualClone.Position = UDim2.fromOffset(input.Position.X, input.Position.Y)
      end
    end
  end)

  UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch and longPressPending then
      cancelLongPress()
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1
      or input.UserInputType == Enum.UserInputType.Touch then
      if not isDragging then return end

      isDragging = false
      lastDropTime = tick()
      invScrolling.ScrollingEnabled = true

      local dropX, dropY = input.Position.X, input.Position.Y
      local targetSlotData = nil

      for _, slotData in ipairs(slotsMapping) do
        if slotData.Placeholder.Visible then
          local btn = slotData.Button
          if btn.AbsolutePosition.X - 10 <= dropX
            and (btn.AbsolutePosition.X + btn.AbsoluteSize.X + 10) >= dropX
            and btn.AbsolutePosition.Y - 10 <= dropY
            and (btn.AbsolutePosition.Y + btn.AbsoluteSize.Y + 10) >= dropY then
            targetSlotData = slotData
            break
          end
        end
      end

      if not targetSlotData and invMenu.Visible then
        local scX, scY = invScrollingWrapper.AbsolutePosition.X, invScrollingWrapper.AbsolutePosition.Y
        local scW, scH = invScrollingWrapper.AbsoluteSize.X, invScrollingWrapper.AbsoluteSize.Y
        if dropX >= scX and dropX <= scX + scW and dropY >= scY and dropY <= scY + scH then
          local highestOccupied = CONFIG.HotbarSlots
          for i, tool in pairs(slotContents) do
            if tool and i > CONFIG.HotbarSlots and i ~= draggedObjectData.Index then
              if i > highestOccupied then highestOccupied = i end
            end
          end
          local nextEmptyIdx = highestOccupied + 1
          for _, slotData in ipairs(slotsMapping) do
            if slotData.Index == nextEmptyIdx then
              targetSlotData = slotData
              break
            end
          end
        end
      end

      if targetSlotData and draggedObjectData then
        local tIndex = targetSlotData.Index
        local dIndex = draggedObjectData.Index
        local draggedTool = slotContents[dIndex]

        if tIndex > CONFIG.HotbarSlots and draggedTool and draggedTool.Parent == player.Character then
          local human = player.Character:FindFirstChildOfClass("Humanoid")
          if human then unequipEverything(player.Character, human) end
        end

        if tIndex > CONFIG.HotbarSlots and not slotContents[tIndex] then
          local highestOccupied = CONFIG.HotbarSlots
          for i, tool in pairs(slotContents) do
            if tool and i > CONFIG.HotbarSlots and i ~= dIndex then
              if i > highestOccupied then highestOccupied = i end
            end
          end

          local allowedMax = highestOccupied + 1
          if tIndex > allowedMax then tIndex = allowedMax end
        end

        local temp = slotContents[tIndex]
        slotContents[tIndex] = slotContents[dIndex]
        slotContents[dIndex] = temp

        local popTweenIn = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0)
        
        for _, sd in ipairs(slotsMapping) do
          if sd.Index == tIndex or sd.Index == dIndex then
            sd.UIScale.Scale = 0.5 
            TweenService:Create(sd.UIScale, popTweenIn, {Scale = 1.1}):Play()
            TweenService:Create(sd.Button, popTweenIn, {Rotation = (math.random() - 0.5) * 10}):Play()
            
            task.delay(0.3, function()
                TweenService:Create(sd.UIScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
                TweenService:Create(sd.Button, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = 0}):Play()
            end)
          end
        end
      end

      if dragVisualClone then
        dragVisualClone:Destroy()
        dragVisualClone = nil
      end

      -- Let renderUI handle background transparency to keep it clean
      draggedObjectData.Stroke.Transparency = 0
      draggedObjectData.NameLabel.TextTransparency = 0
      if draggedObjectData.NameLabel:FindFirstChildOfClass("UIStroke") then
        draggedObjectData.NameLabel:FindFirstChildOfClass("UIStroke").Transparency = 0
      end
      for _, child in ipairs(draggedObjectData.Button:GetChildren()) do
        if child:IsA("ViewportFrame") then
          child.ImageTransparency = 0
          child.Visible = true
        elseif child:IsA("ImageLabel") and child.Name == "ItemImage" then
          child.ImageTransparency = 0
          child.Visible = true
        end
      end
      draggedObjectData.Button.TextTransparency = 0
      draggedObjectData = nil

      ensureCapacity()
      renderUI()
      queueLayoutSync()
    end
  end)

  searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    renderUI()
  end)

  local SortTypes = {"Default", "Name", "Revenue", "Cost", "Rarity"}
  local currentSortIndex = 1

  local function doInventorySort()
    local sortType = SortTypes[currentSortIndex]
    sortBtn.Text = "Sort: " .. sortType
    
    local inventoryTools = {}
    -- BUG FIX: Use pairs() to grab every item regardless of empty grid gaps left by moving items
    for i, tool in pairs(slotContents) do
      if i > CONFIG.HotbarSlots and tool then
        table.insert(inventoryTools, tool)
        slotContents[i] = nil
      end
    end
    
    table.sort(inventoryTools, function(a, b)
      if sortType == "Name" then
        return a.Name < b.Name
      elseif sortType == "Revenue" then
        local revA = a:GetAttribute("Revenue") or 0
        local revB = b:GetAttribute("Revenue") or 0
        if revA == revB then return a.Name < b.Name end
        return revA > revB
      elseif sortType == "Cost" then
        local costA = a:GetAttribute("Cost") or 0
        local costB = b:GetAttribute("Cost") or 0
        if costA == costB then return a.Name < b.Name end
        return costA > costB
      elseif sortType == "Rarity" then
        local fakeA, rarA, nameA = getToolSortValue(a)
        local fakeB, rarB, nameB = getToolSortValue(b)
        if rarA ~= rarB then return rarA > rarB end
        return nameA < nameB
      else 
        local fakeA, rarA, nameA = getToolSortValue(a)
        local fakeB, rarB, nameB = getToolSortValue(b)
        if fakeA ~= fakeB then return fakeA > fakeB end
        if rarA ~= rarB then return rarA > rarB end
        return nameA < nameB
      end
    end)
    
    -- Assign items back starting right after the hotbar
    local idx = CONFIG.HotbarSlots + 1
    for _, t in ipairs(inventoryTools) do
      slotContents[idx] = t
      idx = idx + 1
    end
    
    renderUI()
    queueLayoutSync()
  end

  sortBtn.MouseButton1Click:Connect(function()
    currentSortIndex = (currentSortIndex % #SortTypes) + 1
    doInventorySort()
  end)

  sortBtn.MouseEnter:Connect(function()
    TweenService:Create(sortBtn, CONFIG.TweenInfo, {BackgroundTransparency = 0.4}):Play()
  end)

  sortBtn.MouseLeave:Connect(function()
    TweenService:Create(sortBtn, CONFIG.TweenInfo, {BackgroundTransparency = 0.6}):Play()
  end)

  -----------------------------------------------------------
  -- 8. Keybinds & Connections
  -----------------------------------------------------------
  local keyMap = {
    [Enum.KeyCode.One]=1,[Enum.KeyCode.Two]=2,[Enum.KeyCode.Three]=3,
    [Enum.KeyCode.Four]=4,[Enum.KeyCode.Five]=5,[Enum.KeyCode.Six]=6,
    [Enum.KeyCode.Seven]=7,[Enum.KeyCode.Eight]=8,[Enum.KeyCode.Nine]=9,
    [Enum.KeyCode.Zero]=10,
  }

  local bpConns = {}
  local charConns = {}

  setupConnections = function(bp, char)
    for _, c in ipairs(bpConns) do c:Disconnect() end
    for _, c in ipairs(charConns) do c:Disconnect() end
    bpConns = {}
    charConns = {}

    if bp then
      table.insert(bpConns, bp.ChildAdded:Connect(syncDataAndRender))
      table.insert(bpConns, bp.ChildRemoved:Connect(syncDataAndRender))
    end
    if char then
      table.insert(charConns, char.ChildAdded:Connect(syncDataAndRender))
      table.insert(charConns, char.ChildRemoved:Connect(syncDataAndRender))
    end
  end

  player.CharacterAdded:Connect(function(char)
    currentFakeToolAnimTrack = nil 
    task.wait() 
    local newBp = player:WaitForChild("Backpack")
    setupConnections(newBp, char)
    syncDataAndRender()
  end)

  local function toggleInventory()
      if player:GetAttribute("CarryingAnimal") then
        return
      end
      inventoryOpen = not inventoryOpen
      renderUI()

      local MenuTweenIn = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
      local MenuTweenOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

      if inventoryOpen then
        invMenu.Visible = true

        if not invMenu:FindFirstChild("UIScale") then
            local mScale = Instance.new("UIScale")
            mScale.Parent = invMenu
        end
        invMenu.UIScale.Scale = 0.8

        TweenService:Create(invMenu.UIScale, MenuTweenIn, {Scale = 1}):Play()
        TweenService:Create(invMenu, MenuTweenIn, {GroupTransparency = 0}):Play()
        TweenService:Create(invMenuStroke, MenuTweenIn, {Transparency = 0}):Play()
        TweenService:Create(invScrolling, MenuTweenIn, {ScrollBarImageTransparency = 0}):Play()

        invMenu:TweenPosition(
          UDim2.fromScale((1-CONFIG.InventorySizeScale.X)/2, (1-CONFIG.InventorySizeScale.Y)/2),
          Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.45, true)
      else
        TweenService:Create(invMenu.UIScale, MenuTweenOut, {Scale = 0.8}):Play()
        TweenService:Create(invMenu, MenuTweenOut, {GroupTransparency = 1}):Play()
        TweenService:Create(invMenuStroke, MenuTweenOut, {Transparency = 1}):Play()
        TweenService:Create(invScrolling, MenuTweenOut, {ScrollBarImageTransparency = 1}):Play()

        invMenu:TweenPosition(
          UDim2.fromScale((1 - CONFIG.InventorySizeScale.X)/2, 1.2),
          Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.25, true)

        task.delay(0.25, function()
          if not inventoryOpen then invMenu.Visible = false end
        end)
      end
  end

  -- Keep this bound even if Main/Buttons are created late or replaced.
  local boundInventoryButton = nil
  local inventoryButtonConn = nil
  local function bindInventoryButton()
      local mainGui = pGui:FindFirstChild("Main")
      if not mainGui then
          return
      end

      local invBtn = mainGui:FindFirstChild("InventoryBtn", true)
      if not invBtn or not invBtn:IsA("GuiButton") then
          return
      end

      if boundInventoryButton == invBtn and inventoryButtonConn then
          return
      end

      if inventoryButtonConn then
          inventoryButtonConn:Disconnect()
          inventoryButtonConn = nil
      end

      boundInventoryButton = invBtn
      inventoryButtonConn = invBtn.Activated:Connect(function()
          toggleInventory()
      end)
  end

  bindInventoryButton()
  pGui.DescendantAdded:Connect(function(desc)
      if desc.Name == "InventoryBtn" and desc:IsA("GuiButton") then
          bindInventoryButton()
      end
  end)

  setupConnections(backpack, player.Character)
  syncDataAndRender()
  queueLayoutSync()

  UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or player:GetAttribute("IsHiding") or player:GetAttribute("CarryingAnimal") then return end

    local hotIndex = keyMap[input.KeyCode]
    if hotIndex then
      local toolToToggle = slotContents[hotIndex]
      if toolToToggle then
        toggleTool(toolToToggle)
      end
    end
  end)

  end

  return InventoryController
