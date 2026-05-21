--!strict
-- EconomyUtil.lua
-- Shared sell-price helpers for fish and preserved goods.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local FishCatalog  = require(ReplicatedStorage.Shared.Config.FishCatalog)

local PRESERVED_PREFIX = "preserved_"
local DOCK_NPC_FRACTION = 0.6

local fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do
	fishById[f.id] = f
end

local EconomyUtil = {}

function EconomyUtil.fishWeightMultiplier(fish: any, weightKg: number): number
	local minW = fish.weightRange[1]
	local maxW = fish.weightRange[2]
	local frac = (weightKg - minW) / math.max(maxW - minW, 0.0001)
	return 1 + math.clamp(frac, 0, 1) * 0.5
end

function EconomyUtil.parsePreservedSpeciesId(goodId: string): string?
	if string.sub(goodId, 1, #PRESERVED_PREFIX) ~= PRESERVED_PREFIX then
		return nil
	end
	return string.sub(goodId, #PRESERVED_PREFIX + 1)
end

function EconomyUtil.isPreservedGoodId(goodId: string): boolean
	return EconomyUtil.parsePreservedSpeciesId(goodId) ~= nil
end

-- Fair preserved value before dock NPC discount (base * weight * 3x).
function EconomyUtil.getPreservedGoodFairValue(speciesId: string, weightKg: number?): number
	local f = fishById[speciesId]
	if not f then return 0 end
	local w = weightKg or f.weightRange[1]
	local mul = EconomyUtil.fishWeightMultiplier(f, w)
	return math.floor(f.basePrice * mul * GameConfig.Economy.SmokehouseMultiplier + 0.5)
end

-- Dock quick-sell payout for a preserved good (60% of fair value).
function EconomyUtil.getPreservedGoodQuickSellPayout(speciesId: string, weightKg: number?): number
	return math.floor(EconomyUtil.getPreservedGoodFairValue(speciesId, weightKg) * DOCK_NPC_FRACTION + 0.5)
end

return EconomyUtil
