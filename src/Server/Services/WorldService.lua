--!strict
-- WorldService.lua
-- Sets up the static world: a single big water plane spanning the plot grid,
-- plus tagged biome zones that update each player's CurrentBiome StringValue
-- as they roam. FishingService reads CurrentBiome to decide what can bite.
--
-- Why server-authoritative biomes: the client's location can be spoofed, so
-- biome eligibility has to be computed server-side from the actual character
-- position.

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local WorldService = Knit.CreateService({
	Name = "WorldService",
	_biomeZones = {} :: {{cframe: CFrame, size: Vector3, biome: string}},
})

-- ====================================================================
-- WATER + WORLD GEOMETRY
-- ====================================================================
-- We span enough water to cover the 4x4 plot grid plus generous margins so
-- DeepWater can live "out at sea" past the last plot.
local PLOT = GameConfig.Harbor.PlotSizeStuds
local PLOT_SPACING = PLOT + 40
local PLOT_GRID = 4
local WORLD_RADIUS = PLOT_SPACING * (PLOT_GRID + 2)  -- enough for DeepWater + Trench rings

-- ====================================================================
-- TERRAIN GENERATION
-- Replaces the previous part-based water with proper Terrain water + a
-- procedural sandy island ring at the world's edge + scattered rocky
-- outcrops in the deep-water zone (atmospheric, walkable, fishable from).
-- ====================================================================

-- Bulk-fill water across the playable area. Single FillBlock call so this
-- is fast even at world scale.
local function fillWater(seaCenter: Vector3)
	Workspace.Terrain:FillBlock(
		CFrame.new(seaCenter.X, -10, seaCenter.Z),
		Vector3.new(WORLD_RADIUS * 2, 20, WORLD_RADIUS * 2),
		Enum.Material.Water
	)
end

-- Generate one organic-shaped sandy island. We layer ~50 overlapping balls
-- of varying radii at jittered positions inside `baseRadius`; the result
-- looks far more natural than a single sphere because the silhouette is
-- noisy in 3D.
local function generateIsland(centerX: number, centerZ: number, baseRadius: number, peakHeight: number, material: Enum.Material)
	local terrain = Workspace.Terrain
	local sphereCount = math.floor(baseRadius / 6)  -- denser for bigger islands
	for i = 1, sphereCount do
		-- Sample points biased toward the center so the island has a clear
		-- mass with feathered edges. r in [0, baseRadius * 0.85].
		local angle = math.random() * math.pi * 2
		local r = math.sqrt(math.random()) * baseRadius * 0.85
		local x = centerX + math.cos(angle) * r
		local z = centerZ + math.sin(angle) * r
		-- Sphere radius scales down toward the island edge, so the silhouette
		-- tapers cleanly at the coast.
		local edgeFactor = 1 - (r / baseRadius)
		local sphereR = math.random(8, 22) * (0.6 + edgeFactor * 0.7)
		-- Height: tallest in the middle, lowest at edges (a beach slope).
		local h = peakHeight * (0.3 + edgeFactor * 0.7) + math.noise(x * 0.05, z * 0.05) * 2
		terrain:FillBall(Vector3.new(x, h - sphereR / 2, z), sphereR, material)
	end
end

-- Scatter small rocky outcrops in the deep-water zone for atmosphere. Each
-- outcrop is just one or two rock spheres — not climbable land, more like
-- "stuff at the horizon".
local function scatterOutcrops(seaCenter: Vector3, count: number)
	local terrain = Workspace.Terrain
	for _ = 1, count do
		-- Position somewhere in the outer ring, 280..420 studs from sea center.
		local angle = math.random() * math.pi * 2
		local dist = 280 + math.random() * 140
		local x = seaCenter.X + math.cos(angle) * dist
		local z = seaCenter.Z + math.sin(angle) * dist
		local r = math.random(8, 18)
		terrain:FillBall(Vector3.new(x, r * 0.4, z), r, Enum.Material.Rock)
	end
end

local function buildBiomeZone(name: string, biome: string, cframe: CFrame, size: Vector3): Part
	-- Invisible sensor part. Players inside get the corresponding biome.
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
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

	-- 1. Sea — a single bulk fill of Terrain water.
	fillWater(seaCenter)

	-- 2. Main sandy island, off the "north" side of the plot grid. Players
	--    can swim/walk there from any plot. ~150 stud radius is big enough
	--    to be a real destination but doesn't dominate the skyline.
	generateIsland(
		seaCenter.X,
		seaCenter.Z - PLOT_SPACING * 2.5,
		150,    -- baseRadius
		10,     -- peakHeight
		Enum.Material.Sand
	)

	-- 3. A bigger, taller rocky island further out — gives the horizon shape
	--    and serves as the visual anchor for the DeepWater fishing zone.
	generateIsland(
		seaCenter.X + PLOT_SPACING * 3,
		seaCenter.Z + PLOT_SPACING * 3,
		90,
		28,
		Enum.Material.Rock
	)

	-- 4. Scattered small rocks in the deep-water ring.
	scatterOutcrops(seaCenter, 12)

	-- Default biome is Shoreline — every player starts there. We then carve
	-- out specific zones for Reef / DeepWater / Trench at the world edges.
	-- The further from origin, the harder the biome.
	local seaCenter = Vector3.new(WORLD_RADIUS - PLOT_SPACING, 0, WORLD_RADIUS - PLOT_SPACING)

	-- Reef ring: out past the plot grid but not at the world edge.
	table.insert(self._biomeZones, {
		biome = "Reef",
		cframe = CFrame.new(seaCenter + Vector3.new(0, 0, PLOT_SPACING * (PLOT_GRID - 1) + 60)),
		size = Vector3.new(WORLD_RADIUS, 80, 120),
	})
	buildBiomeZone("Zone_Reef", "Reef",
		CFrame.new(seaCenter + Vector3.new(0, 0, PLOT_SPACING * (PLOT_GRID - 1) + 60)),
		Vector3.new(WORLD_RADIUS, 80, 120))

	-- DeepWater: further still.
	table.insert(self._biomeZones, {
		biome = "DeepWater",
		cframe = CFrame.new(seaCenter + Vector3.new(0, 0, PLOT_SPACING * (PLOT_GRID - 1) + 200)),
		size = Vector3.new(WORLD_RADIUS, 80, 200),
	})
	buildBiomeZone("Zone_DeepWater", "DeepWater",
		CFrame.new(seaCenter + Vector3.new(0, 0, PLOT_SPACING * (PLOT_GRID - 1) + 200)),
		Vector3.new(WORLD_RADIUS, 80, 200))

	-- Trench: world's edge.
	table.insert(self._biomeZones, {
		biome = "Trench",
		cframe = CFrame.new(seaCenter + Vector3.new(0, 0, PLOT_SPACING * (PLOT_GRID - 1) + 440)),
		size = Vector3.new(WORLD_RADIUS, 80, 200),
	})
	buildBiomeZone("Zone_Trench", "Trench",
		CFrame.new(seaCenter + Vector3.new(0, 0, PLOT_SPACING * (PLOT_GRID - 1) + 440)),
		Vector3.new(WORLD_RADIUS, 80, 200))

	-- Per-character setup: stamp a CurrentBiome StringValue and start tracking.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char) self:_onCharacter(player, char) end)
		if player.Character then self:_onCharacter(player, player.Character) end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function(char) self:_onCharacter(p, char) end)
		if p.Character then self:_onCharacter(p, p.Character) end
	end

	-- Tick: 1Hz biome resolution. Cheap; no need to run on Heartbeat.
	task.spawn(function()
		while true do
			task.wait(1)
			self:_resolveBiomes()
		end
	end)
end

function WorldService:_onCharacter(player: Player, char: Model)
	-- Ensure CurrentBiome StringValue exists on the character.
	local existing = char:FindFirstChild("CurrentBiome")
	if not existing then
		local sv = Instance.new("StringValue")
		sv.Name = "CurrentBiome"
		sv.Value = "Shoreline"
		sv.Parent = char
	end

	-- Teleport new characters to their plot's dock so they spawn on the
	-- water's edge instead of the empty default origin.
	task.defer(function()
		-- Wait one frame so HumanoidRootPart is parented.
		task.wait(0.1)
		local HarborService = Knit.GetService("HarborService")
		local origin = HarborService:GetPlotOrigin(player)
		if origin and char:FindFirstChild("HumanoidRootPart") then
			(char.HumanoidRootPart :: BasePart).CFrame = origin * CFrame.new(PLOT / 2, 6, PLOT / 2)
		end
	end)
end

-- For each player, find which (if any) custom biome zone contains them and
-- update their CurrentBiome accordingly. Defaults to Shoreline.
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
			-- Cheap AABB check using inverse CFrame transform.
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
