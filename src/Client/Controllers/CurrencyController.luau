local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local CurrencyController = {
	Name = "CurrencyController",
	Priority = 10,
}

local function smoothNumber(current, target, dt)
	-- Speed of the animation
	local diff = target - current
	if math.abs(diff) < 1 then
		return target
	end
	
	-- Approach quickly but logarithmically
	local moveAmount = diff * math.min(1, dt * 10)
	-- Minimum move amount to ensure it finishes
	if moveAmount > 0 then
		moveAmount = math.max(1, moveAmount)
	else
		moveAmount = math.min(-1, moveAmount)
	end
	
	if (moveAmount > 0 and current + moveAmount > target) or (moveAmount < 0 and current + moveAmount < target) then
		return target
	end
	
	return current + moveAmount
end

local function formatCurrency(value)
	value = math.floor(value)
	if value >= 1000000000 then
		return NumberFormatter:Format(value, "Letters")
	else
		return NumberFormatter:Format(value, "Comma")
	end
end

function CurrencyController:Init(runtime)
	self._runtime = runtime
	self._player = Players.LocalPlayer
	
	self._targetBucks = 0
	self._currentBucks = 0
	
	self._targetDiamonds = 0
	self._currentDiamonds = 0
	
	self._friendsCount = 0
end

function CurrencyController:_updateFriendsBoost(friendsLabel: TextLabel)
	task.spawn(function()
		local count = 0
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= self._player then
				local success, isFriend = pcall(function()
					return self._player:IsFriendsWith(otherPlayer.UserId)
				end)
				if success and isFriend then
					count += 1
				end
			end
		end
		self._friendsCount = count
		if friendsLabel then
			friendsLabel.Text = "Friends Boost: +" .. tostring(count * 10) .. "%"
		end
	end)
end

function CurrencyController:Start()
	local playerGui = self._player:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("Main", 10)
	if not main then return end
	
	-- Bucks Frame
	local bucksLabel = nil
	local bucksFrame = main:FindFirstChild("Bucks")
	if bucksFrame and bucksFrame:IsA("TextLabel") then
		bucksLabel = bucksFrame
	elseif bucksFrame then
		-- In case it's a frame with a textlabel child
		bucksLabel = bucksFrame:FindFirstChildWhichIsA("TextLabel", true)
	end
	
	-- Diamonds Frame
	local diamondsLabel = nil
	local diamondsFrame = main:FindFirstChild("DiamondsFrame")
	if diamondsFrame then
		diamondsLabel = diamondsFrame:FindFirstChild("Diamonds") or diamondsFrame:FindFirstChildWhichIsA("TextLabel", true)
	end
	
	-- Friends Frame
	local friendsLabel = nil
	local friendsFrame = main:FindFirstChild("FriendsFrame")
	if friendsFrame then
		friendsLabel = friendsFrame:FindFirstChild("Friends") or friendsFrame:FindFirstChildWhichIsA("TextLabel", true)
	end
	
	-- Setup initial values
	local leaderstats = self._player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local bucksVal = leaderstats:WaitForChild("Bucks", 5)
		if bucksVal then
			self._targetBucks = bucksVal.Value
			self._currentBucks = bucksVal.Value
			if bucksLabel then
				bucksLabel.Text = "$" .. formatCurrency(self._currentBucks)
			end
			bucksVal.Changed:Connect(function(newVal)
				self._targetBucks = newVal
			end)
		end
		
		local diamondsVal = leaderstats:WaitForChild("Diamonds", 5)
		if diamondsVal then
			self._targetDiamonds = diamondsVal.Value
			self._currentDiamonds = diamondsVal.Value
			if diamondsLabel then
				diamondsLabel.Text = formatCurrency(self._currentDiamonds)
			end
			diamondsVal.Changed:Connect(function(newVal)
				self._targetDiamonds = newVal
			end)
		end
	end
	
	-- Friends Boost Initialization & Listening
	if friendsLabel then
		self:_updateFriendsBoost(friendsLabel)
		Players.PlayerAdded:Connect(function()
			self:_updateFriendsBoost(friendsLabel)
		end)
		Players.PlayerRemoving:Connect(function()
			self:_updateFriendsBoost(friendsLabel)
		end)
	end
	
	-- Smooth Animation Loop
	RunService.RenderStepped:Connect(function(dt)
		if bucksLabel and self._currentBucks ~= self._targetBucks then
			self._currentBucks = smoothNumber(self._currentBucks, self._targetBucks, dt)
			bucksLabel.Text = "$" .. formatCurrency(self._currentBucks)
		end
		
		if diamondsLabel and self._currentDiamonds ~= self._targetDiamonds then
			self._currentDiamonds = smoothNumber(self._currentDiamonds, self._targetDiamonds, dt)
			diamondsLabel.Text = "💎" .. formatCurrency(self._currentDiamonds) -- Optional emoji or string if needed
		end
	end)
end

return CurrencyController
