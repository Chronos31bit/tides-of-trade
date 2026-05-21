--!strict
-- WeatherVisuals.lua
-- Server-side atmosphere + Lighting presets.  Lighting and Atmosphere changes
-- replicate to all clients automatically.
-- ColorCorrectionEffect (a PostEffect) cannot be created on the server — it is
-- applied client-side in WorldFXController via WeatherVisuals.applyColorCorrection().
--
-- All apply() / applyColorCorrection() callers may pass a durationSeconds arg.
-- 0 (or nil) → snap to target (used on server boot and Studio command-bar tests).
-- > 0 → TweenService crossfade between current and target preset.  Active
-- tweens per instance are cached + cancelled before a new one starts, so rapid
-- weather flips never stack.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local WeatherVisuals = {}

local CC_NAME = "TidesWeatherColorCorrection"

local TWEEN_INFO_CACHE: {[number]: TweenInfo} = {}
local function tweenInfoFor(duration: number): TweenInfo
	local cached = TWEEN_INFO_CACHE[duration]
	if cached then return cached end
	local info = TweenInfo.new(
		duration,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		0, false, 0
	)
	TWEEN_INFO_CACHE[duration] = info
	return info
end

-- Weak map: instance → currently-running tween. setmetatable on { __mode = "k" }
-- lets the GC drop the entry when the instance itself is destroyed.
local ACTIVE_TWEENS: {[Instance]: Tween} = setmetatable({}, { __mode = "k" }) :: any

local function applyTween(inst: Instance, duration: number, props: {[string]: any})
	local existing = ACTIVE_TWEENS[inst]
	if existing then
		existing:Cancel()
		ACTIVE_TWEENS[inst] = nil
	end
	if duration <= 0 then
		for k, v in pairs(props) do
			(inst :: any)[k] = v
		end
		return
	end
	local tween = TweenService:Create(inst, tweenInfoFor(duration), props)
	ACTIVE_TWEENS[inst] = tween
	tween.Completed:Connect(function()
		if ACTIVE_TWEENS[inst] == tween then
			ACTIVE_TWEENS[inst] = nil
		end
	end)
	tween:Play()
end

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

local function ensureClouds(): Clouds
	local clouds = Lighting:FindFirstChildOfClass("Clouds")
	if clouds then return clouds end
	clouds = Instance.new("Clouds")
	clouds.Parent = Lighting
	return clouds
end

local function cloudsProps(preset: {[string]: any}): {[string]: any}?
	if preset.CloudCover == nil and preset.CloudDensity == nil then
		return nil
	end
	local props: {[string]: any} = {}
	if preset.CloudCover ~= nil then
		props.Cover = preset.CloudCover
	end
	if preset.CloudDensity ~= nil then
		props.Density = preset.CloudDensity
	end
	if preset.CloudColor then
		props.Color = preset.CloudColor
	end
	return props
end

local function atmosphereProps(preset: {[string]: any}): {[string]: any}
	local props: {[string]: any} = {
		Density = preset.Density,
		Haze = preset.Haze,
		Color = preset.Color,
	}
	if preset.Decay then
		props.Decay = preset.Decay
	end
	return props
end

function WeatherVisuals.apply(weather: string, durationSeconds: number?): boolean
	local preset = getPreset(weather)
	if not preset then
		return false
	end

	local duration = durationSeconds or 0

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Atmosphere") then
			applyTween(child, duration, atmosphereProps(preset))
		end
	end
	-- Guarantee at least one Atmosphere exists, even on fresh place opens.
	local primary = ensureAtmosphere()
	if not ACTIVE_TWEENS[primary] then
		applyTween(primary, duration, atmosphereProps(preset))
	end

	local lightingProps: {[string]: any} = {}
	if preset.Brightness ~= nil then
		lightingProps.Brightness = preset.Brightness
	end
	if preset.ExposureCompensation ~= nil then
		lightingProps.ExposureCompensation = preset.ExposureCompensation
	end
	if next(lightingProps) ~= nil then
		applyTween(Lighting, duration, lightingProps)
	end

	local cloudPreset = cloudsProps(preset)
	if cloudPreset then
		local clouds = ensureClouds()
		applyTween(clouds, duration, cloudPreset)
	end

	return true
end

-- Call this CLIENT-SIDE ONLY.  PostEffects (ColorCorrectionEffect) cannot be
-- created on the server, so this function must be called from a Controller,
-- not a Service.
function WeatherVisuals.applyColorCorrection(weather: string, durationSeconds: number?): boolean
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

	local duration = durationSeconds or 0

	if preset.CcEnabled == false then
		-- Tween Saturation to 0 over duration so it doesn't pop, then disable.
		applyTween(cc, duration, { Saturation = 0, Contrast = 0 })
		if duration <= 0 then
			cc.Enabled = false
		else
			task.delay(duration, function()
				if cc and cc.Parent then
					cc.Enabled = false
				end
			end)
		end
		return true
	end

	cc.Enabled = true
	local props: {[string]: any} = {}
	if preset.CcTint then
		props.TintColor = preset.CcTint
	end
	if preset.CcSaturation ~= nil then
		props.Saturation = preset.CcSaturation
	end
	if preset.CcContrast ~= nil then
		props.Contrast = preset.CcContrast
	end
	if next(props) ~= nil then
		applyTween(cc, duration, props)
	end

	return true
end

-- Client-only distance fog (Lighting.FogStart / FogEnd / FogColor). Complements Atmosphere haze.
function WeatherVisuals.applyDistanceFog(weather: string, durationSeconds: number?): boolean
	local preset = getPreset(weather)
	if not preset then
		return false
	end

	local distanceCfg = GameConfig.Weather.DistanceFog
	local clearEnd = if distanceCfg then distanceCfg.ClearFogEnd else 100000
	local duration = durationSeconds or 0

	local props: {[string]: any}
	if preset.FogEnd ~= nil then
		props = {
			FogStart = preset.FogStart or 0,
			FogEnd = preset.FogEnd,
		}
		if preset.FogColor then
			props.FogColor = preset.FogColor
		end
	else
		props = { FogEnd = clearEnd }
	end

	applyTween(Lighting, duration, props)
	return true
end

return WeatherVisuals
