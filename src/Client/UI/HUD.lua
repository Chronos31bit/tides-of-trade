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

	-- Settings gear. Lives in its own ScreenGui at DisplayOrder.Settings (above
	-- QuestTracker) so the right-edge quest tracker never draws over it. Bottom-
	-- right corner. Opens SettingsUI.
	settingsGui: ScreenGui,
	settingsButton: TextButton,

	-- Action bar
	actionBar: Frame,
	rodButton: TextButton,
	inventoryButton: TextButton,
	marketButton: TextButton,
	harborButton: TextButton,
	aquariumButton: TextButton,
	socialButton: TextButton,
	homeButton: TextButton,
	seasonPassButton: TextButton,
	baitShopButton: TextButton,
	cosmeticButton: TextButton,
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

	-- Inline buttons (not in template) — Season Pass, Bait Shop, Cosmetic Shop.
	local function makeActionButton(name: string, text: string, color: Color3, layoutOrder: number): TextButton
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Text = text
		btn.Size = UDim2.fromOffset(44, 44)
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.BackgroundColor3 = color
		btn.Font = UIKit.Typography.body.font
		btn.TextSize = math.max(UIKit.Typography.body.size, UIKit.MinFontPx)
		btn.TextColor3 = P.Cream
		btn.LayoutOrder = layoutOrder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, UIKit.Radii.md)
		corner.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.3)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn
		btn.Parent = actionBar
		UIKit.skinActionButton(btn, color)
		return btn
	end

	-- Layout orders: Rod=1..Home=7; inline buttons start at 8.
	local seasonPassButton = makeActionButton("SeasonPassButton", "Pass", P.Sunset, 8)
	local baitShopButton   = makeActionButton("BaitShopButton", "Bait", P.Lure, 9)
	local cosmeticButton   = makeActionButton("CosmeticButton", "Style", P.Rare, 10)

	-- Settings gear. Built in code (not in the template) so it's one self-
	-- contained block. It lives in its OWN ScreenGui at DisplayOrder.Settings
	-- (one above QuestTracker) because the quest tracker is a separate, higher-
	-- order ScreenGui pinned to the right edge — parented inside the HUD it drew
	-- *under* the tracker panel. Its own layer keeps it on top while staying in
	-- the bottom-right corner. 44px hit target; skinned like the action bar.
	local settingsGui = UIUtil.makeScreenGui("SettingsGui", gui.Parent, { respectTopbar = true })
	settingsGui.DisplayOrder = UIUtil.DisplayOrder.Settings

	local settingsButton = Instance.new("TextButton")
	settingsButton.Name = "SettingsButton"
	settingsButton.AnchorPoint = Vector2.new(1, 1)
	settingsButton.Position = UDim2.new(
		1, -UIKit.Spacing.md,
		1, -UIKit.Spacing.md
	)
	settingsButton.Size = UDim2.fromOffset(UIKit.MinTouchPx, UIKit.MinTouchPx)
	settingsButton.AutoButtonColor = false
	settingsButton.BorderSizePixel = 0
	settingsButton.BackgroundColor3 = UIKit.Palette.Amber
	settingsButton.Text = "⚙"
	settingsButton.Font = UIKit.Typography.title.font
	settingsButton.TextSize = math.max(UIKit.Typography.title.size, UIKit.MinFontPx)
	settingsButton.TextColor3 = UIKit.Palette.Cream
	settingsButton.Parent = settingsGui

	local gearCorner = Instance.new("UICorner")
	gearCorner.CornerRadius = UDim.new(0, UIKit.Radii.md)
	gearCorner.Parent = settingsButton

	local gearStroke = Instance.new("UIStroke")
	gearStroke.Color = UIKit.Palette.AmberDeep
	gearStroke.Thickness = 1.5
	gearStroke.Transparency = 0.2
	gearStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	gearStroke.Parent = settingsButton

	UIKit.skinActionButton(settingsButton, UIKit.Palette.Amber)

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
		settingsGui = settingsGui,
		settingsButton = settingsButton,
		actionBar = actionBar,
		rodButton = rodButton,
		inventoryButton = inventoryButton,
		marketButton = marketButton,
		harborButton = harborButton,
		aquariumButton = aquariumButton,
		socialButton = socialButton,
		homeButton = homeButton,
		seasonPassButton = seasonPassButton,
		baitShopButton = baitShopButton,
		cosmeticButton = cosmeticButton,
	}
end

return HUD
