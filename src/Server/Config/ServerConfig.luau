local ServerConfig = {
	Remotes = {
		FolderName = "RuntimeRemotes",
		EffectsEvent = "GameplayEffects",
		FakeToolEvent = "FakeToolAction",
		InventoryLayoutEvent = "InventoryLayoutSync",
		StealPromptEvent = "StealAnimalPrompt",
		SoundEvent = "SoundAction",
		AdminEvent = "AdminAction",
		HidingEvent = "HidingAction",
		UpgradeEvent = "UpgradeEvent",
		AreaUnlockEvent = "AreaUnlockAction",
		ConfigEvent = "GetConfigInfo",
		AnnouncementEvent = "AnnouncementAction",
		EventEvent = "EventAction",
		CodeEvent = "CodeRedeemAction",
		NotificationEvent = "NotificationAction",
		GearEvent = "GearAction"
	},
	Admins = {
		[1] = true, -- Studio User
		[729308194] = true, -- Example Admin ID
	},
	Upgrades = {
		Swords = {
			["Wooden Sword"] = {
				MaxLevel = 10,
				BaseCost = 50,
				CostMultiplier = 1.5,
				DamageBonusPerLevel = 0.85, 
				AllowedRarities = {"Common", "Uncommon", "Rare", "Legendary", "Mythical", "Devine"}
			},
			["Stone Sword"] = {
				MaxLevel = 10,
				BaseCost = 150,
				CostMultiplier = 1.6,
				DamageBonusPerLevel = 1.8,
				AllowedRarities = {"Common", "Uncommon", "Rare"}
			},
			["Default"] = {
				MaxLevel = 10,
				BaseCost = 100,
				CostMultiplier = 1.5,
				DamageBonusPerLevel = 0.35,
				AllowedRarities = {"Common"}
			}
		},
		Walkspeed = {
			MaxLevel = 10,
			BaseCost = 100,
			CostMultiplier = 2,
			SpeedBonusPerLevel = 2
		}
	},
	Monetization = {
		StealAnimalProductId = 3554401633
	},
	Sounds = {
		AnimalHit = "140604838213617",
		AnimalDeath = "109921439409050",
		AnimalPickup = "107261392908541",
		AnimalPlaced = "140379755234888",
		AnimalPickedUpFromBase = "134602992766192",
		AnimalStolen = "139965549997439",
		AnimalUpgrade = "76531688808018",
		CashCollected = "135428907715078",
		DivineSpawn = "138332700851497"
	},
	Effects = {
		NearbyRadius = 120,
		Names = {
			AnimalHit = "AnimalHit",
			AnimalDeath = "AnimalDeath",
			AnimalPickup = "AnimalPickup",
			AnimalUpgrade = "AnimalUpgrade",
			PadCollected = "PadCollected",
			AnimalSpawn = "AnimalSpawn",
			AnimalDespawn = "AnimalDespawn",
			ShrineHit = "ShrineHit",
			PlayerUpgrade = "PlayerUpgrade",
			AnimalDelivered = "AnimalDelivered"
		}
	},
	Weapons = {
		Tag = "sword",
		DefaultDamage = 1
	},
	Combat = {
		AttackCooldown = 0.65,
		HitAnimationId = "rbxassetid://134122126546788",
		HoldAnimationId = "rbxassetid://123080179439407"
	},
	Inventory = {
		HotbarSlots = 6
	},
	Data = {
		StoreName = "CaptureBrainRots_PlayerData_v1.4.3",
		AutoSaveInterval = 120
	},
	Events = {
		EventInterval = 60, -- How often (seconds) the server checks to start a new event
		
		Rain = {
			Chance = 0.3, -- 30% chance per interval
			DurationRange = {40, 70},
			MutationChancePerSecond = 0.25, -- 25% chance per second
		},
		
		Shrine = {
			Chance = 0.005, -- 15% chance per interval
			DurationRange = {50, 90},
			MutationChancePerSecond = 0.1, -- 40% chance per second
			ShrineDamageRange = {5, 15}, -- Damage to wild animals
			PulseInterval = 2, -- Visual pulse speed
		},

		Tornado = {
			Chance = 0.05, -- 5% chance per interval
			DurationRange = {60, 100},
			TornadosPerArea = {2, 5},
			MutationChanceOnTouch = 0.5,
			PlayerPushForce = 100,
		},

		Abduction = {
			Chance = 0.04, -- 4% chance
			DurationRange = {80, 120},
			UFOsPerArea = {1, 3},
			MutationChance = 0.7,
			
			-- Movement
			TravelSpeed = 10,
			CurveIntensity = 15,
			ModelFrontOffset = 90, -- Degrees to rotate so the +X axis (Right) faces forward
			
			-- Abduction
			ScanRadius = 6,
			LiftDuration = 5,
		},
	},
	Spawning = {
		MaxAnimalsPerArea = 30,
		InitialSpawnCount = 10,
		SpawnTimeMin = 5,
		SpawnTimeMax = 15,
		ClearanceBuffer = 4,
		WildDespawnTimeMin = 30,
		WildDespawnTimeMax = 120
	},
	Animals = {
		RarityOrder = {
			"Common",
			"Uncommon",
			"Rare",
			"Legendary",
			"Mythical",
			"Devine"
		},
		Leveling = {
			MinLevel = 1,
			MaxLevel = 50,
			WeightPower = 2.35,
			Alpha = 1.1
		},
		Mutations = {
			Gold = 0.05 -- 1%
		},
		Stats = {
			Common = {
				Health = {10, 80},
				Cost = {20, 120},
				Revenue = {1, 6}
			},
			Uncommon = {
				Health = {90, 300},
				Cost = {150, 700},
				Revenue = {8, 40}
			},
			Rare = {
				Health = {350, 1200},
				Cost = {900, 4000},
				Revenue = {60, 400}
			},
			Legendary = {
				Health = {1400, 5000},
				Cost = {5000, 18000},
				Revenue = {800, 8000}
			},
			Mythical = {
				Health = {6000, 15000},
				Cost = {25000, 90000},
				Revenue = {20000, 250000}
			},
			Devine = {
				Health = {18000, 45000},
				Cost = {150000, 500000},
				Revenue = {1000000, 7000000}
			}
		},
		SpawnPools = {
			Common = {
				{name = "Common", chance = 80},
				{name = "Uncommon", chance = 10},
				{name = "Rare", chance = 8},
				{name = "Legendary", chance = 1.5},
				{name = "Mythical", chance = 0.3},
				{name = "Devine", chance = 0.2}
			},
			Uncommon = {
				{name = "Uncommon", chance = 80},
				{name = "Common", chance = 10},
				{name = "Rare", chance = 8},
				{name = "Legendary", chance = 1.5},
				{name = "Mythical", chance = 0.3},
				{name = "Devine", chance = 0.2}
			},
			Rare = {
				{name = "Rare", chance = 80},
				{name = "Uncommon", chance = 10},
				{name = "Common", chance = 8},
				{name = "Legendary", chance = 1.5},
				{name = "Mythical", chance = 0.3},
				{name = "Devine", chance = 0.2}
			},
			Legendary = {
				{name = "Legendary", chance = 80},
				{name = "Rare", chance = 10},
				{name = "Uncommon", chance = 8},
				{name = "Common", chance = 1.5},
				{name = "Mythical", chance = 0.3},
				{name = "Devine", chance = 0.2}
			},
			Mythical = {
				{name = "Mythical", chance = 80},
				{name = "Legendary", chance = 10},
				{name = "Rare", chance = 8},
				{name = "Uncommon", chance = 1.5},
				{name = "Common", chance = 0.3},
				{name = "Devine", chance = 0.2}
			}
		}
	},
	Codes = {
		["RELEASE"] = {
			RewardType = "Bucks",
			Amount = 500,
			MaxUsage = 1000000,
			Expiration = "2026-01-01",
		},
		["BRAINROT"] = {
			RewardType = "Animal",
			Rarity = "Rare",
			AnimalName = "Extinct Ballerina",
			MaxUsage = 5000,
			Expiration = "2026-12-31",
		},
		["BOOST"] = {
			RewardType = "Multiplier",
			Amount = 2,
			Duration = 600, -- 10 minutes
			MaxUsage = -1, -- Unlimited
			Expiration = "2025-12-31",
		},
		["VETERAN"] = {
			RewardType = "ChatTag",
			TagText = "VETERAN",
			TagColor = "#FFAA00",
			MaxUsage = -1,
			Expiration = "lifetime",
		}
	},

	Gear = {
		["Slap Hand"] = {
			Price = 800,
			Cooldown = 0.8,
			PushForce = 60,
		},
		["Tung Bat"] = {
			Price = 1500,
			Cooldown = 0.5,
			PushForce = 110,
		},
		["Speed Coil"] = {
			Price = 8700,
			SpeedBoost = 25,
		},
		["Gravity Coil"] = {
			Price = 15200,
			GravityMultiplier = 0.81,
		}
	}
};
return table.freeze(ServerConfig);
