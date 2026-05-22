-- Command bar: build HUD_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.
--
-- After build: right-click HUD_Template → Save to File…
--   → src/StarterGuiAssets/HUD_Template.rbxmx
-- Commit the .rbxmx (or HUD_Template.model.json from Rojo) so the team syncs.

local StarterGui = game:GetService("StarterGui")

-- UIUtil.Palette (dark nautical HUD — not UIKit cozy palette)
local P = {
	Sunset       = Color3.fromRGB(232, 138, 86),
	SunsetDeep   = Color3.fromRGB(196, 86, 64),
	TealDark     = Color3.fromRGB(18, 52, 60),
	TealDeeper   = Color3.fromRGB(10, 32, 40),
	TealLight    = Color3.fromRGB(78, 156, 162),
	Wood         = Color3.fromRGB(120, 90, 60),
	Cream        = Color3.fromRGB(244, 230, 200),
	CreamSoft    = Color3.fromRGB(208, 198, 178),
	Ink          = Color3.fromRGB(40, 32, 28),
	Gold         = Color3.fromRGB(220, 180, 88),
	Lure         = Color3.fromRGB(200, 124, 220),
	Common       = Color3.fromRGB(176, 182, 190),
	Uncommon     = Color3.fromRGB(120, 205, 135),
	Rare         = Color3.fromRGB(95, 165, 240),
}

local RAD_MD = 10
local CAPTION = 12

local function boolValue(parent: Instance, name: string, value: boolean)
	local v = Instance.new("BoolValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function stringValue(parent: Instance, name: string, value: string)
	local v = Instance.new("StringValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local function pill(size: Vector2, bg: Color3): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = bg
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(size.X, size.Y)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, RAD_MD)
	c.Parent = f
	return f
end

local function iconDisc(name: string, diameter: number, color: Color3, glyph: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(diameter, diameter)
	f.AnchorPoint = Vector2.new(0, 0.5)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local g = Instance.new("TextLabel")
	g.Name = "Glyph"
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, 1)
	g.Font = Enum.Font.GothamBlack
	g.TextSize = math.floor(diameter * 0.62)
	g.TextColor3 = P.Ink
	g.Text = glyph
	g.Parent = f
	return f
end

local function valueLabel(name: string, initial: string, textSize: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = textSize
	lbl.TextColor3 = P.Cream
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.Text = initial
	return lbl
end

local function smallCaps(name: string, text: string): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = CAPTION
	lbl.TextColor3 = P.CreamSoft
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text:upper()
	return lbl
end

local function actionTile(
	name: string,
	glyph: string,
	label: string,
	tint: Color3,
	keybind: string,
	layoutOrder: number
): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.LayoutOrder = layoutOrder
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = tint
	btn.BorderSizePixel = 0
	btn.Size = UDim2.fromOffset(68, 68)
	btn.Text = ""

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 12)
	c.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = P.TealDeeper
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = btn

	local g = Instance.new("TextLabel")
	g.Name = "Glyph"
	g.BackgroundTransparency = 1
	g.Position = UDim2.new(0, 0, 0, 6)
	g.Size = UDim2.new(1, 0, 0.55, 0)
	g.Font = Enum.Font.GothamBlack
	g.TextSize = 24
	g.TextColor3 = P.Cream
	g.Text = glyph
	g.Parent = btn

	local n = Instance.new("TextLabel")
	n.Name = "Label"
	n.BackgroundTransparency = 1
	n.Position = UDim2.new(0, 0, 0.6, 0)
	n.Size = UDim2.new(1, 0, 0.35, 0)
	n.Font = Enum.Font.GothamBold
	n.TextSize = CAPTION
	n.TextColor3 = P.Cream
	n.TextXAlignment = Enum.TextXAlignment.Center
	n.Text = label
	n.Parent = btn

	local kb = Instance.new("TextLabel")
	kb.Name = "Keybind"
	kb.BackgroundTransparency = 1
	kb.AnchorPoint = Vector2.new(1, 0)
	kb.Position = UDim2.new(1, -4, 0, 4)
	kb.Size = UDim2.fromOffset(18, 18)
	kb.Font = Enum.Font.GothamBold
	kb.TextSize = CAPTION
	kb.TextColor3 = P.Cream:Lerp(Color3.new(0, 0, 0), 0.35)
	kb.Text = keybind
	kb.Parent = btn

	return btn
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[HUD] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("HUD_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "HUD_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ClipToDeviceSafeArea = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "HUD")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "RespectTopbar", true)

-- Wallet (built first, parented last so it draws above other HUD chrome)
local wallet = pill(Vector2.new(300, 44), P.TealDark)
wallet.Name = "Wallet"
wallet.Position = UDim2.fromOffset(16, 16)
wallet.ZIndex = 10

local coinsIcon = iconDisc("CoinsIcon", 28, P.Gold, "$")
coinsIcon.Position = UDim2.new(0, 10, 0.5, 0)
coinsIcon.Parent = wallet

local coinsLabel = valueLabel("CoinsLabel", "0", 18)
coinsLabel.Position = UDim2.new(0, 44, 0, 0)
coinsLabel.Size = UDim2.new(0, 110, 1, 0)
coinsLabel.Parent = wallet

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = P.TealDeeper
divider.BorderSizePixel = 0
divider.Position = UDim2.new(0, 158, 0.2, 0)
divider.Size = UDim2.new(0, 2, 0.6, 0)
divider.Parent = wallet

local lureIcon = iconDisc("LureIcon", 28, P.Lure, "★")
lureIcon.Position = UDim2.new(0, 168, 0.5, 0)
lureIcon.Parent = wallet

local lureLabel = valueLabel("LureLabel", "0", 18)
lureLabel.Position = UDim2.new(0, 202, 0, 0)
lureLabel.Size = UDim2.new(0, 80, 1, 0)
lureLabel.Parent = wallet

-- Status column
local statusCol = Instance.new("Frame")
statusCol.Name = "StatusColumn"
statusCol.BackgroundTransparency = 1
statusCol.AnchorPoint = Vector2.new(1, 0)
statusCol.Position = UDim2.new(1, -16, 0, 16)
statusCol.Size = UDim2.fromOffset(260, 112)
statusCol.Parent = gui

local statusLayout = Instance.new("UIListLayout")
statusLayout.FillDirection = Enum.FillDirection.Vertical
statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
statusLayout.Padding = UDim.new(0, 8)
statusLayout.Parent = statusCol

local levelChip = pill(Vector2.new(260, 52), P.TealDark)
levelChip.Name = "LevelChip"
levelChip.LayoutOrder = 1
levelChip.Parent = statusCol

local levelHeader = smallCaps("LevelHeader", "level")
levelHeader.Position = UDim2.new(0, 14, 0, 6)
levelHeader.Size = UDim2.new(1, -28, 0, 12)
levelHeader.Parent = levelChip

local levelLabel = valueLabel("LevelLabel", "Lv 1", 18)
levelLabel.Position = UDim2.new(0, 14, 0, 18)
levelLabel.Size = UDim2.new(1, -28, 0, 18)
levelLabel.Parent = levelChip

local xpBg = Instance.new("Frame")
xpBg.Name = "XpBg"
xpBg.Position = UDim2.new(0, 14, 1, -12)
xpBg.Size = UDim2.new(1, -28, 0, 6)
xpBg.BackgroundColor3 = P.TealDeeper
xpBg.BorderSizePixel = 0
local xpc = Instance.new("UICorner")
xpc.CornerRadius = UDim.new(1, 0)
xpc.Parent = xpBg
xpBg.Parent = levelChip

local xpFill = Instance.new("Frame")
xpFill.Name = "XpFill"
xpFill.Size = UDim2.new(0, 0, 1, 0)
xpFill.BackgroundColor3 = P.Sunset
xpFill.BorderSizePixel = 0
local xpfc = Instance.new("UICorner")
xpfc.CornerRadius = UDim.new(1, 0)
xpfc.Parent = xpFill
xpFill.Parent = xpBg

local rodChip = Instance.new("TextButton")
rodChip.Name = "RodChip"
rodChip.AutoButtonColor = false
rodChip.Text = ""
rodChip.BackgroundColor3 = P.TealDark
rodChip.BorderSizePixel = 0
rodChip.Size = UDim2.fromOffset(260, 52)
rodChip.LayoutOrder = 2
local rcc = Instance.new("UICorner")
rcc.CornerRadius = UDim.new(0, 10)
rcc.Parent = rodChip
local rodChipStroke = Instance.new("UIStroke")
rodChipStroke.Color = P.Common
rodChipStroke.Thickness = 1.5
rodChipStroke.Transparency = 0.25
rodChipStroke.Parent = rodChip
rodChip.Parent = statusCol

local rodChipIcon = iconDisc("RodChipIcon", 28, P.Common, "⌇")
rodChipIcon.Position = UDim2.new(0, 12, 0.5, 0)
rodChipIcon.Parent = rodChip

local rodHeader = smallCaps("RodHeader", "rod")
rodHeader.Position = UDim2.new(0, 50, 0, 8)
rodHeader.Size = UDim2.new(1, -64, 0, 12)
rodHeader.Parent = rodChip

local rodChipValue = valueLabel("RodChipValue", "Tier 1", 18)
rodChipValue.Position = UDim2.new(0, 50, 0, 22)
rodChipValue.Size = UDim2.new(1, -64, 0, 22)
rodChipValue.Parent = rodChip

-- Action bar
local actionBar = Instance.new("Frame")
actionBar.Name = "ActionBar"
actionBar.AnchorPoint = Vector2.new(0.5, 1)
actionBar.Position = UDim2.new(0.5, 0, 1, -20)
actionBar.Size = UDim2.fromOffset(0, 88)
actionBar.AutomaticSize = Enum.AutomaticSize.X
actionBar.BackgroundColor3 = P.TealDark
actionBar.BorderSizePixel = 0
local abc = Instance.new("UICorner")
abc.CornerRadius = UDim.new(0, 14)
abc.Parent = actionBar
local abs = Instance.new("UIStroke")
abs.Color = P.TealDeeper
abs.Thickness = 1.5
abs.Transparency = 0.25
abs.Parent = actionBar
actionBar.Parent = gui

local abp = Instance.new("UIPadding")
abp.PaddingLeft = UDim.new(0, 10)
abp.PaddingRight = UDim.new(0, 10)
abp.PaddingTop = UDim.new(0, 10)
abp.PaddingBottom = UDim.new(0, 10)
abp.Parent = actionBar

local abl = Instance.new("UIListLayout")
abl.FillDirection = Enum.FillDirection.Horizontal
abl.VerticalAlignment = Enum.VerticalAlignment.Center
abl.SortOrder = Enum.SortOrder.LayoutOrder
abl.Padding = UDim.new(0, 8)
abl.Parent = actionBar

actionTile("RodButton", "⌇", "ROD", P.Sunset, "1", 1).Parent = actionBar
actionTile("InventoryButton", "▤", "BAG", P.Wood, "2", 2).Parent = actionBar
actionTile("MarketButton", "$", "MARKET", P.TealLight, "3", 3).Parent = actionBar
actionTile("AquariumButton", "◉", "AQUARIUM", P.Rare, "4", 4).Parent = actionBar
actionTile("HarborButton", "▣", "BUILD", P.SunsetDeep, "5", 5).Parent = actionBar
actionTile("SocialButton", "♥", "CREW", P.Lure, "6", 6).Parent = actionBar
actionTile("HomeButton", "⌂", "HOME", P.Uncommon, "7", 7).Parent = actionBar

wallet.Parent = gui
gui.Parent = assets

print("[HUD] Built HUD_Template under StarterGui.StarterGuiAssets.")
print("[HUD] Save to file: src/StarterGuiAssets/HUD_Template.rbxmx")
