local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundController = {
	Name = "SoundController",
	Priority = 0,
}

function SoundController:Init(runtime)
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetSoundRemote()
	self._soundIds = self._config.Sounds
end

function SoundController:PlayLocal(soundName: string, options)
	local soundId = self._soundIds[soundName]
	if soundId == nil then
		warn("[SoundController] Unknown sound name:", soundName)
		return
	end

	options = options or {}
	local parent = options.parent or SoundService
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

	Debris:AddItem(sound, (sound.TimeLength > 0 and sound.TimeLength / playbackSpeed + 0.5) or 2)
end

function SoundController:Start()
	self._remote.OnClientEvent:Connect(function(soundName, options)
		self:PlayLocal(soundName, options)
	end)
end

return SoundController
