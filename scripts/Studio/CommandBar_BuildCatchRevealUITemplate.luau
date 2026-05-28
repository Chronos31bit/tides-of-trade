-- Command bar: build CatchRevealUI_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.
--
-- Contract (runtime expects):
--   ScreenGui "CatchRevealUI_Template" (Meta.DisplayOrderKey="CatchReveal")
--     FishViewport, NameLabel, RarityChip, ModifierPillStrip, CoinPreviewLabel, DismissButton
--     SparkleCommon / SparkleRare / SparkleLegendary (skip under ReducedMotion)

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CR = GameConfig.UI.CatchReveal

local P = {
	TealDark = Color3.fromRGB(18, 52, 60),
	TealDeeper = Color3.fromRGB(10, 32, 40),
	Cream = Color3.fromRGB(244, 230, 200),
	CreamSoft = Color3.fromRGB(208, 198, 178),
	Gold = Color3.fromRGB(220, 180, 88),
	Shadow = Color3.new(0, 0, 0),
	ThumbLight = Color3.fromRGB(225, 232, 245),
	Common = Color3.fromRGB(176, 182, 190),
	Rare = Color3.fromRGB(95, 165, 240),
	Legendary = Color3.fromRGB(245, 180, 75),
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

local function corner(parent: Instance, radiusPx: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radiusPx)
	c.Parent = parent
	return c
end

local assets = StarterGui:FindFirstChild("StarterGuiAssets")
if not assets then
	error("[CatchRevealUI] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("CatchRevealUI_Template")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "CatchRevealUI_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "CatchReveal")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "RespectTopbar", true)

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, CR.RestTopOffsetPx)
card.Size = UDim2.fromOffset(360, 132)
card.BackgroundColor3 = P.TealDark
card.BorderSizePixel = 0
card.Parent = gui
corner(card, 14)

local stroke = Instance.new("UIStroke")
stroke.Name = "CardStroke"
stroke.Color = P.Common
stroke.Thickness = 3
stroke.Transparency = 0
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = card

local tap = Instance.new("TextButton")
tap.Name = "DismissButton"
tap.BackgroundTransparency = 1
tap.Text = ""
tap.AutoButtonColor = false
tap.Size = UDim2.fromScale(1, 1)
tap.ZIndex = 5
tap.Parent = card

local vpf = Instance.new("ViewportFrame")
vpf.Name = "FishViewport"
vpf.Position = UDim2.new(0, 16, 0, 16)
vpf.Size = UDim2.fromOffset(80, 80)
vpf.BackgroundColor3 = P.TealDeeper
vpf.BorderSizePixel = 0
vpf.LightColor = P.ThumbLight
vpf.LightDirection = Vector3.new(-1, -2, -1)
vpf.Parent = card
corner(vpf, 10)

local name = Instance.new("TextLabel")
name.Name = "NameLabel"
name.BackgroundTransparency = 1
name.Position = UDim2.new(0, 108, 0, 12)
name.Size = UDim2.new(1, -120, 0, 28)
name.Font = Enum.Font.GothamBold
name.TextSize = 24
name.TextColor3 = P.Cream
name.TextXAlignment = Enum.TextXAlignment.Left
name.TextTruncate = Enum.TextTruncate.AtEnd
name.Text = "Fish"
name.Parent = card

local modStrip = Instance.new("Frame")
modStrip.Name = "ModifierPillStrip"
modStrip.BackgroundTransparency = 1
modStrip.Position = UDim2.new(0, 108, 0, 64)
modStrip.Size = UDim2.new(1, -120, 0, 24)
modStrip.Parent = card
local stripLayout = Instance.new("UIListLayout")
stripLayout.FillDirection = Enum.FillDirection.Horizontal
stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
stripLayout.Padding = UDim.new(0, 4)
stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
stripLayout.Parent = modStrip

local coin = Instance.new("TextLabel")
coin.Name = "CoinPreviewLabel"
coin.BackgroundTransparency = 1
coin.AnchorPoint = Vector2.new(0, 1)
coin.Position = UDim2.new(0, 108, 1, -14)
coin.Size = UDim2.new(0, 180, 0, 22)
coin.Font = Enum.Font.GothamBold
coin.TextSize = 16
coin.TextColor3 = P.Gold
coin.TextXAlignment = Enum.TextXAlignment.Left
coin.Text = "~0 coins"
coin.Parent = card

local rarityChip = Instance.new("Frame")
rarityChip.Name = "RarityChip"
rarityChip.AnchorPoint = Vector2.new(1, 1)
rarityChip.Position = UDim2.new(1, -14, 1, -14)
rarityChip.Size = UDim2.fromOffset(96, 24)
rarityChip.BackgroundColor3 = P.Common
rarityChip.BorderSizePixel = 0
rarityChip.Parent = card
corner(rarityChip, 8)

local rarityText = Instance.new("TextLabel")
rarityText.Name = "Label"
rarityText.BackgroundTransparency = 1
rarityText.Size = UDim2.fromScale(1, 1)
rarityText.Font = Enum.Font.GothamBold
rarityText.TextSize = 12
rarityText.TextColor3 = Color3.new(1, 1, 1)
rarityText.Text = "COMMON"
rarityText.Parent = rarityChip

local function sparkle(name: string, color: Color3)
	local s = Instance.new("Frame")
	s.Name = name
	s.BackgroundTransparency = 1
	s.Size = UDim2.fromScale(1, 1)
	s.Visible = false
	s.ZIndex = 6
	s.Parent = card
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(1, color),
	})
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.85),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Rotation = 25
	g.Parent = s
	return s
end

sparkle("SparkleCommon", P.Common)
sparkle("SparkleRare", P.Rare)
sparkle("SparkleLegendary", P.Legendary)

gui.Parent = assets

print("[CatchRevealUI] Built CatchRevealUI_Template under StarterGui.StarterGuiAssets.")
print("[CatchRevealUI] Save to file: src/StarterGuiAssets/CatchRevealUI_Template.rbxmx")

