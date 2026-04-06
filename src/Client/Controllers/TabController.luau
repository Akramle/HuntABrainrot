local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TabController = {
	Name = "TabController",
	Priority = 10, -- Initialize before specific tab controllers
}

local BLUR_SIZE = 15

function TabController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._pGui = self._player:WaitForChild("PlayerGui")
	self._blur = nil
	self._activeTab = nil
	self._isAnimating = false
end

function TabController:_setGroupTransparency(obj: GuiObject, transparency: number)
	if obj:IsA("CanvasGroup") then
		TweenService:Create(obj, TweenInfo.new(0.3), {GroupTransparency = transparency}):Play()
	else
		local function apply(target)
			if target:IsA("TextLabel") or target:IsA("TextButton") or target:IsA("TextBox") then
				TweenService:Create(target, TweenInfo.new(0.3), {TextTransparency = transparency}):Play()
			end
			if target:IsA("ImageLabel") or target:IsA("ImageButton") then
				TweenService:Create(target, TweenInfo.new(0.3), {ImageTransparency = transparency}):Play()
			end
			if target:IsA("Frame") or target:IsA("ScrollingFrame") then
				local original = target:GetAttribute("OrigBT") or target.BackgroundTransparency
				if not target:GetAttribute("OrigBT") then target:SetAttribute("OrigBT", original) end
				local targetBT = (transparency == 1) and 1 or original
				TweenService:Create(target, TweenInfo.new(0.3), {BackgroundTransparency = targetBT}):Play()
			end
			if target:IsA("UIStroke") then
				TweenService:Create(target, TweenInfo.new(0.3), {Transparency = transparency}):Play()
			end
			for _, c in ipairs(target:GetChildren()) do apply(c) end
		end
		apply(obj)
	end
end

function TabController:_setEffectsActive(active: boolean, openTabName: string?)
	local targetBlur = active and BLUR_SIZE or 0
	if active then
		if not self._blur then
			self._blur = Instance.new("BlurEffect")
			self._blur.Size = 0
			self._blur.Parent = Lighting
		end
	end

	if self._blur then
		local blurTween = TweenService:Create(self._blur, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = targetBlur})
		if not active then
			blurTween.Completed:Connect(function()
				if not active and self._blur then
					self._blur:Destroy()
					self._blur = nil
				end
			end)
		end
		blurTween:Play()
	end

	local main = self._pGui:FindFirstChild("Main")
	if main then
		local buttons = main:FindFirstChild("Buttons")
		if buttons then
			for _, btnWrapper in ipairs(buttons:GetChildren()) do
				if btnWrapper:IsA("GuiObject") then
					-- Check if this is the button for the current tab
					local isCurrentTabBtn = openTabName and (btnWrapper.Name == openTabName)
					
					-- "when a tab is open the other buttons doesnt fade out completely but 0.7"
					local targetTransparency = 0
					if active then
						targetTransparency = isCurrentTabBtn and 0 or 0.7
					end
					
					self:_setGroupTransparency(btnWrapper, targetTransparency)
				end
			end
		end

		-- Hide other elements
		if active then
			if not self._mainSnapshot then
				self._mainSnapshot = {}
				for _, child in ipairs(main:GetChildren()) do
					if child:IsA("GuiObject") and child.Name ~= "Buttons" and child.Name ~= "Tabs" and child.Name ~= "CoinsFrame" and child.Name ~= "Bucks" and child.Name ~= "FriendsFrame" and child.Name ~= "DiamondsFrame" then
						self._mainSnapshot[child] = child.Visible
						child.Visible = false
					end
				end
			else
				-- Snapshot already exists (switching tabs), just hide elements
				for _, child in ipairs(main:GetChildren()) do
					if child:IsA("GuiObject") and child.Name ~= "Buttons" and child.Name ~= "Tabs" and child.Name ~= "CoinsFrame" and child.Name ~= "Bucks" and child.Name ~= "FriendsFrame" and child.Name ~= "DiamondsFrame" then
						child.Visible = false
					end
				end
			end
		else
			if self._mainSnapshot then
				for child, wasVisible in pairs(self._mainSnapshot) do
					if child and child.Parent then
						child.Visible = wasVisible
					end
				end
				self._mainSnapshot = nil
			else
				-- Fallback just in case
				for _, child in ipairs(main:GetChildren()) do
					if child:IsA("GuiObject") and child.Name ~= "Buttons" and child.Name ~= "Tabs" and child.Name ~= "CoinsFrame" and child.Name ~= "DropBtn" then
						child.Visible = true
					end
				end
			end
		end
	end
end

function TabController:SetTabVisible(tabName: string, visible: boolean)
	if self._isAnimating then return end
	
	local main = self._pGui:FindFirstChild("Main")
	local tabs = main and main:FindFirstChild("Tabs")
	local tab = tabs and tabs:FindFirstChild(tabName)
	
	if not tab then return end
	if visible == tab.Visible then return end

	self._isAnimating = true
	
	local scale = tab:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", tab)
	
	if visible then
		-- Close previous tab if any
		if self._activeTab and self._activeTab ~= tabName then
			local prevTab = tabs:FindFirstChild(self._activeTab)
			if prevTab then
				prevTab.Visible = false
				local prevScale = prevTab:FindFirstChildOfClass("UIScale")
				if prevScale then prevScale.Scale = 0 end
			end
		end

		self._activeTab = tabName
		tab.Visible = true
		self:_setEffectsActive(true, tabName)
		
		if tab:IsA("CanvasGroup") then
			TweenService:Create(tab, TweenInfo.new(0.3), {GroupTransparency = 0}):Play()
		end
		
		local t = TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
		t.Completed:Connect(function() self._isAnimating = false end)
		t:Play()
	else
		self._activeTab = nil
		self:_setEffectsActive(false)
		
		if tab:IsA("CanvasGroup") then
			TweenService:Create(tab, TweenInfo.new(0.3), {GroupTransparency = 1}):Play()
		end
		
		local tween = TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
		tween.Completed:Connect(function()
			tab.Visible = false
			self._isAnimating = false
		end)
		tween:Play()
	end
end

function TabController:ToggleTab(tabName: string)
	local main = self._pGui:FindFirstChild("Main")
	local tabs = main and main:FindFirstChild("Tabs")
	local tab = tabs and tabs:FindFirstChild(tabName)
	if not tab then return end
	
	self:SetTabVisible(tabName, not tab.Visible)
end

function TabController:BindTab(tabName: string)
	local main = self._pGui:FindFirstChild("Main")
	local buttons = main and main:FindFirstChild("Buttons")
	local tabs = main and main:FindFirstChild("Tabs")
	
	if not buttons or not tabs then return false end
	
	local btnWrapper = buttons:FindFirstChild(tabName)
	local triggerBtn = btnWrapper and btnWrapper:FindFirstChild("btn", true)
	local tab = tabs:FindFirstChild(tabName)
	
	if triggerBtn and tab then
		print("[TabController] Binding " .. tabName)
		
		-- Use Activated for better cross-platform support
		triggerBtn.Activated:Connect(function()
			self:ToggleTab(tabName)
		end)
		
		-- Close button inside tab (usually named 'btn')
		local backBtn = tab:FindFirstChild("btn", true) or tab:FindFirstChild("Back", true)
		if backBtn and backBtn:IsA("GuiButton") then
			backBtn.Activated:Connect(function()
				self:SetTabVisible(tabName, false)
			end)
		end
		
		-- Initial setup
		local scale = tab:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", tab)
		scale.Scale = 0
		tab.Visible = false
		if tab:IsA("CanvasGroup") then tab.GroupTransparency = 1 end
		
		return true
	end
	return false
end

function TabController:Start()
	-- Wait for GUI to be ready
	task.spawn(function()
		local main = self._pGui:WaitForChild("Main", 30)
		local buttons = main:WaitForChild("Buttons", 10)
		local tabs = main:WaitForChild("Tabs", 10)
		
		if not buttons or not tabs then 
			warn("[TabController] Could not find Buttons or Tabs folder in Main!")
			return 
		end

		local function scan()
			for _, btnWrapper in ipairs(buttons:GetChildren()) do
				if btnWrapper:IsA("GuiObject") then
					local tabName = btnWrapper.Name
					if tabs:FindFirstChild(tabName) and not btnWrapper:GetAttribute("TabBound") then
						if self:BindTab(tabName) then
							btnWrapper:SetAttribute("TabBound", true)
						end
					end
				end
			end
		end

		-- Initial bind
		scan()

		-- Listen for new buttons or tabs
		buttons.ChildAdded:Connect(scan)
		tabs.ChildAdded:Connect(scan)
	end)
end

return TabController
