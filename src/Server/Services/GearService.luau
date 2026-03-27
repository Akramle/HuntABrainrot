local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local GearService = {
	Name = "GearService",
	Priority = -25,
}

local function getDistance(part1, part2)
	if not part1 or not part2 then return math.huge end
	return (part1.Position - part2.Position).Magnitude
end

function GearService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetGearRemote()
	self._guiTemplate = ServerStorage:WaitForChild("Assets"):WaitForChild("Gui"):WaitForChild("GearGui")
	-- Corrected path based on user hint
	self._gearFolder = ReplicatedStorage:WaitForChild("Tools"):WaitForChild("Gear")
	self._cooldowns = {}
end

function GearService:_handleGearShopPrompt(prompt: ProximityPrompt, player: Player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	
	local shopPart = prompt.Parent
	if not shopPart or not shopPart:IsA("BasePart") then return end
	
	-- Verify distance
	if getDistance(rootPart, shopPart) > (prompt.MaxActivationDistance + 5) then
		warn("[GearService] Player " .. player.Name .. " is too far from GearShop.")
		return
	end
	
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return end
	
	-- If they already have one, don't spawn another one
	if playerGui:FindFirstChild("GearGui") then return end
	
	local newGui = self._guiTemplate:Clone()
	newGui.Parent = playerGui
	
	-- Tell the client to hook it up
	self._remote:FireClient(player, "BindGui")
end

function GearService:Start()
	-- Listen for prompt triggers
	for _, shop in ipairs(CollectionService:GetTagged("GearShop")) do
		local prompt = shop:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				self:_handleGearShopPrompt(prompt, player)
			end)
		end
	end

	CollectionService:GetInstanceAddedSignal("GearShop"):Connect(function(shop)
		local prompt = shop:FindFirstChildWhichIsA("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(player)
				self:_handleGearShopPrompt(prompt, player)
			end)
		end
	end)
	
	-- Handle remote requests from Client
	self._remote.OnServerEvent:Connect(function(player, action, gearName, targetCharacter)
		local leaderstats = player:FindFirstChild("leaderstats")
		local bucks = leaderstats and leaderstats:FindFirstChild("Bucks")
		
		if action == "BuyGear" then
			if not leaderstats or not bucks then return end
			if not gearName or type(gearName) ~= "string" then return end
			
			local gearConfig = self._config.Gear[gearName]
			if not gearConfig then
				warn("[GearService] No config found for gear: " .. tostring(gearName))
				return
			end
			
			-- Check if player already has it
			local hasGear = false
			local backpack = player:FindFirstChild("Backpack")
			local character = player.Character
			
			if (backpack and backpack:FindFirstChild(gearName)) or (character and character:FindFirstChild(gearName)) then
				hasGear = true
			end
			
			if hasGear then
				self._runtime:GetService("NotificationService"):NotifyPlayer(player, "You already have this gear!", "Warning")
				return
			end
			
			local cost = gearConfig.Price
			if bucks.Value >= cost then
				local gearTemplate = self._gearFolder:FindFirstChild(gearName)
				if not gearTemplate then
					warn("[GearService] Gear tool not found in " .. self._gearFolder:GetFullName() .. ": " .. gearName)
					return
				end
				
				bucks.Value -= cost
				
				local newGear = gearTemplate:Clone()
				newGear.Parent = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack")
				
				-- Play sound
				self._runtime:GetService("SoundService"):PlayForPlayer(player, "AnimalUpgrade", {randomPitch = true})

				-- Trigger effects
				local effectsRemote = self._runtime.Remotes:GetEffectsRemote()
				if effectsRemote then
					effectsRemote:FireClient(player, "ConfettiBurst", { amount = 100 })
				end
				
				self._runtime:GetService("NotificationService"):NotifyPlayer(player, "Purchased " .. gearName .. "!", "Success")
			else
				self._runtime:GetService("NotificationService"):NotifyPlayer(player, "Not enough Bucks!", "Warning")
			end
			
		elseif action == "CloseGui" then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				local gui = playerGui:FindFirstChild("GearGui")
				if gui then
					gui:Destroy()
				end
			end
		elseif action == "EquipGear" then
			if not gearName or type(gearName) ~= "string" then return end
			local gearConfig = self._config.Gear[gearName]
			if not gearConfig then return end
			
			if gearName == "Speed Coil" then
				player:SetAttribute("GearWalkspeedBonus", gearConfig.SpeedBoost)
				local upgradeService = self._runtime:GetService("UpgradeService")
				if upgradeService then upgradeService:UpdatePlayerWalkspeed(player) end
			end
		elseif action == "UnequipGear" then
			if not gearName or type(gearName) ~= "string" then return end
			if gearName == "Speed Coil" then
				player:SetAttribute("GearWalkspeedBonus", 0)
				local upgradeService = self._runtime:GetService("UpgradeService")
				if upgradeService then upgradeService:UpdatePlayerWalkspeed(player) end
			end
		elseif action == "ActivateGear" then
			if not gearName or type(gearName) ~= "string" then return end
			local gearConfig = self._config.Gear[gearName]
			if not gearConfig or not gearConfig.Cooldown then return end

			local now = os.clock()
			local lastUse = self._cooldowns[player] and self._cooldowns[player][gearName] or 0
			if now - lastUse < gearConfig.Cooldown then return end

			if not self._cooldowns[player] then self._cooldowns[player] = {} end
			self._cooldowns[player][gearName] = now

			-- Hit Logic
			if targetCharacter and targetCharacter:IsA("Model") and targetCharacter:FindFirstChild("HumanoidRootPart") then
				local victimRoot = targetCharacter.HumanoidRootPart
				local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if playerRoot and (playerRoot.Position - victimRoot.Position).Magnitude < 15 then
					-- Apply Impulse
					local direction = (victimRoot.Position - playerRoot.Position).Unit
					if direction.Y < 0 then direction = Vector3.new(direction.X, 0, direction.Z).Unit end
					-- Add a bit of upward force
					direction = (direction + Vector3.new(0, 0.5, 0)).Unit

					-- SAFETY: Only call SetNetworkOwner if not anchored
					if not victimRoot.Anchored then
						pcall(function()
							victimRoot:SetNetworkOwner(nil) -- Take ownership to apply force reliably
						end)
						victimRoot:ApplyImpulse(direction * gearConfig.PushForce * victimRoot.AssemblyMass)
						task.delay(1, function()
							if victimRoot.Parent then
								local victimPlayer = Players:GetPlayerFromCharacter(targetCharacter)
								if victimPlayer and not victimRoot.Anchored then
									pcall(function()
										victimRoot:SetNetworkOwner(victimPlayer)
									end)
								end
							end
						end)
					end

					-- Play Sound
					local tool = player.Character:FindFirstChild(gearName)
					local handle = tool and tool:FindFirstChild("Handle")
					local hitSound = handle and handle:FindFirstChild("Hit")
					if hitSound and hitSound:IsA("Sound") then
						hitSound:Play()
					end
				end
			else
				-- Miss Sound for Tung Bat
				if gearName == "Tung Bat" then
					local tool = player.Character:FindFirstChild(gearName)
					local handle = tool and tool:FindFirstChild("Handle")
					local missSound = handle and handle:FindFirstChild("Miss")
					if missSound and missSound:IsA("Sound") then
						missSound:Play()
					end
				end
			end
		end
	end)
end

return GearService
