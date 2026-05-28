-- Command bar: build InventoryUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.
--
-- After build: right-click InventoryUI_Template → Save to File…
--   → src/StarterGuiAssets/InventoryUI_Template.rbxmx
-- Commit the .model.json (or .rbxmx) so Rojo syncs for the whole team.

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local M = GameConfig.UI.Modal
local S = GameConfig.UI.Spacing
local R = GameConfig.UI.Radii

-- UIUtil.Palette (inventory uses dark nautical chrome)
local P = {
	Teal         = Color3.fromRGB(38, 102, 110),
	TealDark     = Color3.fromRGB(18, 52, 60),
	TealDeeper   = Color3.fromRGB(10, 32, 40),
	TealLight    = Color3.fromRGB(78, 156, 162),
	Cream        = Color3.fromRGB(244, 230, 200),
	CreamSoft    = Color3.fromRGB(208, 198, 178),
	Wood         = Color3.fromRGB(120, 90, 60),
	Sunset       = Color3.fromRGB(232, 138, 86),
	Shadow       = Color3.new(0, 0, 0),
	ThumbLight   = Color3.fromRGB(225, 232, 245),
	Common       = Color3.fromRGB(176, 182, 190),
}

local CARD_W = 260
local CARD_H = 260
local THUMB_H = 110
local HEADER_H = 28
local BTN_H = 44
local PANEL_MAX_W = 700
local PANEL_HEIGHT_SCALE = 0.88
local FILTER_CHIP_TAG = "TotInvFilterChip"

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

local function actionBtn(name: string, text: string, bg: Color3, size: UDim2): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AutoButtonColor = false
	btn.Text = text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = P.Cream
	btn.BackgroundColor3 = bg
	btn.BorderSizePixel = 0
	btn.Size = size
	corner(btn, R.sm)
	return btn
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[InventoryUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("InventoryUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryUI_Template"
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
titleLbl.Text = "Inventory"
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

local listTop = (BTN_H + S.sm) * 2 + BTN_H + S.sm

local selectionRow = Instance.new("Frame")
selectionRow.Name = "SelectionRow"
selectionRow.BackgroundTransparency = 1
selectionRow.Size = UDim2.new(1, 0, 0, BTN_H)
selectionRow.Parent = body

local normalBtns = Instance.new("Frame")
normalBtns.Name = "NormalBtns"
normalBtns.BackgroundTransparency = 1
normalBtns.AnchorPoint = Vector2.new(1, 0)
normalBtns.Position = UDim2.new(1, 0, 0, 0)
normalBtns.Size = UDim2.fromOffset(96, BTN_H)
normalBtns.Parent = selectionRow
actionBtn("SelectBtn", "Select", P.TealLight, UDim2.fromOffset(96, BTN_H)).Parent = normalBtns

local selBtns = Instance.new("Frame")
selBtns.Name = "SelBtns"
selBtns.BackgroundTransparency = 1
selBtns.AnchorPoint = Vector2.new(1, 0)
selBtns.Position = UDim2.new(1, 0, 0, 0)
selBtns.Size = UDim2.fromOffset(296, BTN_H)
selBtns.Visible = false
selBtns.Parent = selectionRow
local selLayout = Instance.new("UIListLayout")
selLayout.FillDirection = Enum.FillDirection.Horizontal
selLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
selLayout.VerticalAlignment = Enum.VerticalAlignment.Center
selLayout.Padding = UDim.new(0, S.sm)
selLayout.Parent = selBtns
actionBtn("SelectAllBtn", "Select All", P.TealLight, UDim2.fromOffset(96, BTN_H)).Parent = selBtns
local sellSel = actionBtn("SellSelectedBtn", "Sell (0)", Color3.fromRGB(220, 100, 100), UDim2.fromOffset(104, BTN_H))
sellSel.Name = "SellSelectedBtn"
sellSel.Parent = selBtns
actionBtn("CancelBtn", "Cancel", P.Teal, UDim2.fromOffset(88, BTN_H)).Parent = selBtns

local filterRow = Instance.new("Frame")
filterRow.Name = "FilterRow"
filterRow.BackgroundTransparency = 1
filterRow.Position = UDim2.new(0, 0, 0, BTN_H + S.sm)
filterRow.Size = UDim2.new(1, 0, 0, BTN_H)
filterRow.Parent = body
local filterLayout = Instance.new("UIListLayout")
filterLayout.FillDirection = Enum.FillDirection.Horizontal
filterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
filterLayout.Padding = UDim.new(0, S.sm)
filterLayout.Parent = filterRow

local function filterChip(name: string, label: string, filterId: string, active: boolean): TextButton
	local chip = actionBtn(name, label, active and P.TealLight or P.Teal, UDim2.fromOffset(72, BTN_H))
	stringValue(chip, "FilterId", filterId)
	CollectionService:AddTag(chip, FILTER_CHIP_TAG)
	return chip
end

filterChip("FilterChip_All", "All", "all", true).Parent = filterRow
filterChip("FilterChip_Catch", "Catch", "catch", false).Parent = filterRow
filterChip("FilterChip_Preserved", "Preserved", "preserved", false).Parent = filterRow
filterChip("FilterChip_Goods", "Goods", "goods", false).Parent = filterRow

local sortControls = Instance.new("Frame")
sortControls.Name = "SortControls"
sortControls.BackgroundTransparency = 1
sortControls.Position = UDim2.new(0, 0, 0, (BTN_H + S.sm) * 2)
sortControls.Size = UDim2.new(1, 0, 0, BTN_H)
sortControls.Parent = body
local sortLayout = Instance.new("UIListLayout")
sortLayout.FillDirection = Enum.FillDirection.Horizontal
sortLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sortLayout.Padding = UDim.new(0, S.sm)
sortLayout.Parent = sortControls
actionBtn("RaritySortBtn", "Rarity ▼", P.TealLight, UDim2.fromOffset(104, BTN_H)).Parent = sortControls
actionBtn("PriceSortBtn", "Price ▼", P.Teal, UDim2.fromOffset(94, BTN_H)).Parent = sortControls

local gridContainer = Instance.new("ScrollingFrame")
gridContainer.Name = "GridContainer"
gridContainer.BackgroundTransparency = 1
gridContainer.BorderSizePixel = 0
gridContainer.Position = UDim2.new(0, 0, 0, listTop)
gridContainer.Size = UDim2.new(1, 0, 1, -listTop)
gridContainer.ScrollBarThickness = 6
gridContainer.ScrollBarImageColor3 = P.TealDeeper
gridContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
gridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
gridContainer.ElasticBehavior = Enum.ElasticBehavior.Always
gridContainer.Parent = body
local gridPad = Instance.new("UIPadding")
gridPad.PaddingLeft = UDim.new(0, S.sm)
gridPad.PaddingRight = UDim.new(0, S.sm)
gridPad.PaddingTop = UDim.new(0, S.sm)
gridPad.PaddingBottom = UDim.new(0, S.sm)
gridPad.Parent = gridContainer

local sectionList = Instance.new("Frame")
sectionList.Name = "SectionList"
sectionList.BackgroundTransparency = 1
sectionList.Size = UDim2.new(1, 0, 0, 0)
sectionList.AutomaticSize = Enum.AutomaticSize.Y
sectionList.Parent = gridContainer
local sectionListLayout = Instance.new("UIListLayout")
sectionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
sectionListLayout.Padding = UDim.new(0, S.md)
sectionListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sectionListLayout.Parent = sectionList

local sectionTpl = Instance.new("Frame")
sectionTpl.Name = "Section_Template"
sectionTpl.BackgroundTransparency = 1
sectionTpl.Size = UDim2.new(1, -S.md * 2, 0, 0)
sectionTpl.AutomaticSize = Enum.AutomaticSize.Y
sectionTpl.Visible = false
sectionTpl.Parent = sectionList

local sectionTitle = Instance.new("TextLabel")
sectionTitle.Name = "SectionTitle"
sectionTitle.BackgroundTransparency = 1
sectionTitle.Size = UDim2.new(1, 0, 0, 24)
sectionTitle.Font = Enum.Font.GothamBold
sectionTitle.TextSize = 16
sectionTitle.TextColor3 = P.CreamSoft
sectionTitle.TextXAlignment = Enum.TextXAlignment.Left
sectionTitle.Text = "SECTION"
sectionTitle.Parent = sectionTpl

local sectionGrid = Instance.new("Frame")
sectionGrid.Name = "SectionGrid"
sectionGrid.BackgroundTransparency = 1
sectionGrid.Position = UDim2.new(0, 0, 0, 28)
sectionGrid.Size = UDim2.new(1, 0, 0, 0)
sectionGrid.AutomaticSize = Enum.AutomaticSize.Y
sectionGrid.Parent = sectionTpl
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
gridLayout.CellPadding = UDim2.fromOffset(10, 10)
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = sectionGrid

local fishCardTpl = Instance.new("Frame")
fishCardTpl.Name = "FishCard_Template"
fishCardTpl.BackgroundColor3 = P.Teal
fishCardTpl.BorderSizePixel = 0
fishCardTpl.Size = UDim2.fromOffset(CARD_W, CARD_H)
fishCardTpl.Visible = false
fishCardTpl.Parent = body
corner(fishCardTpl, R.md)

local cardStroke = Instance.new("UIStroke")
cardStroke.Name = "CardStroke"
cardStroke.Color = P.TealDeeper
cardStroke.Thickness = 1
cardStroke.Transparency = 0.5
cardStroke.Parent = fishCardTpl

local rarityHeader = Instance.new("Frame")
rarityHeader.Name = "RarityHeader"
rarityHeader.BackgroundColor3 = P.Common
rarityHeader.BackgroundTransparency = 0.2
rarityHeader.BorderSizePixel = 0
rarityHeader.Size = UDim2.new(1, 0, 0, HEADER_H)
rarityHeader.Parent = fishCardTpl
corner(rarityHeader, R.md)

local rarityLabel = Instance.new("TextLabel")
rarityLabel.Name = "RarityLabel"
rarityLabel.BackgroundTransparency = 1
rarityLabel.Size = UDim2.new(1, 0, 0, HEADER_H)
rarityLabel.Font = Enum.Font.GothamBold
rarityLabel.TextSize = 12
rarityLabel.TextColor3 = Color3.new(1, 1, 1)
rarityLabel.Text = "COMMON"
rarityLabel.Parent = fishCardTpl

local thumbView = Instance.new("ViewportFrame")
thumbView.Name = "ThumbView"
thumbView.AnchorPoint = Vector2.new(0.5, 0)
thumbView.Position = UDim2.new(0.5, 0, 0, HEADER_H + 4)
thumbView.Size = UDim2.new(1, -16, 0, THUMB_H)
thumbView.BackgroundColor3 = P.TealDeeper
thumbView.BorderSizePixel = 0
thumbView.LightColor = P.ThumbLight
thumbView.LightDirection = Vector3.new(-1, -2, -1)
thumbView.Parent = fishCardTpl
corner(thumbView, R.md)

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "NameLabel"
nameLabel.BackgroundTransparency = 1
nameLabel.Position = UDim2.new(0, 10, 0, HEADER_H + 4 + THUMB_H + 8)
nameLabel.Size = UDim2.new(1, -90, 0, 18)
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextSize = 13
nameLabel.TextColor3 = P.Cream
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.Text = "Fish Name"
nameLabel.Parent = fishCardTpl

local weightLabel = Instance.new("TextLabel")
weightLabel.Name = "WeightLabel"
weightLabel.BackgroundTransparency = 1
weightLabel.AnchorPoint = Vector2.new(1, 0)
weightLabel.Position = UDim2.new(1, -10, 0, HEADER_H + 4 + THUMB_H + 8)
weightLabel.Size = UDim2.fromOffset(76, 18)
weightLabel.Font = Enum.Font.Gotham
weightLabel.TextSize = 12
weightLabel.TextColor3 = P.CreamSoft
weightLabel.TextXAlignment = Enum.TextXAlignment.Right
weightLabel.Text = "0.0 kg"
weightLabel.Parent = fishCardTpl

local pillContainer = Instance.new("Frame")
pillContainer.Name = "ModifierPillContainer"
pillContainer.BackgroundTransparency = 1
pillContainer.ClipsDescendants = true
pillContainer.Position = UDim2.new(0, 10, 0, HEADER_H + 4 + THUMB_H + 30)
pillContainer.Size = UDim2.new(1, -20, 0, 24)
pillContainer.Parent = fishCardTpl
local pillLayout = Instance.new("UIListLayout")
pillLayout.FillDirection = Enum.FillDirection.Horizontal
pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
pillLayout.Padding = UDim.new(0, 4)
pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pillLayout.Parent = pillContainer

local checkbox = Instance.new("Frame")
checkbox.Name = "Checkbox"
checkbox.Position = UDim2.new(0, 8, 0, HEADER_H + 6)
checkbox.Size = UDim2.fromOffset(24, 24)
checkbox.BackgroundColor3 = P.TealDark
checkbox.BackgroundTransparency = 0.2
checkbox.BorderSizePixel = 0
checkbox.Visible = false
checkbox.ZIndex = 4
checkbox.Parent = fishCardTpl
corner(checkbox, 999)
local chkStroke = Instance.new("UIStroke")
chkStroke.Color = P.TealLight
chkStroke.Thickness = 2
chkStroke.Transparency = 0.2
chkStroke.Parent = checkbox

local checkMark = Instance.new("TextLabel")
checkMark.Name = "CheckMark"
checkMark.BackgroundTransparency = 1
checkMark.Size = UDim2.fromScale(1, 1)
checkMark.Font = Enum.Font.GothamBold
checkMark.TextSize = 14
checkMark.TextColor3 = P.TealLight
checkMark.Text = "✓"
checkMark.Visible = false
checkMark.Parent = checkbox

local selectOverlay = Instance.new("TextButton")
selectOverlay.Name = "SelectOverlay"
selectOverlay.BackgroundTransparency = 1
selectOverlay.Size = UDim2.fromScale(1, 1)
selectOverlay.Text = ""
selectOverlay.Visible = false
selectOverlay.ZIndex = 5
selectOverlay.Parent = fishCardTpl

local actionRow = Instance.new("Frame")
actionRow.Name = "ActionRow"
actionRow.BackgroundTransparency = 1
actionRow.AnchorPoint = Vector2.new(0, 1)
actionRow.Position = UDim2.new(0, 8, 1, -8)
actionRow.Size = UDim2.new(1, -16, 0, BTN_H)
actionRow.Parent = fishCardTpl
local actionLayout = Instance.new("UIListLayout")
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
actionLayout.Padding = UDim.new(0, 4)
actionLayout.Parent = actionRow
local btnW = math.floor((CARD_W - 16 - 8) / 3)
actionBtn("SellBtn", "Sell", P.Wood, UDim2.fromOffset(btnW, BTN_H)).Parent = actionRow
actionBtn("ListBtn", "List", P.Sunset, UDim2.fromOffset(btnW, BTN_H)).Parent = actionRow
local holdBtn = actionBtn("HoldBtn", "Hold", P.TealLight, UDim2.fromOffset(btnW, BTN_H))
holdBtn.Visible = false
holdBtn.Parent = actionRow

gui.Parent = assets

print("[InventoryUI] Built InventoryUI_Template under StarterGui.StarterGuiAssets.")
print("[InventoryUI] Save to file: src/StarterGuiAssets/InventoryUI_Template.rbxmx")
