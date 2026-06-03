--!strict
-- GoodsCatalog.lua
-- Non-preserved goods definition catalog. Each good has a stable id (never
-- rename once shipped), display name, base quick-sell price, and stackability.
-- Preserved goods (fish) are priced by EconomyUtil.getPreservedGoodQuickSellPayout.
--
-- Pattern: CosmeticsCatalog (byId map + goods array).

export type GoodDef = {
	id: string,
	displayName: string,
	basePrice: number,
	stackable: boolean,
	description: string?,
}

local GoodsCatalog = {
	byId = {} :: {[string]: GoodDef},
	goods = {} :: {GoodDef},
}

-- Register a good in both the id-lookup map and the ordered array.
local function register(def: GoodDef)
	GoodsCatalog.byId[def.id] = def
	table.insert(GoodsCatalog.goods, def)
end

-- ====================================================================
-- GOODS CATALOG — add new goods here
-- ====================================================================

register({
	id = "rare_lure",
	displayName = "Rare Lure",
	basePrice = 50,
	stackable = false,
	description = "Attracts rarer fish for one cast.",
})

-- ====================================================================

return GoodsCatalog
