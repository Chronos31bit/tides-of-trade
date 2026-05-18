--!strict
-- BiomeDebugController.lua
-- Studio-only. Renders a small bottom-left overlay showing the player's
-- current biome (read from Character.CurrentBiome), live tide state, and
-- live weather — useful when standing in a biome zone and testing fish rolls.
--
-- Hidden in production: the RunService:IsStudio() guard in KnitStart returns
-- immediately when running on a real server or in a published build.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local UIUtil     = require(script.Parent.Parent.UI.UIUtil)

local BiomeDebugController = Knit.CreateController({
	Name = "BiomeDebugController",
	_trove      = nil :: any,
	_charTrove  = nil :: any,
	_biomeLabel = nil :: TextLabel?,
	_tideLabel  = nil :: TextLabel?,
	_weatherLabel = nil :: TextLabel?,
})

-- ====================================================================
-- OVERLAY CONSTRUCTION
-- ====================================================================

function BiomeDebugController:_buildOverlay(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name                  = "BiomeDebugOverlay"
	gui.ResetOnSpawn          = false
	gui.IgnoreGuiInset        = false
	gui.ZIndexBehavior        = Enum.ZIndexBehavior.Sibling
	gui.Parent                = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name                = "Panel"
	panel.AnchorPoint         = Vector2.new(0, 1)
	panel.Position            = UDim2.new(0, 8, 1, -8)
	panel.Size                = UDim2.fromOffset(230, 82)
	panel.BackgroundColor3    = UIUtil.Palette.TealDeeper
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel     = 0
	panel.Parent              = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0, 10)
	padding.PaddingRight  = UDim.new(0, 10)
	padding.PaddingTop    = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent        = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding       = UDim.new(0, 4)
	layout.SortOrder     = Enum.SortOrder.LayoutOrder
	layout.Parent        = panel

	local function makeLabel(text: string, bold: boolean, order: number): TextLabel
		local lbl = Instance.new("TextLabel")
		lbl.Size                 = UDim2.new(1, 0, 0, 20)
		lbl.BackgroundTransparency = 1
		lbl.Font                 = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		lbl.TextSize             = if bold then 15 else 13
		lbl.TextColor3           = UIUtil.Palette.Cream
		lbl.TextXAlignment       = Enum.TextXAlignment.Left
		lbl.Text                 = text
		lbl.LayoutOrder          = order
		lbl.Parent               = panel
		return lbl
	end

	self._biomeLabel   = makeLabel("Biome: Shoreline", true,  1)
	self._tideLabel    = makeLabel("Tide: …",          false, 2)
	self._weatherLabel = makeLabel("Weather: …",       false, 3)

	return gui
end

-- ====================================================================
-- LABEL UPDATES
-- ====================================================================

function BiomeDebugController:_updateBiome(biome: string)
	if not self._biomeLabel then return end
	if biome == "Pier" then
		self._biomeLabel.Text = "Biome: Pier  (→ Shoreline)"
	else
		self._biomeLabel.Text = "Biome: " .. biome
	end
end

function BiomeDebugController:_updateTide(state: string)
	if not self._tideLabel then return end
	self._tideLabel.Text = "Tide: " .. state
end

function BiomeDebugController:_updateWeather(weather: string)
	if not self._weatherLabel then return end
	self._weatherLabel.Text = "Weather: " .. weather
end

-- ====================================================================
-- CHARACTER WATCHING
-- ====================================================================

function BiomeDebugController:_watchCharacter(char: Model)
	-- Destroy previous character's connections.
	if self._charTrove then
		self._charTrove:Destroy()
	end
	self._charTrove = Trove.new()

	-- WorldService stamps CurrentBiome via task.defer so it may not exist
	-- at the exact moment CharacterAdded fires. WaitForChild handles the race.
	local sv = char:WaitForChild("CurrentBiome", 10) :: StringValue?
	if not sv then return end

	self:_updateBiome(sv.Value)

	local conn = sv.Changed:Connect(function(newBiome: string)
		self:_updateBiome(newBiome)
	end)
	self._charTrove:Add(conn)
end

-- ====================================================================
-- KNIT LIFECYCLE
-- ====================================================================

function BiomeDebugController:KnitInit() end

function BiomeDebugController:KnitStart()
	if not RunService:IsStudio() then return end

	self._trove = Trove.new()
	self:_buildOverlay()

	local TideService    = Knit.GetService("TideService")
	local WeatherService = Knit.GetService("WeatherService")

	self._trove:Add(TideService.TideChanged:Connect(function(state: string)
		self:_updateTide(state)
	end))

	self._trove:Add(WeatherService.WeatherChanged:Connect(function(weather: string)
		self:_updateWeather(weather)
	end))

	local lp = Players.LocalPlayer

	self._trove:Add(lp.CharacterAdded:Connect(function(char: Model)
		self:_watchCharacter(char)
	end))

	if lp.Character then
		self:_watchCharacter(lp.Character)
	end
end

return BiomeDebugController
