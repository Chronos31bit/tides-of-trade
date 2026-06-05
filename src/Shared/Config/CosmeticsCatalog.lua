--!strict
-- CosmeticsCatalog.lua
-- Stable cosmetic definitions. Each cosmetic has a string id that is FOREVER
-- once shipped (CLAUDE.md stable-ID rule). Add new entries; never rename or
-- remove existing ones.
--
-- Slots: hat, coat, boots. Each slot can hold at most one cosmetic at a time.
-- Sources: "streak" (login streak reward), "shop" (Robux purchase),
--          "event" (time-limited event reward).

export type CosmeticsSlot = "hat" | "coat" | "boots"
export type CosmeticsSource = "streak" | "shop" | "event"

export type CosmeticDef = {
	id: string,
	slot: CosmeticsSlot,
	displayName: string,
	description: string,
	source: CosmeticsSource,
	-- Optional asset path for the cosmetic model in ReplicatedStorage.
	-- Falls back to catalog id when nil.
	assetPath: string?,
}

local CosmeticsCatalog = {
	byId = {} :: {[string]: CosmeticDef},
	cosmetics = {} :: {CosmeticDef},
}

-- ====================================================================
-- HELPERS
-- ====================================================================

local function register(def: CosmeticDef): CosmeticDef
	CosmeticsCatalog.byId[def.id] = def
	table.insert(CosmeticsCatalog.cosmetics, def)
	return def
end

-- ====================================================================
-- STREAK REWARDS (days 14, 21, 28)
-- ====================================================================
-- Login streak cosmetic rewards. Each reward is earned at the listed day of a
-- continuous login streak. These replace the placeholder Good items in
-- GameConfig.LoginStreakRewards once CosmeticService is wired.

register({
	id = "cosmetic_streak_14",
	slot = "hat",
	displayName = "Sailor's Cap",
	description = "A well-worn sailor's cap earned by two weeks of daily visits to the harbor.",
	source = "streak",
	assetPath = nil, -- TODO: upload model to ReplicatedStorage.Assets.Cosmetics.SailorsCap
})

register({
	id = "cosmetic_streak_21",
	slot = "coat",
	displayName = "Harbormaster's Vest",
	description = "A sturdy vest awarded after three weeks of faithful harbor upkeep.",
	source = "streak",
	assetPath = nil, -- TODO: upload model to ReplicatedStorage.Assets.Cosmetics.HarbormastersVest
})

register({
	id = "cosmetic_streak_28",
	slot = "boots",
	displayName = "Tide-Worn Boots",
	description = "Waterproof boots earned by a full month of daily tides.",
	source = "streak",
	assetPath = nil, -- TODO: upload model to ReplicatedStorage.Assets.Cosmetics.TideWornBoots
})

-- ====================================================================
-- SEASON-PASS REWARDS (free track, Season 1)
-- ====================================================================
-- Granted by SeasonPassService:ClaimTier at milestone tiers (see
-- GameConfig.SeasonPass.FreeRewards: tier 10 hat, tier 20 coat). Earned by
-- everyday play — no purchase, no FOMO (rewards repeat across seasons).

register({
	id = "cosmetic_season1_hat",
	slot = "hat",
	displayName = "Coral Crown",
	description = "A coral-tipped cap awarded at Season 1, Tier 10.",
	source = "event",
	assetPath = nil, -- TODO: upload model to ReplicatedStorage.Assets.Cosmetics.CoralCrown
})

register({
	id = "cosmetic_season1_coat",
	slot = "coat",
	displayName = "Captain's Coat",
	description = "A weathered captain's coat awarded at Season 1, Tier 20.",
	source = "event",
	assetPath = nil, -- TODO: upload model to ReplicatedStorage.Assets.Cosmetics.CaptainsCoat
})

return CosmeticsCatalog
