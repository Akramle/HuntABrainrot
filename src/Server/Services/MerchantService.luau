local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local MerchantService = {
	Name = "MerchantService",
	Priority = 0,
}

local SELL_ALL_BUCKS_COST = 25500000
local SELL_ALL_DEVPRODUCT_ID = 3566049090

function MerchantService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetMerchantRemote()

	local assets = ServerStorage:WaitForChild("Assets", 10)
	local guis = assets and assets:WaitForChild("Gui", 10)
	self._guiTemplate = guis and guis:FindFirstChild("MerchantGui")
end

function MerchantService:Start()
	self._remote.OnServerEvent:Connect(function(player, action, ...)
		if action == "SellAnimal" then
			self:_sellHeldAnimal(player)
		elseif action == "SellAll" then
			self:_sellAllAnimals(player)
		elseif action == "UnlockSellAllBucks" then
			self:_unlockSellAllBucks(player)
		elseif action == "UnlockSellAllRBX" then
			self:_unlockSellAllRBX(player)
		elseif action == "CloseGui" then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local gui = playerGui:FindFirstChild("MerchantGui")
				if gui then
					gui:Destroy()
				end
			end
		end
	end)

	local purchaseService = self._runtime:GetService("PurchaseService")
	if purchaseService then
		purchaseService:RegisterProductHandler(SELL_ALL_DEVPRODUCT_ID, function(receiptInfo)
			local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
			if player then
				local stats = player:FindFirstChild("Stats")
				local merchantFolder = stats and stats:FindFirstChild("Merchant")
				local sellAllUnlocked = merchantFolder and merchantFolder:FindFirstChild("SellAllUnlocked")
				if sellAllUnlocked then
					sellAllUnlocked.Value = true
					self._runtime:GetService("SoundService"):PlayForPlayer(player, "Purchase", {})
					self._remote:FireClient(player, "SellSuccess", {
						SellType = "SellAllUnlock",
						Amount = 0,
					})
					self._remote:FireClient(player, "Refresh")
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end)
	end

	self:_setupMerchantPrompts()
end

function MerchantService:_setupMerchantPrompts()
	local function onMerchantAdded(part)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if not prompt then
			prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Talk to Merchant"
			prompt.ObjectText = "Merchant"
			prompt.HoldDuration = 0.5
			prompt.Parent = part
		end

		prompt.Triggered:Connect(function(player)
			local playerGui = player:FindFirstChild("PlayerGui")
			if not playerGui then return end

			if not playerGui:FindFirstChild("MerchantGui") and self._guiTemplate then
				local newGui = self._guiTemplate:Clone()
				newGui.Parent = playerGui
			end

			self._remote:FireClient(player, "OpenGui")
		end)
	end

	for _, part in ipairs(CollectionService:GetTagged("Merchant")) do
		onMerchantAdded(part)
	end
	CollectionService:GetInstanceAddedSignal("Merchant"):Connect(onMerchantAdded)
end

function MerchantService:_getFriendsBoost(player)
	local friendsCount = 0
	local players = game:GetService("Players"):GetPlayers()
	for _, otherPlayer in ipairs(players) do
		if otherPlayer ~= player then
			local success, isFriend = pcall(function()
				return player:IsFriendsWith(otherPlayer.UserId)
			end)
			if success and isFriend then
				friendsCount += 1
			end
		end
	end
	return friendsCount * 0.10
end

function MerchantService:_sellHeldAnimal(player)
	local character = player.Character
	local equippedAnimal = nil

	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and CollectionService:HasTag(child, "Animal") then
				equippedAnimal = child
				break
			end
		end
	end

	if not equippedAnimal then return end
	if equippedAnimal:GetAttribute("IsLuckyBlock") then return end

	local cost = equippedAnimal:GetAttribute("Cost") or 0
	if cost <= 0 then return end	equippedAnimal:Destroy()

	local friendsBoost = self:_getFriendsBoost(player)
	local finalCost = math.floor(cost * (1 + friendsBoost))

	-- Add Bucks
	local leaderstats = player:FindFirstChild("leaderstats")
	local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
	if bucks then
		bucks.Value += finalCost
	end

	self._runtime:GetService("SoundService"):PlayForPlayer(player, "Purchase", {})
	self._remote:FireClient(player, "SellSuccess", {
		SellType = "SellAnimal",
		Amount = finalCost,
	})
	self._remote:FireClient(player, "Refresh")
end

function MerchantService:_sellAllAnimals(player)
	local stats = player:FindFirstChild("Stats")
	local merchantFolder = stats and stats:FindFirstChild("Merchant")
	local sellAllUnlocked = merchantFolder and merchantFolder:FindFirstChild("SellAllUnlocked")
	if not sellAllUnlocked or not sellAllUnlocked.Value then return end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local totalBucks = 0
	for _, tool in ipairs(backpack:GetChildren()) do
		if CollectionService:HasTag(tool, "Animal") and not tool:GetAttribute("IsLuckyBlock") then
			local cost = tool:GetAttribute("Cost") or 0
			totalBucks += cost
			tool:Destroy()
		end
	end

	local character = player.Character
	if character then
		for _, tool in ipairs(character:GetChildren()) do
			if CollectionService:HasTag(tool, "Animal") and not tool:GetAttribute("IsLuckyBlock") then
				local cost = tool:GetAttribute("Cost") or 0
				totalBucks += cost
				tool:Destroy()
			end
		end
	end

	if totalBucks > 0 then
		local friendsBoost = self:_getFriendsBoost(player)
		local finalBucks = math.floor(totalBucks * (1 + friendsBoost))

		local leaderstats = player:FindFirstChild("leaderstats")
		local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
		if bucks then
			bucks.Value += finalBucks
		end
		self._runtime:GetService("SoundService"):PlayForPlayer(player, "Purchase", {})
		self._remote:FireClient(player, "SellSuccess", {
			SellType = "SellAll",
			Amount = finalBucks,
		})
	end

	self._remote:FireClient(player, "Refresh")
end

function MerchantService:_unlockSellAllBucks(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
	if not bucks or bucks.Value < SELL_ALL_BUCKS_COST then return end

	local stats = player:FindFirstChild("Stats")
	local merchantFolder = stats and stats:FindFirstChild("Merchant")
	local sellAllUnlocked = merchantFolder and merchantFolder:FindFirstChild("SellAllUnlocked")
	if not sellAllUnlocked or sellAllUnlocked.Value then return end

	bucks.Value -= SELL_ALL_BUCKS_COST
	sellAllUnlocked.Value = true
	
	self._runtime:GetService("SoundService"):PlayForPlayer(player, "Purchase", {})
	self._remote:FireClient(player, "SellSuccess", {
		SellType = "SellAllUnlock",
		Amount = 0,
	})
	self._remote:FireClient(player, "Refresh")
end

function MerchantService:_unlockSellAllRBX(player)
	MarketplaceService:PromptProductPurchase(player, SELL_ALL_DEVPRODUCT_ID)
end

return MerchantService
