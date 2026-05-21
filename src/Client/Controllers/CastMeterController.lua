--!strict
-- CastMeterController.lua
-- Knit lifecycle owner for the cast meter UI. Wraps CastMeter.show() so
-- FishingController stays the state-machine orchestrator without touching
-- CastMeter directly.
--
-- Two Trove levels:
--   _trove      — controller lifetime; owns the ReelComplete/ReelEscaped
--                 BindableEvents only.
--   _meterTrove — per-cast lifetime; owns the handle cleanup, the
--                 FishingService.CastResolved auto-dismiss connection,
--                 and the reel-signal bridges into the controller events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local CastMeter  = require(script.Parent.Parent.UI.CastMeter)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local CastMeterController = Knit.CreateController({
	Name = "CastMeterController",
	_trove           = nil :: any,
	_meterTrove      = nil :: any,
	_handle          = nil :: any,   -- current CastMeterHandle; nil when idle
	_reelCompleteEvt = nil :: any,
	_reelEscapedEvt  = nil :: any,
	-- Public signals (controller-lifetime). FishingController connects once in
	-- KnitStart. They fire only while a cast/reel is active.
	ReelComplete = nil :: any,  -- fires (perfectFraction: number)
	ReelEscaped  = nil :: any,  -- fires ()
})

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function CastMeterController:KnitInit()
	self._trove = Trove.new()

	local completeEvt = Instance.new("BindableEvent")
	local escapedEvt  = Instance.new("BindableEvent")
	self._reelCompleteEvt = completeEvt
	self._reelEscapedEvt  = escapedEvt
	self.ReelComplete = completeEvt.Event
	self.ReelEscaped  = escapedEvt.Event
	self._trove:Add(completeEvt)
	self._trove:Add(escapedEvt)
end

function CastMeterController:KnitStop()
	self:dismiss()
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

-- Show the cast meter and return the cast button so FishingController can
-- wire its Activated event.
--
-- Reduced motion: the oscillation is frozen at 0.5 immediately. Player sees
-- a static marker at center and taps to confirm; server receives marker=0.5
-- which lands safely inside any normal green zone.
function CastMeterController:show(greenCenter: number, greenSize: number, period: number): Instance
	self:dismiss()

	local meterTrove = Trove.new()
	self._meterTrove = meterTrove

	local handle = CastMeter.show(greenCenter, greenSize, period, {})
	self._handle = handle

	-- Reduced motion: freeze the oscillation so no animation runs. The handle's
	-- releaseCast() stops the Heartbeat tick and returns lastMarker (0.5 at init).
	-- The player taps to confirm; releaseCast() below will return 0.5 again.
	if MotionUtil.reducedMotionEnabled() then
		handle.releaseCast()
	end

	-- Bridge the handle's per-cast BindableEvents into the controller-lifetime
	-- signals so FishingController can stay connected across cast cycles.
	meterTrove:Add(handle.onComplete:Connect(function(perfectFraction: number)
		self._reelCompleteEvt:Fire(perfectFraction)
	end))
	meterTrove:Add(handle.onEscape:Connect(function()
		self._reelEscapedEvt:Fire()
	end))

	-- Auto-dismiss when the server signals cast resolution (hit, miss, timeout,
	-- escape). FishingController._disposeCast also calls dismiss(); the second
	-- call is a no-op since _meterTrove is nil after the first.
	local FishingService = Knit.GetService("FishingService")
	meterTrove:Add(FishingService.CastResolved:Connect(function()
		self:dismiss()
	end))

	-- Stop the handle on any cleanup path (explicit dismiss or auto-dismiss).
	meterTrove:Add(function()
		if self._handle then
			self._handle.stop()
			self._handle = nil
		end
	end)

	return handle.castButton
end

-- Lock the cast oscillation and return (marker, isPerfect).
-- Must be called just before FishingController:ClaimCast so the value is
-- frozen before shipping to the server.
function CastMeterController:releaseCast(): (number, boolean)
	if not self._handle then return 0.5, false end
	return self._handle.releaseCast()
end

-- Transition the meter from cast phase to reel phase.
-- Tween the cast visuals out and build the horizontal reel bar in.
function CastMeterController:enterReel(weightKg: number, tier: string, params: CastMeter.TierParams, rarity: string)
	if not self._handle then return end
	self._handle.enterReel(weightKg, tier, params, rarity)
end

-- Drive the reel indicator. FishingController calls this from InputBegan/InputEnded
-- during the reel phase. No-op when no meter is active.
function CastMeterController:setHold(pressed: boolean)
	if not self._handle then return end
	self._handle.setHold(pressed)
end

-- Tear down the current meter. Safe to call when no meter is active.
function CastMeterController:dismiss()
	if self._meterTrove then
		self._meterTrove:Destroy()
		self._meterTrove = nil
	end
	-- _handle is nil'd by the cleanup function added in show().
end

return CastMeterController
