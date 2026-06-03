--!strict
-- ShopService.lua
-- Handles rod tier upgrades (sold at the dock). All transactions are
-- server-authoritative — client just RPCs in.
-- Bait purchases moved to BaitService (baitStash + equippedBaitId path).
-- Rod catalog moved to GameConfig.Rods.ShopTiers (CLAUDE.md: single source of truth).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit       = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local RODS = GameConfig.Rods.ShopTiers

local ShopService = Knit.CreateService({
	Name = "ShopService",
	Client = {},
})

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
