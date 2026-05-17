--!strict
-- BaitCatalog.lua
-- The four starter baits sold at the Bait Shop NPC.
-- rarityBoost: multiplier on non-Common rarity weights inside FishingService.rollFish.
--   A value of 1.0 is baseline (no boost). 2.5 means Uncommon/Rare/Mythic weights
--   are each multiplied by 2.5 before the rarity roll — Common is unchanged, so
--   the *proportion* of rares grows without removing commons from the pool entirely.
-- baseCost: coins per unit before BaitShop.baitDiscountPct is applied.
-- maxStack: maximum units of this bait a player may hold at once.

export type BaitDef = {
	id: string,
	displayName: string,
	tier: string,         -- display label: "Common" | "Uncommon" | "Rare" | "Epic"
	rarityBoost: number,  -- multiplier on non-Common rarity weights (1.0 = no boost)
	baseCost: number,     -- coins per unit, pre-discount
	maxStack: number,
}

local BaitCatalog: {
	baits: {BaitDef},
	-- O(1) lookup used by BaitService and FishingService; populated below.
	byId: {[string]: BaitDef},
} = {
	baits = {
		{
			id          = "worm",
			displayName = "Worm",
			tier        = "Common",
			rarityBoost = 1.0,
			baseCost    = 5,
			maxStack    = 99,
		},
		{
			id          = "shrimp",
			displayName = "Shrimp",
			tier        = "Uncommon",
			rarityBoost = 1.5,
			baseCost    = 15,
			maxStack    = 75,
		},
		{
			id          = "squid",
			displayName = "Squid",
			tier        = "Rare",
			rarityBoost = 2.5,
			baseCost    = 40,
			maxStack    = 40,
		},
		{
			id          = "glowjig",
			displayName = "Glow Jig",
			tier        = "Epic",
			rarityBoost = 4.0,
			baseCost    = 100,
			maxStack    = 20,
		},
	},
	byId = {},
}

-- Build the id index once at load time.
for _, bait in ipairs(BaitCatalog.baits) do
	BaitCatalog.byId[bait.id] = bait
end

return BaitCatalog
