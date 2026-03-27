local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local AreaService = {
	Name = "AreaService",
	Priority = -100,
}

function AreaService:Init(runtime)
	self._runtime = runtime
	self._areasFolder = Workspace:FindFirstChild("Areas")
	self._unlockRemote = nil
	self._guiTemplate = nil
end

function AreaService:_setupUnlocker(model: Model)
	local interact = model:FindFirstChild("Interact")
	local prompt = interact and interact:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then return end
	
	local areaVal = model:FindFirstChild("Area")
	local priceVal = model:FindFirstChild("Price")
	if not areaVal or not priceVal then return end

	prompt.Triggered:Connect(function(player)
		local playerGui = player:FindFirstChild("PlayerGui")
		if not playerGui then return end
		
		if not self._guiTemplate then
			local assets = ServerStorage:FindFirstChild("Assets")
			local guis = assets and assets:FindFirstChild("Gui")
			self._guiTemplate = guis and guis:FindFirstChild("AlertGui")
		end
		
		if not self._guiTemplate then
			warn("[AreaService] AlertGui not found in ServerStorage.Assets.Gui")
			return
		end
		
		-- Destroy old if it exists
		local existing = playerGui:FindFirstChild("AlertGui")
		if existing then existing:Destroy() end
		
		local clone = self._guiTemplate:Clone()
		clone.Name = "AlertGui"
		
		local mainFrame = clone:FindFirstChild("main")
		if not mainFrame then
			warn("[AreaService] AlertGui missing 'main' frame")
			clone.Parent = playerGui -- Still parent it so it can be debugged
			return
		end
		
		-- Setup GUI Content
		local buyFrame = mainFrame:FindFirstChild("BuyFrame")
		local priceLabel = buyFrame and buyFrame:FindFirstChild("price")
		if priceLabel then
			priceLabel.Text = NumberFormatter:Format(priceVal.Value, "Letters")
		end
		
		local contentLabel = mainFrame:FindFirstChild("content")
		if contentLabel then
			contentLabel.Text = string.format("Do you want to unlock %s?", areaVal.Value)
		end
		
		-- Store data for client to use when accepting
		clone:SetAttribute("AreaName", areaVal.Value)
		clone:SetAttribute("Price", priceVal.Value)
		
		local unlockerRef = Instance.new("ObjectValue")
		unlockerRef.Name = "UnlockerRef"
		unlockerRef.Value = model
		unlockerRef.Parent = clone
		
		clone.Parent = playerGui
	end)
end

-- Checks if a given position is inside any area. Returns the area name, or "Plains" as default/fallback if none found.
function AreaService:GetAreaFromPosition(position: Vector3): string
	if not self._areasFolder then return "Plains" end

	-- Simple AABB check for all parts in the Areas folder
	for _, areaPart in ipairs(self._areasFolder:GetChildren()) do
		if areaPart:IsA("BasePart") then
			local relativePos = areaPart.CFrame:ToObjectSpace(CFrame.new(position))
			local size = areaPart.Size

			if math.abs(relativePos.X) <= size.X/2 and math.abs(relativePos.Y) <= size.Y/2 and math.abs(relativePos.Z) <= size.Z/2 then
				return areaPart.Name
			end
		end
	end

	return "Plains" -- Default area
end

function AreaService:HasAreaUnlocked(player: Player, areaName: string): boolean
	local stats = player:FindFirstChild("Stats")
	if not stats then return false end
	
	local unlockedAreas = stats:FindFirstChild("UnlockedAreas")
	if not unlockedAreas then return false end
	
	local areaVal = unlockedAreas:FindFirstChild(areaName)
	return areaVal and areaVal:IsA("BoolValue") and areaVal.Value == true
end

function AreaService:UnlockArea(player: Player, areaName: string, price: number): boolean
	if self:HasAreaUnlocked(player, areaName) then return true end -- Already unlocked
	
	local leaderstats = player:FindFirstChild("leaderstats")
	local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
	if not bucks or bucks.Value < price then 
		self._runtime:GetService("NotificationService"):NotifyPlayer(player, "Not enough Bucks!", "Warning")
		return false 
	end
	
	local stats = player:FindFirstChild("Stats")
	local unlockedAreas = stats and stats:FindFirstChild("UnlockedAreas")
	if not unlockedAreas then return false end
	
	-- Deduct price
	bucks.Value -= price
	
	-- Unlock area
	local areaVal = unlockedAreas:FindFirstChild(areaName)
	if not areaVal then
		areaVal = Instance.new("BoolValue")
		areaVal.Name = areaName
		areaVal.Parent = unlockedAreas
	end
	areaVal.Value = true
	
	return true
end

function AreaService:Start()
	self._unlockRemote = self._runtime.Remotes:GetAreaUnlockRemote()
	
	self._unlockRemote.OnServerInvoke = function(player, areaName, price)
		if type(areaName) ~= "string" or type(price) ~= "number" then return false end
		return self:UnlockArea(player, areaName, price)
	end

	-- Setup existing unlockers
	for _, model in ipairs(CollectionService:GetTagged("Unlocker")) do
		self:_setupUnlocker(model)
	end
	
	CollectionService:GetInstanceAddedSignal("Unlocker"):Connect(function(model)
		if model:IsA("Model") then
			self:_setupUnlocker(model)
		end
	end)

	-- Teleport cheaters who enter locked areas
	RunService.Heartbeat:Connect(function()
		if not self._areasFolder then return end

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local currentArea = self:GetAreaFromPosition(rootPart.Position)
				
				if not self:HasAreaUnlocked(player, currentArea) then
					-- Debounce teleport to prevent rapid loop stuttering
					if player:GetAttribute("Teleporting") then continue end
					player:SetAttribute("Teleporting", true)

					-- Try to teleport them to their base's spawn location first
					local spawnLoc = player.RespawnLocation
					if not spawnLoc then
						-- Fallback if they don't have a base or spawn location yet
						spawnLoc = Workspace:FindFirstChildWhichIsA("SpawnLocation")
					end
					
					if spawnLoc then
						rootPart.CFrame = spawnLoc.CFrame + Vector3.new(0, 5, 0)
					else
						-- Absolute fallback if no spawn location exists anywhere
						rootPart.CFrame = CFrame.new(0, 10, 0)
					end
					
					-- Reset state after short delay
					task.delay(1, function()
						if player then player:SetAttribute("Teleporting", nil) end
					end)
				end
			end
		end
	end)
end

return AreaService