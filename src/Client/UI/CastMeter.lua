--!strict
-- CastMeter.lua
-- Timing-meter overlay shown during a cast. The marker oscillates 0..1 on
-- a sine over `period` seconds. The green zone is supplied by the server
-- (greenCenter, greenSize). On release, the controller sends marker back
-- to the server which authoritatively decides hit/miss.
--
-- Polish layered on top of the original mechanic:
--   * Slide-in/out transitions (Quad ease), tween-driven; reduced motion = snap.
--   * Inner "perfect" zone — gold sliver at center 25% of the green zone.
--     A marker passing through this zone triggers a "PERFECT!" flash above
--     the meter (rate-limited to once / second). The flash is *cosmetic*
--     today — the current server contract doesn't reward perfect catches.
--     Once a server-side reel phase lands, the controller can use
--     handle.perfectTime / handle.totalActiveTime to feed perfectFraction
--     to FishingService:ReleaseReel.
--   * Tracks perfectTime and totalTime so the controller can read them on
--     release (handle.stop() returns them alongside the marker).

local RunService   = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIUtil     = require(script.Parent.UIUtil)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CastMeter = {}

local P  = UIUtil.Palette
local FT = GameConfig.Fishing.FeelTuning

export type CastMeterHandle = {
	gui: ScreenGui,
	bar: Frame,
	greenZone: Frame,
	marker: Frame,
	-- stop() returns: markerAtRelease, perfectFraction (0..1).
	-- perfectFraction = perfectTime / totalTimeInGreen. 0 if never in green.
	stop: () -> (number, number),
}

function CastMeter.show(greenCenter: number, greenSize: number, period: number): CastMeterHandle
	local gui = UIUtil.makeScreenGui("CastMeter")

	-- ----------------------------------------------------------------
	-- BAR — anchored at lower-third, slides in from below.
	-- ----------------------------------------------------------------
	local restPos = UDim2.new(0.5, 0, 0.66, 0)
	local offPos  = UDim2.new(0.5, 0, 0.66, 80)  -- starts 80px below rest

	local bar = UIUtil.makePanel({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = offPos,
		Size = UDim2.new(0.6, 0, 0, 28),
		BackgroundColor3 = P.WoodDark,
	})
	local barMax = Instance.new("UISizeConstraint"); barMax.MaxSize = Vector2.new(540, 28); barMax.Parent = bar
	bar.Parent = gui

	-- Slide / fade in. Reduced motion = snap to rest.
	MotionUtil.tweenOrSnap(bar, TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = restPos,
	})

	-- ----------------------------------------------------------------
	-- GREEN ZONE — server's success window.
	-- ----------------------------------------------------------------
	local green = Instance.new("Frame")
	green.Name = "Green"
	green.BackgroundColor3 = P.Uncommon
	green.BackgroundTransparency = 0.1
	green.BorderSizePixel = 0
	green.Position = UDim2.new(greenCenter - greenSize / 2, 0, 0, 0)
	green.Size = UDim2.new(greenSize, 0, 1, 0)
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 4); gc.Parent = green
	green.Parent = bar

	-- ----------------------------------------------------------------
	-- PERFECT INNER ZONE — gold sliver at center 25% of the green zone.
	-- Width = greenSize * PerfectZoneFraction; positioned so its center
	-- aligns with greenCenter.
	-- ----------------------------------------------------------------
	local perfectSize = greenSize * FT.PerfectZoneFraction
	local perfectLow  = greenCenter - perfectSize / 2
	local perfectHigh = greenCenter + perfectSize / 2

	local perfect = Instance.new("Frame")
	perfect.Name = "Perfect"
	perfect.BackgroundColor3 = P.Gold
	perfect.BackgroundTransparency = 0.15
	perfect.BorderSizePixel = 0
	-- Positioned relative to the bar (not the green zone), so the X math is
	-- absolute on the meter. perfectLow is in [0, 1] of the bar's width.
	perfect.Position = UDim2.new(perfectLow, 0, 0, 0)
	perfect.Size = UDim2.new(perfectSize, 0, 1, 0)
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 4); pc.Parent = perfect
	perfect.Parent = bar

	-- ----------------------------------------------------------------
	-- MARKER — moving slice. We extend it slightly above/below the bar so
	-- it's still readable when over the perfect strip.
	-- ----------------------------------------------------------------
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.new(0, 0, 0.5, 0)
	marker.Size = UDim2.new(0, 6, 1.5, 0)
	marker.BackgroundColor3 = P.Cream
	marker.BorderSizePixel = 0
	local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 2); mc.Parent = marker
	marker.Parent = bar

	-- ----------------------------------------------------------------
	-- "PERFECT!" flash label — a small text above the bar, hidden by
	-- default. Tween in/out when the marker enters the perfect zone.
	-- Rate-limited to once per second so it doesn't spam if the player
	-- ping-pongs across the boundary.
	-- ----------------------------------------------------------------
	local flash = Instance.new("TextLabel")
	flash.Name = "PerfectFlash"
	flash.BackgroundTransparency = 1
	flash.AnchorPoint = Vector2.new(0.5, 1)
	flash.Position = UDim2.new(0.5, 0, 0, -12)
	flash.Size = UDim2.fromOffset(220, 30)
	flash.Font = Enum.Font.GothamBlack
	flash.TextSize = 22
	flash.TextColor3 = P.Gold
	flash.TextTransparency = 1
	flash.Text = "PERFECT!"
	flash.Parent = bar

	local lastFlashAt = -math.huge
	local function maybeFlash()
		if MotionUtil.reducedMotionEnabled() then return end  -- skip flash on reduced motion
		local now = os.clock()
		if now - lastFlashAt < 1.0 then return end  -- rate limit
		lastFlashAt = now
		-- Fade in fast, hold briefly, fade out.
		flash.TextTransparency = 0
		flash.Position = UDim2.new(0.5, 0, 0, -12)
		MotionUtil.tween(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, -28),  -- drift up
		})
	end

	-- ----------------------------------------------------------------
	-- HEARTBEAT LOOP — per-frame marker update + perfect-zone tracking.
	-- We accumulate perfectTime (time spent inside the inner zone) and
	-- greenTime (time inside the green zone). The controller reads the
	-- ratio on release to estimate "how perfect was this catch".
	-- ----------------------------------------------------------------
	local startT = os.clock()
	local lastFrameAt = startT
	local lastMarker = 0.5
	local perfectTime = 0
	local greenTime = 0
	local wasInPerfect = false
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = now - lastFrameAt
		lastFrameAt = now

		local t = now - startT
		-- (sin(2π t/period) + 1) / 2 → smooth 0..1 ping-pong.
		local p = (math.sin(t / period * math.pi * 2) + 1) / 2
		lastMarker = p
		marker.Position = UDim2.new(p, 0, 0.5, 0)

		-- Time accounting: how long the marker has been inside each zone.
		local inGreen   = p >= (greenCenter - greenSize / 2) and p <= (greenCenter + greenSize / 2)
		local inPerfect = p >= perfectLow and p <= perfectHigh
		if inGreen then greenTime += dt end
		if inPerfect then perfectTime += dt end

		-- Edge trigger: marker just entered the perfect zone.
		if inPerfect and not wasInPerfect then maybeFlash() end
		wasInPerfect = inPerfect
	end)

	-- ----------------------------------------------------------------
	-- STOP — disconnect, fade out, return marker + perfectFraction.
	-- ----------------------------------------------------------------
	local handle: CastMeterHandle = {
		gui = gui,
		bar = bar,
		greenZone = green,
		marker = marker,
		stop = function()
			if conn then conn:Disconnect(); conn = nil end
			-- Tween bar back down before destroying. On reduced motion,
			-- destroy after a short delay to let any pending state settle.
			local outTween = MotionUtil.tweenOrSnap(bar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = offPos,
			})
			if outTween then
				outTween.Completed:Connect(function() outTween:Destroy(); gui:Destroy() end)
			else
				task.delay(0.1, function() gui:Destroy() end)
			end
			local frac = (greenTime > 0) and (perfectTime / greenTime) or 0
			return lastMarker, math.clamp(frac, 0, 1)
		end,
	}
	return handle
end

return CastMeter
