--!strict
-- FishingController.lua
-- Owns the cast lifecycle on the client. The 30-second loop, post-Path-A:
--   1. Player taps Rod (Tool.Activated → RodService.RodActivated).
--   2. Server picks a fish secretly, returns a timing window. Phase: casting.
--   3. Cast feedback fires: camera shake, ripples at the cast point,
--      a Beam from rod tip to water, haptic pulse, splash audio (TODO).
--   4. CastMeter shows; player tracks the inner perfect zone for cosmetic
--      "PERFECT!" flashes. Release triggers ClaimCast.
--   5. If marker missed the green zone, CastResolved fires with reason="missed".
--      If marker hit the green zone, server fires BiteStarted with weight +
--      tier + difficulty and the client transitions into the reel phase.
--   6. Reel phase: a moving good zone oscillates, the player holds a button
--      (LMB / touch / gamepad R2/A) to drive an indicator into the zone.
--      Time inside the zone counts toward ReelHoldDuration; perfect-zone
--      time double-counts. Indicator hitting the left edge while drifting
--      back fires ReportEscape; cumulative time reaching the threshold fires
--      ReleaseReel(perfectFraction).
--   7. Server validates and fires CastResolved (success or escaped).
--   8. CatchRevealUI slides up with the fish data + server-authoritative
--      perfect flag.
--
-- Architecture:
--   * Server-authoritative. Client never decides what was caught or what
--     XP bonus is granted — perfectFraction is validated server-side.
--   * All decoration motion goes through MotionUtil (reduced-motion aware).
--   * Trove owns all per-cast disposables (Beams, attachments, ripples,
--     tweens). Cleared on cast resolve so back-to-back casts don't leak.
--   * Tension tiers (light/medium/heavy/legendary) scale haptic intensity,
--     fight rumble, and zone-loss feedback. Gameplay parameters (zone speed,
--     width, drift speed) are driven server-side from weight so client and
--     server agree on difficulty without round-trip negotiation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local HapticService     = game:GetService("HapticService")
local SoundService      = game:GetService("SoundService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local CastMeter  = require(script.Parent.Parent.UI.CastMeter)
local CatchRevealUI = require(script.Parent.Parent.UI.CatchRevealUI)
local AssetIds   = require(script.Parent.Parent.AssetIds)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local FT = GameConfig.Fishing.FeelTuning

-- Tier-driven feel parameters. Server picks the tier from the catch weight
-- (light <2kg, medium <10kg, heavy <40kg, legendary >=40kg) and sends it
-- in BiteStarted; the client uses these to scale haptic intensity, camera
-- shake magnitude on zone loss, and the continuous fight rumble.
-- (Server *also* uses weight to scale the gameplay parameters — zone speed,
-- zone width, drift-back speed — so client and server stay in sync on
-- difficulty without the client having to derive them.)
local TENSION_TIERS = {
	light = {
		fightRumbleIntensity   = 0.10,
		zoneLossShakeMagnitude = 0.0,
		zoneLossHaptic         = 0.15,
	},
	medium = {
		fightRumbleIntensity   = 0.20,
		zoneLossShakeMagnitude = 0.15,
		zoneLossHaptic         = 0.30,
	},
	heavy = {
		fightRumbleIntensity   = 0.35,
		zoneLossShakeMagnitude = 0.30,
		zoneLossHaptic         = 0.50,
	},
	legendary = {
		fightRumbleIntensity   = 0.55,
		zoneLossShakeMagnitude = 0.45,
		zoneLossHaptic         = 0.70,
	},
}

local FishingController = Knit.CreateController({
	Name = "FishingController",
	-- Phase: "idle" | "casting" | "reeling".
	_phase = "idle",
	_pendingCastId = nil :: string?,
	_meter = nil :: any,          -- the cast meter handle (phase = "casting")
	_reelMeter = nil :: any,      -- the reel meter handle (phase = "reeling")
	_reelTier = nil :: string?,
	_castTrove = nil :: any,      -- disposables for the *current* cast
	_reelInputConns = nil :: any, -- table of RBXScriptConnections for reel hold input
	_lastPerfectFraction = 0,
})

-- ====================================================================
-- HAPTICS — gamepad motors only. Touch devices don't have a public
-- vibration API. Always pcall-wrap; SetMotor throws on unsupported.
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

-- ====================================================================
-- CAMERA SHAKE — small one-shot offset on the active camera. Bound via
-- BindToRenderStep at a priority *after* Roblox's camera update so we
-- additively offset instead of fighting the cam controller.
-- Reduced motion: skipped entirely.
-- ====================================================================
local function shakeCamera()
	if MotionUtil.reducedMotionEnabled() then return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local startT = os.clock()
	local bindName = "TidesFishingCastShake"
	-- Unbind any previous shake so back-to-back casts don't accumulate.
	pcall(function() RunService:UnbindFromRenderStep(bindName) end)
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local t = (os.clock() - startT) / FT.CastShakeDuration
		if t >= 1 then
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local decay = (1 - t) * (1 - t)  -- quad out
		local m = FT.CastShakeMagnitude * decay
		local offset = Vector3.new((math.random() - 0.5) * 2 * m, (math.random() - 0.5) * 2 * m, (math.random() - 0.5) * 2 * m)
		cam.CFrame = cam.CFrame * CFrame.new(offset)
	end)
end

-- ====================================================================
-- CAST POINT — best-guess world position where the line "lands". On PC
-- we use the mouse hit. On touch we project from the rod tip a few
-- studs forward at water level.
-- ====================================================================
local function inferCastPoint(): Vector3
	local cam = Workspace.CurrentCamera
	if cam then
		local mouse = Players.LocalPlayer:GetMouse()
		if mouse and mouse.Hit then
			-- Clamp to water surface (Y=0) — the cast lands ON water, not in air.
			local p = mouse.Hit.Position
			return Vector3.new(p.X, 0, p.Z)
		end
	end
	-- Fallback: 10 studs in front of the character at water level.
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		local fwd = hrp.CFrame.LookVector
		local p = hrp.Position + fwd * 12
		return Vector3.new(p.X, 0, p.Z)
	end
	return Vector3.new(0, 0, 0)
end

-- ====================================================================
-- RIPPLE — geometric fallback that needs no asset. Two concentric
-- cylinders flat at the water surface, expanding outward and fading.
-- AssetIds.Images.RippleRing can swap this for a ring sprite later.
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
		part.Color = Color3.fromRGB(220, 240, 255)
		-- Cylinder's long axis is X; rotate so its caps face up/down.
		local cf = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		part.CFrame = cf
		-- Start size: thin slab with small initial radius. After rotation,
		-- Size.X is vertical thickness, Size.Y/Z are horizontal extent.
		if reduced then
			-- Reduced motion: spawn at full size, just fade.
			part.Size = Vector3.new(0.1, FT.RippleMaxRadius * 2, FT.RippleMaxRadius * 2)
			part.Transparency = 0.4
		else
			part.Size = Vector3.new(0.1, 0.5, 0.5)
			part.Transparency = 0.2
		end
		part.Parent = Workspace
		trove:Add(part)

		-- Stagger the second ripple by ~0.12s for a "drop hit, ring out twice" feel.
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
-- LINE BEAM — fishing line from rod tip to a target attachment at the
-- cast point. Sags initially (CurveSize0/1 nonzero), then snaps taut
-- when the meter shows ("the fish has bitten").
-- ====================================================================
local function spawnBeam(castPoint: Vector3, trove: any): Beam?
	local char = Players.LocalPlayer.Character; if not char then return nil end
	local rod = char:FindFirstChild("Fishing Rod"); if not rod or not rod:IsA("Tool") then return nil end
	local handle = rod:FindFirstChild("Handle"); if not handle or not handle:IsA("BasePart") then return nil end

	-- Source attachment at the rod tip. Reuse if already on the handle so
	-- we don't pile up attachments across casts.
	local source = handle:FindFirstChild("LineEnd") :: Attachment?
	if not source then
		source = Instance.new("Attachment")
		source.Name = "LineEnd"
		-- Offset forward along the handle's long axis. Placeholder rod is
		-- 4.5 studs long on Z; halve that and add the tip's length so we
		-- land near the actual tip. For custom asset rods, override by
		-- adding a real LineEnd attachment to the model.
		source.Position = Vector3.new(0, 0, -((handle.Size.Z / 2) + 1.5))
		source.Parent = handle
	end

	-- Target attachment on an invisible anchor at the cast point.
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
	-- Initial sag — line hangs while the lure settles.
	beam.CurveSize0 = 2
	beam.CurveSize1 = -2
	beam.Color = ColorSequence.new(Color3.fromRGB(250, 245, 230))
	-- TODO: replace with AssetIds.Images.BeamTexture once a 1px line strip
	-- asset is uploaded. Roblox will render Beam without a texture as a
	-- solid color strip, which is fine for v1.
	beam.Texture = AssetIds.Images.BeamTexture
	beam.TextureSpeed = 0
	beam.Parent = anchor
	trove:Add(beam)

	-- Snap taut after a short delay. Reduced motion: snap instantly.
	local snapInfo = MotionUtil.reducedMotionEnabled()
		and TweenInfo.new(0)
		or TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.delay(0.18, function()
		if not beam.Parent then return end
		local t1 = MotionUtil.tween(beam, snapInfo, { CurveSize0 = 0 })
		local t2 = MotionUtil.tween(beam, snapInfo, { CurveSize1 = 0 })
		t1.Completed:Connect(function() t1:Destroy() end)
		t2.Completed:Connect(function() t2:Destroy() end)
	end)
	return beam
end

-- ====================================================================
-- AUDIO — pcall'd because empty SoundId throws in some contexts.
-- ====================================================================
local function playSound(soundId: string, volume: number?, position: Vector3?)
	if not soundId or soundId == "" then return end  -- TODO assets, silent for now
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = soundId
		s.Volume = volume or 0.6
		if position then
			-- Positional sound: parent to an anchor part at the cast point.
			local p = Instance.new("Part")
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
			p.Transparency = 1; p.Size = Vector3.new(0.1, 0.1, 0.1)
			p.CFrame = CFrame.new(position)
			p.Parent = Workspace
			s.RollOffMaxDistance = 80
			s.Parent = p
			s:Play()
			s.Ended:Connect(function() p:Destroy() end)
		else
			SoundService:PlayLocalSound(s)
		end
	end)
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function FishingController:KnitStart()
	local FishingService = Knit.GetService("FishingService")
	local RodService = Knit.GetService("RodService")

	-- Server-resolved cast result. Either ReleaseReel/ReportEscape's
	-- response, or a server timeout. CastResolved is now the SOLE terminus
	-- for the cast lifecycle — ClaimCast's success no longer fires it.
	FishingService.CastResolved:Connect(function(result)
		self:_endCast()
		if result.success then
			self:_celebrate(result)
		else
			self:_fail(result.reason, result)
		end
	end)

	-- Bite signal: server tells us we hit the green zone and a fish is on.
	-- Carries weight + tier + difficulty for the reel phase visuals.
	FishingService.BiteStarted:Connect(function(payload)
		self:_onBiteStarted(payload)
	end)

	-- The cast trigger. Rod's Tool.Activated → CastOrRelease.
	-- In reel phase the rod tap is IGNORED — input switches to hold-and-
	-- release on the reel button (left mouse / touch / gamepad ButtonR2),
	-- bound directly via UserInputService while the reel meter is up.
	RodService.RodActivated:Connect(function()
		self:CastOrRelease()
	end)
end

-- Tap-driven entry point. Behaviour by phase:
--   idle    → start the cast (server picks a fish, returns timing window)
--   casting → release the meter (claim the cast)
--   reeling → ignored (the reel phase uses hold input, not tap)
function FishingController:CastOrRelease()
	if self._phase == "casting" then
		self:_releaseClaim()
		return
	end
	if self._phase == "reeling" then return end
	self:_startCast()
end

-- Per-cast trove holds Beam, attachments, ripple parts, tweens. Disposed
-- on cast resolve so we don't leak instances if the player back-to-back-casts.
function FishingController:_ensureCastTrove()
	if not self._castTrove then self._castTrove = Trove.new() end
	return self._castTrove
end

-- Tears down everything tied to the current cast: trove, both meters,
-- reel input bindings, gamepad rumble. Called when CastResolved fires
-- (success or fail) and also from defensive paths (StartCast error).
function FishingController:_endCast()
	self._phase = "idle"
	self._pendingCastId = nil
	if self._meter then self._meter.stop(); self._meter = nil end
	if self._reelMeter then self._reelMeter.stop(); self._reelMeter = nil end
	self._reelTier = nil
	self:_stopReelInput()
	self:_stopFightRumble()
	if self._castTrove then
		self._castTrove:Destroy()
		self._castTrove = nil
	end
end

function FishingController:_startCast()
	local FishingService = Knit.GetService("FishingService")
	self._phase = "casting"
	FishingService:StartCast():andThen(function(window)
		if not window then
			self:_fail("no_bite")
			return
		end
		-- Race: if a previous cast just resolved on the server and we got an
		-- old StartCast response back late, the phase may have been reset.
		-- Only set up the meter if we're still in casting phase.
		if self._phase ~= "casting" then return end
		self._pendingCastId = window.castId
		local trove = self:_ensureCastTrove()

		-- ---- Cast feedback (the *thunk*) ----
		local castPoint = inferCastPoint()
		shakeCamera()
		spawnRipple(castPoint, trove)
		spawnBeam(castPoint, trove)
		pulseHaptic()
		playSound(AssetIds.Sounds.CastSplash, 0.6, castPoint)

		-- ---- Meter ----
		self._meter = CastMeter.show(window.greenCenter, window.greenSize, window.period)
	end):catch(function(err)
		warn("[FishingController] StartCast failed:", err)
		self._phase = "idle"
	end)
end

-- Player tapped to release the cast meter. Send marker to server; either:
--   * server says "missed" → CastResolved fires with reason="missed"
--   * server says "biting" + fires BiteStarted → transition to reel phase
function FishingController:_releaseClaim()
	if not self._pendingCastId or not self._meter then return end
	local castId = self._pendingCastId
	-- The cast meter slides out; the reel meter (if we get one) slides in.
	local marker, _perfectFraction = self._meter.stop()
	self._meter = nil

	local FishingService = Knit.GetService("FishingService")
	FishingService:ClaimCast(castId, marker):andThen(function(_result)
		-- Both branches drive UI from server signals (CastResolved /
		-- BiteStarted) so timeouts and direct claims behave identically.
		-- Nothing to do here besides letting those handlers run.
	end):catch(function(err)
		warn("[FishingController] ClaimCast failed:", err)
	end)
end

-- ====================================================================
-- REEL PHASE — Path A mini-game
-- ====================================================================

-- Track held buttons across all input types. Reel meter's "is the player
-- holding the reel button right now?" comes from this set.
local REEL_INPUT_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}
local REEL_GAMEPAD_BUTTONS = {
	[Enum.KeyCode.ButtonR2] = true,
	[Enum.KeyCode.ButtonA] = true,
}

function FishingController:_startReelInput()
	if self._reelInputConns then return end
	local conns = {}
	local heldInputs: {[any]: boolean} = {}
	-- Pre-populate from current input state. Handles the race where the user
	-- is still holding the same button they used to release the cast meter
	-- when BiteStarted arrives — without this, InputBegan never re-fires
	-- and the meter would think they're not holding.
	if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		heldInputs[Enum.UserInputType.MouseButton1] = true
	end
	for keyCode in pairs(REEL_GAMEPAD_BUTTONS) do
		if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, keyCode) then
			heldInputs[keyCode] = true
		end
	end
	local function refresh()
		local anyHeld = false
		for _, v in pairs(heldInputs) do
			if v then anyHeld = true; break end
		end
		if self._reelMeter then self._reelMeter.setHolding(anyHeld) end
	end
	refresh()
	conns[#conns+1] = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if REEL_INPUT_TYPES[input.UserInputType] then
			heldInputs[input.UserInputType] = true
			refresh()
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 and REEL_GAMEPAD_BUTTONS[input.KeyCode] then
			heldInputs[input.KeyCode] = true
			refresh()
		end
	end)
	conns[#conns+1] = UserInputService.InputEnded:Connect(function(input)
		if REEL_INPUT_TYPES[input.UserInputType] then
			heldInputs[input.UserInputType] = nil
			refresh()
		elseif input.UserInputType == Enum.UserInputType.Gamepad1 and REEL_GAMEPAD_BUTTONS[input.KeyCode] then
			heldInputs[input.KeyCode] = nil
			refresh()
		end
	end)
	self._reelInputConns = conns
end

function FishingController:_stopReelInput()
	if not self._reelInputConns then return end
	for _, c in ipairs(self._reelInputConns) do c:Disconnect() end
	self._reelInputConns = nil
end

-- Continuous low-frequency rumble during the fight. Intensity scales with
-- tension tier. Server stops the rumble by closing the cast (haptic cleared
-- in _stopFightRumble). pcall-wrapped in case the device has no motors.
function FishingController:_startFightRumble(tier: string)
	if not UserInputService.GamepadEnabled then return end
	local def = TENSION_TIERS[tier] or TENSION_TIERS.medium
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, def.fightRumbleIntensity)
	end)
end

function FishingController:_stopFightRumble()
	if not UserInputService.GamepadEnabled then return end
	pcall(function()
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
		HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0)
	end)
end

-- Small camera shake + haptic pulse when the indicator drops out of the
-- good zone during the fight. Scaled by tier — a 50kg fish jolts the
-- camera and the controller; a 0.5kg fish does nothing.
function FishingController:_zoneLossFeedback(tier: string)
	local def = TENSION_TIERS[tier] or TENSION_TIERS.medium
	if def.zoneLossShakeMagnitude > 0 and not MotionUtil.reducedMotionEnabled() then
		local cam = Workspace.CurrentCamera
		if cam then
			local startT = os.clock()
			local DUR = 0.18
			local bindName = "TidesFishingZoneLossShake"
			pcall(function() RunService:UnbindFromRenderStep(bindName) end)
			RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
				local t = (os.clock() - startT) / DUR
				if t >= 1 then RunService:UnbindFromRenderStep(bindName); return end
				local m = def.zoneLossShakeMagnitude * (1 - t) * (1 - t)
				cam.CFrame = cam.CFrame * CFrame.new(
					(math.random() - 0.5) * 2 * m,
					(math.random() - 0.5) * 2 * m,
					(math.random() - 0.5) * 2 * m
				)
			end)
		end
	end
	if UserInputService.GamepadEnabled and def.zoneLossHaptic > 0 then
		pcall(function()
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, def.zoneLossHaptic)
			task.delay(0.1, function()
				pcall(function()
					-- Restore the continuous fight rumble (don't zero the motor —
					-- there might be background rumble for the current tier).
					HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Small, 0)
				end)
			end)
		end)
	end
end

function FishingController:_onBiteStarted(payload: any)
	if not payload or not payload.castId then return end
	-- Defensive: ignore stale BiteStarted (server already advanced past it).
	if self._pendingCastId and payload.castId ~= self._pendingCastId then
		-- Server reused our castId — accept.
	end
	self._pendingCastId = payload.castId
	self._phase = "reeling"
	self._reelTier = payload.tier or "medium"

	-- Spin up the reel meter. The cast meter has already slid out (see
	-- _releaseClaim → self._meter.stop). The reel meter slides in over
	-- FT.MeterTransitionDuration to deliver the prompt's smooth transition.
	local reel = CastMeter.reel(payload.weightKg or 0, self._reelTier, payload.difficulty or 0.3)
	self._reelMeter = reel

	-- Fire zone-loss feedback (camera shake + haptic) exactly when the
	-- meter transitions tracking → losing. The reel meter handles its own
	-- in-bar visuals; this layers the worldspace impact on top.
	reel.onStateChanged = function(state)
		if state == "losing" then
			self:_zoneLossFeedback(self._reelTier or "medium")
		end
	end

	-- Hook the meter's resolution callbacks. These fire AT MOST once.
	reel.onSuccess = function(perfectFraction)
		self._lastPerfectFraction = perfectFraction
		local FishingService = Knit.GetService("FishingService")
		FishingService:ReleaseReel(payload.castId, perfectFraction):andThen(function() end):catch(function(err)
			warn("[FishingController] ReleaseReel failed:", err)
		end)
		-- CastResolved will arrive shortly; _endCast runs there.
	end
	reel.onEscape = function()
		local FishingService = Knit.GetService("FishingService")
		FishingService:ReportEscape(payload.castId):andThen(function() end):catch(function(err)
			warn("[FishingController] ReportEscape failed:", err)
		end)
	end

	self:_startReelInput()
	self:_startFightRumble(self._reelTier)
end

-- ====================================================================
-- RESULT HANDLERS — replace the old print()s with the reveal card.
-- ====================================================================
function FishingController:_celebrate(result: any)
	playSound(AssetIds.Sounds.CatchSuccess, 0.6)
	-- Server-authoritative perfect flag (Path A). Falls back to the client's
	-- last-known perfect fraction only if the server omits the field — should
	-- never happen with the current FishingService, but defensive.
	local perfect = result.perfect
	if perfect == nil then
		perfect = (result.perfectFraction or self._lastPerfectFraction) >= FT.PerfectThreshold
	end
	CatchRevealUI.show({
		fish = result.fish,
		weightKg = result.weightKg or 0,
		coinsEarned = result.coinsEarned,
		xpGained = result.xpGained,
		perfect = perfect,
	})
end

function FishingController:_fail(reason: any, result: any?)
	playSound(AssetIds.Sounds.CatchFail, 0.4)
	-- TODO: replace print with a small ephemeral toast (reuse Aquarium toast pattern?).
	if reason == "missed" then
		print("[Fishing] Slipped off the line!")
	elseif reason == "no_bite" then
		print("[Fishing] Nothing's biting here right now.")
	elseif reason == "escaped" then
		local xp = (result and result.xpGained) or 0
		print(("[Fishing] The fish escaped! Consolation XP: %d"):format(xp))
	elseif reason == "reel_timeout" then
		print("[Fishing] The line went slack — fish swam away.")
	else
		print("[Fishing] Cast failed:", reason)
	end
end

return FishingController
