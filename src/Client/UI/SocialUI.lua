--!strict
-- SocialUI.lua
-- Crew & friends panel. v1 only exposes emote buttons (server round-trips
-- via SocialService:PlayEmote); the crew browser slot is a placeholder
-- card so the chrome is already in place when Crew v1 ships.
--
-- Public API:
--   SocialUI.show(emotes, onPlayEmote, onClose) -> SocialHandle
--   handle.close()
--   handle.refresh(emotes)

local UIUtil = require(script.Parent.UIUtil)

local P    = UIUtil.Palette
local SP   = UIUtil.Spacing
local RAD  = UIUtil.Radii

local SocialUI = {}

export type SocialHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (emotes: {string}) -> (),
}

function SocialUI.show(
	emotes: {string},
	onPlayEmote: (emoteId: string) -> (),
	onClose: (() -> ())?
): SocialHandle
	local shell
	shell = UIUtil.makeModalShell({
		name = "SocialUI",
		title = "Crew & Friends",
		onClose = function()
			if shell then shell.destroy() end
			if onClose then onClose() end
		end,
		width = 440,
		heightScale = 0.7,
	})
	local gui  = shell.gui
	local body = shell.body

	-- Crew placeholder card — establishes the slot for Crew v1 without
	-- shipping a half-finished feature.
	local crewCard = Instance.new("Frame")
	crewCard.BackgroundColor3 = P.Teal
	crewCard.BorderSizePixel = 0
	crewCard.Size = UDim2.new(1, 0, 0, 72)
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, RAD.md); cc.Parent = crewCard
	crewCard.Parent = body

	UIUtil.makeLabel("Crew", "subtitle", {
		Position = UDim2.new(0, SP.md, 0, SP.sm),
		Size = UDim2.new(1, -SP.lg, 0, 22),
		Font = Enum.Font.GothamBold,
		Parent = crewCard,
	})
	UIUtil.makeLabel("Crew browser coming soon — invite, chat, share daily haul.", "caption", {
		Position = UDim2.new(0, SP.md, 0, 32),
		Size = UDim2.new(1, -SP.lg, 0, 32),
		TextWrapped = true,
		Parent = crewCard,
	})

	local emotesHeader = UIUtil.makeLabel("EMOTES", "caption", {
		Position = UDim2.new(0, 0, 0, 88),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.GothamBold,
		TextColor3 = P.CreamSoft,
		Parent = body,
	})
	emotesHeader = emotesHeader

	-- Emote button stack — each button is full-width and 44px tall.
	local stack = Instance.new("Frame")
	stack.BackgroundTransparency = 1
	stack.Position = UDim2.new(0, 0, 0, 112)
	stack.Size = UDim2.new(1, 0, 1, -112)
	stack.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, SP.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stack

	local function rebuild(currentEmotes: {string})
		for _, c in ipairs(stack:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for i, e in ipairs(currentEmotes) do
			local label = "Emote: " .. e:gsub("_", " ")
			local btn = UIUtil.makePrimaryButton(label, function()
				onPlayEmote(e)
			end, {
				Size = UDim2.new(1, 0, 0, UIUtil.MinTouchPx),
				LayoutOrder = i,
			})
			btn.Parent = stack
		end
	end
	rebuild(emotes)

	return {
		gui = gui,
		close = function() shell.destroy() end,
		refresh = rebuild,
	}
end

return SocialUI
