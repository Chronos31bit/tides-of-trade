--!strict
-- WorldService.lua
-- Sets up the static world: Terrain water + procedural biome geography +
-- per-biome sensor zones that update each player's CurrentBiome StringValue
-- as they roam. FishingService reads CurrentBiome to decide what can bite.
--
-- Why server-authoritative biomes: the client's location can be spoofed, so
-- biome eligibility has to be computed server-side from the actual character
-- position.

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local WorldService = Knit.CreateService({
	Name = "WorldService",
	-- Each entry: { biome, cframe, size }. Used at runtime to resolve which
	-- biome a player's HumanoidRootPart is inside.
	_biomeZones = {} :: {{cframe: CFrame, size: Vector3, biome: string}},
})

local PLOT = GameConfig.Harbor.PlotSizeStuds
local PLOT_SPACING = PLOT + 40
local PLOT_GRID = 4
local WORLD_RADIUS = PLOT_SPACING * (PLOT_GRID + 2)

-- ====================================================================
-- TERRAIN PRIMITIVES
-- All Workspace.Terrain operations are voxelized at 4-stud resolution; we
-- size things in multiples of 4 to avoid stairstepping artifacts.
-- ====================================================================
local TERRAIN = Workspace.Terrain

local function fillBox(centerX: number, y: number, centerZ: number, sx: number, sy: number, sz: number, mat: Enum.Material)
	TERRAIN:FillBlock(CFrame.new(centerX, y, centerZ), Vector3.new(sx, sy, sz), mat)
end

local function fillBall(x: number, y: number, z: number, r: number, mat: Enum.Material)
	TERRAIN:FillBall(Vector3.new(x, y, z), r, mat)
end

-- Sample a 2D Perlin noise field at world (x,z). Returned in [-1, 1].
local function noise2(x: number, z: number, scale: number): number
	return math.noise(x * scale, z * scale, 0)
end

-- ====================================================================
-- BASE OCEAN
-- A single volume of Terrain.Water across the playable area. Biome-specific
-- features overwrite voxels inside this region.
-- ====================================================================
local function fillSeaBase(seaCenter: Vector3)
	-- Default sea floor at Y = -10. Water from Y = -10 up to Y = 0.
	-- We fill the volume in two passes: a sand floor then water above it.
	local sx, sz = WORLD_RADIUS * 2, WORLD_RADIUS * 2
	-- Sand floor (Y = -14..-10).
	fillBox(seaCenter.X, -12, seaCenter.Z, sx, 4, sz, Enum.Material.Sand)
	-- Water column above.
	fillBox(seaCenter.X, -5, seaCenter.Z, sx, 10, sz, Enum.Material.Water)
end

-- ====================================================================
-- ISLANDS — sandy main island + tall rocky island
-- Built from many overlapping spheres at jittered positions for organic
-- silhouettes without needing per-voxel writes.
-- ====================================================================
local function generateIsland(centerX: number, centerZ: number, baseRadius: number, peakHeight: number, material: Enum.Material)
	local sphereCount = math.floor(baseRadius / 5)
	for _ = 1, sphereCount do
		-- Bias points toward center: sqrt(uniform) gives a denser core.
		local angle = math.random() * math.pi * 2
		local r = math.sqrt(math.random()) * baseRadius * 0.85
		local x = centerX + math.cos(angle) * r
		local z = centerZ + math.sin(angle) * r
		-- Sphere shrinks toward edges so the coast tapers cleanly.
		local edgeFactor = 1 - (r / baseRadius)
		local sphereR = math.random(8, 22) * (0.6 + edgeFactor * 0.7)
		-- Peak in the middle, slope down to the edges.
		local h = peakHeight * (0.3 + edgeFactor * 0.7) + noise2(x, z, 0.05) * 2
		fillBall(x, h - sphereR / 2, z, sphereR, material)
	end
end

-- ====================================================================
-- BIOME-SPECIFIC TERRAIN — what makes each fishing zone visually distinct
-- ====================================================================

-- Reef: shallow water with sandstone "coral" mounds and slate (blue-grey)
-- outcrops. Reads as a colorful, busy sea floor when looking down through
-- the water.
local function generateReef(center: Vector3, sizeX: number, sizeZ: number)
	-- Slightly raised sandstone bed — players will see lighter sand here.
	for _ = 1, 60 do
		local x = center.X + (math.random() - 0.5) * sizeX
		local z = center.Z + (math.random() - 0.5) * sizeZ
		local r = math.random(4, 9)
		fillBall(x, -7, z, r, Enum.Material.Sandstone)
	end
	-- Slate rocks scattered between the coral.
	for _ = 1, 30 do
		local x = center.X + (math.random() - 0.5) * sizeX
		local z = center.Z + (math.random() - 0.5) * sizeZ
		local r = math.random(5, 10)
		fillBall(x, -6, z, r, Enum.Material.Slate)
	end
	-- Occasional coral "tower" reaching toward the surface for visual interest.
	for _ = 1, 6 do
		local x = center.X + (math.random() - 0.5) * sizeX
		local z = center.Z + (math.random() - 0.5) * sizeZ
		fillBox(x, -2, z, 6, 10, 6, Enum.Material.Sandstone)
	end
end

-- DeepWater: dig the floor down so the water is visibly darker (deeper),
-- and scatter large basalt boulders. Floor goes from Y = -10 (default) down
-- to Y = -28.
local function generateDeepWater(center: Vector3, sizeX: number, sizeZ: number)
	-- Carve out the basin: replace the existing sand floor with water down
	-- to Y = -28, then refill the new bottom with a darker rock (basalt).
	fillBox(center.X, -19, center.Z, sizeX, 18, sizeZ, Enum.Material.Water)
	fillBox(center.X, -30, center.Z, sizeX, 4, sizeZ, Enum.Material.Basalt)

	-- Half-submerged boulders for atmosphere.
	for _ = 1, 18 do
		local x = center.X + (math.random() - 0.5) * sizeX * 0.9
		local z = center.Z + (math.random() - 0.5) * sizeZ * 0.9
		local r = math.random(10, 22)
		-- Place near the new floor so they read as boulders sitting on it.
		fillBall(x, -28 + r * 0.5, z, r, Enum.Material.Basalt)
	end
end

-- Trench: deepest zone. Vertical rock walls, very dark water. Floor at Y = -50.
local function generateTrench(center: Vector3, sizeX: number, sizeZ: number)
	fillBox(center.X, -30, center.Z, sizeX, 40, sizeZ, Enum.Material.Water)
	fillBox(center.X, -52, center.Z, sizeX, 4, sizeZ, Enum.Material.Rock)

	-- Tall vertical rock spires emerging from the trench floor. These are
	-- the "you have arrived" landmark visible from the surface.
	for _ = 1, 12 do
		local x = center.X + (math.random() - 0.5) * sizeX * 0.85
		local z = center.Z + (math.random() - 0.5) * sizeZ * 0.85
		local h = math.random(30, 50)
		local w = math.random(10, 18)
		fillBox(x, -50 + h / 2, z, w, h, w, Enum.Material.Rock)
	end
end

-- ====================================================================
-- BIOME WATER TINT
-- Roblox Terrain.WaterColor is global, so we fake per-biome water color
-- with a thin translucent slab at the water surface. From above, the
-- player sees the slab's color blended over the terrain water below it.
-- The slab has CanCollide/CanQuery/CanTouch = false so it's purely visual.
-- ====================================================================
local function tintZone(centerX: number, centerZ: number, sizeX: number, sizeZ: number, color: Color3, transparency: number)
	local part = Instance.new("Part")
	part.Name = "BiomeTint"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Thin slab parked just above the Terrain water surface (Y≈0). The 0.05
	-- offset prevents z-fighting with the Terrain water plane.
	part.Size = Vector3.new(sizeX, 0.4, sizeZ)
	part.CFrame = CFrame.new(centerX, 0.05, centerZ)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency
	-- Glow so the tint reads even when sunlight is direct. Material.Neon
	-- would be too punchy; we just nudge it slightly so the color doesn't
	-- get washed out at noon.
	part.CastShadow = false
	part.Parent = Workspace
	return part
end

-- Scatter small rocks around the world edges for far-distance silhouette.
local function scatterOutcrops(seaCenter: Vector3, count: number)
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local dist = 280 + math.random() * 140
		local x = seaCenter.X + math.cos(angle) * dist
		local z = seaCenter.Z + math.sin(angle) * dist
		local r = math.random(8, 18)
		fillBall(x, r * 0.4, z, r, Enum.Material.Rock)
	end
end

-- ====================================================================
-- INVISIBLE BIOME SENSOR PARTS
-- These don't produce visuals — they're just AABB volumes WorldService
-- checks each tick to update player.Character.CurrentBiome.
-- ====================================================================
local function buildBiomeSensor(name: string, biome: string, cframe: CFrame, size: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cframe
	p:SetAttribute("Biome", biome)
	p.Parent = Workspace
	return p
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function WorldService:KnitStart()
	local seaCenter = Vector3.new(WORLD_RADIUS - PLOT_SPACING, 0, WORLD_RADIUS - PLOT_SPACING)

	-- 1. Base ocean (sand floor + water column).
	fillSeaBase(seaCenter)

	-- 2. Main sandy island visible north of the plot grid — somewhere players
	--    can swim to and walk around on.
	generateIsland(
		seaCenter.X,
		seaCenter.Z - PLOT_SPACING * 2.5,
		150, 10,
		Enum.Material.Sand
	)

	-- 3. Big rocky island in the deep-water corner — anchors the horizon.
	generateIsland(
		seaCenter.X + PLOT_SPACING * 3,
		seaCenter.Z + PLOT_SPACING * 3,
		90, 28,
		Enum.Material.Rock
	)

	-- 4. Reef zone — bright tropical cyan tint over shallow varied seabed.
	local reefCenter = Vector3.new(seaCenter.X, 0, seaCenter.Z + PLOT_SPACING * (PLOT_GRID - 1) + 60)
	local reefSize = Vector3.new(WORLD_RADIUS * 1.6, 80, 120)
	generateReef(reefCenter, reefSize.X, reefSize.Z)
	buildBiomeSensor("Zone_Reef", "Reef", CFrame.new(reefCenter), reefSize)
	tintZone(reefCenter.X, reefCenter.Z, reefSize.X, reefSize.Z, Color3.fromRGB(70, 200, 200), 0.55)
	table.insert(self._biomeZones, { biome = "Reef", cframe = CFrame.new(reefCenter), size = reefSize })

	-- 5. DeepWater — deep indigo over the basalt basin.
	local deepCenter = Vector3.new(seaCenter.X, 0, seaCenter.Z + PLOT_SPACING * (PLOT_GRID - 1) + 200)
	local deepSize = Vector3.new(WORLD_RADIUS * 1.6, 80, 200)
	generateDeepWater(deepCenter, deepSize.X, deepSize.Z)
	buildBiomeSensor("Zone_DeepWater", "DeepWater", CFrame.new(deepCenter), deepSize)
	tintZone(deepCenter.X, deepCenter.Z, deepSize.X, deepSize.Z, Color3.fromRGB(20, 60, 130), 0.45)
	table.insert(self._biomeZones, { biome = "DeepWater", cframe = CFrame.new(deepCenter), size = deepSize })

	-- 6. Trench — near-black abyssal tint at the world's edge.
	local trenchCenter = Vector3.new(seaCenter.X, 0, seaCenter.Z + PLOT_SPACING * (PLOT_GRID - 1) + 440)
	local trenchSize = Vector3.new(WORLD_RADIUS * 1.6, 100, 200)
	generateTrench(trenchCenter, trenchSize.X, trenchSize.Z)
	buildBiomeSensor("Zone_Trench", "Trench", CFrame.new(trenchCenter), trenchSize)
	tintZone(trenchCenter.X, trenchCenter.Z, trenchSize.X, trenchSize.Z, Color3.fromRGB(10, 20, 50), 0.35)
	table.insert(self._biomeZones, { biome = "Trench", cframe = CFrame.new(trenchCenter), size = trenchSize })

	-- 7. Distant rocks for far-horizon silhouette.
	scatterOutcrops(seaCenter, 12)

	-- ----------------------------------------------------------------
	-- PLAYER BIOME TRACKING
	-- ----------------------------------------------------------------
	-- Stamp a CurrentBiome StringValue on each character; default Shoreline.
	-- Also teleport new spawns onto their plot's dock plate.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char) self:_onCharacter(player, char) end)
		if player.Character then self:_onCharacter(player, player.Character) end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function(char) self:_onCharacter(p, char) end)
		if p.Character then self:_onCharacter(p, p.Character) end
	end

	-- 1Hz biome resolution. Cheap; no need for Heartbeat.
	task.spawn(function()
		while true do
			task.wait(1)
			self:_resolveBiomes()
		end
	end)
end

function WorldService:_onCharacter(player: Player, char: Model)
	local existing = char:FindFirstChild("CurrentBiome")
	if not existing then
		local sv = Instance.new("StringValue")
		sv.Name = "CurrentBiome"
		sv.Value = "Shoreline"
		sv.Parent = char
	end
	-- Teleport to plot's dock plate.
	task.defer(function()
		task.wait(0.1)
		local HarborService = Knit.GetService("HarborService")
		local origin = HarborService:GetPlotOrigin(player)
		if origin and char:FindFirstChild("HumanoidRootPart") then
			(char.HumanoidRootPart :: BasePart).CFrame = origin * CFrame.new(PLOT / 2, 6, PLOT / 2)
		end
	end)
end

function WorldService:_resolveBiomes()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local sv = char:FindFirstChild("CurrentBiome") :: StringValue?
		if not sv then continue end

		local pos = hrp.Position
		local resolved = "Shoreline"
		for _, zone in ipairs(self._biomeZones) do
			-- Inverse-CFrame AABB check — avoids square-root for distance and
			-- handles arbitrary zone rotation (we don't currently rotate but
			-- this future-proofs).
			local local_ = zone.cframe:PointToObjectSpace(pos)
			if math.abs(local_.X) <= zone.size.X / 2
				and math.abs(local_.Y) <= zone.size.Y / 2
				and math.abs(local_.Z) <= zone.size.Z / 2
			then
				resolved = zone.biome
				break
			end
		end
		if sv.Value ~= resolved then sv.Value = resolved end
	end
end

return WorldService
