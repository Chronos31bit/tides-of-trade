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
}

export type GoodItem = {
	uid: string,
	kind: "Good",       -- preserved goods, lures, etc.
	goodId: string,     -- e.g. "preserved_mackerel", "rare_lure"
	count: number,
}

export type InventoryItem = FishItem | GoodItem

-- ====================================================================
-- BUILDINGS
-- ====================================================================
-- A placed building on a player's plot. Position is stored in grid coords
-- (not world studs) so the same data works regardless of plot location.

export type PlacedBuilding = {
	uid: string,
	kind: string,       -- BuildingCatalog key
	tier: number,       -- 1..3
	gridX: number,      -- top-left grid cell
	gridZ: number,
	rotation: number,   -- 0|90|180|270 degrees
	placedAt: number,
}

-- ====================================================================
-- QUESTS
-- ====================================================================

export type Quest = {
	id: string,         -- per-player unique id (e.g. "daily_2026_05_10_1")
	kind: string,       -- "CatchSpecies" | "CatchAnyFish" | ...
	target: number,     -- e.g. catch 5 mackerel -> 5
	progress: number,
	-- For CatchSpecies, the specific species id required.
	speciesId: string?,
	rewardCoins: number,
	rewardXp: number,
	completed: boolean,
	claimed: boolean,
	expiresAt: number,
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
	-- Aquarium contents keyed by aquarium building uid. Fish here aren't in
	-- the main inventory — they're "displayed" and grant passive trickle.
	aquariumStock: {[string]: {FishItem}},
	cosmetics: Cosmetics,
	rodTier: number,

	-- Daily systems
	loginStreak: number,
	lastLoginDay: string?,    -- "YYYY-MM-DD" UTC
	dailyQuests: {Quest},
	questsRefreshedDay: string?,

	-- Social
	crewId: string?,

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
	count: number,              -- 1 for unique fish, N for goods
	price: number,              -- TOTAL price for the whole listing
	listedAt: number,
	expiresAt: number,
}

return Types
