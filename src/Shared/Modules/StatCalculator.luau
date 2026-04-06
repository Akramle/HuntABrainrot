local StatCalculator = {}

function StatCalculator.CalculateSwordDamage(baseDamage: number, level: number, swordName: string, config: table)
	local swordConfig = (config.Upgrades and config.Upgrades.Swords and config.Upgrades.Swords[swordName]) 
		or (config.Upgrades and config.Upgrades.Swords and config.Upgrades.Swords["Default"])
	
	local multiplier = if swordConfig then (swordConfig.DamageBonusPerLevel or 0.35) else 0.35
	return math.floor(baseDamage * (1 + ((level - 1) * multiplier)))
end

function StatCalculator.CalculateWalkspeed(level: number, config: table, gearBonus: number?)
	local baseSpeed = 24
	local wsConfig = config.Upgrades and config.Upgrades.Walkspeed
	local bonusPerLevel = if wsConfig then (wsConfig.SpeedBonusPerLevel or 2) else 2
	local bonus = gearBonus or 0
	return baseSpeed + ((level - 1) * bonusPerLevel) + bonus
end

function StatCalculator.CalculateAnimalStats(baseRevenue: number, level: number, upgradeLevel: number, mutations: {string: boolean}, config: table)
	local alpha = tonumber(config.Animals.Leveling.Alpha) or 1
	local totalLevel = level + upgradeLevel
	
	-- 1. Calculate base revenue scaled by level
	local scaledRevenue = math.floor((baseRevenue * (totalLevel ^ alpha)) + 0.5)
	
	-- 2. Apply mutation multipliers
	local multiplier = 1
	if mutations.IsGold then multiplier *= 4 end
	if mutations.IsMalevolent then multiplier *= 10 end
	if mutations.IsSoaked then multiplier *= 1.5 end
	if mutations.IsTwistborn then multiplier *= 4 end
	if mutations.IsAlien then multiplier *= 12 end
	
	local finalRevenue = math.floor(scaledRevenue * multiplier)
	local finalCost = finalRevenue * 4
	
	-- 3. Calculate next level revenue for upgrade cost
	local nextTotalLevel = totalLevel + 1
	local nextScaledRevenue = math.floor((baseRevenue * (nextTotalLevel ^ alpha)) + 0.5)
	local nextFinalRevenue = math.floor(nextScaledRevenue * multiplier)
	local upgradeCost = nextFinalRevenue * 4
	
	return {
		Revenue = math.max(1, finalRevenue),
		Cost = math.max(1, finalCost),
		UpgradeCost = math.max(1, upgradeCost)
	}
end

function StatCalculator.GetTemplateBaseDamage(template: Instance, defaultDamage: number): number
	if not template then return defaultDamage end
	local damageValue = template:FindFirstChild("Damage")
	if damageValue and damageValue:IsA("NumberValue") then
		return damageValue.Value
	end
	local damageAttr = template:GetAttribute("Damage")
	if typeof(damageAttr) == "number" then
		return damageAttr
	end
	return defaultDamage
end

return StatCalculator
