-- Command bar: build ReplicatedStorage.Assets.Weather templates for WorldFXController.
-- Paste into Studio command bar (edit mode, not Play Solo).
-- Safe to re-run — replaces RainVolume, StormRain, GroundMist.

local RAIN_TEX = "rbxassetid://419625073"
local FOG_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f :: Folder
end

local RS = game:GetService("ReplicatedStorage")
local rainF = ensureFolder(ensureFolder(ensureFolder(RS, "Assets"), "Weather"), "Rain")
local stormF = ensureFolder(RS.Assets.Weather, "Storm")
local fogF = ensureFolder(RS.Assets.Weather, "Fog")

local function clearTarget(folder: Instance, targetName: string)
	local existing = folder:FindFirstChild(targetName)
	if existing then
		existing:Destroy()
	end
end

type VolumeCfg = {
	texture: string,
	rate: number,
	lifetime: number,
	speed: NumberRange,
	spread: Vector2,
	sizeSeq: NumberSequence,
	direction: Enum.NormalId,
	size: Vector3,
	lightEmission: number?,
	drag: number?,
}

local function buildVolume(name: string, parent: Instance, cfg: VolumeCfg): Part
	clearTarget(parent, name)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = cfg.size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.CFrame = CFrame.new(0, 100, 0)
	part.Parent = parent

	local attach = Instance.new("Attachment")
	attach.Name = "WeatherAttach"
	attach.Parent = part

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "RainEmitter"
	pe.Texture = cfg.texture
	pe.Rate = cfg.rate
	pe.Lifetime = NumberRange.new(cfg.lifetime, cfg.lifetime)
	pe.Speed = cfg.speed
	pe.SpreadAngle = cfg.spread
	pe.Size = cfg.sizeSeq
	pe.EmissionDirection = cfg.direction
	pe.VelocityInheritance = 0
	pe.Drag = cfg.drag or 0.5
	pe.LightEmission = cfg.lightEmission or 0.2
	pe.Enabled = false
	pe.Parent = attach

	return part
end

for _, name in ipairs({ "RainVolume", "StormRain" }) do
	local w = workspace:FindFirstChild(name)
	if w then
		w:Destroy()
	end
end

buildVolume("RainVolume", rainF, {
	texture = RAIN_TEX,
	rate = 80,
	lifetime = 0.6,
	speed = NumberRange.new(28, 40),
	spread = Vector2.new(12, 12),
	sizeSeq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.08),
	}),
	direction = Enum.NormalId.Bottom,
	size = Vector3.new(40, 1, 40),
})

buildVolume("StormRain", stormF, {
	texture = RAIN_TEX,
	rate = 140,
	lifetime = 0.55,
	speed = NumberRange.new(32, 48),
	spread = Vector2.new(18, 18),
	sizeSeq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.22),
		NumberSequenceKeypoint.new(1, 0.1),
	}),
	direction = Enum.NormalId.Bottom,
	size = Vector3.new(48, 1, 48),
})

buildVolume("GroundMist", fogF, {
	texture = FOG_TEX,
	rate = 6,
	lifetime = 8,
	speed = NumberRange.new(0.3, 0.8),
	spread = Vector2.new(180, 20),
	sizeSeq = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 8),
		NumberSequenceKeypoint.new(0.5, 14),
		NumberSequenceKeypoint.new(1, 18),
	}),
	direction = Enum.NormalId.Top,
	size = Vector3.new(80, 1, 80),
	lightEmission = 0.05,
	drag = 1,
})

print("[SetupWeather] Done:")
print("  ReplicatedStorage.Assets.Weather.Rain.RainVolume")
print("  ReplicatedStorage.Assets.Weather.Storm.StormRain")
print("  ReplicatedStorage.Assets.Weather.Fog.GroundMist")
