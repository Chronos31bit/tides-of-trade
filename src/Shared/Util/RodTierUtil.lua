--!strict
-- RodTierUtil.lua
-- Single source of truth for "which fish does each rod tier unlock". Both the
-- server (boot logging + populating GameConfig.Fishing.RodTierUnlocks) and the
-- client (HUD rod-tier tooltip) derive their numbers from this one scan of
-- FishCatalog, so adding a fish to the catalog never requires touching UI or
-- config code.
--
-- Pure + cached: the catalog is static at runtime, so compute() runs once and
-- memoizes. No instance creation, no Knit, safe to require on both sides.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)

local RodTierUtil = {}

export type TierSpecies = {
	id: string,
	displayName: string,
	rarity: string,
}

export type TierGrouping = {
	-- Fish that become *newly* hookable exactly at this tier (rodMinTier == t).
	newAtTier: { [number]: { TierSpecies } },
	-- Count of fish hookable at or below this tier (rodMinTier <= t).
	countAtOrBelow: { [number]: number },
	-- Highest rodMinTier present in the catalog (>= 1).
	maxTier: number,
	-- Fish ids that had no explicit numeric rodMinTier (defaulted to tier 1).
	-- The catalog should eventually give every fish an explicit tier.
	missing: { string },
}

-- A fish with no explicit numeric rodMinTier is treated as tier 1 (the safest
-- default: it stays catchable for everyone) but flagged so the catalog can be
-- fixed.
local function tierOf(fish: any): (number, boolean)
	local raw = fish.rodMinTier
	if typeof(raw) == "number" and raw == raw and raw >= 1 then
		return math.floor(raw), false
	end
	return 1, true
end

local _cache: TierGrouping? = nil

function RodTierUtil.compute(): TierGrouping
	if _cache then
		return _cache
	end

	local newAtTier: { [number]: { TierSpecies } } = {}
	local missing: { string } = {}
	local maxTier = 1

	for _, fish in ipairs(FishCatalog.fish) do
		local tier, wasMissing = tierOf(fish)
		if wasMissing then
			table.insert(missing, fish.id)
		end
		if tier > maxTier then
			maxTier = tier
		end
		newAtTier[tier] = newAtTier[tier] or {}
		table.insert(newAtTier[tier], {
			id = fish.id,
			displayName = fish.displayName,
			rarity = fish.rarity,
		})
	end

	-- Make sure every tier slot 1..maxTier exists even if empty, and build the
	-- cumulative "at or below" counts.
	local countAtOrBelow: { [number]: number } = {}
	local running = 0
	for t = 1, maxTier do
		newAtTier[t] = newAtTier[t] or {}
		running += #newAtTier[t]
		countAtOrBelow[t] = running
	end

	_cache = {
		newAtTier = newAtTier,
		countAtOrBelow = countAtOrBelow,
		maxTier = maxTier,
		missing = missing,
	}
	return _cache
end

-- Up to `limit` example species that unlock at exactly `tier`, plus how many
-- additional species were not included. Used by the tooltip's next-tier
-- preview ("...and N more").
function RodTierUtil.examplesForTier(tier: number, limit: number): ({ TierSpecies }, number)
	local g = RodTierUtil.compute()
	local all = g.newAtTier[tier] or {}
	local shown: { TierSpecies } = {}
	for i = 1, math.min(limit, #all) do
		shown[i] = all[i]
	end
	local remaining = math.max(0, #all - #shown)
	return shown, remaining
end

-- Fills rodTierUnlocks[t].speciesUnlocked with the ids unlocked exactly at t.
-- Idempotent. Returns the grouping so the caller can log counts / warnings.
function RodTierUtil.populate(rodTierUnlocks: { [number]: { speciesUnlocked: { string } } }): TierGrouping
	local g = RodTierUtil.compute()
	for t = 1, g.maxTier do
		local slot = rodTierUnlocks[t]
		if slot then
			local ids: { string } = {}
			for _, s in ipairs(g.newAtTier[t]) do
				table.insert(ids, s.id)
			end
			slot.speciesUnlocked = ids
		end
	end
	return g
end

return RodTierUtil
