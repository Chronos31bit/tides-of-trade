--!strict
-- FishingController.lua
-- Owns the cast lifecycle on the client. The full 30-second loop:
--   1. Player taps Rod (Tool.Activated → RodService.RodActivated).
--   2. Server picks a fish, rolls its weight, returns a timing window.
--   3. Cast feedback fires: camera shake, ripples at the cast point,
--      a Beam from rod tip to water, haptic pulse, splash audio (TODO).
--   4. CastMeter shows; player releases at the right moment. Marker → server.
--   5. Server confirms hit/miss:
--        miss → CastResolved(missed); meter dismissed.
--        hit  → BiteStarted(weight, tier, difficulty) → meter transitions
--               to the reel mini-game. Player hold-tracks the moving zone.
--   6. On reel complete → ReleaseReel(perfectFraction).
--      On reel escape   → ReportEscape().
--   7. Server fires CastResolved with the final result; CatchRevealUI shows.
--
-- Architecture:
--   * Server-authoritative end-to-end. Client only ever sends a marker (cast
--     timing) and a perfectFraction (reel). It never picks a species, weight,
--     or perfect-bonus eligibility.
--   * All decoration motion goes through MotionUtil (reduced-motion aware).
--   * Trove owns per-cast disposables (Beams, attachments, ripples, tweens,
--     input connections, rumble loops). Cleared on cast resolve so back-to-
--     back casts don't leak.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local HapticService     = game:GetService("HapticService")
local RunService        = game:GetService("RunService")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local CatchRevealUI = require(script.Parent.Parent.UI.CatchRevealUI)
local AssetIds   = require(script.Parent.Parent.AssetIds)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local UIUtil     = require(script.Parent.Parent.UI.UIUtil)

local FT = GameConfig.Fishing.FeelTuning

-- ====================================================================
-- TENSION TIERS — all client-side feel parameters that scale with the
-- caught fish's weight. Server provides the tier label ("light"|"medium"|
-- "heavy"|"legendary") in BiteStarted; we pick the row here. Anything you
-- want to retune for fish-fight feel lives in this table.
-- ====================================================================
local TENSION_TIERS: {[string]: any} = {
	light = {
		zoneWidth   = 0.30,
		oscSpeedMul = 0.80,
		driftSpeed  = 0.55,
		holdSpeed   = 0.65,
		shakeOnLoss = 0.0,
		glowAlpha   = 0.85,
		rumble      = 0.10,  -- continuous gamepad rumble during fight
	},
	medium = {
		zoneWidth   = 0.22,
		oscSpeedMul = 1.05,
		driftSpeed  = 0.75,
		holdSpeed   = 0.65,
		shakeOnLoss = 0.0,
		glowAlpha   = 0.85,
		rumble      = 0.20,
	},
	heavy = {
		zoneWidth   = 0.16,
		oscSpeedMul = 1.60,
		driftSpeed  = 1.00,
		holdSpeed   = 0.70,
		shakeOnLoss = 0.18,
		glowAlpha   = 0.70,
		rumble      = 0.35,
	},
	legendary = {
		zoneWidth   = 0.12,
		oscSpeedMul = 2.20,
		driftSpeed  = 1.35,
		holdSpeed   = 0.75,
		shakeOnLoss = 0.28,
		glowAlpha   = 0.55,
		rumble      = 0.55,
	},
}

local FishingController = Knit.CreateController({
	Name = "FishingController",
	_trove          = nil :: any,    -- controller-lifetime cleanup (KnitInit → KnitStop)
	_pendingCastId  = nil :: string?,
	_phase          = "idle",        -- "idle" | "casting" | "reeling"
	_castMeterCtrl  = nil :: any,    -- CastMeterController reference, set in KnitStart
	_soundCtrl      = nil :: any,    -- SoundController reference, set in KnitStart
	_castTrove      = nil :: any,    -- disposables for the *current* cast
	_castButton     = nil :: any,    -- cast button GuiObject; stored so _onBite can pulse it
	_worldModLookup = nil :: any,    -- {[string]: ModifierDef} world-state modifiers only
	_conditionsPill = nil :: any,    -- Frame shown above cast button during active cast
	_weatherState   = "Clear",       -- cached weather for modifier computation
	_tideState      = "Low",         -- cached tide state
	_timeOfDay      = "Day",         -- cached time of day
})

-- ====================================================================
-- HAPTICS — gamepad motors only. pcall-wrapped; SetMotor throws on
-- unsupported devices.
-- ====================================================================
local function pulseHaptic()
	pcall(function()
		if UserInputService.GamepadEnabled then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, FT.HapticIntensity)
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, FT.HapticIntensity * 0.5)
			task.delay(FT.HapticDuration, function()
				pcall(function()
					HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
					HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
				end)
			end)
		end
	end)
end

-- Continuous low-frequency rumble during the reel fight. `stopFn` is wired
-- into the cast trove so disposal always kills the motor.
local function startRumble(intensity: number): () -> ()
	if not UserInputService.GamepadEnabled then
		return function() end
	end
	local active = true
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, intensity)
	end)
	return function()
		if not active then return end
		active = false
		pcall(function()
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
		end)
	end
end

-- ====================================================================
-- CAMERA SHAKE — one-shot offset on the active camera. Reduced motion: skip.
-- ====================================================================
local function shakeCamera()
	if MotionUtil.reducedMotionEnabled() then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local startT = os.clock()
	local bindName = "TidesFishingCastShake"
	pcall(function() RunService:UnbindFromRenderStep(bindName) end)
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local t = (os.clock() - startT) / FT.CastShakeDuration
		if t >= 1 then
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local decay = (1 - t) * (1 - t)
		local m = FT.CastShakeMagnitude * decay
		local offset = Vector3.new((math.random() - 0.5) * 2 * m, (math.random() - 0.5) * 2 * m, (math.random() - 0.5) * 2 * m)
		cam.CFrame = cam.CFrame * CFrame.new(offset)
	end)
end

-- ====================================================================
-- CAST POINT — world position where the line lands, or nil if the
-- cursor is not aimed at terrain water.
-- ====================================================================
local function inferCastPoint(): Vector3?
	local mouse = Players.LocalPlayer:GetMouse()
	if not mouse then return nil end

	-- mouse.UnitRay is the camera→cursor ray in world space, already
	-- accounting for the GUI inset (unlike ViewportPointToRay which uses
	-- full-viewport coords that don't match mouse.X / mouse.Y).
	-- Filter to Terrain only so player parts, harbor buildings, etc.
	-- don't block a click that's visually over the sea.
	local unitRay = mouse.UnitRay
	local params  = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 2000, params)

	if not result or result.Material ~= Enum.Material.Water then
		return nil  -- cursor is over land, a building, the sky, etc.
	end
	return Vector3.new(result.Position.X, 0, result.Position.Z)
end

-- ====================================================================
-- RIPPLE — geometric fallback (Cylinder Parts at water surface).
-- ====================================================================
local function spawnRipple(position: Vector3, trove: any)
	local reduced = MotionUtil.reducedMotionEnabled()
	for i = 1, FT.RippleCount do
		local part = Instance.new("Part")
		part.Name = "CastRipple"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
		part.Color = FT.RippleColor
		local cf = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		part.CFrame = cf
		if reduced then
			part.Size = Vector3.new(0.1, FT.RippleMaxRadius * 2, FT.RippleMaxRadius * 2)
			part.Transparency = 0.4
		else
			part.Size = Vector3.new(0.1, 0.5, 0.5)
			part.Transparency = 0.2
		end
		part.Parent = Workspace
		trove:Add(part)

		local delay = (i - 1) * 0.12

		task.delay(delay, function()
			if not part.Parent then return end
			local targetSize = Vector3.new(0.1, FT.RippleMaxRadius * 2, FT.RippleMaxRadius * 2)
			local info = TweenInfo.new(FT.RippleDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			local fadeInfo = TweenInfo.new(FT.RippleDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
			if not reduced then
				local sizeTween = MotionUtil.tween(part, info, { Size = targetSize })
				trove:Add(function() if sizeTween then sizeTween:Destroy() end end)
			end
			local fadeTween = MotionUtil.tween(part, fadeInfo, { Transparency = 1 })
			fadeTween.Completed:Connect(function()
				fadeTween:Destroy()
				if part.Parent then part:Destroy() end
			end)
		end)
	end
end

-- ====================================================================
-- LINE BEAM — rod tip → cast point. Sags initially, snaps taut on bite.
-- The snap-taut tween is triggered when the meter transitions to reel
-- phase (handled inline in _onBite).
-- ====================================================================
local function spawnBeam(castPoint: Vector3, trove: any): Beam?
	local char = Players.LocalPlayer.Character; if not char then return nil end
	local rod = char:FindFirstChild("Fishing Rod"); if not rod or not rod:IsA("Tool") then return nil end
	local handle = rod:FindFirstChild("Handle"); if not handle or not handle:IsA("BasePart") then return nil end

	local source = handle:FindFirstChild("LineEnd") :: Attachment?
	if not source then
		source = Instance.new("Attachment")
		source.Name = "LineEnd"
		source.Position = Vector3.new(0, 0, -((handle.Size.Z / 2) + 1.5))
		source.Parent = handle
	end

	local anchor = Instance.new("Part")
	anchor.Name = "CastAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(castPoint)
	anchor.Parent = Workspace
	trove:Add(anchor)

	local target = Instance.new("Attachment")
	target.Parent = anchor

	local beam = Instance.new("Beam")
	beam.Attachment0 = source
	beam.Attachment1 = target
	beam.Width0 = 0.04
	beam.Width1 = 0.04
	beam.FaceCamera = true
	beam.CurveSize0 = 2
	beam.CurveSize1 = -2
	beam.Color = ColorSequence.new(FT.BeamColor)
	beam.Texture = AssetIds.Images.BeamTexture
	beam.TextureSpeed = 0
	beam.Parent = anchor
	trove:Add(beam)
	return beam
end

-- Snap the beam taut. Caller passes the Beam returned from spawnBeam.
local function snapBeamTaut(beam: Beam?)
	if not beam or not beam.Parent then return end
	local info = MotionUtil.reducedMotionEnabled()
		and TweenInfo.new(0)
		or TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t1 = MotionUtil.tween(beam, info, { CurveSize0 = 0 })
	local t2 = MotionUtil.tween(beam, info, { CurveSize1 = 0 })
	t1.Completed:Connect(function() t1:Destroy() end)
	t2.Completed:Connect(function() t2:Destroy() end)
end

-- ====================================================================
-- BITE FEEDBACK — camera nudge, button pulse, vignette flash
-- ====================================================================

-- Forward camera nudge: sin-arc offset applied post-camera via BindToRenderStep.
-- TweenService:Create on camera.CFrame is overridden every frame by Roblox's
-- camera system; BindToRenderStep at Camera+1 runs after it, so the offset sticks.
-- Skip under ReducedMotion. `trove` unbinds early if cast disposes mid-nudge.
local function nudgeCamera(trove: any?)
	if MotionUtil.reducedMotionEnabled() then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local cfg = GameConfig.FishBite
	local startT = os.clock()
	local DURATION = cfg.CameraNudgeDuration
	local MAGNITUDE = cfg.CameraNudgeMagnitude
	local bindName = "TidesFishingBiteNudge"
	local function unbind()
		pcall(function() RunService:UnbindFromRenderStep(bindName) end)
	end
	unbind()
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local t = (os.clock() - startT) / DURATION
		if t >= 1 then
			unbind()
			return
		end
		local offset = math.sin(t * math.pi) * MAGNITUDE
		cam.CFrame = cam.CFrame * CFrame.new(0, 0, -offset)
	end)
	if trove then
		trove:Add(unbind)
	end
end

-- Scale the cast button 1.0 → scale → 1.0. Skip under ReducedMotion.
local function pulseCastButton(button: GuiObject?, trove: any?)
	if MotionUtil.reducedMotionEnabled() then return end
	if not button or not button.Parent then return end
	local scale = GameConfig.FishBite.ButtonPulseScale
	local orig = button.Size
	local big  = UDim2.new(
		orig.X.Scale * scale, math.round(orig.X.Offset * scale),
		orig.Y.Scale * scale, math.round(orig.Y.Offset * scale)
	)
	local info = TweenInfo.new(GameConfig.FishBite.ButtonPulseDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t1 = MotionUtil.tween(button, info, { Size = big })
	local conn1 = t1.Completed:Connect(function()
		t1:Destroy()
		if not button.Parent then return end
		local t2 = MotionUtil.tween(button, info, { Size = orig })
		local conn2 = t2.Completed:Connect(function() t2:Destroy() end)
		if trove then trove:Add(conn2) end
	end)
	if trove then
		trove:Add(conn1)
		trove:Add(function()
			t1:Cancel()
			if button.Parent then button.Size = orig end
		end)
	end
end

-- Four-edge vignette: each screen edge gets a panel with a UIGradient fading
-- toward the center. All panels fade out together over 0.3s (one direction
-- only — satisfies ≤3 flips/sec rule). Using edge panels rather than a full-
-- screen overlay avoids center-of-screen colour contamination on bright days.
local function flashVignette(trove: any?)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local cfg = GameConfig.FishBite
	local edgeTransparency = 1 - cfg.VignetteAlpha
	local sg = Instance.new("ScreenGui")
	sg.Name           = "BiteVignette"
	sg.ResetOnSpawn   = false
	sg.DisplayOrder   = 10
	sg.IgnoreGuiInset = true
	sg.Parent         = playerGui

	-- { size, position, gradient rotation (degrees): 0=top→down, 180=bottom→up }
	local EDGES = {
		{ UDim2.new(1, 0, 0.28, 0), UDim2.new(0, 0, 0, 0),    0   },  -- top
		{ UDim2.new(1, 0, 0.28, 0), UDim2.new(0, 0, 0.72, 0), 180 },  -- bottom
		{ UDim2.new(0.18, 0, 1, 0), UDim2.new(0, 0, 0, 0),    270 },  -- left
		{ UDim2.new(0.18, 0, 1, 0), UDim2.new(0.82, 0, 0, 0), 90  },  -- right
	}

	local COLOR = FT.VignetteColor
	local FADE  = TweenInfo.new(cfg.VignetteFadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local frames: {Frame} = {}

	for _, e in ipairs(EDGES) do
		local f = Instance.new("Frame")
		f.Size                   = e[1]
		f.Position               = e[2]
		f.BackgroundColor3       = COLOR
		f.BackgroundTransparency = edgeTransparency
		f.BorderSizePixel        = 0
		f.Parent                 = sg

		local grad = Instance.new("UIGradient")
		grad.Rotation    = e[3]
		grad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),   -- opaque at screen edge
			NumberSequenceKeypoint.new(1, 1),   -- transparent toward screen center
		})
		grad.Parent = f
		table.insert(frames, f)
	end

	-- Tween all panels to fully transparent simultaneously.
	local lastTween: Tween? = nil
	for _, f in ipairs(frames) do
		local tw = MotionUtil.tween(f, FADE, { BackgroundTransparency = 1 })
		lastTween = tw
	end
	local function destroyVignette()
		if sg.Parent then sg:Destroy() end
	end
	if trove then
		trove:Add(destroyVignette)
	end
	if lastTween then
		local conn = lastTween.Completed:Connect(function()
			lastTween:Destroy()
			destroyVignette()
		end)
		if trove then trove:Add(conn) end
	else
		task.delay(cfg.VignetteFadeDuration + 0.05, destroyVignette)
	end
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function FishingController:KnitInit()
	self._trove = Trove.new()
end

function FishingController:KnitStop()
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
end

function FishingController:KnitStart()
	local FishingService = Knit.GetService("FishingService")
	local RodService     = Knit.GetService("RodService")
	self._castMeterCtrl  = Knit.GetController("CastMeterController")
	self._soundCtrl      = Knit.GetController("SoundController")
	self._notifCtrl      = Knit.GetController("NotificationController")

	-- Authoritative end-of-cast result (miss, escape, or success).
	self._trove:Add(FishingService.CastResolved:Connect(function(result)
		self:_onResolved(result)
	end))

	-- Bite — server validated the cast marker and now wants the reel.
	self._trove:Add(FishingService.BiteStarted:Connect(function(payload)
		self:_onBite(payload)
	end))

	-- Tool.Activated. Single entry point for first tap (cast) and second tap
	-- (release-cast-meter). Ignored during the reel phase (which is hold-driven).
	self._trove:Add(RodService.RodActivated:Connect(function()
		self:_onRodTap()
	end))

	-- Reel-phase signals wired once at controller lifetime. They fire only while
	-- a cast is active; idle fires are impossible (CastMeterController guards them).
	self._trove:Add(self._castMeterCtrl.ReelComplete:Connect(function(pf: number)
		self:_releaseReel(pf)
	end))
	self._trove:Add(self._castMeterCtrl.ReelEscaped:Connect(function()
		self:_reportEscape()
	end))

	-- ---- World-state modifier tracking (weather bond) ----
	-- Build lookup of world-state modifiers (dropChance=0, non-deprecated).
	local worldMods: {[string]: any} = {}
	for _, mod in ipairs(GameConfig.FishModifiers) do
		if mod.dropChance == 0 and not mod.deprecated then
			worldMods[mod.id] = mod
		end
	end
	self._worldModLookup = worldMods

	-- Mirror server-side modifier assignment (FishingService.ReleaseReel:639-650):
	-- tide_kissed  ← High tide   storm_forged ← Storm weather
	-- moon_touched ← Night       dawn_blessed ← Morning       fog_shrouded ← Fog
	local TideService    = Knit.GetService("TideService")
	local WeatherService = Knit.GetService("WeatherService")

	self._trove:Add(WeatherService.WeatherChanged:Connect(function(weather: string)
		self._weatherState = weather
		self:_updateConditionsPill()
	end))
	self._trove:Add(TideService.TideChanged:Connect(function(state: string)
		self._tideState = state
		self:_updateConditionsPill()
	end))

	-- Initial pull for weather + time-of-day.
	WeatherService:GetWeatherState():andThen(function(payload: { weather: string, timeOfDay: string })
		self._weatherState = payload.weather
		self._timeOfDay = payload.timeOfDay
		self:_updateConditionsPill()
	end)
end

function FishingController:_onRodTap()
	if self._phase == "idle" then
		self:_startCast()
	elseif self._phase == "casting" then
		self:_releaseCastMarker()
	end
	-- "reeling" phase: hold input drives it; taps do nothing.
end

function FishingController:_ensureCastTrove()
	if not self._castTrove then self._castTrove = Trove.new() end
	return self._castTrove
end

function FishingController:_disposeCast()
	self._phase = "idle"
	self._pendingCastId = nil
	self._castButton = nil
	self._castMeterCtrl:dismiss()
	if self._conditionsPill then
		self._conditionsPill:Destroy()
		self._conditionsPill = nil
	end
	if self._castTrove then
		self._castTrove:Destroy()
		self._castTrove = nil
	end
end

-- ---- World-state modifier helpers (weather bond) ----

function FishingController:_getActiveWorldModifiers(): {string}
	local active: {string} = {}
	if self._tideState  == "High"    then table.insert(active, "tide_kissed")  end
	if self._weatherState == "Storm" then table.insert(active, "storm_forged") end
	if self._timeOfDay  == "Night"   then table.insert(active, "moon_touched") end
	if self._timeOfDay  == "Morning" then table.insert(active, "dawn_blessed") end
	if self._weatherState == "Fog"   then table.insert(active, "fog_shrouded") end
	return active
end

function FishingController:_updateConditionsPill()
	-- Only show pill during an active cast.
	if self._phase == "idle" then return end

	local modifierIds = self:_getActiveWorldModifiers()
	if #modifierIds == 0 then
		if self._conditionsPill then
			self._conditionsPill:Destroy()
			self._conditionsPill = nil
		end
		return
	end

	-- Build a comma-separated display line from world-state modifier names.
	local parts: {string} = {}
	for _, id in ipairs(modifierIds) do
		local def = self._worldModLookup[id]
		if def then
			table.insert(parts, def.displayName)
		end
	end
	local labelText = table.concat(parts, " · ")

	if self._conditionsPill then
		-- Update existing pill text.
		local lbl = self._conditionsPill:FindFirstChild("Label")
		if lbl and lbl:IsA("TextLabel") then
			lbl.Text = labelText
		end
		return
	end

	-- Create pill above cast button. Styled to match HUD theme.
	local P = UIUtil.Palette
	local pill = Instance.new("Frame")
	pill.Name = "ConditionsPill"
	pill.BackgroundColor3 = P.Teal
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -110) -- above the cast button area
	pill.Size = UDim2.new(0, 0, 0, UIUtil.MinTouchPx) -- width set by content
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Parent = self._castButton and self._castButton.Parent or nil

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, UIUtil.Radii.sm)
	corner.Parent = pill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Text = labelText
	label.TextColor3 = P.Cream
	label.Font = UIUtil.Typography("caption")
	label.TextSize = 14
	label.Size = UDim2.new(0, 0, 1, 0)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Position = UDim2.new(0, UIUtil.Spacing.sm, 0, 0)
	label.Parent = pill

	-- Fade-in — respect ReducedMotion.
	label.TextTransparency = 1
	MotionUtil.tweenOrSnap(label, 0.2, { TextTransparency = 0 })

	self._conditionsPill = pill
end

function FishingController:_startCast()
	-- Validate the cast target before touching the server. If the cursor
	-- isn't aimed at terrain water, do nothing — no feedback needed; the
	-- player will quickly learn to aim at the sea.
	local castPoint = inferCastPoint()
	if not castPoint then return end

	local FishingService = Knit.GetService("FishingService")
	FishingService:StartCast():andThen(function(window)
		if not window then
			self:_fail("no_bite")
			return
		end
		self._pendingCastId = window.castId
		self._phase = "casting"
		local trove = self:_ensureCastTrove()

		-- ---- Cast feedback (the *thunk*) ----
		-- castPoint was validated before the async call; use the same value
		-- so the ripple lands exactly where the player aimed.
		shakeCamera()
		spawnRipple(castPoint, trove)
		local beam = spawnBeam(castPoint, trove)
		-- Stash the beam on the trove so the bite handler can snap it taut.
		-- We re-fetch through a closure rather than storing on self so a
		-- second cast starting before the first resolves can't mix beams.
		self._currentBeam = beam
		pulseHaptic()
		self._soundCtrl:Play("CastSplash", { volume = 0.6, position = castPoint })

		-- ---- Cast Meter (cast phase) ----
		-- CastMeterController owns the handle; reel signals are wired in KnitStart.
		local castButton = self._castMeterCtrl:show(window.greenCenter, window.greenSize, window.period)
		self._castButton = castButton  -- stored so _onBite can pulse it on bite

		-- Show world-state conditions pill (e.g. "Storm-Forged · Tide-Kissed")
		-- above the cast button so the player sees active modifiers before
		-- releasing the meter.
		self:_updateConditionsPill()

		-- The cast button (80px circle, bottom-center) is an alternative to the
		-- rod tap for releasing the marker. Both call _onRodTap which guards phase.
		trove:Add(castButton.Activated:Connect(function()
			self:_onRodTap()
		end))
	end):catch(function(err)
		warn("[FishingController] StartCast failed:", err)
	end)
end

-- Second rod tap during cast phase: capture the marker and ship to server.
function FishingController:_releaseCastMarker()
	if not self._pendingCastId then return end
	local castId = self._pendingCastId
	local marker, isPerfect = self._castMeterCtrl:releaseCast()
	if isPerfect then
		self._soundCtrl:Play("PerfectFlash", { volume = 0.35 })
	end
	-- Move to a wait-for-server state so additional taps don't spam ClaimCast.
	-- The server will resolve us into "reeling" (via BiteStarted) or "idle"
	-- (via CastResolved on miss/error).
	self._phase = "awaitingBite"

	-- Safety net: if neither BiteStarted nor CastResolved arrives within 10s
	-- (server error, network drop, or claim_too_late race), reset to idle so
	-- the player isn't stuck with a frozen meter indefinitely.
	task.delay(10, function()
		if self._phase == "awaitingBite" and self._pendingCastId == castId then
			warn("[FishingController] awaitingBite timed out — resetting to idle")
			self:_disposeCast()
		end
	end)

	local FishingService = Knit.GetService("FishingService")
	FishingService:ClaimCast(castId, marker):andThen(function(_ack)
		-- Server will fire either BiteStarted (→ enter reel) or CastResolved
		-- (→ miss/error). Nothing to do here.
	end):catch(function(err)
		warn("[FishingController] ClaimCast failed:", err)
		-- Promise rejection means the remote itself errored; unblock the client.
		if self._phase == "awaitingBite" and self._pendingCastId == castId then
			self:_disposeCast()
		end
	end)
end

-- ====================================================================
-- BITE → REEL
-- ====================================================================
function FishingController:_onBite(payload: any)
	if self._phase ~= "casting" and self._phase ~= "awaitingBite" then return end
	if not self._pendingCastId or payload.castId ~= self._pendingCastId then return end
	self._phase = "reeling"

	-- Snap line taut on bite — the visible cue that "you've got one".
	snapBeamTaut(self._currentBeam)

	-- Bite feedback — disposable hooks land on _castTrove for cleanup.
	local trove = self._castTrove
	nudgeCamera(trove)
	pulseCastButton(self._castButton, trove)
	flashVignette(trove)
	pulseHaptic()
	self._soundCtrl:Play("FishBite", { volume = GameConfig.FishBite.SoundVolume })

	-- Pick the tier params for this fish. Tier is now rarity-derived (server-side).
	-- Defensive fallback to medium in case of an unexpected value.
	local params = TENSION_TIERS[payload.tier] or TENSION_TIERS.medium

	-- Transition the meter UI. Rarity forwarded for zone color theming.
	self._castMeterCtrl:enterReel(payload.weightKg, payload.tier, params, payload.rarity or "Common")

	-- Start the continuous gamepad rumble for the duration of the fight.
	-- Stop function goes onto the trove so all cast-resolve paths kill it.
	local stopRumble = startRumble(params.rumble)
	if self._castTrove then
		self._castTrove:Add(stopRumble)
	end

	-- Hold input: mouse/touch/gamepad-button down → setHold(true). Up → false.
	-- We accept any "primary action" input so platforms feel native.
	local function isHoldInput(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonR2
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.Space
	end

	local beganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if isHoldInput(input) then self._castMeterCtrl:setHold(true) end
	end)
	local endedConn = UserInputService.InputEnded:Connect(function(input)
		if isHoldInput(input) then self._castMeterCtrl:setHold(false) end
	end)
	if self._castTrove then
		self._castTrove:Add(beganConn)
		self._castTrove:Add(endedConn)
	end
end

function FishingController:_releaseReel(perfectFraction: number)
	if self._phase ~= "reeling" then return end
	local castId = self._pendingCastId
	if not castId then return end
	-- Lock out double-fires; the meter still exists until CastResolved.
	self._phase = "resolving"
	local FishingService = Knit.GetService("FishingService")
	FishingService:ReleaseReel(castId, perfectFraction):catch(function(err)
		warn("[FishingController] ReleaseReel failed:", err)
	end)
end

function FishingController:_reportEscape()
	if self._phase ~= "reeling" then return end
	local castId = self._pendingCastId
	if not castId then return end
	self._phase = "resolving"
	local FishingService = Knit.GetService("FishingService")
	FishingService:ReportEscape(castId):catch(function(err)
		warn("[FishingController] ReportEscape failed:", err)
	end)
end

-- ====================================================================
-- RESULT HANDLERS
-- ====================================================================
function FishingController:_onResolved(result: any)
	if result.success then
		self:_celebrate(result)
	else
		self:_fail(result.reason)
	end
	self:_disposeCast()
end

function FishingController:_celebrate(result: any)
	self._soundCtrl:Play("CatchSuccess", { volume = 0.6 })
	-- Perfect flag is server-validated now — we trust result.perfect.
	CatchRevealUI.show({
		fish = result.fish,
		weightKg = result.weightKg or 0,
		coinsEarned = result.coinsEarned,
		xpGained = result.xpGained,
		perfect = result.perfect == true,
		castPerfect = result.castPerfect == true,
		modifiers = result.modifiers,
	})
end

function FishingController:_fail(reason: any)
	self._soundCtrl:Play("CatchFail", { volume = 0.4 })
	if reason == "missed" then
		self._notifCtrl:Toast("Slipped off the line!")
	elseif reason == "no_bite" then
		self._notifCtrl:Toast("Nothing biting here…")
	elseif reason == "escaped" then
		self._notifCtrl:Toast("The fish got away!")
	elseif reason == "reel_timeout" then
		self._notifCtrl:Toast("Too slow — fish escaped.")
	elseif reason == "timeout" then
		self._notifCtrl:Toast("Line went slack.")
	else
		self._notifCtrl:Toast("Cast failed.")
	end
end

return FishingController
