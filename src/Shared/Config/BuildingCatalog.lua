--!strict
-- BuildingCatalog.lua
-- All placeable buildings and their tier curves. Each tier 1->2->3 should roughly
-- double effectiveness while costing more than double — encourages spending
-- on multiple buildings rather than one max-tier monolith.

export type BuildingKind = "Dock" | "MarketStall" | "Smokehouse" | "Lighthouse" | "BaitShop" | "Guildhall" | "Aquarium"

export type BuildingTier = {
	cost: number,            -- coins to upgrade INTO this tier (tier 1 cost = build cost)
	incomePerTick: number,   -- coins produced per IncomeTickSeconds (see GameConfig.Harbor)
	-- Optional behaviour switches — services check these. nil means "no effect".
	smokehouseSlots: number?,        -- how many fish can be preserved at once
	baitDiscountPct: number?,        -- discount on bait purchases at NPC shop
	lighthouseLureRadiusStuds: number?, -- buffs catch rate within this radius
	guildhallCrewBonus: number?,     -- extra crew slots
	marketStallExtraListings: number?, -- extra concurrent listings
	aquariumCapacity: number?,       -- how many fish can live in this aquarium
}

export type BuildingDef = {
	id: BuildingKind,
	displayName: string,
	-- Footprint in grid cells (width, depth). Used by HarborService grid validation.
	footprint: {number},
	-- Description shown in build menu. Keep short.
	description: string,
	tiers: {BuildingTier},
}

local BuildingCatalog: {[BuildingKind]: BuildingDef} = {

	Dock = {
		id = "Dock",
		displayName = "Dock",
		footprint = {4, 6},
		description = "Lets you cast in deeper water. Higher tiers reach Trench biome.",
		tiers = {
			{ cost = 0,    incomePerTick = 0  },               -- starter dock, free
			-- Tier 2 is the tutorial's "first repair" — kept cheap (40c) so
			-- a brand-new player can afford it after a handful of catches,
			-- matching GameConfig.Tutorial.RepairCostCoins. Tier 3 stays
			-- expensive (longer-game sink).
			{ cost = 40,   incomePerTick = 5  },
			{ cost = 9000, incomePerTick = 15 },
		},
	},

	MarketStall = {
		id = "MarketStall",
		displayName = "Market Stall",
		footprint = {3, 3},
		description = "Sells passive trickle of catch and unlocks extra global listings.",
		tiers = {
			{ cost = 800,  incomePerTick = 8,  marketStallExtraListings = 0 },
			{ cost = 3500, incomePerTick = 20, marketStallExtraListings = 3 },
			{ cost = 12000,incomePerTick = 50, marketStallExtraListings = 7 },
		},
	},

	Smokehouse = {
		id = "Smokehouse",
		displayName = "Smokehouse",
		footprint = {3, 4},
		description = "Preserves raw fish into goods worth 3x. Limited slots per tier.",
		tiers = {
			{ cost = 1500, incomePerTick = 0, smokehouseSlots = 2 },
			{ cost = 6000, incomePerTick = 0, smokehouseSlots = 5 },
			{ cost = 18000,incomePerTick = 0, smokehouseSlots = 10 },
		},
	},

	Lighthouse = {
		id = "Lighthouse",
		displayName = "Lighthouse",
		footprint = {3, 3},
		description = "Lures fish near your harbor. Buffs catch rate within radius.",
		tiers = {
			{ cost = 2000, incomePerTick = 0, lighthouseLureRadiusStuds = 30 },
			{ cost = 7500, incomePerTick = 0, lighthouseLureRadiusStuds = 55 },
			{ cost = 22000,incomePerTick = 0, lighthouseLureRadiusStuds = 90 },
		},
	},

	BaitShop = {
		id = "BaitShop",
		displayName = "Bait Shop",
		footprint = {2, 3},
		description = "Discounts bait costs and produces small passive income.",
		tiers = {
			{ cost = 600,  incomePerTick = 4,  baitDiscountPct = 0.10 },
			{ cost = 2400, incomePerTick = 12, baitDiscountPct = 0.20 },
			{ cost = 8000, incomePerTick = 30, baitDiscountPct = 0.35 },
		},
	},

	Aquarium = {
		id = "Aquarium",
		displayName = "Aquarium",
		footprint = {3, 4},
		description = "Display your catches. Each fish trickles passive XP + coins by rarity.",
		tiers = {
			{ cost = 1200, incomePerTick = 0, aquariumCapacity = 4  },
			{ cost = 5000, incomePerTick = 0, aquariumCapacity = 10 },
			{ cost = 16000,incomePerTick = 0, aquariumCapacity = 24 },
		},
	},

	Guildhall = {
		id = "Guildhall",
		displayName = "Guildhall",
		footprint = {5, 5},
		description = "Required for crews. Higher tiers expand crew capacity.",
		tiers = {
			{ cost = 5000, incomePerTick = 10, guildhallCrewBonus = 0 },
			{ cost = 15000,incomePerTick = 25, guildhallCrewBonus = 2 },
			{ cost = 40000,incomePerTick = 60, guildhallCrewBonus = 4 },
		},
	},
}

return BuildingCatalog
