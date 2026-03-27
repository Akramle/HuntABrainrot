local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodeService = {
	Name = "CodeService",
	Priority = -5,
}

function CodeService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetCodeRemote()
	self._globalUsageStore = DataStoreService:GetDataStore("GlobalCodeUsage_v1")
	self._cachedGlobalUsage = {}
end

function CodeService:_isExpired(expiration: string): boolean
	if expiration == "lifetime" then return false end
	
	local year, month, day = expiration:match("(%d+)-(%d+)-(%d+)")
	if not year then return false end
	
	local expiryTime = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
	return os.time() > expiryTime
end

function CodeService:_getGlobalUsage(code: string): number
	if self._cachedGlobalUsage[code] then return self._cachedGlobalUsage[code] end
	
	local success, val = pcall(function()
		return self._globalUsageStore:GetAsync(code)
	end)
	
	local usage = (success and val) or 0
	self._cachedGlobalUsage[code] = usage
	return usage
end

function CodeService:_incrementGlobalUsage(code: string)
	self._cachedGlobalUsage[code] = (self._cachedGlobalUsage[code] or 0) + 1
	pcall(function()
		self._globalUsageStore:IncrementAsync(code, 1)
	end)
end

function CodeService:RedeemCode(player: Player, codeInput: string)
	if not codeInput or type(codeInput) ~= "string" then
		return false, "Invalid input"
	end

	local code = codeInput:match("^%s*(.-)%s*$"):upper()
	if code == "" then
		return false, "Please enter a code"
	end
	local codeData = self._config.Codes[code]
	
	if not codeData then
		return false, "Invalid code"
	end

	-- 1. Check expiration
	if self:_isExpired(codeData.Expiration) then
		return false, "Code has expired"
	end

	-- 2. Check personal usage
	local stats = player:FindFirstChild("Stats")
	if not stats then
		return false, "Your data is still loading, try again in a moment"
	end

	local redeemedFolder = stats and stats:FindFirstChild("RedeemedCodes")
	if not redeemedFolder then
		redeemedFolder = Instance.new("Folder")
		redeemedFolder.Name = "RedeemedCodes"
		redeemedFolder.Parent = stats
	end

	if redeemedFolder:FindFirstChild(code) then
		return false, "Code already redeemed"
	end

	-- 3. Check global usage
	if codeData.MaxUsage ~= -1 then
		local currentUsage = self:_getGlobalUsage(code)
		if currentUsage >= codeData.MaxUsage then
			return false, "Code has reached max usage"
		end
	end

	-- 4. Grant Reward
	local rewardDesc = "Unknown Reward"
	
	if codeData.RewardType == "Bucks" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
		if bucks then
			bucks.Value += codeData.Amount
			rewardDesc = "$" .. codeData.Amount .. " Bucks"
		end
	elseif codeData.RewardType == "Multiplier" then
		local statsFolder = player:FindFirstChild("Stats")
		local mult = statsFolder and statsFolder:FindFirstChild("Multiplier")
		if mult then
			mult.Value += (codeData.Amount - 1)
			rewardDesc = "x" .. codeData.Amount .. " Multiplier Boost"
		end
	elseif codeData.RewardType == "Animal" then
		if type(codeData.AnimalName) ~= "string" or codeData.AnimalName == "" then
			return false, "Code is misconfigured (animal name missing)"
		end
		if type(codeData.Rarity) ~= "string" or codeData.Rarity == "" then
			return false, "Code is misconfigured (rarity missing)"
		end

		local animalService = self._runtime:GetService("AnimalService")
		if animalService then
			local rarityStats = self._config.Animals.Stats[codeData.Rarity]
			if rarityStats then
				local minRevenue = tonumber(rarityStats.Revenue and rarityStats.Revenue[1])
				local maxRevenue = tonumber(rarityStats.Revenue and rarityStats.Revenue[2])
				if not minRevenue or not maxRevenue then
					return false, "Code is misconfigured (invalid rarity revenue range)"
				end
				if minRevenue > maxRevenue then
					minRevenue, maxRevenue = maxRevenue, minRevenue
				end
				local baseRevenue = math.random(math.floor(minRevenue), math.floor(maxRevenue))
				
				local gaveTool, toolOrError = pcall(function()
					return animalService:_giveAnimalTool(player, codeData.AnimalName, codeData.Rarity, {
						Level = 1,
						UpgradeLevel = 0,
						BaseRevenue = baseRevenue,
						Revenue = baseRevenue,
					}, {}, true)
				end)
				
				if not gaveTool then
					warn("[CodeService] Animal reward grant failed for code", code, ":", tostring(toolOrError))
					return false, "Couldn't grant reward right now, please try again"
				end

				if toolOrError then
					rewardDesc = codeData.Rarity .. " " .. codeData.AnimalName
				else
					return false, "Failed to give animal tool"
				end
			else
				return false, "Invalid rarity in code data"
			end
		else
			return false, "AnimalService not available"
		end
	elseif codeData.RewardType == "ChatTag" then
		local chatTags = stats:FindFirstChild("ChatTags")
		if not chatTags then
			chatTags = Instance.new("Folder")
			chatTags.Name = "ChatTags"
			chatTags.Parent = stats
		end
		local tag = Instance.new("StringValue")
		tag.Name = codeData.TagText
		tag.Value = codeData.TagColor
		tag.Parent = chatTags
		rewardDesc = "Exclusive Chat Tag: " .. codeData.TagText
	end

	-- 5. Mark as redeemed
	local val = Instance.new("BoolValue")
	val.Name = code
	val.Value = true
	val.Parent = redeemedFolder

	if codeData.MaxUsage ~= -1 then
		self:_incrementGlobalUsage(code)
	end

	return true, "Successfully redeemed! You got: " .. rewardDesc
end

function CodeService:Start()
	self._remote.OnServerInvoke = function(player, codeInput)
		local ok, success, message = xpcall(function()
			return self:RedeemCode(player, codeInput)
		end, debug.traceback)
		
		if not ok then
			warn("[CodeService] Error during redemption for", player and player.Name or "unknown", "with input", tostring(codeInput), ":", success)
			return false, "Server Error"
		end
		
		return success, message
	end
end

return CodeService
