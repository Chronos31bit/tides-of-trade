-- Command bar: build SmokehouseUI_Template under StarterGui.StarterGuiAssets.

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
	Sunset = Color3.fromRGB(232, 138, 86),
	SunsetSoft = Color3.fromRGB(200, 120, 80),
	Gold = Color3.fromRGB(220, 180, 88),
	Shadow = Color3.new(0, 0, 0),
	ThumbLight = Color3.fromRGB(225, 232, 245),
}

local maxSlots = 0
local sh = BuildingCatalog.Smokehouse
if sh and sh.tiers then
	for _, t in ipairs(sh.tiers) do
		maxSlots = math.max(maxSlots, t.smokehouseSlots or 0)
	end
end
if maxSlots < 1 then
	maxSlots = 10
end

local SLOT_H = 72
local THUMB = 56
local BTN_H = 44
local PANEL_MAX_W = 720
local PANEL_HEIGHT_SCALE = 0.88

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
	error("[SmokehouseUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("SmokehouseUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "SmokehouseUI_Template"
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
numberValue(meta, "MaxSmokehouseSlots", maxSlots)

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
titleLbl.Text = "Smokehouse"
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 20
titleLbl.TextColor3 = P.Cream
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Position = UDim2.fromOffset(S.lg, 0)
titleLbl.Size = UDim2.new(1, -(S.lg * 2 + M.CloseButtonPx + 280), 1, 0)
titleLbl.Parent = header

local collectAllBtn = Instance.new("TextButton")
collectAllBtn.Name = "CollectAllButton"
collectAllBtn.AutoButtonColor = false
collectAllBtn.Text = "Collect All"
collectAllBtn.Font = Enum.Font.GothamBold
collectAllBtn.TextSize = 13
collectAllBtn.TextColor3 = P.Cream
collectAllBtn.BackgroundColor3 = P.Sunset
collectAllBtn.BorderSizePixel = 0
collectAllBtn.AnchorPoint = Vector2.new(1, 0.5)
collectAllBtn.Position = UDim2.new(1, -(M.CloseButtonPx + S.xl + 130), 0.5, 0)
collectAllBtn.Size = UDim2.fromOffset(120, BTN_H)
collectAllBtn.Parent = header
corner(collectAllBtn, R.sm)

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

local function makeColumn(name: string, headerText: string, xAnchor: number)
	local col = Instance.new("Frame")
	col.Name = name
	col.BackgroundTransparency = 1
	col.Position = UDim2.new(xAnchor, xAnchor == 0 and 0 or S.sm, 0, 0)
	col.Size = UDim2.new(0.5, -S.sm, 1, 0)
	col.Parent = body
	local hdr = Instance.new("TextLabel")
	hdr.Name = "ColumnHeader"
	hdr.BackgroundTransparency = 1
	hdr.Text = headerText
	hdr.Font = Enum.Font.GothamBold
	hdr.TextSize = 14
	hdr.TextColor3 = P.CreamSoft
	hdr.Size = UDim2.new(1, 0, 0, 22)
	hdr.Parent = col
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name == "SmokeColumn" and "SmokeSlotGrid" or "InventorySlotGrid"
	scroll.BackgroundColor3 = P.Teal
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.new(0, 0, 0, 28)
	scroll.Size = UDim2.new(1, 0, 1, -28)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = P.TealDeeper
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = col
	corner(scroll, R.md)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, S.sm)
	pad.PaddingBottom = UDim.new(0, S.sm)
	pad.PaddingLeft = UDim.new(0, S.sm)
	pad.PaddingRight = UDim.new(0, S.sm)
	pad.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	return scroll
end

makeColumn("SmokeColumn", "SLOTS", 0)
makeColumn("InventoryColumn", "INVENTORY (TAP TO SMOKE)", 0.5)

local slotTpl = Instance.new("Frame")
slotTpl.Name = "SmokeSlot_Template"
slotTpl.BackgroundColor3 = P.TealDark
slotTpl.BorderSizePixel = 0
slotTpl.Size = UDim2.new(1, 0, 0, SLOT_H)
slotTpl.Visible = false
slotTpl.Parent = body
corner(slotTpl, R.sm)

local vpf = Instance.new("ViewportFrame")
vpf.Name = "ThumbViewport"
vpf.Position = UDim2.fromOffset(8, 8)
vpf.Size = UDim2.fromOffset(THUMB, THUMB)
vpf.BackgroundColor3 = P.TealDeeper
vpf.BorderSizePixel = 0
vpf.LightColor = P.ThumbLight
vpf.LightDirection = Vector3.new(-1, -2, -1)
vpf.Parent = slotTpl
corner(vpf, R.sm)

local ring = Instance.new("Frame")
ring.Name = "ProgressRing"
ring.BackgroundColor3 = P.TealDeeper
ring.BorderSizePixel = 0
ring.Position = UDim2.new(0, THUMB + 16, 0, 44)
ring.Size = UDim2.new(1, -(THUMB + 100), 0, 8)
ring.Parent = slotTpl
corner(ring, 4)
local ringFill = Instance.new("Frame")
ringFill.Name = "ProgressFill"
ringFill.BackgroundColor3 = P.Sunset
ringFill.BorderSizePixel = 0
ringFill.Size = UDim2.fromScale(0, 1)
ringFill.Parent = ring
corner(ringFill, 4)

local timeLbl = Instance.new("TextLabel")
timeLbl.Name = "TimeLabel"
timeLbl.BackgroundTransparency = 1
timeLbl.Position = UDim2.new(0, THUMB + 16, 0, 26)
timeLbl.Size = UDim2.new(1, -(THUMB + 100), 0, 16)
timeLbl.Font = Enum.Font.Gotham
timeLbl.TextSize = 12
timeLbl.TextColor3 = P.SunsetSoft
timeLbl.TextXAlignment = Enum.TextXAlignment.Left
timeLbl.Text = ""
timeLbl.Parent = slotTpl

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "FishNameLabel"
nameLbl.BackgroundTransparency = 1
nameLbl.Position = UDim2.new(0, THUMB + 16, 0, 8)
nameLbl.Size = UDim2.new(1, -(THUMB + 100), 0, 18)
nameLbl.Font = Enum.Font.GothamBold
nameLbl.TextSize = 14
nameLbl.TextColor3 = P.Cream
nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
nameLbl.Text = "Fish"
nameLbl.Parent = slotTpl

local emptyHint = Instance.new("TextLabel")
emptyHint.Name = "EmptyHint"
emptyHint.BackgroundTransparency = 1
emptyHint.Position = UDim2.new(0, THUMB + 16, 0, 0)
emptyHint.Size = UDim2.new(1, -(THUMB + 24), 1, 0)
emptyHint.Font = Enum.Font.Gotham
emptyHint.TextSize = 13
emptyHint.TextColor3 = P.CreamSoft
emptyHint.TextXAlignment = Enum.TextXAlignment.Left
emptyHint.TextYAlignment = Enum.TextYAlignment.Center
emptyHint.Text = "Empty"
emptyHint.Parent = slotTpl

local collectBtn = Instance.new("TextButton")
collectBtn.Name = "CollectButton"
collectBtn.AutoButtonColor = false
collectBtn.Text = "Claim"
collectBtn.Font = Enum.Font.GothamBold
collectBtn.TextSize = 12
collectBtn.TextColor3 = P.Cream
collectBtn.BackgroundColor3 = P.TealLight
collectBtn.BorderSizePixel = 0
collectBtn.AnchorPoint = Vector2.new(1, 0.5)
collectBtn.Position = UDim2.new(1, -8, 0.5, 0)
collectBtn.Size = UDim2.fromOffset(80, BTN_H)
collectBtn.Parent = slotTpl
corner(collectBtn, R.sm)

local invTpl = Instance.new("Frame")
invTpl.Name = "InvFishRow_Template"
invTpl.BackgroundColor3 = P.TealDark
invTpl.BorderSizePixel = 0
invTpl.Size = UDim2.new(1, 0, 0, 56)
invTpl.Visible = false
invTpl.Parent = body
corner(invTpl, R.sm)

local invVpf = Instance.new("ViewportFrame")
invVpf.Name = "ThumbViewport"
invVpf.Position = UDim2.fromOffset(8, 0)
invVpf.Size = UDim2.fromOffset(48, 48)
invVpf.AnchorPoint = Vector2.new(0, 0.5)
invVpf.Position = UDim2.new(0, 8, 0.5, 0)
invVpf.BackgroundColor3 = P.TealDeeper
invVpf.BorderSizePixel = 0
invVpf.LightColor = P.ThumbLight
invVpf.LightDirection = Vector3.new(-1, -2, -1)
invVpf.Parent = invTpl
corner(invVpf, R.sm)

local invName = Instance.new("TextLabel")
invName.Name = "FishNameLabel"
invName.BackgroundTransparency = 1
invName.Position = UDim2.new(0, 64, 0, 8)
invName.Size = UDim2.new(1, -160, 0, 40)
invName.Font = Enum.Font.GothamBold
invName.TextSize = 14
invName.TextColor3 = P.Cream
invName.TextTruncate = Enum.TextTruncate.AtEnd
invName.Text = "Fish"
invName.Parent = invTpl

local smokeBtn = Instance.new("TextButton")
smokeBtn.Name = "SmokeButton"
smokeBtn.AutoButtonColor = false
smokeBtn.Text = "Smoke"
smokeBtn.Font = Enum.Font.GothamBold
smokeBtn.TextSize = 12
smokeBtn.TextColor3 = P.Cream
smokeBtn.BackgroundColor3 = P.Sunset
smokeBtn.BorderSizePixel = 0
smokeBtn.AnchorPoint = Vector2.new(1, 0.5)
smokeBtn.Position = UDim2.new(1, -8, 0.5, 0)
smokeBtn.Size = UDim2.fromOffset(80, BTN_H)
smokeBtn.Parent = invTpl
corner(smokeBtn, R.sm)

gui.Parent = assets

print("[SmokehouseUI] Built SmokehouseUI_Template (maxSlots=" .. maxSlots .. ").")
print("[SmokehouseUI] Save to file: src/StarterGuiAssets/SmokehouseUI_Template.model.json")
