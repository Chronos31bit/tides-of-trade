-- DEV ONLY — placeholder building model generator.
--
-- Populates ReplicatedStorage.Assets.Buildings.<kind>.tier{1,2,3}.Visual with
-- procedural placeholder Models so the harbor visual system can boot in Studio
-- without art assets. Delete this script (and ReplicatedStorage.Assets in
-- the project, if regenerated) once real art is uploaded.
--
-- Per-tier aesthetic (confirmed in design Q&A: there is no "broken" tier;
-- tier 1 IS the rundown visual state — debris spawns around it client-side):
--   tier 1  — weathered, smaller, desaturated. The "rundown" look.
--   tier 2  — full color & size, a second detail block on top.
--   tier 3  — luxurious. tier-2 silhouette plus a gold-trim cap block.
--
-- Each Visual Model has its PrimaryPart set to the base block, sitting at
-- footprint bottom-center, so HarborVisualController:PivotTo(gridToWorld(...))
-- positions it correctly on the plot plate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuildingCatalog   = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local GameConfig        = require(ReplicatedStorage.Shared.Config.GameConfig)

local CELL = GameConfig.Harbor.GridCellStuds

-- ====================================================================
-- KIND_STYLE — per-building color/material baseline. Tier modifiers are
-- applied on top (see tintForTier + sizing block in buildModel).
-- ====================================================================
local KIND_STYLE: {[string]: any} = {
	Dock        = { color = Color3.fromRGB(120, 90, 60),   material = Enum.Material.WoodPlanks, walkable = true },
	MarketStall = { color = Color3.fromRGB(190, 80, 60),   material = Enum.Material.Fabric },
	Smokehouse  = { color = Color3.fromRGB(80, 80, 85),    material = Enum.Material.Slate },
	Lighthouse  = { color = Color3.fromRGB(230, 230, 220), material = Enum.Material.Concrete, isTall = true },
	BaitShop    = { color = Color3.fromRGB(100, 130, 80),  material = Enum.Material.Wood },
	Aquarium    = { color = Color3.fromRGB(80, 160, 200),  material = Enum.Material.Glass, transparency = 0.3 },
	Guildhall   = { color = Color3.fromRGB(140, 130, 110), material = Enum.Material.Marble },
}

local FALLBACK_STYLE = { color = Color3.fromRGB(180, 180, 180), material = Enum.Material.Plastic }

local function tintForTier(base: Color3, tier: number): Color3
	local h, s, v = base:ToHSV()
	if tier == 1 then
		-- Rundown: desaturate hard, darken.
		return Color3.fromHSV(h, s * 0.4, v * 0.55)
	elseif tier == 2 then
		return base
	else
		return Color3.fromHSV(h, math.min(1, s * 1.1), math.min(1, v * 1.15))
	end
end

local function buildModel(kind: string, tier: number, footprint: {number}): Model
	local style = KIND_STYLE[kind] or FALLBACK_STYLE
	local w, d = footprint[1], footprint[2]
	local widthStuds = w * CELL
	local depthStuds = d * CELL

	local heightStuds = style.isTall and (6 + tier * 6) or (4 + tier * 2)

	if tier == 1 then
		-- Slight shrink keeps the silhouette obviously incomplete at a glance.
		widthStuds = widthStuds * 0.9
		depthStuds = depthStuds * 0.9
		heightStuds = heightStuds * 0.85
	end

	local color = tintForTier(style.color, tier)

	local model = Instance.new("Model")
	model.Name = "Visual"

	-- ---- BASE ---------------------------------------------------------
	-- Anchor at footprint bottom-center → CFrame.new(0, height/2, 0).
	-- HarborVisualController PivotTo()s the Model to the world target, which
	-- moves the PrimaryPart there and brings every other part along.
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.CanCollide = true
	base.Material = style.material
	base.Color = color
	base.Size = Vector3.new(widthStuds, heightStuds, depthStuds)
	base.CFrame = CFrame.new(0, heightStuds / 2, 0)
	if style.transparency then
		base.Transparency = style.transparency * (tier == 1 and 0.7 or 1)
	end
	base.Parent = model
	model.PrimaryPart = base

	-- ---- TIER 2+: detail block ---------------------------------------
	if tier >= 2 then
		local detailH = heightStuds * 0.4
		local detail = Instance.new("Part")
		detail.Name = "Detail"
		detail.Anchored = true
		detail.CanCollide = false
		detail.Material = style.material
		detail.Color = color:Lerp(Color3.fromRGB(255, 255, 255), 0.15)
		detail.Size = Vector3.new(widthStuds * 0.6, detailH, depthStuds * 0.6)
		detail.CFrame = CFrame.new(0, heightStuds + detailH / 2, 0)
		detail.Parent = model
	end

	-- ---- TIER 3: gold-trim cap ---------------------------------------
	if tier >= 3 then
		local detailH = heightStuds * 0.4
		local capH = heightStuds * 0.2
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Anchored = true
		cap.CanCollide = false
		cap.Material = Enum.Material.Metal
		cap.Color = Color3.fromRGB(220, 180, 88)
		cap.Size = Vector3.new(widthStuds * 0.35, capH, depthStuds * 0.35)
		cap.CFrame = CFrame.new(0, heightStuds + detailH + capH / 2, 0)
		cap.Parent = model
	end

	-- Footprint hint for the controller. Format "WxD" in unrotated cells.
	local fp = Instance.new("StringValue")
	fp.Name = "Footprint"
	fp.Value = ("%dx%d"):format(w, d)
	fp.Parent = model

	-- TODO: Replace with art asset. Footprint: (w)x(d) cells; PrimaryPart
	-- anchors at footprint bottom-center so Model:PivotTo() lands the
	-- base at plate level. Match the placeholder's PrimaryPart placement
	-- when you swap in real art so positioning math doesn't drift.

	return model
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end
	local f = Instance.new("Folder"); f.Name = name; f.Parent = parent
	return f
end

local function main()
	local assets = ensureFolder(ReplicatedStorage, "Assets")
	local buildings = ensureFolder(assets, "Buildings")

	for kind, def in pairs(BuildingCatalog) do
		local kindFolder = ensureFolder(buildings, kind)
		-- Skip if real art is already present (Visual present in tier1).
		local existingT1 = kindFolder:FindFirstChild("tier1")
		if existingT1 and existingT1:FindFirstChild("Visual") then
			continue
		end
		for tier = 1, 3 do
			local tierFolder = ensureFolder(kindFolder, "tier" .. tier)
			-- Clear any prior placeholder so re-run regenerates cleanly.
			local stale = tierFolder:FindFirstChild("Visual")
			if stale then stale:Destroy() end
			local model = buildModel(kind, tier, def.footprint)
			model.Parent = tierFolder
		end
	end
end

main()
