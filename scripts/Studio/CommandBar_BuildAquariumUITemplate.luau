-- Command bar: build AquariumUI_Template under StarterGui.StarterGuiAssets.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
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
	Gold = Color3.fromRGB(220, 180, 88),
	Shadow = Color3.new(0, 0, 0),
	ThumbLight = Color3.fromRGB(225, 232, 245),
	Rare = Color3.fromRGB(95, 165, 240),
}

local maxCap = 0
local aq = BuildingCatalog.Aquarium
if aq and aq.tiers then
	for _, t in ipairs(aq.tiers) do
		maxCap = math.max(maxCap, t.aquariumCapacity or 0)
	end
end
if maxCap < 1 then
	maxCap = 24
end

local SLOT_W, SLOT_H = 152, 180
local THUMB = 88
local BTN_H = 44
local PANEL_MAX_W = 720
local PANEL_HEIGHT_SCALE = 0.88
local GRID_COLS = 3

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
	error("[AquariumUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("AquariumUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "AquariumUI_Template"
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
numberValue(meta, "MaxAquariumCapacity", maxCap)
numberValue(meta, "SlotGridColumns", GRID_COLS)
numberValue(meta, "SlotCellWidthPx", SLOT_W)
numberValue(meta, "SlotCellHeightPx", SLOT_H)

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
sizeCap.MaxSize = Vector2.new(10000, 10000)
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
titleLbl.Text = "Aquarium"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 20
titleLbl.TextColor3 = P.Cream
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Position = UDim2.fromOffset(S.lg, 0)
titleLbl.Size = UDim2.new(1, -(S.lg * 2 + M.CloseButtonPx + 130), 1, 0)
titleLbl.Parent = header

local capLbl = Instance.new("TextLabel")
capLbl.Name = "CapacityLabel"
capLbl.BackgroundTransparency = 1
capLbl.Text = "0 / 0"
capLbl.Font = Enum.Font.GothamBold
capLbl.TextSize = 16
capLbl.TextColor3 = P.Gold
capLbl.TextXAlignment = Enum.TextXAlignment.Right
capLbl.AnchorPoint = Vector2.new(1, 0.5)
capLbl.Position = UDim2.new(1, -(M.CloseButtonPx + S.xl), 0.5, 0)
capLbl.Size = UDim2.fromOffset(120, 26)
capLbl.Parent = header

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
closeBtn.Parent = header
corner(closeBtn, R.sm)

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.new(0, 0, 0, M.HeaderHeightPx)
body.Size = UDim2.new(1, 0, 1, -M.HeaderHeightPx)
body.Parent = panel
local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingLeft = UDim.new(0, M.BodyPaddingPx)
bodyPad.PaddingRight = UDim.new(0, M.BodyPaddingPx)
bodyPad.PaddingTop = UDim.new(0, M.BodyPaddingPx)
bodyPad.PaddingBottom = UDim.new(0, M.BodyPaddingPx)
bodyPad.Parent = body

local leftCol = Instance.new("Frame")
leftCol.Name = "AquariumColumn"
leftCol.BackgroundTransparency = 1
leftCol.Position = UDim2.new(0, 0, 0, 0)
leftCol.Size = UDim2.new(0.5, -S.sm, 1, 0)
leftCol.Parent = body

local leftHdr = Instance.new("TextLabel")
leftHdr.Name = "ColumnHeader"
leftHdr.BackgroundTransparency = 1
leftHdr.Text = "IN AQUARIUM (TAP TO REMOVE)"
leftHdr.Font = Enum.Font.GothamBold
leftHdr.TextSize = 14
leftHdr.TextColor3 = P.CreamSoft
leftHdr.Size = UDim2.new(1, 0, 0, 22)
leftHdr.Parent = leftCol

local leftScroll = Instance.new("ScrollingFrame")
leftScroll.Name = "AquariumSlotGrid"
leftScroll.BackgroundColor3 = P.Teal
leftScroll.BorderSizePixel = 0
leftScroll.Position = UDim2.new(0, 0, 0, 28)
leftScroll.Size = UDim2.new(1, 0, 1, -28)
leftScroll.ScrollBarThickness = 6
leftScroll.ScrollBarImageColor3 = P.TealDeeper
leftScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
leftScroll.ElasticBehavior = Enum.ElasticBehavior.Always
leftScroll.Parent = leftCol
corner(leftScroll, R.md)
local leftPad = Instance.new("UIPadding")
leftPad.PaddingTop = UDim.new(0, S.sm)
leftPad.PaddingBottom = UDim.new(0, S.sm)
leftPad.PaddingLeft = UDim.new(0, S.sm)
leftPad.PaddingRight = UDim.new(0, S.sm)
leftPad.Parent = leftScroll
local leftGrid = Instance.new("UIGridLayout")
leftGrid.Name = "GridLayout"
leftGrid.CellSize = UDim2.fromOffset(SLOT_W, SLOT_H)
leftGrid.CellPadding = UDim2.fromOffset(8, 8)
leftGrid.FillDirectionMaxCells = GRID_COLS
leftGrid.SortOrder = Enum.SortOrder.LayoutOrder
leftGrid.Parent = leftScroll

local rightCol = Instance.new("Frame")
rightCol.Name = "InventoryColumn"
rightCol.BackgroundTransparency = 1
rightCol.Position = UDim2.new(0.5, S.sm, 0, 0)
rightCol.Size = UDim2.new(0.5, -S.sm, 1, 0)
rightCol.Parent = body

local rightHdr = Instance.new("TextLabel")
rightHdr.Name = "ColumnHeader"
rightHdr.BackgroundTransparency = 1
rightHdr.Text = "INVENTORY (TAP TO ADD)"
rightHdr.Font = Enum.Font.GothamBold
rightHdr.TextSize = 14
rightHdr.TextColor3 = P.CreamSoft
rightHdr.Size = UDim2.new(1, -100, 0, 22)
rightHdr.Parent = rightCol

local sortBtn = Instance.new("TextButton")
sortBtn.Name = "SortButton"
sortBtn.AutoButtonColor = false
sortBtn.AnchorPoint = Vector2.new(1, 0)
sortBtn.Position = UDim2.new(1, 0, 0, 0)
sortBtn.Size = UDim2.fromOffset(92, 44)
sortBtn.Font = Enum.Font.GothamBold
sortBtn.TextSize = 12
sortBtn.TextColor3 = P.Cream
sortBtn.BackgroundColor3 = P.TealDark
sortBtn.BorderSizePixel = 0
sortBtn.Text = "Sort"
sortBtn.Parent = rightCol
corner(sortBtn, R.sm)

local rightScroll = Instance.new("ScrollingFrame")
rightScroll.Name = "InventorySlotGrid"
rightScroll.BackgroundColor3 = P.Teal
rightScroll.BorderSizePixel = 0
rightScroll.Position = UDim2.new(0, 0, 0, 48)
rightScroll.Size = UDim2.new(1, 0, 1, -48)
rightScroll.ScrollBarThickness = 6
rightScroll.ScrollBarImageColor3 = P.TealDeeper
rightScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rightScroll.ElasticBehavior = Enum.ElasticBehavior.Always
rightScroll.Parent = rightCol
corner(rightScroll, R.md)
local rightPad = Instance.new("UIPadding")
rightPad.PaddingTop = UDim.new(0, S.sm)
rightPad.PaddingBottom = UDim.new(0, S.sm)
rightPad.PaddingLeft = UDim.new(0, S.sm)
rightPad.PaddingRight = UDim.new(0, S.sm)
rightPad.Parent = rightScroll
local rightGrid = Instance.new("UIGridLayout")
rightGrid.Name = "GridLayout"
rightGrid.CellSize = UDim2.fromOffset(SLOT_W, SLOT_H)
rightGrid.CellPadding = UDim2.fromOffset(8, 8)
rightGrid.FillDirectionMaxCells = GRID_COLS
rightGrid.SortOrder = Enum.SortOrder.LayoutOrder
rightGrid.Parent = rightScroll

local slotTpl = Instance.new("Frame")
slotTpl.Name = "Slot_Template"
slotTpl.BackgroundColor3 = P.TealDark
slotTpl.BorderSizePixel = 0
slotTpl.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
slotTpl.Visible = false
slotTpl.Parent = body
corner(slotTpl, R.sm)

local ring = Instance.new("Frame")
ring.Name = "RarityRing"
ring.BackgroundTransparency = 1
ring.BorderSizePixel = 0
ring.AnchorPoint = Vector2.new(0.5, 0)
ring.Position = UDim2.new(0.5, 0, 0, 6)
ring.Size = UDim2.fromOffset(THUMB + 8, THUMB + 8)
ring.Parent = slotTpl
local ringStroke = Instance.new("UIStroke")
ringStroke.Color = P.Rare
ringStroke.Thickness = 2
ringStroke.Parent = ring

local vpf = Instance.new("ViewportFrame")
vpf.Name = "ViewportFrame"
vpf.AnchorPoint = Vector2.new(0.5, 0.5)
vpf.Position = UDim2.fromScale(0.5, 0.5)
vpf.Size = UDim2.fromOffset(THUMB, THUMB)
vpf.BackgroundColor3 = P.TealDeeper
vpf.BorderSizePixel = 0
vpf.LightColor = P.ThumbLight
vpf.LightDirection = Vector3.new(-1, -2, -1)
vpf.Parent = ring
corner(vpf, R.sm)

local emptyHint = Instance.new("TextLabel")
emptyHint.Name = "EmptyHint"
emptyHint.BackgroundTransparency = 1
emptyHint.Text = "Empty"
emptyHint.Font = Enum.Font.GothamMedium
emptyHint.TextSize = 12
emptyHint.TextColor3 = P.CreamSoft
emptyHint.AnchorPoint = Vector2.new(0.5, 0.5)
emptyHint.Position = UDim2.new(0.5, 0, 0, THUMB * 0.5 + 10)
emptyHint.Size = UDim2.fromOffset(THUMB, 20)
emptyHint.TextXAlignment = Enum.TextXAlignment.Center
emptyHint.Parent = slotTpl

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "NameLabel"
nameLbl.BackgroundTransparency = 1
nameLbl.Text = "Fish"
nameLbl.Font = Enum.Font.GothamBold
nameLbl.TextSize = 11
nameLbl.TextColor3 = P.Cream
nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
nameLbl.Position = UDim2.new(0, 4, 0, THUMB + 14)
nameLbl.Size = UDim2.new(1, -8, 0, 18)
nameLbl.Parent = slotTpl

local incomeLbl = Instance.new("TextLabel")
incomeLbl.Name = "IncomeRateLabel"
incomeLbl.BackgroundTransparency = 1
incomeLbl.Text = "+0 coins/hr"
incomeLbl.Font = Enum.Font.GothamBold
incomeLbl.TextSize = 11
incomeLbl.TextColor3 = P.Gold
incomeLbl.TextTruncate = Enum.TextTruncate.AtEnd
incomeLbl.TextXAlignment = Enum.TextXAlignment.Left
incomeLbl.Position = UDim2.new(0, 4, 0, THUMB + 34)
incomeLbl.Size = UDim2.new(1, -8, 0, 14)
incomeLbl.Parent = slotTpl

local pillStrip = Instance.new("Frame")
pillStrip.Name = "ModifierPillStrip"
pillStrip.BackgroundTransparency = 1
pillStrip.ClipsDescendants = true
pillStrip.Position = UDim2.new(0, 4, 1, -(BTN_H + 20))
pillStrip.Size = UDim2.new(1, -8, 0, 16)
pillStrip.Parent = slotTpl
local pillLayout = Instance.new("UIListLayout")
pillLayout.FillDirection = Enum.FillDirection.Horizontal
pillLayout.Padding = UDim.new(0, 2)
pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
pillLayout.Parent = pillStrip

local actionBtn = Instance.new("TextButton")
actionBtn.Name = "ActionButton"
actionBtn.AutoButtonColor = false
actionBtn.Text = "Add"
actionBtn.Font = Enum.Font.GothamBold
actionBtn.TextSize = 12
actionBtn.TextColor3 = P.Cream
actionBtn.BackgroundColor3 = P.TealLight
actionBtn.BorderSizePixel = 0
actionBtn.AnchorPoint = Vector2.new(0.5, 1)
actionBtn.Position = UDim2.new(0.5, 0, 1, -4)
actionBtn.Size = UDim2.new(1, -8, 0, BTN_H)
actionBtn.Parent = slotTpl
corner(actionBtn, R.sm)

gui.Parent = assets

print("[AquariumUI] Built AquariumUI_Template (maxCapacity=" .. maxCap .. ").")
print("[AquariumUI] Save to file: src/StarterGuiAssets/AquariumUI_Template.rbxmx")
