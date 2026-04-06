local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local MusicController = {
	Name = "MusicController",
	Priority = 10,
}

local BASE_VOLUME = 0.5
local FADE_TIME = 1.5

function MusicController:Init(runtime)
	self._runtime = runtime
	self._musicFolder = ReplicatedStorage:WaitForChild("Music", 5)
	self._currentSound = nil
	self._isEnabled = true
	self._isEventActive = false
	self._connection = nil
end

function MusicController:_playNextSong()
	if not self._isEnabled or not self._musicFolder then return end

	local songs = self._musicFolder:GetChildren()
	if #songs == 0 then return end

	local randomSong = songs[math.random(1, #songs)]
	
	if self._currentSound then
		self._currentSound:Stop()
		self._currentSound:Destroy()
	end

	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end

	self._currentSound = randomSong:Clone()
	self._currentSound.Name = "GameMusic"
	self._currentSound.Parent = SoundService
	self._currentSound.Volume = if self._isEventActive then 0 else BASE_VOLUME
	self._currentSound:Play()

	self._connection = self._currentSound.Ended:Connect(function()
		if self._isEnabled then
			self:_playNextSong()
		end
	end)
end

function MusicController:SetMusicEnabled(enabled)
	self._isEnabled = enabled
	if enabled then
		if self._currentSound then
			self._currentSound:Resume()
			self:_updateVolume()
		else
			self:_playNextSong()
		end
	else
		if self._currentSound then
			self._currentSound:Pause()
		end
	end
end

function MusicController:SetEventActive(active)
	self._isEventActive = active
	self:_updateVolume()
end

function MusicController:_updateVolume()
	if not self._currentSound then return end
	
	local targetVolume = (self._isEnabled and not self._isEventActive) and BASE_VOLUME or 0
	
	TweenService:Create(self._currentSound, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = targetVolume
	}):Play()
end

function MusicController:Start()
	if self._musicFolder then
		self:_playNextSong()
	end
end

return MusicController
