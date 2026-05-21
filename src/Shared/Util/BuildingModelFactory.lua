--!strict
-- BuildingModelFactory.lua
-- Procedural placeholder Models for harbor buildings (kind × tier).
-- Pivot: PrimaryPart at (0,0,0) = footprint bottom-center on the plot plate (GridUtil PLATE_TOP).
-- All geometry is built upward from Y >= 0 so nothing clips into the harbor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CELL = GameConfig.Harbor.GridCellStuds

local BuildingModelFactory = {}

local C = {
	woodDark   = Color3.fromRGB(72, 48, 28),
	woodMid    = Color3.fromRGB(120, 78, 42),
	woodLight  = Color3.fromRGB(168, 128, 78),
	woodFresh  = Color3.fromRGB(190, 150, 95),
	stone      = Color3.fromRGB(140, 135, 125),
	brick      = Color3.fromRGB(150, 85, 65),
	brickDark  = Color3.fromRGB(110, 60, 48),
	thatch     = Color3.fromRGB(175, 145, 90),
	white      = Color3.fromRGB(235, 232, 220),
	red        = Color3.fromRGB(180, 55, 45),
	teal       = Color3.fromRGB(55, 130, 125),
	canvas     = Color3.fromRGB(95, 125, 155),
	canvasFade = Color3.fromRGB(130, 145, 165),
	glass      = Color3.fromRGB(140, 200, 220),
	water      = Color3.fromRGB(60, 140, 180),
	copper     = Color3.fromRGB(180, 110, 70),
	iron       = Color3.fromRGB(70, 72, 78),
	moss       = Color3.fromRGB(70, 110, 65),
	gold       = Color3.fromRGB(210, 175, 60),
	smoke      = Color3.fromRGB(180, 180, 175),
	rope       = Color3.fromRGB(160, 140, 100),
	rodHandle  = Color3.fromRGB(90, 55, 30),
	rodShaft   = Color3.fromRGB(55, 90, 55),
	rodReel    = Color3.fromRGB(50, 50, 55),
}

local function studs(footprint: {number}): (number, number)
	return footprint[1] * CELL, footprint[2] * CELL
end

local function mkPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	opts: { transparency: number?, canCollide: boolean? }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = if opts and opts.canCollide ~= nil then opts.canCollide else true
	p.CanQuery = false
	p.CanTouch = false
	if opts and opts.transparency then
		p.Transparency = opts.transparency
	end
	p.Parent = parent
	return p
end

-- Bottom face on Y = groundY (default 0 = plot plate surface).
local function onGround(
	parent: Instance,
	name: string,
	size: Vector3,
	x: number,
	z: number,
	color: Color3,
	material: Enum.Material,
	groundY: number?,
	opts: { transparency: number?, canCollide: boolean? }?
): Part
	local gy = groundY or 0
	return mkPart(parent, name, size, CFrame.new(x, gy + size.Y / 2, z), color, material, opts)
end

local function addLight(parent: Instance, x: number, y: number, z: number, brightness: number, range: number)
	local anchor = onGround(parent, "Lantern", Vector3.new(0.35, 0.35, 0.35), x, z, C.gold, Enum.Material.Metal, y - 0.175, { canCollide = false })
	anchor.Transparency = 0.25
	local pl = Instance.new("PointLight")
	pl.Brightness = brightness
	pl.Range = range
	pl.Color = Color3.fromRGB(255, 200, 120)
	pl.Parent = anchor
end

local function anchorModel(model: Model)
	-- PrimaryPart at true bbox bottom-center, then shift model so bottom rests at Y=0.
	local bbCF, bbSize = model:GetBoundingBox()
	local bottomCenter = Vector3.new(
		bbCF.Position.X,
		bbCF.Position.Y - bbSize.Y / 2,
		bbCF.Position.Z
	)

	local pp = Instance.new("Part")
	pp.Name = "PrimaryPart"
	pp.Size = Vector3.new(0.2, 0.2, 0.2)
	pp.Transparency = 1
	pp.Anchored = true
	pp.CanCollide = false
	pp.CanQuery = false
	pp.CanTouch = false
	pp.CFrame = CFrame.new(bottomCenter)
	pp.Parent = model
	model.PrimaryPart = pp

	local shift = CFrame.new(-bottomCenter)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CFrame = shift * desc.CFrame
		end
	end
end

-- Fishing rod prop leaning on a stand (for BaitShop rod stand).
local function mkRodDisplay(parent: Instance, x: number, z: number, length: number, lean: number, tier: number)
	local handleH = 0.5
	local shaftLen = length - handleH
	onGround(parent, "RodHandle", Vector3.new(0.22, handleH, 0.22), x, z, C.rodHandle, Enum.Material.Wood)
	local shaft = mkPart(
		parent,
		"RodShaft",
		Vector3.new(0.1, 0.1, shaftLen),
		CFrame.new(x, handleH + shaftLen / 2, z) * CFrame.Angles(math.rad(lean), 0, 0),
		if tier >= 2 then C.rodShaft else C.woodMid,
		Enum.Material.Wood
	)
	if tier >= 2 then
		mkPart(parent, "RodReel", Vector3.new(0.35, 0.35, 0.2),
			CFrame.new(x + 0.15, handleH + 0.2, z + 0.1), C.rodReel, Enum.Material.Metal)
	end
end

-- ====================================================================
-- DOCK — wooden pier extending toward the water (+Z)
-- ====================================================================
local function buildDock(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "Dock"

	local plankH = 0.45
	local rows = math.max(2, math.floor(d / 2.5))
	for i = 0, rows - 1 do
		local z = -d / 2 + 1.2 + i * (d - 2) / math.max(rows - 1, 1)
		local color = if tier == 1 then C.woodDark elseif tier == 2 then C.woodMid else C.woodFresh
		local gap = if tier == 1 and i % 2 == 0 then 0.2 else 0
		onGround(model, "Plank" .. i, Vector3.new(w - 0.8, plankH, 2.2 - gap), 0, z, color, Enum.Material.WoodPlanks)
		if tier == 1 and i % 3 == 0 then
			onGround(model, "Moss" .. i, Vector3.new(1, 0.12, 1), (i % 2) * 2 - 1, z, C.moss, Enum.Material.Grass, plankH)
		end
	end

	-- Pilings along the water edge
	local postCount = if tier == 1 then 2 elseif tier == 2 then 4 else 5
	for i = 0, postCount - 1 do
		local x = -w / 2 + 1 + (i / math.max(postCount - 1, 1)) * (w - 2)
		local h = if tier == 1 then 2.8 elseif tier == 2 then 3.5 else 4.5
		onGround(model, "Piling" .. i, Vector3.new(0.55, h, 0.55), x, d / 2 - 0.8,
			if tier >= 3 then C.iron else C.woodDark,
			if tier >= 3 then Enum.Material.Metal else Enum.Material.Wood)
	end

	if tier >= 2 then
		onGround(model, "RopeRail", Vector3.new(w - 0.6, 0.25, 0.25), 0, d / 2 - 0.4, C.rope, Enum.Material.Fabric, 1.1)
	end
	if tier >= 3 then
		onGround(model, "Cleat", Vector3.new(0.9, 0.35, 0.9), w / 2 - 1.5, d / 4, C.gold, Enum.Material.Metal, 0.2)
		addLight(model, -w / 2 + 1.2, 3.8, d / 2 - 0.6, 1.2, 14)
		addLight(model, w / 2 - 1.2, 3.8, d / 2 - 0.6, 1.2, 14)
	end

	anchorModel(model)
	return model
end

-- ====================================================================
-- MARKET STALL — open fish market with awning and goods
-- ====================================================================
local function buildMarketStall(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "MarketStall"

	local counterH = if tier == 1 then 2.6 elseif tier == 2 then 3 else 3.4
	onGround(model, "Counter", Vector3.new(w - 0.4, counterH, 1.1), 0, -d / 2 + 1.2,
		if tier >= 2 then C.woodMid else C.woodDark, Enum.Material.Wood)

	-- Striped awning
	local awningY = counterH + 1.2
	onGround(model, "Awning", Vector3.new(w, 0.3, d * 0.75), 0, 0, if tier == 1 then C.canvasFade else C.teal, Enum.Material.Fabric, awningY)
	if tier >= 2 then
		onGround(model, "AwningStripe", Vector3.new(w, 0.1, d * 0.4), 0, 0.5, C.white, Enum.Material.Fabric, awningY + 0.05)
		onGround(model, "Scale", Vector3.new(0.8, 1.2, 0.8), w / 2 - 1, -d / 2 + 1.5, C.iron, Enum.Material.Metal, counterH)
	end

	-- Fish crates / baskets on counter
	if tier == 1 then
		onGround(model, "CrateA", Vector3.new(1.1, 0.7, 1.1), -1.2, 0.5, C.woodDark, Enum.Material.Wood)
		onGround(model, "CrateB", Vector3.new(0.9, 0.6, 0.9), 1.3, 0.3, C.woodMid, Enum.Material.Wood)
	else
		onGround(model, "FishIce", Vector3.new(1.8, 0.35, 1.2), 0, -d / 2 + 1.8, C.glass, Enum.Material.Ice, counterH, { transparency = 0.2 })
	end

	if tier >= 3 then
		onGround(model, "Sign", Vector3.new(2.8, 1, 0.15), 0, -d / 2 + 0.4, C.gold, Enum.Material.Wood, counterH + 2.2)
		addLight(model, 0, counterH + 1.5, -d / 2 + 1.5, 0.9, 12)
	end

	anchorModel(model)
	return model
end

-- ====================================================================
-- SMOKEHOUSE — brick smoker with chimney and drying racks
-- ====================================================================
local function buildSmokehouse(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "Smokehouse"

	local wallH = if tier == 1 then 4 elseif tier == 2 then 5 else 6.5
	local wallMat = if tier == 1 then Enum.Material.Rock else Enum.Material.Brick
	local wallCol = if tier == 1 then C.stone else C.brick

	onGround(model, "BackWall", Vector3.new(w - 0.2, wallH, 0.55), 0, -d / 2 + 0.35, wallCol, wallMat)
	onGround(model, "LeftWall", Vector3.new(0.55, wallH, d - 0.4), -w / 2 + 0.3, 0, wallCol, wallMat)
	onGround(model, "RightWall", Vector3.new(0.55, wallH, d - 0.4), w / 2 - 0.3, 0, wallCol, wallMat)
	onGround(model, "Roof", Vector3.new(w + 0.3, 0.45, d + 0.3), 0, 0, if tier == 1 then C.thatch else C.brickDark,
		if tier == 1 then Enum.Material.Grass else Enum.Material.Slate, wallH)

	local chimX = w / 2 - 1
	local chimH = if tier == 1 then 2.5 elseif tier == 2 then 3.5 else 5
	onGround(model, "Chimney", Vector3.new(1.1, chimH, 1.1), chimX, 0, if tier >= 3 then C.copper else C.brickDark,
		if tier >= 3 then Enum.Material.Metal else Enum.Material.Brick, wallH)

	if tier >= 2 then
		onGround(model, "Door", Vector3.new(1.6, 2.8, 0.2), 0, d / 2 - 0.15, C.woodDark, Enum.Material.Wood)
	end
	if tier >= 3 then
		onGround(model, "FishRack", Vector3.new(2.8, 0.12, 0.6), -1, d / 2 - 0.5, C.woodMid, Enum.Material.Wood, 2.2)
		onGround(model, "FishRack2", Vector3.new(2.8, 0.12, 0.6), 1, d / 2 - 0.5, C.woodMid, Enum.Material.Wood, 2.8)
		mkPart(model, "Vane", Vector3.new(0.12, 1.8, 0.7),
			CFrame.new(chimX, wallH + chimH + 1.2, 0), C.gold, Enum.Material.Metal)
	end

	local smokeSize = if tier == 1 then 1 elseif tier == 2 then 1.8 else 2.5
	mkPart(model, "Smoke", Vector3.new(smokeSize, smokeSize, smokeSize),
		CFrame.new(chimX, wallH + chimH + 1.8, 0), C.smoke, Enum.Material.SmoothPlastic, { transparency = 0.5, canCollide = false })

	anchorModel(model)
	return model
end

-- ====================================================================
-- LIGHTHOUSE — tapered tower with lamp room
-- ====================================================================
local function buildLighthouse(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "Lighthouse"

	local baseR = math.min(w, d) * 0.38
	local towerH = if tier == 1 then 7 elseif tier == 2 then 11 else 15

	onGround(model, "Foundation", Vector3.new(baseR * 2.4, 1, baseR * 2.4), 0, 0, C.stone, Enum.Material.Concrete)
	onGround(model, "Tower", Vector3.new(baseR * 1.5, towerH, baseR * 1.5), 0, 0, C.white, Enum.Material.SmoothPlastic, 1)

	if tier >= 2 then
		for i = 0, 3 do
			onGround(model, "Band" .. i, Vector3.new(baseR * 1.55, 0.55, baseR * 1.55), 0, 0,
				if i % 2 == 0 then C.red else C.white, Enum.Material.SmoothPlastic, 1.5 + i * 2.5)
		end
	end

	local lampBase = 1 + towerH + 0.5
	onGround(model, "Gallery", Vector3.new(baseR * 2.2, 0.35, baseR * 2.2), 0, 0, C.iron, Enum.Material.Metal, lampBase)
	onGround(model, "LanternRoom", Vector3.new(baseR * 1.3, 1.4, baseR * 1.3), 0, 0, C.glass, Enum.Material.Glass, lampBase + 0.5, { transparency = 0.35 })

	if tier >= 3 then
		addLight(model, 0, lampBase + 1.8, 0, 2.5, 45)
	end

	anchorModel(model)
	return model
end

-- ====================================================================
-- BAIT SHOP — open rod stand (sells rods; catalog id stays BaitShop)
-- ====================================================================
local function buildBaitShop(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "BaitShop"

	local standH = if tier == 1 then 2.4 elseif tier == 2 then 2.8 else 3.2
	-- Counter / stand table facing the harbor (-Z)
	onGround(model, "StandTop", Vector3.new(w - 0.3, 0.35, 1.4), 0, -d / 2 + 1.1, C.woodMid, Enum.Material.Wood, standH - 0.35)
	onGround(model, "StandLegL", Vector3.new(0.25, standH, 0.25), -w / 2 + 0.5, -d / 2 + 1.1, C.woodDark, Enum.Material.Wood)
	onGround(model, "StandLegR", Vector3.new(0.25, standH, 0.25), w / 2 - 0.5, -d / 2 + 1.1, C.woodDark, Enum.Material.Wood)

	-- Rod rack behind the stand
	onGround(model, "RodRack", Vector3.new(0.2, standH + 0.8, w * 0.6), 0, d / 2 - 0.5, C.woodDark, Enum.Material.Wood)

	local rodCount = if tier == 1 then 2 elseif tier == 2 then 4 else 6
	for i = 0, rodCount - 1 do
		local x = -w / 2 + 0.8 + (i / math.max(rodCount - 1, 1)) * (w - 1.6)
		mkRodDisplay(model, x, -d / 2 + 0.6, if tier >= 3 then 5.5 else 4.5, -12 - i * 3, tier)
	end

	if tier == 1 then
		onGround(model, "Sign", Vector3.new(2.2, 0.7, 0.12), 0, -d / 2 + 0.35, C.woodDark, Enum.Material.Wood, standH + 0.5)
	elseif tier == 2 then
		onGround(model, "Awning", Vector3.new(w + 0.2, 0.25, 1.8), 0, -d / 2 + 1.5, C.teal, Enum.Material.Fabric, standH + 0.6)
		onGround(model, "SignRods", Vector3.new(2.5, 0.9, 0.12), 0, -d / 2 + 0.3, C.gold, Enum.Material.Wood, standH + 1)
	else
		onGround(model, "Canopy", Vector3.new(w + 0.4, 0.3, 2.2), 0, 0, C.teal, Enum.Material.Fabric, standH + 1.2)
		onGround(model, "DisplayCase", Vector3.new(1.6, 1.2, 0.8), w / 2 - 1.2, 0, C.glass, Enum.Material.Glass, standH, { transparency = 0.35 })
		addLight(model, 0, standH + 1.5, -d / 2 + 1, 1, 14)
	end

	anchorModel(model)
	return model
end

-- ====================================================================
-- AQUARIUM — glass tank display
-- ====================================================================
local function buildAquarium(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "Aquarium"

	if tier == 1 then
		-- Barrel tank
		local tankW = math.min(w, 3.5)
		onGround(model, "BarrelBody", Vector3.new(tankW, 2.2, math.min(d, 3)), 0, 0, C.woodDark, Enum.Material.Wood)
		onGround(model, "GlassPanel", Vector3.new(tankW - 0.4, 1.4, 0.12), 0, -math.min(d, 3) / 2 + 0.08, C.glass, Enum.Material.Glass, 0.6, { transparency = 0.4 })
		onGround(model, "Water", Vector3.new(tankW - 0.6, 1, math.min(d, 3) - 0.4), 0, 0, C.water, Enum.Material.Glass, 0.7, { transparency = 0.35, canCollide = false })
		addLight(model, 0, 2.5, 0, 0.5, 8)
	elseif tier == 2 then
		local tankH = 3.6
		onGround(model, "TankFrame", Vector3.new(w - 0.4, tankH, d - 0.4), 0, 0, C.woodMid, Enum.Material.Wood)
		onGround(model, "GlassFront", Vector3.new(w - 0.8, tankH - 0.5, 0.15), 0, -d / 2 + 0.1, C.glass, Enum.Material.Glass, 0.3, { transparency = 0.35 })
		onGround(model, "WaterFill", Vector3.new(w - 1.2, tankH - 1, d - 1), 0, 0, C.water, Enum.Material.Glass, 0.5, { transparency = 0.4, canCollide = false })
		onGround(model, "BrassTrim", Vector3.new(w, 0.25, d), 0, 0, C.copper, Enum.Material.Metal, tankH)
		addLight(model, 0, tankH - 0.3, 0, 0.8, 12)
	else
		local tankH = 4.8
		onGround(model, "MarbleBase", Vector3.new(w, 0.5, d + 0.8), 0, 0.3, C.stone, Enum.Material.Marble)
		onGround(model, "TankBody", Vector3.new(w - 0.3, tankH, d - 0.3), 0, 0, C.stone, Enum.Material.Marble)
		onGround(model, "GlassWall", Vector3.new(w - 0.6, tankH - 0.4, 0.2), 0, -d / 2 + 0.1, C.glass, Enum.Material.Glass, 0.5, { transparency = 0.3 })
		onGround(model, "Water", Vector3.new(w - 1, tankH - 1.2, d - 1), 0, 0, C.water, Enum.Material.Glass, 0.8, { transparency = 0.35, canCollide = false })
		onGround(model, "MosaicPath", Vector3.new(w + 0.5, 0.15, 1.5), 0, d / 2 + 0.5, C.teal, Enum.Material.Glass)
		addLight(model, 0, tankH, 0, 1.3, 18)
	end

	anchorModel(model)
	return model
end

-- ====================================================================
-- GUILDHALL — crew hall with banner and bell
-- ====================================================================
local function buildGuildhall(tier: number, w: number, d: number): Model
	local model = Instance.new("Model")
	model.Name = "Guildhall"

	local wallH = if tier == 1 then 5 elseif tier == 2 then 7 else 9
	onGround(model, "MainHall", Vector3.new(w - 0.3, wallH, d - 0.3), 0, 0,
		if tier >= 3 then C.stone else C.woodMid,
		if tier >= 3 then Enum.Material.Marble else Enum.Material.WoodPlanks)

	-- Peaked roof silhouette
	onGround(model, "Roof", Vector3.new(w, 0.5, d), 0, 0, if tier >= 3 then C.brickDark else C.woodDark,
		Enum.Material.Slate, wallH)

	if tier == 1 then
		onGround(model, "AnchorBanner", Vector3.new(3.2, 1.6, 0.1), 0, -d / 2 + 0.15, C.red, Enum.Material.Fabric, wallH - 1.5)
		onGround(model, "NoticeBoard", Vector3.new(1.8, 1.4, 0.15), w / 2 - 0.4, 0, C.woodDark, Enum.Material.Wood, 2)
	elseif tier == 2 then
		onGround(model, "EntryArch", Vector3.new(2.8, 3.8, 0.6), 0, -d / 2 + 0.35, C.stone, Enum.Material.Concrete, 0.2)
		onGround(model, "Bell", Vector3.new(1.1, 1.1, 1.1), 0, -d / 2 + 0.5, C.gold, Enum.Material.Metal, wallH + 0.5)
		for i = -1, 1, 2 do
			mkPart(model, "Pennant" .. i, Vector3.new(0.08, 2.2, 1.1),
				CFrame.new(i * 2.8, wallH - 1, -d / 2 + 0.35), C.teal, Enum.Material.Fabric)
		end
	else
		onGround(model, "StoneFacade", Vector3.new(w + 0.4, 2.2, 0.5), 0, -d / 2 - 0.15, C.stone, Enum.Material.Slate, wallH - 2)
		onGround(model, "StainedGlass", Vector3.new(3.2, 4.2, 0.15), 0, -d / 2 + 0.12, C.glass, Enum.Material.Glass, 2, { transparency = 0.25 })
		onGround(model, "Crest", Vector3.new(4, 3, 0.25), 0, -d / 2 - 0.35, C.gold, Enum.Material.Metal, wallH / 2)
		onGround(model, "Flagpole", Vector3.new(0.3, 7, 0.3), w / 2 - 1, d / 2 - 0.8, C.woodDark, Enum.Material.Wood)
		addLight(model, 0, wallH - 1, 0, 0.7, 22)
	end

	anchorModel(model)
	return model
end

local BUILDERS: {[string]: (number, number, number) -> Model} = {
	Dock         = buildDock,
	MarketStall  = buildMarketStall,
	Smokehouse   = buildSmokehouse,
	Lighthouse   = buildLighthouse,
	BaitShop     = buildBaitShop,
	Aquarium     = buildAquarium,
	Guildhall    = buildGuildhall,
}

function BuildingModelFactory.build(kind: string, tier: number, footprint: {number}): Model
	local builder = BUILDERS[kind]
	if not builder then
		error(("[BuildingModelFactory] Unknown kind: %s"):format(kind))
	end
	local w, d = studs(footprint)
	local model = builder(tier, w, d)
	model.Name = kind .. "_T" .. tier
	model:SetAttribute("ProceduralPlaceholder", true)
	return model
end

return BuildingModelFactory
