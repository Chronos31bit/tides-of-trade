--!strict
-- RodCatalog.lua
-- Ten named rod tiers, ascending, apex = Abyssal (tier 10). The early
-- progression (Driftwood → Bamboo → Ironwood → Coral) is unchanged; tiers
-- 5-9 are the mid/late rods and Abyssal sits at the top of the rack.
--
-- Stable string ids are forever (see CLAUDE.md) — every rod here keeps its
-- original id. The *numeric* tier mapping changed (Abyssal 5 → 10); that is
-- acceptable because the DataStore is locked at TidesProfile_v1 until launch
-- (Studio uses a _studio sandbox key) so there is no production data to
-- migrate, and rodTier is re-derived from equippedRodId the next time a rod
-- is equipped.
--
-- rank / rankColor : cosmetic rarity badge ("Common"…"Divine"). The UI
--   tints both the rank label and the rod name with rankColor so the rack
--   reads as a rarity ladder at a glance. Purely presentational — rank has
--   no gameplay effect; progression is gated by unlockLevel.
--
-- castWindowBonus : kept for schema stability but no longer used by
--   FishingService. Rods now affect rarity via rarityMultiplier instead.
--
-- rarityMultiplier : multiplier applied to all non-Common rarity weights
--   during rollFish(). Driftwood = 1.0 (no bonus); Abyssal = 7.0
--   (7× better odds at Uncommon–Divine fish).
--
-- catchWeightBonus : flat kg added to the resolved fish weight after the
--   catalog weight range is rolled. Applied before modifier weightMul.
--
-- color : Color3 used in the rod rack UI for the tier strip / glow tint.
--
-- unlockLevel is populated at load time from GameConfig.Rods.UnlockLevel —
-- the single source of truth for progression thresholds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

export type RodDef = {
	id: string,
	displayName: string,
	tier: number,              -- 1..10, sets data.rodTier on equip
	rank: string,              -- cosmetic rarity badge, no gameplay effect
	rankColor: Color3,         -- tint for rank label + rod name in the rack UI
	unlockLevel: number,       -- populated from GameConfig.Rods.UnlockLevel
	castWindowBonus: number,   -- unused post-rework; kept for schema stability
	rarityMultiplier: number,  -- multiplier on non-Common rarity weights in rollFish
	catchWeightBonus: number,  -- additive kg
	color: Color3,
}

-- Rarity ladder. Names are stable for UI/analytics; colors are cosmetic.
local RANK = {
	Common    = Color3.fromRGB(176, 182, 190),
	Uncommon  = Color3.fromRGB(120, 205, 135),
	Rare      = Color3.fromRGB( 95, 165, 240),
	Epic      = Color3.fromRGB(185, 120, 235),
	Legendary = Color3.fromRGB(245, 180,  75),
	Mythic    = Color3.fromRGB(240,  95, 140),
	Divine    = Color3.fromRGB(255, 225, 150),
}

local RodCatalog: {
	rods: {RodDef},
	byId: {[string]: RodDef},
} = {
	rods = {
		{
			id               = "driftwood",
			displayName      = "Driftwood Rod",
			tier             = 1,
			rank             = "Common",
			rankColor        = RANK.Common,
			unlockLevel      = 1,
			castWindowBonus  = 0.00,
			rarityMultiplier = 1.0,
			catchWeightBonus = 0.0,
			color            = Color3.fromRGB(160, 124, 88),
		},
		{
			id               = "bamboo",
			displayName      = "Bamboo Rod",
			tier             = 2,
			rank             = "Common",
			rankColor        = RANK.Common,
			unlockLevel      = 1,
			castWindowBonus  = 0.05,
			rarityMultiplier = 1.3,
			catchWeightBonus = 0.5,
			color            = Color3.fromRGB(120, 200, 130),
		},
		{
			id               = "ironwood",
			displayName      = "Ironwood Rod",
			tier             = 3,
			rank             = "Uncommon",
			rankColor        = RANK.Uncommon,
			unlockLevel      = 1,
			castWindowBonus  = 0.10,
			rarityMultiplier = 1.7,
			catchWeightBonus = 1.5,
			color            = Color3.fromRGB(160, 160, 200),
		},
		{
			id               = "coral",
			displayName      = "Coral Rod",
			tier             = 4,
			rank             = "Rare",
			rankColor        = RANK.Rare,
			unlockLevel      = 1,
			castWindowBonus  = 0.16,
			rarityMultiplier = 2.2,
			catchWeightBonus = 3.5,
			color            = Color3.fromRGB(220, 130, 200),
		},
		{
			id               = "tempest",
			displayName      = "Tempest Rod",
			tier             = 5,
			rank             = "Epic",
			rankColor        = RANK.Epic,
			unlockLevel      = 1,
			castWindowBonus  = 0.22,
			rarityMultiplier = 2.8,
			catchWeightBonus = 6.5,
			color            = Color3.fromRGB(120, 170, 230),
		},
		{
			id               = "leviathan",
			displayName      = "Leviathan Rod",
			tier             = 6,
			rank             = "Epic",
			rankColor        = RANK.Epic,
			unlockLevel      = 1,
			castWindowBonus  = 0.28,
			rarityMultiplier = 3.5,
			catchWeightBonus = 10.0,
			color            = Color3.fromRGB(70, 110, 165),
		},
		{
			id               = "aurora",
			displayName      = "Aurora Rod",
			tier             = 7,
			rank             = "Legendary",
			rankColor        = RANK.Legendary,
			unlockLevel      = 1,
			castWindowBonus  = 0.34,
			rarityMultiplier = 4.2,
			catchWeightBonus = 15.0,
			color            = Color3.fromRGB(150, 235, 210),
		},
		{
			id               = "celestial",
			displayName      = "Celestial Rod",
			tier             = 8,
			rank             = "Legendary",
			rankColor        = RANK.Legendary,
			unlockLevel      = 1,
			castWindowBonus  = 0.40,
			rarityMultiplier = 5.0,
			catchWeightBonus = 21.0,
			color            = Color3.fromRGB(210, 165, 250),
		},
		{
			id               = "eclipse",
			displayName      = "Eclipse Rod",
			tier             = 9,
			rank             = "Mythic",
			rankColor        = RANK.Mythic,
			unlockLevel      = 1,
			castWindowBonus  = 0.47,
			rarityMultiplier = 5.8,
			catchWeightBonus = 30.0,
			color            = Color3.fromRGB(120, 90, 160),
		},
		{
			id               = "abyssal",
			displayName      = "Abyssal Rod",
			tier             = 10,
			rank             = "Divine",
			rankColor        = RANK.Divine,
			unlockLevel      = 1,
			castWindowBonus  = 0.54,
			rarityMultiplier = 7.0,
			catchWeightBonus = 42.0,
			color            = Color3.fromRGB(45, 80, 130),
		},
	},
	byId = {},
}

-- Inject unlock thresholds from GameConfig and build O(1) id index.
for _, rod in ipairs(RodCatalog.rods) do
	rod.unlockLevel = GameConfig.Rods.UnlockLevel[rod.id] or 1
	RodCatalog.byId[rod.id] = rod
end

return RodCatalog
