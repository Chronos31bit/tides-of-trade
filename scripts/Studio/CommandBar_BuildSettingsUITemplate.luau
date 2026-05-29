-- Command bar: build SettingsUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar. Re-running replaces the template.
-- Save to File → src/StarterGuiAssets/SettingsUI_Template.model.json for Rojo.

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local UI = GameConfig.UI
local H = UI.SettingsHub
local M = UI.Modal
local R = UI.Radii
local S = UI.Spacing
local TY = UI.Typography

local P = {
	Parchment     = Color3.fromRGB(245, 236, 218),
	ParchmentDeep = Color3.fromRGB(232, 220, 198),
	Ink           = Color3.fromRGB( 48,  38,  28),
	InkSoft       = Color3.fromRGB( 96,  80,  64),
	BorderLight   = Color3.fromRGB(210, 194, 168),
	BorderMid     = Color3.fromRGB(172, 152, 122),
	Mint          = Color3.fromRGB(140, 196, 182),
	MintDark      = Color3.fromRGB( 88, 152, 138),
	Cream         = Color3.fromRGB(252, 244, 228),
	Shadow        = Color3.new(0, 0, 0),
}

local function sv(parent: Instance, name: string, value: string | boolean | number)
	local cls = if type(value) == "boolean" then "BoolValue"
		elseif type(value) == "number" then "NumberValue"
		else "StringValue"
	local v = Instance.new(cls)
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

local function stroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Color = P.BorderMid
	s.Thickness = 1.2
	s.Transparency = 0.25
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function sectionCard(parent: Instance, name: string, title: string, layoutOrder: number): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.BackgroundColor3 = P.ParchmentDeep
	card.BorderSizePixel = 0
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.LayoutOrder = layoutOrder
	card.Parent = parent
	corner(card, R.md)
	stroke(card)

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, S.md)
	pad.PaddingBottom = UDim.new(0, S.md)
	pad.PaddingLeft = UDim.new(0, S.md)
	pad.PaddingRight = UDim.new(0, S.md)
	pad.Parent = card

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.sm)
	list.Parent = card

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Name = "SectionTitle"
	titleLbl.BackgroundTransparency = 1
	titleLbl.Font = TY.subtitle.font
	titleLbl.TextSize = TY.subtitle.size
	titleLbl.TextColor3 = P.Ink
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Text = title
	titleLbl.AutomaticSize = Enum.AutomaticSize.Y
	titleLbl.Size = UDim2.new(1, 0, 0, 0)
	titleLbl.LayoutOrder = 0
	titleLbl.Parent = card

	local body = Instance.new("Frame")
	body.Name = name:gsub("Section$", "") .. "Body"
	if name == "AudioSection" then
		body.Name = "AudioBody"
	elseif name == "MotionSection" then
		body.Name = "MotionBody"
	elseif name == "CreditsSection" then
		body.Name = "CreditsBody"
	end
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.new(1, 0, 0, 0)
	body.LayoutOrder = 1
	body.Parent = card

	local bodyList = Instance.new("UIListLayout")
	bodyList.FillDirection = Enum.FillDirection.Vertical
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Padding = UDim.new(0, S.sm)
	bodyList.Parent = body

	return body
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[SettingsUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("SettingsUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
sv(meta, "DisplayOrderKey", "Modal")
sv(meta, "ResetOnSpawn", false)
sv(meta, "IgnoreGuiInset", true)
sv(meta, "FadeDuration", H.FadeDuration)
sv(meta, "SlideOffsetPx", H.SlideOffsetPx)
sv(meta, "ThemeKey", "modal-parchment")

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.BackgroundColor3 = P.Shadow
backdrop.BackgroundTransparency = 1
backdrop.BorderSizePixel = 0
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = 1
backdrop.Selectable = true
backdrop.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.BackgroundColor3 = P.Parchment
panel.BorderSizePixel = 0
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -H.MarginPx, 1, -H.MarginPx)
panel.Size = UDim2.fromOffset(H.PanelWidthPx, H.PanelHeightPx)
panel.ZIndex = 2
panel.Parent = gui
corner(panel, R.lg)
stroke(panel)

local sizeCap = Instance.new("UISizeConstraint")
sizeCap.MaxSize = Vector2.new(M.MaxWidthPx, H.PanelHeightPx)
sizeCap.Parent = panel

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = P.ParchmentDeep
header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, M.HeaderHeightPx)
header.ZIndex = 3
header.Parent = panel
corner(header, R.lg)

local headerMask = Instance.new("Frame")
headerMask.Name = "HeaderMask"
headerMask.BackgroundColor3 = P.ParchmentDeep
headerMask.BorderSizePixel = 0
headerMask.AnchorPoint = Vector2.new(0, 1)
headerMask.Position = UDim2.new(0, 0, 1, 0)
headerMask.Size = UDim2.new(1, 0, 0, R.lg)
headerMask.ZIndex = 3
headerMask.Parent = header

local headerDiv = Instance.new("Frame")
headerDiv.Name = "HeaderDivider"
headerDiv.BackgroundColor3 = P.BorderLight
headerDiv.BorderSizePixel = 0
headerDiv.AnchorPoint = Vector2.new(0, 1)
headerDiv.Position = UDim2.new(0, 0, 1, 0)
headerDiv.Size = UDim2.new(1, 0, 0, 1)
headerDiv.ZIndex = 4
headerDiv.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Name = "Title"
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "Settings"
titleLbl.Font = TY.title.font
titleLbl.TextSize = TY.title.size
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
closeBtn.TextScaled = false
closeBtn.TextSize = 20
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -S.md, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(M.CloseButtonPx, M.CloseButtonPx)
closeBtn.ZIndex = 4
closeBtn.Selectable = true
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

local sections = Instance.new("ScrollingFrame")
sections.Name = "Sections"
sections.BackgroundTransparency = 1
sections.BorderSizePixel = 0
sections.Size = UDim2.fromScale(1, 1)
sections.CanvasSize = UDim2.new()
sections.AutomaticCanvasSize = Enum.AutomaticSize.Y
sections.ScrollBarThickness = 6
sections.ScrollBarImageColor3 = P.BorderMid
sections.ScrollingDirection = Enum.ScrollingDirection.Y
sections.Parent = body

local sectionsList = Instance.new("UIListLayout")
sectionsList.FillDirection = Enum.FillDirection.Vertical
sectionsList.SortOrder = Enum.SortOrder.LayoutOrder
sectionsList.Padding = UDim.new(0, S.md)
sectionsList.Parent = sections

local sectionsPad = Instance.new("UIPadding")
sectionsPad.PaddingRight = UDim.new(0, S.sm)
sectionsPad.Parent = sections

-- Audio
local audioBody = sectionCard(sections, "AudioSection", "Audio", 1)

local volLbl = Instance.new("TextLabel")
volLbl.Name = "VolumeLabel"
volLbl.BackgroundTransparency = 1
volLbl.Font = TY.body.font
volLbl.TextSize = TY.body.size
volLbl.TextColor3 = P.Ink
volLbl.TextXAlignment = Enum.TextXAlignment.Left
volLbl.Text = "Master volume"
volLbl.AutomaticSize = Enum.AutomaticSize.Y
volLbl.Size = UDim2.new(1, 0, 0, 0)
volLbl.LayoutOrder = 0
volLbl.Parent = audioBody

local sliderMount = Instance.new("Frame")
sliderMount.Name = "VolumeSliderMount"
sliderMount.BackgroundTransparency = 1
sliderMount.BorderSizePixel = 0
sliderMount.Size = UDim2.new(1, 0, 0, UI.MinTouchPx)
sliderMount.LayoutOrder = 1
sliderMount.Parent = audioBody

local muteMount = Instance.new("Frame")
muteMount.Name = "MuteToggleMount"
muteMount.BackgroundTransparency = 1
muteMount.BorderSizePixel = 0
muteMount.Size = UDim2.new(1, 0, 0, UI.MinTouchPx)
muteMount.LayoutOrder = 2
muteMount.Parent = audioBody

-- Motion
local motionBody = sectionCard(sections, "MotionSection", "Motion", 2)

local motionHint = Instance.new("TextLabel")
motionHint.Name = "MotionHint"
motionHint.BackgroundTransparency = 1
motionHint.Font = TY.caption.font
motionHint.TextSize = TY.caption.size
motionHint.TextColor3 = P.InkSoft
motionHint.TextWrapped = true
motionHint.TextXAlignment = Enum.TextXAlignment.Left
motionHint.Text = "Reduce on-screen animation. Auto follows your device's accessibility setting."
motionHint.AutomaticSize = Enum.AutomaticSize.Y
motionHint.Size = UDim2.new(1, 0, 0, 0)
motionHint.LayoutOrder = 0
motionHint.Parent = motionBody

local modeRow = Instance.new("Frame")
modeRow.Name = "ModeRow"
modeRow.BackgroundTransparency = 1
modeRow.BorderSizePixel = 0
modeRow.Size = UDim2.new(1, 0, 0, UI.MinTouchPx)
modeRow.LayoutOrder = 1
modeRow.Parent = motionBody

local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.SortOrder = Enum.SortOrder.LayoutOrder
modeLayout.Padding = UDim.new(0, S.sm)
modeLayout.Parent = modeRow

local modeOptions = {
	{ mode = "auto", label = "Auto" },
	{ mode = "off", label = "Always Off" },
	{ mode = "reduced", label = "Always Reduced" },
}
for i, opt in ipairs(modeOptions) do
	local mode, label = opt.mode, opt.label
	local btn = Instance.new("TextButton")
	btn.Name = "Mode_" .. mode
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.BackgroundColor3 = P.Parchment
	btn.Font = TY.caption.font
	btn.TextSize = math.max(TY.caption.size, UI.MinFontPx)
	btn.Text = label
	btn.TextWrapped = true
	btn.TextColor3 = P.InkSoft
	btn.Size = UDim2.new(1 / 3, -S.sm, 1, 0)
	btn.LayoutOrder = i
	btn.Selectable = true
	btn.Parent = modeRow
	corner(btn, R.md)
	stroke(btn)
end

-- Credits (entries filled at runtime from CreditsConfig)
sectionCard(sections, "CreditsSection", "Credits", 3)

gui.Parent = assets
print("[SettingsUI] Built SettingsUI_Template — bottom-right panel. Save to File → SettingsUI_Template.model.json")
