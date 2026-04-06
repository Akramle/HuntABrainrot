local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Icon = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("TopbarPlus"))

local TopbarController = {
	Name = "TopbarController",
	Priority = 20,
}

function TopbarController:Init(runtime)
	self._runtime = runtime
end

function TopbarController:Start(runtime)
	local musicController = self._runtime:GetController("MusicController")

	local musicToggleIcon = Icon.new()
		:setLabel("🔊 Disable Music")
		:bindEvent("selected", function(icon)
			icon:setLabel("🔇 Enable Music")
			if musicController then
				musicController:SetMusicEnabled(false)
			end
		end)
		:bindEvent("deselected", function(icon)
			icon:setLabel("🔊 Disable Music")
			if musicController then
				musicController:SetMusicEnabled(true)
			end
		end)

	local giftsToggleIcon = Icon.new()
		:setLabel("🎁 Disable Gifts")
		:bindEvent("selected", function(icon)
			icon:setLabel("🎁 Enable Gifts")
			Players.LocalPlayer:SetAttribute("GiftsDisabled", true)
		end)
		:bindEvent("deselected", function(icon)
			icon:setLabel("🎁 Disable Gifts")
			Players.LocalPlayer:SetAttribute("GiftsDisabled", false)
		end)

	-- Settings Button
	Icon.new()
		:setName("Settings")
		:setLabel("⚙️ Settings")
		:setDropdown({
			musicToggleIcon,
			giftsToggleIcon
		})
		
	-- Invite Friends Button
	Icon.new()
		:setName("InviteFriends")
		:setLabel("👥 Invite friends")
		:bindEvent("selected", function(icon)
			local success, err = pcall(function()
				SocialService:PromptGameInvite(Players.LocalPlayer)
			end)
			if not success then
				warn("Failed to prompt game invite: ", err)
			end
			-- Immediately deselect so it acts like a normal button
			task.delay(0.1, function()
				icon:deselect()
			end)
		end)
		
	-- Daily Prizes Button
	Icon.new()
		:setName("DailyPrizes")
		:setLabel("📆 Daily")
end


return TopbarController
