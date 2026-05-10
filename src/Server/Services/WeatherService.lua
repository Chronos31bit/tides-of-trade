--!strict
-- WeatherService.lua
-- Drives the Lighting environment (clock time, atmosphere, post-FX) and
-- exposes the current weather/timeOfDay to other services. The state machine
-- is a simple weighted Markov chain configured in GameConfig.Weather.

local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local WeatherService = Knit.CreateService({
	Name = "WeatherService",
	Client = {
		WeatherChanged = Knit.CreateSignal(),  -- (weather)
		TimeOfDayChanged = Knit.CreateSignal(),-- (timeOfDay)
	},
	_weather = "Clear",
	_timeOfDay = "Day",
	_clock = 8,  -- starts at 08:00 game-time
})

local function pickNext(current: string): string
	local row = GameConfig.Weather.Transitions[current]
	if not row then return current end
	local roll = math.random()
	local cumulative = 0
	for to, prob in pairs(row) do
		cumulative += prob
		if roll <= cumulative then return to end
	end
	return current
end

local function classifyTimeOfDay(clock: number): string
	-- Bands match GameConfig comments: Morning 5-9, Day 9-17, Dusk 17-20, Night 20-5.
	if clock >= 5 and clock < 9 then return "Morning" end
	if clock >= 9 and clock < 17 then return "Day" end
	if clock >= 17 and clock < 20 then return "Dusk" end
	return "Night"
end

-- Lazily create the Atmosphere instance the first time we need it. Doing
-- this in code (rather than the Rojo project file) keeps the project file
-- minimal and avoids Color3-as-array deserialization issues.
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

function WeatherService:_applyVisuals()
	-- ClockTime drives sun position. We update it each tick.
	Lighting.ClockTime = self._clock

	local atm = ensureAtmosphere()

	if self._weather == "Clear" then
		atm.Density = 0.30; atm.Haze = 1.0
		atm.Color = Color3.fromRGB(232, 200, 168)
	elseif self._weather == "Cloudy" then
		atm.Density = 0.45; atm.Haze = 1.6
		atm.Color = Color3.fromRGB(190, 190, 195)
	elseif self._weather == "Rain" then
		atm.Density = 0.55; atm.Haze = 2.0
		atm.Color = Color3.fromRGB(150, 160, 175)
	elseif self._weather == "Storm" then
		atm.Density = 0.65; atm.Haze = 2.6
		atm.Color = Color3.fromRGB(110, 115, 130)
	elseif self._weather == "Fog" then
		atm.Density = 0.6; atm.Haze = 3.5
		atm.Color = Color3.fromRGB(220, 220, 220)
	end
end

function WeatherService:KnitStart()
	-- Two background loops: one advances time-of-day, one rolls weather.
	-- A real game-day completes in MinutesPerGameDay real minutes.

	-- Time-of-day loop: advance ClockTime by 1 hour every (MinutesPerGameDay * 60 / 24) seconds.
	task.spawn(function()
		local secondsPerHour = (GameConfig.TimeOfDay.MinutesPerGameDay * 60) / 24
		while true do
			task.wait(secondsPerHour)
			self._clock = (self._clock + 1) % 24
			local newTOD = classifyTimeOfDay(self._clock)
			if newTOD ~= self._timeOfDay then
				self._timeOfDay = newTOD
				for _, player in ipairs(Players:GetPlayers()) do
					self.Client.TimeOfDayChanged:Fire(player, newTOD)
				end
			end
			self:_applyVisuals()
		end
	end)

	-- Weather loop.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Weather.TickSeconds)
			local next_ = pickNext(self._weather)
			if next_ ~= self._weather then
				self._weather = next_
				self:_applyVisuals()
				for _, player in ipairs(Players:GetPlayers()) do
					self.Client.WeatherChanged:Fire(player, next_)
				end
			end
		end
	end)

	-- Initial paint so the world looks intentional from second zero.
	self:_applyVisuals()
end

function WeatherService:GetWeather(): string return self._weather end
function WeatherService:GetTimeOfDay(): string return self._timeOfDay end
function WeatherService:GetClock(): number return self._clock end

return WeatherService
