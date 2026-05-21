# Source WAV staging area

Drop your final, mixed WAV files here before uploading to Roblox
Creator Dashboard. Filenames are locked to the entries in
[`../TRACKING.md`](../TRACKING.md) — use them verbatim so the
upload workflow stays predictable.

| Slot | Filename | Notes |
|------|----------|-------|
| 1 | `ambient_ocean.wav`     | Stereo, 30–90 s seamless loop |
| 2 | `music_harbor_theme.wav`| Stereo, 60–120 s seamless loop |
| 3 | `cast_splash.wav`       | Mono, 0.3–0.8 s, positional |
| 4 | `fish_bite.wav`         | Mono, ≤ 1.5 s |
| 5 | `catch_success.wav`     | Mono, 0.6–1.0 s |
| 6 | `catch_fail.wav`        | Mono, 0.2–0.5 s, quieter than peers |
| 7 | `perfect_flash.wav`     | Mono, 200–400 ms |
| 8 | `harbor_upgrade.wav`    | Mono, 1.0–1.8 s |
| 9 | `coin_clink.wav`        | Mono, 0.15–0.35 s |

Per-slot sourcing prompts (CC0 + AI), reference vibes, anti-patterns,
and mix targets live in [`../SOUND_SPEC.md`](../SOUND_SPEC.md). Full
upload steps live in [`../UPLOAD.md`](../UPLOAD.md).

## Hybrid sourcing (per plan)

- **CC0 (Freesound / Kenney / Pixabay CC0)** — ocean ambient, UI ping,
  coin clink, splash, miss whoosh. Safe licensing, plenty of options.
- **AI (ElevenLabs Sound Effects / Stable Audio)** — fish bite, catch
  success, harbor upgrade, music harbor theme. Distinctive per-game
  feel; re-check commercial terms on the date of generation.

## Not committed

These WAVs are staging-only and shouldn't be committed to git (the
canonical copy lives on Roblox Creator Dashboard, identified by the
numeric ID in `src/Client/AssetIds.lua`). Treat this folder as a
local working directory.
