-- DEV ONLY — placeholder building model generator.
--
-- Populates ReplicatedStorage.Assets.Buildings.<kind>.tier{1,2,3}.Visual with
-- procedural Models from BuildingModelFactory so harbor visuals boot in Studio
-- without art assets. Delete this script once real art is uploaded.
--
-- Tier 1 = rundown, tier 2 = repaired, tier 3 = grand (see BuildingModelFactory).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuildingCatalog   = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local BuildingModelFactory = require(ReplicatedStorage.Shared.Util.BuildingModelFactory)

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
			local stale = tierFolder:FindFirstChild("Visual")
			if stale then stale:Destroy() end
			local model = BuildingModelFactory.build(kind, tier, def.footprint)
			model.Name = "Visual"
			local fp = Instance.new("StringValue")
			fp.Name = "Footprint"
			fp.Value = ("%dx%d"):format(def.footprint[1], def.footprint[2])
			fp.Parent = model
			model.Parent = tierFolder
		end
	end
end

main()
