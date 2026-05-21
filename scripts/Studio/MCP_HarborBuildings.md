# Harbor building visuals — Studio MCP workflow

Generate and install building meshes into `ReplicatedStorage.Assets.Buildings` so `HarborVisualController` clones them at runtime. Assets live in the **place file** (not Rojo-synced). **Save the place** after each session.

Prerequisites: [MCP_Setup.md](./MCP_Setup.md) (Studio MCP green, Cursor `Roblox_Studio` enabled).

## Asset contract

| Path | Content |
|------|---------|
| `ReplicatedStorage.Assets.Buildings.<Kind>.tier<N>.Visual` | `Model` with mesh geometry |
| `Visual.PrimaryPart` | Invisible part at bbox **bottom-center** |
| `Visual.Footprint` | `StringValue`, e.g. `"4x6"` |

**Orientation at `rotation = 0`:** width along world **X**, depth along **Z** (longer catalog axis → **+Z**). Shop fronts toward **−Z**; **Dock** pier extends toward **+Z**. AI meshes often bake ~45° yaw — always run [CommandBar_InstallHarborVisual.luau](./CommandBar_InstallHarborVisual.luau) (includes `alignVisualYaw`).

Footprints (grid cells × 4 studs; fit target = 90% of stud pad):

| Kind | Cells | Stud pad |
|------|-------|----------|
| Dock | 4×6 | 16×24 |
| MarketStall | 3×3 | 12×12 |
| Lighthouse | 3×3 | 12×12 |
| BaitShop | 2×3 | 8×12 |
| Smokehouse | 3×4 | 12×16 |
| Aquarium | 3×4 | 12×16 |
| Guildhall | 5×5 | 20×20 |

## Workflow per tier

1. Clear kind: [CommandBar_ClearHarborBuildings.luau](./CommandBar_ClearHarborBuildings.luau) (`KIND = "MarketStall"`)
2. MCP `generate_mesh` (prompts below; add **axis-aligned, no diagonal rotation, longer side along Z**)
3. Edit + run [CommandBar_InstallHarborVisual.luau](./CommandBar_InstallHarborVisual.luau) (`KIND`, `TIER`, footprint, `FACING_YAW_EXTRA`)
4. Repeat tiers 2–3
5. Save place

`BuildAssetPlaceholders.server.lua` skips kinds that already have `tier1.Visual`.

## Prompts (v2)

**Canonical table:** [`HarborMeshPrompts.lua`](./HarborMeshPrompts.lua) — use these for regen; tier sentences describe silhouette, materials, tier read.

### Prefix (prepend to every tier prompt)

> Stylized cozy Roblox harbor game building, warm nautical colors, chunky readable silhouette, single cohesive structure, orthogonal straight edges axis-aligned to world grid, no diagonal rotation, no characters, no floating parts, sits on flat ground, game-ready asset

### Legacy per-kind tier prompts (append to prefix)

**Dock** (4×6; `FACING_YAW_EXTRA = 0`, pier toward +Z) — size x,y,z:

| Tier | Prompt | y |
|------|--------|---|
| 1 | wooden fishing dock pier tier 1 rundown: weathered dark wood, gaps, moss, crooked pilings, pier extends toward +Z | 6 |
| 2 | wooden dock pier tier 2 repaired: clean planks, rope railing, more pilings, pier toward +Z | 7 |
| 3 | wooden dock pier tier 3 grand: fresh wood, metal pilings, cleats, lantern posts, pier toward +Z | 9 |

**MarketStall** (3×3; sizes 12,5,12 / 12,6,12 / 12,7,12):

| Tier | Prompt |
|------|--------|
| 1 | open fish market stall tier 1: faded canvas awning, wooden crates, front counter toward -Z |
| 2 | fish market stall tier 2: striped teal awning, weighing scale, front toward -Z |
| 3 | fish market stall tier 3: ice bed display, gold sign, lanterns, front toward -Z |

**Lighthouse** (3×3; y 8/11/14):

| Tier | Prompt |
|------|--------|
| 1 | short white lighthouse tower tier 1 worn stone base |
| 2 | lighthouse tier 2 red and white horizontal bands, taller |
| 3 | tall lighthouse tier 3 bright glass lantern room on top |

**BaitShop** (2×3; sizes 8,5,12 / 8,6,12 / 8,7,12):

| Tier | Prompt |
|------|--------|
| 1 | fishing rod shop stand tier 1: wooden counter and rod sign, front toward -Z |
| 2 | rod shop tier 2: teal awning, rod rack, front toward -Z |
| 3 | rod shop tier 3: canopy, glass display case, warm lights, front toward -Z |

**Smokehouse** (3×4; sizes 12,6,16 / 12,7,16 / 12,9,16):

| Tier | Prompt |
|------|--------|
| 1 | stone smokehouse tier 1: small smoker chimney, door toward +Z |
| 2 | brick smokehouse tier 2: wooden door, taller chimney |
| 3 | smokehouse tier 3: fish drying racks, copper chimney, weather vane |

**Aquarium** (3×4; sizes 12,5,16 / 12,7,16 / 12,9,16):

| Tier | Prompt |
|------|--------|
| 1 | barrel fish aquarium display tier 1, glass panel toward -Z |
| 2 | glass fish tank building tier 2 brass trim, front glass -Z |
| 3 | grand marble aquarium gallery tier 3 large tank, path toward +Z |

**Guildhall** (5×5; sizes 20,8,20 / 20,10,20 / 20,12,20; maxTriangles 12000 on tier 3):

| Tier | Prompt |
|------|--------|
| 1 | wooden guild hall tier 1: peaked roof, red banner, notice board, entrance -Z |
| 2 | guild hall tier 2: stone entry arch, bell, pennants, entrance -Z |
| 3 | guild hall tier 3: stone facade, stained glass, gold crest, entrance -Z |

`maxTriangles`: 10000 (12000 Guildhall/Dock tier 3).

## Re-align existing mesh (no regen)

MCP `execute_luau` on in-place `Visual` models — same `alignVisualYaw` + `anchorBottomCenter` as install script; see agent session or duplicate logic from `CommandBar_InstallHarborVisual.luau`.

## Validate

- `meshYaw` ≈ 0° on `body_geom` after install
- Top-down: building edges parallel to plot at rotation 0
- Play: no `HarborVisualController` missing-asset warn; clones use `MeshPart` not `Plank0`/`Walls`

## Save

**File → Save** (Ctrl+S). MCP cannot save the place file.

## Status

**v2 regen (latest):** All **7 kinds × 3 tiers** regenerated with improved prompts in [`HarborMeshPrompts.lua`](./HarborMeshPrompts.lua) + `alignVisualYaw` install. Dock/MarketStall redone in main session; Lighthouse through Guildhall in follow-up pass.
