local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local GiftService = {
	Name = "GiftService",
	Priority = 0,
}

function GiftService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._remote = runtime.Remotes:GetGiftRemote()
	self._animalService = runtime:GetService("AnimalService")
	self._notificationService = runtime:GetService("NotificationService")
	
	self._guiTemplate = ServerStorage:WaitForChild("Assets"):WaitForChild("Gui"):WaitForChild("GiftGui")
	
	self._activeGifts = {} -- [targetPlayer] = {sender = player, animalData = {}}
end

function GiftService:_handleGiftRequest(sender: Player, target: Player)
	-- Verify sender is holding an animal or carrying one
	local animalTool = nil
	local character = sender.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and CollectionService:HasTag(child, "Animal") then
				animalTool = child
				break
			end
		end
	end
	
	local isCarrying = sender:GetAttribute("CarryingAnimal") == true
	local carriedData = isCarrying and self._animalService._carriedAnimals[sender]
	
	if not animalTool and not isCarrying then
		self._notificationService:NotifyPlayer(sender, "You must be holding or carrying an animal to gift!", "Warning")
		return
	end
	
	-- Check if target has gifts enabled
	if target:GetAttribute("GiftsDisabled") == true then
		self._notificationService:NotifyPlayer(sender, target.Name .. " has gifts disabled!", "Warning")
		return
	end
	
	-- Check if target is already receiving a gift
	if self._activeGifts[target] then
		self._notificationService:NotifyPlayer(sender, target.Name .. " is already busy!", "Warning")
		return
	end

	local animalData = {}
	if animalTool then
		animalData = {
			name = animalTool.Name,
			rarity = animalTool:GetAttribute("Rarity"),
			attributes = animalTool:GetAttributes(),
			tags = CollectionService:GetTags(animalTool),
			isTool = true,
			instance = animalTool
		}
	else
		animalData = {
			name = carriedData.animalName,
			rarity = carriedData.animalRarity,
			attributes = carriedData.attributes,
			tags = carriedData.tags,
			isTool = false
		}
	end
	
	self._activeGifts[target] = {
		sender = sender,
		animalData = animalData
	}
	
	-- Clone GUI to target
	local newGui = self._guiTemplate:Clone()
	newGui.Name = "GiftGui"
	newGui.Parent = target:FindFirstChild("PlayerGui")
	
	self._notificationService:NotifyPlayer(sender, "Gift request sent successfully", "Success")
	
	-- Send to target
	self._remote:FireClient(target, "OpenGiftGui", {
		senderName = sender.Name,
		animalName = animalData.name
	})
end

function GiftService:_processGift(target: Player, accepted: boolean, dropped: boolean)
	local gift = self._activeGifts[target]
	if not gift then return end
	
	local sender = gift.sender
	local animalData = gift.animalData
	
	if accepted then
		-- Give to target
		self._animalService:_giveAnimalTool(
			target,
			animalData.name,
			animalData.rarity,
			animalData.attributes,
			animalData.tags,
			true
		)
		
		-- Remove from sender
		if animalData.isTool then
			if animalData.instance and animalData.instance.Parent then
				animalData.instance:Destroy()
			end
		else
			self._animalService:_destroyCarriedVisual(sender)
			sender:SetAttribute("CarryingAnimal", false)
			self._animalService:_cancelCarryWatcher(sender)
			self._animalService:_togglePlayerPlacers(sender, false)
		end
		
		self._notificationService:NotifyPlayer(sender, target.Name .. " accepted your gift!", "Success")
		self._notificationService:NotifyPlayer(target, "You received " .. animalData.name .. " from " .. sender.Name .. "!", "Success")
		
	elseif dropped then
		-- Drop animal at target's position
		local character = target.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local dropPos = hrp and hrp.CFrame or CFrame.new()
		
		self._animalService:_dropAnimal(
			animalData.name,
			animalData.rarity,
			dropPos,
			animalData.attributes,
			animalData.tags
		)
		
		-- Remove from sender
		if animalData.isTool then
			if animalData.instance and animalData.instance.Parent then
				animalData.instance:Destroy()
			end
		else
			self._animalService:_destroyCarriedVisual(sender)
			sender:SetAttribute("CarryingAnimal", false)
			self._animalService:_cancelCarryWatcher(sender)
			self._animalService:_togglePlayerPlacers(sender, false)
		end
		
		-- No notification to sender as per request
	else
		-- Refused
		self._notificationService:NotifyPlayer(sender, target.Name .. " refused the gift", "Warning")
	end
	
	self._activeGifts[target] = nil
end

function GiftService:Start()
	self._remote.OnServerEvent:Connect(function(player, action, ...)
		if action == "Accept" then
			self:_processGift(player, true, false)
		elseif action == "Decline" then
			self:_processGift(player, false, false)
		elseif action == "Back" then
			self:_processGift(player, false, true)
		elseif action == "RequestGift" then
			local target = ...
			if typeof(target) == "Instance" and target:IsA("Player") then
				self:_handleGiftRequest(player, target)
			end
		end
	end)
end

return GiftService
