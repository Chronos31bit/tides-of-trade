--!strict
-- ModifierMutations.lua
-- Per-modifier visual treatment for held fish (GAG video-aligned pass 4).
--
-- Three layers: (1) body material/tint/colorCycle, (2) softGlow fillT 0.72–0.85,
-- (3) signature particles/fire/beams/glass only where needed.
-- No default ForceField shells. Particle fields: lockedToPart, velocityInheritance,
-- drag — see FishMutations.lua. Stable IDs forever.

local GameConfig = require(script.Parent.GameConfig)

local M = {}

local _bodyScale = ((GameConfig :: any).FishMutationVisuals :: any).ModifierBodyScale or {}

local STAR_TEX    = "rbxasset://textures/particles/sparkles_main.dds"
local SPARKLE_TEX = "rbxassetid://6282433556" -- rainbow motes only

-- Studio tester electricity (Preview_shocked / Preview_frozen Attachment children).
local ELECTRIC_BURST_TEX      = "rbxassetid://138370769"
local TRAIL_ELECTRIC_TEX      = "rbxassetid://243098098"
local TRAIL_ELECTRIC_BLUR_TEX = "rbxassetid://243664672"

-- Studio preview attachment textures.
local VOID_CLOUD_TEX       = "rbxassetid://243599653"
local VOID_BUBBLE_TEX      = "rbxassetid://241597670"
local DAWN_BLESSED_TEX     = "rbxassetid://8890667599"
local FOG_SHROUDED_TEX     = "rbxassetid://14221378803"
local PRISMATIC_TEX        = "rbxassetid://14054628491"
local SHINY_TEX            = "rbxassetid://7216849325"
local INFERNO_FIRE_TEX     = "rbxassetid://11395089850"
local INFERNO_EMBER_TEX    = "rbxassetid://4509687978"

local VOID_CLOUD_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 1),
	NumberSequenceKeypoint.new(0.4, 1.25),
	NumberSequenceKeypoint.new(0.5, 1),
	NumberSequenceKeypoint.new(1, 0),
})

local VOID_BUBBLE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.3, 0.85),
	NumberSequenceKeypoint.new(0.4, 1),
	NumberSequenceKeypoint.new(0.5, 0.85),
	NumberSequenceKeypoint.new(1, 0),
})

local function studioAttachment(emitters: {{[string]: any}}): {[string]: any}
	return {
		kind = "attachmentParticles",
		position = Vector3.zero,
		emitters = emitters,
	}
end

local INFERNO_FIRE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.328, 0.522),
	NumberSequenceKeypoint.new(0.769, 0.538),
	NumberSequenceKeypoint.new(0.862, 0.844),
	NumberSequenceKeypoint.new(0.933, 0.95),
	NumberSequenceKeypoint.new(1, 1),
})

local function voidPreviewAttachment(): {[string]: any}
	return studioAttachment({
			{
				name = "VoidCloudParticles",
				texture = VOID_CLOUD_TEX,
				rate = 5,
				lifetime = NumberRange.new(2.5, 2.5),
				speed = NumberRange.new(1, 1),
				spreadAngle = Vector2.new(1000, 1000),
				size = VOID_CLOUD_SIZE,
				transparency = NumberSequence.new(0.4),
				lockedToPart = false,
				velocityInheritance = 0,
				lightEmission = 0,
				shape = Enum.ParticleEmitterShape.Box,
				shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			},
			{
				name = "VoidBubbleParticles",
				texture = VOID_BUBBLE_TEX,
				rate = 10,
				lifetime = NumberRange.new(2.5, 2.5),
				speed = NumberRange.new(0, 0),
				spreadAngle = Vector2.new(0, 0),
				size = VOID_BUBBLE_SIZE,
				transparency = NumberSequence.new(0.95),
				lockedToPart = false,
				velocityInheritance = 0,
				lightEmission = 0,
				shape = Enum.ParticleEmitterShape.Box,
				shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
			},
	})
end

local function dawnBlessedAttachment(): {[string]: any}
	return studioAttachment({
		{
			name = "ParticleEmitter",
			texture = DAWN_BLESSED_TEX,
			color = ColorSequence.new(Color3.fromRGB(182, 131, 28)),
			rate = 20,
			lifetime = NumberRange.new(5, 5),
			speed = NumberRange.new(0.01, 0.01),
			spreadAngle = Vector2.new(360, 360),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 5.39),
			}),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 1,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
	})
end

local function fogShroudedAttachment(): {[string]: any}
	return studioAttachment({
		{
			name = "ParticleEmitter",
			texture = FOG_SHROUDED_TEX,
			color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			rate = 30,
			lifetime = NumberRange.new(4, 4),
			speed = NumberRange.new(0.01, 0.01),
			spreadAngle = Vector2.new(360, 360),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 4.52),
			}),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.88),
				NumberSequenceKeypoint.new(1, 1),
			}),
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 1,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
	})
end

local function prismaticAttachment(): {[string]: any}
	return studioAttachment({
		{
			name = "ParticleEmitter",
			texture = PRISMATIC_TEX,
			color = ColorSequence.new(Color3.fromRGB(14, 255, 235)),
			rate = 20,
			lifetime = NumberRange.new(5, 5),
			speed = NumberRange.new(0.01, 0.01),
			spreadAngle = Vector2.new(360, 360),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 16.2),
			}),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			}),
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 1,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
	})
end

local function shinyAttachment(): {[string]: any}
	return studioAttachment({
		{
			name = "ParticleEmitter",
			texture = SHINY_TEX,
			color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			rate = 20,
			lifetime = NumberRange.new(1, 1),
			speed = NumberRange.new(0.01, 0.01),
			spreadAngle = Vector2.new(0, 0),
			rotSpeed = NumberRange.new(-360, 360),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 6.375),
				NumberSequenceKeypoint.new(0.149, 2.56),
				NumberSequenceKeypoint.new(0.401, 0.625),
				NumberSequenceKeypoint.new(1, 0),
			}),
			transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.056, 0.512),
				NumberSequenceKeypoint.new(0.098, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 1,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
	})
end

local function infernoAttachment(): {[string]: any}
	return studioAttachment({
		{
			name = "Fire-01",
			texture = INFERNO_FIRE_TEX,
			color = ColorSequence.new(Color3.fromRGB(255, 124, 91)),
			rate = 10,
			lifetime = NumberRange.new(0.5, 0.5),
			speed = NumberRange.new(1.5, 1.5),
			spreadAngle = Vector2.new(360, 360),
			rotSpeed = NumberRange.new(-30, 30),
			size = NumberSequence.new(2),
			transparency = INFERNO_FIRE_TRANSPARENCY,
			drag = 5,
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 0,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
		{
			name = "Fire-02",
			texture = INFERNO_FIRE_TEX,
			color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
			rate = 10,
			lifetime = NumberRange.new(0.5, 0.5),
			speed = NumberRange.new(1.5, 1.5),
			spreadAngle = Vector2.new(360, 360),
			rotSpeed = NumberRange.new(-30, 30),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.94),
				NumberSequenceKeypoint.new(1, 2.5),
			}),
			transparency = INFERNO_FIRE_TRANSPARENCY,
			drag = 5,
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 0,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
		{
			name = "Glow",
			texture = INFERNO_EMBER_TEX,
			color = ColorSequence.new(Color3.fromRGB(255, 90, 14)),
			rate = 50,
			lifetime = NumberRange.new(0.5, 1),
			speed = NumberRange.new(0, 0),
			spreadAngle = Vector2.new(0, 0),
			acceleration = Vector3.new(0, 5, 0),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 2.125),
				NumberSequenceKeypoint.new(1, 1),
			}),
			transparency = INFERNO_FIRE_TRANSPARENCY,
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 0,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
		{
			name = "Specks",
			texture = INFERNO_EMBER_TEX,
			color = ColorSequence.new(Color3.fromRGB(255, 129, 19)),
			rate = 100,
			lifetime = NumberRange.new(0.375, 0.625),
			speed = NumberRange.new(11, 11),
			spreadAngle = Vector2.new(100, 100),
			rotSpeed = NumberRange.new(-45, 45),
			acceleration = Vector3.new(0, -15, 0),
			size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.125),
				NumberSequenceKeypoint.new(1, 0),
			}),
			transparency = INFERNO_FIRE_TRANSPARENCY,
			drag = 5,
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 0,
			shape = Enum.ParticleEmitterShape.Box,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		},
	})
end

local SHOCKED_BURST_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.057, 1.333),
	NumberSequenceKeypoint.new(0.131, 1.278),
	NumberSequenceKeypoint.new(0.202, 0.833),
	NumberSequenceKeypoint.new(0.272, 1.556),
	NumberSequenceKeypoint.new(0.342, 0.722),
	NumberSequenceKeypoint.new(0.404, 0.944),
	NumberSequenceKeypoint.new(0.481, 0),
	NumberSequenceKeypoint.new(0.553, 0.833),
	NumberSequenceKeypoint.new(0.606, 0),
	NumberSequenceKeypoint.new(0.692, 0.667),
	NumberSequenceKeypoint.new(0.769, 0.278),
	NumberSequenceKeypoint.new(0.832, 1.111),
	NumberSequenceKeypoint.new(0.898, 0.389),
	NumberSequenceKeypoint.new(1, 1),
})

local function shockedElectricBurst(): {[string]: any}
	return studioAttachment({
			{
				texture = ELECTRIC_BURST_TEX,
				rate = 5,
				lifetime = NumberRange.new(0.5, 0.5),
				speed = NumberRange.new(0, 0),
				spreadAngle = Vector2.new(360, 360),
				rotSpeed = NumberRange.new(10000, 10000),
				size = SHOCKED_BURST_SIZE,
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 0),
				}),
				lockedToPart = false,
				velocityInheritance = 0,
				lightEmission = 0,
			},
	})
end

local function electricityTrailPair(
	colorA: Color3,
	colorB: Color3,
	blurA: Color3,
	blurB: Color3
): {[string]: any}
	return studioAttachment({
			{
				name = "TrailElectricity",
				texture = TRAIL_ELECTRIC_TEX,
				color = ColorSequence.new(colorA, colorB),
				rate = 50,
				lifetime = NumberRange.new(2, 2),
				speed = NumberRange.new(60, 60),
				spreadAngle = Vector2.new(360, 360),
				rotSpeed = NumberRange.new(-200, 200),
				size = NumberSequence.new(2),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.551, 0),
					NumberSequenceKeypoint.new(0.782, 0.569),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lockedToPart = true,
				velocityInheritance = 0,
				drag = 50,
				lightEmission = 0.3,
			},
			{
				name = "TrailElectricityBlur",
				texture = TRAIL_ELECTRIC_BLUR_TEX,
				color = ColorSequence.new(blurA, blurB),
				rate = 50,
				lifetime = NumberRange.new(2, 2),
				speed = NumberRange.new(60, 60),
				spreadAngle = Vector2.new(360, 360),
				rotSpeed = NumberRange.new(-200, 200),
				size = NumberSequence.new(2),
				transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.856),
					NumberSequenceKeypoint.new(0.533, 0.937),
					NumberSequenceKeypoint.new(1, 1),
				}),
				lockedToPart = true,
				velocityInheritance = 0,
				drag = 50,
				lightEmission = 0.2,
			},
	})
end

local PARTICLE_SIZE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.2, 0.14),
	NumberSequenceKeypoint.new(1, 0),
})

local PARTICLE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.95),
	NumberSequenceKeypoint.new(0.15, 0.1),
	NumberSequenceKeypoint.new(0.85, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})

local function softGlow(
	outline: Color3,
	fill: Color3?,
	outlineT: number?,
	fillT: number?
): {[string]: any}
	return {
		kind = "highlight",
		outlineColor = outline,
		outlineT = outlineT or 0.1,
		fillColor = fill or outline,
		fillT = fillT or 0.8,
	}
end

local function starShimmer(
	color: ColorSequence,
	rate: number?,
	spread: Vector2?
): {[string]: any}
	return {
		kind = "attachedParticle",
		texture = STAR_TEX,
		color = color,
		rate = rate or 10,
		lifetime = NumberRange.new(0.5, 0.9),
		size = PARTICLE_SIZE,
		transparency = PARTICLE_TRANSPARENCY,
		speed = NumberRange.new(0.4, 1.2),
		spreadAngle = spread or Vector2.new(40, 40),
		emissionDirection = Enum.NormalId.Top,
		acceleration = Vector3.new(0, 0.8, 0),
		lightEmission = 0.8,
		lockedToPart = true,
		velocityInheritance = 0.8,
	}
end

local function upwardColumn(
	color: ColorSequence,
	rate: number?,
	speedMin: number?,
	speedMax: number?,
	accelY: number?
): {[string]: any}
	return {
		kind = "attachedParticle",
		texture = STAR_TEX,
		color = color,
		rate = rate or 8,
		lifetime = NumberRange.new(0.5, 0.9),
		size = PARTICLE_SIZE,
		transparency = PARTICLE_TRANSPARENCY,
		speed = NumberRange.new(speedMin or 1.5, speedMax or 3),
		spreadAngle = Vector2.new(28, 28),
		emissionDirection = Enum.NormalId.Top,
		acceleration = Vector3.new(0, accelY or 1.2, 0),
		lightEmission = 0.75,
		lockedToPart = true,
		velocityInheritance = 0.8,
	}
end

-- Preview_radioactive Attachment child (Studio tester) — Cylinder surface burst + green motes.
local RADIOACTIVE_ATTACH_TEX = "rbxassetid://4984018468"

local function radioactivePreviewAttachment(): {[string]: any}
	return studioAttachment({
		{
			name = "ParticleEmitter",
			texture = RADIOACTIVE_ATTACH_TEX,
			color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			rate = 3,
			lifetime = NumberRange.new(1, 1),
			speed = NumberRange.new(10, 10),
			spreadAngle = Vector2.new(0, 0),
			size = NumberSequence.new(0.5),
			transparency = NumberSequence.new(0.7),
			lockedToPart = false,
			velocityInheritance = 0,
			lightEmission = 0,
			lightInfluence = 1,
			drag = 0,
			emissionDirection = Enum.NormalId.Front,
			shape = Enum.ParticleEmitterShape.Cylinder,
			shapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		},
	})
end

local function moonOrbitOrbs(): {[string]: any}
	return {
		kind = "orbitOrbs",
		count = 4,
		radius = 1.75,
		size = 0.24,
		color = Color3.fromRGB(255, 252, 220),
		periodSec = 5.5,
		heightOffset = 0.35,
	}
end

local function radiateParticles(
	color: ColorSequence,
	rate: number?,
	speedMin: number?,
	speedMax: number?
): {[string]: any}
	return {
		kind = "attachedParticle",
		texture = STAR_TEX,
		color = color,
		rate = rate or 12,
		lifetime = NumberRange.new(0.5, 0.9),
		size = PARTICLE_SIZE,
		transparency = PARTICLE_TRANSPARENCY,
		speed = NumberRange.new(speedMin or 1, speedMax or 2.5),
		spreadAngle = Vector2.new(180, 180),
		emissionDirection = Enum.NormalId.Top,
		lightEmission = 0.85,
		lockedToPart = true,
		velocityInheritance = 0.8,
	}
end

local function downwardMotes(
	color: ColorSequence,
	rate: number?,
	accelY: number?
): {[string]: any}
	return {
		kind = "attachedParticle",
		texture = STAR_TEX,
		color = color,
		rate = rate or 7,
		lifetime = NumberRange.new(0.6, 1.0),
		size = PARTICLE_SIZE,
		transparency = PARTICLE_TRANSPARENCY,
		speed = NumberRange.new(0.3, 0.8),
		spreadAngle = Vector2.new(35, 35),
		emissionDirection = Enum.NormalId.Top,
		acceleration = Vector3.new(0, accelY or -2.5, 0),
		lightEmission = 0.7,
		lockedToPart = true,
		velocityInheritance = 0.8,
	}
end

local function glassShell(
	scale: number,
	color: Color3,
	transparency: number?
): {[string]: any}
	return {
		kind = "shell",
		shape = "mesh",
		scale = scale,
		material = Enum.Material.Glass,
		color = color,
		transparency = transparency or 0.5,
	}
end

local function rainbowArchBeam(): {[string]: any}
	return {
		kind = "beam",
		offsetA = Vector3.new(-2.4, 1.0, 0),
		offsetB = Vector3.new(2.4, 1.0, 0),
		width0 = 0.28, width1 = 0.28, segments = 16, curveSize = 1.4,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,  80, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220,  80)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(120, 255, 140)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(100, 180, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(220, 120, 255)),
		}),
	}
end

-- ====================================================================
-- ROLL-ELIGIBLE
-- ====================================================================

-- Metal preview: material + tint only (no halo, light, or particles).
M.golden = {
	{ kind = "materialLock", material = Enum.Material.Foil, reflectance = 0.88 },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 215, 55) },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 200, 90), range = 5, brightness = 1.4 },
}

-- Tester look: (1) hue cycle on mesh (2) soft halo + rainbow motes — no arch beam strip.
M.rainbow = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "hueRotate", periodSec = 2.2, saturation = 1.0, value = 1.0 },
	softGlow(Color3.new(1, 1, 1), Color3.new(1, 1, 1), 0.12, 0.38),
	{ kind = "pointLight",   color = Color3.fromRGB(255, 240, 255), range = 6, brightness = 1.2 },
	{
		kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 120, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 120)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(120, 255, 160)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 200, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(220, 140, 255)),
		}),
		rate = 5,
		lifetime = NumberRange.new(0.5, 0.9),
		size = PARTICLE_SIZE,
		transparency = PARTICLE_TRANSPARENCY,
		speed = NumberRange.new(0.5, 1.2),
		spreadAngle = Vector2.new(30, 30),
		emissionDirection = Enum.NormalId.Top,
		lightEmission = 0.7,
		lockedToPart = true,
	},
}

-- Metal preview: material + tint only.
M.silver = {
	{ kind = "materialLock", material = Enum.Material.Foil, reflectance = 0.48 },
	{ kind = "tintLock",     color = Color3.fromRGB(220, 228, 240) },
}

M.frozen = {
	electricityTrailPair(
		Color3.fromRGB(42, 98, 255),
		Color3.fromRGB(105, 255, 255),
		Color3.fromRGB(82, 128, 255),
		Color3.fromRGB(142, 221, 255)
	),
}

M.inferno = {
	infernoAttachment(),
}

M.shocked = {
	shockedElectricBurst(),
}

M.radioactive = {
	radioactivePreviewAttachment(),
}

M.crystal = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 220, 255) },
	glassShell(1.12, Color3.fromRGB(200, 230, 255), 0.48),
	softGlow(Color3.fromRGB(220, 240, 255), Color3.fromRGB(200, 230, 255), 0.1, 0.8),
	{ kind = "pointLight",   color = Color3.fromRGB(200, 230, 255), range = 7, brightness = 1.8 },
	upwardColumn(ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(160, 210, 255)), 7, 2, 3),
}

M.colossal = {
	{ kind = "modelScale", scale = _bodyScale.colossal or 1.45 },
}

M.tiny = {
	{ kind = "modelScale", scale = _bodyScale.tiny or 0.65 },
}

M.bloodlust = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "lerpLoop", periodSec = 1.1, palette = {
		Color3.fromRGB(200, 30, 30),
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(140, 0, 0),
	} },
	softGlow(Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 30, 30), 0.1, 0.8),
	{ kind = "pointLight",   color = Color3.fromRGB(255, 40, 40), range = 7, brightness = 2.0 },
	{ kind = "fire",         size = 3, heat = 4,
		color = Color3.fromRGB(255, 50, 50), secondaryColor = Color3.fromRGB(100, 0, 0) },
	upwardColumn(ColorSequence.new(Color3.fromRGB(255, 120, 120), Color3.fromRGB(200, 30, 30)), 7),
}

M.voidtouched = {
	voidPreviewAttachment(),
}

M.ghostly = {
	{ kind = "transparency", value = 0.5 },
	{ kind = "tintLock",     color = Color3.fromRGB(220, 235, 255) },
	glassShell(1.15, Color3.fromRGB(230, 245, 255), 0.62),
	softGlow(Color3.fromRGB(240, 250, 255), Color3.fromRGB(220, 235, 255), 0.15, 0.75),
	{ kind = "pointLight",   color = Color3.fromRGB(220, 235, 255), range = 6, brightness = 1.4 },
	upwardColumn(ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 215, 255)), 6, 0.8, 1.5, 0.8),
}

M.disco = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "flicker", periodSec = 0.35, palette = {
		Color3.fromRGB(255,  60, 200),
		Color3.fromRGB( 60, 200, 255),
		Color3.fromRGB(255, 240,  80),
		Color3.fromRGB(120, 255, 120),
		Color3.fromRGB(255, 140,  40),
	} },
	softGlow(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255), 0.08, 0.82),
	{ kind = "pointLight",   color = Color3.fromRGB(255, 200, 255), range = 7, brightness = 1.6 },
	rainbowArchBeam(),
}

M.ancientcore = {
	{ kind = "materialLock", material = Enum.Material.Sand },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 130, 60) },
	softGlow(Color3.fromRGB(220, 170, 90), Color3.fromRGB(220, 170, 90), 0.12, 0.8),
	{ kind = "pointLight",   color = Color3.fromRGB(220, 170, 90), range = 6, brightness = 1.6 },
	upwardColumn(ColorSequence.new(Color3.fromRGB(230, 200, 140), Color3.fromRGB(160, 110, 60)), 7, 1, 2, 0.8),
}

-- ====================================================================
-- WORLD-STATE
-- ====================================================================

M.tide_kissed = {
	{ kind = "materialLock", material = Enum.Material.Glass },
	{ kind = "tintLock",     color = Color3.fromRGB(120, 230, 220) },
	{ kind = "transparency", value = 0.15 },
	softGlow(Color3.fromRGB(90, 220, 210), Color3.fromRGB(90, 220, 210), 0.1, 0.8),
	{ kind = "pointLight",   color = Color3.fromRGB(90, 230, 220), range = 7, brightness = 1.8 },
	downwardMotes(ColorSequence.new(Color3.fromRGB(180, 240, 235), Color3.fromRGB(70, 200, 200)), 8, -1.8),
}

-- Tester look: (1) purple storm halo (2) radiating motes — no horizontal beam strips.
M.storm_forged = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(70, 70, 160) },
	softGlow(Color3.fromRGB(160, 150, 255), Color3.fromRGB(120, 110, 220), 0.1, 0.52),
	{ kind = "pointLight",   color = Color3.fromRGB(170, 120, 255), range = 7, brightness = 1.8 },
	electricityTrailPair(
		Color3.fromRGB(100, 80, 220),
		Color3.fromRGB(180, 160, 255),
		Color3.fromRGB(120, 100, 240),
		Color3.fromRGB(160, 140, 255)
	),
}

M.moon_touched = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(210, 220, 255) },
	glassShell(1.14, Color3.fromRGB(230, 235, 255), 0.46),
	softGlow(Color3.fromRGB(255, 252, 240), Color3.fromRGB(220, 230, 255), 0.1, 0.5),
	{ kind = "pointLight",   color = Color3.fromRGB(240, 245, 255), range = 7, brightness = 1.8 },
	moonOrbitOrbs(),
	starShimmer(ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 225, 255)), 5),
}

M.dawn_blessed = {
	dawnBlessedAttachment(),
}

M.fog_shrouded = {
	fogShroudedAttachment(),
}

-- ====================================================================
-- DEPRECATED
-- ====================================================================

M.shiny = {
	shinyAttachment(),
}
M.giant     = M.colossal
M.glowing   = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(240, 245, 255) },
	softGlow(Color3.fromRGB(225, 235, 255), Color3.fromRGB(225, 235, 255), 0.1, 0.82),
	{ kind = "pointLight",   color = Color3.fromRGB(225, 235, 255), range = 6, brightness = 1.6 },
	starShimmer(ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 230, 255)), 8),
}
M.lucky     = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(160, 230, 160) },
	softGlow(Color3.fromRGB(120, 220, 120), Color3.fromRGB(120, 220, 120), 0.12, 0.8),
	{ kind = "pointLight",   color = Color3.fromRGB(120, 220, 120), range = 6, brightness = 1.6 },
	starShimmer(ColorSequence.new(Color3.fromRGB(200, 255, 200), Color3.fromRGB(120, 220, 120)), 8),
}
M.ancient   = M.ancientcore
M.prismatic = {
	prismaticAttachment(),
}
M.elder     = M.voidtouched
M.cursed    = M.bloodlust
M.magnetic  = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(150, 220, 240) },
	softGlow(Color3.fromRGB(80, 200, 230), Color3.fromRGB(80, 200, 230), 0.1, 0.8),
	{ kind = "pointLight",   color = Color3.fromRGB(80, 200, 230), range = 6, brightness = 1.6 },
	radiateParticles(ColorSequence.new(Color3.fromRGB(180, 240, 255), Color3.fromRGB(80, 200, 230)), 8),
}
M.barnacled = {
	{ kind = "materialLock", material = Enum.Material.Rock },
	{ kind = "tintLock",     color = Color3.fromRGB(150, 160, 130) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 110, 90), outlineT = 0.2, fillT = 1 },
}

return M
