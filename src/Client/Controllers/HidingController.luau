local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local HidingController = {
	Name = "HidingController",
	Priority = 0,
}

function HidingController:Init(runtime)
	self._remote = runtime.Remotes:GetHidingRemote()
end

function HidingController:Start()
	self._remote.OnClientEvent:Connect(function(isHiding, spotModel)
		local camera = Workspace.CurrentCamera
		if not camera then return end

		local player = Players.LocalPlayer
		local character = player.Character

		if isHiding then
			-- Hide custom inventory
			local inventoryGui = player.PlayerGui:FindFirstChild("ModernStylizedInventory")
			if inventoryGui then
				inventoryGui.Enabled = false
			end

			-- Keep camera custom so player can rotate around, but adjust limits
			camera.CameraType = Enum.CameraType.Custom
			
			if character then
				local head = character:FindFirstChild("Head")
				if head then
					camera.CameraSubject = head
				end
			end
			
			-- Force a closer zoom and angle so they look down at themselves
			player.CameraMaxZoomDistance = 12
			player.CameraMinZoomDistance = 5
			
		else
			-- Show custom inventory
			local inventoryGui = player.PlayerGui:FindFirstChild("ModernStylizedInventory")
			if inventoryGui then
				inventoryGui.Enabled = true
			end

			-- Return camera to normal behavior
			camera.CameraType = Enum.CameraType.Custom
			if character then
				local humanoid = character:FindFirstChild("Humanoid")
				if humanoid then
					camera.CameraSubject = humanoid
				end
			end
			
			-- Restore normal zoom distances (you can adjust these to your game's defaults)
			player.CameraMaxZoomDistance = 128
			player.CameraMinZoomDistance = 0.5
		end
	end)
end

return HidingController