local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local SoundService = {
	Name = "SoundService",
	Priority = -50,
}

local function getCharacterPosition(player: Player): Vector3?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	return nil
end

function SoundService:Init(runtime)
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetSoundRemote()
	self._soundIds = self._config.Sounds
end

function SoundService:PlayOnServer(soundName: string, options)
	local soundId = self._soundIds[soundName]
	if soundId == nil then
		warn("[SoundService] Unknown sound name:", soundName)
		return
	end

	options = options or {}
	local parent = options.parent or game:GetService("SoundService")
	local useRandomPitch = options.randomPitch or false
	local volume = options.volume or 0.5
	local playbackSpeed = options.playbackSpeed or 1

	if useRandomPitch then
		playbackSpeed = math.random(80, 120) / 100
	end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. soundId
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed
	sound.Parent = parent
	sound:Play()

	Debris:AddItem(sound, 2) -- Safely cleanup
end

function SoundService:PlayForPlayer(player: Player, soundName: string, options)
	self._remote:FireClient(player, soundName, options)
end

function SoundService:PlayForEveryone(soundName: string, options)
	self._remote:FireAllClients(soundName, options)
end

function SoundService:PlayNearby(worldPosition: Vector3, soundName: string, options, radius: number?)
	local effectRadius = radius or self._config.Effects.NearbyRadius

	for _, player in ipairs(Players:GetPlayers()) do
		local playerPosition = getCharacterPosition(player)
		if playerPosition and (playerPosition - worldPosition).Magnitude <= effectRadius then
			self:PlayForPlayer(player, soundName, options)
		end
	end
end

function SoundService:Start()
	self._remote.OnServerEvent:Connect(function(player, action, data)
		if action == "PlayGlobal" then
			local soundName = data.SoundName
			if soundName then
				self:PlayForEveryone(soundName, data)
			end
		end
	end)
end

return SoundService
