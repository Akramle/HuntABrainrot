local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local TeleportController = {
	Name = "TeleportController",
	Priority = 0,
}

function TeleportController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	self._playerGui = self._player:WaitForChild("PlayerGui")
end

function TeleportController:Start()
	task.spawn(function()
		local mainUi = self._playerGui:WaitForChild("Main")
		local teleporters = mainUi:WaitForChild("Teleporters")

		self:_setupTeleporter(teleporters:WaitForChild("Base"), function()
			self:_teleportToBase()
		end)

		self:_setupTeleporter(teleporters:WaitForChild("Sell"), function()
			self:_teleportToStand("Sell")
		end)

		self:_setupTeleporter(teleporters:WaitForChild("Swords"), function()
			self:_teleportToStand("Swords")
		end)
	end)
end

function TeleportController:_setupTeleporter(teleporterFrame, callback)
	local btn = teleporterFrame:WaitForChild("btn", 10)
	if btn and btn:IsA("GuiButton") then
		btn.Activated:Connect(callback)
	end
end

function TeleportController:_teleport(targetCFrame)
	local character = self._player.Character
	if character then
		-- Prevent teleporting while hiding or carrying (optional safety check, but generally good)
		if self._player:GetAttribute("IsHiding") then
			local notificationController = self._runtime:GetController("NotificationController")
			if notificationController then
				notificationController:ShowNotification("Cannot teleport while hiding!", "Error")
			end
			return
		end

		character:PivotTo(targetCFrame + Vector3.new(0, 3, 0))
		
		local soundController = self._runtime:GetController("SoundController")
		if soundController then
			soundController:PlayLocal("Click") -- Optional feedback
		end
	end
end

function TeleportController:_teleportToBase()
	local bases = Workspace:FindFirstChild("Bases")
	if not bases then return end

	local playerBase = bases:FindFirstChild(self._player.Name)
	if playerBase then
		local extras = playerBase:FindFirstChild("Extras")
		if extras then
			local multiplier = extras:FindFirstChild("Multiplier")
			if multiplier and multiplier:IsA("BasePart") then
				self:_teleport(multiplier.CFrame)
			end
		end
	end
end

function TeleportController:_teleportToStand(standName)
	local stands = Workspace:FindFirstChild("Stands")
	if not stands then return end

	local stand = stands:FindFirstChild(standName)
	if stand then
		local tpPart = stand:FindFirstChild("tp")
		if tpPart and tpPart:IsA("BasePart") then
			self:_teleport(tpPart.CFrame)
		end
	end
end

return TeleportController
