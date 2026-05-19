--!strict
-- FishParticles.lua
-- Client-only. Attaches layered ParticleEmitters to a BasePart per modifier.
-- Each modifier in GameConfig.ModifierParticles is an array of layer configs;
-- this creates one emitter per layer, allowing multi-layer GAG-style effects.
-- rateScale multiplies every layer's Rate (pass ~0.35 for UI viewports).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig  = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil  = require(script.Parent.MotionUtil)

local FishParticles = {}

function FishParticles.attach(part: BasePart, mods: {string}, rateScale: number?)
	if #mods == 0 then return end
	local scale   = rateScale or 1.0
	local reduced = MotionUtil.reducedMotionEnabled()
	local cfg: {[string]: any} = (GameConfig :: any).ModifierParticles or {}

	for _, modId in ipairs(mods) do
		local layers: {any}? = cfg[modId]
		if not layers then continue end

		for _, layer: {[string]: any} in ipairs(layers) do
			local pe = Instance.new("ParticleEmitter")
			if layer.Texture then pe.Texture = layer.Texture end
			pe.Color          = layer.Color
			pe.LightEmission  = layer.LightEmission  or 0
			pe.LightInfluence = layer.LightInfluence or 1
			pe.Lifetime       = layer.Lifetime
			pe.Size           = layer.Size
			pe.Transparency   = layer.Transparency or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			pe.Speed          = layer.Speed
			pe.SpreadAngle    = layer.SpreadAngle
			pe.Rate           = reduced and 0 or (layer.Rate * scale)
			if layer.Rotation     then pe.Rotation     = layer.Rotation     end
			if layer.RotSpeed     then pe.RotSpeed     = layer.RotSpeed     end
			if layer.Acceleration then pe.Acceleration = layer.Acceleration end
			pe.Parent = part
		end
	end
end

return FishParticles
