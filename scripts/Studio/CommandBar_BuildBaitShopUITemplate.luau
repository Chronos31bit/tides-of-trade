-- Command bar: build BaitShopUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.
--
-- After build: right-click BaitShopUI_Template → Save to File…
--   → src/StarterGuiAssets/BaitShopUI_Template.rbxmx (or .model.json)
--
-- Contract (runtime expects):
--   ScreenGui "BaitShopUI_Template" (Meta.DisplayOrderKey="Modal")
--     Body.BaitList (ScrollingFrame)
--     BaitTile_Template (tagged "TotBaitTile")
--       Icon, NameLabel, EffectDescLabel, PriceLabel, BuyButton, OwnedCountBadge

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local M = GameConfig.UI.Modal
local S = GameConfig.UI.Spacing
local R = GameConfig.UI.Radii

-- UIUtil.Palette (dark nautical chrome)
local P = {
	Teal         = Color3.fromRGB(38, 102, 110),
	TealDark     = Color3.fromRGB(18, 52, 60),
	TealDeeper   = Color3.fromRGB(10, 32, 40),
	TealLight    = Color3.fromRGB(78, 156, 162),
	Cream        = Color3.fromRGB(244, 230, 200),
	CreamSoft    = Color3.fromRGB(208, 198, 178),
	Sunset       = Color3.fromRGB(232, 138, 86),
	Gold         = Color3.fromRGB(220, 180, 88),
	Shadow       = Color3.new(0, 0, 0),
}

local PANEL_MAX_W = 520
local PANEL_HEIGHT_SCALE = 0.88
local TILE_H = 96
local TILE_ICON = 56
local TILE_TAG = "TotBaitTile"

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

local function numberValue(parent: Instance, name: string, value: number)
	local v = Instance.new("NumberValue")
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
	error("[BaitShopUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("BaitShopUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "BaitShopUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "Modal")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "IgnoreGuiInset", true)
numberValue(meta, "FadeDuration", M.FadeDuration)
numberValue(meta, "SlideOffsetPx", M.SlideOffsetPx)

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = P.Shadow
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = 1
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.BackgroundColor3 = P.TealDark
panel.BorderSizePixel = 0
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.92, 0, PANEL_HEIGHT_SCALE, 0)
panel.ZIndex = 2
panel.Parent = gui
corner(panel, R.lg)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = P.TealDeeper
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.25
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent = panel
local sizeCap = Instance.new("UISizeConstraint")
sizeCap.MaxSize = Vector2.new(PANEL_MAX_W, math.huge)
sizeCap.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = P.TealDeeper
header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, M.HeaderHeightPx)
header.ZIndex = 3
header.Parent = panel
corner(header, R.lg)

local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "Title"
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Bait Shop"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 20
titleLbl.TextColor3 = P.Cream
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Position = UDim2.fromOffset(S.lg, 0)
titleLbl.Size = UDim2.new(1, -(S.lg * 2 + M.CloseButtonPx), 1, 0)
titleLbl.ZIndex = 4
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AutoButtonColor = false
closeBtn.BorderSizePixel = 0
closeBtn.BackgroundColor3 = P.TealDeeper
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = P.CreamSoft
closeBtn.TextScaled = true
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -S.md, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(M.CloseButtonPx, M.CloseButtonPx)
closeBtn.ZIndex = 4
closeBtn.Parent = header
corner(closeBtn, R.sm)

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.new(0, 0, 0, M.HeaderHeightPx)
body.Size = UDim2.new(1, 0, 1, -M.HeaderHeightPx)
body.ZIndex = 2
body.Parent = panel
local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingLeft = UDim.new(0, M.BodyPaddingPx)
bodyPad.PaddingRight = UDim.new(0, M.BodyPaddingPx)
bodyPad.PaddingTop = UDim.new(0, M.BodyPaddingPx)
bodyPad.PaddingBottom = UDim.new(0, M.BodyPaddingPx)
bodyPad.Parent = body

local list = Instance.new("ScrollingFrame")
list.Name = "BaitList"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Size = UDim2.fromScale(1, 1)
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = P.TealDeeper
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ElasticBehavior = Enum.ElasticBehavior.Always
list.Parent = body
local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, S.sm)
listLayout.Parent = list

local tile = Instance.new("Frame")
tile.Name = "BaitTile_Template"
tile.BackgroundColor3 = P.Teal
tile.BorderSizePixel = 0
tile.Size = UDim2.new(1, 0, 0, TILE_H)
tile.Visible = false
tile.Parent = body
corner(tile, R.md)
local tileStroke = Instance.new("UIStroke")
tileStroke.Color = P.TealDeeper
tileStroke.Thickness = 1.5
tileStroke.Transparency = 0.25
tileStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
tileStroke.Parent = tile
CollectionService:AddTag(tile, TILE_TAG)

local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.BackgroundColor3 = P.TealDeeper
icon.BorderSizePixel = 0
icon.Position = UDim2.fromOffset(S.sm, S.sm)
icon.Size = UDim2.fromOffset(TILE_ICON, TILE_ICON)
icon.Image = ""
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = tile
corner(icon, R.sm)

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "NameLabel"
nameLbl.BackgroundTransparency = 1
nameLbl.Text = "Bait"
nameLbl.Font = Enum.Font.GothamBold
nameLbl.TextSize = 16
nameLbl.TextColor3 = P.Cream
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.Position = UDim2.new(0, TILE_ICON + S.md + S.sm, 0, 10)
nameLbl.Size = UDim2.new(1, -(TILE_ICON + 220), 0, 20)
nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
nameLbl.Parent = tile

local effectLbl = Instance.new("TextLabel")
effectLbl.Name = "EffectDescLabel"
effectLbl.BackgroundTransparency = 1
effectLbl.Text = "No boost"
effectLbl.Font = Enum.Font.Gotham
effectLbl.TextSize = 12
effectLbl.TextColor3 = P.CreamSoft
effectLbl.TextXAlignment = Enum.TextXAlignment.Left
effectLbl.Position = UDim2.new(0, TILE_ICON + S.md + S.sm, 0, 34)
effectLbl.Size = UDim2.new(1, -(TILE_ICON + 220), 0, 16)
effectLbl.TextTruncate = Enum.TextTruncate.AtEnd
effectLbl.Parent = tile

local priceLbl = Instance.new("TextLabel")
priceLbl.Name = "PriceLabel"
priceLbl.BackgroundTransparency = 1
priceLbl.Text = "0c"
priceLbl.Font = Enum.Font.GothamBold
priceLbl.TextSize = 14
priceLbl.TextColor3 = P.Gold
priceLbl.TextXAlignment = Enum.TextXAlignment.Left
priceLbl.Position = UDim2.new(0, TILE_ICON + S.md + S.sm, 0, 56)
priceLbl.Size = UDim2.new(0, 120, 0, 18)
priceLbl.Parent = tile

local buyBtn = Instance.new("TextButton")
buyBtn.Name = "BuyButton"
buyBtn.AutoButtonColor = false
buyBtn.Text = "Buy"
buyBtn.Font = Enum.Font.GothamBold
buyBtn.TextSize = 13
buyBtn.TextColor3 = P.Cream
buyBtn.BackgroundColor3 = P.Sunset
buyBtn.BorderSizePixel = 0
buyBtn.AnchorPoint = Vector2.new(1, 0.5)
buyBtn.Position = UDim2.new(1, -S.md, 0.5, 0)
buyBtn.Size = UDim2.fromOffset(110, 44)
buyBtn.Parent = tile
corner(buyBtn, R.sm)

local owned = Instance.new("TextLabel")
owned.Name = "OwnedCountBadge"
owned.BackgroundColor3 = P.TealDeeper
owned.BorderSizePixel = 0
owned.Text = "0"
owned.Font = Enum.Font.GothamBold
owned.TextSize = 12
owned.TextColor3 = P.Cream
owned.AnchorPoint = Vector2.new(0, 0)
owned.Position = UDim2.new(0, S.sm, 0, S.sm)
owned.Size = UDim2.fromOffset(22, 22)
owned.Visible = false
owned.Parent = tile
corner(owned, 999)

gui.Parent = assets

print("[BaitShopUI] Built BaitShopUI_Template under StarterGui.StarterGuiAssets.")
print("[BaitShopUI] Save to file: src/StarterGuiAssets/BaitShopUI_Template.rbxmx")

