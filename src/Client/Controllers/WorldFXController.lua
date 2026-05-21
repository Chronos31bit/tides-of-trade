--!strict
-- WorldFXController.lua
-- Client rain particles + ambient ducking. Atmosphere is server Lighting only.

local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil     = require(ReplicatedStorage.Shared.Util.MotionUtil)
local WeatherVisuals = require(ReplicatedStorage.Shared.Util.WeatherVisuals)

local RAIN_CFG = GameConfig.Weather.Rain
local ATTR_WEATHER = GameConfig.Weather.WorkspaceAttribute

local WorldFXController = Knit.CreateController({
	Name = "WorldFXController",
	_currentWeather = "Clear",
	_targetTideLevel = -1,
	_rainTemplate = nil :: ParticleEmitter?,
	_rainTrove = nil :: any,
	_rainEmitter = nil :: ParticleEmitter?,
	_baseSpread = Vector2.new(12, 12),
	_sound = nil :: any,
	_baseVol = 0.5,
	_useProceduralRain = false,
	_loggedRainSource = false,
})

local function isRainyWeather(weather: string): boolean
	return weather == "Rain" or weather == "Storm"
end

function WorldFXController:_logRainSourceOnce()
	if self._loggedRainSource then return end
	self._loggedRainSource = true
	if self._useProceduralRain then
		print("[WorldFX] Rain: using procedural emitter (no place template)")
	else
		print("[WorldFX] Rain: using Assets.Weather.Rain.RainEmitter template")
	end
end

function WorldFXController:_createProceduralRainEmitter(): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "WorldFX_Rain"
	pe.Texture = RAIN_CFG.PlaceholderTextureId
	pe.Rate = RAIN_CFG.ProceduralRate
	pe.Lifetime = NumberRange.new(RAIN_CFG.ProceduralLifetime, RAIN_CFG.ProceduralLifetime)
	pe.Speed = RAIN_CFG.ProceduralSpeed
	pe.SpreadAngle = RAIN_CFG.ProceduralSpreadAngle
	pe.Size = RAIN_CFG.ProceduralSize
	pe.VelocityInheritance = 0.2
	pe.Drag = 1
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.LightEmission = 0.25
	pe.Color = ColorSequence.new(Color3.fromRGB(170, 200, 255))
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	return pe
end

function WorldFXController:_tearDownRain()
	if self._rainTrove then
		self._rainTrove:Destroy()
		self._rainTrove = nil
	end
	self._rainEmitter = nil
end

function WorldFXController:_computeRate(weather: string, reduced: boolean): number
	local rate = if self._useProceduralRain then RAIN_CFG.ProceduralRate else RAIN_CFG.Rate
	if weather == "Storm" then
		rate *= RAIN_CFG.StormRateMultiplier
	end
	if reduced then
		rate *= RAIN_CFG.ReducedMotionRateMultiplier
	end
	return rate
end

function WorldFXController:_startWindSway(emitter: ParticleEmitter, trove: any)
	local spread = RAIN_CFG.WindSwaySpreadDegrees
	local base = self._baseSpread
	local target = Vector2.new(base.X + spread, base.Y + spread)
	local info = TweenInfo.new(
		RAIN_CFG.WindSwayPeriodSeconds,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	)
	local tween = TweenService:Create(emitter, info, { SpreadAngle = target })
	tween:Play()
	trove:Add(tween)
end

function WorldFXController:_applyRain(weather: string)
	if not isRainyWeather(weather) then
		self:_tearDownRain()
		return
	end

	self:_tearDownRain()

	local camera = Workspace.CurrentCamera
	if not camera then
		warn("[WorldFX] No CurrentCamera — rain deferred until camera exists")
		return
	end

	local reduced = MotionUtil.reducedMotionEnabled()
	local emitter: ParticleEmitter
	if self._rainTemplate then
		emitter = self._rainTemplate:Clone()
		emitter.Texture = RAIN_CFG.PlaceholderTextureId
		emitter.Lifetime = NumberRange.new(RAIN_CFG.Lifetime, RAIN_CFG.Lifetime)
	else
		emitter = self:_createProceduralRainEmitter()
	end

	emitter.Name = "WorldFX_Rain"
	emitter.Rate = self:_computeRate(weather, reduced)
	emitter.Enabled = true
	emitter.SpreadAngle = if reduced then Vector2.zero else self._baseSpread
	emitter.Parent = camera

	local trove = Trove.new()
	trove:Add(emitter)

	if not reduced then
		self:_startWindSway(emitter, trove)
	end

	self._rainTrove = trove
	self._rainEmitter = emitter
	self:_logRainSourceOnce()
end

function WorldFXController:_onWeatherChanged(weather: string, sound: any, baseVol: number)
	self._currentWeather = weather
	if weather == "Storm" then
		sound:SetAmbientVolume(0.7)
	elseif weather == "Rain" then
		sound:SetAmbientVolume(0.55)
	else
		sound:SetAmbientVolume(baseVol)
	end
	self:_applyRain(weather)
	-- ColorCorrectionEffect is a PostEffect and can only be created client-side.
	WeatherVisuals.applyColorCorrection(weather)
end

function WorldFXController:KnitStart()
	local TideService    = Knit.GetService("TideService")
	local WeatherService = Knit.GetService("WeatherService")
	local HarborService  = Knit.GetService("HarborService")
	local sound = Knit.GetController("SoundController")
	local baseVol = GameConfig.Audio.AmbientBaseVolume
	self._sound = sound
	self._baseVol = baseVol

	local trove = Trove.new()

	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	if assets then
		local weatherFolder = assets:FindFirstChild("Weather")
		local rainFolder = weatherFolder and weatherFolder:FindFirstChild("Rain")
		local template = rainFolder and rainFolder:FindFirstChild("RainEmitter")
		if template and template:IsA("ParticleEmitter") then
			self._rainTemplate = template
			self._baseSpread = template.SpreadAngle
		else
			self._useProceduralRain = true
			warn("[WorldFX] Missing Assets.Weather.Rain.RainEmitter — using procedural rain")
		end
	else
		self._useProceduralRain = true
		warn("[WorldFX] Missing ReplicatedStorage.Assets — using procedural rain")
	end

	TideService.TideChanged:Connect(function(state, level)
		self._targetTideLevel = level
		Workspace:SetAttribute("TideState", state)
		Workspace:SetAttribute("TideOffset", level * 1.5)
	end)

	local function handleWeather(weather: string)
		if type(weather) ~= "string" or weather == "" then return end
		self:_onWeatherChanged(weather, sound, baseVol)
	end

	trove:Add(WeatherService.WeatherChanged:Connect(handleWeather))

	trove:Add(Workspace:GetAttributeChangedSignal(ATTR_WEATHER):Connect(function()
		local weather = Workspace:GetAttribute(ATTR_WEATHER)
		if type(weather) == "string" then
			handleWeather(weather)
		end
	end))

	trove:Add(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if isRainyWeather(self._currentWeather) then
			self:_applyRain(self._currentWeather)
		end
	end))

	trove:Add(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		if isRainyWeather(self._currentWeather) then
			self:_applyRain(self._currentWeather)
		end
	end))

	HarborService.HarborVisualUpdate:Connect(function(uid: string, kind: string, tier: number, worldPos: Vector3)
		print(("[WorldFX] HarborVisualUpdate uid=%s kind=%s tier=%d pos=%s"):format(uid, kind, tier, tostring(worldPos)))
	end)

	local initial = Workspace:GetAttribute(ATTR_WEATHER)
	if type(initial) == "string" then
		handleWeather(initial)
	end

	WeatherService:GetWeatherState():andThen(function(payload: { weather: string, timeOfDay: string })
		handleWeather(payload.weather)
	end)
end

return WorldFXController
