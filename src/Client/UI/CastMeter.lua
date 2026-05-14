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

-- ====================================================================
-- REEL MINI-GAME (Path A)
-- ====================================================================
-- A second, distinct meter spawned after the bite. The cast meter has
-- already been :stop()'d by the controller; this one slides in from the
-- same anchor (same look-and-feel; the prompt's "smooth transition" is
-- realized by the two meters' tween-out / tween-in overlap).
--
-- Mechanics:
--   * An "indicator" lives somewhere in [0, 1] on the bar.
--   * The "good zone" — width set by tier — slides left/right as a sine
--     wave whose period is faster for heavier fish.
--   * The player holds a button → indicator moves right at hold speed.
--     Release → indicator drifts left at release speed.
--   * Time the indicator spends in the good zone counts toward
--     ReelHoldDuration; time in the inner perfect zone counts double.
--   * If the indicator reaches 0 while drifting → escape (fish lost).
--   * Once cumulative tracking time reaches ReelHoldDuration, the meter
--     fires onSuccess(perfectFraction) and stops itself.
--
-- The controller wires real input (mouse / touch / gamepad) into the
-- handle's setHolding(bool). The meter exposes onSuccess and onEscape
-- as plain function fields the controller assigns.

export type ReelMeterHandle = {
	gui: ScreenGui,
	setHolding: (boolean) -> (),
	-- Assigned by the controller before the meter starts firing. onSuccess
	-- and onEscape fire at most once; onStateChanged may fire repeatedly as
	-- the indicator weaves in and out of the zone ("neutral" / "tracking" /
	-- "losing"). The controller layers zone-loss camera shake on top.
	onSuccess: ((perfectFraction: number) -> ())?,
	onEscape: (() -> ())?,
	onStateChanged: ((state: string) -> ())?,
	stop: () -> (),
}

function CastMeter.reel(weightKg: number, tier: string, difficulty: number): ReelMeterHandle
	local gui = UIUtil.makeScreenGui("ReelMeter")

	-- Bar reuses the cast-meter palette so the visual transition reads
	-- as "same meter, new mode" rather than a context-switch.
	local restPos = UDim2.new(0.5, 0, 0.66, 0)
	local offPos  = UDim2.new(0.5, 0, 0.66, 80)

	local bar = UIUtil.makePanel({
		Name = "ReelBar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = offPos,
		Size = UDim2.new(0.6, 0, 0, 28),
		BackgroundColor3 = P.WoodDark,
	})
	local barMax = Instance.new("UISizeConstraint"); barMax.MaxSize = Vector2.new(540, 28); barMax.Parent = bar
	bar.Parent = gui

	-- Slide / fade in.
	MotionUtil.tweenOrSnap(bar, TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = restPos,
	})

	-- Tier label (small, above the bar) so the player understands why this
	-- fish is fighting harder. Cosmetic only; tier comes from the server.
	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "TierLabel"
	tierLabel.BackgroundTransparency = 1
	tierLabel.AnchorPoint = Vector2.new(0.5, 1)
	tierLabel.Position = UDim2.new(0.5, 0, 0, -6)
	tierLabel.Size = UDim2.fromOffset(220, 18)
	tierLabel.Font = Enum.Font.GothamBold
	tierLabel.TextSize = 14
	tierLabel.TextColor3 = P.CreamSoft
	tierLabel.Text = ("%s — %.1f kg"):format(tier:upper(), weightKg)
	tierLabel.Parent = bar

	-- ----------------------------------------------------------------
	-- DIFFICULTY-DRIVEN PARAMETERS
	-- ----------------------------------------------------------------
	local zoneWidth = math.max(0.08, FT.ReelZoneBaseWidth + FT.ReelZoneWidthPerDifficulty * difficulty)
	local zoneOmega = FT.ReelZoneSpeedBase + FT.ReelZoneSpeedPerKg * weightKg
	local holdSpeed = FT.ReelIndicatorHoldSpeed
	local releaseSpeed = FT.ReelIndicatorReleaseSpeed
	-- Heavier fish drift back faster too — adds the "wrestling" feel.
	releaseSpeed = releaseSpeed * (1 + 0.5 * difficulty)

	-- ----------------------------------------------------------------
	-- ZONE — green strip with a gold inner perfect strip.
	-- Both move together via UDim2 position update each Heartbeat.
	-- ----------------------------------------------------------------
	local zone = Instance.new("Frame")
	zone.Name = "Zone"
	zone.BackgroundColor3 = P.Uncommon
	zone.BackgroundTransparency = 0.15
	zone.BorderSizePixel = 0
	zone.Size = UDim2.new(zoneWidth, 0, 1, 0)
	zone.Position = UDim2.new(0.5 - zoneWidth / 2, 0, 0, 0)
	local zc = Instance.new("UICorner"); zc.CornerRadius = UDim.new(0, 4); zc.Parent = zone
	zone.Parent = bar

	-- Stroke used to show "tracking" state via Color tween.
	local zoneStroke = Instance.new("UIStroke")
	zoneStroke.Color = P.WoodDark
	zoneStroke.Thickness = 1
	zoneStroke.Transparency = 0.6
	zoneStroke.Parent = zone

	local perfectWidth = zoneWidth * FT.PerfectZoneFraction
	local perfect = Instance.new("Frame")
	perfect.Name = "Perfect"
	perfect.BackgroundColor3 = P.Gold
	perfect.BackgroundTransparency = 0.15
	perfect.BorderSizePixel = 0
	perfect.Size = UDim2.new(perfectWidth, 0, 1, 0)
	perfect.Position = UDim2.new(zoneWidth / 2 - perfectWidth / 2, 0, 0, 0)
	local pc2 = Instance.new("UICorner"); pc2.CornerRadius = UDim.new(0, 3); pc2.Parent = perfect
	perfect.Parent = zone

	-- ----------------------------------------------------------------
	-- INDICATOR — the player's cursor on the bar.
	-- ----------------------------------------------------------------
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.Position = UDim2.new(0, 0, 0.5, 0)
	indicator.Size = UDim2.new(0, 8, 1.5, 0)
	indicator.BackgroundColor3 = P.Cream
	indicator.BorderSizePixel = 0
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 2); ic.Parent = indicator
	indicator.Parent = bar

	-- ----------------------------------------------------------------
	-- PROGRESS BAR — thin sliver below the meter, fills as the player
	-- tracks the zone. Diagetic feedback: "how close to landing the fish".
	-- ----------------------------------------------------------------
	local progressTrack = Instance.new("Frame")
	progressTrack.Name = "ProgressTrack"
	progressTrack.BackgroundColor3 = P.TealDeeper
	progressTrack.BorderSizePixel = 0
	progressTrack.AnchorPoint = Vector2.new(0.5, 0)
	progressTrack.Position = UDim2.new(0.5, 0, 1, 4)
	progressTrack.Size = UDim2.new(1, 0, 0, 4)
	progressTrack.Parent = bar
	local progressFill = Instance.new("Frame")
	progressFill.Name = "Fill"
	progressFill.BackgroundColor3 = P.Gold
	progressFill.BorderSizePixel = 0
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.Parent = progressTrack

	-- ----------------------------------------------------------------
	-- STATE MACHINE: neutral / tracking / losing.
	-- Tween between visual states cleanly.
	-- ----------------------------------------------------------------
	local function setState(state: string)
		if state == "tracking" then
			MotionUtil.tweenOrSnap(zoneStroke, TweenInfo.new(0.15), { Color = P.Success, Thickness = 2, Transparency = 0 })
			MotionUtil.tweenOrSnap(indicator, TweenInfo.new(0.15), { BackgroundColor3 = P.Cream })
		elseif state == "losing" then
			MotionUtil.tweenOrSnap(indicator, TweenInfo.new(0.12), { BackgroundColor3 = P.Danger })
			MotionUtil.tweenOrSnap(zoneStroke, TweenInfo.new(0.15), { Color = P.WoodDark, Thickness = 1, Transparency = 0.6 })
			-- Tiny 0.2s UI shake on the bar — purely cosmetic.
			if not MotionUtil.reducedMotionEnabled() then
				local origPos = bar.Position
				local startT = os.clock()
				local SHAKE_DUR = 0.2
				local shakeConn: RBXScriptConnection?
				shakeConn = RunService.Heartbeat:Connect(function()
					local t = (os.clock() - startT) / SHAKE_DUR
					if t >= 1 then
						bar.Position = origPos
						if shakeConn then shakeConn:Disconnect() end
						return
					end
					local m = 4 * (1 - t)
					bar.Position = origPos + UDim2.fromOffset(
						(math.random() - 0.5) * 2 * m,
						(math.random() - 0.5) * 2 * m
					)
				end)
			end
		else  -- neutral
			MotionUtil.tweenOrSnap(zoneStroke, TweenInfo.new(0.2), { Color = P.WoodDark, Thickness = 1, Transparency = 0.6 })
			MotionUtil.tweenOrSnap(indicator, TweenInfo.new(0.2), { BackgroundColor3 = P.CreamSoft })
		end
	end

	-- ----------------------------------------------------------------
	-- RUNTIME
	-- ----------------------------------------------------------------
	local handle: ReelMeterHandle = nil :: any  -- forward declare for closures
	local holding = false
	local indicatorPos = 0.5  -- starts at center to give the player a fair shot
	local startT = os.clock()
	local lastFrameAt = startT
	local progress = 0       -- toward ReelHoldDuration (perfect time counts double)
	local greenT = 0
	local perfectT = 0
	local lastState = "neutral"
	local resolved = false
	local conn: RBXScriptConnection? = nil

	local function finish(success: boolean)
		if resolved then return end
		resolved = true
		if conn then conn:Disconnect(); conn = nil end
		-- Slide out, destroy after fade.
		local outTween = MotionUtil.tweenOrSnap(bar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = offPos,
		})
		if outTween then
			outTween.Completed:Connect(function() outTween:Destroy(); gui:Destroy() end)
		else
			task.delay(0.1, function() if gui then gui:Destroy() end end)
		end
		if success then
			local total = greenT + perfectT
			local frac = (total > 0) and (perfectT / total) or 0
			frac = math.clamp(frac, 0, 1)
			if handle.onSuccess then handle.onSuccess(frac) end
		else
			if handle.onEscape then handle.onEscape() end
		end
	end

	conn = RunService.Heartbeat:Connect(function()
		if resolved then return end
		local now = os.clock()
		local dt = now - lastFrameAt
		lastFrameAt = now

		-- Indicator velocity.
		if holding then
			indicatorPos = math.min(1, indicatorPos + holdSpeed * dt)
		else
			indicatorPos = math.max(0, indicatorPos - releaseSpeed * dt)
		end

		-- Zone center: sine wave around 0.5, amplitude ReelZoneSwingAmplitude.
		-- Clamp so the zone never clips off the bar edges.
		local t = now - startT
		local zoneCenter = 0.5 + FT.ReelZoneSwingAmplitude * math.sin(t * zoneOmega)
		local minZoneCenter = zoneWidth / 2
		local maxZoneCenter = 1 - zoneWidth / 2
		zoneCenter = math.clamp(zoneCenter, minZoneCenter, maxZoneCenter)

		zone.Position = UDim2.new(zoneCenter - zoneWidth / 2, 0, 0, 0)
		indicator.Position = UDim2.new(indicatorPos, 0, 0.5, 0)

		-- Zone hit-test.
		local zoneLow = zoneCenter - zoneWidth / 2
		local zoneHigh = zoneCenter + zoneWidth / 2
		local perfectLow = zoneCenter - perfectWidth / 2
		local perfectHigh = zoneCenter + perfectWidth / 2
		local inZone = indicatorPos >= zoneLow and indicatorPos <= zoneHigh
		local inPerfect = indicatorPos >= perfectLow and indicatorPos <= perfectHigh

		-- Progress accounting. Perfect zone double-counts.
		if inPerfect then
			progress += dt * FT.PerfectBonusMultiplier
			perfectT += dt
		elseif inZone then
			progress += dt
			greenT += dt
		end
		progressFill.Size = UDim2.new(math.min(1, progress / FT.ReelHoldDuration), 0, 1, 0)

		-- State transitions.
		local nextState
		if inZone then
			nextState = "tracking"
		elseif lastState == "tracking" then
			nextState = "losing"
		else
			nextState = "neutral"
		end
		if nextState ~= lastState then
			setState(nextState)
			lastState = nextState
			if handle and handle.onStateChanged then handle.onStateChanged(nextState) end
		end

		-- Win.
		if progress >= FT.ReelHoldDuration then
			finish(true)
			return
		end

		-- Lose: indicator hit the left edge while drifting (player isn't holding).
		if indicatorPos <= 0 and not holding then
			finish(false)
			return
		end
	end)

	handle = {
		gui = gui,
		setHolding = function(b)
			holding = b and true or false
		end,
		onSuccess = nil,
		onEscape = nil,
		onStateChanged = nil,
		stop = function()
			-- External cancel (e.g. cast resolved by timeout from server).
			-- Don't fire onSuccess / onEscape — caller decided how to handle.
			if resolved then return end
			resolved = true
			if conn then conn:Disconnect(); conn = nil end
			if gui then gui:Destroy() end
		end,
	}
	return handle
end

return CastMeter
