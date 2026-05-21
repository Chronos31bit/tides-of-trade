# Tides of Trade — cozy audio source kit

Comprehensive sourcing spec for the 9 audio slots wired in
`src/Client/AssetIds.lua`. Use this doc to source CC0 audio (Freesound /
Kenney) or AI-generate replacements (ElevenLabs Sound Effects / Stable
Audio), edit to spec, upload to Creator Dashboard, and paste IDs back into
`AssetIds.lua`.

Design constraints from `CLAUDE.md`:

- Cozy, low-pressure, warm. Game session is 5–15 min, world stays alive.
- No combat, no failure stings, no time pressure.
- Mobile-first — mix for phone speakers, not studio monitors.
- No voice / TTS / breath samples anywhere.
- Respect Reduced Motion (audio still fires; visuals attenuate).
- Server-authoritative — audio is purely presentational.

## Global cozy palette

Every slot must conform to the same sonic palette:

- **Instruments** — nylon classical guitar (fingerpicked, never strummed
  loud), marimba, glockenspiel / music box, soft upright piano (felt
  hammers), warm low pad (sine + slow tremolo), wooden percussion (tongue
  drum, kalimba, soft brush snare).
- **Tempo (music)** — 60–80 BPM. Music is *background*, never foreground.
- **Reverb** — short tails only (≤0.6 s). No cathedral / cinematic verb.
- **EQ tilt** — warm. HPF below 60–80 Hz on everything. Soft shelf below
  6 kHz so phone speakers don't reproduce a brittle high end.
- **Dynamics** — gentle. Peak normalize one-shots to ~-3 dBFS; loops to
  ~-9 dBFS so SFX can sit above the bed when the ambient duck fires
  (see `GameConfig.Audio.DuckDb = -6`).
- **Stereo** — mono for one-shots that play positional (cast splash,
  perfect flash); stereo for the two loops (ambient ocean, music).

## Global anti-patterns — never use

Reject any sample/prompt that matches these, regardless of how cozy the
filename sounds:

- Slot-machine triplets, casino bell flourishes, "level-up" 4-note
  ascending stings ("Mario 1-up").
- Retro 8-bit / chiptune blips. We are not a retro pixel game.
- Big-budget cinematic stings — orchestral hits, taiko slams, riser FX,
  movie-trailer impacts.
- Voice, breath, mouth sounds, whispered "yeah/nice/woo" samples,
  vocal-pad "aah/ooh" beds. CLAUDE.md is explicit: no audio dialogue.
- Aggressive transients — gunshot-style attacks, harsh metallic clicks,
  laser zaps, glass shatter.
- Distorted bass, dubstep wobbles, EDM drops, sidechained pumping.
- Crowd noise, birds-of-prey screeches, dramatic seagulls, thunder. The
  harbor is *calm*.
- More than 3 opacity / color / volume changes per second
  (CLAUDE.md accessibility rule for flashing/strobing).
- Loud sudden onsets without a fade-in on loops — clicks at loop seams
  are the #1 reason cozy ambient feels "off".

## Slot 1 — `AmbientOcean` (loop)

- **Trigger** — `SoundController:KnitStart`, always-on under everything.
- **Code volume** — `GameConfig.Audio.AmbientBaseVolume` (0.28).
- **Length** — 30–90 s seamless loop.
- **Reference vibes** — Spiritfarer dock ambient (the quiet bits, not
  the storm sections); Stardew Valley Beach overworld minus the gulls;
  Coffee Talk shop ambience with the chatter stripped out.
- **CC0 Freesound search strings (filter `license:cc0`)**:
  - `ocean waves calm loop seamless`
  - `gentle shore lapping no birds`
  - `harbor water lapping wood dock`
  - `small waves close pebble beach`
  - `calm sea ambience loopable`
- **ElevenLabs Sound Effects prompt**:
  - `Gentle calm ocean waves lapping a wooden harbor at low tide. Soft
    rolling water, distant low ocean rumble, no birds, no wind, no
    voices. Warm and cozy. Seamless 45-second loop.`
- **Stable Audio prompt**:
  - `Calm ocean ambience, soft waves on a wooden dock, low tide, warm
    low-end, no birds, no thunder, no voices, seamless field-recording
    style, 45 seconds, mobile game background.`
- **Avoid (slot-specific)** — seagulls, fog horns, boat engines, wind
  howling, surf crashes, distant music bleed.
- **Mix targets** — stereo, 44.1 kHz, peak ~-9 dBFS, HPF at 80 Hz, 200 ms
  crossfade at the loop seam, no clicks.

## Slot 2 — `MusicHarborTheme` (loop, NEW)

- **Trigger** — `SoundController:KnitStart`, layers under `AmbientOcean`.
- **Code volume** — `GameConfig.Audio.MusicBaseVolume` (0.16). Music
  sits *below* the ocean so the ocean stays the dominant cue; music is
  the warm glow underneath.
- **Length** — 60–120 s seamless loop.
- **Reference vibes** — Stardew Valley *Spring (It's a Big World
  Outside)* slowed to ~70 BPM; Spiritfarer *Everdoor* / hub piano
  pieces; Animal Crossing K.K. calm requests (K.K. Lullaby, Hypno
  K.K.); Coffee Talk lobby loop; A Short Hike trailhead theme.
- **CC0 Freesound search strings (filter `license:cc0`)**:
  - `acoustic guitar fingerpicked loop cozy`
  - `marimba calm slow loop ambient`
  - `lo-fi piano felt warm loop`
  - `kalimba slow melody loop`
  - `cozy game music loop royalty free` (also try Kenney
    [`kenney.nl/assets/music-jingles`](https://kenney.nl/assets/music-jingles)
    and Pixabay Music CC0 filter)
- **ElevenLabs Sound Effects prompt** (Eleven's music output is short,
  prefer their Music product if available):
  - `Cozy harbor town daytime theme, slow fingerpicked nylon guitar
    with soft marimba accents and a warm low pad, 72 BPM, no drums, no
    vocals, no synth leads, gentle and unobtrusive, 90-second seamless
    loop.`
- **Stable Audio prompt**:
  - `Cozy fishing village background music, fingerpicked nylon classical
    guitar, soft marimba, warm low pad, no drums, no vocals, no synths,
    70 BPM in C major, gentle and looping, Stardew Valley meets
    Spiritfarer, mobile game background, 90 seconds, seamless.`
- **Avoid (slot-specific)** — vocals (humming, "aah/ooh" pads, scat),
  drum kits, sub-bass drops, key changes more dramatic than relative
  minor, anything that demands attention. If a human would lean in to
  listen, it's wrong.
- **Mix targets** — stereo, 44.1 kHz, peak ~-9 dBFS, integrated loudness
  around -20 LUFS so the ducking math (`-6 dB`) stays comfortable, HPF
  at 60 Hz, low-shelf -2 dB at 200 Hz to leave room for ocean, 300 ms
  crossfade at the loop seam, **zero click at the loop point** —
  test by playing the loop 3× back-to-back.

## Slot 3 — `CastSplash` (one-shot, positional)

- **Trigger** — `FishingController` when the cast lands, positional at
  `castPoint`.
- **Code volume** — 0.6 (call site).
- **Length** — 0.3–0.8 s.
- **Reference vibes** — Stardew Valley cast plop; A Short Hike water
  step into a pond; a small pebble dropped into a koi pond.
- **CC0 Freesound search strings**:
  - `water plop single small splash`
  - `bobber drop water close`
  - `pebble small splash pond`
  - `cartoon water plop soft`
- **ElevenLabs prompt**:
  - `Soft cartoon water plop, single splash, cozy mobile fishing game,
    small bobber landing in a calm harbor, no long reverb tail, warm
    not harsh, half-second total.`
- **Stable Audio prompt**:
  - `Single soft water plop, small splash, cozy game cast sound, close
    mic, warm low-end, short tail, 0.5 seconds, mono.`
- **Avoid (slot-specific)** — large splashes ("cannonball"), comedy
  "boing" cartoon water, slosh-bucket sounds, anything with a vocal
  reaction ("whoa", "oof").
- **Mix targets** — mono, 44.1 kHz, peak ~-3 dBFS, HPF at 100 Hz, 10 ms
  fade-in, 50 ms fade-out, no DC offset.

## Slot 4 — `FishBite` (one-shot)

- **Trigger** — `FishingController._onBite` (reel phase start).
- **Code volume** — `GameConfig.FishBite.SoundVolume` (0.7).
- **Length** — under 1.5 s.
- **Reference vibes** — Stardew Valley nibble tug; Spiritfarer rope tension
  pull; the gentle "click" of a bobber being pulled below the surface.
- **CC0 Freesound search strings**:
  - `fishing line tug short`
  - `rope tension small pull wet`
  - `bobber dip small ripple`
  - `wood creak short single small`
- **ElevenLabs prompt**:
  - `Gentle fishing line tug with a small water ripple, cozy game, soft
    pull on a wooden rod, not aggressive, no jump-scare, under one
    second, warm.`
- **Stable Audio prompt**:
  - `Soft fishing line tug, small water ripple, light wooden rod creak,
    cozy game feedback, 0.8 seconds, mono, warm.`
- **Avoid (slot-specific)** — alarm-style "alert" beeps (no UI ding
  here — `PerfectFlash` handles UI dings), heavy splashes, monster
  rumble, "boss appears" stings.
- **Mix targets** — mono, 44.1 kHz, peak ~-3 dBFS, HPF at 100 Hz, 10 ms
  fade-in, 60 ms fade-out.

## Slot 5 — `CatchSuccess` (one-shot)

- **Trigger** — `FishingController` on successful catch.
- **Code volume** — 0.6.
- **Length** — 0.6–1.0 s.
- **Reference vibes** — Animal Crossing item-acquired bell (calmer
  version, no fanfare); Stardew Valley fish-caught chime; a music-box
  closing.
- **CC0 Freesound search strings**:
  - `wooden coin clink soft bell`
  - `glockenspiel single note warm cozy`
  - `music box chime two notes ascending`
  - `kalimba major chord short`
- **ElevenLabs prompt**:
  - `Warm wooden coin clink followed by a soft glockenspiel two-note
    rise, cozy harbor game success sound, not a slot machine, not a
    fanfare, gentle and satisfying, under one second.`
- **Stable Audio prompt**:
  - `Cozy catch success sound, warm wooden coin clink and soft
    glockenspiel two-note rise in C major, no fanfare, no orchestra,
    mobile game positive feedback, 0.9 seconds, mono.`
- **Avoid (slot-specific)** — slot-machine triplets, "ding ding ding"
  cascades, brass fanfares, choir hits, level-up four-note ascensions,
  reward-chest "shimmer" pads.
- **Mix targets** — mono, 44.1 kHz, peak ~-3 dBFS, HPF at 120 Hz, 5 ms
  fade-in, 80 ms fade-out, brief tail (no long reverb).

## Slot 6 — `CatchFail` (one-shot)

- **Trigger** — `FishingController` on failed catch / fish escapes.
- **Code volume** — 0.4 (intentionally quiet — failure has no real
  cost, per CLAUDE.md pillar 6).
- **Length** — 0.2–0.5 s.
- **Reference vibes** — Spiritfarer rope going slack; the soft "tssh"
  of a tea bag dropped in water; a held breath released.
- **CC0 Freesound search strings**:
  - `rope slack short soft`
  - `gentle whoosh short single`
  - `wood tap soft single muted`
  - `cloth fold short soft`
- **ElevenLabs prompt**:
  - `Soft rope going slack, gentle whoosh, cozy game miss feedback,
    not punishing, not negative, just a neutral "fish got away"
    half-second, no harsh transient.`
- **Stable Audio prompt**:
  - `Soft slack rope and gentle air whoosh, neutral cozy miss sound,
    no negative musical interval, 0.3 seconds, mono.`
- **Avoid (slot-specific)** — descending sad-trombone, minor-key
  "wah-wah-wah", buzzer/error tones, glass break, anything a player
  could read as scolding. Failure costs nothing — sell that in audio.
- **Mix targets** — mono, 44.1 kHz, peak ~-6 dBFS (quieter than other
  one-shots), HPF at 150 Hz, 10 ms fade-in, 40 ms fade-out.

## Slot 7 — `PerfectFlash` (one-shot, UI)

- **Trigger** — `CastMeterController` when the marker enters the
  perfect zone.
- **Code volume** — 0.35.
- **Length** — 200–400 ms.
- **Reference vibes** — Animal Crossing menu confirm; the high note of
  a music box; a single small wind-chime ping.
- **CC0 Freesound search strings**:
  - `ui notification ding soft cozy`
  - `glockenspiel single note high`
  - `wind chime single ping`
  - `music box single note`
- **ElevenLabs prompt**:
  - `Soft UI confirm ding, single warm glockenspiel note, cozy mobile
    game perfect-zone feedback, 300 ms, no reverb tail, warm metallic
    not bright.`
- **Stable Audio prompt**:
  - `Single warm glockenspiel note, cozy game UI ping, no reverb tail,
    250 ms, mono.`
- **Avoid (slot-specific)** — laser zap, "ping" radar tones, bright
  synth blips, video-game coin (Mario), any tone that fires on every
  frame the marker is in the zone — this slot fires once on entry.
- **Mix targets** — mono, 44.1 kHz, peak ~-3 dBFS, HPF at 200 Hz, 5 ms
  fade-in, 100 ms fade-out, short tail.

## Slot 8 — `HarborUpgrade` (one-shot)

- **Trigger** — `HarborVisualController` on building tier-up.
- **Code volume** — 0.5.
- **Length** — 1.0–1.8 s.
- **Reference vibes** — Stardew Valley building-complete chime; the
  warm clunk of a wooden door closing properly; a hammer tap followed
  by a music-box flourish.
- **CC0 Freesound search strings**:
  - `wood hammer tap single soft`
  - `wooden building creak settle`
  - `music box short flourish three notes`
  - `kalimba arpeggio short major`
- **ElevenLabs prompt**:
  - `Cozy harbor building upgrade: light wooden hammer tap followed by
    a soft three-note marimba rise, satisfying not fireworks, no
    fanfare, no orchestra, warm and tactile, about 1.4 seconds.`
- **Stable Audio prompt**:
  - `Light wooden hammer tap and gentle marimba three-note rise in C
    major, cozy harbor upgrade sound, no orchestra, no choir, 1.4
    seconds, mono, warm.`
- **Avoid (slot-specific)** — orchestral hit, "level up" fanfare,
  fireworks bursts, choir swells, big-budget "achievement unlocked"
  stings.
- **Mix targets** — mono, 44.1 kHz, peak ~-3 dBFS, HPF at 80 Hz, 5 ms
  fade-in, 200 ms fade-out, gentle natural tail.

## Slot 9 — `CoinClink` (one-shot)

- **Trigger** — `HarborEditController` on place / upgrade confirm.
- **Code volume** — 0.45.
- **Length** — 0.15–0.35 s.
- **Reference vibes** — Stardew coin pickup; the soft chink of a wooden
  bead on a tabletop; a single coin set down on a counter (not
  dropped, set).
- **CC0 Freesound search strings**:
  - `coin drop wood single light`
  - `single coin set table soft`
  - `small wooden bead tap`
  - `pocket change single chink`
- **ElevenLabs prompt**:
  - `Light single coin set on a wooden counter, soft cozy harbor game,
    no jingle, no cascade, 200 ms, warm wooden tone, mono.`
- **Stable Audio prompt**:
  - `Single light coin on wooden surface, cozy game confirm sound,
    warm low-mid, 0.2 seconds, mono.`
- **Avoid (slot-specific)** — coin cascades, jingling pouches, slot
  machine payouts, metallic anvil clinks.
- **Mix targets** — mono, 44.1 kHz, peak ~-3 dBFS, HPF at 150 Hz, 0 ms
  fade-in (let the transient breathe), 40 ms fade-out.

## Edit checklist — before Roblox upload

For every slot, run this list. Skipping the loop-seam test is the #1
reason a cozy bed feels "off" once it's in-engine.

- [ ] Export 44.1 kHz, 16-bit WAV. Mono unless stereo is called for
      above.
- [ ] HPF per slot (60–200 Hz cutoffs above).
- [ ] Peak normalize to the target dBFS above (loops -9, fail -6,
      everything else -3).
- [ ] Fade-in / fade-out per slot (avoid clicks).
- [ ] One-shots: clip silence to ≤ 50 ms head/tail (Roblox round-trip
      latency is real; trim it out at source).
- [ ] Loops (`AmbientOcean`, `MusicHarborTheme`): crossfade 200–300 ms
      at the seam. Play the loop 3× back-to-back. If you can hear the
      seam, it's not done.
- [ ] Spot-listen on a phone speaker, not just headphones. Cozy
      players play on mobile.
- [ ] Confirm no breath / vocal artifacts (especially in AI-generated
      music — ElevenLabs and Stable Audio love to sneak in "aah" pads).

## Upload workflow

1. Drop the final WAV in `assets/audio/sources/<key>.wav` using the
   exact key name from `src/Client/AssetIds.lua` (e.g.
   `MusicHarborTheme.wav`).
2. Upload to Roblox Creator Dashboard → Audio as `TOT_<Key>_v1`
   (e.g. `TOT_MusicHarborTheme_v1`).
3. Copy the numeric asset ID. Paste into the matching entry in
   `src/Client/AssetIds.lua` *only*. Do not touch other files.
4. Playtest in Studio: cast → bite → catch → perfect ding → harbor
   upgrade → coin clink → confirm both loops audible and ducking
   together when a one-shot fires.
5. Update `assets/audio/TRACKING.md` row from "Placeholder" to
   "Replaced — <date>".

## Licensing

CC0 / Public Domain (Freesound, Kenney, Pixabay CC0 filter) is the
safest. CC-BY requires attribution in the game (Settings / Credits
screen) — track those in `TRACKING.md`. AI-generated audio: confirm
the platform's commercial-use terms on the date of generation
(ElevenLabs and Stable Audio both currently permit commercial use on
paid tiers but the terms shift — re-check before launch). Roblox
library `rbxassetid` placeholders currently in `AssetIds.lua` must be
replaced before commercial ship — they have no documented commercial
clearance.
