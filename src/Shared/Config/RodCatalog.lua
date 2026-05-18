--!strict
-- RodCatalog.lua
-- Five named rod tiers: Driftwood → Bamboo → Ironwood → Coral → Abyssal.
-- Each rod maps to a numeric tier (1..5) which drives fish species access via
-- data.rodTier. The bonuses here apply on top of base fishing math.
--
-- castWindowBonus : additive fraction widening the validation green zone.
--   Example: 0.05 adds 5pp to the green zone width before the assist multiplier.
--   The display zone is unchanged — the player sees the same visual bar; the
--   server just accepts a slightly wider hit region.
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
	tier: number,             -- 1..5, sets data.rodTier on equip
	unlockXp: number,         -- populated from GameConfig.Rods.UnlockXp
	castWindowBonus: number,  -- additive fraction [0,1]
	catchWeightBonus: number, -- additive kg
	color: Color3,
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
			unlockXp         = 0,
			castWindowBonus  = 0.00,
			catchWeightBonus = 0.0,
			color            = Color3.fromRGB(160, 124, 88),
		},
		{
			id               = "bamboo",
			displayName      = "Bamboo Rod",
			tier             = 2,
			unlockXp         = 0,
			castWindowBonus  = 0.05,
			catchWeightBonus = 0.5,
			color            = Color3.fromRGB(120, 200, 130),
		},
		{
			id               = "ironwood",
			displayName      = "Ironwood Rod",
			tier             = 3,
			unlockXp         = 0,
			castWindowBonus  = 0.10,
			catchWeightBonus = 1.5,
			color            = Color3.fromRGB(160, 160, 200),
		},
		{
			id               = "coral",
			displayName      = "Coral Rod",
			tier             = 4,
			unlockXp         = 0,
			castWindowBonus  = 0.16,
			catchWeightBonus = 3.5,
			color            = Color3.fromRGB(220, 130, 200),
		},
		{
			id               = "abyssal",
			displayName      = "Abyssal Rod",
			tier             = 5,
			unlockXp         = 0,
			castWindowBonus  = 0.24,
			catchWeightBonus = 7.0,
			color            = Color3.fromRGB(120, 170, 230),
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
