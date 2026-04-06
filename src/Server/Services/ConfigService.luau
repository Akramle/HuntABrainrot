local Players = game:GetService("Players")

local ConfigService = {
	Name = "ConfigService",
	Priority = -1000, -- Initialize first
}

function ConfigService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
end

function ConfigService:Start()
	local configRemote = self._runtime.Remotes:GetConfigRemote()
	
	configRemote.OnServerInvoke = function(player)
		-- Provide a sanitized version of the config for the client
		-- Only include what the client ACTUALLY needs for UI/Logic
		return {
			Upgrades = self._config.Upgrades,
			Monetization = self._config.Monetization,
			Sounds = self._config.Sounds,
			Effects = self._config.Effects,
			Weapons = self._config.Weapons,
			Combat = self._config.Combat,
			Inventory = self._config.Inventory,
			Gear = self._config.Gear,
			Rebirth = self._config.Rebirth,
			BaseUpgrades = self._config.BaseUpgrades,
			Animals = {
				RarityOrder = self._config.Animals.RarityOrder,
				Leveling = self._config.Animals.Leveling,
			}
		}
	end
end

return ConfigService
