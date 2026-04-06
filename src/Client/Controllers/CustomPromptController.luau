local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CustomPromptController = {
	Name = "CustomPromptController",
	Priority = 5,
}

local COIN_IMAGE = "rbxassetid://110831422321689"
local MOBILE_TAP_IMAGE = "rbxassetid://9071533698"

function CustomPromptController:Init(runtime)
	self._prompts = {}
	self._player = Players.LocalPlayer
end

local function extractPrice(text)
	-- Extracts just the numbers and common suffixes (K, M, B) from strings like "Common Dog -$150" or "-$500"
	local price = text:match("%%$([%%d%%.%%a]+)")
	if not price then
		price = text:match("%%-(%%d+)") -- Fallback for just -500
	end
	if not price then
		-- Absolute fallback: remove -$ and keep the rest
		price = text:gsub("[%%-%%$]", ""):gsub("^%%s*(.-)%%s*$", "%%1")
	end
	return price
end

function CustomPromptController:_isMoneyPurchase(prompt: ProximityPrompt)
	local action = prompt.ActionText:lower()
	local obj = prompt.ObjectText:lower()
	if action:find("upgrade") or action:find("unlock") or obj:find("%%$") or action:find("%%$") then
		return true
	end
	return false
end

local function getKeyName(keyCode)
	local success, name = pcall(function()
		return UserInputService:GetStringByKeyCode(keyCode)
	end)
	if success and name and name ~= "" then
		return name
	end
	return keyCode.Name
end

function CustomPromptController:_createPromptUI(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local isMobile = inputType == Enum.ProximityPromptInputType.Touch
	local isMoney = self:_isMoneyPurchase(prompt)

	local gui = Instance.new("BillboardGui")
	gui.Name = "CustomPrompt_" .. prompt.Name
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Active = true
	gui.Size = UDim2.new(8.0, 0, 2.2, 0)
	gui.StudsOffset = Vector3.new(0, 1.5, 0)
	if prompt.UIOffset then
		gui.StudsOffset = gui.StudsOffset + Vector3.new(prompt.UIOffset.X, prompt.UIOffset.Y, 0)
	end

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	mainFrame.BackgroundTransparency = 0.1
	mainFrame.BorderSizePixel = 0
	mainFrame.Active = true
	mainFrame.Parent = gui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0.2, 0)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(255, 255, 255)
	mainStroke.Transparency = 0.8
	mainStroke.Thickness = 2
	mainStroke.Parent = mainFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.Parent = mainFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.08, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = mainFrame

	local inputFrame = Instance.new("Frame")
	inputFrame.Name = "InputFrame"
	inputFrame.Size = UDim2.fromScale(0.85, 0.85)
	inputFrame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	inputFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	inputFrame.BackgroundTransparency = 0.92
	inputFrame.LayoutOrder = 1
	inputFrame.Parent = mainFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = inputFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = inputFrame

	local keyLabel = nil
	if isMobile then
		local mobileIcon = Instance.new("ImageLabel")
		mobileIcon.Name = "MobileIcon"
		mobileIcon.Size = UDim2.fromScale(1, 1)
		mobileIcon.BackgroundTransparency = 1
		mobileIcon.Image = MOBILE_TAP_IMAGE
		mobileIcon.ZIndex = 2
		mobileIcon.Parent = inputFrame

		local iconPadding = Instance.new("UIPadding")
		iconPadding.PaddingTop = UDim.new(0.15, 0)
		iconPadding.PaddingBottom = UDim.new(0.15, 0)
		iconPadding.PaddingLeft = UDim.new(0.15, 0)
		iconPadding.PaddingRight = UDim.new(0.15, 0)
		iconPadding.Parent = mobileIcon
	else
		keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "KeyLabel"
		keyLabel.Size = UDim2.fromScale(1, 1)
		keyLabel.BackgroundTransparency = 1
		keyLabel.Font = Enum.Font.GothamBold
		keyLabel.TextColor3 = Color3.new(1, 1, 1)
		keyLabel.TextScaled = true
		keyLabel.Text = getKeyName(prompt.KeyboardKeyCode)
		keyLabel.ZIndex = 2
		keyLabel.Parent = inputFrame

		local keyPadding = Instance.new("UIPadding")
		keyPadding.PaddingTop = UDim.new(0.25, 0)
		keyPadding.PaddingBottom = UDim.new(0.25, 0)
		keyPadding.PaddingLeft = UDim.new(0.2, 0)
		keyPadding.PaddingRight = UDim.new(0.2, 0)
		keyPadding.Parent = keyLabel
	end

	local progressFrame = Instance.new("Frame")
	progressFrame.Name = "ProgressFrame"
	progressFrame.Size = UDim2.fromScale(1, 1)
	progressFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	progressFrame.BackgroundTransparency = 1
	progressFrame.BorderSizePixel = 0
	progressFrame.ZIndex = 1
	progressFrame.Parent = inputFrame
	
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 0)
	fill.Position = UDim2.fromScale(0, 1)
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BackgroundTransparency = 0.5
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = progressFrame
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.25, 0)
	fillCorner.Parent = fill

	local textFrame = Instance.new("Frame")
	textFrame.Name = "TextFrame"
	textFrame.Size = UDim2.fromScale(0.7, 1)
	textFrame.BackgroundTransparency = 1
	textFrame.LayoutOrder = 2
	textFrame.Parent = mainFrame

	local textLayout = Instance.new("UIListLayout")
	textLayout.FillDirection = Enum.FillDirection.Vertical
	textLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	textLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	textLayout.Padding = UDim.new(0.02, 0)
	textLayout.Parent = textFrame

	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Size = UDim2.new(1, 0, 0.45, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.TextColor3 = Color3.new(1, 1, 1)
	actionLabel.TextScaled = true
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.Text = prompt.ActionText
	actionLabel.Parent = textFrame

	local actionConstraint = Instance.new("UITextSizeConstraint")
	actionConstraint.MaxTextSize = 32
	actionConstraint.Parent = actionLabel

	local objectLabel = Instance.new("TextLabel")
	objectLabel.Name = "ObjectLabel"
	objectLabel.Size = UDim2.new(1, 0, 0.35, 0)
	objectLabel.BackgroundTransparency = 1
	objectLabel.Font = Enum.Font.GothamMedium
	objectLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	objectLabel.TextScaled = true
	objectLabel.TextXAlignment = Enum.TextXAlignment.Left
	objectLabel.Text = prompt.ObjectText
	objectLabel.Visible = not isMoney
	objectLabel.Parent = textFrame

	local objectConstraint = Instance.new("UITextSizeConstraint")
	objectConstraint.MaxTextSize = 24
	objectConstraint.Parent = objectLabel

	local moneyFrame = Instance.new("Frame")
	moneyFrame.Name = "MoneyFrame"
	moneyFrame.Size = UDim2.new(1, 0, 0.45, 0)
	moneyFrame.BackgroundTransparency = 1
	moneyFrame.Visible = isMoney
	moneyFrame.Parent = textFrame

	local moneyLayout = Instance.new("UIListLayout")
	moneyLayout.FillDirection = Enum.FillDirection.Horizontal
	moneyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	moneyLayout.Padding = UDim.new(0.05, 0)
	moneyLayout.Parent = moneyFrame

	local coinIcon = Instance.new("ImageLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.fromScale(0.85, 0.85)
	coinIcon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	coinIcon.BackgroundTransparency = 1
	coinIcon.Image = COIN_IMAGE
	coinIcon.Parent = moneyFrame

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Size = UDim2.new(0.8, 0, 1, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextColor3 = Color3.fromRGB(255, 230, 100)
	priceLabel.TextScaled = true
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Text = extractPrice(prompt.ObjectText)
	priceLabel.Parent = moneyFrame

	local priceConstraint = Instance.new("UITextSizeConstraint")
	priceConstraint.MaxTextSize = 28
	priceConstraint.Parent = priceLabel

	local button = Instance.new("TextButton")
	button.Name = "TouchButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Active = true
	button.ZIndex = 10
	button.Parent = gui

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)

	button.Activated:Connect(function()
		-- Final fallback to ensure single-clicks work
		if prompt.HoldDuration == 0 then
			local p = prompt :: any
			p:InputHoldBegin()
			p:InputHoldEnd()
		end
	end)


	local playerGui = self._player:WaitForChild("PlayerGui")
	gui.Adornee = prompt.Parent
	gui.Parent = playerGui

	local conn = prompt.Changed:Connect(function(prop)
		if prop == "ActionText" then
			actionLabel.Text = prompt.ActionText
		elseif prop == "ObjectText" then
			if isMoney then
				priceLabel.Text = extractPrice(prompt.ObjectText)
			else
				objectLabel.Text = prompt.ObjectText
			end
		elseif prop == "KeyboardKeyCode" and not isMobile and keyLabel then
			keyLabel.Text = getKeyName(prompt.KeyboardKeyCode)
		elseif prop == "Enabled" and not prompt.Enabled then
			self:_destroyPromptUI(prompt)
		end
	end)

	gui.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(gui, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(8.0, 0, 2.2, 0)}):Play()

	self._prompts[prompt] = {
		gui = gui,
		fill = fill,
		tween = nil,
		conn = conn
	}
end

function CustomPromptController:_destroyPromptUI(prompt: ProximityPrompt)
	local data = self._prompts[prompt]
	if data then
		if data.conn then data.conn:Disconnect() end
		if data.tween then data.tween:Cancel() end
		if data.gui then
			local gui = data.gui
			TweenService:Create(gui, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = UDim2.new(0, 0, 0, 0)}):Play()
			task.delay(0.15, function() if gui then gui:Destroy() end end)
		end
		self._prompts[prompt] = nil
	end
end

function CustomPromptController:Start()
	local function overridePrompt(prompt)
		if prompt:IsA("ProximityPrompt") then
			prompt.Style = Enum.ProximityPromptStyle.Custom
		end
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		overridePrompt(descendant)
	end
	Workspace.DescendantAdded:Connect(overridePrompt)

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			if not self._prompts[prompt] then
				self:_createPromptUI(prompt, inputType)
			end
		end
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		self:_destroyPromptUI(prompt)
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local data = self._prompts[prompt]
		if data then
			if data.tween then data.tween:Cancel() end
			data.fill.Size = UDim2.fromScale(1, 0)
			data.tween = TweenService:Create(data.fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(1, 1)})
			data.tween:Play()
		end
	end)

	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local data = self._prompts[prompt]
		if data then
			if data.tween then data.tween:Cancel() end
			data.fill.Size = UDim2.fromScale(1, 0)
		end
	end)
end

return CustomPromptController
