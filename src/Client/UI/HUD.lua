--!strict
-- HUD.lua  (rebuild #3 — minimal, opaque, legible)
--
-- Design principles after several iterations:
--   * Every panel is fully opaque (no BackgroundTransparency, no fade
--     gradients). Glassy effects hurt readability and we lost more time to
--     them than they were worth.
--   * No drop shadows. The previous shadow Frames kept getting laid out as
--     UIListLayout slots, producing phantom tiles.
--   * Strong typographic contrast: big bold currency numbers, small caps
--     labels.
--   * Anchored carefully around the Roblox topbar (IgnoreGuiInset = false)
--     so the chat / menu icons never sit on top of our chips.
--   * Daily quests are owned by QuestTrackerUI (separate ScreenGui, higher
--     DisplayOrder). HUD chrome clones from StarterGuiAssets.HUD_Template.

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)

local HUD = {}

local P = UIUtil.Palette

export type HUDController = {
	gui: ScreenGui,

	-- Currency
	coinsLabel: TextLabel,
	lureLabel: TextLabel,

	-- Level / XP
	levelLabel: TextLabel,
	xpFill: Frame,

	-- Rod tier chip (read-only; tap/long-press/hover opens a tooltip).
	-- HUDController recolours icon disc + stroke + value by tier.
	rodChip: TextButton,
	rodChipIcon: Frame,
	rodChipStroke: UIStroke,
	rodChipValue: TextLabel,

	-- Action bar
	actionBar: Frame,
	rodButton: TextButton,
	inventoryButton: TextButton,
	marketButton: TextButton,
	harborButton: TextButton,
	aquariumButton: TextButton,
	socialButton: TextButton,
	homeButton: TextButton,
}

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[HUD] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

-- -------------------------------------------------------------------
-- Main build — layout from HUD_Template; behavior wiring only here.
-- -------------------------------------------------------------------
function HUD.create(): HUDController
	local gui = TemplateLoader.spawn("HUD")

	local wallet = requireChild(gui, "Wallet", "Frame") :: Frame
	local coinsLabel = requireChild(wallet, "CoinsLabel", "TextLabel") :: TextLabel
	local lureLabel = requireChild(wallet, "LureLabel", "TextLabel") :: TextLabel

	local statusCol = requireChild(gui, "StatusColumn", "Frame") :: Frame
	local levelChip = requireChild(statusCol, "LevelChip", "Frame") :: Frame
	local levelLabel = requireChild(levelChip, "LevelLabel", "TextLabel") :: TextLabel
	local xpBg = requireChild(levelChip, "XpBg", "Frame") :: Frame
	local xpFill = requireChild(xpBg, "XpFill", "Frame") :: Frame

	local rodChip = requireChild(statusCol, "RodChip", "TextButton") :: TextButton
	local rodChipIcon = requireChild(rodChip, "RodChipIcon", "Frame") :: Frame
	local rodChipStroke = rodChip:FindFirstChildOfClass("UIStroke")
	if not rodChipStroke then
		error("[HUD] Missing UIStroke on RodChip", 2)
	end
	local rodChipValue = requireChild(rodChip, "RodChipValue", "TextLabel") :: TextLabel

	local actionBar = requireChild(gui, "ActionBar", "Frame") :: Frame
	local rodButton = requireChild(actionBar, "RodButton", "TextButton") :: TextButton
	local inventoryButton = requireChild(actionBar, "InventoryButton", "TextButton") :: TextButton
	local marketButton = requireChild(actionBar, "MarketButton", "TextButton") :: TextButton
	local aquariumButton = requireChild(actionBar, "AquariumButton", "TextButton") :: TextButton
	local harborButton = requireChild(actionBar, "HarborButton", "TextButton") :: TextButton
	local socialButton = requireChild(actionBar, "SocialButton", "TextButton") :: TextButton
	local homeButton = requireChild(actionBar, "HomeButton", "TextButton") :: TextButton

	UIKit.skinActionButton(rodButton, P.Sunset)
	UIKit.skinActionButton(inventoryButton, P.Wood)
	UIKit.skinActionButton(marketButton, P.TealLight)
	UIKit.skinActionButton(aquariumButton, P.Rare)
	UIKit.skinActionButton(harborButton, P.SunsetDeep)
	UIKit.skinActionButton(socialButton, P.Lure)
	UIKit.skinActionButton(homeButton, P.Uncommon)

	return {
		gui = gui,
		coinsLabel = coinsLabel,
		lureLabel = lureLabel,
		levelLabel = levelLabel,
		xpFill = xpFill,
		rodChip = rodChip,
		rodChipIcon = rodChipIcon,
		rodChipStroke = rodChipStroke,
		rodChipValue = rodChipValue,
		actionBar = actionBar,
		rodButton = rodButton,
		inventoryButton = inventoryButton,
		marketButton = marketButton,
		harborButton = harborButton,
		aquariumButton = aquariumButton,
		socialButton = socialButton,
		homeButton = homeButton,
	}
end

return HUD
