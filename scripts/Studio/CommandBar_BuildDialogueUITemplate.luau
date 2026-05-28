-- Command bar: build DialogueUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar. Re-running replaces the template.

local StarterGui = game:GetService("StarterGui")

local P = {
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	Sunset = Color3.fromRGB(232, 138, 86),
	Wood = Color3.fromRGB(120, 90, 60),
	Cream = Color3.fromRGB(244, 230, 200),
	CreamSoft = Color3.fromRGB(208, 198, 178),
	Teal = Color3.fromRGB(38, 102, 110),
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
	error("[DialogueUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("DialogueUI_Template")
if existing then
	existing:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "DialogueUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "Dialogue")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "RespectTopbar", true)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1.1, 0)
panel.Size = UDim2.new(0.96, 0, 0.22, 0)
panel.BackgroundColor3 = P.TealDark
panel.BorderSizePixel = 0
panel.ZIndex = 5
panel.Parent = gui
corner(panel, 12)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = P.TealDeeper
panelStroke.Thickness = 1.5
panelStroke.Transparency = 0.25
panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
panelStroke.Parent = panel

local speaker = Instance.new("TextLabel")
speaker.Name = "SpeakerNameLabel"
speaker.BackgroundTransparency = 1
speaker.Font = Enum.Font.GothamBold
speaker.Text = "Captain Mira"
speaker.TextColor3 = P.Sunset
speaker.TextSize = 18
speaker.TextXAlignment = Enum.TextXAlignment.Left
speaker.Position = UDim2.new(0, 16, 0, 8)
speaker.Size = UDim2.new(1, -32, 0, 22)
speaker.ZIndex = 6
speaker.Parent = panel

local portrait = Instance.new("Frame")
portrait.Name = "PortraitFrame"
portrait.BackgroundColor3 = P.Wood
portrait.BorderSizePixel = 0
portrait.Position = UDim2.new(0, 16, 0, 38)
portrait.Size = UDim2.fromOffset(80, 80)
portrait.ZIndex = 6
portrait.Parent = panel
corner(portrait, 10)

local initial = Instance.new("TextLabel")
initial.Name = "PortraitInitialLabel"
initial.BackgroundTransparency = 1
initial.Font = Enum.Font.GothamBold
initial.Text = "M"
initial.TextColor3 = P.Cream
initial.TextScaled = true
initial.Size = UDim2.fromScale(1, 1)
initial.ZIndex = 7
initial.Parent = portrait
local initialConstraint = Instance.new("UITextSizeConstraint")
initialConstraint.MaxTextSize = 36
initialConstraint.MinTextSize = 14
initialConstraint.Parent = initial

local body = Instance.new("TextLabel")
body.Name = "BodyTextLabel"
body.BackgroundTransparency = 1
body.Font = Enum.Font.Gotham
body.Text = ""
body.TextColor3 = P.Cream
body.TextSize = 16
body.TextWrapped = true
body.TextYAlignment = Enum.TextYAlignment.Top
body.Position = UDim2.new(0, 110, 0, 38)
body.Size = UDim2.new(1, -220, 1, -56)
body.ZIndex = 6
body.Parent = panel

local continue = Instance.new("TextButton")
continue.Name = "ContinueHint"
continue.AutoButtonColor = false
continue.BackgroundColor3 = P.Sunset
continue.Font = Enum.Font.GothamBold
continue.Text = "Continue ▸"
continue.TextColor3 = P.Cream
continue.TextSize = 16
continue.AnchorPoint = Vector2.new(1, 1)
continue.Position = UDim2.new(1, -16, 1, -10)
continue.Size = UDim2.fromOffset(140, 44)
continue.ZIndex = 7
continue.Parent = panel
corner(continue, 10)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseButton"
closeBtn.AutoButtonColor = false
closeBtn.BackgroundTransparency = 1
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Text = "×"
closeBtn.TextColor3 = P.CreamSoft
closeBtn.TextScaled = true
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -8, 0, 6)
closeBtn.Size = UDim2.fromOffset(44, 28)
closeBtn.ZIndex = 8
closeBtn.Parent = panel
local closeConstraint = Instance.new("UITextSizeConstraint")
closeConstraint.MaxTextSize = 22
closeConstraint.MinTextSize = 14
closeConstraint.Parent = closeBtn

local choicesList = Instance.new("Frame")
choicesList.Name = "ChoicesList"
choicesList.BackgroundTransparency = 1
choicesList.AnchorPoint = Vector2.new(1, 1)
choicesList.Position = UDim2.new(1, -170, 1, -10)
choicesList.AutomaticSize = Enum.AutomaticSize.X
choicesList.Size = UDim2.fromOffset(0, 44)
choicesList.Visible = false
choicesList.ZIndex = 7
choicesList.Parent = panel
local choiceLayout = Instance.new("UIListLayout")
choiceLayout.FillDirection = Enum.FillDirection.Horizontal
choiceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
choiceLayout.Padding = UDim.new(0, 8)
choiceLayout.SortOrder = Enum.SortOrder.LayoutOrder
choiceLayout.Parent = choicesList

local choiceTpl = Instance.new("TextButton")
choiceTpl.Name = "ChoiceButton_Template"
choiceTpl.AutoButtonColor = false
choiceTpl.BackgroundColor3 = P.Teal
choiceTpl.Font = Enum.Font.GothamBold
choiceTpl.Text = "Choice"
choiceTpl.TextColor3 = P.Cream
choiceTpl.TextSize = 14
choiceTpl.Visible = false
choiceTpl.Size = UDim2.fromOffset(120, 44)
choiceTpl.ZIndex = 7
choiceTpl.Parent = gui
corner(choiceTpl, 10)

gui.Parent = assets
print("[DialogueUI] DialogueUI_Template built under StarterGuiAssets. Save to File → DialogueUI_Template.model.json if needed.")
