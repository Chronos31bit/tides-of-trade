# Audio asset tracking

All 13 slots sourced and ready for Roblox upload.
Source files live in `assets/audio/sources/*.mp3`.
Old placeholder `rbxassetid://` IDs cleared from `src/Client/AssetIds.lua`.
After uploading each file to Creator Dashboard, paste the numeric ID into `AssetIds.lua`.

| Slot key | Source file | Origin | Duration | Status |
|----------|-------------|--------|----------|--------|
| `AmbientOcean` | `ambient_ocean.mp3` | Freesound #852826 "Gentle Ocean Waves Loop" by kkenny101, **CC0** | 21.8s loop | **Ready to upload** |
| `MusicHarborTheme` | `music_harbor_theme.mp3` | Freesound #518917 "The calm theme" by BloodPixelHero, **CC BY 4.0** | 89.5s | **Ready to upload — attribution required** |
| `CastSplash` | `cast_splash.mp3` | ElevenLabs SFX generated | ~1s | **Ready to upload** |
| `FishBite` | `fish_bite.mp3` | ElevenLabs SFX generated | ~1s | **Ready to upload** |
| `CatchSuccess` | `catch_success.mp3` | ElevenLabs SFX generated | ~1s | **Ready to upload** |
| `CatchFail` | `catch_fail.mp3` | ElevenLabs SFX generated | ~2s (trim to 0.4s before upload) | **Ready to upload** |
| `PerfectFlash` | `perfect_flash.mp3` | ElevenLabs SFX generated | ~2s (trim to 0.3s before upload) | **Ready to upload** |
| `HarborUpgrade` | `harbor_upgrade.mp3` | ElevenLabs SFX generated | ~1.5s | **Ready to upload** |
| `CoinClink` | `coin_clink.mp3` | ElevenLabs SFX generated | ~1s | **Ready to upload** |
| `RainLoop` | `rain_loop.mp3` | ElevenLabs SFX generated 2026-05-21 | 22s loop | **Replaced — 2026-05-21** (rbxassetid://139877858000726) |
| `ThunderRumble` | `thunder_rumble.mp3` | ElevenLabs SFX generated 2026-05-21 | ~5s | **Replaced — 2026-05-21** (rbxassetid://82477411818423) |
| `WindStorm` | `wind_storm.mp3` | ElevenLabs SFX generated 2026-05-21 | 22s loop | **Replaced — 2026-05-21** (rbxassetid://74233360850100) |
| `FogAmbient` | `fog_ambient.mp3` | ElevenLabs SFX generated 2026-05-21 | 22s loop | **Replaced — 2026-05-21** (rbxassetid://95321828167943) |

## Licensing

| Slot | License | Action required |
|------|---------|----------------|
| `AmbientOcean` | CC0 (public domain) — Freesound #852826 by kkenny101 | None |
| `MusicHarborTheme` | **CC BY 4.0** — Freesound #518917 by BloodPixelHero | Credit in Settings/Credits |
| All 7 SFX | ElevenLabs generated 2026-05-21 | Re-verify commercial terms before launch |
| `RainLoop` / `ThunderRumble` / `WindStorm` / `FogAmbient` | ElevenLabs generated 2026-05-21 | Re-verify commercial terms before launch |

CC BY 4.0 credit line for Settings/Credits screen:
> "The calm theme" by BloodPixelHero (freesound.org/s/518917) — CC BY 4.0

## Sounds needing trim before upload

| Slot | File | Generated length | Target length | Action |
|------|------|-----------------|---------------|--------|
| `CatchFail` | `catch_fail.mp3` | ~2s | 0.2–0.5s | Trim tail in Audacity/editor |
| `PerfectFlash` | `perfect_flash.mp3` | ~2s | 0.2–0.4s | Trim tail in Audacity/editor |

All others are within spec or close enough to ship untrimmed.

## Upload workflow

1. Open [Roblox Creator Dashboard → Audio](https://create.roblox.com/dashboard/creations?activeTab=Audio)
2. Upload each `.mp3` from `assets/audio/sources/` as `TOT_<Key>_v1`
   (e.g. `TOT_AmbientOcean_v1`, `TOT_MusicHarborTheme_v1`, …)
3. Copy the numeric asset ID for each
4. Paste into `src/Client/AssetIds.lua` in the matching slot (add `rbxassetid://` prefix)
5. Studio playtest: cast → bite → catch → perfect ding → harbor upgrade → coin clink
   Confirm both loops (ocean + music) audible at idle and duck together on any SFX
6. Update the Status column above from "Ready to upload" to **"Replaced — YYYY-MM-DD"**

## AmbientOcean loop note

The generated ambient ocean is ~22s (ElevenLabs max). The SOUND_SPEC target was 30–90s.
22s is workable: Roblox loops seamlessly if you crossfade the end into the start before upload.
Use Audacity: select the last 0.5s, Effect → Crossfade Clips with the first 0.5s, export.
If the seam is audible, search Freesound for "ocean waves calm" (many CC0 results available)
as a longer alternative.
