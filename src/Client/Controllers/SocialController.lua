--!strict
-- SocialController.lua
-- Minimal v1 social UI: a single button that plays a wave emote, and a
-- placeholder "open crew menu" that prints to console. Wire richer flows
-- (crew browser, friend visit dropdown) in v2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local UIUtil = require(script.Parent.Parent.UI.UIUtil)

local SocialController = Knit.CreateController({
	Name = "SocialController",
	_open = false,
	_gui = nil :: ScreenGui?,
})

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
	local gui = UIUtil.makeScreenGui("SocialUI")
	self._gui = gui

	local backdrop = UIUtil.makeFrame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
	}); backdrop.Parent = gui

	local panel = UIUtil.makePanel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.7, 0, 0, 360),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local cap = Instance.new("UISizeConstraint"); cap.MaxSize = Vector2.new(440, 360); cap.Parent = panel
	panel.Parent = gui

	local title = UIUtil.makeLabel("Crew & Friends", "title", {
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -100, 0, 28),
	}); title.Parent = panel
	local close = UIUtil.makeButton("Close", function() self:_close() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(80, 32),
		BackgroundColor3 = UIUtil.Palette.Wood,
	}); close.Parent = panel

	local stack = UIUtil.makeFrame({
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 16, 0, 60),
		Size = UDim2.new(1, -32, 1, -76),
	}); stack.Parent = panel
	local layout = Instance.new("UIListLayout"); layout.Padding = UDim.new(0, 8); layout.Parent = stack

	-- Emote buttons. Each emote is a server round-trip so other players see it
	-- via their EmotePlayed signal.
	local SocialService = Knit.GetService("SocialService")
	for _, e in ipairs({"wave", "dance", "fish_pose", "salute", "bow"}) do
		local btn = UIUtil.makeButton("Emote: " .. e, function()
			SocialService:PlayEmote(e)
		end, { Size = UDim2.new(1, 0, 0, 44) })
		btn.Parent = stack
	end
end

function SocialController:_close()
	self._open = false
	if self._gui then self._gui:Destroy(); self._gui = nil end
end

return SocialController
