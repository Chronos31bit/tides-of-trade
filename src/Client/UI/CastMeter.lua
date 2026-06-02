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

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil     = require(script.Parent.UIUtil)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CastMeter = {}

local P  = UIUtil.Palette
local FT = GameConfig.Fishing.FeelTuning
local CM = GameConfig.Fishing.CastMeter

-- Resolve the reel-zone color for a given rarity string.
local function rarityColor(rarity: string): Color3
	return GameConfig.Fishing.RarityColors[rarity] or P.Uncommon
end

export type ShowOpts = {
}

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
	-- The 80px cast-button circle. FishingController wires .Activated to
	-- _releaseCastMarker as an alternative to the rod-tap path.
	castButton: Frame,
	-- Cast-phase release: stops the cast oscillation, returns (marker, isPerfect).
	-- isPerfect = marker was in the gold strip at release. Caller plays the ding.
	releaseCast: () -> (number, boolean),
	-- Begin reel mini-game. Tween cast visuals out and build reel visuals in.
	enterReel: (weightKg: number, tier: string, params: TierParams, rarity: string) -> (),
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

local function req(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if not c or not c:IsA(class) then
		error(`[CastMeter] Missing {class} "{name}" under {parent:GetFullName()}`, 2)
	end
	return c
end

function CastMeter.show(greenCenter: number, greenSize: number, period: number, opts: ShowOpts?): CastMeterHandle
	local gui = TemplateLoader.spawn("CastMeter", { instanceName = "CastMeter" })

	-- ----------------------------------------------------------------
	-- CAST BUTTON — 80px circle, bottom-center, above the nav bar.
	-- CastButtonBottomPx accounts for nav bar height (88) + gap (20) + clearance.
	-- Exposed in the handle so FishingController can wire Activated to
	-- _releaseCastMarker as an alternative to the rod-tap path.
	-- ----------------------------------------------------------------
	local castBtn = Instance.new("TextButton")
	castBtn.Name = "CastButton"
	castBtn.Text = ""
	castBtn.AutoButtonColor = false
	castBtn.AnchorPoint = Vector2.new(0.5, 1)
	castBtn.Position = UDim2.new(0.5, 0, 1, -CM.CastButtonBottomPx)
	castBtn.Size = UDim2.fromOffset(CM.CastButtonSizePx, CM.CastButtonSizePx)
	castBtn.BackgroundColor3 = P.TealDeeper
	castBtn.BorderSizePixel = 0
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(1, 0)
	btnCorner.Parent = castBtn
	local castLabel = Instance.new("TextLabel")
	castLabel.Name = "CastLabel"
	castLabel.BackgroundTransparency = 1
	castLabel.Size = UDim2.fromScale(1, 1)
	castLabel.Font = Enum.Font.GothamBold
	castLabel.TextSize = 16
	castLabel.TextColor3 = P.Cream
	castLabel.Text = "CAST"
	castLabel.TextXAlignment = Enum.TextXAlignment.Center
	castLabel.TextYAlignment = Enum.TextYAlignment.Center
	castLabel.Parent = castBtn
	castBtn.Parent = gui

	-- ----------------------------------------------------------------
	-- TRACK — template chrome. Script drives zone + indicator.
	-- ----------------------------------------------------------------
	local track = req(gui, "Track", "Frame") :: Frame
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(
		0.5,
		0,
		1,
		-(CM.CastButtonBottomPx + CM.CastButtonSizePx + CM.BarButtonGapPx)
	)
	local zoneCommon = req(track, "ZoneCommon", "Frame") :: Frame
	local zoneRare = req(track, "ZoneRare", "Frame") :: Frame
	local zoneLegendary = req(track, "ZoneLegendary", "Frame") :: Frame
	local indicator = req(track, "Indicator", "Frame") :: Frame
	local releaseHint = req(track, "ReleaseHintLabel", "TextLabel") :: TextLabel
	zoneCommon.Visible = true
	zoneRare.Visible = false
	zoneLegendary.Visible = false
	releaseHint.Visible = true

	-- "PERFECT!" flash — reused across both phases. Anchored above the bar.
	local flash = Instance.new("TextLabel")
	flash.Name = "PerfectFlash"
	flash.BackgroundTransparency = 1
	flash.AnchorPoint = Vector2.new(0.5, 1)
	-- Position flash just above the track top edge in screen coords.
	local flashRestY = -(CM.CastButtonBottomPx + CM.CastButtonSizePx + CM.BarButtonGapPx + CM.BarHeightPx + 12)
	flash.Position = UDim2.new(0.5, 0, 1, flashRestY)
	flash.Size = UDim2.fromOffset(220, 30)
	flash.Font = Enum.Font.GothamBlack
	flash.TextSize = 22
	flash.TextColor3 = P.Gold
	flash.TextTransparency = 1
	flash.Text = "PERFECT!"
	flash.Parent = gui
	flash.ZIndex = 10  -- above all track children

	local lastFlashAt = -math.huge
	local function flashPerfect()
		if MotionUtil.reducedMotionEnabled() then return end
		local now = os.clock()
		if now - lastFlashAt < 1.0 then return end
		lastFlashAt = now
		flash.TextTransparency = 0
		flash.Position = UDim2.new(0.5, 0, 1, flashRestY)
		MotionUtil.tween(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			Position = UDim2.new(0.5, 0, 1, flashRestY - 16),
		})
	end

	-- ================================================================
	-- PHASE 1 — CAST. Static green zone + sine marker.
	-- ================================================================
	-- Zone geometry: greenCenter/greenSize are 0..1 fractions where 0 is top and 1 is bottom.
	zoneCommon.Position = UDim2.new(0, 0, 1 - greenCenter - greenSize / 2, 0)
	zoneCommon.Size = UDim2.new(1, 0, greenSize, 0)
	zoneCommon.BackgroundColor3 = P.Uncommon  -- warm green zone (template default is gray)

	local castStart = os.clock()
	local lastMarker = 0.5
	local wasInCastGreen   = false
	local wasInCastPerfect = false
	local castConn: RBXScriptConnection? = nil
	castConn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - castStart
		local p = (math.sin(t / period * math.pi * 2) + 1) / 2
		lastMarker = p
		-- p=0 → bottom of bar (Y=1), p=1 → top of bar (Y=0).
		indicator.Position = UDim2.new(0.5, 0, 1 - p, 0)
		-- Zone hit-tests (same math as before — p and zone fractions are all 0..1).
		local gLow  = greenCenter - greenSize / 2
		local gHigh = greenCenter + greenSize / 2
		local pLow  = greenCenter - (greenSize * FT.PerfectZoneFraction) / 2
		local pHigh = greenCenter + (greenSize * FT.PerfectZoneFraction) / 2
		local inCastGreen   = p >= gLow  and p <= gHigh
		local inCastPerfect = p >= pLow  and p <= pHigh
		-- Marker warms while inside the zone; cream when outside (no red/green binary).
		if inCastGreen ~= wasInCastGreen then
			wasInCastGreen = inCastGreen
			MotionUtil.tweenOrSnap(indicator, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = inCastGreen and P.Sunset or P.Cream,
			})
		end
		-- Flash "PERFECT!" each time the marker sweeps into the gold inner strip.
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

	-- Reel-phase horizontal bar; nil until enterReel() runs.
	local reelBar: Frame? = nil
	local reelBarRestPos = UDim2.new(0.5, 0, 1, -CM.ReelBarBottomPx)
	local reelBarOffPos  = UDim2.new(0.5, 0, 1, -(CM.ReelBarBottomPx - 80))

	-- Forward-declare so closures can reference them.
	local enterReel: (weightKg: number, tier: string, params: TierParams, rarity: string) -> ()
	local stop: () -> ()

	local stopped = false
	stop = function()
		if stopped then return end
		stopped = true
		if castConn then castConn:Disconnect(); castConn = nil end
		if reelConn then reelConn:Disconnect(); reelConn = nil end
		-- Tween button and whichever bar is currently visible out, then destroy.
		MotionUtil.tweenOrSnap(castBtn, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 1, CM.CastButtonSizePx + 20),
		})
		local activeBar: Frame = if reelBar ~= nil then reelBar else track
		local activeOffPos = if reelBar ~= nil then reelBarOffPos else (track.Position + UDim2.fromOffset(0, CM.BarHeightPx + 20))
		local outTween = MotionUtil.tweenOrSnap(activeBar,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = activeOffPos })
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

	enterReel = function(weightKg: number, tier: string, params: TierParams, rarity: string)
		if reelStarted or stopped then return end
		reelStarted = true

		-- Disconnect the cast oscillation; the marker is now history.
		if castConn then castConn:Disconnect(); castConn = nil end

		-- Fade the cast button out — it's irrelevant during the reel mini-game.
		MotionUtil.tweenOrSnap(castBtn,
			TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})

		-- ---- transition: fade cast visuals, slide vertical bar out ----
		local fadeInfo = TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		MotionUtil.tweenOrSnap(indicator, fadeInfo, { BackgroundTransparency = 1 })
		MotionUtil.tweenOrSnap(zoneCommon, fadeInfo, { BackgroundTransparency = 1 })
		MotionUtil.tweenOrSnap(track,
			TweenInfo.new(FT.MeterTransitionDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = track.Position + UDim2.fromOffset(0, CM.BarHeightPx + 20) })

		-- ---- create horizontal reel bar ----
		local rb = UIUtil.makePanel({
			Name = "ReelBar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = reelBarOffPos,
			Size = UDim2.new(0.6, 0, 0, 28),
			BackgroundColor3 = P.WoodDark,
		})
		local rbMax = Instance.new("UISizeConstraint")
		rbMax.MaxSize = Vector2.new(540, 28)
		rbMax.Parent = rb
		rb.Parent = gui
		reelBar = rb
		MotionUtil.tweenOrSnap(rb, fadeInfo, { Position = reelBarRestPos })

		-- Rarity label: shown above the reel bar so the player sees what's on the line.
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "RarityLabel"
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.AnchorPoint = Vector2.new(0.5, 1)
		rarityLabel.Position = UDim2.new(0.5, 0, 0, -6)
		rarityLabel.Size = UDim2.fromOffset(220, 20)
		rarityLabel.Font = Enum.Font.GothamBold
		rarityLabel.TextSize = 14
		rarityLabel.TextColor3 = rarityColor(rarity)
		rarityLabel.Text = ("%s • %.1f kg"):format(rarity:upper(), weightKg)
		rarityLabel.Parent = rb

		-- "Bite!" flash: reel bar pulses rarity color to announce the phase change.
		if not MotionUtil.reducedMotionEnabled() then
			MotionUtil.tween(rb, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = rarityColor(rarity),
			})
			task.delay(0.12, function()
				if stopped then return end
				MotionUtil.tween(rb, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundColor3 = P.WoodDark,
				})
			end)
		end

		-- ---- reel: moving good zone (X-axis fractions work correctly in rb) ----
		local NEUTRAL_TRANSPARENCY = 0.3   -- dim when not tracking
		local zone = Instance.new("Frame")
		zone.Name = "ReelZone"
		zone.BackgroundColor3 = rarityColor(rarity)
		zone.BackgroundTransparency = 1    -- start invisible for fade-in
		zone.BorderSizePixel = 0
		zone.Position = UDim2.new(0.5 - params.zoneWidth / 2, 0, 0, 0)
		zone.Size = UDim2.new(params.zoneWidth, 0, 1, 0)
		local zc = Instance.new("UICorner"); zc.CornerRadius = UDim.new(0, 4); zc.Parent = zone
		zone.Parent = rb
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
		indicator.Position = UDim2.new(0.5, 0, 0.5, 0)
		indicator.Size = UDim2.new(0, 8, 1.6, 0)
		indicator.BackgroundColor3 = P.Cream
		indicator.BackgroundTransparency = 1
		indicator.BorderSizePixel = 0
		local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 3); ic.Parent = indicator
		indicator.Parent = rb
		MotionUtil.tweenOrSnap(indicator, fadeInfo, { BackgroundTransparency = 0 })

		-- ---- reel: hold-progress bar (mounted below the reel bar) ----
		local progressTrack = Instance.new("Frame")
		progressTrack.Name = "ReelProgressTrack"
		progressTrack.AnchorPoint = Vector2.new(0.5, 0)
		progressTrack.Position = UDim2.new(0.5, 0, 1, 8)
		progressTrack.Size = UDim2.new(1, 0, 0, 6)
		progressTrack.BackgroundColor3 = P.TealDeeper
		progressTrack.BorderSizePixel = 0
		local pt = Instance.new("UICorner"); pt.CornerRadius = UDim.new(0, 3); pt.Parent = progressTrack
		progressTrack.Parent = rb

		local progressFill = Instance.new("Frame")
		progressFill.Name = "Fill"
		progressFill.AnchorPoint = Vector2.new(0, 0.5)
		progressFill.Position = UDim2.new(0, 0, 0.5, 0)
		progressFill.Size = UDim2.new(0, 0, 1, 0)
		progressFill.BackgroundColor3 = rarityColor(rarity)
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
				-- Soft teal glow on the zone; warm indicator.
				MotionUtil.tweenOrSnap(zone, glowInfo, {
					BackgroundColor3 = P.TealLight,
					BackgroundTransparency = math.clamp(1 - params.glowAlpha, 0, 1),
				})
				MotionUtil.tweenOrSnap(indicator, glowInfo, { BackgroundColor3 = P.Sunset })
			elseif newState == "losing" then
				-- Warm amber cue on drift (no red flash); small UI shake on heavier fish.
				MotionUtil.tweenOrSnap(indicator, glowInfo, { BackgroundColor3 = P.SunsetSoft })
				if not MotionUtil.reducedMotionEnabled() and params.shakeOnLoss > 0 then
					local now = os.clock()
					if now - losingFlashAt > CM.LossFlashMinIntervalSec then
						losingFlashAt = now
						local origin = rb.Position
						local mag = math.floor(params.shakeOnLoss * 10 + 0.5)  -- studs → px
						rb.Position = origin + UDim2.fromOffset(math.random(-mag, mag), math.random(-mag, mag))
						MotionUtil.tween(rb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Position = origin,
						})
					end
				end
			else  -- neutral
				MotionUtil.tweenOrSnap(zone, glowInfo, {
					BackgroundColor3 = rarityColor(rarity),
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

			-- Perfect-strip glow + flash on zone edge transitions.
			if inPerfect ~= wasInPerfect then
				if inPerfect then
					flashPerfect()
					MotionUtil.tweenOrSnap(perfectStrip,
						TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ BackgroundTransparency = 0.0 })
				else
					MotionUtil.tweenOrSnap(perfectStrip,
						TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ BackgroundTransparency = 0.08 })
				end
			end
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
	-- Cast-phase release. Stop the oscillation, return (marker, isPerfect).
	-- isPerfect = marker was inside the gold strip at the moment of release.
	-- Visuals stay in place until enterReel() takes over or stop() destroys.
	-- ----------------------------------------------------------------
	local function releaseCast(): (number, boolean)
		if castConn then castConn:Disconnect(); castConn = nil end
		-- Dim the frozen marker: signals "locked in, waiting for the bite".
		MotionUtil.tweenOrSnap(indicator, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.5,
		})
		local pLow  = greenCenter - (greenSize * FT.PerfectZoneFraction) / 2
		local pHigh = greenCenter + (greenSize * FT.PerfectZoneFraction) / 2
		return lastMarker, lastMarker >= pLow and lastMarker <= pHigh
	end

	local function setHold(pressed: boolean)
		reelHeld = pressed
	end

	return {
		gui = gui,
		castButton = castBtn,
		releaseCast = releaseCast,
		enterReel = enterReel,
		setHold = setHold,
		stop = stop,
		onComplete = completeEvt.Event,
		onEscape = escapeEvt.Event,
	}
end

return CastMeter
