-- Command bar: spawn one preview fish per modifier in a grid.
-- Works in Play Solo (grid in front of you) OR Edit mode (fixed world position).
-- Paste entire script into Studio command bar, or run via Rojo-synced ModuleScript.
--
-- Re-running clears workspace._ModifierPreview and respawns everything.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local GameConfig          = require(ReplicatedStorage.Shared.Config.GameConfig)
local ModifierMutations   = require(ReplicatedStorage.Shared.Config.ModifierMutations)
local FishMutations       = require(ReplicatedStorage.Shared.Util.FishMutations)

-- ====================================================================
-- CONFIG
-- ====================================================================
local CONFIG = {
	-- Fish model used for EVERY preview cell (one species, all modifiers).
	SPECIES_ID = "harbor_mackerel",

	-- true = every FishModifiers entry that has a ModifierMutations visual (sorted A→Z).
	INCLUDE_ALL = true,
	-- When INCLUDE_ALL is false, spawn only these ids (grid order left→right).
	MODIFIER_IDS = { "rainbow", "silver", "golden", "storm_forged", "shocked", "frozen" },

	INCLUDE_DEPRECATED  = true,
	INCLUDE_WORLD_STATE = true,

	-- Edit mode: spawn at fixed world CFrame (no LocalPlayer needed).
	-- Play Solo: set false to place grid in front of your character.
	USE_FIXED_SPAWN = true,
	SPAWN_CFRAME    = CFrame.new(0, 6, -28), -- centre of grid; look from +Z

	-- Grid layout
	COLUMNS          = 6,
	SPACING_STUDS    = 6,
	ROW_SPACING      = 6,
	FRONT_OFFSET     = 0,   -- extra Z when using player-relative spawn
	HEIGHT_OFFSET    = 0,

	FISH_STUDS = 2.5,

	SHOW_LABELS     = true,
	LABEL_OFFSET_Y  = 2.2,
}

local ROOT_FOLDER_NAME = "_ModifierPreview"

-- ====================================================================
-- HELPERS
-- ====================================================================
local function clearExisting()
	local existing = Workspace:FindFirstChild(ROOT_FOLDER_NAME)
	if existing then existing:Destroy() end
end

local function pickModifiers(): {{id: string, displayName: string?}}
	if not CONFIG.INCLUDE_ALL and CONFIG.MODIFIER_IDS and #CONFIG.MODIFIER_IDS > 0 then
		local byId: {[string]: {id: string, displayName: string?}} = {}
		for _, m in ipairs(GameConfig.FishModifiers) do
			byId[m.id] = m
		end
		local mods: {{id: string, displayName: string?}} = {}
		for _, id in ipairs(CONFIG.MODIFIER_IDS) do
			local m = byId[id]
			if m then
				table.insert(mods, m)
			else
				warn(("[ModifierPreview] Unknown modifier id '%s' — skip"):format(id))
			end
		end
		return mods
	end

	local mods: {{id: string, displayName: string?}} = {}
	for _, m in ipairs(GameConfig.FishModifiers) do
		local isDeprecated = m.deprecated == true
		local isWorldState = (m.dropChance or 0) == 0 and not isDeprecated
		local isActive     = (m.dropChance or 0) > 0
		local include = CONFIG.INCLUDE_ALL
			or isActive
			or (isWorldState and CONFIG.INCLUDE_WORLD_STATE)
			or (isDeprecated and CONFIG.INCLUDE_DEPRECATED)
		if include and (ModifierMutations :: any)[m.id] then
			table.insert(mods, m)
		end
	end
	table.sort(mods, function(a, b)
		return a.id < b.id
	end)
	return mods
end

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fishFolder = assets and assets:FindFirstChild("Fish")
	if not fishFolder then
		warn("[ModifierPreview] ReplicatedStorage.Assets.Fish not found")
		return nil
	end
	local tmpl = fishFolder:FindFirstChild(CONFIG.SPECIES_ID)
	if not tmpl then
		warn(("[ModifierPreview] No '%s' — using first Fish model"):format(CONFIG.SPECIES_ID))
		tmpl = fishFolder:FindFirstChildOfClass("Model")
	end
	return tmpl :: Model?
end

local function getSpawnBaseCFrame(): CFrame
	if CONFIG.USE_FIXED_SPAWN then
		return CONFIG.SPAWN_CFRAME
	end
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local lookFlat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if lookFlat.Magnitude < 0.01 then lookFlat = Vector3.new(0, 0, -1) end
		lookFlat = lookFlat.Unit
		return CFrame.lookAt(hrp.Position, hrp.Position + lookFlat)
	end
	return CONFIG.SPAWN_CFRAME
end

local function findAnchorPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local named = model:FindFirstChild("body_geom", true)
	if named and named:IsA("BasePart") then return named end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then return d :: BasePart end
	end
	return nil
end

local function scaleModelUniform(model: Model, targetStuds: number)
	local _cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	if maxDim < 0.01 then return end
	local factor = targetStuds / maxDim
	-- ScaleTo keeps welds intact on rigged / nested fish.
	pcall(function()
		model:ScaleTo(factor)
	end)
end

local function makeLabel(parent: Instance, modId: string, displayName: string, anchorPart: BasePart)
	local bg = Instance.new("BillboardGui")
	bg.Name = "Label"
	bg.Adornee = anchorPart
	bg.AlwaysOnTop = true
	bg.Size = UDim2.fromOffset(200, 40)
	bg.StudsOffsetWorldSpace = Vector3.new(0, CONFIG.LABEL_OFFSET_Y, 0)
	bg.MaxDistance = 200
	bg.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	lbl.BackgroundTransparency = 0.2
	lbl.BorderSizePixel = 0
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextColor3 = Color3.fromRGB(245, 240, 220)
	lbl.Text = ("%s\n%s"):format(displayName or modId, modId)
	lbl.Parent = bg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = lbl
end

local function aimCameraAtGrid(root: Folder, cols: number, rows: number, spacing: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local centre = CONFIG.SPAWN_CFRAME.Position
	local width = (cols - 1) * spacing
	local depth = (rows - 1) * CONFIG.ROW_SPACING
	local dist = math.max(width, depth) * 0.85 + 14
	cam.CFrame = CFrame.new(
		centre + Vector3.new(width * 0.25, dist * 0.35, dist),
		centre
	)
end

-- ====================================================================
-- MAIN
-- ====================================================================
clearExisting()

local template = getTemplate()
if not template then
	warn("[ModifierPreview] Aborting — no fish model available")
	return
end

local mods = pickModifiers()
local cols = math.max(1, CONFIG.COLUMNS)
local rows = math.ceil(#mods / cols)

print(("[ModifierPreview] Spawning %d modifiers (%d×%d grid) — species '%s'")
	:format(#mods, cols, rows, CONFIG.SPECIES_ID))

local root = Instance.new("Folder")
root.Name = ROOT_FOLDER_NAME
root.Parent = Workspace

local baseCF = getSpawnBaseCFrame()
local spacing = CONFIG.SPACING_STUDS
local rowSpacing = CONFIG.ROW_SPACING

for i, m in ipairs(mods) do
	local idx0 = i - 1
	local col = idx0 % cols
	local row = math.floor(idx0 / cols)

	local xOffset = (col - (cols - 1) * 0.5) * spacing
	local zOffset = row * rowSpacing + CONFIG.FRONT_OFFSET
	local yOffset = CONFIG.HEIGHT_OFFSET

	local clone: Model = template:Clone()
	clone.Name = "Preview_" .. m.id
	clone.Parent = root

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored     = true
			bp.CanCollide   = false
			bp.CanTouch     = false
			bp.CanQuery     = false
			bp.Massless     = true
			bp.CastShadow   = false
		end
	end

	scaleModelUniform(clone, CONFIG.FISH_STUDS)

	local anchor = findAnchorPart(clone)
	if not anchor then
		warn("[ModifierPreview] No BasePart for", m.id)
		clone:Destroy()
		continue
	end

	local cell = baseCF * CFrame.new(xOffset, yOffset, zOffset)
	clone:PivotTo(cell)

	FishMutations.attach(anchor, { m.id })

	if CONFIG.SHOW_LABELS then
		makeLabel(clone, m.id, m.displayName or m.id, anchor)
	end
end

if CONFIG.USE_FIXED_SPAWN then
	aimCameraAtGrid(root, cols, rows, spacing)
end

print(("[ModifierPreview] Done → workspace.%s (%d fish). Re-run to refresh."):format(ROOT_FOLDER_NAME, #mods))
print("[ModifierPreview] Cleanup: workspace:FindFirstChild('_ModifierPreview'):Destroy()")
