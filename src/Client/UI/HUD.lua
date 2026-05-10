--!strict
-- HUD.lua
-- Top chip cluster (coins / lure / level+XP) and bottom action bar. Topbar
-- uses currency chips with emoji glyphs. Action bar uses square tile buttons
-- with glyph-on-top, label-below layout. Both float with drop shadows.

local UIUtil = require(script.Parent.UIUtil)

local HUD = {}

export type HUDController = {
	gui: ScreenGui,
	coinsLabel: TextLabel,
	lureLabel: TextLabel,
	levelLabel: TextLabel,
	xpFill: Frame,
	questLabel: TextLabel,
	bottomBar: Frame?,
	rodButton: TextButton?,
	inventoryButton: TextButton?,
	marketButton: TextButton?,
	harborButton: TextButton?,
	aquariumButton: TextButton?,
	socialButton: TextButton?,
}

-- Build a square action-bar tile: glyph centered with a label underneath.
local function makeActionTile(glyph: string, label: string, tint: Color3): TextButton
	local btn = UIUtil.makeButton("", function() end, {
		Size = UDim2.fromOffset(64, 70),
		BackgroundColor3 = tint,
		variant = "primary",
	})
	-- Stomp the inherited text — we'll lay out glyph + label as children.
	btn.Text = ""

	local glyphLbl = Instance.new("TextLabel")
	glyphLbl.BackgroundTransparency = 1
	glyphLbl.Position = UDim2.new(0, 0, 0, 4)
	glyphLbl.Size = UDim2.new(1, 0, 0.55, 0)
	glyphLbl.Font = Enum.Font.GothamBlack
	glyphLbl.TextSize = 22
	glyphLbl.TextColor3 = UIUtil.Palette.Cream
	glyphLbl.Text = glyph
	glyphLbl.Parent = btn

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Position = UDim2.new(0, 0, 0.55, 0)
	nameLbl.Size = UDim2.new(1, 0, 0.4, 0)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 11
	nameLbl.TextColor3 = UIUtil.Palette.Cream
	nameLbl.TextXAlignment = Enum.TextXAlignment.Center
	nameLbl.Text = label
	nameLbl.Parent = btn
	return btn
end

function HUD.create(): HUDController
	local gui = UIUtil.makeScreenGui("HUD")

	-- ====================================================================
	-- TOP CLUSTER — chips floating on a transparent canvas (no full-width
	-- bar). Looks more modern than a solid topbar; the world fills the gaps.
	-- ====================================================================
	local topCluster = Instance.new("Frame")
	topCluster.Name = "TopCluster"
	topCluster.BackgroundTransparency = 1
	topCluster.AnchorPoint = Vector2.new(0.5, 0)
	topCluster.Position = UDim2.new(0.5, 0, 0, 14)
	topCluster.Size = UDim2.new(0.96, 0, 0, 76)
	topCluster.Parent = gui
	local topMax = Instance.new("UISizeConstraint")
	topMax.MaxSize = Vector2.new(820, 76); topMax.Parent = topCluster

	-- Left half: chips horizontally laid out.
	local chipRow = Instance.new("Frame")
	chipRow.Name = "Chips"
	chipRow.BackgroundTransparency = 1
	chipRow.Position = UDim2.new(0, 0, 0, 0)
	chipRow.Size = UDim2.new(0.6, 0, 0, 38)
	chipRow.Parent = topCluster
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.Parent = chipRow

	-- Coins chip (gold disc, $ glyph).
	local coinsChip, coinsLabel = UIUtil.makeChip({
		name = "Coins", iconGlyph = "$", iconColor = UIUtil.Palette.Gold, value = "0",
	})
	coinsChip.LayoutOrder = 1
	coinsChip.Parent = chipRow

	-- Lure chip (purple disc, ★ glyph).
	local lureChip, lureLabel = UIUtil.makeChip({
		name = "Lure", iconGlyph = "★", iconColor = UIUtil.Palette.Lure, value = "0",
	})
	lureChip.LayoutOrder = 2
	lureChip.Parent = chipRow

	-- Level + XP cluster (separate widget — a chip with a thick XP bar
	-- underneath replaces the previous combined-frame approach).
	local levelChip = UIUtil.makeFrame({
		Name = "Level",
		Size = UDim2.fromOffset(180, 38),
		BackgroundColor3 = UIUtil.Palette.TealDark,
		LayoutOrder = 3,
	})
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 12); lc.Parent = levelChip
	local ls = Instance.new("UIStroke"); ls.Color = UIUtil.Palette.TealDeeper; ls.Thickness = 1.2; ls.Transparency = 0.3; ls.Parent = levelChip
	levelChip.Parent = chipRow

	local levelLabel = UIUtil.makeLabel("Lv 1", "subtitle", {
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -24, 0.55, 0),
		TextSize = 14,
		TextColor3 = UIUtil.Palette.Cream,
	})
	levelLabel.Parent = levelChip
	-- XP bar underneath the level number.
	local xpBg = UIUtil.makeFrame({
		Name = "XPBg",
		Position = UDim2.new(0, 12, 0.62, 0),
		Size = UDim2.new(1, -24, 0, 6),
		BackgroundColor3 = UIUtil.Palette.TealDeeper,
	})
	xpBg.Parent = levelChip
	local xpc = Instance.new("UICorner"); xpc.CornerRadius = UDim.new(1, 0); xpc.Parent = xpBg
	local xpFill = UIUtil.makeFrame({
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = UIUtil.Palette.Sunset,
	})
	xpFill.Parent = xpBg
	local xpfc = Instance.new("UICorner"); xpfc.CornerRadius = UDim.new(1, 0); xpfc.Parent = xpFill
	-- Glow gradient on the fill so it reads as "active progress" not "static bar".
	local xpgrad = Instance.new("UIGradient")
	xpgrad.Rotation = 90
	xpgrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIUtil.Palette.SunsetSoft),
		ColorSequenceKeypoint.new(1, UIUtil.Palette.SunsetDeep),
	})
	xpgrad.Parent = xpFill

	-- Right side: quest preview (full-width hint banner under the chip row).
	local questBanner = UIUtil.makeFrame({
		Name = "QuestBanner",
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = UIUtil.Palette.TealDark,
		BackgroundTransparency = 0.25,
	})
	local qc = Instance.new("UICorner"); qc.CornerRadius = UDim.new(1, 0); qc.Parent = questBanner
	questBanner.Parent = topCluster

	local questDot = Instance.new("Frame")
	questDot.AnchorPoint = Vector2.new(0, 0.5)
	questDot.Position = UDim2.new(0, 12, 0.5, 0)
	questDot.Size = UDim2.fromOffset(8, 8)
	questDot.BackgroundColor3 = UIUtil.Palette.Sunset
	questDot.BorderSizePixel = 0
	local qdc = Instance.new("UICorner"); qdc.CornerRadius = UDim.new(1, 0); qdc.Parent = questDot
	questDot.Parent = questBanner

	local questLabel = UIUtil.makeLabel("Loading daily quests…", "caption", {
		Position = UDim2.new(0, 28, 0, 0),
		Size = UDim2.new(1, -40, 1, 0),
		TextColor3 = UIUtil.Palette.Cream,
		TextSize = 13,
	})
	questLabel.Parent = questBanner

	-- ====================================================================
	-- BOTTOM ACTION BAR
	-- ====================================================================
	local bottomBar = UIUtil.makePanel({
		Name = "ActionBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0.96, 0, 0, 88),
		BackgroundColor3 = UIUtil.Palette.TealDark,
		BackgroundTransparency = 0.05,
	})
	local barMax = Instance.new("UISizeConstraint")
	barMax.MaxSize = Vector2.new(560, 88); barMax.Parent = bottomBar
	bottomBar.Parent = gui

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, 6)
	barLayout.Parent = bottomBar
	local barPad = Instance.new("UIPadding")
	barPad.PaddingTop = UDim.new(0, 8); barPad.PaddingBottom = UDim.new(0, 8)
	barPad.PaddingLeft = UDim.new(0, 8); barPad.PaddingRight = UDim.new(0, 8)
	barPad.Parent = bottomBar

	-- Six tiles. Glyphs picked from glyphs that render in Gotham fonts.
	-- The visual character of the icon comes from the colored disc behind
	-- it; the glyph itself is just a hint (a single bold letter or symbol).
	local rodBtn  = makeActionTile("⌇",  "Rod",      UIUtil.Palette.Sunset)
	local invBtn  = makeActionTile("▤",  "Bag",      UIUtil.Palette.Wood)
	local mktBtn  = makeActionTile("$",  "Market",   UIUtil.Palette.TealLight)
	local aquaBtn = makeActionTile("◉",  "Aquarium", UIUtil.Palette.Rare)
	local hrbBtn  = makeActionTile("▣",  "Build",    UIUtil.Palette.SunsetDeep)
	local socBtn  = makeActionTile("♥",  "Crew",     UIUtil.Palette.Lure)
	rodBtn.Parent  = bottomBar; rodBtn.LayoutOrder = 1
	invBtn.Parent  = bottomBar; invBtn.LayoutOrder = 2
	mktBtn.Parent  = bottomBar; mktBtn.LayoutOrder = 3
	aquaBtn.Parent = bottomBar; aquaBtn.LayoutOrder = 4
	hrbBtn.Parent  = bottomBar; hrbBtn.LayoutOrder = 5
	socBtn.Parent  = bottomBar; socBtn.LayoutOrder = 6

	return {
		gui = gui,
		coinsLabel = coinsLabel,
		lureLabel = lureLabel,
		levelLabel = levelLabel,
		xpFill = xpFill,
		questLabel = questLabel,
		bottomBar = bottomBar,
		rodButton = rodBtn,
		inventoryButton = invBtn,
		marketButton = mktBtn,
		harborButton = hrbBtn,
		aquariumButton = aquaBtn,
		socialButton = socBtn,
	}
end

return HUD
