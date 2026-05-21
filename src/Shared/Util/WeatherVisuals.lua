--!strict
-- WeatherVisuals.lua
-- Server-side atmosphere + Lighting presets.  Lighting and Atmosphere changes
-- replicate to all clients automatically.
-- ColorCorrectionEffect (a PostEffect) cannot be created on the server — it is
-- applied client-side in WorldFXController via WeatherVisuals.applyColorCorrection().

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local WeatherVisuals = {}

local CC_NAME = "TidesWeatherColorCorrection"

local function getPreset(weather: string): {[string]: any}?
	local visuals = GameConfig.Weather.Visuals
	return visuals and visuals[weather]
end

local function ensureAtmosphere(): Atmosphere
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then return atm end
	atm = Instance.new("Atmosphere")
	atm.Density = 0.35
	atm.Glare = 0.3
	atm.Haze = 1.2
	atm.Color = Color3.fromRGB(232, 200, 168)
	atm.Decay = Color3.fromRGB(153, 115, 89)
	atm.Parent = Lighting
	return atm
end

local function applyToAtmosphere(atm: Atmosphere, preset: {[string]: any})
	atm.Density = preset.Density
	atm.Haze = preset.Haze
	atm.Color = preset.Color
	if preset.Decay then
		atm.Decay = preset.Decay
	end
end

function WeatherVisuals.apply(weather: string): boolean
	local preset = getPreset(weather)
	if not preset then
		return false
	end

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") then
			applyToAtmosphere(child, preset)
		end
	end
	applyToAtmosphere(ensureAtmosphere(), preset)

	if preset.Brightness ~= nil then
		Lighting.Brightness = preset.Brightness
	end
	if preset.ExposureCompensation ~= nil then
		Lighting.ExposureCompensation = preset.ExposureCompensation
	end

	return true
end

-- Call this CLIENT-SIDE ONLY.  PostEffects (ColorCorrectionEffect) cannot be
-- created on the server, so this function must be called from a Controller,
-- not a Service.
function WeatherVisuals.applyColorCorrection(weather: string): boolean
	local Lighting = game:GetService("Lighting")
	local preset = getPreset(weather)
	if not preset then return false end

	local cc: ColorCorrectionEffect
	local existing = Lighting:FindFirstChild(CC_NAME)
	if existing and existing:IsA("ColorCorrectionEffect") then
		cc = existing
	else
		if existing then
			-- Stale instance with a different class — clear it so we can replace.
			existing:Destroy()
		end
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = CC_NAME
		cc.Parent = Lighting
	end

	if preset.CcEnabled == false then
		cc.Enabled = false
	else
		cc.Enabled = true
		if preset.CcTint then
			cc.TintColor = preset.CcTint
		end
		if preset.CcSaturation ~= nil then
			cc.Saturation = preset.CcSaturation
		end
		if preset.CcContrast ~= nil then
			cc.Contrast = preset.CcContrast
		end
	end

	return true
end

return WeatherVisuals
