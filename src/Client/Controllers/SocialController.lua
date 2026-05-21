--!strict
-- SocialController.lua
-- v1 social UI: emote buttons via SocialService round-trip. Crew browser
-- placeholder card lives in SocialUI; this controller just opens/closes
-- the panel and forwards PlayEmote calls to the service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local SocialUI = require(script.Parent.Parent.UI.SocialUI)

local SocialController = Knit.CreateController({
	Name = "SocialController",
	_open = false,
	_handle = nil :: any,
})

local EMOTES = { "wave", "dance", "fish_pose", "salute", "bow" }

function SocialController:KnitStart()
	local SocialService = Knit.GetService("SocialService")
	SocialService.EmotePlayed:Connect(function(userId, emoteId)
		-- TODO: hook to AnimationController to actually play the animation
		-- on the player's character. For now print so the round-trip is verifiable.
		print(("[Social] %d played emote %s"):format(userId, emoteId))
	end)
	SocialService.CrewChat:Connect(function(fromName, message)
		print(("[Crew] %s: %s"):format(fromName, message))
	end)
end

function SocialController:Open()
	if self._open then self:_close() return end
	self._open = true
	local SocialService = Knit.GetService("SocialService")
	self._handle = SocialUI.show(EMOTES, function(emoteId)
		SocialService:PlayEmote(emoteId)
	end, function()
		self._open = false
		self._handle = nil
	end)
end

function SocialController:_close()
	self._open = false
	if self._handle then self._handle.close(); self._handle = nil end
end

function SocialController:Close()
	if self._open then self:_close() end
end

return SocialController
