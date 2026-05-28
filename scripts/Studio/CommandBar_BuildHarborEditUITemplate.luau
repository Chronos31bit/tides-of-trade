-- Command bar: build HarborEditUI_Template under StarterGui.StarterGuiAssets.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local S = GameConfig.UI.Spacing
local R = GameConfig.UI.Radii

local P = {
	Teal = Color3.fromRGB(38, 102, 110),
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	TealLight = Color3.fromRGB(78, 156, 162),
	Cream = Color3.fromRGB(244, 230, 200),
	CreamSoft = Color3.fromRGB(208, 198, 178),
	Sunset = Color3.fromRGB(232, 138, 86),
	Wood = Color3.fromRGB(139, 90, 43),
	Gold = Color3.fromRGB(220, 180, 88),
	Danger = Color3.fromRGB(196, 86, 64),
	ThumbLight = Color3.fromRGB(225, 232, 245),
	Common = Color3.fromRGB(176, 182, 190),
	Uncommon = Color3.fromRGB(95, 165, 120),
	Rare = Color3.fromRGB(95, 165, 240),
}

local ROW_W, ROW_H = 200, 100
local THUMB = 56
local BTN_H = 56
local ACTION_W = 140

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

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[HarborEditUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("HarborEditUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "HarborEditUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "Modal")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "RespectTopbar", true)

local hint = Instance.new("Frame")
hint.Name = "HintBanner"
hint.AnchorPoint = Vector2.new(0.5, 0)
hint.Position = UDim2.new(0.5, 0, 0, 16)
hint.Size = UDim2.new(0.7, 0, 0, 48)
hint.BackgroundColor3 = P.TealDark
hint.BorderSizePixel = 0
hint.Parent = gui
corner(hint, 10)
local hintStroke = Instance.new("UIStroke")
hintStroke.Color = P.TealDeeper
hintStroke.Thickness = 1.5
hintStroke.Transparency = 0.3
hintStroke.Parent = hint
local hintCap = Instance.new("UISizeConstraint")
hintCap.MaxSize = Vector2.new(720, 48)
hintCap.Parent = hint

local rotateBtn = Instance.new("TextButton")
rotateBtn.Name = "RotateButton"
rotateBtn.AutoButtonColor = false
rotateBtn.Text = "Rotate 90°"
rotateBtn.Font = Enum.Font.GothamBold
rotateBtn.TextSize = 14
rotateBtn.TextColor3 = P.Cream
rotateBtn.BackgroundColor3 = P.Wood
rotateBtn.BorderSizePixel = 0
rotateBtn.AnchorPoint = Vector2.new(1, 0.5)
rotateBtn.Position = UDim2.new(1, -12, 0.5, 0)
rotateBtn.Size = UDim2.fromOffset(100, 44)
rotateBtn.Parent = hint
corner(rotateBtn, R.sm)

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintLabel"
hintLabel.BackgroundTransparency = 1
hintLabel.Position = UDim2.new(0, 16, 0, 0)
hintLabel.Size = UDim2.new(1, -(16 + 100 + 12 + 16), 1, 0)
hintLabel.Font = Enum.Font.GothamMedium
hintLabel.TextSize = 15
hintLabel.TextColor3 = P.Cream
hintLabel.TextXAlignment = Enum.TextXAlignment.Left
hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
hintLabel.Text = "Pick a building below."
hintLabel.Parent = hint

local actions = Instance.new("Frame")
actions.Name = "ActionStack"
actions.AnchorPoint = Vector2.new(1, 0.5)
actions.Position = UDim2.new(1, -16, 0.5, 0)
actions.Size = UDim2.fromOffset(ACTION_W, 296)
actions.BackgroundTransparency = 1
actions.Parent = gui

local actLayout = Instance.new("UIListLayout")
actLayout.Padding = UDim.new(0, 10)
actLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
actLayout.Parent = actions

local function actionBtn(name: string, text: string, color: Color3, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = P.Cream
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(ACTION_W, BTN_H)
	b.LayoutOrder = order
	b.Parent = actions
	corner(b, R.sm)
	return b
end

actionBtn("PlaceButton", "Place", P.Sunset, 1)
actionBtn("UpgradeButton", "Upgrade", P.Gold, 2)
actionBtn("DemolishButton", "Demolish", P.Danger, 3)
actionBtn("CancelButton", "Cancel", P.Wood, 4)

local palette = Instance.new("Frame")
palette.Name = "BuildingPalette"
palette.AnchorPoint = Vector2.new(0.5, 1)
palette.Position = UDim2.new(0.5, 0, 1, -16)
palette.Size = UDim2.new(0.86, 0, 0, 132)
palette.BackgroundColor3 = P.TealDark
palette.BorderSizePixel = 0
palette.Parent = gui
corner(palette, 14)
local palStroke = Instance.new("UIStroke")
palStroke.Color = P.TealDeeper
palStroke.Thickness = 1.5
palStroke.Transparency = 0.3
palStroke.Parent = palette
local palCap = Instance.new("UISizeConstraint")
palCap.MaxSize = Vector2.new(900, 132)
palCap.Parent = palette

local palPad = Instance.new("UIPadding")
palPad.PaddingTop = UDim.new(0, 12)
palPad.PaddingBottom = UDim.new(0, 12)
palPad.PaddingLeft = UDim.new(0, 12)
palPad.PaddingRight = UDim.new(0, 12)
palPad.Parent = palette

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "BuildingScroll"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Size = UDim2.fromScale(1, 1)
scroll.ScrollingDirection = Enum.ScrollingDirection.X
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = P.TealDeeper
scroll.Parent = palette

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, 10)
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = scroll

local rowTpl = Instance.new("TextButton")
rowTpl.Name = "BuildingRow_Template"
rowTpl.AutoButtonColor = false
rowTpl.Text = ""
rowTpl.BackgroundColor3 = P.Teal
rowTpl.BorderSizePixel = 0
rowTpl.Size = UDim2.fromOffset(ROW_W, ROW_H)
rowTpl.Visible = false
rowTpl.Parent = gui
corner(rowTpl, 10)
local rowStroke = Instance.new("UIStroke")
rowStroke.Color = P.TealDeeper
rowStroke.Thickness = 1.2
rowStroke.Transparency = 0.4
rowStroke.Parent = rowTpl

local kindVal = Instance.new("StringValue")
kindVal.Name = "BuildingKind"
kindVal.Value = ""
kindVal.Parent = rowTpl

local vpf = Instance.new("ViewportFrame")
vpf.Name = "ThumbnailViewport"
vpf.Position = UDim2.fromOffset(8, 8)
vpf.Size = UDim2.fromOffset(THUMB, THUMB)
vpf.BackgroundColor3 = P.TealDeeper
vpf.BorderSizePixel = 0
vpf.LightColor = P.ThumbLight
vpf.LightDirection = Vector3.new(-1, -2, -1)
vpf.Parent = rowTpl
corner(vpf, R.sm)

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "NameLabel"
nameLbl.BackgroundTransparency = 1
nameLbl.Position = UDim2.new(0, THUMB + 14, 0, 8)
nameLbl.Size = UDim2.new(1, -(THUMB + 22), 0, 22)
nameLbl.Font = Enum.Font.GothamBold
nameLbl.TextSize = 15
nameLbl.TextColor3 = P.Cream
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
nameLbl.Text = "Building"
nameLbl.Parent = rowTpl

local footprintLbl = Instance.new("TextLabel")
footprintLbl.Name = "FootprintLabel"
footprintLbl.BackgroundTransparency = 1
footprintLbl.Position = UDim2.new(0, THUMB + 14, 0, 30)
footprintLbl.Size = UDim2.new(1, -(THUMB + 22), 0, 16)
footprintLbl.Font = Enum.Font.Gotham
footprintLbl.TextSize = 12
footprintLbl.TextColor3 = P.CreamSoft
footprintLbl.TextXAlignment = Enum.TextXAlignment.Left
footprintLbl.Text = "0 × 0 cells"
footprintLbl.Parent = rowTpl

local tierBadges = Instance.new("Frame")
tierBadges.Name = "TierBadges"
tierBadges.BackgroundTransparency = 1
tierBadges.Position = UDim2.new(0, THUMB + 14, 0, 48)
tierBadges.Size = UDim2.fromOffset(72, 14)
tierBadges.Parent = rowTpl
local badgeLayout = Instance.new("UIListLayout")
badgeLayout.FillDirection = Enum.FillDirection.Horizontal
badgeLayout.Padding = UDim.new(0, 4)
badgeLayout.Parent = tierBadges
for i = 1, 3 do
	local pip = Instance.new("Frame")
	pip.Name = "Tier" .. i
	pip.Size = UDim2.fromOffset(12, 12)
	pip.BackgroundColor3 = P.Common
	pip.BorderSizePixel = 0
	pip.LayoutOrder = i
	pip.Parent = tierBadges
	corner(pip, 6)
end

local costLbl = Instance.new("TextLabel")
costLbl.Name = "CostLabel"
costLbl.BackgroundTransparency = 1
costLbl.AnchorPoint = Vector2.new(0, 1)
costLbl.Position = UDim2.new(0, THUMB + 14, 1, -8)
costLbl.Size = UDim2.new(1, -(THUMB + 22), 0, 20)
costLbl.Font = Enum.Font.GothamBold
costLbl.TextSize = 15
costLbl.TextColor3 = P.Gold
costLbl.TextXAlignment = Enum.TextXAlignment.Left
costLbl.Text = "0 coins"
costLbl.Parent = rowTpl

local placeBtn = Instance.new("TextButton")
placeBtn.Name = "PlaceButton"
placeBtn.Visible = false
placeBtn.AutoButtonColor = false
placeBtn.Text = "Place"
placeBtn.Font = Enum.Font.GothamBold
placeBtn.TextSize = 11
placeBtn.TextColor3 = P.Cream
placeBtn.BackgroundColor3 = P.Sunset
placeBtn.BorderSizePixel = 0
placeBtn.AnchorPoint = Vector2.new(1, 1)
placeBtn.Position = UDim2.new(1, -6, 1, -6)
placeBtn.Size = UDim2.fromOffset(52, 28)
placeBtn.Parent = rowTpl
corner(placeBtn, R.sm)

local upgradeBtn = Instance.new("TextButton")
upgradeBtn.Name = "UpgradeButton"
upgradeBtn.Visible = false
upgradeBtn.AutoButtonColor = false
upgradeBtn.Text = "Up"
upgradeBtn.Font = Enum.Font.GothamBold
upgradeBtn.TextSize = 11
upgradeBtn.TextColor3 = P.Cream
upgradeBtn.BackgroundColor3 = P.Gold
upgradeBtn.BorderSizePixel = 0
upgradeBtn.AnchorPoint = Vector2.new(1, 1)
upgradeBtn.Position = UDim2.new(1, -62, 1, -6)
upgradeBtn.Size = UDim2.fromOffset(52, 28)
upgradeBtn.Parent = rowTpl
corner(upgradeBtn, R.sm)

gui.Parent = assets

print("[HarborEditUI] Built HarborEditUI_Template.")
print("[HarborEditUI] Save to file: src/StarterGuiAssets/HarborEditUI_Template.model.json")
