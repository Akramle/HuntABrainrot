local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local RebirthService = {
	Name = "RebirthService",
	Priority = 0,
}

function RebirthService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetRebirthRemote()
end

function RebirthService:_checkRequirements(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stats = player:FindFirstChild("Stats")
	if not leaderstats or not stats then return false, "Stats not found" end

	local bucks = leaderstats:FindFirstChild("Bucks")
	local diamonds = leaderstats:FindFirstChild("Diamonds")
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if not bucks or not diamonds or not rebirths then return false, "Currency not found" end

	local currentRebirths = rebirths.Value
	local requirements = self._config.Rebirth.Requirements
	
	-- Find the requirement for the NEXT rebirth
	local req = nil
	for _, r in ipairs(requirements) do
		if r.RebirthCount == currentRebirths then
			req = r
			break
		end
	end

	-- If no specific requirement found for this high level, use the last one or a formula
	if not req then
		req = requirements[#requirements]
	end

	if not req then return false, "No rebirth configuration found" end

	-- Check Bucks
	if bucks.Value < req.Bucks then
		return false, "Not enough Bucks!"
	end

	-- Check Diamonds
	if diamonds.Value < req.Diamonds then
		return false, "Not enough Diamonds!"
	end

	-- Check Animals (this part depends on how collection is tracked)
	-- For now, we check if they HAVE the animal in inventory or on base
	if req.Animals and #req.Animals > 0 then
		local hasAll = true
		local animalService = self._runtime:GetService("AnimalService")
		-- We need a way to check if player "owns" an animal species
		-- Assuming we check currently owned instances for now
		for _, animalName in ipairs(req.Animals) do
			local found = false
			-- Check inventory
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				for _, item in ipairs(backpack:GetChildren()) do
					if item.Name == animalName and CollectionService:HasTag(item, "Animal") then
						found = true
						break
					end
				end
			end
			
			if not found then
				-- Check base
				local baseService = self._runtime:GetService("BaseService")
				local base = baseService:GetPlayerBase(player)
				if base then
					for _, desc in ipairs(base:GetDescendants()) do
						if desc.Name == animalName and CollectionService:HasTag(desc, "Animal") then
							found = true
							break
						end
					end
				end
			end

			if not found then
				hasAll = false
				break
			end
		end

		if not hasAll then
			return false, "You don't have the required animals!"
		end
	end

	return true, req
end

function RebirthService:PerformRebirth(player: Player)
	local success, reqOrMessage = self:_checkRequirements(player)
	if not success then
		return false, reqOrMessage
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local stats = player:FindFirstChild("Stats")
	local bucks = leaderstats:FindFirstChild("Bucks")
	local diamonds = leaderstats:FindFirstChild("Diamonds")
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	local multiplier = stats:FindFirstChild("Multiplier")

	-- 1. Increase Rebirths and Multiplier
	rebirths.Value += 1
	multiplier.Value += self._config.Rebirth.MultiplierIncrease

	-- 2. Reset Currencies
	bucks.Value = 0
	diamonds.Value = 0

	-- 3. Clear Base
	local baseService = self._runtime:GetService("BaseService")
	if baseService then
		baseService:ResetBase(player)
	end

	-- 4. Reset Swords
	local swordsFolder = stats:FindFirstChild("Swords")
	local ownedSwords = stats:FindFirstChild("OwnedSwords")
	if swordsFolder then
		local currentSword = swordsFolder:FindFirstChild("CurrentSword")
		if currentSword then
			currentSword.Value = "Wooden Sword"
		end
	end
	if ownedSwords then
		for _, child in ipairs(ownedSwords:GetChildren()) do
			if child.Name ~= "Wooden Sword" then
				child:Destroy()
			end
		end
	end

	-- 5. Clear Inventory (Except default sword)
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child.Name ~= "Wooden Sword" then
				child:Destroy()
			end
		end
	end
	
	-- Also check character
	if player.Character then
		for _, child in ipairs(player.Character:GetChildren()) do
			if child:IsA("Tool") and child.Name ~= "Wooden Sword" then
				child:Destroy()
			end
		end
	end

	-- Give default sword back just in case
	local swordService = self._runtime:GetService("SwordService")
	if swordService then
		-- This will ensure they have the physical tool
		task.defer(function()
			if player.Parent then
				swordService:_giveSword(player, "Wooden Sword")
			end
		end)
	end

	-- 6. Reset Upgrades
	local upgrades = stats:FindFirstChild("Upgrades")
	if upgrades then
		for _, val in ipairs(upgrades:GetChildren()) do
			if val:IsA("IntValue") or val:IsA("NumberValue") then
				val.Value = (val.Name == "Walkspeed") and 1 or 0
			end
		end
	end

	-- 7. Lock areas (Except Plains)
	local unlockedAreas = stats:FindFirstChild("UnlockedAreas")
	if unlockedAreas then
		for _, val in ipairs(unlockedAreas:GetChildren()) do
			if val:IsA("BoolValue") then
				val.Value = (val.Name == "Plains")
			end
		end
	end

	-- Notify client
	local notificationService = self._runtime:GetService("NotificationService")
	if notificationService then
		notificationService:NotifyPlayer(player, "Successfully Rebithed! Multiplier increased!", "Success")
	end
	
	return true
end

function RebirthService:Start()
	self._remote.OnServerEvent:Connect(function(player, action)
		if action == "Rebirth" then
			self:PerformRebirth(player)
		elseif action == "GetRequirements" then
			-- Logic to send requirements back if needed, 
			-- but client can usually check config or attributes
		end
	end)
end

return RebirthService
