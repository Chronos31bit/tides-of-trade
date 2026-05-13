--!strict
-- FishingController.lua
-- Owns the cast lifecycle on the client. The 30-second loop:
--   1. Player taps Rod (Tool.Activated → RodService.RodActivated).
--   2. Server picks a fish secretly, returns a timing window.
--   3. Cast feedback fires: camera shake, ripples at the cast point,
--      a Beam from rod tip to water, haptic pulse, splash audio (TODO).
--   4. CastMeter shows; player tracks the perfect inner zone for cosmetic
--      "PERFECT!" flashes. Release triggers ClaimCast.
--   5. Server returns success/fail via CastResolved.
--   6. CatchRevealUI slides up with the fish data + perfect flag.
--
-- Architecture:
--   * Server-authoritative. Client never decides what was caught.
--   * All decoration motion goes through MotionUtil (reduced-motion aware).
--   * Trove owns all per-cast disposables (Beams, attachments, ripples,
--     tweens). Cleared on cast resolve so back-to-back casts don't leak.

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

local FishingController = Knit.CreateController({
	Name = "FishingController",
	_pendingCastId = nil :: string?,
	_meter = nil :: any,
	_castTrove = nil :: any,     -- disposables for the *current* cast
	_lastPerfectFraction = 0,    -- captured from the meter on release
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

	-- Server-resolved cast result. Either claim's response or a timeout.
	FishingService.CastResolved:Connect(function(result)
		self:_disposeCast()
		if result.success then
			self:_celebrate(result)
		else
			self:_fail(result.reason)
		end
	end)

	-- The cast trigger gated by holding the rod tool. Server fires
	-- RodActivated on Tool.Activated. Same handler for first tap (cast) and
	-- second tap (release).
	RodService.RodActivated:Connect(function()
		self:CastOrRelease()
	end)
end

-- The unified entry point. First call → cast; second call → release.
function FishingController:CastOrRelease()
	if self._pendingCastId then
		self:_releaseClaim()
		return
	end
	self:_startCast()
end

-- Per-cast trove holds Beam, attachments, ripple parts, tweens. Disposed
-- on cast resolve so we don't leak instances if the player back-to-back-casts.
function FishingController:_ensureCastTrove()
	if not self._castTrove then self._castTrove = Trove.new() end
	return self._castTrove
end

function FishingController:_disposeCast()
	if self._castTrove then
		self._castTrove:Destroy()
		self._castTrove = nil
	end
end

function FishingController:_startCast()
	local FishingService = Knit.GetService("FishingService")
	FishingService:StartCast():andThen(function(window)
		if not window then
			self:_fail("no_bite")
			return
		end
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
	end)
end

function FishingController:_releaseClaim()
	if not self._pendingCastId or not self._meter then return end
	local castId = self._pendingCastId
	self._pendingCastId = nil
	local marker, perfectFraction = self._meter.stop()
	self._meter = nil
	-- Stash for the reveal card. Server result will arrive via CastResolved.
	self._lastPerfectFraction = perfectFraction or 0

	local FishingService = Knit.GetService("FishingService")
	FishingService:ClaimCast(castId, marker):andThen(function(_result)
		-- Authoritative result also arrives via CastResolved — let that
		-- path drive UI so server timeouts and direct claims behave
		-- identically. Nothing to do here.
	end):catch(function(err)
		warn("[FishingController] ClaimCast failed:", err)
	end)
end

-- ====================================================================
-- RESULT HANDLERS — replace the old print()s with the reveal card.
-- ====================================================================
function FishingController:_celebrate(result: any)
	playSound(AssetIds.Sounds.CatchSuccess, 0.6)
	-- "Perfect" client-side check: did the meter's perfectFraction clear
	-- the threshold? Today this is cosmetic only — the server can't
	-- validate it under the current contract. Once Path A lands, this
	-- becomes a server-confirmed flag in the result payload instead.
	local perfect = self._lastPerfectFraction >= FT.PerfectThreshold
	CatchRevealUI.show({
		fish = result.fish,
		weightKg = result.weightKg or 0,
		coinsEarned = result.coinsEarned,
		xpGained = result.xpGained,
		perfect = perfect,
	})
end

function FishingController:_fail(reason: any)
	playSound(AssetIds.Sounds.CatchFail, 0.4)
	-- TODO: replace print with a small ephemeral toast (reuse Aquarium toast pattern?).
	if reason == "missed" then
		print("[Fishing] Slipped off the line!")
	elseif reason == "no_bite" then
		print("[Fishing] Nothing's biting here right now.")
	else
		print("[Fishing] Cast failed:", reason)
	end
end

return FishingController
