-- Command bar: build CastMeter_Template under StarterGui.StarterGuiAssets.
-- Paste into Studio command bar (Edit or Play). Re-running replaces the template.
--
-- Contract (runtime expects):
--   ScreenGui "CastMeter_Template" (Meta.DisplayOrderKey="CastMeter")
--     Track (Frame)
--       ZoneCommon / ZoneRare / ZoneLegendary (Frame)
--     Indicator (Frame)
--     ReleaseHintLabel (TextLabel)

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CM = GameConfig.Fishing.CastMeter
local M = GameConfig.UI.Modal

local P = {
	TealDeeper = Color3.fromRGB(10, 32, 40),
	WoodDark = Color3.fromRGB(78, 58, 40),
	Cream = Color3.fromRGB(244, 230, 200),
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

local function numberValue(parent: Instance, name: string, value: number)
	local v = Instance.new("NumberValue")
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
	error("[CastMeter] StarterGui.StarterGuiAssets missing — run Rojo sync first.", 0)
end

local existing = assets:FindFirstChild("CastMeter_Template")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "CastMeter_Template"
gui.Enabled = false
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local meta = Instance.new("Folder")
meta.Name = "Meta"
meta.Parent = gui
stringValue(meta, "DisplayOrderKey", "CastMeter")
boolValue(meta, "ResetOnSpawn", false)
boolValue(meta, "IgnoreGuiInset", true)
numberValue(meta, "FadeDuration", M.FadeDuration)
numberValue(meta, "SlideOffsetPx", M.SlideOffsetPx)

local barBottomPx = CM.CastButtonBottomPx + CM.CastButtonSizePx + CM.BarButtonGapPx
local restPos = UDim2.new(0.5, 0, 1, -barBottomPx)

local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 1)
track.Position = restPos
track.Size = UDim2.fromOffset(CM.BarWidthPx, CM.BarHeightPx)
track.BackgroundColor3 = P.WoodDark
track.BorderSizePixel = 0
track.Parent = gui
corner(track, 10)

local function zone(name: string, color: Color3)
	local z = Instance.new("Frame")
	z.Name = name
	z.BackgroundColor3 = color
	z.BackgroundTransparency = 0.12
	z.BorderSizePixel = 0
	z.Position = UDim2.new(0, 0, 0.35, 0)
	z.Size = UDim2.new(1, 0, 0.30, 0)
	z.Visible = (name == "ZoneCommon")
	z.Parent = track
	corner(z, 4)
	return z
end

zone("ZoneCommon", P.Common)
zone("ZoneRare", P.Rare)
zone("ZoneLegendary", P.Legendary)

local indicator = Instance.new("Frame")
indicator.Name = "Indicator"
indicator.AnchorPoint = Vector2.new(0.5, 0.5)
indicator.Position = UDim2.new(0.5, 0, 0.5, 0)
indicator.Size = UDim2.new(1.5, 0, 0, 6)
indicator.BackgroundColor3 = P.Cream
indicator.BorderSizePixel = 0
indicator.Parent = track
corner(indicator, 2)

local hint = Instance.new("TextLabel")
hint.Name = "ReleaseHintLabel"
hint.BackgroundTransparency = 1
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 0, -8)
hint.Size = UDim2.fromOffset(220, 18)
hint.Font = Enum.Font.GothamBold
hint.TextSize = 14
hint.TextColor3 = P.Cream
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.Text = "Release to cast"
hint.Parent = track

gui.Parent = assets

print("[CastMeter] Built CastMeter_Template under StarterGui.StarterGuiAssets.")
print("[CastMeter] Save to file: src/StarterGuiAssets/CastMeter_Template.rbxmx")

