-- Command bar: build RodSelectUI_Template under StarterGui.StarterGuiAssets.

local StarterGui = game:GetService("StarterGui")

local P = {
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	Sunset = Color3.fromRGB(232, 138, 86),
	Wood = Color3.fromRGB(120, 90, 60),
	WoodDark = Color3.fromRGB(78, 58, 40),
	Cream = Color3.fromRGB(244, 230, 200),
}

local HEADER_H, ROW_H, STRIP_W, BTN_W = 54, 84, 52, 88

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
	error("[RodSelectUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("RodSelectUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "RodSelectUI_Template"
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

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.5
backdrop.BorderSizePixel = 0
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = 1
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -16)
panel.Size = UDim2.new(0.94, 0, 0, 480)
panel.BackgroundColor3 = P.TealDark
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.ZIndex = 2
panel.Parent = gui
corner(panel, 12)
local cap = Instance.new("UISizeConstraint")
cap.MaxSize = Vector2.new(420, 99999)
cap.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Rod Rack"
title.TextColor3 = P.Cream
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Position = UDim2.new(0, 14, 0, 0)
title.Size = UDim2.new(1, -64, 1, 0)
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AutoButtonColor = false
closeBtn.BackgroundColor3 = P.Wood
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = P.Cream
closeBtn.TextScaled = true
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -8, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(44, 44)
closeBtn.Parent = header
corner(closeBtn, 10)

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = P.TealDeeper
divider.BackgroundTransparency = 0.5
divider.BorderSizePixel = 0
divider.Position = UDim2.new(0, 0, 0, HEADER_H)
divider.Size = UDim2.new(1, 0, 0, 1)
divider.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "RodList"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 0, 0, HEADER_H + 2)
list.Size = UDim2.new(1, 0, 1, -(HEADER_H + 2))
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = P.TealDeeper
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.CanvasSize = UDim2.new()
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = list

local rowTpl = Instance.new("Frame")
rowTpl.Name = "RodRow_Template"
rowTpl.Size = UDim2.new(1, 0, 0, ROW_H)
rowTpl.BackgroundColor3 = P.TealDark
rowTpl.Visible = false
rowTpl.Parent = gui
corner(rowTpl, 10)

local tierBadge = Instance.new("Frame")
tierBadge.Name = "TierBadge"
tierBadge.Size = UDim2.fromOffset(STRIP_W, ROW_H)
tierBadge.BackgroundColor3 = P.Wood
tierBadge.BorderSizePixel = 0
tierBadge.Parent = rowTpl
corner(tierBadge, 10)

local tierLbl = Instance.new("TextLabel")
tierLbl.Name = "TierLabel"
tierLbl.BackgroundTransparency = 1
tierLbl.Size = UDim2.fromScale(1, 1)
tierLbl.Font = Enum.Font.GothamBold
tierLbl.Text = "1"
tierLbl.TextColor3 = Color3.new(1, 1, 1)
tierLbl.TextSize = 22
tierLbl.Parent = tierBadge

local nameLbl = Instance.new("TextLabel")
nameLbl.Name = "NameLabel"
nameLbl.BackgroundTransparency = 1
nameLbl.Position = UDim2.new(0, STRIP_W + 10, 0, 8)
nameLbl.Size = UDim2.new(1, -(STRIP_W + BTN_W + 30), 0, 18)
nameLbl.Font = Enum.Font.GothamBold
nameLbl.Text = "Rod"
nameLbl.TextSize = 14
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.Parent = rowTpl

local effectLbl = Instance.new("TextLabel")
effectLbl.Name = "EffectSummaryLabel"
effectLbl.BackgroundTransparency = 1
effectLbl.Position = UDim2.new(0, STRIP_W + 10, 0, 28)
effectLbl.Size = UDim2.new(1, -(STRIP_W + BTN_W + 30), 0, 48)
effectLbl.Font = Enum.Font.Gotham
effectLbl.Text = "Stats"
effectLbl.TextSize = 12
effectLbl.TextWrapped = true
effectLbl.TextYAlignment = Enum.TextYAlignment.Top
effectLbl.TextXAlignment = Enum.TextXAlignment.Left
effectLbl.Parent = rowTpl

local equipBtn = Instance.new("TextButton")
equipBtn.Name = "EquipButton"
equipBtn.AutoButtonColor = false
equipBtn.BackgroundColor3 = P.Sunset
equipBtn.Font = Enum.Font.GothamBold
equipBtn.Text = "Equip"
equipBtn.TextColor3 = P.Cream
equipBtn.TextSize = 14
equipBtn.AnchorPoint = Vector2.new(1, 0.5)
equipBtn.Position = UDim2.new(1, -10, 0.5, 0)
equipBtn.Size = UDim2.fromOffset(BTN_W, 42)
equipBtn.Parent = rowTpl
corner(equipBtn, 10)

local lockOverlay = Instance.new("Frame")
lockOverlay.Name = "LockOverlay"
lockOverlay.BackgroundColor3 = P.TealDeeper
lockOverlay.BackgroundTransparency = 0.35
lockOverlay.BorderSizePixel = 0
lockOverlay.Size = UDim2.fromScale(1, 1)
lockOverlay.Visible = false
lockOverlay.ZIndex = 8
lockOverlay.Parent = rowTpl
corner(lockOverlay, 10)

gui.Parent = assets
print("[RodSelectUI] RodSelectUI_Template built.")
