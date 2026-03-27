local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local TagController = {
	Name = "TagController",
	Priority = 50,
}

function TagController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	
	-- Setup TextChatService tags and command hiding on the client
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		TextChatService.OnIncomingMessage = function(message: TextChatMessage)
			local properties = Instance.new("TextChatMessageProperties")
			if message.TextSource then
				local player = Players:GetPlayerByUserId(message.TextSource.UserId)
				if player then
					-- 1. Apply Role Tags
					local roleTag = player:GetAttribute("RoleTag")
					local roleColor = player:GetAttribute("RoleColor")
					
					if roleTag and roleTag ~= "" then
						properties.PrefixText = string.format("<font color=\"%s\">%s</font> %s", roleColor or "rgb(255, 255, 255)", roleTag, message.PrefixText)
					end

					-- 2. Hide Admin Commands
					if string.sub(message.Text, 1, 1) == "/" and player:GetAttribute("IsAdmin") == true then
						properties.Text = "" -- Hide the command text
					end
				end
			end
			return properties
		end
	end
end

function TagController:Start()
	-- Hide local player's tags
	local player = Players.LocalPlayer
	
	local function hideTags(character)
		local function setTagEnabled(child)
			if child.Name == "NameTag" or child.Name == "RoleTag" then
				if child:IsA("BillboardGui") then
					child.Enabled = false
				end
			end
		end

		character.ChildAdded:Connect(setTagEnabled)
		for _, child in ipairs(character:GetChildren()) do
			setTagEnabled(child)
		end
	end

	player.CharacterAdded:Connect(hideTags)
	if player.Character then
		hideTags(player.Character)
	end
end

return TagController
