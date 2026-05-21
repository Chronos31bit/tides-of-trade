--!strict
-- TideService.lua
-- 20-minute high/low tide cycle. The visual change (water level) is also
-- driven from here so server and client stay in sync — clients receive the
-- current TideLevel value (-1..1, sinusoidal) and can lerp the actual water
-- mesh locally.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit       = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local TideService = Knit.CreateService({
	Name = "TideService",
	Client = {
		TideChanged = Knit.CreateSignal(),  -- (state: "High"|"Low"|"Transitioning", level: -1..1)
	},
	_state = "Low",
	_level = -1,
	_startTime = 0,
})

function TideService:KnitInit()
	self._startTime = os.clock()
end

function TideService:KnitStart()
	-- Tick every 5 seconds. Cheaper than per-frame and the client lerps the
	-- visual tide mesh between updates.
	task.spawn(function()
		while true do
			self:_update()
			-- Broadcast to all clients. Knit handles per-player iteration when
			-- you Fire to all subscribers.
			for _, player in ipairs(game.Players:GetPlayers()) do
				self.Client.TideChanged:Fire(player, self._state, self._level)
			end
			task.wait(5)
		end
	end)
end

function TideService:_update()
	local elapsed = os.clock() - self._startTime
	local cycle = elapsed % GameConfig.Tides.CycleSeconds
	local phase = cycle / GameConfig.Tides.CycleSeconds  -- 0..1
	-- Sinusoidal level curve. At phase=0 we're at low tide (level=-1),
	-- phase=0.5 high tide (level=1), phase=1.0 back to low.
	self._level = -math.cos(phase * math.pi * 2)
	-- Discrete state: top HighFraction of cycle = High, bottom HighFraction = Low,
	-- the rest is "Transitioning" (visual only — fish use High/Low cleanly).
	local hi = GameConfig.Tides.HighFraction
	if self._level >= 1 - hi then
		self._state = "High"
	elseif self._level <= -1 + hi then
		self._state = "Low"
	else
		self._state = "Transitioning"
	end
end

-- Server-callable for FishingService.
function TideService:GetTide(): string
	-- Eligibility-wise we treat "Transitioning" as Low (deep-water mythics
	-- only spawn in fully-High windows). This makes high tide a tangible event.
	if self._state == "High" then return "High" end
	return "Low"
end

function TideService:GetLevel(): number
	return self._level
end

return TideService
