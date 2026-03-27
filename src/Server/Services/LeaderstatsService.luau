local Players = game:GetService("Players")

local LeaderstatsService = {
	Name = "LeaderstatsService",
	Priority = -80,
}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder :: Folder
end

local function getOrCreateValue(parent: Instance, className: string, name: string)
	local value = parent:FindFirstChild(name)
	if value == nil then
		value = Instance.new(className)
		value.Name = name
		value.Parent = parent
	end

	return value
end

function LeaderstatsService:_setupPlayer(player: Player)
	local leaderstats = getOrCreateFolder(player, "leaderstats")
	local bucks = getOrCreateValue(leaderstats, "IntValue", "Bucks")
	bucks.Value = bucks.Value or 0

	local stats = getOrCreateFolder(player, "Stats")
	local multiplier = getOrCreateValue(stats, "NumberValue", "Multiplier")
	if multiplier.Value == 0 then
		multiplier.Value = 1
	end

	-- Swords setup
	local swords = getOrCreateFolder(stats, "Swords")
	local currentSword = getOrCreateValue(swords, "StringValue", "CurrentSword")
	if currentSword.Value == "" then
		currentSword.Value = "Wooden Sword"
	end

	local ownedSwords = getOrCreateFolder(stats, "OwnedSwords")
	local defaultOwnedSword = ownedSwords:FindFirstChild("Wooden Sword")
	if defaultOwnedSword == nil then
		local woodenSwordVal = getOrCreateValue(ownedSwords, "IntValue", "Wooden Sword")
		woodenSwordVal.Value = 1
	end

	-- Upgrades setup
	local upgrades = getOrCreateFolder(stats, "Upgrades")
	local walkspeedLevel = getOrCreateValue(upgrades, "IntValue", "Walkspeed")
	if walkspeedLevel.Value == 0 then
		walkspeedLevel.Value = 1
	end

	-- Unlocked Areas setup
	local unlockedAreas = getOrCreateFolder(stats, "UnlockedAreas")
	local plains = getOrCreateValue(unlockedAreas, "BoolValue", "Plains")
	plains.Value = true -- Plains is always unlocked by default

	if player:GetAttribute("Damage") == nil then
		player:SetAttribute("Damage", 0)
	end
	if player:GetAttribute("IsArmed") == nil then
		player:SetAttribute("IsArmed", false)
	end
	if player:GetAttribute("HasAnimal") == nil then
		player:SetAttribute("HasAnimal", false)
	end
end

function LeaderstatsService:Start()
	for _, player in ipairs(Players:GetPlayers()) do
		self:_setupPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self:_setupPlayer(player)
	end)
end

return LeaderstatsService
