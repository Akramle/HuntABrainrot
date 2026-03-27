local Players = game:GetService("Players")

local NotificationService = {
	Name = "NotificationService",
	Priority = -10,
}

function NotificationService:Init(runtime)
	self._runtime = runtime
	self._remote = runtime.Remotes:GetNotificationRemote()
end

function NotificationService:NotifyPlayer(player: Player, message: string, nType: "Announcement" | "Warning", data: table?)
	if not player then return end
	self._remote:FireClient(player, message, nType, data or {})
end

function NotificationService:NotifyAll(message: string, nType: "Announcement" | "Warning", data: table?)
	self._remote:FireAllClients(message, nType, data or {})
end

return NotificationService
