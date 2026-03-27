local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local TagService = {
	Name = "TagService",
	Priority = 50,
}

-- Roles configuration (Can be moved to GameConfig later)
local ROLES = {
	OWNER = { Tag = "[OWNER 👑]", Color = "rgb(0, 89, 255)", Priority = 100 },
	DEV = { Tag = "[DEV 🔧]", Color = "rgb(124, 255, 76)", Priority = 80 },
	VIP = { Tag = "[VIP]", Color = "rgb(255, 215, 0)", Priority = 60 },
	FAN = { Tag = "[FAN]", Color = "rgb(200, 200, 200)", Priority = 40 },
	DEFAULT = { Tag = "", Color = "rgb(255, 255, 255)", Priority = 0 },
}

local GROUP_ID = 729308194 -- TODO: Replace with actual Group ID if known, otherwise FanTag might be based on badge/purchase

function TagService:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._assets = ServerStorage:WaitForChild("Assets"):WaitForChild("PlayerTags")
end

function TagService:GetPlayerRole(player: Player)
	-- Owner check
	if player.UserId == game.CreatorId or (RunService:IsStudio() and player.UserId == 1) then
		return "OWNER"
	end
	
	-- Admin/Dev check from config
	if self._config.Admins and self._config.Admins[player.UserId] then
		return "DEV"
	end
	
	-- VIP check (Example: Gamepass or Attribute)
	if player:GetAttribute("IsVIP") == true then
		return "VIP"
	end
	
	-- Fan check (Group membership)
	if GROUP_ID > 0 and player:IsInGroup(GROUP_ID) then
		return "FAN"
	end
	
	return "DEFAULT"
end

function TagService:_setupNametag(player: Player, character: Model)
    local roleName = self:GetPlayerRole(player)
	local roleData = ROLES[roleName] or ROLES.DEFAULT
	
    player:SetAttribute("Role", roleName)
	player:SetAttribute("RoleTag", roleData.Tag)
	player:SetAttribute("RoleColor", roleData.Color)

	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not rootPart then return end
	
	-- Hide default name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	
	-- Clean existing tags
	for _, child in ipairs(character:GetChildren()) do
		if child.Name == "NameTag" or child.Name == "RoleTag" then
			child:Destroy()
		end
	end
	
	-- 1. Setup NameTag
	local nameTagTemplate = self._assets:FindFirstChild("NameTag")
	local nameTag = if nameTagTemplate then nameTagTemplate:Clone() else nil
	
	if nameTag then
		nameTag.Name = "NameTag"
		nameTag.Adornee = rootPart
		local nameLabel = nameTag:FindFirstChild("Name", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = player.DisplayName or player.Name
		end
		nameTag.Parent = character
	end

	-- 2. Setup RoleTag
	local roleTagName = ""
	if roleName == "OWNER" then roleTagName = "OwnerTag"
	elseif roleName == "DEV" then roleTagName = "DevTag"
	elseif roleName == "VIP" then roleTagName = "VipTag"
	elseif roleName == "FAN" then roleTagName = "FanTag"
	end

	local roleTagTemplate = if roleTagName ~= "" then self._assets:FindFirstChild(roleTagName) else nil
	local roleTag = if roleTagTemplate then roleTagTemplate:Clone() else nil

	if roleTag then
		roleTag.Name = "RoleTag"
		roleTag.Adornee = rootPart
		roleTag.Parent = character
	end

	-- 3. Position them stacked above character extents
	local function updateOffsets()
		if not character.Parent or not rootPart.Parent then return end
		
		-- Get total height including accessories
		local cf, size = character:GetBoundingBox()
		local rootPos = rootPart.Position
		
		-- Calculate height of the top of the character relative to the rootPart
		local topYRel = (cf.Y + size.Y/2) - rootPos.Y
		
		if nameTag then
			nameTag.StudsOffsetWorldSpace = Vector3.new(0, topYRel + 0.8, 0)
		end
		
		if roleTag then
			-- Stack role above name (assuming name tag is ~0.8-1 stud tall)
			roleTag.StudsOffsetWorldSpace = Vector3.new(0, topYRel + 1.8, 0)
		end
	end

	updateOffsets()
	
	-- Re-calculate when things are added (like hair or hats)
	local conn = character.DescendantAdded:Connect(function()
		task.wait(0.1)
		updateOffsets()
	end)

	character.Destroying:Connect(function()
		conn:Disconnect()
	end)
end
function TagService:Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			self:_setupNametag(player, character)
		end)
		
		if player.Character then
			self:_setupNametag(player, player.Character)
		end
	end)
	
	-- Setup for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			self:_setupNametag(player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			self:_setupNametag(player, character)
		end)
	end
end

return TagService
