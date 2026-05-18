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
--   no gameplay effect; progression is gated by unlockXp.
--
-- castWindowBonus : additive fraction widening the validation green zone.
--   Example: 0.05 adds 5pp to the green zone width before the assist
--   multiplier. The display zone is unchanged — the player sees the same
--   visual bar; the server just accepts a slightly wider hit region.
--
-- catchWeightBonus : flat kg added to the resolved fish weight after the
--   catalog weight range is rolled. Applied before modifier weightMul.
--
-- color : Color3 used in the rod rack UI for the tier strip / glow tint.
--
-- unlockXp is populated at load time from GameConfig.Rods.UnlockXp — the
-- single source of truth for progression thresholds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

export type RodDef = {
	id: string,
	displayName: string,
	tier: number,             -- 1..10, sets data.rodTier on equip
	rank: string,             -- cosmetic rarity badge, no gameplay effect
	rankColor: Color3,        -- tint for rank label + rod name in the rack UI
	unlockXp: number,         -- populated from GameConfig.Rods.UnlockXp
	castWindowBonus: number,  -- additive fraction [0,1]
	catchWeightBonus: number, -- additive kg
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
			unlockXp         = 0,
			castWindowBonus  = 0.00,
			catchWeightBonus = 0.0,
			color            = Color3.fromRGB(160, 124, 88),
		},
		{
			id               = "bamboo",
			displayName      = "Bamboo Rod",
			tier             = 2,
			rank             = "Common",
			rankColor        = RANK.Common,
			unlockXp         = 0,
			castWindowBonus  = 0.05,
			catchWeightBonus = 0.5,
			color            = Color3.fromRGB(120, 200, 130),
		},
		{
			id               = "ironwood",
			displayName      = "Ironwood Rod",
			tier             = 3,
			rank             = "Uncommon",
			rankColor        = RANK.Uncommon,
			unlockXp         = 0,
			castWindowBonus  = 0.10,
			catchWeightBonus = 1.5,
			color            = Color3.fromRGB(160, 160, 200),
		},
		{
			id               = "coral",
			displayName      = "Coral Rod",
			tier             = 4,
			rank             = "Rare",
			rankColor        = RANK.Rare,
			unlockXp         = 0,
			castWindowBonus  = 0.16,
			catchWeightBonus = 3.5,
			color            = Color3.fromRGB(220, 130, 200),
		},
		{
			id               = "tempest",
			displayName      = "Tempest Rod",
			tier             = 5,
			rank             = "Epic",
			rankColor        = RANK.Epic,
			unlockXp         = 0,
			castWindowBonus  = 0.22,
			catchWeightBonus = 6.5,
			color            = Color3.fromRGB(120, 170, 230),
		},
		{
			id               = "leviathan",
			displayName      = "Leviathan Rod",
			tier             = 6,
			rank             = "Epic",
			rankColor        = RANK.Epic,
			unlockXp         = 0,
			castWindowBonus  = 0.28,
			catchWeightBonus = 10.0,
			color            = Color3.fromRGB(70, 110, 165),
		},
		{
			id               = "aurora",
			displayName      = "Aurora Rod",
			tier             = 7,
			rank             = "Legendary",
			rankColor        = RANK.Legendary,
			unlockXp         = 0,
			castWindowBonus  = 0.34,
			catchWeightBonus = 15.0,
			color            = Color3.fromRGB(150, 235, 210),
		},
		{
			id               = "celestial",
			displayName      = "Celestial Rod",
			tier             = 8,
			rank             = "Legendary",
			rankColor        = RANK.Legendary,
			unlockXp         = 0,
			castWindowBonus  = 0.40,
			catchWeightBonus = 21.0,
			color            = Color3.fromRGB(210, 165, 250),
		},
		{
			id               = "eclipse",
			displayName      = "Eclipse Rod",
			tier             = 9,
			rank             = "Mythic",
			rankColor        = RANK.Mythic,
			unlockXp         = 0,
			castWindowBonus  = 0.47,
			catchWeightBonus = 30.0,
			color            = Color3.fromRGB(120, 90, 160),
		},
		{
			id               = "abyssal",
			displayName      = "Abyssal Rod",
			tier             = 10,
			rank             = "Divine",
			rankColor        = RANK.Divine,
			unlockXp         = 0,
			castWindowBonus  = 0.54,
			catchWeightBonus = 42.0,
			color            = Color3.fromRGB(45, 80, 130),
		},
	},
	byId = {},
}

-- Inject unlock thresholds from GameConfig and build O(1) id index.
for _, rod in ipairs(RodCatalog.rods) do
	rod.unlockXp = GameConfig.Rods.UnlockXp[rod.id] or 0
	RodCatalog.byId[rod.id] = rod
end

return RodCatalog
