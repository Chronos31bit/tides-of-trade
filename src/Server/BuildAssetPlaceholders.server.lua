--!strict
-- BuildAssetPlaceholders.server.lua
-- DEV ONLY ----------------------------------------------------------------
-- Runs once at server boot. If ReplicatedStorage.Assets.Buildings doesn't
-- exist (or is empty), this synthesizes placeholder Models for every
-- BuildingCatalog kind × tier so HarborVisualController has something to
-- clone. Once real art ships as .rbxmx files under src/Assets/Buildings/
-- (mapped via default.project.json), this script can be deleted — it's a
-- no-op when the folder is already populated.
--
-- We do NOT generate a "broken" Model variant. The current Profile schema
-- has no broken tier; the rundown-harbor feel comes from procedural debris
-- around tier-1 buildings (see HarborVisualController:_spawnDebris).
-- --------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local GameConfig      = require(ReplicatedStorage.Shared.Config.GameConfig)

local CELL = GameConfig.Harbor.GridCellStuds

-- ====================================================================
-- ASSET ROOT
-- ====================================================================
local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local assetsRoot   = ensureFolder(ReplicatedStorage, "Assets")
local buildingsRoot = ensureFolder(assetsRoot, "Buildings")

-- If the folder was hand-authored with real art, leave it alone. Detection:
-- if there's already a kind subfolder with at least one tier Model under it,
-- assume art is wired up and skip generation entirely.
local function isPopulated(): boolean
	for _, child in ipairs(buildingsRoot:GetChildren()) do
		if child:IsA("Folder") then
			for _, sub in ipairs(child:GetChildren()) do
				if sub:IsA("Folder") and sub:FindFirstChildOfClass("Model") then
					return true
				end
			end
		end
	end
	return false
end

if isPopulated() then
	print("[BuildAssetPlaceholders] Real assets detected, skipping placeholder generation.")
	return
end

-- ====================================================================
-- VISUAL DESIGN: tier 1 is a single block, tier 2 a block with a second
-- layer on top, tier 3 a base + roof + chimney/spire so contrast is
-- obvious "from 30 studs away" (success criterion #4).
-- ====================================================================

local function hueForKind(kind: string): number
	-- Stable hash. Same kind always gets the same hue.
	local h = 0
	for i = 1, #kind do
		h = (h * 31 + string.byte(kind, i)) % 360
	end
	return h / 360
end

local function makePart(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, canCollide: boolean): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = canCollide
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Build a placeholder Model for a (kind, tier). Origin is the model's
-- PrimaryPart, which sits at the *base center* of the footprint (matches
-- the convention HarborVisualController uses when calling Model:PivotTo).
local function buildVisual(kind: string, tier: number): Model
	local def = BuildingCatalog[kind]
	local w, d = def.footprint[1], def.footprint[2]
	-- Convert footprint cells to studs.
	local studW, studD = w * CELL, d * CELL

	local model = Instance.new("Model")
	model.Name = "Visual"

	local hue = hueForKind(kind)
	-- Tier brightens saturation + value: tier1 is muted, tier3 is vibrant.
	local sat = 0.35 + (tier - 1) * 0.15
	local val = 0.55 + (tier - 1) * 0.10
	local baseColor = Color3.fromHSV(hue, sat, val)
	local accentColor = Color3.fromHSV((hue + 0.08) % 1, math.min(1, sat + 0.2), math.min(1, val + 0.1))

	-- The PrimaryPart is a single full-footprint Body part that anchors at
	-- base center. Decorative parts stack flush on top — no floating gaps,
	-- no thin rim around a smaller block (avoids the "hollow base" look
	-- where you can see through a halo of base into open air).
	--
	-- Heights: tier 1 = solid block. Tier 2 = block + smaller second
	-- layer. Tier 3 = block + roof + flush spire and corner ornaments.
	local bodyHeight = 4 + tier * 1.5
	local primary = makePart(
		model,
		"Body",
		Vector3.new(studW, bodyHeight, studD),
		CFrame.new(0, bodyHeight / 2, 0),
		baseColor,
		Enum.Material.WoodPlanks,
		true   -- collidable so the player can walk on flat-top buildings
	)
	model.PrimaryPart = primary

	if tier >= 2 then
		local roofHeight = 2 + (tier - 1) * 0.8
		local roofY = bodyHeight + roofHeight / 2
		makePart(
			model,
			"Upper",
			Vector3.new(studW * 0.7, roofHeight, studD * 0.7),
			CFrame.new(0, roofY, 0),
			accentColor,
			Enum.Material.Slate,
			false
		)
	end
	if tier >= 3 then
		-- Spire sits flush on top of the body (no air gap).
		local spireH = 3
		local spireY = bodyHeight + spireH / 2
		makePart(
			model,
			"Spire",
			Vector3.new(0.8, spireH, 0.8),
			CFrame.new(0, spireY, 0),
			accentColor,
			Enum.Material.Metal,
			false
		)
		-- Two ornament cubes flush on the body top, near opposite corners.
		-- The corner offset stays inside the footprint so they don't poke
		-- past the building's edge.
		local ornaSize = 1.2
		local ornaX = studW * 0.4
		local ornaZ = studD * 0.4
		local ornaY = bodyHeight + ornaSize / 2
		makePart(
			model,
			"OrnamentA",
			Vector3.new(ornaSize, ornaSize, ornaSize),
			CFrame.new(ornaX, ornaY, ornaZ),
			accentColor,
			Enum.Material.Metal,
			false
		)
		makePart(
			model,
			"OrnamentB",
			Vector3.new(ornaSize, ornaSize, ornaSize),
			CFrame.new(-ornaX, ornaY, -ornaZ),
			accentColor,
			Enum.Material.Metal,
			false
		)
	end

	-- Footprint advertisement. Matches the prompt's "child StringValue named
	-- Footprint with a Value like '2x3'". HarborVisualController doesn't
	-- need this today (it reads the catalog directly), but real art will.
	local footprint = Instance.new("StringValue")
	footprint.Name = "Footprint"
	footprint.Value = ("%dx%d"):format(w, d)
	footprint.Parent = model

	-- TODO marker for art-replacement phase.
	-- TODO: Replace with art asset. Footprint: WxD cells (each cell = GameConfig.Harbor.GridCellStuds studs).
	--       Primary part anchors at base center; client uses Model:PivotTo() to position.
	local todo = Instance.new("StringValue")
	todo.Name = "__placeholder"
	todo.Value = ("TODO art: %s tier %d, footprint %dx%d"):format(kind, tier, w, d)
	todo.Parent = model

	return model
end

-- ====================================================================
-- POPULATE
-- ====================================================================
local generated = 0
for kind, def in pairs(BuildingCatalog) do
	local kindFolder = ensureFolder(buildingsRoot, kind)
	for tier = 1, #def.tiers do
		local tierFolderName = ("tier%d"):format(tier)
		local tierFolder = ensureFolder(kindFolder, tierFolderName)
		-- Skip if a Visual Model is already there (real art that arrived as
		-- a single Model under tierN/ — be tolerant).
		if not tierFolder:FindFirstChild("Visual") then
			local visual = buildVisual(kind, tier)
			visual.Parent = tierFolder
			generated += 1
		end
	end
end

print(("[BuildAssetPlaceholders] Generated %d placeholder Models."):format(generated))
