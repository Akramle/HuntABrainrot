local Players = game:GetService("Players")

local ClientEffectsService = {
	Name = "ClientEffectsService",
	Priority = -70,
}

local function getCharacterPosition(player: Player): Vector3?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	return nil
end

function ClientEffectsService:Init(runtime)
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetEffectsRemote()
end

function ClientEffectsService:EmitToPlayer(player: Player, effectName: string, payload)
	self._remote:FireClient(player, effectName, payload)
end

function ClientEffectsService:EmitToAll(effectName: string, payload)
	self._remote:FireAllClients(effectName, payload)
end

function ClientEffectsService:EmitToNearby(worldPosition: Vector3, effectName: string, payload, radius: number?)
	local effectRadius = radius or self._config.Effects.NearbyRadius

	for _, player in ipairs(Players:GetPlayers()) do
		local playerPosition = getCharacterPosition(player)
		if playerPosition and (playerPosition - worldPosition).Magnitude <= effectRadius then
			self:EmitToPlayer(player, effectName, payload)
		end
	end
end

return ClientEffectsService
