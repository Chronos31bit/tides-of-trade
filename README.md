# Tides of Trade

A cozy + social Roblox harbor-trading game. Fish, build up a harbor, and trade
rare catches with players across servers via a global market. Mobile-first.

## Stack

- **Knit** (Sleitnick) for service/controller framework
- **ProfileService** (loleris) for player data persistence (vendored)
- **Trove**, **Promise**, **Signal** (Sleitnick / evaera) — pulled by Wally
- **Rojo** for filesystem ↔ Studio sync

## Project layout

```
purna/
├── default.project.json     # Rojo project (single-file, no place file required)
├── wally.toml               # Knit/Trove/Promise/Signal versions
├── README.md
├── src/
│   ├── Shared/              -> ReplicatedStorage.Shared
│   │   ├── Config/
│   │   │   ├── FishCatalog.json     # 5 starter species, schema doc'd inline
│   │   │   ├── BuildingCatalog.lua  # 6 buildings × 3 tiers
│   │   │   └── GameConfig.lua       # all economy/world tuning
│   │   ├── Types.lua                # shared Profile / Item / Listing types
│   │   ├── Util/
│   │   │   ├── GridUtil.lua         # grid math (used by client + server)
│   │   │   ├── RateLimiter.lua      # sliding-window per-player throttle
│   │   │   ├── TimeUtil.lua         # UTC day math for daily systems
│   │   │   └── UidUtil.lua
│   │   └── Vendor/
│   │       ├── ProfileService.README.md   # how to install ProfileService
│   │       └── ProfileService.lua         # YOU drop this in (see §2)
│   ├── Server/              -> ServerScriptService.Server
│   │   ├── init.server.lua
│   │   └── Services/
│   │       ├── PlayerDataService.lua  # ProfileService wrapper, single source of truth
│   │       ├── FishingService.lua     # cast/reel, server-authoritative
│   │       ├── HarborService.lua      # plot allocation, building grid
│   │       ├── MarketService.lua      # cross-server DataStore market + MessagingService
│   │       ├── QuestService.lua       # 3 daily quests + login streak
│   │       ├── TideService.lua        # 20-min high/low cycle
│   │       ├── WeatherService.lua     # Markov weather + Lighting drive
│   │       └── SocialService.lua      # crews, emotes, harbor visits
│   └── Client/              -> StarterPlayer.StarterPlayerScripts.Client
│       ├── init.client.lua
│       ├── Controllers/
│       │   ├── HUDController.lua
│       │   ├── FishingController.lua
│       │   ├── InventoryController.lua
│       │   ├── MarketController.lua
│       │   ├── HarborEditController.lua
│       │   ├── SocialController.lua
│       │   └── WorldFXController.lua
│       └── UI/
│           ├── UIUtil.lua             # palette + scaling rig
│           ├── HUD.lua                # topbar + bottom action bar
│           ├── CastMeter.lua          # timing meter overlay
│           ├── InventoryUI.lua
│           ├── MarketUI.lua
│           ├── HarborEditUI.lua
│           └── QuestTrackerUI.lua
```

## Dev roadmap (interactive)

Open [`roadmap.html`](roadmap.html) in a browser for an interactive implementation map: a **dependency flowchart** (click any node), **CLAUDE.md pillar audit chips**, and backlog cards — each opens a ready-to-paste Cursor / Claude Code prompt (prefixed with CLAUDE.md guardrails). Status last synced May 2026. Deep-link examples: `roadmap.html#smokehouse`, `roadmap.html#ui-overhaul`, `roadmap.html#ui-remaining-screens`.

## 1. First-time setup

### Install Rojo

```
rojo --version    # need 7.x
# https://rojo.space/docs/v7/getting-started/installation/
```

### Install dependencies (Wally)

```
wally install
```

This downloads Knit, Promise, Trove, Signal into `Packages/`. Rojo's project
file maps `Packages/` to `ReplicatedStorage.Packages` automatically.

### Vendor ProfileService

ProfileService is **not** on Wally. Manually:

1. Download:
   `https://raw.githubusercontent.com/MadStudioRoblox/ProfileService/master/ProfileService.lua`

2. Save as: `src/Shared/Vendor/ProfileService.lua`

3. Done — `PlayerDataService` already requires it from
   `ReplicatedStorage.Shared.Vendor.ProfileService`.

## 2. Running in Studio

```
rojo serve
```

Then in Roblox Studio: **Plugins ▸ Rojo ▸ Connect** (port 34872 by default).

### Roblox Studio MCP (Cursor agent)

To let the Cursor agent run Luau and edit your open place from chat, enable Studio MCP and connect Cursor. See [scripts/Studio/MCP_Setup.md](scripts/Studio/MCP_Setup.md). Use **only** global `~/.cursor/mcp.json` (not a duplicate project config). After changes, **fully restart Cursor** with your place already open in Studio; the MCP row must show tools, not "No tools…".

> **DataStore note**: DataStores don't write to disk in Studio unless
> "Enable Studio Access to API Services" is on under **Game Settings ▸
> Security**. Without it, profile data won't persist between Studio sessions
> — you'll see a warning in Output and ProfileService falls back to mock mode.
> The market and crew DataStores behave the same way.

## 3. Publishing

1. Create a new place on Roblox.
2. From Studio (with Rojo synced) → **File ▸ Publish to Roblox As**.
3. In **Game Settings ▸ Security** enable:
   - "Enable Studio Access to API Services"
   - "Allow HTTP Requests" (only needed if you later add HttpService for
     analytics; the base game does not use it)
4. In **Game Settings ▸ Permissions** ensure your place is set to public, or
   provide tester access.

## 4. Test checklist

After connecting Rojo and pressing Play:

- [ ] Server boot logs `[TidesOfTrade] Server services started.`
- [ ] Client boot logs `[TidesOfTrade] Client controllers started.`
- [ ] HUD appears with coins/lure/level chips
- [ ] On a touch device emulator (Studio: View ▸ Device Emulator), bottom
      action bar appears with 5 buttons
- [ ] At 380px-wide portrait, action bar buttons remain ≥44px tall
- [ ] Tapping Rod opens a cast meter; release in green zone awards a fish
- [ ] Inventory shows the catch with weight + Sell button
- [ ] Listing a fish → opening Market shows it; second test client can buy
- [ ] Building Place → Confirm spawns a part on the player's plot
- [ ] After a server restart, the player's coins/inventory/buildings persist
      (assuming API services are enabled)
- [ ] Tide level changes visibly every ~10 minutes (cycle is 20 min)
- [ ] Weather rotates every 90s

### Two-client test for the market

DataStore-backed cross-server features only show end-to-end behavior with
two clients. In Studio: **Test ▸ Start ▸ Local Server (2 players)**.

## 5. Configuration knobs

Almost everything is in `src/Shared/Config/GameConfig.lua`:

| Value                            | Effect                                  |
|---------------------------------|-----------------------------------------|
| `Economy.MarketFeePct`          | Coin sink rate                          |
| `Economy.MaxActiveListingsPerPlayer` | Anti-spam cap                      |
| `Tides.CycleSeconds`            | Tide period (default: 20 min)           |
| `Weather.TickSeconds`           | How often weather may transition        |
| `Fishing.RarityWeights`         | Catch rarity distribution               |
| `Quests.Templates`              | Daily quest pool                        |
| `LoginRewards`                  | Day 1–7 reward sequence                 |
| `Crew.MaxMembers`               | Crew size cap                           |
| `AntiExploit.*`                 | Per-minute rate limits                  |

To **wipe all data** (e.g. economy gone wrong in early access), bump
`DataStores.ProfileStore` from `TidesProfile_v1` to `_v2`. **There is no
auto-migration** — this is intentional. Don't bump in production unless you
mean it.

## 6. Adding fish

Edit `src/Shared/Config/FishCatalog.json`. Schema is documented in the file's
`_doc` block. Stable `id` strings are critical — once a player has caught
`harbor_mackerel`, that string is in their inventory and DataStore forever.
Renaming it would orphan their save.

## 7. Adding buildings

Edit `src/Shared/Config/BuildingCatalog.lua`. Add a new entry with three
tiers; `HarborService` and `MarketService` automatically pick up:

- Income contribution (`incomePerTick`)
- Listing slot bonus (`marketStallExtraListings`)
- Crew slot bonus (`guildhallCrewBonus`)
- Bait discount (`baitDiscountPct`) — wired through whenever you implement
  the bait shop NPC

## 8. TODOs left for art/audio

These are stubbed with placeholder logic. Search the codebase for `TODO:` to
find them all:

- **Audio asset IDs**: Phase 1 library IDs in `src/Client/AssetIds.lua`
  (see `assets/audio/TRACKING.md`). Replace with your uploads when ready.
- **Building meshes**: `HarborService:_spawnBuildingVisual` makes a tinted
  box. Swap with a `:Clone()` from `ReplicatedStorage.Assets.Buildings.<kind>`.
- **Animations**: Emotes are server-broadcast but `SocialController` only
  prints them. Hook to your character animator.
- **Game Pass IDs**: `Captain's Log` (XP doubler + analytics) needs to be
  created in the Roblox dashboard, ID dropped into a new `Monetization.lua`.

## 9. Anti-exploit summary

- All economy/inventory mutations live server-side in services.
- Every RemoteEvent path validates ownership and rate limits.
- `FishingService` chooses the fish before the client knows; the client
  can only influence the timing release. Replay attacks are blocked by a
  6s claim window.
- `MarketService:Create` removes the inventory item only after the listing
  DataStore write succeeds, preventing duplicate-then-cancel exploits.
- ProfileService session-locks profiles, so a player can't be logged in on
  two servers spending the same coins.

## 10. Performance & scale notes

- `StreamingEnabled` is on with 64-stud minimum / 256-stud target. Players
  far away from each other's harbors won't replicate parts.
- The market DataStore is a single ~4MB JSON value. At expected scale
  (few hundred concurrents × 10 listings) we use ~30% of the cap. If
  you grow past that, shard the index by rarity (`market_index_common`,
  `market_index_rare`, etc.).
- MessagingService payloads are throttled to 1KB; we deliberately send
  empty heartbeats and let receivers re-fetch from DataStore.

## License

Your project, your license. Vendored ProfileService is MIT — keep its
license header in `src/Shared/Vendor/ProfileService.lua`.
