# Boats & Deep Water — Design Brief

> **Status:** Discovery / proposal (no code)
> **Roadmap:** `boat` — "Boats & Deep Water" (lane 5, P2, backlog)
> **Date:** 2026-05-29
> **Decision asked:** drivable boat (A) vs autopilot "sail to" (B). **Recommendation: B.**

---

## TL;DR

Build **Option B — an autopilot "Set Sail" menu**, not a drivable boat.

The cast already resolves its biome from `character.CurrentBiome`, which the server
stamps from the player's `HumanoidRootPart` position once a second
(`WorldService:_resolveBiomes`). A "boat" in this game does not need to be a vehicle —
it needs to be **whatever legally relocates the player into a deep band**. The cheapest,
most thumb-friendly, most cozy, most server-authoritative way to do that is a menu of
unlocked destinations that fades the player onto an anchored fishing pad. The drivable
boat costs far more, fights three design pillars, and buys a "journey" fantasy that this
genre is better off selling as a **cosmetic** (`boatSkin`, already planned) than as a
mechanic.

---

## Current state (what the code actually does)

| Fact | Source |
|---|---|
| Biomes are **AABB sensor bands** in open water, increasing in `+Z` from the plot grid. Reef ≈ Z 1020, DeepWater ≈ Z 1160, Trench ≈ Z 1400. | `WorldService:KnitStart` |
| Biome is resolved **server-side at 1 Hz** from the player's HRP position; default fallback is `Shoreline`. | `WorldService:_resolveBiomes` |
| The cast reads `character.CurrentBiome.Value` and rolls only fish whose `biomes` list contains it. | `FishingService:_getContext`, `fishMatches` |
| **The "requires boat/dock tier 2+" gate does not exist in code.** It is a comment in `GameConfig.Biomes`. Deep fish are reachable today by a long swim, or the Studio-only `BiomeTestService` teleport hub. | `GameConfig.lua:40`, `FishingService` (no tier check) |
| `BiomeTestService` already teleports the HRP to each biome's centre (`GameConfig.BiomeTest.TeleportTargets`) and the resolver picks up the new biome within a second. **This is a working proof-of-concept for Option B.** | `BiomeTestService`, `GameConfig.BiomeTest` |
| The Dock building already has tiers 1–3 and its description literally reads *"Lets you cast in deeper water. Higher tiers reach Trench biome."* Tier 2 is the tutorial's first repair (40 coins); tier 3 is 9000 coins. | `BuildingCatalog.Dock`, `GameConfig.Buildings.Dock` |
| A `boatSkin` cosmetic line is already planned in the future CosmeticCatalog. | roadmap `cosmetics` task |
| ~22 of ~78 catalog entries list `DeepWater`; several are `Trench`-only. A meaningful content slice is gated behind traversal that doesn't exist yet. | `FishCatalog.json` biome counts |

**Implication:** the hard problem is *not* "how do we move a boat." It is "how do we let a
thumb-only player reach a far band, keep it server-authoritative, keep it low-pressure, and
make the dock upgrade finally mean something." Movement is a thin layer over an existing
server-resolved system.

---

## Constraints that bind this feature (from CLAUDE.md)

1. **Mobile-first, one thumb.** Twin-stick steering is a hard pass (brief). 44px targets, ≥12px font.
2. **Low-pressure 5-minute session.** No multi-minute sail before any fishing. Travel time is dead time.
3. **No failure states.** Boats cannot sink, capsize, or run out of fuel. No lost progress.
4. **World stays alive.** Tides cycle regardless of UI. Tide should affect where you can fish — but never auto-pause or hard-fail.
5. **Server-authoritative.** Client requests; server decides. Biome is computed server-side *specifically because the client position can be spoofed* (`WorldService` header comment).
6. **Sell identity, not progress.** Monetization is the boat's *look*, never faster/farther/better catches.

---

## Option A — Drivable boat

Player pilots a boat across the sea to the deep bands. Twin-stick is banned, so the two
viable input schemes are:

- **A1 — single virtual joystick** (left thumb steers + throttles, camera auto-follows).
- **A2 — auto-forward + tap-to-turn** (boat always moves; tap a side / heading to steer; Alto/Sky style).

### Thumb ergonomics — ⚠️ Mixed
- The left thumb already drives the default Roblox character. A boat reuses that thumb, which is *consistent*, but now also competes with watching a 380px screen and a follow-camera.
- A2's "always moving" means the player must actively **stop/anchor** to fish, and can drift out of a band mid-session — low-grade pressure that fights pillar 2.
- Driving and fishing are different modes (the fishing HUD already owns the bottom thumb zone: cast button at `CastButtonBottomPx` 118, reel bar at `ReelBarBottomPx` 200). You need an explicit **drive ↔ fish mode switch**. More taps, more state.

### Server-auth feasibility — ⚠️ Workable but fiddly
- Roblox hands **network ownership** of a vehicle assembly to the controlling client for responsiveness. That makes the boat's position *client-owned*, i.e. spoofable — directly at odds with "biome is server-resolved because the client can be spoofed."
- This is **survivable** *if* the catch is gated on dock tier **server-side at cast resolution** (so being in Trench without tier 3 still cannot catch Trench fish). But that gate is exactly the work Option B needs too — A doesn't get it for free, and A adds a spoofable movement surface on top.
- Physics boats at scale: many assemblies per server, collisions with Trench rock spires, seat/dismount flow, StreamingEnabled (deep bands are far from plots and must stream in), and anti-capsize work (no failure states → must constrain upright with `AlignOrientation`, no buoyancy mishaps).

### Dev cost — 🔴 High
Vehicle controller + mobile input scheme + follow camera + seat/dismount + anti-capsize +
terrain collision + network-ownership policy + drive/fish mode toggle + tide-driven
navigability (dynamic blockers the player physically bumps into). Each is a multi-day item.

### Cozy alignment — ⚠️ Mixed
A calm sail *can* be cozy (Wind Waker, Sail Forth). But auto-forward, "don't drift away,"
follow-camera dexterity, and mode-switching add exactly the friction pillars 1, 2, and 7
push against. Every 5-minute session now pays a travel tax.

---

## Option B — Autopilot "Set Sail" menu  ✅ recommended

Player approaches the Dock (a `ProximityPrompt`, mirroring the existing rod-shop / bait-shop
prompts), opens a **"Set Sail"** modal listing unlocked destinations (Pier · Reef · DeepWater ·
Trench · Home), taps one, and a short fade carries them onto that band's **anchored fishing
pad**. A cosmetic boat model sits at the pad. They fish, then "Sail home" returns them to
their plot dock.

### Thumb ergonomics — ✅ Best possible
One tap on a 44px button in a modal — infrastructure the codebase already has
(`UIUtil.makeModalShell`, `ModalShell_Template`). Zero steering, zero follow-camera, no
competition with the fishing thumb zone (the modal closes before fishing begins).

### Server-auth feasibility — ✅ Excellent, already proven
`SailTo(destination)` is a Knit **RemoteEvent**: client *requests*, server *validates*
(dock tier + that the destination is a real band) and sets the HRP `CFrame` to the pad.
Biome then resolves through the **existing** 1 Hz `WorldService` path — no new authority
surface. This is literally the `BiomeTestService.TeleportTargets` pattern promoted out of
its `IsStudio()` guard. The client cannot self-teleport, and even if a position were
spoofed, the cast stays dock-tier-gated server-side. Textbook "client requests, server decides."

### Dev cost — 🟢 Low–Medium
`BoatService` (server) + `SailController` / `SailUI` (client modal). Reuse modal chrome,
reuse the teleport pattern, add one static anchor pad + spawn point per band (the bands
already exist and are already generated). The boat is **set-dressing** — a static model at
the pad and a sprite in the fade — which is exactly where `boatSkin` cosmetics plug in.

### Cozy alignment — ✅ Strong
No dexterity, no drift, no travel tax. Tap Reef → ~1.5s fade → fishing. Fits "dip in for
5 minutes" precisely. The fade is `MotionUtil`-safe (slide/vignette normally, quick
cross-fade under ReducedMotion). No failure state is even possible: an unlocked destination
always succeeds; a locked one is greyed with a cozy reason line, never an error.

---

## Side-by-side

| Axis | A — Drivable | B — Sail-to menu |
|---|---|---|
| One-thumb input | ⚠️ joystick/tap + mode switch | ✅ single tap |
| Competes with fishing HUD | ⚠️ yes (needs mode toggle) | ✅ no (separate modal) |
| Server-authoritative | ⚠️ spoofable movement; needs same gate as B *plus* hardening | ✅ proven, no new authority surface |
| No-failure-state by default | ⚠️ must design out capsize/drift | ✅ free |
| Travel time per session | 🔴 real, every trip | 🟢 ~1.5s fade |
| Dev cost | 🔴 high | 🟢 low–medium |
| Tide integration | ⚠️ invisible walls / dynamic blockers | ✅ menu entry gating + flavor |
| Cosmetic monetization fit | ✅ skinnable hull (but expensive base) | ✅ skinnable pad/fade boat (cheap base) |
| Cozy pillar | ⚠️ mixed | ✅ strong |

---

## Recommendation & justification

**Ship Option B.** Defer the drivable boat as a *possible* far-future opt-in (see Endgame).

1. **The brief's own constraints select B.** "No 3-minute sail before any fishing" and
   "one thumb, no twin-stick" are nearly a spec for an autopilot menu. "Tide affects where
   boats can go" is one greyed menu row in B; in A it's invisible walls that frustrate.
2. **B is the smallest change to a system that already works.** Biome resolution, the
   teleport pattern, modal chrome, and dock tiers all exist. B wires them together; A adds a
   whole vehicle subsystem beside them.
3. **B is more server-authoritative, not less.** It introduces no client-owned position.
   A's physics boat reintroduces exactly the spoofable surface `WorldService` was written to avoid.
4. **The "boat" fantasy is better sold than driven.** For a cozy harbor-trader, the product
   is the *destination* (rare catches) and the *harbor transformation* — not the commute.
   Players still get to **own and customize** a boat (`boatSkin`), shown at the pad and in the
   fade, which honors pillar 2 ("sell identity") without a driving mechanic that taxes pillars 1, 2, 7.

If we later learn from telemetry that players *want* the journey, we can layer a free-roam
drivable boat on top of B as an opt-in toggle — without ever removing the instant-sail default.

---

## Gating model (grounded in existing config)

**Dock tier is the access key** — this matches the `GameConfig.Biomes` comment, the Dock
description, and the roadmap's "Dock-tier gates boat access." Proposed map (new, additive,
designer-tunable — e.g. `GameConfig.Boats.AccessByDockTier`):

| Destination | Dock tier required | Notes |
|---|---|---|
| Pier / Shoreline | 1 (starter) | status quo |
| Reef | 2 | currently ungated; folds into the sail menu |
| DeepWater | 2 | matches existing "tier 2+" comment |
| Trench | 3 | "end-game"; matches 9000-coin tier-3 dock |

The dock upgrade the tutorial already teaches (tier 2 repair) becomes the moment the sea
*opens up* — a clean, visible payoff for a building the player already restored.

### Tide (pillar: world stays alive, no failure states)
- Trench is already specced as *"mythics only at high tide"* (`GameConfig.Biomes`). Keep the
  Trench destination **always available** at tier 3, but let the mythic pool ride the existing
  `tide` context in `fishMatches`. At low tide, show a **cozy hint** ("Calm now — the big ones
  surface at high tide"), never a lock.
- Optional flavor: the deep pad / boat visibly rests lower at low tide (a tide line on the pad).
  Visible-world charm, not a gate.

---

## Security note (do this regardless of A/B)

The "requires boat/dock tier 2+" gate is **currently unenforced** — a player can swim to
DeepWater/Trench today and catch gated fish. Recommend adding a **server-side dock-tier check
at catch resolution** (in `FishingService`, alongside the existing per-fish `rodMinTier`
gate): if the resolved biome requires a dock tier the player hasn't reached, drop it to the
best biome they *have* unlocked (or reject the deep roll). This:
- makes the dock upgrade meaningful,
- closes the swim/spoof bypass for both options,
- is **additive** (no schema change, no `TidesProfile_v1` bump).

This is the one piece of hardening worth doing even before boats ship.

---

## Phased rollout

### MVP — ship the loop
- `GameConfig.Boats` sub-table: `AccessByDockTier`, fade durations, per-band pad CFrames/offsets. (No magic numbers in services.)
- **Server `BoatService`:** `SailTo(destination)` RemoteEvent → validate dock tier + real band → set HRP CFrame to the band's anchor pad → biome resolves via existing `WorldService`. `SailResolved` RemoteSignal for client fade timing. `SailHome` returns to `HarborService:GetPlotOrigin`.
- Promote the `BiomeTestService` teleport pattern out of `IsStudio()` into production **anchor pads** (one static part + spawn point per band centre; bands already generate today).
- Add the **server-side dock-tier catch gate** (security note above).
- **Client `SailController` / `SailUI`:** Dock `ProximityPrompt` → "Set Sail" modal listing unlocked destinations (locked rows greyed with a reason line) → tap → `MotionUtil` fade cover → land on pad. Static cosmetic boat model at the pad.
- **Drip-feed:** keep the menu hidden until the design schedule's week for it (pillar 4); it rides on the already-taught tier-2 dock repair but isn't surfaced in the tutorial.

### Polish
- **`boatSkin` cosmetics** (already planned): swap the pad/fade boat model; Robux, cosmetic-only (pillar 2).
- Fade feel: brief "sailing" vignette + ambient SFX swell; ReducedMotion → quick crossfade.
- Tide-aware hint lines in the menu; tide line on the deep pad.
- "Sail home" polish + a one-line Mira beat the first time the sea opens up.

### Endgame
- **Crew sailing:** a crew sails to a shared deep pad together (Guildhall already gates crews; MessagingService already exists). Social tension, no combat.
- **Optional free-roam drivable boat** as an *opt-in toggle* layered over B — built only if telemetry shows demand. The instant-sail default never goes away.
- **Migrating destinations:** a "shoal" pad that appears only at certain tides/weather — novelty with no new system.

---

## Open questions / flagged conflicts

1. **Reef is currently ungated and swim-reachable.** Proposal folds it into the tier-2 sail
   menu but does **not** add invisible walls (no failure states) — players can still swim there.
   Confirm Reef should require tier 2 in the menu, or stay a tier-1 freebie.
2. **"Boat" as mechanic vs fantasy.** B intentionally delivers the *ownership/cosmetic* boat,
   not the *driving* boat. If driving is wanted as a headline feature, that's a product call
   trading directly against the cozy/low-pressure pillars — flagging, not deciding.
3. **Lighthouse + deep bands.** The Lighthouse lure radius is plot-anchored, so it won't buff
   deep-band fishing. Fine for MVP (deep bands = raw-odds zones); a future deployable buoy
   could extend it. Flagged, not scoped.
4. **Drip-feed week.** Which week does the sail menu unlock? Needs a slot on the onboarding
   schedule (pillar 4).

---

## Appendix — likely code touch-points (for the eventual build, not this brief)

- `GameConfig.lua` — new `GameConfig.Boats` sub-table (access map, fade timings, pad CFrames).
- `WorldService` / new `BoatService` — anchor pads + `SailTo` / `SailHome` validation & teleport.
- `FishingService` — additive server-side dock-tier catch gate.
- `BiomeTestService` — source the teleport pattern from here (Studio → production).
- New client `SailController` + `SailUI` — modal reusing `UIUtil.makeModalShell`; Dock `ProximityPrompt`.
- `Types.lua` / `PlayerDataService` — additive cosmetic fields if `boatSkin` lands (e.g. `ownedBoatSkins`, `equippedBoatSkin`); **no `TidesProfile_v1` bump** (ProfileService reconcile).
- Future `CosmeticCatalog` — `boatSkin` entries.
