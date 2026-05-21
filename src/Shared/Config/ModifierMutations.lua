--!strict
-- ModifierMutations.lua
-- Per-modifier visual treatment for held fish (Grow-a-Garden-style).
--
-- Design philosophy (read this before tuning):
--   The MUTATION should make the fish look mutated — not blanket the camera in
--   particles or wash the screen in volumetric light. GAG keeps the pet
--   silhouette readable through every mutation. We do the same:
--
--     1. Identity comes from the MESH (tintLock / materialLock / colorCycle).
--        These are the loudest, most efficient signal — "this fish is gold"
--        is sold by the gold tint on the body, not by a halo of sparkles.
--     2. The HIGHLIGHT is outline-dominant. outlineT ≈ 0.05–0.2 (visible),
--        fillT ≈ 0.85–0.95 (almost invisible). Yields the classic GAG
--        "outlined glow" without flooding the player's view.
--     3. PointLights are SMALL. range 4–8, brightness 1.0–2.0. Neon mesh
--        already glows on its own; the PointLight is just spill onto nearby
--        surfaces. Anything larger reads as "spotlight" not "magic fish".
--     4. ONE attachedParticle layer, low rate (8–15), small size (peak
--        0.15–0.3), short lifetime (0.4–1.0), gentle upward drift. Never
--        spreadAngle 180,180 with rate 50 — that's the cloud-cloud failure.
--     5. The built-in Roblox `Sparkles` class is BANNED. It cannot be tuned
--        for density and instantly reads as "Roblox 2008". Use attachedParticle.
--     6. `Smoke` is reserved for fog_shrouded only — it fogs the player's view.
--     7. `Fire` is small (size 2–3, heat 3–5). Larger reads as combat VFX,
--        which we don't have (cozy game, see CLAUDE.md design pillars).
--
-- Engine contract (see FishMutations.lua) — each entry is an array of effect
-- tables applied in this order:
--
--   tintLock     { color: Color3 }
--                  Locks part.Color (snapshotted for restore).
--
--   materialLock { material: Enum.Material }
--                  Locks part.Material (snapshotted).
--
--   transparency { value: number }
--                  Static transparency (snapshotted).
--
--   colorCycle   { mode: "hueRotate" | "lerpLoop" | "flicker",
--                  periodSec: number,
--                  palette: {Color3}?,        -- required for lerpLoop / flicker
--                  saturation: number?,       -- hueRotate only (default 0.85)
--                  value: number? }           -- hueRotate only (default 1.0)
--                  Animated part.Color via Heartbeat. Skipped under ReducedMotion.
--
--   pulseTransparency { min: number, max: number, periodSec: number }
--                       Sine pulse on Transparency. Skipped under ReducedMotion.
--
--   highlight    { fillColor: Color3?, fillT: number?,
--                  outlineColor: Color3?, outlineT: number?,
--                  flickerHz: number? }
--                  Single Highlight per part — successive entries MERGE.
--
--   pointLight   { color: Color3, range: number, brightness: number,
--                  flickerHz: number? }
--                  Single PointLight per part. Skipped in viewport mode.
--
--   shell        { shape: "mesh" | "cube"?, scale: number?, padding: number?,
--                  material: Enum.Material?, color: Color3?,
--                  transparency: number?, reflectance: number? }
--                  Wrapper part around the fish (mesh-shaped or cube).
--
--   decal        { texture: string, faces: {Enum.NormalId}?, color: Color3?,
--                  transparency: number?, zIndex: number? }
--                  Decal on requested faces (default = all 6).
--
--   attachedParticle { texture: string?, color: ColorSequence,
--                      rate: number, lifetime: NumberRange, size: NumberSequence,
--                      speed: NumberRange?, spreadAngle: Vector2?,
--                      rotation/rotSpeed/acceleration/lightEmission/
--                      lightInfluence/emissionDirection: opt }
--                      Localised ParticleEmitter on the anchor. Suppressed in
--                      viewport mode. Reduced motion sets rate=0.
--
-- Effect application order (sorted automatically inside FishMutations):
--   materialLock(1) → tintLock(2) → transparency(3) → colorCycle(4) →
--   pulseTransparency(5) → highlight(6) → pointLight(7) → shell(8) →
--   decal(9) → attachedParticle(10) → fire(11) → smoke(12) → sparkles(13) →
--   beam(14)
--
-- Stable IDs forever (CLAUDE.md). Legacy entries kept so old inventory
-- items still render visuals even though their dropChance is now 0.

local M = {}

-- ====================================================================
-- Shared particle texture — standard Roblox sparkle/star texture.
-- Same id everywhere keeps engine batching efficient.
-- ====================================================================
local SPARKLE_TEX = "rbxassetid://6282433556"

-- ====================================================================
-- NEW SET — roll-eligible (matches GameConfig.FishModifiers entries with
-- dropChance > 0). Designed against the GAG mutation visual language.
-- ====================================================================

-- Rainbow: Neon mesh smoothly hue-cycles across the spectrum. Soft white
-- outline. Single tiny rainbow particle drift. The MESH is the rainbow,
-- not a particle storm.
M.rainbow = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "hueRotate", periodSec = 2.2, saturation = 1.0, value = 1.0 },
	{ kind = "highlight",    outlineColor = Color3.new(1, 1, 1), outlineT = 0.1,
		fillColor = Color3.new(1, 1, 1), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 220, 255), range = 6, brightness = 1.5 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 120, 120)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 120)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(120, 255, 160)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 200, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(220, 140, 255)),
		}),
		rate     = 10,
		lifetime = NumberRange.new(0.6, 1.0),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.3, 0.8),
		spreadAngle = Vector2.new(70, 70),
		rotation    = NumberRange.new(0, 360),
		rotSpeed    = NumberRange.new(-120, 120),
		acceleration = Vector3.new(0, 1.2, 0),
		lightEmission = 1.0,
	},
}

-- Golden: Neon-gold body + soft gold outline + small warm PointLight + a
-- single tasteful particle drift. No shell (was creating a doubled silhouette)
-- and no second particle layer (was the blinding cloud).
M.golden = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 200, 40) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 230, 110), outlineT = 0.1,
		fillColor = Color3.fromRGB(255, 215, 80), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 210, 90), range = 6, brightness = 1.6 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(255, 245, 180), Color3.fromRGB(255, 200, 40)),
		rate     = 10,
		lifetime = NumberRange.new(0.6, 1.0),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.3, 0.8),
		spreadAngle = Vector2.new(70, 70),
		rotation    = NumberRange.new(0, 360),
		rotSpeed    = NumberRange.new(-180, 180),
		acceleration = Vector3.new(0, 1.0, 0),
		lightEmission = 1.0,
	},
}

-- Silver: Foil mesh (already reflective on its own) + cool silver tint +
-- thin silver outline. No shell, no PointLight (Foil reflects ambient light
-- naturally), no sparkles cloud — the polished metal IS the look.
M.silver = {
	{ kind = "materialLock", material = Enum.Material.Foil },
	{ kind = "tintLock",     color = Color3.fromRGB(220, 228, 240) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(245, 250, 255), outlineT = 0.1,
		fillColor = Color3.fromRGB(225, 235, 250), fillT = 0.92 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 225, 245)),
		rate     = 8,
		lifetime = NumberRange.new(0.5, 0.9),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.2, 0.6),
		spreadAngle = Vector2.new(70, 70),
		rotation    = NumberRange.new(0, 360),
		rotSpeed    = NumberRange.new(-200, 200),
		acceleration = Vector3.new(0, 0.8, 0),
		lightEmission = 1.0,
	},
}

-- Frozen: fish encased in a translucent cube of Ice (the signature look) +
-- small cool PointLight + a few faint frost specks around the cube.
M.frozen = {
	{ kind = "shell",        shape = "cube", padding = 1.2,
		material = Enum.Material.Ice, color = Color3.fromRGB(195, 230, 255),
		transparency = 0.35, reflectance = 0.45 },
	{ kind = "pointLight",   color = Color3.fromRGB(170, 220, 255), range = 6, brightness = 1.4 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(220, 240, 255), Color3.fromRGB(160, 210, 245)),
		rate     = 8,
		lifetime = NumberRange.new(0.8, 1.4),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.35, 0.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.1, 0.4),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, -0.5, 0),  -- gentle fall (frost dust)
		lightEmission = 0.9,
	},
}

-- Inferno: small contained fire on the fish + warm tint + warm spill light.
-- No smoke (was fogging the camera), no oversized Fire (size 8 was huge).
M.inferno = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 110, 30) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 170, 70), outlineT = 0.1,
		fillColor = Color3.fromRGB(255, 120, 40), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 130, 50), range = 8, brightness = 1.8 },
	{ kind = "fire",         size = 3, heat = 5,
		color = Color3.fromRGB(255, 170, 50), secondaryColor = Color3.fromRGB(200, 50, 10) },
}

-- Shocked: electric-yellow body + steady bright outline + a few quick spark
-- specks (not a 55-rate explosion). Steady, not flickering (epilepsy risk).
M.shocked = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 240, 130) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 240, 80), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 250, 180), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 240, 110), range = 6, brightness = 1.5 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(255, 255, 220), Color3.fromRGB(255, 230, 80)),
		rate     = 14,
		lifetime = NumberRange.new(0.2, 0.4),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(1.5, 3.5),
		spreadAngle = Vector2.new(180, 180),
		rotation    = NumberRange.new(0, 360),
		rotSpeed    = NumberRange.new(-400, 400),
		lightEmission = 1.0, lightInfluence = 0.0,
	},
}

-- Radioactive: glowing Neon green body that gently pulses + faint green halo.
-- No more triple-stacked fire+smoke+sparkles — the pulsing neon IS the toxic
-- read.
M.radioactive = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(160, 255, 80) },
	{ kind = "pulseTransparency", min = 0, max = 0.18, periodSec = 1.4 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(150, 255, 90), outlineT = 0.1,
		fillColor = Color3.fromRGB(150, 255, 90), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(150, 255, 90), range = 8, brightness = 2.0 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(220, 255, 180), Color3.fromRGB(140, 255, 80)),
		rate     = 10,
		lifetime = NumberRange.new(0.6, 1.0),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.3, 0.7),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 1.0, 0),
		lightEmission = 1.0,
	},
}

-- Crystal: Glass cube shell wraps a Neon-glowing core fish. The cube itself
-- is the signature; no sparkle storm needed inside it.
M.crystal = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 220, 255) },
	{ kind = "shell",        shape = "cube", padding = 0.8,
		material = Enum.Material.Glass, color = Color3.fromRGB(200, 230, 255),
		transparency = 0.45, reflectance = 0.7 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(220, 240, 255), outlineT = 0.1,
		fillColor = Color3.fromRGB(200, 230, 255), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(200, 230, 255), range = 7, brightness = 1.8 },
}

-- Colossal: deep Neon green body + green halo + slow heavy particles drifting
-- DOWN (visual weight cue — this fish is HEAVY). No smoke cloud.
M.colossal = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(80, 200, 100) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 255, 130), outlineT = 0.1,
		fillColor = Color3.fromRGB(90, 220, 110), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(120, 255, 110), range = 8, brightness = 1.8 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(180, 255, 180), Color3.fromRGB(90, 220, 110)),
		rate     = 8,
		lifetime = NumberRange.new(0.8, 1.4),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.28),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.2, 0.5),
		spreadAngle = Vector2.new(160, 160),
		acceleration = Vector3.new(0, -1.4, 0),  -- heavy: motes fall
		lightEmission = 0.9,
	},
}

-- Tiny: pristine neon-white body + a clean white outline + a tiny PointLight.
-- The CLEANNESS of a tiny mutation is the look — no sparkle blizzard needed.
M.tiny = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 255, 255) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 255, 255), outlineT = 0.1,
		fillColor = Color3.fromRGB(255, 255, 255), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 255, 255), range = 4, brightness = 1.2 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 230, 255)),
		rate     = 8,
		lifetime = NumberRange.new(0.3, 0.6),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.14),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.2, 0.6),
		spreadAngle = Vector2.new(140, 140),
		rotation    = NumberRange.new(0, 360),
		rotSpeed    = NumberRange.new(-300, 300),
		lightEmission = 1.0,
	},
}

-- Bloodlust: pulsing red Neon body (signature look) + small red fire + small
-- red halo. Drop smoke — the pulse already screams "danger".
M.bloodlust = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "lerpLoop", periodSec = 1.1, palette = {
		Color3.fromRGB(200, 30, 30),
		Color3.fromRGB(255, 80, 80),
		Color3.fromRGB(140, 0, 0),
	} },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 60, 60), outlineT = 0.1,
		fillColor = Color3.fromRGB(255, 30, 30), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 40, 40), range = 7, brightness = 1.8 },
	{ kind = "fire",         size = 2, heat = 4,
		color = Color3.fromRGB(255, 50, 50), secondaryColor = Color3.fromRGB(100, 0, 0) },
}

-- Voidtouched: near-black Neon body + purple halo + small upward void wisps.
-- Drop fire (was too loud), drop smoke, drop sparkles.
M.voidtouched = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(30, 8, 60) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(200, 120, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(140, 60, 220), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(180, 90, 255), range = 8, brightness = 1.8 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(220, 160, 255), Color3.fromRGB(100, 40, 200)),
		rate     = 10,
		lifetime = NumberRange.new(0.8, 1.2),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.22),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.2, 0.6),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 0.6, 0),
		lightEmission = 1.0,
	},
}

-- Ghostly: half-transparent fish + soft white halo + slow upward wisps.
-- Was already restrained; just nudge the particle rate slightly down.
M.ghostly = {
	{ kind = "transparency", value = 0.5 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(240, 250, 255), outlineT = 0.2,
		fillColor = Color3.fromRGB(220, 235, 255), fillT = 0.85 },
	{ kind = "pointLight",   color = Color3.fromRGB(220, 235, 255), range = 6, brightness = 1.4 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color    = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 215, 255)),
		rate     = 12,
		lifetime = NumberRange.new(1.2, 2.0),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.4),
			NumberSequenceKeypoint.new(0.8, 0.3),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.2, 0.6),
		spreadAngle = Vector2.new(60, 60),
		acceleration = Vector3.new(0, 1.8, 0),
		emissionDirection = Enum.NormalId.Top,
		lightEmission = 1.0,
	},
}

-- Disco: Neon flicker color cycle + a thin multicolor arc beam above the fish.
-- Dropped Sparkles. Color cycle is slower (was 0.2s — hit the 3-changes-per-sec
-- accessibility ceiling).
M.disco = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "flicker", periodSec = 0.35, palette = {
		Color3.fromRGB(255,  60, 200),
		Color3.fromRGB( 60, 200, 255),
		Color3.fromRGB(255, 240,  80),
		Color3.fromRGB(120, 255, 120),
		Color3.fromRGB(255, 140,  40),
	} },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 255, 255), outlineT = 0.1,
		fillColor = Color3.fromRGB(255, 255, 255), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 200, 255), range = 8, brightness = 2.0 },
	{ kind = "beam",
		offsetA = Vector3.new(-2.2, 0.8, 0), offsetB = Vector3.new(2.2, 0.8, 0),
		width0 = 0.25, width1 = 0.25, segments = 14, curveSize = 1.2,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,  60, 200)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB( 60, 200, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 240,  80)),
		}),
	},
}

-- Ancient core: Sand body (signature) + bronze halo + slow dust drift.
-- Drop the smoke wall, drop sparkles.
M.ancientcore = {
	{ kind = "materialLock", material = Enum.Material.Sand },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 130, 60) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(220, 170, 90), outlineT = 0.1,
		fillColor = Color3.fromRGB(220, 170, 90), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(220, 170, 90), range = 5, brightness = 1.2 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(230, 200, 140), Color3.fromRGB(160, 110, 60)),
		rate     = 8,
		lifetime = NumberRange.new(1.0, 1.8),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.18),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.1, 0.3),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 0.4, 0),
		lightEmission = 0.8,
	},
}

-- ====================================================================
-- WORLD-STATE MODIFIERS — server-assigned by tide/weather/time, not rolled.
-- Stable IDs referenced in src/Server/Services/FishingService.lua:607–619.
-- ====================================================================

-- Tide-Kissed: Glass body + cyan tint + soft cyan mist particles.
M.tide_kissed = {
	{ kind = "materialLock", material = Enum.Material.Glass },
	{ kind = "tintLock",     color = Color3.fromRGB(120, 230, 220) },
	{ kind = "transparency", value = 0.15 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(90, 220, 210), outlineT = 0.1,
		fillColor = Color3.fromRGB(90, 220, 210), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(90, 230, 220), range = 6, brightness = 1.5 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(180, 240, 235), Color3.fromRGB(70, 200, 200)),
		rate     = 10,
		lifetime = NumberRange.new(0.7, 1.2),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.2, 0.5),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 0.8, 0),
		lightEmission = 1.0,
	},
}

-- Storm-Forged: Neon storm-purple body + the two electric Beam arcs that are
-- the signature read for this mod. Drop smoke + sparkles cloud.
M.storm_forged = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(70, 70, 160) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(180, 180, 255), outlineT = 0.1,
		fillColor = Color3.fromRGB(140, 140, 230), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(170, 170, 255), range = 7, brightness = 1.7 },
	{ kind = "beam",
		offsetA = Vector3.new(-2, 0.7, 0), offsetB = Vector3.new(2, 0.7, 0),
		width0 = 0.18, width1 = 0.18, segments = 14, curveSize = 1.6,
		color = ColorSequence.new(Color3.fromRGB(220, 220, 255), Color3.fromRGB(150, 150, 255)),
	},
	{ kind = "beam",
		offsetA = Vector3.new(-2, -0.7, 0), offsetB = Vector3.new(2, -0.7, 0),
		width0 = 0.15, width1 = 0.15, segments = 14, curveSize = -1.4,
		color = ColorSequence.new(Color3.fromRGB(200, 200, 255), Color3.fromRGB(130, 130, 240)),
	},
}

-- Moon-Touched: silvery Neon + thin glass shell. Drop smoke + sparkles.
M.moon_touched = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(210, 220, 255) },
	{ kind = "shell",        scale = 1.06, material = Enum.Material.Glass,
		color = Color3.fromRGB(230, 235, 255), transparency = 0.45, reflectance = 0.55 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(230, 240, 255), outlineT = 0.1,
		fillColor = Color3.fromRGB(210, 220, 255), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(210, 225, 255), range = 6, brightness = 1.6 },
}

-- Dawn-Blessed: warm Neon body + small sunrise flame + soft warm halo.
-- Drop smoke + sparkles, shrink fire.
M.dawn_blessed = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 190, 110) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 200, 110), outlineT = 0.1,
		fillColor = Color3.fromRGB(255, 200, 120), fillT = 0.88 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 200, 120), range = 7, brightness = 1.7 },
	{ kind = "fire",         size = 2, heat = 3,
		color = Color3.fromRGB(255, 230, 150), secondaryColor = Color3.fromRGB(255, 140, 60) },
}

-- Fog-Shrouded: this one IS supposed to be misty, but we still cap the
-- density. Half-transparent fish + faint gray outline + a few slow gray wisps.
-- This is the ONE modifier that keeps a smoke-adjacent feel intentionally.
M.fog_shrouded = {
	{ kind = "transparency", value = 0.4 },
	{ kind = "tintLock",     color = Color3.fromRGB(190, 200, 215) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(225, 232, 240), outlineT = 0.35,
		fillT = 0.95 },
	{ kind = "attachedParticle",
		texture = SPARKLE_TEX,
		color   = ColorSequence.new(Color3.fromRGB(220, 230, 240), Color3.fromRGB(170, 185, 200)),
		rate     = 12,
		lifetime = NumberRange.new(1.2, 2.0),
		size     = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.5),
			NumberSequenceKeypoint.new(0.8, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		speed       = NumberRange.new(0.1, 0.3),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 0.3, 0),
		lightEmission = 0.6,
	},
}

-- ====================================================================
-- DEPRECATED (dropChance = 0) — kept so legacy inventory items render.
-- Each maps to a flavor close to a current modifier.
-- ====================================================================

M.shiny     = M.golden       -- golden visual
M.giant     = M.colossal
M.glowing   = {              -- pale white glow
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(240, 245, 255) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(225, 235, 255), outlineT = 0.15,
		fillColor = Color3.fromRGB(225, 235, 255), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(225, 235, 255), range = 5, brightness = 1.2 },
}
M.lucky     = {              -- soft green
	{ kind = "tintLock",     color = Color3.fromRGB(160, 230, 160) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 220, 120), outlineT = 0.15,
		fillColor = Color3.fromRGB(120, 220, 120), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(120, 220, 120), range = 4, brightness = 1.0 },
}
M.ancient   = M.ancientcore
M.prismatic = M.rainbow
M.elder     = M.voidtouched
M.cursed    = M.bloodlust    -- close enough visually
M.magnetic  = {              -- cool cyan steady (no flicker — epilepsy)
	{ kind = "tintLock",     color = Color3.fromRGB(150, 220, 240) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(80, 200, 230), outlineT = 0.15,
		fillColor = Color3.fromRGB(80, 200, 230), fillT = 0.9 },
	{ kind = "pointLight",   color = Color3.fromRGB(80, 200, 230), range = 5, brightness = 1.4 },
}
M.barnacled = {              -- rough rocky body + brown highlight
	{ kind = "materialLock", material = Enum.Material.Rock },
	{ kind = "tintLock",     color = Color3.fromRGB(150, 160, 130) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 110, 90), outlineT = 0.3, fillT = 1 },
}

return M
