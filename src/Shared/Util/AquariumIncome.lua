--!strict
-- AquariumIncome.lua — passive aquarium coin/xp per harbor income tick (server + UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local AquariumIncome = {}

local _fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do
	_fishById[f.id] = f
end

local _modById: {[string]: any} = {}
for _, m in ipairs(GameConfig.FishModifiers) do
	_modById[m.id] = m
end

local function weightMultiplier(fish: any, weightKg: number): number
	local minW = fish.weightRange[1]
	local maxW = fish.weightRange[2]
	local span = math.max(maxW - minW, 0.0001)
	local frac = math.clamp((weightKg - minW) / span, 0, 1)
	return 1 + frac
end

local function modifierSellMul(modifiers: {string}?): number
	local mul = 1
	for _, id in ipairs(modifiers or {}) do
		local mod = _modById[id]
		if mod and mod.sellPriceMul then
			mul *= mod.sellPriceMul
		end
	end
	return mul
end

local function modifierXpMul(modifiers: {string}?): number
	local mul = 1
	for _, id in ipairs(modifiers or {}) do
		local mod = _modById[id]
		if mod and mod.xpMul then
			mul *= mod.xpMul
		end
	end
	return mul
end

function AquariumIncome.coinsPerTick(item: any): number
	local f = _fishById[item.speciesId]
	if not f then
		return 0
	end
	local r = GameConfig.Aquarium.RarityIncome[f.rarity]
	if not r then
		return 0
	end
	local mul = weightMultiplier(f, item.weightKg or f.weightRange[1])
	local sellMul = modifierSellMul(item.modifiers)
	return math.floor(r.coins * mul * sellMul + 0.5)
end

function AquariumIncome.xpPerTick(item: any): number
	local f = _fishById[item.speciesId]
	if not f then
		return 0
	end
	local r = GameConfig.Aquarium.RarityIncome[f.rarity]
	if not r then
		return 0
	end
	local mul = weightMultiplier(f, item.weightKg or f.weightRange[1])
	local xpMul = modifierXpMul(item.modifiers)
	return math.floor(r.xp * mul * xpMul + 0.5)
end

function AquariumIncome.coinsPerHour(item: any): number
	local tickSec = GameConfig.Harbor.IncomeTickSeconds
	if tickSec <= 0 then
		return 0
	end
	return math.floor(AquariumIncome.coinsPerTick(item) * (3600 / tickSec) + 0.5)
end

-- Steady-state coins per second (weight + modifiers already in coinsPerTick).
function AquariumIncome.coinsPerSecond(item: any): number
	local tickSec = GameConfig.Harbor.IncomeTickSeconds
	if tickSec <= 0 then
		return 0
	end
	return AquariumIncome.coinsPerTick(item) / tickSec
end

return AquariumIncome
