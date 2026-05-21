# Roblox upload — cozy art pass

The 8 existing audio IDs in `src/Client/AssetIds.lua` are Roblox library
placeholders, kept as fallbacks so Studio playtests still have sound
while you produce the cozy replacements. `MusicHarborTheme` is wired in
code but empty until the first upload (silent no-op in `SoundController`
until an ID is pasted in).

Per-slot sourcing guidance lives in [`SOUND_SPEC.md`](SOUND_SPEC.md)
(reference vibes, CC0 Freesound search strings, ElevenLabs / Stable
Audio prompts, anti-patterns, mix targets). Per-slot filename / ID
tracking lives in [`TRACKING.md`](TRACKING.md).

## Workflow (per slot)

1. Open the slot section in `SOUND_SPEC.md` (Slot 1 = `AmbientOcean`,
   Slot 2 = `MusicHarborTheme`, etc.).
2. Source CC0 audio or AI-generate per the prompts.
3. Edit per the slot's mix targets and the global edit checklist
   (HPF, normalize, fades, loop seam).
4. Save final WAV to `assets/audio/sources/<key>.wav`. Filenames are
   locked in `TRACKING.md` — do not improvise (`MusicHarborTheme.wav`,
   `ambient_ocean.wav`, `cast_splash.wav`, etc.).
5. Upload to Roblox Creator Dashboard → Audio as `TOT_<Key>_v1`
   (e.g. `TOT_MusicHarborTheme_v1`). Tag for commercial use.
6. Copy the numeric asset ID. Paste into `src/Client/AssetIds.lua`
   *only*. Do not touch `SoundController.lua` or `GameConfig.lua` —
   they are already wired.
7. Rojo sync, then Studio playtest the checklist in
   [`SOUND_SPEC.md` — Edit checklist](SOUND_SPEC.md#edit-checklist--before-roblox-upload).
8. Update the slot's row in `TRACKING.md` to `Replaced — YYYY-MM-DD`.

## Studio QA via MCP

For a quick "is it loaded and playable" smoke test, the
`execute_luau` MCP tool can preload + play any `AssetIds.Sounds`
entry against the connected Studio place (same path used for the
Phase 1 QA logged in `QA_RESULTS.md`).

## License reminder

CC0 / Public Domain is safest. CC-BY needs a credits-screen
attribution — track those in `TRACKING.md`. AI platforms (ElevenLabs,
Stable Audio): re-check commercial terms on the date of generation,
they shift. Roblox library `rbxassetid` placeholders **must** be
replaced before commercial ship — they have no documented commercial
clearance.
