# Harbor building visuals — Studio MCP workflow

Generate and install building meshes into `ReplicatedStorage.Assets.Buildings` so `HarborVisualController` clones them at runtime. Assets live in the **place file** (not Rojo-synced). **Save the place** after each session.

Prerequisites: [MCP_Setup.md](./MCP_Setup.md) (Studio MCP green, Cursor `Roblox_Studio` enabled).

## Asset contract

| Path | Content |
|------|---------|
| `ReplicatedStorage.Assets.Buildings.<Kind>.tier<N>.Visual` | `Model` with mesh geometry |
| `Visual.PrimaryPart` | Invisible part at bbox **bottom-center** |
| `Visual.Footprint` | `StringValue`, e.g. `"4x6"` for Dock |

Footprints (grid cells × `GameConfig.Harbor.GridCellStuds` = 4 studs):

| Kind | Cells | Stud pad (×0.9 fit target) |
|------|-------|----------------------------|
| Dock | 4×6 | 16×24 |
| MarketStall | 3×3 | 12×12 |
| Smokehouse | 3×4 | 12×16 |
| Lighthouse | 3×3 | 12×12 |
| BaitShop | 2×3 | 8×12 |
| Aquarium | 3×4 | 12×16 |
| Guildhall | 5×5 | 20×20 |

Tier read (cozy pillar): tier1 rundown → tier2 repaired → tier3 grand (height + detail + tier3 lights where appropriate).

## 1. Clear old visuals

Command Bar: run [CommandBar_ClearHarborBuildings.luau](./CommandBar_ClearHarborBuildings.luau) with `KIND = "Dock"` or `"*"` for all.

Or MCP `execute_luau`:

```lua
local kind = "Dock" -- or nil to clear all kinds
local buildings = game.ReplicatedStorage.Assets.Buildings
for _, kindFolder in buildings:GetChildren() do
	if kind and kindFolder.Name ~= kind then continue end
	for _, tierFolder in kindFolder:GetChildren() do
		local v = tierFolder:FindFirstChild("Visual")
		if v then v:Destroy() end
	end
end
```

`BuildAssetPlaceholders.server.lua` only refills kinds with **no** `tier1.Visual`.

## 2. Generate mesh (MCP `generate_mesh`)

Use the same prompt prefix for style consistency:

> cozy Roblox harbor fishing game, low-poly stylized

**Dock pilot prompts**

| Tier | `textPrompt` (append to prefix) | `size` (x, y, z) |
|------|--------------------------------|------------------|
| 1 | wooden fishing dock pier, tier 1 rundown: weathered dark wood, gaps, moss, crooked pilings | 16, 6, 24 |
| 2 | wooden dock pier, tier 2 repaired: clean planks, rope railing, more pilings, no moss | 16, 7, 24 |
| 3 | wooden dock pier, tier 3 grand: fresh wood, metal pilings, cleats, warm lantern posts, taller ornate cozy | 16, 9, 24 |

`maxTriangles`: 10000–12000.

## 3. Install visual (MCP `execute_luau`)

After each `generate_mesh`, run install (set `TIER` and footprint cells):

```lua
local TIER = 1
local FOOTPRINT_W, FOOTPRINT_D = 4, 6
local TARGET_X, TARGET_Z = FOOTPRINT_W * 4 * 0.9, FOOTPRINT_D * 4 * 0.9

local function getSourceModel()
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("RBX_AI_GENERATED") then
			return child
		end
	end
	return nil
end

local function anchorBottomCenter(model: Model)
	local bbCF, bbSize = model:GetBoundingBox()
	local bottomCenter = Vector3.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2, bbCF.Position.Z)
	local shift = CFrame.new(-bottomCenter)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = shift * desc.CFrame
			desc.Anchored = true
			desc.CanCollide = true
			desc.CanQuery = false
			desc.CanTouch = false
		end
	end
	local pp = model:FindFirstChild("PrimaryPart")
	if pp then pp:Destroy() end
	pp = Instance.new("Part")
	pp.Name = "PrimaryPart"
	pp.Size = Vector3.new(0.2, 0.2, 0.2)
	pp.Transparency = 1
	pp.Anchored = true
	pp.CanCollide = false
	pp.CanQuery = false
	pp.CanTouch = false
	pp.Parent = model
	bbCF, bbSize = model:GetBoundingBox()
	bottomCenter = Vector3.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2, bbCF.Position.Z)
	pp.CFrame = CFrame.new(bottomCenter)
	model.PrimaryPart = pp
end

local src = getSourceModel()
assert(src, "No RBX_AI_GENERATED model in Workspace")

local visual = Instance.new("Model")
visual.Name = "Visual"
for _, desc in src:GetDescendants() do
	if desc:IsA("BasePart") then
		desc:Clone().Parent = visual
	end
end

local _, bbSize = visual:GetBoundingBox()
local scale = math.min(TARGET_X / bbSize.X, TARGET_Z / bbSize.Z)
if scale > 0 and math.abs(scale - 1) > 0.001 then
	visual:ScaleTo(scale)
end
anchorBottomCenter(visual)

local fp = Instance.new("StringValue")
fp.Name = "Footprint"
fp.Value = string.format("%dx%d", FOOTPRINT_W, FOOTPRINT_D)
fp.Parent = visual

local kindFolder = game.ReplicatedStorage.Assets.Buildings.Dock
local tierFolder = kindFolder:WaitForChild("tier" .. TIER)
local old = tierFolder:FindFirstChild("Visual")
if old then old:Destroy() end
visual.Parent = tierFolder
src:Destroy()

-- Optional tier3 dock lanterns (if mesh lacks them)
if TIER == 3 then
	local bbCF, sz = visual:GetBoundingBox()
	local y = bbCF.Position.Y - sz.Y / 2 + math.min(sz.Y * 0.85, 4.5)
	for i, xz in ipairs({{-sz.X * 0.35, -sz.Z * 0.35}, {sz.X * 0.35, -sz.Z * 0.35}}) do
		local anchor = Instance.new("Part")
		anchor.Name = "LanternAnchor" .. i
		anchor.Size = Vector3.new(0.35, 0.35, 0.35)
		anchor.Transparency = 0.25
		anchor.Color = Color3.fromRGB(210, 175, 60)
		anchor.Material = Enum.Material.Metal
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CFrame = CFrame.new(xz[1], y, xz[2])
		anchor.Parent = visual
		local pl = Instance.new("PointLight")
		pl.Brightness = 1.2
		pl.Range = 14
		pl.Color = Color3.fromRGB(255, 200, 120)
		pl.Parent = anchor
	end
end
```

Replace `Dock` / footprint constants per kind.

## 4. Validate

- `search_game_tree` → `ReplicatedStorage.Assets.Buildings.Dock`, depth 4
- Each `Visual` has `MeshPart`, `PrimaryPart`, `Footprint`
- Play: place/upgrade building; Output must **not** show `HarborVisualController` missing-asset fallback
- Cloned model should have `body_geom` (mesh), not `Plank0` (procedural)

## 5. Save

**File → Save** (or Ctrl+S). MCP cannot reliably save the place from the agent.

## Completed pilot

**Dock** tiers 1–3 installed via `generate_mesh` (May 2026). Other kinds still use procedural placeholders until repeated.
