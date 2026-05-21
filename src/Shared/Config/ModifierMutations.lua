--!strict
-- ModifierMutations.lua
-- Per-modifier visual treatment for held fish (GAG-style mesh mutations).
-- Each entry is an array of effect tables, applied in order. Each effect kind:
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
--   decal(9) → attachedParticle(10)
--
-- Stable IDs forever (CLAUDE.md). Legacy entries kept so old inventory
-- items still render visuals even though their dropChance is now 0.

local M = {}

-- ====================================================================
-- NEW SET — roll-eligible (matches GameConfig.FishModifiers entries with
-- dropChance > 0). Inspired by Grow a Garden mutation visuals.
-- ====================================================================

-- Rainbow: Neon mesh hue-cycles + rainbow Beam wraps through fish + dense
-- multicolor Sparkles. The whole fish reads as a living rainbow.
M.rainbow = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle", mode = "hueRotate", periodSec = 1.5, saturation = 1.0, value = 1.0 },
	{ kind = "highlight",  outlineColor = Color3.new(1,1,1), outlineT = 0.05,
		fillColor = Color3.new(1,1,1), fillT = 0.5 },
	{ kind = "pointLight", color = Color3.fromRGB(255, 200, 255), range = 14, brightness = 5.0 },
	{ kind = "sparkles",   color = Color3.fromRGB(255, 100, 255) },
	{ kind = "beam",
		offsetA = Vector3.new(-2, 0.5, 0), offsetB = Vector3.new(2, 0.5, 0),
		width0 = 0.6, width1 = 0.6, segments = 16, curveSize = 1.2,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,  60,  60)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200,  60)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB( 60, 255,  60)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB( 60, 200, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(200,  60, 255)),
		}),
	},
}

-- Golden: solid Neon gold body + reflective Foil shell + warm glow + two
-- sparkle layers (slow drifting + fast twinkling).
M.golden = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 200, 20) },
	{ kind = "shell",        scale = 1.06, material = Enum.Material.Foil,
		color = Color3.fromRGB(255, 230, 90), transparency = 0.25, reflectance = 0.6 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 240, 120), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 220, 70), fillT = 0.4 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 210, 80), range = 12, brightness = 4.5 },
	{ kind = "attachedParticle",
		texture = "rbxassetid://6282433556",
		color   = ColorSequence.new(Color3.fromRGB(255, 245, 180), Color3.fromRGB(255, 200, 20)),
		rate    = 25, lifetime = NumberRange.new(1.0, 1.8),
		size    = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 0.7), NumberSequenceKeypoint.new(0.8, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		speed   = NumberRange.new(0.6, 1.8), spreadAngle = Vector2.new(180, 180),
		rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-200, 200),
		acceleration = Vector3.new(0, 1.2, 0),
		lightEmission = 1.0,
	},
	{ kind = "attachedParticle",
		texture = "rbxassetid://6282433556",
		color   = ColorSequence.new(Color3.fromRGB(255, 255, 230), Color3.fromRGB(255, 230, 100)),
		rate    = 50, lifetime = NumberRange.new(0.25, 0.45),
		size    = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.22), NumberSequenceKeypoint.new(1, 0) }),
		speed   = NumberRange.new(0.2, 0.6), spreadAngle = Vector2.new(180, 180),
		rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-400, 400),
		lightEmission = 1.0,
	},
}

-- Silver: chrome Foil shell wraps mesh + bright white Sparkles. Dense
-- reflective shimmer.
M.silver = {
	{ kind = "materialLock", material = Enum.Material.Foil },
	{ kind = "tintLock",     color = Color3.fromRGB(200, 210, 230) },
	{ kind = "shell",        scale = 1.08, material = Enum.Material.Foil,
		color = Color3.fromRGB(240, 245, 255), transparency = 0.2, reflectance = 0.9 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 255, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(220, 230, 255), fillT = 0.55 },
	{ kind = "pointLight",   color = Color3.fromRGB(235, 245, 255), range = 10, brightness = 3.0 },
	{ kind = "sparkles",     color = Color3.fromRGB(220, 235, 255) },
}

-- Frozen: fish encased in a translucent cube of Ice (diamond-case look).
M.frozen = {
	{ kind = "shell",        shape = "cube", padding = 1.2,
		material = Enum.Material.Ice, color = Color3.fromRGB(190, 230, 255),
		transparency = 0.4, reflectance = 0.4 },
	{ kind = "pointLight",   color = Color3.fromRGB(160, 220, 255), range = 10, brightness = 2.5 },
}

-- Inferno: fish is ON FIRE. Roblox Fire instance + orange glow + dark smoke trail.
M.inferno = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 100, 20) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 160, 60), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 100, 20), fillT = 0.5 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 120, 40), range = 16, brightness = 6.0 },
	{ kind = "fire",         size = 8, heat = 12,
		color = Color3.fromRGB(255, 160, 40), secondaryColor = Color3.fromRGB(180, 30, 0) },
	{ kind = "smoke",        size = 2, opacity = 0.45, riseVelocity = 3,
		color = Color3.fromRGB(40, 20, 10) },
}

-- Shocked: electric-yellow body + steady bright outline + heavy spark cloud.
-- No flicker (epilepsy risk).
M.shocked = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 240, 130) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 240, 60), outlineT = 0.0,
		fillColor = Color3.fromRGB(255, 255, 150), fillT = 0.65 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 240, 100), range = 10, brightness = 4.0 },
	{ kind = "attachedParticle",
		texture = "rbxassetid://6282433556",
		color   = ColorSequence.new(Color3.fromRGB(255, 255, 220), Color3.fromRGB(255, 230, 80)),
		rate    = 55, lifetime = NumberRange.new(0.25, 0.5),
		size    = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.3, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		speed   = NumberRange.new(4.0, 9.0), spreadAngle = Vector2.new(180, 180),
		rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-500, 500),
		lightEmission = 1.0, lightInfluence = 0.0,
	},
}

-- Radioactive: glowing Neon green body + thick green smoke + green sparkles +
-- green Fire (toxic flame). Bright green light dominates.
M.radioactive = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(160, 255, 80) },
	{ kind = "pulseTransparency", min = 0, max = 0.2, periodSec = 1.0 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(140, 255, 80), outlineT = 0.05,
		fillColor = Color3.fromRGB(140, 255, 80), fillT = 0.45 },
	{ kind = "pointLight",   color = Color3.fromRGB(140, 255, 80), range = 18, brightness = 7.0 },
	{ kind = "fire",         size = 5, heat = 5,
		color = Color3.fromRGB(160, 255, 100), secondaryColor = Color3.fromRGB(40, 120, 20) },
	{ kind = "smoke",        size = 3, opacity = 0.5, riseVelocity = 1.5,
		color = Color3.fromRGB(120, 200, 80) },
	{ kind = "sparkles",     color = Color3.fromRGB(140, 255, 80) },
}

-- Crystal: Glass cube shell wraps a Neon-glowing core fish. Bright white
-- light fills the cube + dense cyan Sparkles inside.
M.crystal = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 220, 255) },
	{ kind = "shell",        shape = "cube", padding = 0.8,
		material = Enum.Material.Glass, color = Color3.fromRGB(200, 230, 255),
		transparency = 0.4, reflectance = 0.7 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(220, 240, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(200, 230, 255), fillT = 0.5 },
	{ kind = "pointLight",   color = Color3.fromRGB(200, 230, 255), range = 14, brightness = 5.0 },
	{ kind = "sparkles",     color = Color3.fromRGB(180, 230, 255) },
}

-- Colossal: deep green tint + green halo + green PointLight + slow falling
-- earthy motes (gravity bow). Reads as "heavy, mighty fish".
-- Colossal: deep green Neon body + thick green aura smoke + green sparkles.
M.colossal = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(80, 200, 100) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 255, 120), outlineT = 0.05,
		fillColor = Color3.fromRGB(80, 220, 100), fillT = 0.5 },
	{ kind = "pointLight",   color = Color3.fromRGB(120, 255, 100), range = 16, brightness = 5.0 },
	{ kind = "smoke",        size = 5, opacity = 0.4, riseVelocity = 1,
		color = Color3.fromRGB(80, 200, 100) },
	{ kind = "sparkles",     color = Color3.fromRGB(140, 255, 140) },
}

-- Tiny: shrunken fish gets dense white Sparkles + thin Neon glow body.
M.tiny = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 255, 255) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 255, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 255, 255), fillT = 0.45 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 255, 255), range = 8, brightness = 3.5 },
	{ kind = "sparkles",     color = Color3.fromRGB(255, 255, 255) },
}

-- Bloodlust: pulsing red mesh + dark red Fire + red Smoke + red Sparkles.
-- Reads as "this fish is hungry for blood".
M.bloodlust = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle",   mode = "lerpLoop", periodSec = 0.7,
		palette = { Color3.fromRGB(200, 30, 30), Color3.fromRGB(255, 80, 80), Color3.fromRGB(140, 0, 0) } },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 30, 30), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 20, 20), fillT = 0.5 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 20, 20), range = 14, brightness = 5.0 },
	{ kind = "fire",         size = 5, heat = 6,
		color = Color3.fromRGB(255, 40, 40), secondaryColor = Color3.fromRGB(80, 0, 0) },
	{ kind = "smoke",        size = 2, opacity = 0.45, riseVelocity = 2,
		color = Color3.fromRGB(80, 10, 10) },
}

-- Voidtouched: near-black Neon body + dark purple Smoke + purple Sparkles +
-- purple Fire (dark flame). Reads as "this fish came from the void".
M.voidtouched = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(20, 5, 50) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(200, 100, 255), outlineT = 0.0,
		fillColor = Color3.fromRGB(120, 50, 200), fillT = 0.45 },
	{ kind = "pointLight",   color = Color3.fromRGB(180, 80, 255), range = 16, brightness = 5.5 },
	{ kind = "fire",         size = 6, heat = 4,
		color = Color3.fromRGB(180, 80, 255), secondaryColor = Color3.fromRGB(30, 0, 60) },
	{ kind = "smoke",        size = 3, opacity = 0.55, riseVelocity = 1.5,
		color = Color3.fromRGB(60, 20, 120) },
	{ kind = "sparkles",     color = Color3.fromRGB(180, 80, 255) },
}

-- Ghostly: half-transparent fish + soft white halo + slow upward wisps.
M.ghostly = {
	{ kind = "transparency", value = 0.5 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(240, 250, 255), outlineT = 0.2,
		fillColor = Color3.fromRGB(220, 235, 255), fillT = 0.7 },
	{ kind = "pointLight",   color = Color3.fromRGB(220, 235, 255), range = 7, brightness = 1.8 },
	{ kind = "attachedParticle",
		color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 210, 255)),
		rate = 18, lifetime = NumberRange.new(1.5, 2.5),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(0.8, 0.55), NumberSequenceKeypoint.new(1,0) }),
		speed = NumberRange.new(0.2, 0.6), spreadAngle = Vector2.new(60, 60),
		acceleration = Vector3.new(0, 2.0, 0),
		emissionDirection = Enum.NormalId.Top,
	},
}

-- Disco: Neon mesh fast color-flicker + bright pink Sparkles + multicolor
-- Beam ring + huge color-cycling PointLight (disco-ball feel).
M.disco = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "colorCycle", mode = "flicker", periodSec = 0.2, palette = {
		Color3.fromRGB(255,  60, 200),
		Color3.fromRGB( 60, 200, 255),
		Color3.fromRGB(255, 240,  80),
		Color3.fromRGB(120, 255, 120),
		Color3.fromRGB(255, 140,  40),
	} },
	{ kind = "highlight", outlineColor = Color3.fromRGB(255, 255, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 255, 255), fillT = 0.55 },
	{ kind = "pointLight", color = Color3.fromRGB(255, 200, 255), range = 16, brightness = 5.0 },
	{ kind = "sparkles",  color = Color3.fromRGB(255, 60, 200) },
	{ kind = "beam",
		offsetA = Vector3.new(-2.5, 0, 0), offsetB = Vector3.new(2.5, 0, 0),
		width0 = 0.5, width1 = 0.5, segments = 18, curveSize = 1.6,
		color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,  60, 200)),
			ColorSequenceKeypoint.new(0.5,  Color3.fromRGB( 60, 200, 255)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 240,  80)),
		}),
	},
}

-- Ancient core: Sand body + bronze halo + heavy tan Smoke (dusty aura) +
-- bronze Sparkles. Reads as "dusty ancient artifact".
M.ancientcore = {
	{ kind = "materialLock", material = Enum.Material.Sand },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 130, 60) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(220, 170, 90), outlineT = 0.05,
		fillColor = Color3.fromRGB(220, 170, 90), fillT = 0.6 },
	{ kind = "pointLight",   color = Color3.fromRGB(220, 170, 90), range = 10, brightness = 2.5 },
	{ kind = "smoke",        size = 3, opacity = 0.5, riseVelocity = 0.5,
		color = Color3.fromRGB(180, 140, 80) },
	{ kind = "sparkles",     color = Color3.fromRGB(220, 170, 90) },
}

-- ====================================================================
-- WORLD-STATE MODIFIERS — server-assigned by tide/weather/time, not rolled.
-- Stable IDs referenced in src/Server/Services/FishingService.lua:607–619.
-- ====================================================================

-- Tide-Kissed: Glass body + cyan Sparkles + cyan Smoke (mist) + cyan halo.
M.tide_kissed = {
	{ kind = "materialLock", material = Enum.Material.Glass },
	{ kind = "tintLock",     color = Color3.fromRGB(120, 230, 220) },
	{ kind = "transparency", value = 0.15 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(80, 220, 200), outlineT = 0.05,
		fillColor = Color3.fromRGB(80, 220, 200), fillT = 0.55 },
	{ kind = "pointLight",   color = Color3.fromRGB(80, 230, 220), range = 12, brightness = 4.0 },
	{ kind = "smoke",        size = 3, opacity = 0.4, riseVelocity = 1,
		color = Color3.fromRGB(80, 200, 200) },
	{ kind = "sparkles",     color = Color3.fromRGB(80, 230, 220) },
}

-- Storm-Forged: dark Neon purple body + 2 electric Beam arcs over fish +
-- purple Sparkles + purple Smoke (storm cloud).
M.storm_forged = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(60, 60, 140) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(180, 180, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(120, 120, 220), fillT = 0.5 },
	{ kind = "pointLight",   color = Color3.fromRGB(160, 160, 255), range = 14, brightness = 4.5 },
	{ kind = "smoke",        size = 3, opacity = 0.45, riseVelocity = 1.5,
		color = Color3.fromRGB(80, 80, 160) },
	{ kind = "sparkles",     color = Color3.fromRGB(180, 180, 255) },
	{ kind = "beam",
		offsetA = Vector3.new(-2, 1, 0), offsetB = Vector3.new(2, 1, 0),
		width0 = 0.25, width1 = 0.25, segments = 14, curveSize = 1.8,
		color = ColorSequence.new(Color3.fromRGB(220, 220, 255), Color3.fromRGB(140, 140, 255)),
	},
	{ kind = "beam",
		offsetA = Vector3.new(-2, -1, 0), offsetB = Vector3.new(2, -1, 0),
		width0 = 0.2, width1 = 0.2, segments = 14, curveSize = -1.5,
		color = ColorSequence.new(Color3.fromRGB(200, 200, 255), Color3.fromRGB(120, 120, 240)),
	},
}

-- Moon-Touched: silvery Neon body + thin glass shell + white Sparkles +
-- soft white Smoke (moonlight mist).
M.moon_touched = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(210, 220, 255) },
	{ kind = "shell",        scale = 1.06, material = Enum.Material.Glass,
		color = Color3.fromRGB(230, 235, 255), transparency = 0.35, reflectance = 0.5 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(230, 240, 255), outlineT = 0.05,
		fillColor = Color3.fromRGB(210, 220, 255), fillT = 0.55 },
	{ kind = "pointLight",   color = Color3.fromRGB(210, 225, 255), range = 14, brightness = 4.5 },
	{ kind = "smoke",        size = 3, opacity = 0.35, riseVelocity = 0.8,
		color = Color3.fromRGB(220, 230, 255) },
	{ kind = "sparkles",     color = Color3.fromRGB(220, 230, 255) },
}

-- Dawn-Blessed: warm orange Neon body + gentle Fire (sunrise glow) + warm
-- Sparkles + warm Smoke trailing.
M.dawn_blessed = {
	{ kind = "materialLock", material = Enum.Material.Neon },
	{ kind = "tintLock",     color = Color3.fromRGB(255, 190, 110) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(255, 200, 100), outlineT = 0.05,
		fillColor = Color3.fromRGB(255, 200, 120), fillT = 0.5 },
	{ kind = "pointLight",   color = Color3.fromRGB(255, 200, 120), range = 14, brightness = 4.5 },
	{ kind = "fire",         size = 4, heat = 4,
		color = Color3.fromRGB(255, 230, 150), secondaryColor = Color3.fromRGB(255, 140, 60) },
	{ kind = "smoke",        size = 2, opacity = 0.3, riseVelocity = 1.5,
		color = Color3.fromRGB(255, 220, 160) },
	{ kind = "sparkles",     color = Color3.fromRGB(255, 230, 160) },
}

-- Fog-Shrouded: faded body + softer gray shell + slow gray fog wisps.
M.fog_shrouded = {
	{ kind = "transparency", value = 0.35 },
	{ kind = "tintLock",     color = Color3.fromRGB(180, 195, 210) },
	{ kind = "shell",        scale = 1.18, material = Enum.Material.SmoothPlastic,
		color = Color3.fromRGB(200, 210, 220), transparency = 0.75, reflectance = 0 },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(220, 230, 240), outlineT = 0.3, fillT = 1 },
	{ kind = "attachedParticle",
		color = ColorSequence.new(Color3.fromRGB(220, 230, 240), Color3.fromRGB(170, 185, 200)),
		rate = 22, lifetime = NumberRange.new(1.5, 2.5),
		size = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(0.3, 0.85), NumberSequenceKeypoint.new(0.8, 0.65), NumberSequenceKeypoint.new(1,0) }),
		speed = NumberRange.new(0.1, 0.4), spreadAngle = Vector2.new(180,180),
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
	{ kind = "highlight",    outlineColor = Color3.fromRGB(220, 235, 255), outlineT = 0.2,
		fillColor = Color3.fromRGB(220, 235, 255), fillT = 0.65 },
	{ kind = "pointLight",   color = Color3.fromRGB(220, 235, 255), range = 8, brightness = 2.5 },
}
M.lucky     = {              -- soft green
	{ kind = "tintLock",     color = Color3.fromRGB(160, 230, 160) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 220, 120), outlineT = 0.2,
		fillColor = Color3.fromRGB(120, 220, 120), fillT = 0.7 },
	{ kind = "pointLight",   color = Color3.fromRGB(120, 220, 120), range = 5, brightness = 1.5 },
}
M.ancient   = M.ancientcore
M.prismatic = M.rainbow
M.elder     = M.voidtouched
M.cursed    = M.bloodlust    -- close enough visually
M.magnetic  = {              -- cool cyan steady (no flicker — epilepsy)
	{ kind = "tintLock",     color = Color3.fromRGB(150, 220, 240) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(80, 200, 230), outlineT = 0.15,
		fillColor = Color3.fromRGB(80, 200, 230), fillT = 0.65 },
	{ kind = "pointLight",   color = Color3.fromRGB(80, 200, 230), range = 6, brightness = 1.8 },
}
M.barnacled = {              -- rough rocky body + brown highlight
	{ kind = "materialLock", material = Enum.Material.Rock },
	{ kind = "tintLock",     color = Color3.fromRGB(150, 160, 130) },
	{ kind = "highlight",    outlineColor = Color3.fromRGB(120, 110, 90), outlineT = 0.3, fillT = 1 },
}

return M
