local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CarryAnimalController = {
	Name = "CarryAnimalController",
	Priority = 0,
}

local function tweenGroupTransparency(root: Instance, target: number, duration: number)
	local function tweenIfGui(obj: Instance)
		if not obj or not obj:IsA("GuiObject") then return end
		pcall(function()
			TweenService:Create(
				obj,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ GroupTransparency = target }
			):Play()
		end)
	end

	tweenIfGui(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		tweenIfGui(descendant)
	end
end

function CarryAnimalController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetCarryAnimalRemote()
end

function CarryAnimalController:Start()
	if self._started then
		return
	end
	self._started = true

	local playerGui = self._player:WaitForChild("PlayerGui")
	local mainHud = playerGui:WaitForChild("Main", 10)
	if not mainHud then
		warn("[CarryAnimalController] Missing PlayerGui.Main")
		return
	end

	local dropBtnFrame = mainHud:WaitForChild("DropBtn", 10)
	if not dropBtnFrame then
		warn("[CarryAnimalController] Missing Main.DropBtn frame")
		return
	end

	local dropButton = dropBtnFrame:WaitForChild("btn", 10)
	if not dropButton then
		warn("[CarryAnimalController] Missing DropBtn.btn button")
		return
	end

	local uiScale = dropBtnFrame:FindFirstChildWhichIsA("UIScale") or dropBtnFrame:FindFirstChild("uiScale")
	if not uiScale then
		warn("[CarryAnimalController] Missing DropBtn.uiScale (UIScale)")
	end

	-- Initial hide
	dropBtnFrame.Visible = false
	if uiScale then
		uiScale.Scale = 0.7
	end

	self._playerGui = playerGui
	self._mainHud = mainHud
	self._dropBtnFrame = dropBtnFrame
	self._dropButton = dropButton
	self._uiScale = uiScale

	self._guiSnapshot = nil

	-- Wire drop action
	dropButton.MouseButton1Click:Connect(function()
		if not self._player:GetAttribute("CarryingAnimal") then
			return
		end
		if not self._remote then
			return
		end
		self._remote:FireServer("Drop")
	end)

	local function hideAllGuiForCarry()
		-- Snapshot current enabled/visible states so we can restore cleanly.
		self._guiSnapshot = {
			screenGuiEnabled = {},
			mainChildrenVisible = {},
		}

		-- Hide all other ScreenGuis (inventory, notifications, menus, etc).
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and child ~= mainHud then
				self._guiSnapshot.screenGuiEnabled[child] = child.Enabled
				child.Enabled = false
			end
		end

		-- Hide every Main child except DropBtn.
		for _, child in ipairs(mainHud:GetChildren()) do
			if child:IsA("GuiObject") and child ~= dropBtnFrame then
				self._guiSnapshot.mainChildrenVisible[child] = child.Visible
				tweenGroupTransparency(child, 1, 0.2)
				child.Visible = false
			end
		end

		-- Show drop frame after hiding others.
		dropBtnFrame.Visible = true
		tweenGroupTransparency(dropBtnFrame, 0, 0.15)

		if uiScale then
			uiScale.Scale = 0.7
			TweenService:Create(
				uiScale,
				TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }
			):Play()
		end
	end

	local function restoreGuiAfterCarry()
		local snapshot = self._guiSnapshot
		self._guiSnapshot = nil
		if snapshot then
			for gui, enabled in pairs(snapshot.screenGuiEnabled) do
				if gui and gui.Parent then
					gui.Enabled = enabled == true
				end
			end

			for child, visible in pairs(snapshot.mainChildrenVisible) do
				if child and child.Parent then
					child.Visible = visible == true
					tweenGroupTransparency(child, 0, 0.15)
				end
			end
		end

		-- Keep inventory disabled while hiding.
		local inv = playerGui:FindFirstChild("ModernStylizedInventory")
		if inv and inv:IsA("ScreenGui") and self._player:GetAttribute("IsHiding") then
			inv.Enabled = false
		end

		-- Hide drop frame
		if uiScale then
			TweenService:Create(
				uiScale,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = 0.7 }
			):Play()
		end
		task.delay(0.18, function()
			if dropBtnFrame then
				dropBtnFrame.Visible = false
			end
		end)
	end

	local function onCarryChanged()
		if self._player:GetAttribute("CarryingAnimal") == true then
			hideAllGuiForCarry()
		else
			restoreGuiAfterCarry()
		end
	end

	self._player:GetAttributeChangedSignal("CarryingAnimal"):Connect(onCarryChanged)
	onCarryChanged()
end

return CarryAnimalController

