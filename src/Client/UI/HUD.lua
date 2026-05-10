--!strict
-- HUD.lua
-- Single self-contained ScreenGui that owns:
--   * Top-left:  Coins + Lure chips
--   * Top-right: Level chip with XP bar + daily quest tracker
--   * Bottom:    Action bar (6 tiles)
--
-- Designed to avoid the previous bugs:
--   * No second ScreenGui for the quest tracker (everything's here)
--   * No drop-shadow Frames as siblings of UIListLayout containers (those
--     were getting laid out as phantom slots)
--   * No magic offset math — top-left and top-right anchor naturally to
--     their corners, action bar is centered.

local UIUtil = require(script.Parent.UIUtil)

local HUD = {}

export type QuestRow = {
	frame: Frame,
	label: TextLabel,
	claimButton: TextButton?,
}

export type HUDController = {
	gui: ScreenGui,

	-- Currency
	coinsLabel: TextLabel,
	lureLabel: TextLabel,

	-- Level + XP
	levelLabel: TextLabel,
	xpFill: Frame,

	-- Quest tracker — refresh helpers exposed here.
	questList: Frame,
	-- Container parent of quest rows; HUDController rebuilds rows on update.
	-- We expose just enough surface for the controller to manage children.

	-- Action bar
	actionBar: Frame,
	rodButton: TextButton,
	inventoryButton: TextButton,
	marketButton: TextButton,
	harborButton: TextButton,
	aquariumButton: TextButton,
	socialButton: TextButton,
}

-- Internal: build a square action-bar tile (glyph above, label below).
local function makeActionTile(glyph: string, label: string, tint: Color3): TextButton
	local btn = UIUtil.makeButton("", function() end, {
		Size = UDim2.fromOffset(64, 70),
		BackgroundColor3 = tint,
	})
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
	-- TOP-LEFT — currency cluster
	-- A simple horizontal stack anchored to the top-left of the screen.
	-- We use a *transparent* container Frame and let chips have their own
	-- backgrounds; this avoids the look of a giant solid topbar.
	-- ====================================================================
	local currencyRow = Instance.new("Frame")
	currencyRow.Name = "Currency"
	currencyRow.BackgroundTransparency = 1
	currencyRow.Position = UDim2.fromOffset(16, 16)
	currencyRow.Size = UDim2.fromOffset(280, 40)
	currencyRow.Parent = gui

	local currencyLayout = Instance.new("UIListLayout")
	currencyLayout.FillDirection = Enum.FillDirection.Horizontal
	currencyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	currencyLayout.Padding = UDim.new(0, 8)
	currencyLayout.Parent = currencyRow

	local coinsChip, coinsLabel = UIUtil.makeChip({
		name = "Coins", iconGlyph = "$", iconColor = UIUtil.Palette.Gold, value = "0",
	})
	coinsChip.LayoutOrder = 1
	coinsChip.Parent = currencyRow

	local lureChip, lureLabel = UIUtil.makeChip({
		name = "Lure", iconGlyph = "★", iconColor = UIUtil.Palette.Lure, value = "0",
	})
	lureChip.LayoutOrder = 2
	lureChip.Parent = currencyRow

	-- ====================================================================
	-- TOP-RIGHT — Level chip on top, quest tracker beneath it
	-- ====================================================================
	local statusColumn = Instance.new("Frame")
	statusColumn.Name = "Status"
	statusColumn.BackgroundTransparency = 1
	statusColumn.AnchorPoint = Vector2.new(1, 0)
	statusColumn.Position = UDim2.new(1, -16, 0, 16)
	statusColumn.Size = UDim2.fromOffset(280, 220)
	statusColumn.Parent = gui

	local statusLayout = Instance.new("UIListLayout")
	statusLayout.FillDirection = Enum.FillDirection.Vertical
	statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusLayout.Padding = UDim.new(0, 8)
	statusLayout.Parent = statusColumn

	-- Level chip with XP bar inside.
	local levelChip = Instance.new("Frame")
	levelChip.Name = "Level"
	levelChip.Size = UDim2.fromOffset(220, 44)
	levelChip.BackgroundColor3 = UIUtil.Palette.TealDark
	levelChip.BorderSizePixel = 0
	levelChip.LayoutOrder = 1
	local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0, 14); lc.Parent = levelChip
	local ls = Instance.new("UIStroke"); ls.Color = UIUtil.Palette.TealDeeper; ls.Thickness = 1.2; ls.Transparency = 0.3; ls.Parent = levelChip
	local lgrad = Instance.new("UIGradient")
	lgrad.Rotation = 90
	lgrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	lgrad.Parent = levelChip
	levelChip.Parent = statusColumn

	local levelLabel = UIUtil.makeLabel("Lv 1", "subtitle", {
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -28, 0.55, 0),
		TextSize = 14,
	})
	levelLabel.Parent = levelChip

	local xpBg = Instance.new("Frame")
	xpBg.Name = "XPBg"
	xpBg.Position = UDim2.new(0, 14, 0.62, 0)
	xpBg.Size = UDim2.new(1, -28, 0, 6)
	xpBg.BackgroundColor3 = UIUtil.Palette.TealDeeper
	xpBg.BorderSizePixel = 0
	local xpc = Instance.new("UICorner"); xpc.CornerRadius = UDim.new(1, 0); xpc.Parent = xpBg
	xpBg.Parent = levelChip

	local xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = UIUtil.Palette.Sunset
	xpFill.BorderSizePixel = 0
	local xpfc = Instance.new("UICorner"); xpfc.CornerRadius = UDim.new(1, 0); xpfc.Parent = xpFill
	local xpgrad = Instance.new("UIGradient")
	xpgrad.Rotation = 90
	xpgrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIUtil.Palette.SunsetSoft),
		ColorSequenceKeypoint.new(1, UIUtil.Palette.SunsetDeep),
	})
	xpgrad.Parent = xpFill
	xpFill.Parent = xpBg

	-- Quest tracker panel underneath the level chip.
	local questPanel = Instance.new("Frame")
	questPanel.Name = "Quests"
	questPanel.BackgroundColor3 = UIUtil.Palette.TealDark
	questPanel.BackgroundTransparency = 0.1
	questPanel.BorderSizePixel = 0
	questPanel.Size = UDim2.fromOffset(260, 168)
	questPanel.LayoutOrder = 2
	local qpc = Instance.new("UICorner"); qpc.CornerRadius = UDim.new(0, 14); qpc.Parent = questPanel
	local qps = Instance.new("UIStroke"); qps.Color = UIUtil.Palette.TealDeeper; qps.Thickness = 1.2; qps.Transparency = 0.3; qps.Parent = questPanel
	questPanel.Parent = statusColumn

	local questTitle = UIUtil.makeLabel("Daily Quests", "title", {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 22),
		TextSize = 15,
	})
	questTitle.Parent = questPanel

	-- Container for the quest rows — controller rebuilds children on update.
	local questList = Instance.new("Frame")
	questList.Name = "List"
	questList.BackgroundTransparency = 1
	questList.Position = UDim2.new(0, 8, 0, 34)
	questList.Size = UDim2.new(1, -16, 1, -42)
	questList.Parent = questPanel

	local questListLayout = Instance.new("UIListLayout")
	questListLayout.Padding = UDim.new(0, 4)
	questListLayout.Parent = questList

	-- ====================================================================
	-- BOTTOM ACTION BAR
	-- Centered, fixed-width container with 6 tiles. UIListLayout drives
	-- horizontal flow; tiles are the only children, so no shadow phantoms.
	-- ====================================================================
	local actionBar = Instance.new("Frame")
	actionBar.Name = "ActionBar"
	actionBar.AnchorPoint = Vector2.new(0.5, 1)
	actionBar.Position = UDim2.new(0.5, 0, 1, -16)
	-- Width: 6 tiles * 64 + 5 paddings * 6 + 16 padding-edges = 446 px.
	-- We use AutomaticSize so the parent shrinks to fit children without
	-- the dark background extending beyond the tiles.
	actionBar.Size = UDim2.fromOffset(0, 86)
	actionBar.AutomaticSize = Enum.AutomaticSize.X
	actionBar.BackgroundColor3 = UIUtil.Palette.TealDark
	actionBar.BackgroundTransparency = 0.05
	actionBar.BorderSizePixel = 0
	local abc = Instance.new("UICorner"); abc.CornerRadius = UDim.new(0, 14); abc.Parent = actionBar
	local abs = Instance.new("UIStroke"); abs.Color = UIUtil.Palette.TealDeeper; abs.Thickness = 1.5; abs.Transparency = 0.2; abs.Parent = actionBar
	-- Subtle top-light.
	local abgrad = Instance.new("UIGradient")
	abgrad.Rotation = 90
	abgrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	abgrad.Parent = actionBar
	actionBar.Parent = gui

	local barPad = Instance.new("UIPadding")
	barPad.PaddingLeft = UDim.new(0, 8); barPad.PaddingRight = UDim.new(0, 8)
	barPad.PaddingTop = UDim.new(0, 8);  barPad.PaddingBottom = UDim.new(0, 8)
	barPad.Parent = actionBar

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, 6)
	barLayout.Parent = actionBar

	local rodBtn  = makeActionTile("⌇",  "Rod",      UIUtil.Palette.Sunset)
	local invBtn  = makeActionTile("▤",  "Bag",      UIUtil.Palette.Wood)
	local mktBtn  = makeActionTile("$",  "Market",   UIUtil.Palette.TealLight)
	local aquaBtn = makeActionTile("◉",  "Aquarium", UIUtil.Palette.Rare)
	local hrbBtn  = makeActionTile("▣",  "Build",    UIUtil.Palette.SunsetDeep)
	local socBtn  = makeActionTile("♥",  "Crew",     UIUtil.Palette.Lure)
	rodBtn.LayoutOrder = 1; rodBtn.Parent = actionBar
	invBtn.LayoutOrder = 2; invBtn.Parent = actionBar
	mktBtn.LayoutOrder = 3; mktBtn.Parent = actionBar
	aquaBtn.LayoutOrder = 4; aquaBtn.Parent = actionBar
	hrbBtn.LayoutOrder = 5; hrbBtn.Parent = actionBar
	socBtn.LayoutOrder = 6; socBtn.Parent = actionBar

	return {
		gui = gui,
		coinsLabel = coinsLabel,
		lureLabel = lureLabel,
		levelLabel = levelLabel,
		xpFill = xpFill,
		questList = questList,
		actionBar = actionBar,
		rodButton = rodBtn,
		inventoryButton = invBtn,
		marketButton = mktBtn,
		harborButton = hrbBtn,
		aquariumButton = aquaBtn,
		socialButton = socBtn,
	}
end

return HUD
