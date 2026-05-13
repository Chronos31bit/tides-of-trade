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
	-- A little longer than ReelHoldDuration to allow for fumbles on heavy fish.
	ReelTimeoutSeconds = 12.0,

	-- Consolation XP granted when a fish escapes during the reel phase. Keep
	-- small — the point is to not punish a near-miss, not reward failure.
	EscapeConsolationXP = 5,

	-- Lure Token drop chance per successful catch (premium soft currency).
	LureTokenDropChance = 0.02, -- 2% per catch

	-- Rarity weights when rolling which fish from the eligible pool to award.
	-- Higher = more common. These are *post-filter* weights — only fish that
	-- match the current biome/tide/weather/time get rolled at all.
	RarityWeights = {
		Common   = 60,
		Uncommon = 25,
		Rare     = 12,
		Mythic   = 3,
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
		RevealSlideInDuration     = 0.5,
		RevealAutoDismissAfter    = 3.0,
		MythicBorderCycleDuration = 1.5,
	},
}

-- ====================================================================
-- QUESTS — daily refresh at midnight UTC
-- ====================================================================
GameConfig.Quests = {
	DailyCount = 3,
	-- Quest templates the QuestService can roll. {kind, target range, reward range}
	-- The actual target value is randomized within [min, max] per day.
	Templates = {
		{ kind = "CatchSpecies", targetMin = 3,  targetMax = 8,  coins = 150,  xp = 60  },
		{ kind = "CatchAnyFish", targetMin = 10, targetMax = 25, coins = 120,  xp = 50  },
		{ kind = "SellAtMarket", targetMin = 2,  targetMax = 5,  coins = 200,  xp = 80  },
		{ kind = "EarnCoins",    targetMin = 500, targetMax = 1500, coins = 100, xp = 40 },
		{ kind = "VisitHarbor",  targetMin = 1,  targetMax = 3,  coins = 80,   xp = 30  },
	},
}

-- ====================================================================
-- DAILY LOGIN — Day 7 grants a guaranteed Rare lure
-- ====================================================================
GameConfig.LoginRewards = {
	-- Streak slot 1 = day 1, slot 7 = day 7. After day 7 the cycle restarts.
	-- Mix coins, lure tokens, and on day 7 a Rare-tier lure item.
	[1] = { kind = "Coins",      amount = 100 },
	[2] = { kind = "Coins",      amount = 200 },
	[3] = { kind = "LureToken",  amount = 1   },
	[4] = { kind = "Coins",      amount = 350 },
	[5] = { kind = "LureToken",  amount = 2   },
	[6] = { kind = "Coins",      amount = 500 },
	[7] = { kind = "RareLure",   amount = 1   },
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

	-- Minimum elapsed seconds between bite (server-side ClaimCast hit) and the
	-- client's ReleaseReel claim. Below this, the reel mini-game couldn't have
	-- been played honestly. Reject as exploit; treat as escape.
	MinReelSeconds = 0.5,
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

return GameConfig
