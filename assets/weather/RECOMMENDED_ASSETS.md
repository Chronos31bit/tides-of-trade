# Recommended weather assets (Creator Store)

Curated after MCP Creator Store search + insert tests in Studio (May 2026).

## Rain — use this

| Field | Value |
|-------|--------|
| **Creator Store asset** | [5323533667](https://create.roblox.com/store/asset/5323533667) |
| **Insert name in Toolbox** | Search: `rain particle effect` → type **particle effect** |
| **Structure** | Model `Raining` → Parts + 2× `ParticleEmitter` + optional sound |
| **Main rain texture** | `rbxassetid://671728795` (rate ~1000, speed ~75 in source) |
| **Secondary** | `rbxassetid://270368855` (light mist sheet) |

**Installed in place as:** `ReplicatedStorage.Assets.Weather.Rain.RainVolume` (cloned from store; emitters set to `Bottom`, disabled until runtime).

**Procedural fallback** (no store): texture `rbxassetid://419625073` — see `CommandBar_SetupWeatherAssets.luau`.

### Other rain textures (scripts / modules; may need “trust asset” in Studio)

| Asset ID | Source | Notes |
|----------|--------|--------|
| `419625073` | Tutorials / GameConfig default | 1×1 streak; good fallback |
| `1822883048` | [buildthomas/Rain](https://github.com/buildthomas/Rain) | Straight rain module texture |
| `1822856633` | buildthomas/Rain | Top-down + splash |
| `304777684` | Tutorials | Snow/rain variant |

---

## Storm — no good free “storm pack” found

| Store search result | Asset ID | Verdict |
|---------------------|----------|---------|
| `storm lightning rain` → weather | `14413753` | Model, **0** particle emitters |
| Same search alts | `31887782`, `71815967`, `19182769` | Not authorized or no emitters in test |

**Recommendation:** Use **Rain** asset above as `StormRain` with higher rate/spread (already done in Studio install), plus code-side `GameConfig.Weather.Rain.StormRateMultiplier` and server **Clouds** + lightning CC.

**Installed as:** `ReplicatedStorage.Assets.Weather.Storm.StormRain` (clone of rain, tuned emitters).

---

## Fog — use this (cozy, low rate)

| Field | Value |
|-------|--------|
| **Creator Store asset** | [72521990827105](https://create.roblox.com/store/asset/72521990827105) |
| **Insert** | Search: `fog particle effect` |
| **Structure** | Model → Part `Smoke` → 1× `ParticleEmitter` |
| **Texture** | `rbxassetid://7731347137` |
| **Source rate** | 20 (capped to **8** in install for cozy harbor) |

**Avoid for cozy fog:** asset `131768932120754` — rate **9000**, too heavy.

**Installed as:** `ReplicatedStorage.Assets.Weather.Fog.GroundMist`.

**Built-in fallback:** `rbxasset://textures/particles/smoke_main.dds`

---

## Audio (already in project)

Your `AssetIds.lua` already has rain/wind/thunder/fog loops uploaded — keep those; disable or zero volume on particle **Sound** children inside store models.

---

## Re-install / refresh templates

1. MCP or Toolbox: insert assets above into `Workspace`.
2. Run [`scripts/Studio/CommandBar_SetupWeatherAssets.luau`](../../scripts/Studio/CommandBar_SetupWeatherAssets.luau) for procedural-only setup, **or**
3. Ask agent to re-run the Studio `execute_luau` install block from the chat that clones `Raining` / `Smoke` into `ReplicatedStorage.Assets.Weather`.

**Save the place** after install — assets are not in Rojo until you add an `Assets` `$path`.
