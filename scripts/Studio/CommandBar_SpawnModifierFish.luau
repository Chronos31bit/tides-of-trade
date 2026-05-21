-- Command bar: spawn one preview fish per modifier in a grid in front of you.
-- Paste into the Studio command bar (Play Solo gives you the LocalPlayer this
-- relies on). Re-running clears the previous batch first.
--
-- Each fish is:
--   * cloned from ReplicatedStorage.Assets.Fish[SPECIES_ID]
--   * anchored (no physics), no collision, no shadow
--   * decorated via FishMutations.attach() so you see the live look
--   * labelled with a BillboardGui showing the modifier id + displayName
--
-- Tweak the CONFIG block below to switch fish species, include deprecated
-- modifiers, change grid spacing, or drop the BillboardGui labels.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local GameConfig    = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishMutations = require(ReplicatedStorage.Shared.Util.FishMutations)

-- ====================================================================
-- CONFIG
-- ====================================================================
local CONFIG = {
	-- Which species model to clone for every preview fish.
	-- Must exist as ReplicatedStorage.Assets.Fish.<id>.
	SPECIES_ID = "harbor_mackerel",

	-- Include deprecated modifiers (dropChance=0 AND deprecated=true)?
	-- Off by default — those are legacy mappings, you usually want only the
	-- shipping mutations plus the world-state ones.
	INCLUDE_DEPRECATED = false,

	-- Show world-state modifiers (tide_kissed, storm_forged, etc.)?
	INCLUDE_WORLD_STATE = true,

	-- Grid layout (looking forward from the player).
	COLUMNS         = 5,    -- fish per row
	SPACING_STUDS   = 5,    -- gap between centres
	FRONT_OFFSET    = 8,    -- distance from player to nearest row
	HEIGHT_ABOVE_HRP = 0,   -- vertical offset relative to HumanoidRootPart

	-- Uniform fish scale (target longest dim in studs).
	FISH_STUDS = 2.0,

	-- BillboardGui label above each fish.
	SHOW_LABELS = true,
	LABEL_OFFSET_Y = 1.8,
}

local ROOT_FOLDER_NAME = "_ModifierPreview"

-- ====================================================================
-- HELPERS
-- ====================================================================
local function clearExisting()
	local existing = Workspace:FindFirstChild(ROOT_FOLDER_NAME)
	if existing then existing:Destroy() end
end

local function pickModifiers()
	local mods = {}
	for _, m in ipairs(GameConfig.FishModifiers) do
		local isDeprecated = m.deprecated == true
		local isWorldState = (m.dropChance or 0) == 0 and not isDeprecated
		local isActive     = (m.dropChance or 0) > 0
		local include = isActive
			or (isWorldState and CONFIG.INCLUDE_WORLD_STATE)
			or (isDeprecated and CONFIG.INCLUDE_DEPRECATED)
		if include then
			table.insert(mods, m)
		end
	end
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
		warn(("[ModifierPreview] No model for species '%s' — falling back to first child"):format(CONFIG.SPECIES_ID))
		tmpl = fishFolder:FindFirstChildOfClass("Model")
	end
	return tmpl :: Model?
end

local function getPlayerCFrame(): CFrame
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		-- Look direction without pitch (so the grid sits at ground level).
		local lookFlat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z).Unit
		return CFrame.lookAt(hrp.Position, hrp.Position + lookFlat)
	end
	-- Fallback: world origin.
	return CFrame.new()
end

local function scaleFishToTarget(parts: {BasePart}, targetStuds: number)
	if #parts ~= 1 then return end
	local p = parts[1]
	local maxDim = math.max(p.Size.X, p.Size.Y, p.Size.Z)
	if maxDim > 0.01 then
		p.Size = p.Size * (targetStuds / maxDim)
	end
end

local function makeLabel(parent: Instance, modId: string, displayName: string, anchorPart: BasePart)
	local bg = Instance.new("BillboardGui")
	bg.Name = "Label"
	bg.Adornee = anchorPart
	bg.AlwaysOnTop = true
	bg.Size = UDim2.fromOffset(180, 36)
	bg.StudsOffsetWorldSpace = Vector3.new(0, CONFIG.LABEL_OFFSET_Y, 0)
	bg.MaxDistance = 80
	bg.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
	lbl.BackgroundTransparency = 0.25
	lbl.BorderSizePixel = 0
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(245, 240, 220)
	lbl.Text = ("%s\n(%s)"):format(displayName, modId)
	lbl.Parent = bg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = lbl

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = lbl
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
print(("[ModifierPreview] Spawning %d modifier previews using species '%s'")
	:format(#mods, CONFIG.SPECIES_ID))

local root = Instance.new("Folder")
root.Name = ROOT_FOLDER_NAME
root.Parent = Workspace

local baseCF = getPlayerCFrame()
local cols = math.max(1, CONFIG.COLUMNS)
local spacing = CONFIG.SPACING_STUDS

for i, m in ipairs(mods) do
	local idx0 = i - 1
	local col = idx0 % cols
	local row = math.floor(idx0 / cols)

	-- Centre the grid horizontally on the player's look line.
	local xOffset = (col - (cols - 1) * 0.5) * spacing
	local zOffset = -(CONFIG.FRONT_OFFSET + row * spacing)
	local yOffset = CONFIG.HEIGHT_ABOVE_HRP

	local clone: Model = template:Clone()
	clone.Name = "Preview_" .. m.id
	clone.Parent = root

	-- Collect parts + neutralise physics so the grid is stable.
	local parts: {BasePart} = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			local bp = d :: BasePart
			bp.Anchored   = true
			bp.CanCollide = false
			bp.CanTouch   = false
			bp.CanQuery   = false
			bp.Massless   = true
			bp.CastShadow = false
			table.insert(parts, bp)
		end
	end
	if #parts == 0 then continue end

	scaleFishToTarget(parts, CONFIG.FISH_STUDS)

	-- Place at grid cell. clone:PivotTo with a CFrame keeps every part welded
	-- to the model's PrimaryPart/first BasePart.
	local cell = baseCF * CFrame.new(xOffset, yOffset, zOffset)
	if clone.PrimaryPart then
		clone:PivotTo(cell)
	else
		clone.PrimaryPart = parts[1]
		clone:PivotTo(cell)
	end

	-- Anchor target for attach() — prefer PrimaryPart, fall back to first part.
	local anchor: BasePart = (clone.PrimaryPart or parts[1]) :: BasePart

	-- Attach the mutation. intensity=1.0 matches the in-hand look.
	FishMutations.attach(anchor, { m.id })

	if CONFIG.SHOW_LABELS then
		makeLabel(clone, m.id, m.displayName or m.id, anchor)
	end
end

print(("[ModifierPreview] Done. Folder: workspace.%s — re-run this script to refresh."):format(ROOT_FOLDER_NAME))
print("[ModifierPreview] Tip: to clean up without spawning, run:  workspace:FindFirstChild('" .. ROOT_FOLDER_NAME .. "'):Destroy()")
