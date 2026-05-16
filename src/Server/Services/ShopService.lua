--!strict
-- ShopService.lua
-- Handles purchases that don't fit into the global market: rod tier
-- upgrades (sold at the dock) and bait (sold at the BaitShop building).
-- All transactions are server-authoritative — client just RPCs in.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ShopService = Knit.CreateService({
	Name = "ShopService",
	Client = {
		-- Fired when a player's active bait buff changes (purchased, used up,
		-- or expired). Client uses this for HUD timer display.
		BuffChanged = Knit.CreateSignal(),
	},
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
-- BAIT CATALOG
-- Each bait grants a temporary buff that boosts non-Common rarity
-- weights when fish are rolled. Duration in seconds.
-- ====================================================================
local BAITS = {
	worm = {
		name = "Worm",
		cost = 25,
		description = "+50% boost to Uncommon/Rare/Mythic chance for 3 min.",
		duration = 180,
		rareWeightMultiplier = 1.5,
	},
	shrimp = {
		name = "Shrimp",
		cost = 120,
		description = "+150% boost for 5 min.",
		duration = 300,
		rareWeightMultiplier = 2.5,
	},
	moonlure = {
		name = "Moon Lure",
		cost = 600,
		description = "+300% boost for 8 min. Premium catches become realistic.",
		duration = 480,
		rareWeightMultiplier = 4.0,
	},
}

-- ====================================================================
-- CLIENT API — catalogs
-- ====================================================================
function ShopService.Client:GetRodCatalog(_player: Player): {[number]: any}
	return RODS
end

function ShopService.Client:GetBaitCatalog(_player: Player): {[string]: any}
	return BAITS
end

function ShopService.Client:GetActiveBuff(player: Player): any?
	local data = Knit.GetService("PlayerDataService"):GetProfile(player)
	if not data then return nil end
	-- Expire on read so the client never sees a stale buff.
	if data.activeBuff and os.time() >= data.activeBuff.expiresAt then
		data.activeBuff = nil
	end
	return data.activeBuff
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

-- ====================================================================
-- BUY BAIT
-- Spending coins activates the buff for `duration` seconds. If the
-- player has an existing buff, the new one replaces it (no stacking;
-- keeps balance simple).
-- ====================================================================
function ShopService.Client:BuyBait(player: Player, baitId: string): {ok: boolean, reason: string?, expiresAt: number?}
	local self = self.Server
	local bait = BAITS[baitId]
	if not bait then return { ok = false, reason = "no_such_bait" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	if not PlayerDataService:TrySpendCoins(player, bait.cost) then
		return { ok = false, reason = "not_enough_coins" }
	end
	local now = os.time()
	data.activeBuff = {
		kind = baitId,
		expiresAt = now + bait.duration,
		rareWeightMultiplier = bait.rareWeightMultiplier,
	}
	self.Client.BuffChanged:Fire(player, data.activeBuff)
	return { ok = true, expiresAt = data.activeBuff.expiresAt }
end

-- ====================================================================
-- LIFECYCLE — periodic buff expiry sweep so clients get a clean signal
-- when their bait runs out, not just a "next read returns nil".
-- ====================================================================
function ShopService:KnitStart()
	task.spawn(function()
		while true do
			task.wait(10)
			local PlayerDataService = Knit.GetService("PlayerDataService")
			local now = os.time()
			for _, player in ipairs(Players:GetPlayers()) do
				local data = PlayerDataService:GetProfile(player)
				if data and data.activeBuff and now >= data.activeBuff.expiresAt then
					data.activeBuff = nil
					self.Client.BuffChanged:Fire(player, nil)
				end
			end
		end
	end)
end

return ShopService
