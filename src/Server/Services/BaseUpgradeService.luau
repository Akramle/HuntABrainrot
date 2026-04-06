local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

local BaseUpgradeService = {
	Name = "BaseUpgradeService",
	Priority = -45,
}

local CEILING_Y_POSITIONS = {
	[1] = 17.973,
	[2] = 33.925,
	[3] = 49.007,
	[4] = 65.095,
	[5] = 81.183,
}

function BaseUpgradeService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
end

function BaseUpgradeService:_setBaseLevelState(base: Model, currentLevel: number, animateLevel: number?)
	local ceiling = base:FindFirstChild("Ceiling")
	if ceiling then
		local targetY = CEILING_Y_POSITIONS[currentLevel] or CEILING_Y_POSITIONS[5]
		ceiling:PivotTo(CFrame.new(ceiling:GetPivot().Position.X, targetY, ceiling:GetPivot().Position.Z) * ceiling:GetPivot().Rotation)
	end

	for levelNum = 1, 5 do
		local levelFolder = base:FindFirstChild(tostring(levelNum))
		if levelFolder then
			local isUnlocked = levelNum <= currentLevel
			local upgradeProp = levelFolder:FindFirstChild("Upgrade")
			local shouldShowUpgrade = false

			if upgradeProp then
				if isUnlocked and levelNum < currentLevel then
					-- Already surpassed this level, hide its upgrade prompt
					shouldShowUpgrade = false
				elseif isUnlocked and levelNum == currentLevel then
					-- This is the current max level, show its upgrade prompt (if there's a next level)
					if levelNum < 5 then
						shouldShowUpgrade = true
						self:_setupUpgradePrompt(base, levelFolder, levelNum)
					else
						shouldShowUpgrade = false
					end
				else
					-- Locked level, hide upgrade prompt
					shouldShowUpgrade = false
				end
			end

			-- Set visibility/collision
			if isUnlocked then
				-- It's unlocked. If it's the one we just bought, animate it.
				if animateLevel == levelNum then
					self:_animateUnlock(levelFolder)
				else
					-- Just make sure it's fully visible and solid
					for _, part in ipairs(levelFolder:GetDescendants()) do
						-- If part is inside the Upgrade prop, we'll handle it separately below
						if upgradeProp and part:IsDescendantOf(upgradeProp) then continue end
						if part:FindFirstAncestor("Animal") then continue end
						
						if part:IsA("BasePart") then
							part.CanCollide = true
							if part.Name == "Glass" then
								part.Transparency = 0.55
							elseif part.Name == "Placer" then
								part.Transparency = 1
							else
								part.Transparency = 0
							end
						elseif part:IsA("SurfaceGui") then
							part.Enabled = true
						elseif part:IsA("Texture") then
							part.Transparency = 0.8
						end
					end
				end
			else
				-- Locked level. Make invisible and non-colliding
				for _, part in ipairs(levelFolder:GetDescendants()) do
					if upgradeProp and part:IsDescendantOf(upgradeProp) then continue end
					if part:FindFirstAncestor("Animal") then continue end
					
					if part:IsA("BasePart") then
						part.CanCollide = false
						part.Transparency = 1
					elseif part:IsA("SurfaceGui") or part:IsA("BillboardGui") or part:IsA("ProximityPrompt") then
						part.Enabled = false
					elseif part:IsA("Texture") then
						part.Transparency = 1
					end
				end
			end
			
			-- Apply Upgrade Prop visibility (Force hide on server for everyone)
			if upgradeProp then
				if shouldShowUpgrade then
					self:_setupUpgradePrompt(base, levelFolder, levelNum)
				end

				for _, part in ipairs(upgradeProp:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = shouldShowUpgrade
						if shouldShowUpgrade then
							if part.Name == "Glass" then
								part.Transparency = 0.55
							elseif part.Name == "Placer" then
								part.Transparency = 1
							else
								part.Transparency = 0
							end
						else
							part.Transparency = 1
						end
					elseif part:IsA("SurfaceGui") or part:IsA("BillboardGui") or part:IsA("ProximityPrompt") then
						part.Enabled = shouldShowUpgrade
					elseif part:IsA("Texture") or part:IsA("Decal") then
						part.Transparency = shouldShowUpgrade and 0 or 1
					end
				end
			end
		end
	end
end

function BaseUpgradeService:_animateUnlock(levelFolder: Instance)
	local parts = levelFolder:GetDescendants()
	
	-- We can play the pop animation by playing smoke particles at random parts, or central part
	local smokeTemplate = ReplicatedStorage:FindFirstChild("Smoke")
	
	local centerParts = {}
	for _, part in ipairs(parts) do
		if part:FindFirstAncestor("Animal") then continue end
		
		if part:IsA("BasePart") then
			part.CanCollide = true
			if part.Name == "Glass" then
				part.Transparency = 0.55
			elseif part.Name == "Placer" then
				part.Transparency = 1
			else
				part.Transparency = 0
			end
			
			if part.Size.Magnitude > 10 then
				table.insert(centerParts, part)
			end
		elseif part:IsA("SurfaceGui") then
			part.Enabled = true
		elseif part:IsA("Texture") then
			part.Transparency = 0.8
		end
	end
	
	-- Play smoke effect
	if smokeTemplate and smokeTemplate:IsA("BasePart") then
		for _, target in ipairs(centerParts) do
			if math.random() > 0.3 then continue end -- Don't spawn too many smokes
			local smoke = smokeTemplate:Clone()
			smoke.CFrame = target.CFrame
			smoke.Parent = Workspace
			for _, emitter in ipairs(smoke:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then
					emitter:Emit(20)
				end
			end
			game:GetService("Debris"):AddItem(smoke, 2)
		end
	end
	
	-- Sound effect
	local soundService = self._runtime:GetService("SoundService")
	if soundService then
		soundService:PlayOnServer("AnimalPlaced") -- Using a generic pop sound
	end
end

function BaseUpgradeService:_setupUpgradePrompt(base: Model, levelFolder: Instance, currentLevel: number)
	local upgradeProp = levelFolder:FindFirstChild("Upgrade")
	if not upgradeProp then return end

	local nextLevel = currentLevel + 1
	local upgradeConfig = self._config.BaseUpgrades and self._config.BaseUpgrades[tostring(nextLevel)]
	if not upgradeConfig then return end

	local screen = upgradeProp:FindFirstChild("Screen")
	local surfaceGui = screen and screen:FindFirstChild("SurfaceGui")
	local frame = surfaceGui and surfaceGui:FindFirstChild("Frame")
	if not surfaceGui then return end

	local priceLabel = frame and frame:FindFirstChild("price")
	local rebirthsLabel = surfaceGui:FindFirstChild("Rebirths")
	local btn = surfaceGui:FindFirstChild("btn")

	if priceLabel and priceLabel:IsA("TextLabel") then
		priceLabel.Text = "$" .. NumberFormatter:Format(upgradeConfig.Price, "Letters")
	end

	if rebirthsLabel and rebirthsLabel:IsA("TextLabel") then
		if upgradeConfig.Rebirths > 0 then
			rebirthsLabel.Text = "(" .. tostring(upgradeConfig.Rebirths) .. " Rebirths)"
			rebirthsLabel.Visible = true
		else
			rebirthsLabel.Visible = false
		end
	end

	if btn and btn:IsA("GuiButton") then
		-- Bound on client side instead
	end
end

function BaseUpgradeService:_tryPurchaseUpgrade(player: Player, base: Model, currentLevel: number, upgradeConfig: table)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stats = player:FindFirstChild("Stats")
	if not leaderstats or not stats then return end

	local bucks = leaderstats:FindFirstChild("Bucks")
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	local baseUpgradeVal = stats:FindFirstChild("BaseUpgrade")

	if not bucks or not rebirths or not baseUpgradeVal then return end

	-- Validate
	if baseUpgradeVal.Value ~= currentLevel then return end -- already upgraded or out of sync
	if rebirths.Value < upgradeConfig.Rebirths then
		local notificationService = self._runtime:GetService("NotificationService")
		if notificationService then
			notificationService:NotifyPlayer(player, "You need " .. upgradeConfig.Rebirths .. " Rebirths!", "Warning")
		end
		return
	end

	if bucks.Value < upgradeConfig.Price then
		local notificationService = self._runtime:GetService("NotificationService")
		if notificationService then
			notificationService:NotifyPlayer(player, "Not enough Bucks!", "Warning")
		end
		return
	end

	-- Purchase
	bucks.Value -= upgradeConfig.Price
	baseUpgradeVal.Value = currentLevel + 1

	-- Apply visually
	self:_setBaseLevelState(base, baseUpgradeVal.Value, baseUpgradeVal.Value)

	-- Play purchase sound
	local soundService = self._runtime:GetService("SoundService")
	if soundService then
		soundService:PlayForPlayer(player, "Purchase", {randomPitch = true})
		soundService:PlayForPlayer(player, "AnimalUpgrade", {randomPitch = true})
	end

	-- Particles
	local effectsRemote = self._runtime.Remotes:GetEffectsRemote()
	if effectsRemote then
		effectsRemote:FireClient(player, "ConfettiBurst", { amount = 80 })
	end
end

function BaseUpgradeService:ApplyPlayerBase(player: Player, base: Model)
	local stats = player:WaitForChild("Stats", 5)
	if not stats then return end
	
	local baseUpgradeVal = stats:WaitForChild("BaseUpgrade", 5)
	if not baseUpgradeVal then return end

	local function updateBase()
		local currentLevel = baseUpgradeVal.Value
		self:_setBaseLevelState(base, currentLevel)
	end

	-- Apply immediately
	updateBase()

	-- Also listen for changes (like when DataService finishes loading save data, or a rebirth resets it)
	-- We only need to store the connection if we intend to clean it up, but since it's tied to the player's stat value which is destroyed on leave, it's fine.
	baseUpgradeVal.Changed:Connect(updateBase)
end

function BaseUpgradeService:Start()
	local remote = self._runtime.Remotes:GetBaseUpgradeRemote()
	if remote then
		remote.OnServerEvent:Connect(function(player, requestedLevel)
			if type(requestedLevel) ~= "number" then return end
			
			local baseService = self._runtime:GetService("BaseService")
			if not baseService then return end
			
			local base = baseService:GetPlayerBase(player)
			if not base then return end
			
			local stats = player:FindFirstChild("Stats")
			local baseUpgradeVal = stats and stats:FindFirstChild("BaseUpgrade")
			if not baseUpgradeVal then return end
			
			local currentLevel = baseUpgradeVal.Value
			if requestedLevel ~= currentLevel + 1 then return end
			
			local upgradeConfig = self._config.BaseUpgrades and self._config.BaseUpgrades[tostring(requestedLevel)]
			if not upgradeConfig then return end
			
			self:_tryPurchaseUpgrade(player, base, currentLevel, upgradeConfig)
		end)
	end

	local baseService = self._runtime:GetService("BaseService")
	if baseService then
		local originalAssign = baseService._assignBase
		baseService._assignBase = function(selfBase, player)
			originalAssign(selfBase, player)
			
			local base = selfBase:GetPlayerBase(player)
			if base then
				self:ApplyPlayerBase(player, base)
			end
		end

		-- Apply to players who already got assigned a base
		for _, player in ipairs(Players:GetPlayers()) do
			local base = baseService:GetPlayerBase(player)
			if base then
				self:ApplyPlayerBase(player, base)
			end
		end
	end
end

return BaseUpgradeService
