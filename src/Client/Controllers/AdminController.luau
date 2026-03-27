local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local AdminController = {
	Name = "AdminController",
	Priority = 0,
}

function AdminController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetAdminRemote()
	self._player = Players.LocalPlayer
end

local function applyStyling(instance, bgColor)
	instance.BackgroundColor3 = bgColor
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = instance
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
end

local function buildViewport(model, parentFrame)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Parent = parentFrame

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local displayClone = model:Clone()
	displayClone.Parent = worldModel
	
	local cf, size = displayClone:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	if maxDim < 0.5 then maxDim = 1 end
	
	local camera = Instance.new("Camera")
	viewport.CurrentCamera = camera
	camera.Parent = viewport
	
	local fov = math.rad(camera.FieldOfView)
	local distance = (maxDim / 2) / math.tan(fov / 2) * 1.3
	
	camera.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-distance*0.4, distance * 0.4, distance), cf.Position)
	return viewport
end

function AdminController:_createPickerGui(data)
	local mode = data.Mode
	local targetName = data.Target
	local mutation = data.Mutation
	
	local gui = Instance.new("ScreenGui")
	gui.Name = "AdminPicker"
	gui.Parent = self._player:WaitForChild("PlayerGui")
	
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(0.6, 0.7)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	applyStyling(frame, Color3.fromRGB(45, 180, 255))
	frame.Parent = gui
	
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	if mode == "give" then
		title.Text = "Give Animal to " .. targetName
	elseif mode == "spawn_wild" then
		title.Text = "Spawn Wild near " .. targetName
	elseif mode == "fill_base" then
		title.Text = "Fill " .. targetName .. "'s Base"
	end
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 24
	title.Parent = frame
	
	local close = Instance.new("TextButton")
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -45, 0, 5)
	close.Text = "X"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	Instance.new("UICorner").Parent = close
	close.Parent = frame
	close.MouseButton1Click:Connect(function() gui:Destroy() end)
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -20, 1, -70)
	scroll.Position = UDim2.new(0, 10, 0, 60)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.Parent = frame
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(100, 100)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.Parent = scroll
	
	local templates = ReplicatedStorage:WaitForChild("AdminAnimalTemplates")
	for _, rarityFolder in ipairs(templates:GetChildren()) do
		for _, animal in ipairs(rarityFolder:GetChildren()) do
			local btn = Instance.new("TextButton")
			btn.Text = ""
			applyStyling(btn, Color3.fromRGB(150, 220, 255))
			btn.Parent = scroll
			
			buildViewport(animal, btn)
			
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 0, 20)
			label.Position = UDim2.fromScale(0, 0.8)
			label.BackgroundTransparency = 1
			label.Text = animal.Name
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.Parent = btn
			
			btn.MouseButton1Click:Connect(function()
				if mode == "give" then
					self._remote:FireServer("GiveAnimal", {Rarity = rarityFolder.Name, AnimalName = animal.Name, Target = targetName, Mutation = mutation})
				elseif mode == "spawn_wild" then
					self._remote:FireServer("SpawnWild", {Rarity = rarityFolder.Name, AnimalName = animal.Name, Target = targetName, Mutation = mutation})
				elseif mode == "fill_base" then
					self._remote:FireServer("FillBase", {Rarity = rarityFolder.Name, AnimalName = animal.Name, Target = targetName, Mutation = mutation})
				end
				gui:Destroy()
			end)
		end
	end
	
	scroll.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 20)
end

function AdminController:Start()
	local isAdmin = self._player:GetAttribute("IsAdmin") == true
	
	if not isAdmin then
		self._player:GetAttributeChangedSignal("IsAdmin"):Connect(function()
			if self._player:GetAttribute("IsAdmin") == true then
				self:_setupChatInterception()
			end
		end)
	else
		self:_setupChatInterception()
	end
	self._remote.OnClientEvent:Connect(function(action, data)
		if action == "Feedback" then
			local channel = TextChatService:FindFirstChild("TextChannels") and TextChatService.TextChannels:FindFirstChild("RBXGeneral")
			if channel then
				-- Using a wrapper to ensure RichText is always parsed correctly
				local message = tostring(data.Message or "")
				local color = tostring(data.Color or "#FFFFFF")
				
				-- Strip any existing broken tags if they somehow leaked through
				message = message:gsub("<font.->", ""):gsub("</font>", "")
				
				local formatted = string.format("<font color=\"%s\">%s</font>", color, message)
				channel:DisplaySystemMessage(formatted)
			end
		elseif action == "OpenPicker" then
			self:_createPickerGui(data)
		end
	end)
end

function AdminController:_setupChatInterception()
	TextChatService.SendingMessage:Connect(function(message: TextChatMessage)
		if string.sub(message.Text, 1, 1) == "/" then
			local fullText = string.sub(message.Text, 2)
			local parts = string.split(fullText, " ")
			local cmd = parts[1]
			table.remove(parts, 1)

			self._remote:FireServer("Command", {Command = cmd, Args = parts})
		end
	end)
end

return AdminController
