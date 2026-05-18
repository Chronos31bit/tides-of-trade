--!strict
-- GameConfig.lua
-- Single source of truth for tunable economy + world numbers.
-- Anything you'd want a designer to twiddle without touching service code lives here.

local GameConfig = {}

-- ====================================================================
-- ECONOMY
-- ====================================================================
GameConfig.Economy = {
	-- 5% transaction fee on every market sale. Sinks coins out of the economy.
	-- Tune up if inflation creeps; tune down if listings dry up.
	MarketFeePct = 0.05,

	-- Hard cap on simultaneous active listings per player. Prevents one whale
	-- from spamming the global board and starving other listings of visibility.
	MaxActiveListingsPerPlayer = 10,

	-- Minimum and maximum coin price you can list a single item for.
	-- Min stops dust-listing griefs; max stops gold-laundering exploits.
	MinListingPrice = 1,
	MaxListingPrice = 1_000_000,

	-- Listings auto-expire after this many seconds (48h). Server sweeps expired
	-- listings on a timer in MarketService.
	ListingTTLSeconds = 48 * 60 * 60,

	-- Daily demand spike: one species pays this multiplier for 24h.
	-- Drives login engagement ("which fish today?").
	DemandSpikeMultiplier = 2.5,

	-- Smokehouse conversion: preserved goods sell for this multiple of raw fish.
	SmokehouseMultiplier = 3.0,
}

-- ====================================================================
-- BIOMES — used by FishCatalog, FishingService, and the world generator
-- ====================================================================
GameConfig.Biomes = {
	Shoreline  = "Shoreline",   -- safe starter zone, plentiful commons
	Pier       = "Pier",        -- harbor-adjacent, similar to shoreline
	Reef       = "Reef",        -- mid-game, more variety
	DeepWater  = "DeepWater",   -- requires boat/dock tier 2+
	Trench     = "Trench",      -- end-game, mythics only at high tide
}

-- ====================================================================
-- TIDES — drives the 20-minute high/low cycle
-- ====================================================================
GameConfig.Tides = {
	-- Total period: 20 real minutes per full low->high->low cycle.
	-- The world spends ~half the cycle in High and ~half in Low, with short
	-- transition windows in between (handled in TideService).
	CycleSeconds = 20 * 60,

	-- Fraction of cycle classified as High tide (the rest is Low).
	-- 0.45 leaves a 5% transition margin on each side.
	HighFraction = 0.45,
}

-- ====================================================================
-- WEATHER — probabilistic state machine, ticked by WeatherService
-- ====================================================================
GameConfig.Weather = {
	-- How often (seconds) the weather may roll a transition.
	TickSeconds = 90,

	-- Per-tick transition probabilities. Rows sum to 1.0.
	-- Layout: From -> To -> probability.
	-- Sticky weights (Clear->Clear, etc.) keep states from flickering.
	Transitions = {
		Clear  = { Clear = 0.70, Cloudy = 0.25, Fog    = 0.05 },
		Cloudy = { Cloudy = 0.55, Clear = 0.20, Rain   = 0.20, Fog = 0.05 },
		Rain   = { Rain   = 0.55, Cloudy = 0.30, Storm  = 0.15 },
		Storm  = { Storm  = 0.40, Rain   = 0.55, Cloudy = 0.05 },
		Fog    = { Fog    = 0.55, Clear  = 0.25, Cloudy = 0.20 },
	},
}

-- ====================================================================
-- TIME OF DAY — Lighting.ClockTime breakpoints
-- ====================================================================
GameConfig.TimeOfDay = {
	-- The Roblox day is 24 ClockTime units (game hours). We map:
	--   Morning: 5..9
	--   Day:     9..17
	--   Dusk:    17..20
	--   Night:   20..5  (wraps midnight)
	-- WeatherService advances ClockTime so a full day is real-life ~24 minutes.
	MinutesPerGameDay = 24,
}

-- ====================================================================
-- HARBOR
-- ====================================================================
GameConfig.Harbor = {
	-- Plot is 80x80 studs as required. Grid cells are 4 studs so buildings
	-- snap cleanly. 80/4 = 20x20 grid of placement cells per plot.
	PlotSizeStuds = 80,
	GridCellStuds = 4,

	-- Cap concurrent buildings per plot to keep the network and physics budget
	-- in check with StreamingEnabled.
	MaxBuildingsPerPlot = 60,

	-- Passive income tick interval (seconds). Buildings produce coins per tick.
	IncomeTickSeconds = 60,

	-- ----------------------------------------------------------------
	-- VISUAL TUNING — every magic number for the visible harbor
	-- transformation system. Drives upgrade tween timing, particle
	-- burst, debris spawn density, and reduced-motion scaling.
	-- Designer-friendly: tweak these without hunting through HarborVisualController.
	-- ----------------------------------------------------------------
	VisualTuning = {
		UpgradeTransitionDuration = 1.5,
		UpgradeFadeOutDuration    = 0.5,
		UpgradeFadeInDuration     = 1.0,
		UpgradeOvershoot          = 1.05,
		UpgradeSettleDuration     = 0.3,
		ParticleBurstCount        = 30,
		ParticleBurstDuration     = 0.3,
		ParticleSpawnDelay        = 0.4,
		AudioSpawnDelay           = 0.4,
		HapticSpawnDelay          = 0.4,
		DebrisFadeOutDuration     = 0.5,
		DebrisPerBuildingMin      = 3,
		DebrisPerBuildingMax      = 5,
		DebrisRadiusStuds         = 6,
		DebrisMaxPerPlot          = 30,
		ReducedMotionDurationScale = 0.5,
	},
}

-- ====================================================================
-- BUILDINGS — all coin costs live here so designers can tune the build
-- economy in one place without touching BuildingCatalog's structural
-- data (footprints, behavior flags, description text).
-- tierCosts[1] = placement cost; [2]/[3] = upgrade costs into that tier.
-- ====================================================================
GameConfig.Buildings = {
	Dock        = { tierCosts = { 0,     40,     9000  } },
	MarketStall = { tierCosts = { 800,   3500,   12000 } },
	Smokehouse  = { tierCosts = { 1500,  6000,   18000 } },
	Lighthouse  = { tierCosts = { 2000,  7500,   22000 }, RarityBumpChance = { 0.15, 0.28, 0.45 } },
	BaitShop    = { tierCosts = { 600,   2400,   8000  } },
	Aquarium    = { tierCosts = { 1200,  5000,   16000 } },
	Guildhall   = { tierCosts = { 5000,  15000,  40000 } },
}

-- ====================================================================
-- FISHING
-- ====================================================================
GameConfig.Fishing = {
	-- Cast meter oscillation period (seconds). Lower = harder.
	CastMeterPeriod = 1.4,

	-- Minimum cooldown between casts (anti-spam, anti-exploit).
	CastCooldownSeconds = 0.5,

	-- How long the meter stays up before the cast auto-fails.
	CastTimeoutSeconds = 8.0,

	-- Reel mini-game window. After the bite (ClaimCast hit), the player has
	-- this many seconds to either complete the hold or escape, otherwise the
	-- pending cast is reaped and CastResolved fires with reason="reel_timeout".
	ReelTimeoutSeconds = 12.0,

	-- Consolation XP granted when a fish escapes during the reel phase.
	EscapeConsolationXP = 5,

	-- Lure Token drop chance per successful catch (premium soft currency).
	LureTokenDropChance = 0.02, -- 2% per catch

	-- Rarity weights when rolling which fish from the eligible pool to award.
	-- Higher = more common. These are *post-filter* weights — only fish that
	-- match the current biome/tide/weather/time get rolled at all.
	RarityWeights = {
		Common    = 50,
		Uncommon  = 25,
		Rare      = 13,
		Epic      =  7,
		Legendary =  3,
		Mythic    =  1.5,
		Divine    =  0.5,
	},

	-- ----------------------------------------------------------------
	-- FEEL TUNING — every magic number for the cast/reel/reveal UI.
	-- Designer-friendly: tweak these without hunting through controllers.
	--
	-- Reel-related values (ReelHoldDuration / ReelZoneSpeed*) are
	-- referenced by the future server-validated reel mini-game (Path A
	-- of the polish plan). They're harmless to keep here today; the
	-- current single-phase contract just ignores them.
	-- ----------------------------------------------------------------
	FeelTuning = {
		CastShakeMagnitude        = 0.3,
		CastShakeDuration         = 0.25,
		RippleMaxRadius           = 4,
		RippleDuration            = 0.8,
		RippleCount               = 2,
		HapticIntensity           = 0.4,
		HapticDuration            = 0.08,
		MeterTransitionDuration   = 0.3,
		ReelHoldDuration          = 2.0,
		ReelZoneSpeedBase         = 1.2,
		ReelZoneSpeedPerKg        = 0.04,
		PerfectZoneFraction       = 0.25,
		PerfectBonusMultiplier    = 2.0,
		PerfectThreshold          = 0.8,
		-- Perfect-cast: marker lands in the inner gold strip → fish is heavier.
		PerfectCastWeightBonus    = 0.15,   -- +15% weight, capped at 1.5× catalog max
		-- Perfect-reel: award immediate coins = fraction of the fish's base market price.
		PerfectReelCoinFraction   = 0.20,   -- 20% of fish.basePrice awarded on completion
		RevealSlideInDuration     = 0.5,
		RevealAutoDismissAfter    = 3.0,
		MythicBorderCycleDuration = 1.5,
	},

	-- ----------------------------------------------------------------
	-- ROD TIER UNLOCKS — declarative tier slots. `speciesUnlocked` is
	-- left empty here and populated at server boot from FishCatalog by
	-- RodTierUtil.populate (RodService:KnitInit). Keyed by tier number.
	--
	-- Intentionally species-ONLY: the rod display name / cost /
	-- description already live in ShopService.RODS (the rod shop's
	-- catalog, client-exposed via ShopService:GetRodCatalog). Duplicating
	-- them here would let the two drift apart, so the tooltip pulls names
	-- from the shop catalog and counts/species from FishCatalog via
	-- RodTierUtil. Biomes are NOT listed because rod tier does not gate
	-- biomes in this game — only per-fish rodMinTier gates catches.
	--
	-- Slot count must cover every rodMinTier the catalog uses (currently
	-- 1..5). RodTierUtil only populates slots that exist here.
	RodTierUnlocks = {
		[1] = { speciesUnlocked = {} },
		[2] = { speciesUnlocked = {} },
		[3] = { speciesUnlocked = {} },
		[4] = { speciesUnlocked = {} },
		[5] = { speciesUnlocked = {} },
	},
}

-- ====================================================================
-- UI — client-only presentation tunables (no gameplay effect)
-- ====================================================================
GameConfig.UI = {
	-- HUD rod-tier chip + its tap/long-press tooltip.
	RodTierChip = {
		-- Tooltip auto-dismisses after this many seconds of no interaction.
		TooltipInactivitySeconds = 12,
		-- Fade in/out duration. Under ReducedMotion the slide is skipped but
		-- the fade still plays (halved) — a fade is the reduced-motion-safe
		-- form of "appear".
		TooltipFadeDuration      = 0.18,
		-- Slide-in vertical offset (px). Skipped entirely under ReducedMotion.
		TooltipSlideOffsetPx     = 14,
		-- Tier-change glow pulse duration (decorative; snapped under RM).
		GlowPulseDuration        = 0.45,
		-- Max example species names shown in the "next tier" preview.
		NextTierExampleLimit     = 5,
		-- Hold this long (seconds) on touch to count as a long-press open.
		LongPressSeconds         = 0.35,
		-- Max-tier accent colour cycle period (reuses the mythic-frame feel).
		MaxTierCycleDuration     = 1.5,
		-- Single source of truth for the tooltip's "how to upgrade" line.
		-- The Rod Shop exists (ShopService:BuyRodTier), so this points at it
		-- rather than a placeholder. Edit this one string if the path moves.
		UpgradeHintText          = "Upgrade your rod at the Rod Shop on the dock.",
	},
}

-- ====================================================================
-- TUTORIAL — first-session onboarding tunables
-- ====================================================================
-- Every magic number for the 0–25 minute flow lives here. Dialogue lines
-- themselves are in src/Shared/Config/TutorialConfig.lua (kept separate
-- so writers can edit voice without touching numeric tuning).
GameConfig.Tutorial = {
	-- Multiplier applied to the *validation* green zone width for the first
	-- N successful casts. The visual width stays normal — players see what
	-- looks like a near-miss become a catch. Server-only knob.
	BeginnerAssistMultiplier        = 1.8,
	BeginnerAssistCount             = 3,

	-- Beat 2: cast-stuck nudges. First nudge after 90s of no cast attempt,
	-- repeats every 60s. Analytics-only stuck event at 4 minutes.
	Beat2StuckTimeoutSeconds        = 90,
	Beat2StuckRepeatSeconds         = 60,
	Beat2AnalyticsStuckSeconds      = 240,

	-- Beat 3: if the player catches but doesn't head to the stall, drop a
	-- HUD waypoint pointing at the market stall after this many seconds.
	Beat3WaypointDelaySeconds       = 60,
	Beat3StallProximityStuds        = 8,

	-- Beat 5: re-encouragement cadence while the player waits to afford
	-- the dock repair. Re-checks on every coin gain via PlayerData hooks.
	Beat5EncouragementRepeatSeconds = 30,
	RepairCostCoins                 = 40,

	-- Beat 6: the seeded daily quest's reward.
	FirstQuestRewardCoins           = 100,
	FirstQuestTarget                = 5,        -- catch 5 fish

	-- Mira spawn anchor (along dock-edge offset from dock-building corner).
	MiraSpawnOffsetStuds            = 6,

	-- If the player roams more than this many studs from their plot
	-- origin, Mira despawns and respawns near them with a recall line.
	WanderRecallDistanceStuds       = 80,
	WanderRecallCheckSeconds        = 2,

	-- DialogueUI feel.
	TypewriterCharsPerSecond        = 40,
	DialogueSlideInDuration         = 0.4,
	DialogueReducedMotionFadeIn     = 0.2,
	DialogueZIndex                  = 5,

	-- How long a dialogue line stays on screen before auto-hiding (no
	-- gameplay impact — state is preserved, player can re-open via the
	-- "Talk" ProximityPrompt on Mira). Keeps the dialogue panel out of
	-- the way during fishing / interacting with HUD.
	DialogueAutoDismissSeconds         = 8,
	DialogueAutoDismissTransientSeconds = 4,
}

-- ====================================================================
-- QUESTS — daily refresh at midnight UTC
-- ====================================================================
-- All tunable knobs for the daily-quest system. Quest *shapes* live in
-- src/Shared/Config/QuestTemplates.lua; this block sets the dials around
-- them: how many slots per day, which categories rotate when, what each
-- difficulty band pays out, and how long completed-but-unclaimed quests
-- linger after midnight.
GameConfig.Quests = {
	DailyCount = 3,
	-- After midnight UTC, completed-but-unclaimed quests move to
	-- profile.yesterdayQuests and stay claimable for this many hours.
	-- Incomplete quests are discarded outright (cozy: no streak stress).
	RolloverGraceHours = 24,

	-- Weekday rotation. UTC weekdays use Mon=1..Sun=7. Each day picks
	-- exactly 3 categories so the daily roll always spans 3 distinct
	-- categories — no day of three fishing quests.
	CategoryRotation = {
		[1] = { "fishing", "market", "social" },        -- Monday
		[2] = { "fishing", "market", "social" },        -- Tuesday
		[3] = { "fishing", "building", "exploration" }, -- Wednesday
		[4] = { "fishing", "building", "exploration" }, -- Thursday
		[5] = { "fishing", "market", "social" },        -- Friday
		[6] = { "fishing", "building", "exploration" }, -- Saturday
		[7] = { "fishing", "market", "exploration" },   -- Sunday
	},

	-- Difficulty mix per day. Today's roll always picks 1 easy + 1 medium
	-- + 1 hard quest, mapped onto the 3 rotation categories in that order
	-- (easy → first rotation category, etc.). Adjust if the daily feels
	-- too breezy or grindy.
	DifficultyDistribution = { "easy", "medium", "hard" },

	-- Reward bands per difficulty. Templates' rewardFormula picks within
	-- these via a per-template "param scale" (e.g. larger N → closer to
	-- the band max). Easy ≈ 5 min play, medium ≈ 15 min, hard ≈ 45 min.
	DifficultyRewardScale = {
		easy     = { coinsMin = 60,  coinsMax = 120, xpMin = 25,  xpMax = 50  },
		medium   = { coinsMin = 100, coinsMax = 200, xpMin = 50,  xpMax = 100 },
		hard     = { coinsMin = 250, coinsMax = 500, xpMin = 150, xpMax = 300 },
		-- Tutorial seed is a special case — rewardFormula reads
		-- GameConfig.Tutorial.FirstQuestRewardCoins directly, ignoring
		-- this band.
		tutorial = { coinsMin = 100, coinsMax = 100, xpMin = 40,  xpMax = 40  },
	},

	-- Login-streak rewards. Day 7 is the headline (guaranteed Rare lure).
	-- Day 14/21/28 are cosmetic placeholders — the cosmetic catalog
	-- doesn't exist yet, so QuestService grants them as Good items with
	-- the placeholder ids until cosmetics ship. After day 28 the streak
	-- continues earning the day-28+ entry every day until the streak
	-- breaks; we never reset the streak just because they "finished".
	LoginStreakRewards = {
		[1]  = { coins = 50  },
		[2]  = { coins = 75  },
		[3]  = { coins = 100 },
		[4]  = { coins = 150 },
		[5]  = { coins = 200 },
		[6]  = { coins = 300 },
		-- Day 7: keep existing `rare_lure` goodId (stable IDs are forever).
		[7]  = { items = { { id = "rare_lure", count = 1 } } },
		[14] = { items = { { id = "cosmetic_streak_14", count = 1 } } },  -- TODO: cosmetic catalog
		[21] = { items = { { id = "cosmetic_streak_21", count = 1 } } },  -- TODO
		[28] = { items = { { id = "cosmetic_streak_28", count = 1 } } },  -- TODO
	},
	-- After day 28 reward this every day until streak breaks.
	LoginStreakReward28Plus = { coins = 200 },

	-- Coalescing window for the QuestsChanged network push during
	-- incremental progress. NOT a DataStore batch — the profile is mutated
	-- in memory immediately and ProfileService owns the autosave, so there
	-- is no thrash to guard against. Quest *completion* bypasses this and
	-- pushes instantly so the card flip lands with the popup. Keep this
	-- small; 0.3–0.5s coalesces rapid catches without feeling laggy.
	SnapshotPushDebounceSeconds = 0.4,

	-- How long the completion popup stays visible before auto-collapsing
	-- to a tab badge. The reward stays claimable from the tracker either way.
	CompletionPopupDuration = 8,
}

-- ====================================================================
-- CREW / GUILD
-- ====================================================================
GameConfig.Crew = {
	MaxMembers = 8,
	BaseCrewSlotsCost = 0, -- first crew is free; extra slots via game pass
}

-- ====================================================================
-- ANTI-EXPLOIT
-- ====================================================================
GameConfig.AntiExploit = {
	-- Per-player rate limits. Server drops requests above these thresholds.
	MaxCastsPerMinute     = 30,
	MaxListingsPerMinute  = 5,
	MaxBuildOpsPerMinute  = 60,

	-- If a client claims a catch outside this window after server says "fish
	-- on the line", reject. Tight window = exploiters can't replay old hooks.
	CatchClaimWindowSeconds = 6,

	-- Minimum elapsed seconds between bite and ReleaseReel claim.
	-- Below this, the reel mini-game couldn't have been played honestly.
	MinReelSeconds = 0.5,
}

-- ====================================================================
-- RODS — XP thresholds to unlock each named rod tier.
-- Display data (castWindowBonus, catchWeightBonus, color) lives in
-- RodCatalog.lua. Thresholds live here so designers can tune the
-- progression curve without touching the catalog.
-- Keys must match RodCatalog rod ids exactly.
-- ====================================================================
GameConfig.Rods = {
	-- Keyed by rod id; ascends with RodCatalog tier (apex = abyssal).
	UnlockXp = {
		driftwood = 0,       -- t1  starter rod, always available
		bamboo    = 200,     -- t2  ~10-20 fish caught
		ironwood  = 800,     -- t3  ~40-60 fish caught
		coral     = 2500,    -- t4  solid mid-game milestone
		tempest   = 7000,    -- t5  dedicated long-term players
		leviathan = 15000,   -- t6  late-game push
		aurora    = 30000,   -- t7  prestige territory
		celestial = 55000,   -- t8  months of play
		eclipse   = 95000,   -- t9  veteran flex
		abyssal   = 160000,  -- t10 apex — top of the rack
	},
}

-- ====================================================================
-- FISH MODIFIERS — rare mutations that spawn on caught fish.
-- Each modifier rolls independently per catch (dropChance = per-catch
-- probability). Multiple modifiers can stack on one fish.
-- Effect fields (all optional):
--   weightMul    : multiply resolved weight by this value
--   xpMul        : multiply XP award by this value
--   coinInstant  : grant fish.basePrice × this as instant coins on catch
--   lureBonus    : immediately grant this many extra lure tokens
-- Modifiers are stored on FishItem.modifiers for display in inventory
-- and future market-price integration. Stable ids — never rename.
-- ====================================================================
GameConfig.FishModifiers = {
	-- ── Random modifiers — rolled independently per catch ────────────────
	{ id = "shiny",        displayName = "Shiny",        dropChance = 0.015, coinInstant = 1.0,               sellPriceMul = 1.25 },
	{ id = "giant",        displayName = "Giant",        dropChance = 0.050, weightMul = 1.4                                      },
	{ id = "glowing",      displayName = "Glowing",      dropChance = 0.060,               xpMul = 1.5                           },
	{ id = "lucky",        displayName = "Lucky",        dropChance = 0.030, lureBonus = 1                                       },
	{ id = "ancient",      displayName = "Ancient",      dropChance = 0.020,               xpMul = 3.0,       sellPriceMul = 1.50 },
	{ id = "prismatic",    displayName = "Prismatic",    dropChance = 0.005, coinInstant = 2.0, weightMul = 2.0, xpMul = 2.0, sellPriceMul = 2.0 },
	{ id = "elder",        displayName = "Elder",        dropChance = 0.008,               xpMul = 5.0,       sellPriceMul = 1.80 },
	{ id = "cursed",       displayName = "Cursed",       dropChance = 0.035,               xpMul = 3.0,       sellPriceMul = 0.50 },
	{ id = "magnetic",     displayName = "Magnetic",     dropChance = 0.025, lureBonus = 3                                       },
	{ id = "barnacled",    displayName = "Barnacled",    dropChance = 0.045, weightMul = 1.6                                     },
	-- ── World-state modifiers — dropChance=0, assigned by world state ───
	{ id = "tide_kissed",  displayName = "Tide-Kissed",  dropChance = 0,                    sellPriceMul = 1.25 },
	{ id = "storm_forged", displayName = "Storm-Forged", dropChance = 0,                    sellPriceMul = 1.50 },
	{ id = "moon_touched", displayName = "Moon-Touched", dropChance = 0,     xpMul = 1.25,  sellPriceMul = 1.15 },
	{ id = "dawn_blessed", displayName = "Dawn-Blessed", dropChance = 0,     xpMul = 1.20,  sellPriceMul = 1.10 },
	{ id = "fog_shrouded", displayName = "Fog-Shrouded", dropChance = 0,     lureBonus = 1, sellPriceMul = 1.20 },
}

-- ====================================================================
-- BAIT
-- ====================================================================
-- Tunable knobs for the bait-shop purchase flow. Catalog data (names,
-- costs, rarityBoost values, maxStack) lives in BaitCatalog.lua so
-- designers can edit it without touching this file.
GameConfig.Bait = {
	-- RateLimiter window for BuyBait: at most RateLimitMax purchases in
	-- RateLimitWindowSec seconds per player.
	RateLimitMax       = 1,
	RateLimitWindowSec = 1,

	-- Maximum qty a player may request in a single BuyBait call.
	-- Prevents one-click drain exploits; also caps the UI "Buy" step.
	MaxBuyQty = 10,
}

-- ====================================================================
-- DATASTORE KEYS
-- ====================================================================
GameConfig.DataStores = {
	-- Bump this suffix to wipe all data (e.g. "ProfileV2"). Only do that if
	-- you intentionally want a fresh economy — there is no auto-migration.
	ProfileStore = "TidesProfile_v1",
	-- Cross-server market index — listings are stored as values keyed by
	-- listingId, with a sorted index for browsing.
	MarketStore  = "TidesMarket_v1",
	-- Daily demand spike — single key written by master server each UTC day.
	DemandStore  = "TidesDemand_v1",
}

-- ====================================================================
-- MESSAGINGSERVICE TOPICS — used for cross-server market notifications
-- ====================================================================
GameConfig.Topics = {
	MarketListed   = "TidesMarket_Listed",
	MarketSold     = "TidesMarket_Sold",
	MarketCanceled = "TidesMarket_Canceled",
	DemandRotated  = "TidesMarket_Demand",
}

-- ====================================================================
-- ASSETS
-- ====================================================================
-- Canonical paths under ReplicatedStorage for art assets. All service and
-- controller code that resolves building models sources the path from here
-- so it can be updated in one place if the folder hierarchy changes.
--
-- Lookup convention used by HarborVisualController:
--   Assets.Buildings[kind]["tier" .. N] / Visual   (Model instance)
GameConfig.Assets = {
	BuildingModels = "Assets.Buildings",
}

return GameConfig
