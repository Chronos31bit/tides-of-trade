# Weather VFX — Studio asset setup

**Curated Creator Store picks:** see [RECOMMENDED_ASSETS.md](RECOMMENDED_ASSETS.md).

Client code in `WorldFXController` clones templates from `ReplicatedStorage.Assets.Weather`.  
Templates are **not** synced by Rojo today — insert them once in Studio (or add a Rojo `$path` later).

## Folder layout

```
ReplicatedStorage
└── Assets
    └── Weather
        ├── Rain
        │   └── RainVolume      (Model or Part — see below)
        ├── Storm
        │   └── StormRain         (optional; falls back to Rain × multiplier)
        └── Fog
            └── GroundMist        (optional; atmosphere is primary fog)
```

## One-time Studio setup

### Option A — Command bar (recommended)

1. Open the place in Roblox Studio (edit mode).
2. Paste and run [`scripts/Studio/CommandBar_SetupWeatherAssets.luau`](../../scripts/Studio/CommandBar_SetupWeatherAssets.luau) in the command bar.
3. Confirm Explorer shows `ReplicatedStorage.Assets.Weather` with `RainVolume`, `StormRain`, `GroundMist`.

### Option B — Cursor + Roblox Studio MCP

With Studio open and the MCP plugin connected, an agent can run the same setup via `execute_luau` or `insert_from_creator_store`. **Note:** Creator Store search often returns hats/models, not particle volumes — the command-bar script builds correct `Part` + `Attachment` + `ParticleEmitter` templates instead.

### Option C — Manual Toolbox

1. Create folder layout under `ReplicatedStorage.Assets.Weather`.
2. Insert toolbox rain/fog assets only if they are real `ParticleEmitter` packs.
3. Rename to `RainVolume`, `StormRain`, `GroundMist` and tune (see structure below).

Optional: paste texture `rbxassetid://` values into `src/Client/AssetIds.lua` (`Images.RainStreak`, `Images.FogMist`).

## RainVolume structure

Either:

- A **Part** (or Model with PrimaryPart) named `RainVolume` with a child `Attachment` and one or more `ParticleEmitter`s, or
- A bare `ParticleEmitter` named `RainVolume` (legacy; still supported)

Recommended part size in template: ~40 × 1 × 40 studs (code overrides follower size from `GameConfig.Weather.Rain.VolumeSizeStuds`).

## StormRain

Same structure as `RainVolume`. If missing, Storm uses `Rain/RainVolume` with `GameConfig.Weather.Rain.StormRateMultiplier`.

## GroundMist

Wide low sheet at harbor height (`GameConfig.Weather.Fog.SheetWorldY`). If missing, Fog uses **atmosphere only** (no particle bubble).

## Play Solo validation

1. F8 admin panel → cycle Clear, Rain, Storm, Fog.
2. Output should log e.g. `[WorldFX] Rain: Assets.Weather.Rain.RainVolume template`.
3. Rain falls **downward** when looking at the sky (world-upright volume, not camera-local).
4. Fog reads globally; harbor visible ~30 studs.
5. Storm: dark clouds, heavy rain, lightning ≥8 s apart.

## Command bar smoke test

Paste `scripts/Studio/CommandBar_TestWeather.luau` into the Studio command bar during Play Solo.
