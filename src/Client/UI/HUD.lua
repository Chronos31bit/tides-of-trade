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
--     DisplayOrder). Self-cleans via UIUtil.makeScreenGui.

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

-- -------------------------------------------------------------------
-- Tiny helpers — local to HUD so we don't pollute UIUtil with one-off
-- shapes. Each returns a single Instance, parented by the caller.
-- -------------------------------------------------------------------
local function pill(size: Vector2, bg: Color3): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = bg
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(size.X, size.Y)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = f
	return f
end

local function iconDisc(diameter: number, color: Color3, glyph: string): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(diameter, diameter)
	f.AnchorPoint = Vector2.new(0, 0.5)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = f
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, 1)
	g.Font = Enum.Font.GothamBlack
	g.TextSize = math.floor(diameter * 0.62)
	g.TextColor3 = P.Ink
	g.Text = glyph
	g.Parent = f
	return f
end

local function valueLabel(initial: string, size: number?): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = size or 18
	lbl.TextColor3 = P.Cream
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = initial
	return lbl
end

local function smallCaps(text: string): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 10
	lbl.TextColor3 = P.CreamSoft
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text:upper()
	return lbl
end

-- Action-bar tile: vertical stack of glyph + label, fully opaque. Returns
-- a TextButton so HUDController can hook .Activated on it.
local function actionTile(glyph: string, label: string, tint: Color3, keybind: string?): TextButton
	local btn = Instance.new("TextButton")
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = tint
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(68, 68)
	btn.Text = ""
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = P.Cream

	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = btn

	-- Slight darker rim so each tile reads as a separate object.
	local stroke = Instance.new("UIStroke")
	stroke.Color = P.TealDeeper
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = btn

	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Position = UDim2.new(0, 0, 0, 6)
	g.Size = UDim2.new(1, 0, 0.55, 0)
	g.Font = Enum.Font.GothamBlack
	g.TextSize = 24
	g.TextColor3 = P.Cream
	g.Text = glyph
	g.Parent = btn

	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Position = UDim2.new(0, 0, 0.6, 0)
	n.Size = UDim2.new(1, 0, 0.35, 0)
	n.Font = Enum.Font.GothamBold
	n.TextSize = 10
	n.TextColor3 = P.Cream
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.Text = label
	n.Parent = btn

	-- Small key-hint badge in the top-right corner (PC only hint).
	if keybind then
		local kb = Instance.new("TextLabel")
		kb.BackgroundTransparency = 1
		kb.AnchorPoint = Vector2.new(1, 0)
		kb.Position = UDim2.new(1, -4, 0, 4)
		kb.Size = UDim2.fromOffset(14, 14)
		kb.Font = Enum.Font.GothamBold
		kb.TextSize = 9
		kb.TextColor3 = P.Cream:Lerp(Color3.new(0, 0, 0), 0.35)
		kb.Text = keybind
		kb.Parent = btn
	end

	-- Tactile click feedback derived from the tile's tint.
	local TweenService = game:GetService("TweenService")
	local rest = tint
	local pressed = rest:Lerp(Color3.new(0, 0, 0), 0.22)
	local hover = rest:Lerp(Color3.new(1, 1, 1), 0.08)
	local tween = TweenInfo.new(0.08)
	btn.MouseEnter:Connect(function() TweenService:Create(btn, tween, { BackgroundColor3 = hover }):Play() end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = rest end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(btn, tween, { BackgroundColor3 = pressed }):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(btn, tween, { BackgroundColor3 = hover }):Play() end)

	return btn
end

-- -------------------------------------------------------------------
-- Main build
-- -------------------------------------------------------------------
function HUD.create(): HUDController
	-- respectTopbar=true means the ScreenGui's coordinate space starts
	-- BELOW the Roblox chat/menu icons, so our top-anchored elements
	-- don't collide with chrome.
	local gui = UIUtil.makeScreenGui("HUD", nil, { respectTopbar = true })

	-- ================================================================
	-- TOP-LEFT — single horizontal currency strip
	-- One opaque pill containing both coins and lure tokens side-by-side
	-- with vertical separators. Reads like a wallet, not a chip cloud.
	-- ================================================================
	local wallet = pill(Vector2.new(260, 44), P.TealDark)
	wallet.Position = UDim2.fromOffset(16, 16)
	wallet.Parent = gui

	-- COINS section
	local coinsIcon = iconDisc(28, P.Gold, "$")
	coinsIcon.Position = UDim2.new(0, 10, 0.5, 0)
	coinsIcon.Parent = wallet

	local coinsLabel = valueLabel("0", 18)
	coinsLabel.Position = UDim2.new(0, 44, 0, 0)
	coinsLabel.Size = UDim2.new(0, 80, 1, 0)
	coinsLabel.TextColor3 = P.Cream
	coinsLabel.Parent = wallet

	-- vertical divider
	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = P.TealDeeper
	divider.BorderSizePixel = 0
	divider.Position = UDim2.new(0, 132, 0.2, 0)
	divider.Size = UDim2.new(0, 2, 0.6, 0)
	divider.Parent = wallet

	-- LURE section
	local lureIcon = iconDisc(28, P.Lure, "★")
	lureIcon.Position = UDim2.new(0, 142, 0.5, 0)
	lureIcon.Parent = wallet

	local lureLabel = valueLabel("0", 18)
	lureLabel.Position = UDim2.new(0, 176, 0, 0)
	lureLabel.Size = UDim2.new(0, 80, 1, 0)
	lureLabel.TextColor3 = P.Cream
	lureLabel.Parent = wallet

	-- ================================================================
	-- TOP-RIGHT — level chip with XP bar + quest list under it
	-- ================================================================
	local statusCol = Instance.new("Frame")
	statusCol.BackgroundTransparency = 1
	statusCol.AnchorPoint = Vector2.new(1, 0)
	statusCol.Position = UDim2.new(1, -16, 0, 16)
	-- level chip (52) + rod chip (52) + 1 layout gap (8) = 112.
	-- Quest panel removed — QuestTrackerUI owns it now.
	statusCol.Size = UDim2.fromOffset(260, 112)
	statusCol.Parent = gui

	local statusLayout = Instance.new("UIListLayout")
	statusLayout.FillDirection = Enum.FillDirection.Vertical
	statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statusLayout.Padding = UDim.new(0, 8)
	statusLayout.Parent = statusCol

	-- LEVEL CHIP
	local levelChip = pill(Vector2.new(260, 52), P.TealDark)
	levelChip.LayoutOrder = 1
	levelChip.Parent = statusCol

	local levelHeader = smallCaps("level")
	levelHeader.Position = UDim2.new(0, 14, 0, 6)
	levelHeader.Size = UDim2.new(1, -28, 0, 12)
	levelHeader.Parent = levelChip

	local levelLabel = valueLabel("Lv 1", 18)
	levelLabel.Position = UDim2.new(0, 14, 0, 18)
	levelLabel.Size = UDim2.new(1, -28, 0, 18)
	levelLabel.TextColor3 = P.Cream
	levelLabel.Parent = levelChip

	-- XP bar
	local xpBg = Instance.new("Frame")
	xpBg.Position = UDim2.new(0, 14, 1, -12)
	xpBg.Size = UDim2.new(1, -28, 0, 6)
	xpBg.BackgroundColor3 = P.TealDeeper
	xpBg.BorderSizePixel = 0
	local xpc = Instance.new("UICorner"); xpc.CornerRadius = UDim.new(1, 0); xpc.Parent = xpBg
	xpBg.Parent = levelChip

	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = P.Sunset
	xpFill.BorderSizePixel = 0
	local xpfc = Instance.new("UICorner"); xpfc.CornerRadius = UDim.new(1, 0); xpfc.Parent = xpFill
	xpFill.Parent = xpBg

	-- ROD TIER CHIP
	-- Read-only pill. It's a TextButton so HUDController can hook .Activated
	-- (tap/click), MouseEnter (PC hover) and touch long-press to open the
	-- tooltip. Background stays TealDark like the other chips; the tier
	-- colour shows on the icon disc / stroke / value text (recoloured by
	-- HUDController via UIUtil.tierPalette).
	local rodChip = Instance.new("TextButton")
	rodChip.Name = "RodChip"
	rodChip.AutoButtonColor = false
	rodChip.Text = ""
	rodChip.BackgroundColor3 = P.TealDark
	rodChip.BorderSizePixel = 0
	rodChip.Size = UDim2.fromOffset(260, 52)
	rodChip.LayoutOrder = 2
	local rcc = Instance.new("UICorner"); rcc.CornerRadius = UDim.new(0, 10); rcc.Parent = rodChip
	local rodChipStroke = Instance.new("UIStroke")
	rodChipStroke.Color = P.Common
	rodChipStroke.Thickness = 1.5
	rodChipStroke.Transparency = 0.25
	rodChipStroke.Parent = rodChip
	rodChip.Parent = statusCol

	-- TODO(asset): swap this glyph for a proper rod-silhouette image asset
	-- once art is available (rbxassetid). Keep the disc + recolour logic.
	local rodChipIcon = iconDisc(28, P.Common, "⌇")
	rodChipIcon.Position = UDim2.new(0, 12, 0.5, 0)
	rodChipIcon.Parent = rodChip

	local rodHeader = smallCaps("rod")
	rodHeader.Position = UDim2.new(0, 50, 0, 8)
	rodHeader.Size = UDim2.new(1, -64, 0, 12)
	rodHeader.Parent = rodChip

	local rodChipValue = valueLabel("Tier 1", 18)
	rodChipValue.Position = UDim2.new(0, 50, 0, 22)
	rodChipValue.Size = UDim2.new(1, -64, 0, 22)
	rodChipValue.TextColor3 = P.Cream
	rodChipValue.Parent = rodChip

	-- ================================================================
	-- BOTTOM ACTION BAR
	-- AutomaticSize.X = bar shrinks to fit children, so the dark background
	-- never extends past the buttons.
	-- ================================================================
	local actionBar = Instance.new("Frame")
	actionBar.AnchorPoint = Vector2.new(0.5, 1)
	actionBar.Position = UDim2.new(0.5, 0, 1, -20)
	actionBar.Size = UDim2.fromOffset(0, 88)
	actionBar.AutomaticSize = Enum.AutomaticSize.X
	actionBar.BackgroundColor3 = P.TealDark
	actionBar.BorderSizePixel = 0
	local abc = Instance.new("UICorner"); abc.CornerRadius = UDim.new(0, 14); abc.Parent = actionBar
	local abs = Instance.new("UIStroke"); abs.Color = P.TealDeeper; abs.Thickness = 1.5; abs.Transparency = 0.25; abs.Parent = actionBar
	actionBar.Parent = gui

	local abp = Instance.new("UIPadding")
	abp.PaddingLeft = UDim.new(0, 10); abp.PaddingRight = UDim.new(0, 10)
	abp.PaddingTop = UDim.new(0, 10); abp.PaddingBottom = UDim.new(0, 10)
	abp.Parent = actionBar

	local abl = Instance.new("UIListLayout")
	abl.FillDirection = Enum.FillDirection.Horizontal
	abl.VerticalAlignment = Enum.VerticalAlignment.Center
	abl.Padding = UDim.new(0, 8)
	abl.Parent = actionBar

	-- 7 tiles total. Home goes last (rightmost) so it's a clear "go back" position.
	-- Named so TutorialController and any future tooltip system can target
	-- specific tiles via FindFirstChild without coupling to layout order.
	local rodBtn  = actionTile("⌇",  "ROD",      P.Sunset,     "1"); rodBtn.Name  = "RodButton"
	local invBtn  = actionTile("▤",  "BAG",      P.Wood,       "2"); invBtn.Name  = "InventoryButton"
	local mktBtn  = actionTile("$",  "MARKET",   P.TealLight,  "3"); mktBtn.Name  = "MarketButton"
	local aquaBtn = actionTile("◉",  "AQUARIUM", P.Rare,       "4"); aquaBtn.Name = "AquariumButton"
	local hrbBtn  = actionTile("▣",  "BUILD",    P.SunsetDeep, "5"); hrbBtn.Name  = "HarborButton"
	local socBtn  = actionTile("♥",  "CREW",     P.Lure,       "6"); socBtn.Name  = "SocialButton"
	local homeBtn = actionTile("⌂",  "HOME",     P.Uncommon,   "7"); homeBtn.Name = "HomeButton"
	rodBtn.LayoutOrder = 1; rodBtn.Parent = actionBar
	invBtn.LayoutOrder = 2; invBtn.Parent = actionBar
	mktBtn.LayoutOrder = 3; mktBtn.Parent = actionBar
	aquaBtn.LayoutOrder = 4; aquaBtn.Parent = actionBar
	hrbBtn.LayoutOrder = 5; hrbBtn.Parent = actionBar
	socBtn.LayoutOrder = 6; socBtn.Parent = actionBar
	homeBtn.LayoutOrder = 7; homeBtn.Parent = actionBar

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
		rodButton = rodBtn,
		inventoryButton = invBtn,
		marketButton = mktBtn,
		harborButton = hrbBtn,
		aquariumButton = aquaBtn,
		socialButton = socBtn,
		homeButton = homeBtn,
	}
end

return HUD
