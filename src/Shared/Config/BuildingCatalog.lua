--!strict
-- BuildingCatalog.lua
-- All placeable buildings and their tier curves. Each tier 1->2->3 should roughly
-- double effectiveness while costing more than double — encourages spending
-- on multiple buildings rather than one max-tier monolith.

export type BuildingKind = "Dock" | "MarketStall" | "Smokehouse" | "Lighthouse" | "BaitShop" | "Guildhall" | "Aquarium"

-- Placement and upgrade costs are NOT stored here — they live in
-- GameConfig.Buildings[kind].tierCosts so all economy numbers stay in
-- one designer-editable place. HarborService reads from there; this type
-- covers only the structural / behavioural data per tier.
export type BuildingTier = {
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
			{ incomePerTick = 0  },               -- starter dock (free — see GameConfig.Buildings)
			-- Tier 2 is the tutorial's "first repair" — see GameConfig.Tutorial.RepairCostCoins
			-- and GameConfig.Buildings.Dock.tierCosts[2] for the coin cost.
			{ incomePerTick = 5  },
			{ incomePerTick = 15 },
		},
	},

	MarketStall = {
		id = "MarketStall",
		displayName = "Market Stall",
		footprint = {3, 3},
		description = "Sells passive trickle of catch and unlocks extra global listings.",
		tiers = {
			{ incomePerTick = 8,  marketStallExtraListings = 0 },
			{ incomePerTick = 20, marketStallExtraListings = 3 },
			{ incomePerTick = 50, marketStallExtraListings = 7 },
		},
	},

	Smokehouse = {
		id = "Smokehouse",
		displayName = "Smokehouse",
		footprint = {3, 4},
		description = "Preserves raw fish into goods worth 3x. Limited slots per tier.",
		tiers = {
			{ incomePerTick = 0, smokehouseSlots = 2  },
			{ incomePerTick = 0, smokehouseSlots = 5  },
			{ incomePerTick = 0, smokehouseSlots = 10 },
		},
	},

	Lighthouse = {
		id = "Lighthouse",
		displayName = "Lighthouse",
		footprint = {3, 3},
		description = "Lures fish near your harbor. Buffs catch rate within radius.",
		tiers = {
			{ incomePerTick = 0, lighthouseLureRadiusStuds = 30 },
			{ incomePerTick = 0, lighthouseLureRadiusStuds = 55 },
			{ incomePerTick = 0, lighthouseLureRadiusStuds = 90 },
		},
	},

	BaitShop = {
		id = "BaitShop",
		displayName = "Bait Shop",
		footprint = {2, 3},
		description = "Discounts bait costs and produces small passive income.",
		tiers = {
			{ incomePerTick = 4,  baitDiscountPct = 0.10 },
			{ incomePerTick = 12, baitDiscountPct = 0.20 },
			{ incomePerTick = 30, baitDiscountPct = 0.35 },
		},
	},

	Aquarium = {
		id = "Aquarium",
		displayName = "Aquarium",
		footprint = {3, 4},
		description = "Display your catches. Each fish trickles passive XP + coins by rarity.",
		tiers = {
			{ incomePerTick = 0, aquariumCapacity = 4  },
			{ incomePerTick = 0, aquariumCapacity = 10 },
			{ incomePerTick = 0, aquariumCapacity = 24 },
		},
	},

	Guildhall = {
		id = "Guildhall",
		displayName = "Guildhall",
		footprint = {5, 5},
		description = "Required for crews. Higher tiers expand crew capacity.",
		tiers = {
			{ incomePerTick = 10, guildhallCrewBonus = 0 },
			{ incomePerTick = 25, guildhallCrewBonus = 2 },
			{ incomePerTick = 60, guildhallCrewBonus = 4 },
		},
	},
}

return BuildingCatalog
