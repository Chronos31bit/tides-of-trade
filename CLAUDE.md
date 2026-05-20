---
## Git workflow (mandatory)

Every task must follow this exact sequence. No exceptions.
Always work from C:\Users\derin\purna — never from worktrees or any other directory.

1. Start on main and pull latest:
   cd C:\Users\derin\purna
   git checkout main && git pull origin main

2. Create a feature branch named after the task:
   git checkout -b feat/<short-task-name>
   (examples: feat/fishing-core-loop, feat/bait-shop-npc, feat/market-ui-filters)

3. Do the work. Commit frequently:
   git add -A && git commit -m "feat: <what was done>"

4. When complete, merge to main and push:
   git checkout main
   git merge feat/<short-task-name> --no-ff -m "merge: <task name>"
   git push origin main

5. Delete the feature branch:
   git branch -d feat/<short-task-name>

Never leave work uncommitted. Never leave main behind origin. Always push at the end of every task. Never use worktrees.
---

# CLAUDE.md — Tides of Trade

This file is the project's persistent context for any Claude (Code, Chat, or otherwise) working on the repo. Read it before starting any task. The conventions and constraints here override conflicting instincts from training data.

## What this project is

Tides of Trade is a cozy Roblox harbor-trading game. Core loop: fish from a procedurally generated coastline, restore an inherited rundown harbor, trade rare catches with other players via a cross-server global market. Mobile-first controls. Target audience is broader than typical Roblox (all ages, leans toward the 18–34 cohort that Roblox is actively trying to grow).

This is positioned in the **cozy + social + persistent** opportunity gap, against Grow a Garden and Bee Swarm Simulator. Not against Steal a Brainrot, not against RIVALS. The genre choice constrains every design decision below.

## Design pillars

These are non-negotiable. If a task seems to violate one, finish the task as specified and add a note flagging the conflict — don't silently rewrite to "fix" it.1

1. **Low-pressure sessions.** A typical session is 5–15 minutes. The game must be satisfying to dip into for 5 minutes and satisfying to play for 2 hours. No mechanics that punish short sessions (e.g. lost progress on disconnect, forced multi-step quests that can't be paused).

2. **Sell identity, not progress.** Monetization is cosmetic, decorative, or quality-of-life. Never speed-ups on core gameplay loops. Never coins for sale. Never "best in slot" rod/bait behind a paywall. A free player and a paying player playing side-by-side should both feel like they're winning their version of the game.

3. **Visible transformation.** When the player spends coins on a harbor upgrade, the change must be obvious from 30 studs away. Cozy players are driven by *seeing their space improve*. Subtle upgrades fail this game.

4. **Drip-feed mechanics.** New systems unlock weekly across the first month. Tutorial teaches the 6 core beats, nothing more. Don't surface deep mechanics (crews, seasonal pass, market arbitrage, building variety) until the design schedule says so.

5. **World stays alive.** Tides cycle, weather changes, NPCs move regardless of UI state. Never auto-pause the world for dialogue, modals, or transitions. Players should feel the world breathing around them.

6. **No combat, no time pressure, no failure states with progress loss.** A failed cast costs nothing. An escaped fish costs nothing meaningful. There are no enemies, no PvP, no permadeath, no rage moments.
   
7. **Mobile-first, always.** Every UI element is built for a 380px portrait phone first, then scaled up. Every button is 44px minimum hit target. Every interaction works thumb-only. PC and Xbox are nice-to-haves, not the primary target.

## Architecture conventions

### Tech stack
- **Knit** (Sleitnick) for service/controller framework. All server code is in Services, all client code is in Controllers. No exceptions.
- **ProfileService** (loleris, vendored at `src/Shared/Vendor/ProfileService.lua`) for player data persistence.
- **Trove** (Sleitnick, vendored under `Packages/_Index/sleitnick_trove@*/`) for connection/instance cleanup. Every Controller and Service that creates connections, tweens, or instances should hold a Trove and add to it.
- **Rojo** for filesystem ↔ Studio sync. The Rojo project file is `default.project.json`. Confirm folder mappings before adding new top-level folders.

### Architectural rules
- **Server-authoritative for all state.** The server is the source of truth for inventory, coins, buildings, market listings, quest progress, tutorial state, everything. The client is purely presentational.
- **Client can only request, never decide.** Client sends "I'd like to release the cast meter now" via RemoteEvent. Server validates and computes the result. Client never tells the server what fish it caught, what the price was, or what tier its building is.
- **All gameplay-affecting state lives in `GameConfig.lua`.** No magic numbers in service or controller files. If a task introduces tunable values (timings, multipliers, costs, thresholds), they go in `GameConfig` under a namespaced sub-table.
- **All motion via TweenService.** No `RunService.Heartbeat` manual lerps for UI motion. Heartbeat is fine for per-frame gameplay updates (cast meter oscillation, NPC pathing) that need sub-frame precision.
- **Cleanup is explicit.** Tweens get destroyed after completion. Connections get disconnected. Instances get destroyed. Don't rely on garbage collection.

### Communication patterns
- **Knit RemoteSignals** for server → client broadcasts (e.g. `HarborVisualUpdate`, `CastResolved`).
- **Knit RemoteEvents** for client → server requests.
- **BindableEvents/Signals (Sleitnick Signal)** for in-process server-to-server or client-to-client communication between services/controllers.
- **MessagingService** for cross-server broadcasts (market updates, crew chat, daily demand spikes).
- **DataStores** wrapped by services. Never call `DataStoreService` directly from gameplay code — always through `PlayerDataService`, `MarketService`, etc.

### Accessibility (not optional)
- **Respect `GuiService.ReducedMotionEnabled`.** Read on init and on its changed signal. When true: skip camera shake, skip particle bursts, replace slide-ins with fade-ins, halve animation durations. Never disable gameplay — only decoration.
- **44px minimum hit target** on all interactive elements at the base mobile scale.
- **No font below 12px** at effective rendered scale.
- **Text-only NPCs.** No TTS, no audio dialogue. Cozy players read.
- **No flashing/strobing effects.** No effect should change opacity or color more than 3 times per second.

## Things that are NOT this game

When evaluating any task, push back if it asks for:

- **Combat or PvP.** No fighting fish, no fighting players, no defensive structures. Trading creates social tension; combat does not.
- **Time-gated progression that punishes absence.** Crops that die if you don't log in, buildings that decay, energy systems that recover slowly. Players should *want* to come back, not *need* to.
- **Loot boxes, gacha, or randomized monetization.** Every purchase is a known-quantity transaction.
- **Voice acting or audio dialogue.** Mira and all NPCs are text-only.
- **Skip buttons on the tutorial.** Cozy players don't skip tutorials; players who would skip aren't the audience.
- **Auto-pause during dialogue/UI.** The world keeps moving.
- **Camera shake for non-impact moments.** Camera shake is for the cast splash and rare zone-loss events on heavy fish. Not for upgrades, not for notifications, not for "feel."
- **Speed-up purchases.** Don't sell timer skips on building construction, tide cycles, or anything else.
- **Pay-to-progress.** Don't sell coins. Don't sell guaranteed catches. Don't sell better rods that catch better fish. Cosmetic versions of the best gear are fine.

## How to handle conflicts

When a task prompt contradicts the existing code:

1. **Read the actual code first.** Don't assume the prompt is right.
2. **Stop and flag specific contradictions.** Don't silently adapt the prompt to fit the code, and don't silently extend the code to fit the prompt.
3. **Propose concrete options** with a clear default if the user doesn't reply.
4. **Wait for confirmation** before changing schemas, RemoteEvent contracts, or core service logic. Additive changes (new Signals, new methods, new fields with safe defaults) can proceed with a note.

When a task prompt contradicts these design pillars:

1. **Complete the task as specified** unless it would cause immediate harm (security, data loss, anti-exploit holes).
2. **Add a clear note at the end** flagging the design conflict and the reasoning.
3. **Don't editorialize during implementation.** One note at the end, not eight comments scattered through the code.

## Repo navigation

Key files for orientation:
- `README.md` — setup, Rojo, deployment
- `default.project.json` — Rojo folder mappings
- `wally.toml` — package dependencies
- `src/Shared/Config/GameConfig.lua` — all tunable values
- `src/Shared/Config/FishCatalog.json` — fish data (schema in `_doc` block at top)
- `src/Shared/Config/BuildingCatalog.lua` — 6 buildings × 3 tiers
- `src/Shared/Types.lua` — shared type definitions
- `src/Server/Services/PlayerDataService.lua` — profile schema and persistence
- `src/Server/Services/FishingService.lua` — server-authoritative fishing logic
- `src/Server/Services/HarborService.lua` — building placement and upgrades
- `src/Server/Services/MarketService.lua` — cross-server market
- `src/Server/Services/QuestService.lua` — daily quests and login streak

## Schema versioning

The DataStore version is locked at `TidesProfile_v1` until launch. ProfileService's reconcile pattern handles additive schema changes (new top-level keys with default values) without a version bump. **Only bump the version if the change is destructive** (removed fields, renamed IDs, changed field types). There is no auto-migration — a version bump wipes all data. This is intentional.

Stable string IDs across the codebase (`fish.id`, `building.kind`, cosmetic IDs, quest IDs) are **forever once shipped**. Never rename them. Add new IDs alongside old ones; deprecate by marking, not by removing.

## When in doubt

- Cozy over chaotic.
- Visible over numeric.
- Server over client.
- Configurable over hardcoded.
- Additive over destructive.
- Ask over assume.
