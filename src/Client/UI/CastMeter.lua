--!strict
-- CastMeter.lua
-- Two-phase timing UI for the fishing loop.
--
--   PHASE 1 — CAST (release-to-bite). A marker sine-oscillates 0..1 across
--             a fixed green zone (server-supplied center/size). On the
--             player's release, the marker is sent to the server.
--   PHASE 2 — REEL (hold-to-track). After the server confirms a bite, the
--             meter transitions: cast visuals fade out and the reel UI
--             fades in. A *moving* good-zone oscillates on a sine; an
--             indicator driven by the player's hold input chases it. Time
--             spent inside the zone fills a hold-progress bar. Inside the
--             inner 25% perfect zone, hold-progress fills 2×. When the bar
--             fills, .onComplete fires with the perfect-zone fraction. If
--             the indicator hits the left edge while drifting back, .onEscape
--             fires (the fish slipped off).
--
-- Reduced motion:
--   * Cast-phase slide-in: replaced by snap.
--   * Reel-phase transition fade: replaced by snap.
--   * Perfect flash and zone-loss shake: skipped.
--   * The mini-games still run — only the decoration is muted.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local UIUtil     = require(script.Parent.UIUtil)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CastMeter = {}

local P  = UIUtil.Palette
local FT = GameConfig.Fishing.FeelTuning

export type TierParams = {
	zoneWidth:    number,   -- 0..1 width of the moving good zone
	oscSpeedMul:  number,   -- multiplier on the zone oscillation speed
	driftSpeed:   number,   -- /sec indicator decay when not held
	holdSpeed:    number,   -- /sec indicator gain while held
	shakeOnLoss:  number,   -- studs of UI shake when zone is lost (0 = none)
	glowAlpha:    number,   -- background transparency of the tracking glow
}

export type CastMeterHandle = {
	gui: ScreenGui,
	-- Cast-phase release: stops the cast oscillation, returns latest marker.
	-- The caller forwards the marker to FishingService:ClaimCast.
	releaseCast: () -> number,
	-- Begin reel mini-game. Tween cast visuals out and build reel visuals in.
	enterReel: (weightKg: number, tier: string, params: TierParams) -> (),
	-- Drive the reel indicator. Caller wires this to InputBegan/InputEnded.
	setHold: (pressed: boolean) -> (),
	-- Destroy everything immediately (used on cast resolve).
	stop: () -> (),
	-- Fires with (perfectFraction) when the hold bar fills.
	onComplete: RBXScriptSignal,
	-- Fires when the indicator hits the left edge while drifting back.
	onEscape: RBXScriptSignal,
}

-- Helper: derive zone-oscillation period (seconds) from weight + tier.
local function reelPeriod(weightKg: number, params: TierParams): number
	local speed = FT.ReelZoneSpeedBase + FT.ReelZoneSpeedPerKg * weightKg
	if speed <= 0 then speed = FT.ReelZoneSpeedBase end
	return math.clamp(2.5 / speed / params.oscSpeedMul, 0.4, 4.0)
end

function CastMeter.show(greenCenter: number, greenSize: number, period: number): CastMeterHandle
	local gui = UIUtil.makeScreenGui("CastMeter")

	-- ----------------------------------------------------------------
	-- BAR — anchored at lower-third, slides in from below.
	-- ----------------------------------------------------------------
	local restPos = UDim2.new(0.5, 0, 0.66, 0)
	local offPos  = UDim2.new(0.5, 0, 0.66, 80)

	local bar = UIUtil.makePanel({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = offPos,
		Size = UDim2.new(0.6, 0, 0, 28),
		BackgroundColor3 = P.WoodDark,
	})
	local barMax = Instance.new("UISizeConstraint"); barMax.MaxSize = Vector2.new(540, 28); barMax.Parent = bar
	bar.Parent = gui

	-- Slide in (snap if reduced motion).
	MotionUtil.tweenOrSnap(bar, TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = restPos,
	})

	-- "PERFECT!" flash — reused across both phases. Anchored above the bar.
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
	local function flashPerfect()
		if MotionUtil.reducedMotionEnabled() then return end
		local now = os.clock()
		if now - lastFlashAt < 1.0 then return end
		lastFlashAt = now
		flash.TextTransparency = 0
		flash.Position = UDim2.new(0.5, 0, 0, -12)
		MotionUtil.tween(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, -28),
		})
	end

	-- ================================================================
	-- PHASE 1 — CAST. Static green zone + sine marker.
	-- ================================================================
	local castFolder = Instance.new("Folder"); castFolder.Name = "CastPhase"; castFolder.Parent = bar

	local castGreen = Instance.new("Frame")
	castGreen.Name = "Green"
	castGreen.BackgroundColor3 = P.Uncommon
	castGreen.BackgroundTransparency = 0.1
	castGreen.BorderSizePixel = 0
	castGreen.Position = UDim2.new(greenCenter - greenSize / 2, 0, 0, 0)
	castGreen.Size = UDim2.new(greenSize, 0, 1, 0)
	local cgc = Instance.new("UICorner"); cgc.CornerRadius = UDim.new(0, 4); cgc.Parent = castGreen
	castGreen.Parent = castFolder

	-- Inner gold perfect strip — sweet-spot within the green zone.
	local cpFrac = FT.PerfectZoneFraction
	local castPerfect = Instance.new("Frame")
	castPerfect.Name = "CastPerfect"
	castPerfect.BackgroundColor3 = P.Gold
	castPerfect.BackgroundTransparency = 0.15
	castPerfect.BorderSizePixel = 0
	castPerfect.Position = UDim2.new((1 - cpFrac) / 2, 0, 0, 0)
	castPerfect.Size = UDim2.new(cpFrac, 0, 1, 0)
	local cpc = Instance.new("UICorner"); cpc.CornerRadius = UDim.new(0, 3); cpc.Parent = castPerfect
	castPerfect.Parent = castGreen

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.new(0, 0, 0.5, 0)
	marker.Size = UDim2.new(0, 6, 1.5, 0)
	marker.BackgroundColor3 = P.Cream
	marker.BorderSizePixel = 0
	local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 2); mc.Parent = marker
	marker.Parent = castFolder

	local castStart = os.clock()
	local lastMarker = 0.5
	local wasInCastPerfect = false
	local castConn: RBXScriptConnection? = nil
	castConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - castStart
		local p = (math.sin(t / period * math.pi * 2) + 1) / 2
		lastMarker = p
		marker.Position = UDim2.new(p, 0, 0.5, 0)
		-- Flash "PERFECT!" each time the marker sweeps into the gold inner strip.
		local pLow  = greenCenter - (greenSize * FT.PerfectZoneFraction) / 2
		local pHigh = greenCenter + (greenSize * FT.PerfectZoneFraction) / 2
		local inCastPerfect = p >= pLow and p <= pHigh
		if inCastPerfect and not wasInCastPerfect then flashPerfect() end
		wasInCastPerfect = inCastPerfect
	end)

	-- ================================================================
	-- PHASE 2 — REEL. State held in upvalues; UI built lazily on enterReel.
	-- ================================================================
	local reelStarted = false
	local reelConn: RBXScriptConnection? = nil
	local reelHeld = false

	-- Bindable signals for the controller.
	local completeEvt = Instance.new("BindableEvent")
	local escapeEvt = Instance.new("BindableEvent")

	-- Forward-declare so closures can reference them.
	local enterReel: (weightKg: number, tier: string, params: TierParams) -> ()
	local stop: () -> ()

	local stopped = false
	stop = function()
		if stopped then return end
		stopped = true
		if castConn then castConn:Disconnect(); castConn = nil end
		if reelConn then reelConn:Disconnect(); reelConn = nil end
		-- Tween bar out, then destroy. The completeEvt/escapeEvt go with it.
		local outTween = MotionUtil.tweenOrSnap(bar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = offPos,
		})
		if outTween then
			outTween.Completed:Connect(function()
				outTween:Destroy()
				gui:Destroy()
				completeEvt:Destroy(); escapeEvt:Destroy()
			end)
		else
			task.delay(0.1, function()
				gui:Destroy()
				completeEvt:Destroy(); escapeEvt:Destroy()
			end)
		end
	end

	enterReel = function(weightKg: number, tier: string, params: TierParams)
		if reelStarted or stopped then return end
		reelStarted = true

		-- Disconnect the cast oscillation; the marker is now history.
		if castConn then castConn:Disconnect(); castConn = nil end

		-- ---- transition: fade cast visuals, build reel visuals ----
		local fadeInfo = TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		MotionUtil.tweenOrSnap(marker, fadeInfo, { BackgroundTransparency = 1 })
		MotionUtil.tweenOrSnap(castGreen, fadeInfo, { BackgroundTransparency = 1 })

		-- ---- reel: moving good zone ----
		local NEUTRAL_TRANSPARENCY = 0.3   -- dim when not tracking
		local zone = Instance.new("Frame")
		zone.Name = "ReelZone"
		zone.BackgroundColor3 = P.Uncommon
		zone.BackgroundTransparency = 1    -- start invisible for fade-in
		zone.BorderSizePixel = 0
		zone.Position = UDim2.new(0.5 - params.zoneWidth / 2, 0, 0, 0)
		zone.Size = UDim2.new(params.zoneWidth, 0, 1, 0)
		local zc = Instance.new("UICorner"); zc.CornerRadius = UDim.new(0, 4); zc.Parent = zone
		zone.Parent = bar
		MotionUtil.tweenOrSnap(zone, fadeInfo, { BackgroundTransparency = NEUTRAL_TRANSPARENCY })

		-- Inner perfect strip — 25% of zone width, centered.
		local perfectStrip = Instance.new("Frame")
		perfectStrip.Name = "ReelPerfect"
		perfectStrip.BackgroundColor3 = P.Gold
		perfectStrip.BackgroundTransparency = 1
		perfectStrip.BorderSizePixel = 0
		local pWidth = params.zoneWidth * FT.PerfectZoneFraction
		perfectStrip.Position = UDim2.new(0.5 - pWidth / 2, 0, 0, 0)
		perfectStrip.Size = UDim2.new(pWidth, 0, 1, 0)
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 4); pc.Parent = perfectStrip
		perfectStrip.Parent = zone
		MotionUtil.tweenOrSnap(perfectStrip, fadeInfo, { BackgroundTransparency = 0.08 })

		-- ---- reel: indicator (player-controlled) ----
		local indicator = Instance.new("Frame")
		indicator.Name = "ReelIndicator"
		indicator.AnchorPoint = Vector2.new(0.5, 0.5)
		indicator.Position = UDim2.new(0.5, 0, 0.5, 0)  -- starts at centre, matches indicatorPos
		indicator.Size = UDim2.new(0, 8, 1.6, 0)
		indicator.BackgroundColor3 = P.Cream
		indicator.BackgroundTransparency = 1
		indicator.BorderSizePixel = 0
		local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 3); ic.Parent = indicator
		indicator.Parent = bar
		MotionUtil.tweenOrSnap(indicator, fadeInfo, { BackgroundTransparency = 0 })

		-- ---- reel: hold-progress bar (mounted below the main bar) ----
		local progressTrack = Instance.new("Frame")
		progressTrack.Name = "ReelProgressTrack"
		progressTrack.AnchorPoint = Vector2.new(0.5, 0)
		progressTrack.Position = UDim2.new(0.5, 0, 1, 8)
		progressTrack.Size = UDim2.new(1, 0, 0, 6)
		progressTrack.BackgroundColor3 = P.TealDeeper
		progressTrack.BorderSizePixel = 0
		local pt = Instance.new("UICorner"); pt.CornerRadius = UDim.new(0, 3); pt.Parent = progressTrack
		progressTrack.Parent = bar

		local progressFill = Instance.new("Frame")
		progressFill.Name = "Fill"
		progressFill.AnchorPoint = Vector2.new(0, 0.5)
		progressFill.Position = UDim2.new(0, 0, 0.5, 0)
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = P.Success
		progressFill.BorderSizePixel = 0
		local pf = Instance.new("UICorner"); pf.CornerRadius = UDim.new(0, 3); pf.Parent = progressFill
		progressFill.Parent = progressTrack

		-- ---- reel state ----
		local reelStart = os.clock()
		local lastFrameAt = reelStart
		local indicatorPos = 0.5       -- physics position 0..1
		local displayPos   = 0.5       -- smoothed visual position (spring-follows indicatorPos)
		local prevHeld     = false     -- detects hold press/release for squeeze animation
		local holdTime = 0.0           -- accumulated time in zone (perfect = 2×)
		local perfectTime = 0.0        -- raw seconds spent inside the perfect strip
		local totalTrackingTime = 0.0  -- raw seconds spent inside the zone
		local lastState = "neutral"    -- "neutral" | "tracking" | "losing"
		local losingFlashAt = -math.huge
		local wasInPerfect = false
		local fired = false            -- guard against double-firing complete/escape

		local period_s = reelPeriod(weightKg, params)
		-- Zone center oscillation: snap into [zoneWidth/2, 1-zoneWidth/2] so the
		-- zone never clips the bar edge.
		local centerLow  = params.zoneWidth / 2
		local centerHigh = 1 - params.zoneWidth / 2

		local function setState(newState: string)
			if newState == lastState then return end
			lastState = newState
			local glowInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			if newState == "tracking" then
				-- Bright soft green glow on the zone; cream indicator.
				MotionUtil.tweenOrSnap(zone, glowInfo, {
					BackgroundColor3 = P.Success,
					BackgroundTransparency = math.clamp(1 - params.glowAlpha, 0, 1),
				})
				MotionUtil.tweenOrSnap(indicator, glowInfo, { BackgroundColor3 = P.Cream })
			elseif newState == "losing" then
				-- Red flash on the indicator; small UI shake on heavier fish.
				MotionUtil.tweenOrSnap(indicator, glowInfo, { BackgroundColor3 = P.Danger })
				if not MotionUtil.reducedMotionEnabled() and params.shakeOnLoss > 0 then
					local now = os.clock()
					if now - losingFlashAt > 0.25 then
						losingFlashAt = now
						local origin = bar.Position
						local mag = math.floor(params.shakeOnLoss * 10 + 0.5)  -- studs → px
						bar.Position = origin + UDim2.fromOffset(math.random(-mag, mag), math.random(-mag, mag))
						MotionUtil.tween(bar, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Position = origin,
						})
					end
				end
			else  -- neutral
				MotionUtil.tweenOrSnap(zone, glowInfo, {
					BackgroundColor3 = P.Uncommon,
					BackgroundTransparency = NEUTRAL_TRANSPARENCY,
				})
				MotionUtil.tweenOrSnap(indicator, glowInfo, { BackgroundColor3 = P.Cream })
			end
		end

		local function fireComplete()
			if fired then return end; fired = true
			local frac = (totalTrackingTime > 0) and (perfectTime / totalTrackingTime) or 0
			completeEvt:Fire(math.clamp(frac, 0, 1))
		end
		local function fireEscape()
			if fired then return end; fired = true
			escapeEvt:Fire()
		end

		reelConn = RunService.Heartbeat:Connect(function()
			if fired or stopped then return end
			local now = os.clock()
			local dt = now - lastFrameAt
			lastFrameAt = now

			-- Indicator velocity. Held → toward 1, released → toward 0.
			if reelHeld then
				indicatorPos += params.holdSpeed * dt
			else
				indicatorPos -= params.driftSpeed * dt
			end

			-- Edge: drifted off the left while not held → escape.
			if indicatorPos <= 0 then
				indicatorPos = 0
				if not reelHeld then
					fireEscape()
					return
				end
			end
			if indicatorPos >= 1 then indicatorPos = 1 end

			-- Spring-follow: smooth visual so movement feels weighted, not snappy.
			displayPos = displayPos + (indicatorPos - displayPos) * math.min(1, dt * 18)
			indicator.Position = UDim2.new(displayPos, 0, 0.5, 0)

			-- Hold squeeze: indicator widens on press, shrinks on release.
			if reelHeld ~= prevHeld then
				prevHeld = reelHeld
				if not MotionUtil.reducedMotionEnabled() then
					local w = reelHeld and 11 or 8
					local h = reelHeld and 1.9 or 1.6
					MotionUtil.tween(indicator, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Size = UDim2.new(0, w, h, 0),
					})
				end
			end

			-- Zone center oscillation (sine, clamped to keep the zone on-bar).
			local t = now - reelStart
			local raw = 0.5 + 0.5 * math.sin(t / period_s * math.pi * 2)
			local zoneCenter = centerLow + (centerHigh - centerLow) * raw
			zone.Position = UDim2.new(zoneCenter - params.zoneWidth / 2, 0, 0, 0)

			-- Tracking & perfect accounting.
			local zLow  = zoneCenter - params.zoneWidth / 2
			local zHigh = zoneCenter + params.zoneWidth / 2
			local pLow  = zoneCenter - (params.zoneWidth * FT.PerfectZoneFraction) / 2
			local pHigh = zoneCenter + (params.zoneWidth * FT.PerfectZoneFraction) / 2

			local inZone = indicatorPos >= zLow and indicatorPos <= zHigh
			local inPerfect = indicatorPos >= pLow and indicatorPos <= pHigh

			if inZone then
				totalTrackingTime += dt
				-- Time in perfect zone counts 2× toward the hold goal.
				if inPerfect then
					perfectTime += dt
					holdTime += dt * FT.PerfectBonusMultiplier
				else
					holdTime += dt
				end
				setState("tracking")
			else
				-- Danger: show red warning when close to escaping regardless of prior state.
				if indicatorPos < 0.15 or lastState == "tracking" then
					setState("losing")
				else
					setState("neutral")
				end
			end

			-- Perfect-flash edge trigger.
			if inPerfect and not wasInPerfect then flashPerfect() end
			wasInPerfect = inPerfect

			-- Hold-progress fill.
			local pct = math.clamp(holdTime / FT.ReelHoldDuration, 0, 1)
			progressFill.Size = UDim2.new(pct, 0, 1, 0)

			if holdTime >= FT.ReelHoldDuration then
				fireComplete()
			end
		end)
	end

	-- ----------------------------------------------------------------
	-- Cast-phase release. Stop the oscillation, return latest marker. The
	-- visuals stay in place until enterReel() takes over or stop() destroys.
	-- ----------------------------------------------------------------
	local function releaseCast(): number
		if castConn then castConn:Disconnect(); castConn = nil end
		return lastMarker
	end

	local function setHold(pressed: boolean)
		reelHeld = pressed
	end

	return {
		gui = gui,
		releaseCast = releaseCast,
		enterReel = enterReel,
		setHold = setHold,
		stop = stop,
		onComplete = completeEvt.Event,
		onEscape = escapeEvt.Event,
	}
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
