-- Command bar: build NotificationUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar. Re-running replaces the template.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CFG = GameConfig.UI.Notification

local P = {
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	Cream = Color3.fromRGB(244, 230, 200),
}

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
	error("[NotificationUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("NotificationUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "NotificationUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "Notification")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "RespectTopbar", true)

local stack = Instance.new("Frame")
stack.Name = "StackContainer"
stack.BackgroundTransparency = 1
stack.AnchorPoint = Vector2.new(0.5, 1)
stack.Position = UDim2.new(0.5, 0, 1, -CFG.BottomOffsetPx)
stack.AutomaticSize = Enum.AutomaticSize.Y
stack.Size = UDim2.fromOffset(340, 0)
stack.ZIndex = 10
stack.Parent = gui

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Bottom
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 8)
list.Parent = stack

local toastTpl = Instance.new("Frame")
toastTpl.Name = "Toast_Template"
toastTpl.BackgroundColor3 = P.TealDark
toastTpl.BackgroundTransparency = 1
toastTpl.AutomaticSize = Enum.AutomaticSize.Y
toastTpl.Size = UDim2.new(1, 0, 0, 0)
toastTpl.Visible = false
toastTpl.ZIndex = 10
toastTpl.Parent = gui
corner(toastTpl, 12)
local stroke = Instance.new("UIStroke")
stroke.Color = P.TealDeeper
stroke.Thickness = 1.5
stroke.Transparency = 0.25
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = toastTpl

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = toastTpl

local label = Instance.new("TextLabel")
label.Name = "MessageLabel"
label.BackgroundTransparency = 1
label.Font = Enum.Font.Gotham
label.Text = ""
label.TextColor3 = P.Cream
label.TextSize = 16
label.TextTransparency = 1
label.TextWrapped = true
label.TextXAlignment = Enum.TextXAlignment.Center
label.AutomaticSize = Enum.AutomaticSize.Y
label.Size = UDim2.new(1, 0, 0, 0)
label.ZIndex = 11
label.Parent = toastTpl

gui.Parent = assets
print("[NotificationUI] NotificationUI_Template built under StarterGuiAssets. Save to File → NotificationUI_Template.model.json if needed.")
