--!strict
-- ShopService.lua
-- Handles rod tier upgrades (sold at the dock). All transactions are
-- server-authoritative — client just RPCs in.
-- Bait purchases moved to BaitService (baitStash + equippedBaitId path).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ShopService = Knit.CreateService({
	Name = "ShopService",
	Client = {},
})

-- ====================================================================
-- ROD CATALOG
-- Tier 1 is the starter; players spawn with it. Higher tiers cost more
-- and unlock deeper biomes via FishCatalog's rodMinTier filter.
-- ====================================================================
local RODS = {
	[1] = { name = "Driftwood Rod",  cost = 0,     description = "Starter rod. Common shoreline catches." },
	[2] = { name = "Bamboo Rod",     cost = 500,   description = "Reaches reef-tier fish (Lantern Squid, Speckled Perch)." },
	[3] = { name = "Hardwood Rod",   cost = 2500,  description = "Reels deep-water catches like Stormcoat Tuna." },
	[4] = { name = "Whalebone Rod",  cost = 12000, description = "Sturdy enough for Mythic-tier strikes." },
	[5] = { name = "Coralforged Rod",cost = 50000, description = "Legendary. Pulls anything that bites." },
}

-- ====================================================================
-- CLIENT API — catalogs
-- ====================================================================
function ShopService.Client:GetRodCatalog(_player: Player): {[number]: any}
	return RODS
end

-- ====================================================================
-- BUY ROD UPGRADE
-- ====================================================================
function ShopService.Client:BuyRodTier(player: Player, targetTier: number): {ok: boolean, reason: string?, newTier: number?}
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	if typeof(targetTier) ~= "number" then return { ok = false, reason = "bad_tier" } end
	targetTier = math.floor(targetTier)
	if not RODS[targetTier] then return { ok = false, reason = "no_such_rod" } end
	-- Must be the *next* tier — no skipping.
	if targetTier ~= data.rodTier + 1 then
		return { ok = false, reason = "must_upgrade_sequentially" }
	end

	local cost = RODS[targetTier].cost
	if not PlayerDataService:TrySpendCoins(player, cost) then
		return { ok = false, reason = "not_enough_coins" }
	end
	-- Routes through the single rodTier writer, which fires the dedicated
	-- RodTierChanged signal (replaces the old coarse ProfileLoaded cue).
	PlayerDataService:SetRodTier(player, targetTier)
	return { ok = true, newTier = targetTier }
end

return ShopService
