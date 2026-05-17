--!strict
-- BaitService.lua
-- Owns all server-authoritative bait operations:
--   BuyBait(player, baitId, qty)  — validated purchase, coin deduction, stash update
--   EquipBait(player, baitId?)    — set or clear the player's active bait
-- Internal API (called by FishingService, not the client):
--   GetEquippedRarityBoost(player) -> number   (1.0 if no bait)
--   ConsumeEquippedBait(player)                (call on successful cast hit)
--
-- Discount: if the player has a BaitShop building placed, its baitDiscountPct
-- (from BuildingCatalog) is applied as a fractional reduction to baseCost.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit             = require(ReplicatedStorage.Packages.Knit)
local GameConfig       = require(ReplicatedStorage.Shared.Config.GameConfig)
local BaitCatalog      = require(ReplicatedStorage.Shared.Config.BaitCatalog)
local BuildingCatalog  = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local RateLimiter      = require(ReplicatedStorage.Shared.Util.RateLimiter)

local BaitService = Knit.CreateService({
	Name = "BaitService",
	Client = {
		-- Fires to the owning player after any stash or equip change.
		-- Shape: (stash: {[string]: number}, equippedBaitId: string?)
		BaitStashChanged = Knit.CreateSignal(),
	},
	_buyLimiter = nil :: any,
})

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function BaitService:KnitInit()
	local BC = GameConfig.Bait
	self._buyLimiter = RateLimiter.new(BC.RateLimitMax, BC.RateLimitWindowSec)
end

function BaitService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		self._buyLimiter:reset(player)
	end)
end

-- ====================================================================
-- INTERNAL HELPERS
-- ====================================================================

local function getPlayerDataService()
	return Knit.GetService("PlayerDataService")
end

-- Returns the baitDiscountPct from the player's Dock building tier.
-- Every player has a Dock, so this is always defined (0 for tier 1).
function BaitService:_getDiscount(player: Player): number
	local data = getPlayerDataService():GetProfile(player)
	if not data then return 0 end
	for _, building in ipairs(data.buildings) do
		if building.kind == "Dock" then
			local def = BuildingCatalog.Dock
			local tierData = def and def.tiers[building.tier]
			if tierData and tierData.baitDiscountPct then
				return tierData.baitDiscountPct
			end
		end
	end
	return 0
end

-- Push the current stash snapshot to the owning client.
function BaitService:_notifyClient(player: Player)
	local data = getPlayerDataService():GetProfile(player)
	if not data then return end
	self.Client.BaitStashChanged:Fire(player, data.baitStash, data.equippedBaitId)
end

-- ====================================================================
-- PUBLIC SERVER-INTERNAL API (called by FishingService)
-- ====================================================================

-- Returns the rarityBoost multiplier for the player's equipped bait.
-- Returns 1.0 when no bait is equipped (no-op for the rarity roll).
function BaitService:GetEquippedRarityBoost(player: Player): number
	local data = getPlayerDataService():GetProfile(player)
	if not data or not data.equippedBaitId then return 1.0 end
	local def = BaitCatalog.byId[data.equippedBaitId]
	return def and def.rarityBoost or 1.0
end

-- Deduct 1 unit of the equipped bait. Clears equippedBaitId if the stack
-- hits zero. No-op when no bait is equipped. Called by FishingService
-- inside ClaimCast after a confirmed green-zone hit.
function BaitService:ConsumeEquippedBait(player: Player)
	local data = getPlayerDataService():GetProfile(player)
	if not data or not data.equippedBaitId then return end

	local baitId = data.equippedBaitId
	local count  = data.baitStash[baitId] or 0
	if count <= 1 then
		data.baitStash[baitId] = nil
		data.equippedBaitId    = nil
	else
		data.baitStash[baitId] = count - 1
	end
	self:_notifyClient(player)
end

-- ====================================================================
-- CLIENT-CALLABLE METHODS
-- ====================================================================

-- Purchase `qty` units of `baitId`.
-- Returns {ok = true} on success, or {ok = false, reason = "..."}.
function BaitService.Client:BuyBait(
	player:  Player,
	baitId:  string,
	qty:     number
): {ok: boolean, reason: string?}
	local self = self.Server

	if not self._buyLimiter:check(player) then
		return { ok = false, reason = "rate_limited" }
	end

	local def = BaitCatalog.byId[baitId]
	if not def then
		return { ok = false, reason = "invalid_bait" }
	end

	qty = math.floor(qty or 1)
	if qty < 1 or qty > GameConfig.Bait.MaxBuyQty then
		return { ok = false, reason = "invalid_qty" }
	end

	local PDS  = getPlayerDataService()
	local data = PDS:GetProfile(player)
	if not data then return { ok = false, reason = "no_profile" } end

	-- Clamp to maxStack before charging coins.
	local current    = data.baitStash[baitId] or 0
	local affordable = math.min(current + qty, def.maxStack) - current
	if affordable <= 0 then
		return { ok = false, reason = "stack_full" }
	end

	local discount  = self:_getDiscount(player)
	local costEach  = math.max(1, math.ceil(def.baseCost * (1 - discount)))
	local totalCost = costEach * affordable

	if not PDS:TrySpendCoins(player, totalCost) then
		return { ok = false, reason = "not_enough_coins" }
	end

	data.baitStash[baitId] = current + affordable
	self:_notifyClient(player)
	return { ok = true }
end

-- Equip a bait (nil to unequip). The player must hold at least 1 unit.
function BaitService.Client:EquipBait(
	player: Player,
	baitId: string?
): {ok: boolean, reason: string?}
	local self = self.Server
	local PDS  = getPlayerDataService()
	local data = PDS:GetProfile(player)
	if not data then return { ok = false, reason = "no_profile" } end

	if baitId == nil then
		data.equippedBaitId = nil
		self:_notifyClient(player)
		return { ok = true }
	end

	if not BaitCatalog.byId[baitId] then
		return { ok = false, reason = "invalid_bait" }
	end
	if (data.baitStash[baitId] or 0) < 1 then
		return { ok = false, reason = "no_bait_in_stash" }
	end

	data.equippedBaitId = baitId
	self:_notifyClient(player)
	return { ok = true }
end

return BaitService
