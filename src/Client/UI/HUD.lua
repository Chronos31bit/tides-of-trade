--!strict
-- HUD.lua
-- Single horizontal top strip (wallet | level/XP | rod tier+rank) +
-- bottom action bar. Everything that was in the vertical status column
-- is now inline left-to-right so the screen stays open below.

local UIUtil = require(script.Parent.UIUtil)

local HUD = {}
local P = UIUtil.Palette

export type HUDController = {
	gui: ScreenGui,

	-- Currency
	coinsLabel: TextLabel,
	lureLabel:  TextLabel,

	-- Level / XP
	levelLabel: TextLabel,
	xpFill:     Frame,

	-- Rod tier chip (tap opens the rod rack; HUDController recolours per tier).
	rodChip:       TextButton,
	rodChipIcon:   Frame,
	rodChipStroke: UIStroke,
	rodChipValue:  TextLabel,

	-- Rarity pill — NEW. HUDController updates rank + colour on equip.
	rodRankPill:  Frame,
	rodRankLabel: TextLabel,

	-- Action bar
	actionBar:       Frame,
	rodButton:       TextButton,
	inventoryButton: TextButton,
	marketButton:    TextButton,
	harborButton:    TextButton,
	aquariumButton:  TextButton,
	socialButton:    TextButton,
	homeButton:      TextButton,
}

-- ── Shared helpers ──────────────────────────────────────────────────────

local function iconDisc(diameter: number, color: Color3, glyph: string): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel  = 0
	f.Size             = UDim2.fromOffset(diameter, diameter)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Size      = UDim2.fromScale(1, 1)
	g.Font      = Enum.Font.GothamBlack
	g.TextSize  = math.floor(diameter * 0.6)
	g.TextColor3 = P.Ink
	g.Text      = glyph
	g.Parent    = f
	return f
end

local function valueLabel(initial: string, size: number?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font          = Enum.Font.GothamBold
	lbl.TextSize      = size or 17
	lbl.TextColor3    = P.Cream
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text          = initial
	return lbl
end

local function smallCaps(text: string): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font      = Enum.Font.GothamBold
	lbl.TextSize  = 10
	lbl.TextColor3 = P.CreamSoft
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text      = text:upper()
	return lbl
end

local function vDiv(parent: Instance, order: number)
	local d = Instance.new("Frame")
	d.BackgroundColor3       = P.TealDeeper
	d.BackgroundTransparency = 0.35
	d.BorderSizePixel        = 0
	d.Size                   = UDim2.fromOffset(1, 32)
	d.LayoutOrder            = order
	d.Parent                 = parent
end

local function actionTile(glyph: string, label: string, tint: Color3, keybind: string?): TextButton
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = tint
	btn.BorderSizePixel  = 0
	btn.Size             = UDim2.fromOffset(64, 64)
	btn.Text             = ""
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = btn
	local s = Instance.new("UIStroke"); s.Color = P.TealDeeper; s.Thickness = 1.5; s.Transparency = 0.4; s.Parent = btn

	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Position = UDim2.new(0, 0, 0, 5)
	g.Size     = UDim2.new(1, 0, 0.52, 0)
	g.Font     = Enum.Font.GothamBlack
	g.TextSize = 22
	g.TextColor3 = P.Cream
	g.Text     = glyph
	g.Parent   = btn

	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Position = UDim2.new(0, 0, 0.6, 0)
	n.Size     = UDim2.new(1, 0, 0.35, 0)
	n.Font     = Enum.Font.GothamBold
	n.TextSize = 9
	n.TextColor3 = P.Cream
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.Text     = label
	n.Parent   = btn

	if keybind then
		local kb = Instance.new("TextLabel")
		kb.BackgroundTransparency = 1
		kb.AnchorPoint = Vector2.new(1, 0)
		kb.Position    = UDim2.new(1, -3, 0, 3)
		kb.Size        = UDim2.fromOffset(13, 13)
		kb.Font        = Enum.Font.GothamBold
		kb.TextSize    = 8
		kb.TextColor3  = P.Cream:Lerp(Color3.new(0, 0, 0), 0.35)
		kb.Text        = keybind
		kb.Parent      = btn
	end

	local TweenService = game:GetService("TweenService")
	local rest    = tint
	local pressed = rest:Lerp(Color3.new(0, 0, 0), 0.22)
	local hover   = rest:Lerp(Color3.new(1, 1, 1), 0.08)
	local info    = TweenInfo.new(0.08)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, info, { BackgroundColor3 = hover }):Play()
	end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = rest end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(btn, info, { BackgroundColor3 = pressed }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(btn, info, { BackgroundColor3 = hover }):Play()
	end)

	return btn
end

-- ── Main build ──────────────────────────────────────────────────────────

function HUD.create(): HUDController
	local gui = UIUtil.makeScreenGui("HUD", nil, { respectTopbar = true })

	-- ================================================================
	-- HORIZONTAL TOP STRIP
	-- Wallet | Level/XP | Rod tier + rarity rank — all inline.
	-- ================================================================
	local topBar = Instance.new("Frame")
	topBar.Name             = "TopBar"
	topBar.AnchorPoint      = Vector2.new(0.5, 0)
	topBar.Position         = UDim2.new(0.5, 0, 0, 14)
	topBar.Size             = UDim2.new(0, 0, 0, 54)
	topBar.AutomaticSize    = Enum.AutomaticSize.X
	topBar.BackgroundColor3 = P.TealDark
	topBar.BorderSizePixel  = 0
	local topCap = Instance.new("UISizeConstraint")
	topCap.MaxSize = Vector2.new(480, 9999)
	topCap.Parent  = topBar
	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 14)
	topCorner.Parent = topBar
	local topStroke = Instance.new("UIStroke")
	topStroke.Color       = P.TealDeeper
	topStroke.Thickness   = 1.5
	topStroke.Transparency = 0.25
	topStroke.Parent = topBar
	topBar.Parent = gui

	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection     = Enum.FillDirection.Horizontal
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	topLayout.SortOrder         = Enum.SortOrder.LayoutOrder
	topLayout.Padding           = UDim.new(0, 0)
	topLayout.Parent = topBar

	-- ── Wallet section (coins + lure) ──────────────────────────────
	local walletSec = Instance.new("Frame")
	walletSec.BackgroundTransparency = 1
	walletSec.BorderSizePixel  = 0
	walletSec.Size             = UDim2.new(0, 0, 1, 0)
	walletSec.AutomaticSize    = Enum.AutomaticSize.X
	walletSec.LayoutOrder      = 1
	walletSec.Parent = topBar

	local wl = Instance.new("UIListLayout")
	wl.FillDirection     = Enum.FillDirection.Horizontal
	wl.VerticalAlignment = Enum.VerticalAlignment.Center
	wl.Padding           = UDim.new(0, 6)
	wl.SortOrder         = Enum.SortOrder.LayoutOrder
	wl.Parent = walletSec

	local wp = Instance.new("UIPadding")
	wp.PaddingLeft  = UDim.new(0, 14)
	wp.PaddingRight = UDim.new(0, 12)
	wp.Parent = walletSec

	local coinsIcon = iconDisc(26, P.Gold, "$")
	coinsIcon.LayoutOrder = 1
	coinsIcon.Parent = walletSec

	local coinsLabel = valueLabel("0", 16)
	coinsLabel.Size        = UDim2.fromOffset(70, 26)
	coinsLabel.LayoutOrder = 2
	coinsLabel.Parent = walletSec

	local wDiv1 = Instance.new("Frame")
	wDiv1.BackgroundColor3       = P.TealDeeper
	wDiv1.BackgroundTransparency = 0.35
	wDiv1.BorderSizePixel        = 0
	wDiv1.Size                   = UDim2.fromOffset(2, 26)
	wDiv1.LayoutOrder            = 3
	wDiv1.Parent = walletSec

	local lureIcon = iconDisc(26, P.Lure, "★")
	lureIcon.LayoutOrder = 4
	lureIcon.Parent = walletSec

	local lureLabel = valueLabel("0", 16)
	lureLabel.Size        = UDim2.fromOffset(42, 26)
	lureLabel.LayoutOrder = 5
	lureLabel.Parent = walletSec

	-- Divider between wallet and level
	vDiv(topBar, 2)

	-- ── Level section ──────────────────────────────────────────────
	local levelSec = Instance.new("Frame")
	levelSec.BackgroundTransparency = 1
	levelSec.BorderSizePixel = 0
	levelSec.Size            = UDim2.fromOffset(96, 54)
	levelSec.LayoutOrder     = 3
	levelSec.Parent = topBar

	local levelHeader = smallCaps("level")
	levelHeader.Position = UDim2.new(0, 10, 0, 7)
	levelHeader.Size     = UDim2.new(1, -20, 0, 11)
	levelHeader.Parent   = levelSec

	local levelLabel = valueLabel("Lv 1", 16)
	levelLabel.Position = UDim2.new(0, 10, 0, 19)
	levelLabel.Size     = UDim2.new(1, -20, 0, 16)
	levelLabel.Parent   = levelSec

	local xpBg = Instance.new("Frame")
	xpBg.Position         = UDim2.new(0, 10, 1, -11)
	xpBg.Size             = UDim2.new(1, -20, 0, 5)
	xpBg.BackgroundColor3 = P.TealDeeper
	xpBg.BorderSizePixel  = 0
	local xpc = Instance.new("UICorner"); xpc.CornerRadius = UDim.new(1, 0); xpc.Parent = xpBg
	xpBg.Parent = levelSec

	local xpFill = Instance.new("Frame")
	xpFill.Size             = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = P.Sunset
	xpFill.BorderSizePixel  = 0
	local xpfc = Instance.new("UICorner"); xpfc.CornerRadius = UDim.new(1, 0); xpfc.Parent = xpFill
	xpFill.Parent = xpBg

	-- Divider between level and rod
	vDiv(topBar, 4)

	-- ── Rod chip (TextButton — tap opens rod rack) ──────────────────
	-- Slight background tint distinguishes it as interactive.
	local rodChip = Instance.new("TextButton")
	rodChip.Name             = "RodChip"
	rodChip.AutoButtonColor  = false
	rodChip.Text             = ""
	rodChip.BackgroundColor3 = P.TealDeeper
	rodChip.BackgroundTransparency = 0.65
	rodChip.BorderSizePixel  = 0
	rodChip.Size             = UDim2.new(0, 0, 1, 0)
	rodChip.AutomaticSize    = Enum.AutomaticSize.X
	rodChip.LayoutOrder      = 5
	rodChip.Parent = topBar

	-- Right rounded corners only — left side is flat against the divider.
	local rcc = Instance.new("UICorner"); rcc.CornerRadius = UDim.new(0, 14); rcc.Parent = rodChip

	-- This stroke is coloured by HUDController._applyRodTier to show the
	-- tier accent; it also pulses on tier-up. Keep it on the chip itself.
	local rodChipStroke = Instance.new("UIStroke")
	rodChipStroke.Color       = P.Common
	rodChipStroke.Thickness   = 1.5
	rodChipStroke.Transparency = 0.3
	rodChipStroke.Parent = rodChip

	local rcLayout = Instance.new("UIListLayout")
	rcLayout.FillDirection     = Enum.FillDirection.Horizontal
	rcLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rcLayout.Padding           = UDim.new(0, 8)
	rcLayout.SortOrder         = Enum.SortOrder.LayoutOrder
	rcLayout.Parent = rodChip

	local rcPad = Instance.new("UIPadding")
	rcPad.PaddingLeft  = UDim.new(0, 12)
	rcPad.PaddingRight = UDim.new(0, 14)
	rcPad.Parent = rodChip

	local rodChipIcon = iconDisc(26, P.Common, "⌇")
	rodChipIcon.Size        = UDim2.fromOffset(26, 26)
	rodChipIcon.LayoutOrder = 1
	rodChipIcon.Parent = rodChip

	-- Vertical text stack: "ROD" label / "Tier N" / rank pill
	local rodStack = Instance.new("Frame")
	rodStack.BackgroundTransparency = 1
	rodStack.BorderSizePixel        = 0
	rodStack.Size                   = UDim2.fromOffset(88, 44)
	rodStack.LayoutOrder            = 2
	rodStack.Parent = rodChip

	local rodHeader = smallCaps("rod")
	rodHeader.Position = UDim2.new(0, 0, 0, 4)
	rodHeader.Size     = UDim2.new(1, 0, 0, 11)
	rodHeader.Parent   = rodStack

	local rodChipValue = valueLabel("Tier 1", 15)
	rodChipValue.Position = UDim2.new(0, 0, 0, 16)
	rodChipValue.Size     = UDim2.new(1, 0, 0, 15)
	rodChipValue.Parent   = rodStack

	-- Rarity pill badge — colour + label updated by HUDController._applyRodRank
	local rodRankPill = Instance.new("Frame")
	rodRankPill.Name                = "RodRankPill"
	rodRankPill.BackgroundColor3    = P.Common
	rodRankPill.BackgroundTransparency = 0.68
	rodRankPill.BorderSizePixel     = 0
	rodRankPill.AutomaticSize       = Enum.AutomaticSize.X
	rodRankPill.Size                = UDim2.new(0, 0, 0, 14)
	rodRankPill.Position            = UDim2.new(0, 0, 0, 33)
	local rpc = Instance.new("UICorner"); rpc.CornerRadius = UDim.new(1, 0); rpc.Parent = rodRankPill
	local rps = Instance.new("UIStroke")
	rps.Color       = P.Common
	rps.Thickness   = 1
	rps.Transparency = 0.25
	rps.Parent = rodRankPill
	local rpp = Instance.new("UIPadding")
	rpp.PaddingLeft  = UDim.new(0, 5)
	rpp.PaddingRight = UDim.new(0, 5)
	rpp.Parent = rodRankPill

	local rodRankLabel = Instance.new("TextLabel")
	rodRankLabel.BackgroundTransparency = 1
	rodRankLabel.Size          = UDim2.new(0, 0, 1, 0)
	rodRankLabel.AutomaticSize = Enum.AutomaticSize.X
	rodRankLabel.Font          = Enum.Font.GothamBold
	rodRankLabel.TextSize      = 8
	rodRankLabel.TextColor3    = P.Cream
	rodRankLabel.Text          = "COMMON"
	rodRankLabel.Parent = rodRankPill

	rodRankPill.Parent = rodStack

	-- ================================================================
	-- BOTTOM ACTION BAR
	-- ================================================================
	local actionBar = Instance.new("Frame")
	actionBar.AnchorPoint      = Vector2.new(0.5, 1)
	actionBar.Position         = UDim2.new(0.5, 0, 1, -18)
	actionBar.Size             = UDim2.fromOffset(0, 84)
	actionBar.AutomaticSize    = Enum.AutomaticSize.X
	actionBar.BackgroundColor3 = P.TealDark
	actionBar.BorderSizePixel  = 0
	local abc = Instance.new("UICorner"); abc.CornerRadius = UDim.new(0, 14); abc.Parent = actionBar
	local abs_ = Instance.new("UIStroke"); abs_.Color = P.TealDeeper; abs_.Thickness = 1.5; abs_.Transparency = 0.25; abs_.Parent = actionBar
	actionBar.Parent = gui

	local abp = Instance.new("UIPadding")
	abp.PaddingLeft   = UDim.new(0, 10); abp.PaddingRight  = UDim.new(0, 10)
	abp.PaddingTop    = UDim.new(0, 10); abp.PaddingBottom = UDim.new(0, 10)
	abp.Parent = actionBar

	local abl = Instance.new("UIListLayout")
	abl.FillDirection    = Enum.FillDirection.Horizontal
	abl.VerticalAlignment = Enum.VerticalAlignment.Center
	abl.SortOrder        = Enum.SortOrder.LayoutOrder
	abl.Padding          = UDim.new(0, 8)
	abl.Parent = actionBar

	local rodBtn  = actionTile("⌇", "ROD",      P.Sunset,     "1"); rodBtn.Name  = "RodButton"
	local invBtn  = actionTile("▤", "BAG",      P.Wood,       "2"); invBtn.Name  = "InventoryButton"
	local mktBtn  = actionTile("$", "MARKET",   P.TealLight,  "3"); mktBtn.Name  = "MarketButton"
	local aquaBtn = actionTile("◉", "AQUARIUM", P.Rare,       "4"); aquaBtn.Name = "AquariumButton"
	local hrbBtn  = actionTile("▣", "BUILD",    P.SunsetDeep, "5"); hrbBtn.Name  = "HarborButton"
	local socBtn  = actionTile("♥", "CREW",     P.Lure,       "6"); socBtn.Name  = "SocialButton"
	local homeBtn = actionTile("⌂", "HOME",     P.Uncommon,   "7"); homeBtn.Name = "HomeButton"

	rodBtn.LayoutOrder  = 1; rodBtn.Parent  = actionBar
	invBtn.LayoutOrder  = 2; invBtn.Parent  = actionBar
	mktBtn.LayoutOrder  = 3; mktBtn.Parent  = actionBar
	aquaBtn.LayoutOrder = 4; aquaBtn.Parent = actionBar
	hrbBtn.LayoutOrder  = 5; hrbBtn.Parent  = actionBar
	socBtn.LayoutOrder  = 6; socBtn.Parent  = actionBar
	homeBtn.LayoutOrder = 7; homeBtn.Parent = actionBar

	return {
		gui            = gui,
		coinsLabel     = coinsLabel,
		lureLabel      = lureLabel,
		levelLabel     = levelLabel,
		xpFill         = xpFill,
		rodChip        = rodChip,
		rodChipIcon    = rodChipIcon,
		rodChipStroke  = rodChipStroke,
		rodChipValue   = rodChipValue,
		rodRankPill    = rodRankPill,
		rodRankLabel   = rodRankLabel,
		actionBar      = actionBar,
		rodButton      = rodBtn,
		inventoryButton = invBtn,
		marketButton   = mktBtn,
		harborButton   = hrbBtn,
		aquariumButton = aquaBtn,
		socialButton   = socBtn,
		homeButton     = homeBtn,
	}
end

return HUD
