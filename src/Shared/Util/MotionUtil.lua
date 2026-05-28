--!strict
-- MotionUtil.lua
-- Tween + animation helpers that are aware of GuiService.ReducedMotionEnabled.
-- The rule: never disable gameplay, only decoration. If a motion is purely
-- decorative (slide in, ripple expansion, screen shake), the reduced-motion
-- path skips/snaps it. If a motion communicates state (XP bar fill, meter
-- marker position), it still animates — just often faster or with less
-- easing.
--
-- Keep this module pure: no instance creation, no global state. Callers
-- create their tweens via these helpers and own cleanup.

local TweenService = game:GetService("TweenService")
local GuiService   = game:GetService("GuiService")
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local MotionUtil = {}

local MOTION_ATTR = GameConfig.Settings.AttrMotionMode

-- Single source of truth for "is reduced motion on". Cached so we don't pay
-- a property read every frame; refreshed via GuiService:GetPropertyChangedSignal
-- and the player's motion-override attribute (set by the Settings hub).
local _reduced = GuiService.ReducedMotionEnabled

-- Recompute the cached flag from the OS setting + the player's override:
--   "off"     -> always animate (reduced = false)
--   "reduced" -> always reduced (reduced = true)
--   "auto"/nil -> follow GuiService.ReducedMotionEnabled
-- On the server there is no LocalPlayer, so we fall back to the OS value.
local function recompute()
	local mode: string? = nil
	if RunService:IsClient() then
		local player = Players.LocalPlayer
		if player then
			local attr = player:GetAttribute(MOTION_ATTR)
			if type(attr) == "string" then
				mode = attr
			end
		end
	end

	if mode == "off" then
		_reduced = false
	elseif mode == "reduced" then
		_reduced = true
	else
		_reduced = GuiService.ReducedMotionEnabled
	end
end

GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(recompute)

-- Bind the override attribute on the client. LocalPlayer can be nil for a few
-- frames during client boot, so wait for it without blocking module load.
if RunService:IsClient() then
	task.spawn(function()
		local player = Players.LocalPlayer
		while not player do
			task.wait()
			player = Players.LocalPlayer
		end
		player:GetAttributeChangedSignal(MOTION_ATTR):Connect(recompute)
		recompute()
	end)
end

recompute()

function MotionUtil.reducedMotionEnabled(): boolean
	return _reduced
end

-- Create + play a tween. Returns the Tween so callers can :Destroy() it on
-- cleanup (or wire it into a Trove). Does NOT auto-destroy — that's caller's
-- responsibility.
function MotionUtil.tween(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

-- "Tween, or snap if reduced motion." Use this for purely decorative motion.
-- If reduced motion is on, the final property values are applied immediately
-- and the function returns nil (no Tween to clean up).
function MotionUtil.tweenOrSnap(instance: Instance, info: TweenInfo, props: {[string]: any}): Tween?
	if _reduced then
		for k, v in pairs(props) do (instance :: any)[k] = v end
		return nil
	end
	return MotionUtil.tween(instance, info, props)
end

-- Apply a property value either via tween or instant — same as tweenOrSnap
-- but takes a single property name. Convenience.
function MotionUtil.set(instance: Instance, info: TweenInfo, prop: string, value: any): Tween?
	return MotionUtil.tweenOrSnap(instance, info, { [prop] = value })
end

-- Quad-out decay curve in [0, 1]. Used by the cast shake's amplitude envelope.
function MotionUtil.quadOutDecay(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

return MotionUtil
