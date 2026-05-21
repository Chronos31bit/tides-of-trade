# Studio QA — Phase 1 audio

**Date:** 2026-05-21  
**Studio place:** fishing sim idk yet  
**Method:** MCP `execute_luau` preload + play all `AssetIds.Sounds` IDs

## Playback

| Sound | Loaded | Duration (s) | Playing |
|-------|--------|--------------|---------|
| AmbientOcean | yes | ~46.6 | yes |
| CastSplash | yes | ~1.8 | yes |
| FishBite | yes | ~1.4 | yes |
| CatchSuccess | yes | ~1.5 | yes |
| CatchFail | yes | ~0.4 | yes |
| PerfectFlash | yes | ~0.37 | yes |
| HarborUpgrade | yes | ~1.8 | yes |
| CoinClink | yes | ~0.2 | yes |

## Notes

- Rojo must be synced for in-game `SoundController` to read updated `AssetIds.lua` from disk.
- Ambient loop + ducking logic lives in `SoundController`; full ducking test requires Play mode with Knit client running.
- `PerfectFlash` SFX fires even when Reduced Motion skips the visual flash (audio is not decorative-only).
- Replace library IDs with owned uploads before commercial launch; verify licenses on Creator Store pages.
