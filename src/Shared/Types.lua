--!strict
-- Types.lua
-- Shared type definitions. Importing these into both server and client keeps
-- the network shape honest — change the type once, both sides scream until
-- they're updated.

local Types = {}

-- ====================================================================
-- INVENTORY ITEMS
-- ====================================================================
-- A single inventory entry. We store fish per *catch* (not stacked) because
-- weight varies per catch and weight affects price. Other goods stack.

export type FishItem = {
	uid: string,        -- unique per catch, used for market listings
	kind: "Fish",
	speciesId: string,  -- matches FishCatalog id
	weightKg: number,
	caughtAt: number,   -- os.time() of catch, used for spoilage / display
	modifiers: {string}?, -- e.g. {"shiny", "giant"}; nil when unmodified
}

export type GoodItem = {
	uid: string,
	kind: "Good",       -- preserved goods, lures, etc.
	goodId: string,     -- e.g. "preserved_mackerel", "rare_lure"
	count: number,
	-- Set on preserved_* goods so sell price can use the source catch weight.
	weightKg: number?,
}

export type InventoryItem = FishItem | GoodItem

-- ====================================================================
-- BUILDINGS
-- ====================================================================
-- A placed building on a player's plot. Position is stored in grid coords
-- (not world studs) so the same data works regardless of plot location.

-- Smokehouse slot: fish smokes here until ready, then claim moves a Good
-- into inventory. Keys are 1..smokehouseSlots (tier capacity).
export type PreserveSlot = {
	speciesId: string,
	startedAt: number,
	weightKg: number,
	ready: boolean?,        -- set by SmokehouseService tick when PreserveTimeSec elapsed
	goodId: string?,        -- "preserved_" .. speciesId when ready
	modifiers: {string}?,   -- carried from FishItem so Cancel/Refund can restore the full fish
}

export type PlacedBuilding = {
	uid: string,
	kind: string,       -- BuildingCatalog key
	tier: number,       -- 1..3
	gridX: number,      -- top-left grid cell
	gridZ: number,
	rotation: number,   -- 0|90|180|270 degrees
	placedAt: number,
	preserveSlots: {[number]: PreserveSlot}?,  -- Smokehouse only
}

-- ====================================================================
-- QUESTS
-- ====================================================================
-- A rolled, per-player daily quest. The quest's *shape* (text, trigger,
-- match/progress/reward logic) lives in QuestTemplates.lua keyed by
-- templateId. This struct carries only the per-player roll: the sampled
-- parameters, the player's progress, and claim state. Reward amounts are
-- snapshotted at roll-time (via the template's rewardFormula) so that
-- balance tweaks to a template don't retroactively change what a player
-- already saw.

export type QuestReward = {
	coins: number?,
	xp: number?,
	lureTokens: number?,
	items: {{id: string, count: number}}?,
}

export type Quest = {
	id: string,                      -- per-player unique id (e.g. "daily_2026-05-15_uid")
	templateId: string,              -- key into QuestTemplates (e.g. "fishing_catch_n")
	params: {[string]: any},         -- sampled parameter values for this roll
	progress: number,
	target: number,                  -- progress required to complete
	difficulty: string,              -- "easy" | "medium" | "hard" | "tutorial"
	reward: QuestReward,             -- snapshotted at roll-time
	completed: boolean,
	claimed: boolean,
	rolledForUtcDay: string,         -- the "YYYY-MM-DD" the quest belongs to
	expiresAt: number,               -- os.time() — drives the yesterday-grace countdown
	-- Opaque service-only state for templates that need uniqueness
	-- tracking (e.g. exploration_biomes_visited tracks the set of biomes
	-- seen today). Keys are template-defined.
	progressState: {[string]: any}?,
	-- Cached rendered text so clients and logs don't need to import the
	-- template module. Re-derivable from templateId+params if dropped.
	renderedText: string,
	-- Localized category for UI grouping ("fishing" | "market" | ...).
	category: string,
}

-- ====================================================================
-- STREAK
-- ====================================================================
export type Streak = {
	current: number,                 -- consecutive UTC days logged in
	longest: number,                 -- record
	lastLoginUtcDay: string?,        -- "YYYY-MM-DD" of last credited login
	weekStartedAt: number,           -- os.time() of the current 7-day cycle start
}

-- ====================================================================
-- COSMETICS
-- ====================================================================

export type Cosmetics = {
	hat: string?,
	coat: string?,
	boots: string?,
}

-- ====================================================================
-- PROFILE
-- ====================================================================
-- The full ProfileService data shape. Keep this in sync with
-- PlayerDataService.PROFILE_TEMPLATE.

export type Profile = {
	-- Currencies
	coins: number,
	lureTokens: number,

	-- Progression
	level: number,
	xp: number,

	-- Inventory & buildings
	inventory: {InventoryItem},
	buildings: {PlacedBuilding},
	-- World-plot slot index assigned on first join. Persisted so the same
	-- player always returns to the same patch of coastline, even across
	-- server restarts. nil until the first assignment.
	plotIndex: number?,
	-- Aquarium contents keyed by aquarium building uid. Fish here aren't in
	-- the main inventory — they're "displayed" and grant passive trickle.
	aquariumStock: {[string]: {FishItem}},
	cosmetics: Cosmetics,
	rodTier: number,
	-- The named rod the player has selected. Defaults to "driftwood".
	-- Drives castWindowBonus and catchWeightBonus in FishingService.
	-- Setting this also syncs rodTier for fish species access.
	equippedRodId: string?,

	-- Daily systems
	streak: Streak,
	dailyQuests: {Quest},
	-- Yesterday's completed-but-unclaimed quests, held for
	-- GameConfig.Quests.RolloverGraceHours after the midnight refresh. After
	-- the grace window ends this list is wiped (rewards forfeit).
	-- Incomplete quests from yesterday are NOT moved here — they're
	-- discarded outright (cozy: no stress accumulation).
	yesterdayQuests: {Quest},
	questsRefreshedDay: string?,

	-- Social
	crewId: string?,

	-- Active bait buff (nil when no bait is active). The server checks
	-- expiresAt every time fish are rolled, and clears it if expired.
	activeBuff: {
		kind: string,
		expiresAt: number,
		rareWeightMultiplier: number,   -- how much to boost Uncommon/Rare/Mythic weights
	}?,

	-- Bait inventory: baitId -> unit count. Populated by BaitService;
	-- never stored inside the general inventory array because bait is
	-- stackable, consumed per-cast, and looked up by id frequently.
	baitStash: {[string]: number},
	-- The bait the player has equipped (nil = no bait active on next cast).
	equippedBaitId: string?,

	-- Stats (for analytics + Captain's Log gamepass)
	stats: {
		totalCatches: number,
		totalSold: number,
		totalCoinsEarned: number,
		caughtSpecies: {[string]: number},
	},

	-- Schema version for future migrations
	schemaVersion: number,
}

-- ====================================================================
-- MARKET
-- ====================================================================

export type MarketListing = {
	listingId: string,
	sellerId: number,           -- UserId
	sellerName: string,
	itemKind: "Fish" | "Good",
	speciesId: string?,         -- for fish
	goodId: string?,            -- for goods
	weightKg: number?,          -- for fish
	modifiers: {string}?,       -- for fish; copied from FishItem.modifiers at list time
	count: number,              -- 1 for unique fish, N for goods
	price: number,              -- TOTAL price for the whole listing
	listedAt: number,
	expiresAt: number,
}

return Types
