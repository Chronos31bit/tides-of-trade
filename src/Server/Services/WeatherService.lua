--!strict
-- WeatherService.lua
-- Drives the Lighting environment (clock time, atmosphere, post-FX) and
-- exposes the current weather/timeOfDay to other services.

local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local Knit           = require(ReplicatedStorage.Packages.Knit)
local GameConfig     = require(ReplicatedStorage.Shared.Config.GameConfig)
local WeatherVisuals = require(ReplicatedStorage.Shared.Util.WeatherVisuals)

local ATTR_WEATHER = GameConfig.Weather.WorkspaceAttribute
local ATTR_LOCKED  = GameConfig.Weather.WorkspaceLockedAttribute
local REMOTES_FOLDER = "TidesRemotes"
local REMOTE_FORCE_WEATHER = "ForceWeather"

local WeatherService = Knit.CreateService({
	Name = "WeatherService",
	Client = {
		WeatherChanged = Knit.CreateSignal(),
		TimeOfDayChanged = Knit.CreateSignal(),
	},
	_weather = "Clear",
	_previousWeather = "Clear",
	_timeOfDay = "Day",
	_clock = 8,
	_weatherLocked = false,
	_forceWeatherRemote = nil :: RemoteEvent?,
})

local VALID_WEATHER: {[string]: boolean} = {}
for state in pairs(GameConfig.Weather.Transitions) do
	VALID_WEATHER[state] = true
end

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
	if clock >= 5 and clock < 9 then return "Morning" end
	if clock >= 9 and clock < 17 then return "Day" end
	if clock >= 17 and clock < 20 then return "Dusk" end
	return "Night"
end

function WeatherService:_syncWorkspaceAttributes()
	Workspace:SetAttribute(ATTR_WEATHER, self._weather)
	Workspace:SetAttribute(ATTR_LOCKED, self._weatherLocked)
end

function WeatherService:_broadcastWeather(durationSeconds: number)
	for _, player in ipairs(Players:GetPlayers()) do
		self.Client.WeatherChanged:Fire(player, self._weather, self._previousWeather, durationSeconds)
	end
end

function WeatherService:SetWeather(weather: string, lockMarkov: boolean?): boolean
	if not VALID_WEATHER[weather] then
		return false
	end
	self._previousWeather = self._weather
	self._weather = weather
	if lockMarkov ~= nil then
		self._weatherLocked = lockMarkov
	end
	self:_syncWorkspaceAttributes()
	local duration = GameConfig.Weather.Transition.DurationSeconds
	self:_applyVisuals(duration)
	self:_broadcastWeather(duration)
	if RunService:IsStudio() then
		print(("[WeatherService] SetWeather → %s (prev %s, dur %.2fs) locked=%s"):format(
			weather, self._previousWeather, duration, tostring(self._weatherLocked)
		))
	end
	return true
end

function WeatherService:UnlockWeather()
	self._weatherLocked = false
	self:_syncWorkspaceAttributes()
end

function WeatherService:IsWeatherLocked(): boolean
	return self._weatherLocked
end

function WeatherService:_applyVisuals(durationSeconds: number?)
	Lighting.ClockTime = self._clock
	WeatherVisuals.apply(self._weather, durationSeconds)
end

function WeatherService:_handleForceWeatherRequest(player: Player, weather: string, lockMarkov: boolean?)
	local AdminService = Knit.GetService("AdminService")
	if not AdminService:_isAdmin(player) then
		return
	end
	if type(weather) ~= "string" or not VALID_WEATHER[weather] then
		return
	end
	local lock = if lockMarkov == nil then true else lockMarkov
	self:SetWeather(weather, lock)
end

function WeatherService:KnitStart()
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER
		folder.Parent = ReplicatedStorage
	end
	local remote = folder:FindFirstChild(REMOTE_FORCE_WEATHER)
	if not remote or not remote:IsA("RemoteEvent") then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_FORCE_WEATHER
		remote.Parent = folder
	end
	self._forceWeatherRemote = remote

	remote.OnServerEvent:Connect(function(player: Player, weather: string, lockMarkov: boolean?)
		self:_handleForceWeatherRequest(player, weather, lockMarkov)
	end)

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
			self:_applyVisuals(GameConfig.Weather.Transition.DurationSeconds)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(GameConfig.Weather.TickSeconds)
			if not self._weatherLocked then
				local next_ = pickNext(self._weather)
				if next_ ~= self._weather then
					self._previousWeather = self._weather
					self._weather = next_
					self:_syncWorkspaceAttributes()
					local duration = GameConfig.Weather.Transition.DurationSeconds
					self:_applyVisuals(duration)
					self:_broadcastWeather(duration)
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Initial fire: duration 0 so the joining client snaps to current state.
		self.Client.WeatherChanged:Fire(player, self._weather, self._weather, 0)
		self.Client.TimeOfDayChanged:Fire(player, self._timeOfDay)
	end)

	self:_syncWorkspaceAttributes()
	self:_applyVisuals(0)
end

function WeatherService:GetWeather(): string return self._weather end
function WeatherService:GetTimeOfDay(): string return self._timeOfDay end
function WeatherService:GetClock(): number return self._clock end

function WeatherService.Client:ForceWeather(
	player: Player,
	weather: string,
	lockMarkov: boolean?
): { ok: boolean, reason: string?, weather: string? }
	local server = self.Server
	local AdminService = Knit.GetService("AdminService")
	if not AdminService:_isAdmin(player) then
		return { ok = false, reason = "denied" }
	end
	if not VALID_WEATHER[weather] then
		return { ok = false, reason = "invalid" }
	end
	local lock = if lockMarkov == nil then true else lockMarkov
	if not server:SetWeather(weather, lock) then
		return { ok = false, reason = "failed" }
	end
	return { ok = true, weather = server:GetWeather() }
end

function WeatherService.Client:GetWeatherState(_player: Player): { weather: string, timeOfDay: string }
	return {
		weather = self.Server:GetWeather(),
		timeOfDay = self.Server:GetTimeOfDay(),
	}
end

return WeatherService
