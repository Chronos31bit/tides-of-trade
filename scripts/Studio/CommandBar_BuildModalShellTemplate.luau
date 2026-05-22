-- Command bar: build ModalShell_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.
--
-- After build: right-click ModalShell_Template → Save to File…
--   → src/StarterGuiAssets/ModalShell_Template.rbxmx
-- Commit the .rbxmx so Rojo syncs for the whole team.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local UI = GameConfig.UI
local M = UI.Modal
local R = UI.Radii
local S = UI.Spacing

-- Cozy palette (matches UIKit.Palette)
local P = {
	Parchment     = Color3.fromRGB(245, 236, 218),
	ParchmentDeep = Color3.fromRGB(232, 220, 198),
	Ink           = Color3.fromRGB( 48,  38,  28),
	InkSoft       = Color3.fromRGB( 96,  80,  64),
	BorderLight   = Color3.fromRGB(210, 194, 168),
	BorderMid     = Color3.fromRGB(172, 152, 122),
	Shadow        = Color3.new(0, 0, 0),
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

local function numberValue(parent: Instance, name: string, value: number)
	local v = Instance.new("NumberValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[ModalShell] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("ModalShell_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "ModalShell_Template"
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
panel.BackgroundColor3 = P.Parchment
panel.BorderSizePixel = 0
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.92, 0, 0.78, 0)
panel.ZIndex = 2
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, R.lg)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = P.BorderMid
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.25
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent = panel

local sizeCap = Instance.new("UISizeConstraint")
sizeCap.MaxSize = Vector2.new(M.MaxWidthPx, math.huge)
sizeCap.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = P.ParchmentDeep
header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, M.HeaderHeightPx)
header.ZIndex = 3
header.Parent = panel

local hCorner = Instance.new("UICorner")
hCorner.CornerRadius = UDim.new(0, R.lg)
hCorner.Parent = header

local hMask = Instance.new("Frame")
hMask.Name = "HeaderMask"
hMask.BackgroundColor3 = P.ParchmentDeep
hMask.BorderSizePixel = 0
hMask.AnchorPoint = Vector2.new(0, 1)
hMask.Position = UDim2.new(0, 0, 1, 0)
hMask.Size = UDim2.new(1, 0, 0, R.lg)
hMask.ZIndex = 3
hMask.Parent = header

local hDiv = Instance.new("Frame")
hDiv.Name = "HeaderDivider"
hDiv.BackgroundColor3 = P.BorderLight
hDiv.BorderSizePixel = 0
hDiv.AnchorPoint = Vector2.new(0, 1)
hDiv.Position = UDim2.new(0, 0, 1, 0)
hDiv.Size = UDim2.new(1, 0, 0, 1)
hDiv.ZIndex = 4
hDiv.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "Title"
titleLbl.BackgroundTransparency = 1
titleLbl.Text = ""
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 20
titleLbl.TextColor3 = P.Ink
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.TextYAlignment = Enum.TextYAlignment.Center
titleLbl.Position = UDim2.fromOffset(S.lg, 0)
titleLbl.Size = UDim2.new(1, -(S.lg * 2 + M.CloseButtonPx), 1, 0)
titleLbl.ZIndex = 4
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AutoButtonColor = false
closeBtn.BorderSizePixel = 0
closeBtn.BackgroundColor3 = P.ParchmentDeep
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = P.InkSoft
closeBtn.TextScaled = true
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -S.md, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(M.CloseButtonPx, M.CloseButtonPx)
closeBtn.ZIndex = 4
closeBtn.Parent = header

local textCap = Instance.new("UITextSizeConstraint")
textCap.MaxTextSize = 20
textCap.MinTextSize = 14
textCap.Parent = closeBtn

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, R.sm)
closeCorner.Parent = closeBtn

local body = Instance.new("Frame")
body.Name = "Body"
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.Position = UDim2.new(0, 0, 0, M.HeaderHeightPx)
body.Size = UDim2.new(1, 0, 1, -M.HeaderHeightPx)
body.ZIndex = 2
body.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingLeft   = UDim.new(0, M.BodyPaddingPx)
pad.PaddingRight  = UDim.new(0, M.BodyPaddingPx)
pad.PaddingTop    = UDim.new(0, M.BodyPaddingPx)
pad.PaddingBottom = UDim.new(0, M.BodyPaddingPx)
pad.Parent = body

gui.Parent = assets

print("[ModalShell] Built ModalShell_Template under StarterGui.StarterGuiAssets.")
print("[ModalShell] Save to file: src/StarterGuiAssets/ModalShell_Template.rbxmx")
