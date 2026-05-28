-- Command bar: build MarketUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local M = GameConfig.UI.Modal
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
	SunsetDeep = Color3.fromRGB(196, 86, 64),
	Gold = Color3.fromRGB(220, 180, 88),
	Shadow = Color3.new(0, 0, 0),
	ThumbLight = Color3.fromRGB(225, 232, 245),
	Common = Color3.fromRGB(176, 182, 190),
}

local ROW_H = 72
local THUMB = 56
local BTN_H = 44
local PANEL_MAX_W = 700
local PANEL_HEIGHT_SCALE = 0.88
local DEMAND_H = 44

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

local function label(name: string, text: string, size: UDim2, pos: UDim2, textSize: number, color: Color3, font: Enum.Font): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = font
	lbl.TextSize = textSize
	lbl.TextColor3 = color
	lbl.Size = size
	lbl.Position = pos
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	return lbl
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[MarketUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("MarketUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "MarketUI_Template"
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
titleLbl.Text = "Global Market"
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

local demandBanner = Instance.new("Frame")
demandBanner.Name = "DemandBanner"
demandBanner.Size = UDim2.new(1, 0, 0, DEMAND_H)
demandBanner.BackgroundColor3 = P.SunsetDeep
demandBanner.BorderSizePixel = 0
demandBanner.Parent = body
corner(demandBanner, R.md)

local dDot = Instance.new("Frame")
dDot.Name = "DemandDot"
dDot.BackgroundColor3 = P.Sunset
dDot.BorderSizePixel = 0
dDot.AnchorPoint = Vector2.new(0, 0.5)
dDot.Position = UDim2.new(0, S.md, 0.5, 0)
dDot.Size = UDim2.fromOffset(10, 10)
dDot.Parent = demandBanner
corner(dDot, 999)

local demandLbl = label("DemandLabel", "Loading demand…", UDim2.new(1, -(S.xl + 6 + S.md), 1, 0), UDim2.new(0, S.xl + 6, 0, 0), 15, P.Cream, Enum.Font.GothamBold)
demandLbl.Parent = demandBanner

local searchRow = Instance.new("Frame")
searchRow.Name = "SearchRow"
searchRow.BackgroundTransparency = 1
searchRow.Position = UDim2.new(0, 0, 0, DEMAND_H + S.md)
searchRow.Size = UDim2.new(1, 0, 0, 44)
searchRow.Parent = body

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchBox"
searchBox.PlaceholderText = "Search fish or seller…"
searchBox.Text = ""
searchBox.Font = Enum.Font.GothamMedium
searchBox.TextSize = 15
searchBox.TextColor3 = P.Cream
searchBox.PlaceholderColor3 = P.CreamSoft
searchBox.BackgroundColor3 = P.Teal
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.Size = UDim2.new(1, 0, 1, 0)
searchBox.Parent = searchRow
corner(searchBox, R.md)

local listTop = DEMAND_H + S.md + 44 + S.md
local listingScroll = Instance.new("ScrollingFrame")
listingScroll.Name = "ListingScroll"
listingScroll.BackgroundTransparency = 1
listingScroll.BorderSizePixel = 0
listingScroll.Position = UDim2.new(0, 0, 0, listTop)
listingScroll.Size = UDim2.new(1, 0, 1, -listTop)
listingScroll.ScrollBarThickness = 6
listingScroll.ScrollBarImageColor3 = P.TealDeeper
listingScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listingScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listingScroll.ElasticBehavior = Enum.ElasticBehavior.Always
listingScroll.Parent = body

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, S.sm)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listingScroll

local rowTpl = Instance.new("Frame")
rowTpl.Name = "ListingRow_Template"
rowTpl.BackgroundColor3 = P.Teal
rowTpl.BorderSizePixel = 0
rowTpl.Size = UDim2.new(1, 0, 0, ROW_H)
rowTpl.Visible = false
rowTpl.Parent = body
corner(rowTpl, R.md)

local thumb = Instance.new("ViewportFrame")
thumb.Name = "FishThumb"
thumb.Position = UDim2.new(0, S.md, 0.5, 0)
thumb.AnchorPoint = Vector2.new(0, 0.5)
thumb.Size = UDim2.fromOffset(THUMB, THUMB)
thumb.BackgroundColor3 = P.TealDeeper
thumb.BorderSizePixel = 0
thumb.LightColor = P.ThumbLight
thumb.LightDirection = Vector3.new(-1, -2, -1)
thumb.Parent = rowTpl
corner(thumb, R.md)

local rarityChip = Instance.new("Frame")
rarityChip.Name = "RarityChip"
rarityChip.BackgroundColor3 = P.Common
rarityChip.BackgroundTransparency = 0.08
rarityChip.BorderSizePixel = 0
rarityChip.Position = UDim2.new(0, S.md + THUMB + 6, 0, S.sm)
rarityChip.Size = UDim2.fromOffset(56, 20)
rarityChip.Parent = rowTpl
corner(rarityChip, R.sm)
local rarityLbl = label("RarityLabel", "COMMON", UDim2.fromScale(1, 1), UDim2.new(), 12, P.TealDeeper, Enum.Font.GothamBold)
rarityLbl.TextXAlignment = Enum.TextXAlignment.Center
rarityLbl.Parent = rarityChip

local fishName = label("FishName", "Fish", UDim2.new(0.45, 0, 0, 22), UDim2.new(0, S.md + THUMB + 6, 0, S.sm + 22), 16, P.Cream, Enum.Font.GothamBold)
fishName.Parent = rowTpl

local sellerLbl = label("SellerLabel", "by Seller", UDim2.new(0.45, 0, 0, 18), UDim2.new(0, S.md + THUMB + 6, 0, S.sm + 44), 12, P.CreamSoft, Enum.Font.Gotham)
sellerLbl.Parent = rowTpl

local priceLbl = label("PriceLabel", "0 coins", UDim2.fromOffset(100, 26), UDim2.new(1, -210, 0.5, 0), 18, P.Gold, Enum.Font.GothamBold)
priceLbl.AnchorPoint = Vector2.new(1, 0.5)
priceLbl.TextXAlignment = Enum.TextXAlignment.Right
priceLbl.Parent = rowTpl

local sparkline = Instance.new("Frame")
sparkline.Name = "SparklineSlot"
sparkline.BackgroundTransparency = 1
sparkline.AnchorPoint = Vector2.new(1, 1)
sparkline.Position = UDim2.new(1, -118, 1, -4)
sparkline.Size = UDim2.fromOffset(96, 0)
sparkline.Parent = rowTpl

local buyBtn = Instance.new("TextButton")
buyBtn.Name = "BuyButton"
buyBtn.AutoButtonColor = false
buyBtn.Text = "Buy"
buyBtn.Font = Enum.Font.GothamBold
buyBtn.TextSize = 13
buyBtn.TextColor3 = P.Cream
buyBtn.BackgroundColor3 = P.TealLight
buyBtn.BorderSizePixel = 0
buyBtn.AnchorPoint = Vector2.new(1, 0.5)
buyBtn.Position = UDim2.new(1, -S.sm, 0.5, 0)
buyBtn.Size = UDim2.fromOffset(96, BTN_H)
buyBtn.Parent = rowTpl
corner(buyBtn, R.sm)

local buyConfirm = Instance.new("Frame")
buyConfirm.Name = "BuyConfirm"
buyConfirm.BackgroundColor3 = P.TealDeeper
buyConfirm.BorderSizePixel = 0
buyConfirm.AnchorPoint = Vector2.new(1, 0.5)
buyConfirm.Position = UDim2.new(1, -S.sm, 0.5, 0)
buyConfirm.Size = UDim2.fromOffset(0, BTN_H)
buyConfirm.Visible = false
buyConfirm.ClipsDescendants = true
buyConfirm.Parent = rowTpl
corner(buyConfirm, R.sm)

local confirmLayout = Instance.new("UIListLayout")
confirmLayout.FillDirection = Enum.FillDirection.Horizontal
confirmLayout.VerticalAlignment = Enum.VerticalAlignment.Center
confirmLayout.Padding = UDim.new(0, 4)
confirmLayout.Parent = buyConfirm

local confirmBtn = Instance.new("TextButton")
confirmBtn.Name = "ConfirmBtn"
confirmBtn.AutoButtonColor = false
confirmBtn.Text = "Confirm"
confirmBtn.Font = Enum.Font.GothamBold
confirmBtn.TextSize = 12
confirmBtn.TextColor3 = P.Cream
confirmBtn.BackgroundColor3 = P.Sunset
confirmBtn.BorderSizePixel = 0
confirmBtn.Size = UDim2.fromOffset(88, BTN_H - 4)
confirmBtn.Parent = buyConfirm
corner(confirmBtn, R.sm)

local cancelBtn = Instance.new("TextButton")
cancelBtn.Name = "CancelBtn"
cancelBtn.AutoButtonColor = false
cancelBtn.Text = "Cancel"
cancelBtn.Font = Enum.Font.GothamBold
cancelBtn.TextSize = 12
cancelBtn.TextColor3 = P.CreamSoft
cancelBtn.BackgroundColor3 = P.Teal
cancelBtn.BorderSizePixel = 0
cancelBtn.Size = UDim2.fromOffset(72, BTN_H - 4)
cancelBtn.Parent = buyConfirm
corner(cancelBtn, R.sm)

gui.Parent = assets

print("[MarketUI] Built MarketUI_Template under StarterGui.StarterGuiAssets.")
print("[MarketUI] Save to file: src/StarterGuiAssets/MarketUI_Template.rbxmx")
