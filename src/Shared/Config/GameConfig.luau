local GameConfig = {
	Remotes = {
		FolderName = "RuntimeRemotes",
	},
	-- Simulator Rarity Settings (Top and Bottom colors for gradients)
	RaritySettings = {
		Common    = { Top = Color3.fromRGB(200, 200, 200), Bottom = Color3.fromRGB(130, 130, 130), Thickness = 1 },
		Uncommon  = { Top = Color3.fromRGB(100, 255, 100), Bottom = Color3.fromRGB(0, 180, 0),     Thickness = 1 },
		Rare      = { Top = Color3.fromRGB(0, 220, 255),   Bottom = Color3.fromRGB(0, 120, 200),   Thickness = 1 },
		Epic      = { Top = Color3.fromRGB(166, 91, 222),  Bottom = Color3.fromRGB(100, 40, 150),  Thickness = 1 },
		Legendary = { Top = Color3.fromRGB(255, 220, 50),  Bottom = Color3.fromRGB(200, 140, 0),   Thickness = 2 },
		Mythical  = { Top = Color3.fromRGB(255, 60, 60),   Bottom = Color3.fromRGB(180, 0, 0),     Thickness = 2 },
		Devine    = { Top = Color3.fromRGB(180, 50, 255),  Bottom = Color3.fromRGB(100, 0, 180),   Thickness = 3 },
		Void      = { Top = Color3.fromRGB(30, 30, 30),    Bottom = Color3.fromRGB(10, 10, 10),    Thickness = 3 }
	},
};
return table.freeze(GameConfig);
