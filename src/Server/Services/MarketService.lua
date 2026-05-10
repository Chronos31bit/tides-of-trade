--!strict
-- MarketService.lua
-- Cross-server global market. Every Roblox server in the experience writes to
-- the same DataStore (a single shared listing index) and uses MessagingService
-- for near-real-time invalidation across servers. The DataStore is the source
-- of truth; MessagingService just nudges other servers to re-fetch.
--
-- Why a single shared key for the listing INDEX:
--   - Browsing the market needs an ordered, paginated list. With per-listing
--     keys you'd need OrderedDataStore (one axis only) or scan all keys
--     (impossible). A single index list under a known key is simple and fits
--     the 4MB DataStore value cap for our scale (10 listings/player * a few
--     hundred concurrent players).
--   - For larger scale you'd shard the index by rarity or page. Out of scope
--     for v1.

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types        = require(ReplicatedStorage.Shared.Types)
local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)
local FishCatalog  = require(ReplicatedStorage.Shared.Config.FishCatalog)

local MARKET_INDEX_KEY = "market_index"  -- single key under MarketStore that holds the list
local DEMAND_KEY = "current_demand"

local MarketService = Knit.CreateService({
	Name = "MarketService",
	Client = {
		ListingsUpdated = Knit.CreateSignal(),  -- (listings) — periodic broadcast
		DemandRotated   = Knit.CreateSignal(),  -- (speciesId, multiplier)
	},

	-- internal
	_marketStore = nil :: any,
	_demandStore = nil :: any,
	_cache = nil :: any,        -- last known listing list (refreshed on Messaging or timer)
	_cacheStaleAt = 0,
	_listLimiter = nil :: any,
	_demandSpike = { speciesId = nil, multiplier = 1.0, expiresAt = 0 },
})

-- ====================================================================
-- DEMAND SPIKE — rotate which species pays premium each UTC day.
-- The first server to notice the day rolled wins the right to pick. We use
-- DataStore UpdateAsync as a CAS lock: only one server's update will land
-- with the new day.
-- ====================================================================
local function rollDemandSpecies(): string
	local pool = {}
	for _, f in ipairs(FishCatalog.fish) do
		-- Don't put Mythic on demand spike — would trivialize the rarest tier.
		if f.rarity ~= "Mythic" then
			table.insert(pool, f.id)
		end
	end
	return pool[math.random(1, #pool)]
end

function MarketService:_refreshDemand()
	local TimeUtil = require(ReplicatedStorage.Shared.Util.TimeUtil)
	local today = TimeUtil.currentUTCDay()

	local result = self._demandStore:UpdateAsync(DEMAND_KEY, function(old)
		if old and old.day == today then
			return nil -- no update needed; another server already set today
		end
		return {
			day = today,
			speciesId = rollDemandSpecies(),
			multiplier = GameConfig.Economy.DemandSpikeMultiplier,
			rolledAt = os.time(),
		}
	end)

	-- Whether we wrote it or another server did, fetch the canonical value.
	local current = self._demandStore:GetAsync(DEMAND_KEY)
	if current then
		self._demandSpike = {
			speciesId = current.speciesId,
			multiplier = current.multiplier,
			expiresAt = os.time() + TimeUtil.secondsUntilUTCMidnight(),
		}
		-- Notify all players on this server.
		for _, player in ipairs(Players:GetPlayers()) do
			self.Client.DemandRotated:Fire(player, current.speciesId, current.multiplier)
		end
		-- Tell other servers in case they haven't refreshed yet.
		pcall(function()
			MessagingService:PublishAsync(GameConfig.Topics.DemandRotated, current)
		end)
	end
end

function MarketService:GetDemandMultiplier(speciesId: string): number
	if self._demandSpike.speciesId == speciesId and os.time() < self._demandSpike.expiresAt then
		return self._demandSpike.multiplier
	end
	return 1.0
end

-- ====================================================================
-- LISTING CRUD — DataStore is source of truth. We use UpdateAsync so
-- concurrent listings/buys from different servers don't clobber each other.
-- ====================================================================

-- Loads the listing array from DataStore. Returns {} on miss.
function MarketService:_readListings(): {Types.MarketListing}
	local ok, value = pcall(function()
		return self._marketStore:GetAsync(MARKET_INDEX_KEY)
	end)
	if not ok or not value then return {} end
	return value :: {Types.MarketListing}
end

-- Sweep expired listings off the index. Cheap to do whenever we already have
-- the array open inside an UpdateAsync callback.
local function pruneExpired(listings: {Types.MarketListing}): {Types.MarketListing}
	local now = os.time()
	local kept = {}
	for _, l in ipairs(listings) do
		if l.expiresAt > now then
			table.insert(kept, l)
		end
	end
	return kept
end

function MarketService:_publishCacheRefresh()
	-- Tell other servers to invalidate their cache. Body is just a heartbeat.
	pcall(function()
		MessagingService:PublishAsync(GameConfig.Topics.MarketListed, { ts = os.time() })
	end)
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function MarketService:KnitInit()
	self._marketStore = DataStoreService:GetDataStore(GameConfig.DataStores.MarketStore)
	self._demandStore = DataStoreService:GetDataStore(GameConfig.DataStores.DemandStore)
	self._listLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxListingsPerMinute, 60)
	self._cache = {}
end

function MarketService:KnitStart()
	-- Subscribe to cross-server events. A Listed/Sold/Canceled message just
	-- invalidates our cache — we don't trust the message body.
	local function invalidate()
		self._cacheStaleAt = 0
	end
	pcall(function() MessagingService:SubscribeAsync(GameConfig.Topics.MarketListed, invalidate) end)
	pcall(function() MessagingService:SubscribeAsync(GameConfig.Topics.MarketSold, invalidate) end)
	pcall(function() MessagingService:SubscribeAsync(GameConfig.Topics.MarketCanceled, invalidate) end)
	pcall(function()
		MessagingService:SubscribeAsync(GameConfig.Topics.DemandRotated, function(message)
			local data = message.Data
			if data and data.speciesId then
				local TimeUtil = require(ReplicatedStorage.Shared.Util.TimeUtil)
				self._demandSpike = {
					speciesId = data.speciesId,
					multiplier = data.multiplier,
					expiresAt = os.time() + TimeUtil.secondsUntilUTCMidnight(),
				}
				for _, player in ipairs(Players:GetPlayers()) do
					self.Client.DemandRotated:Fire(player, data.speciesId, data.multiplier)
				end
			end
		end)
	end)

	-- Player leave: clean up rate limiter.
	Players.PlayerRemoving:Connect(function(player)
		self._listLimiter:reset(player)
	end)

	-- Periodic refresh: pull listings every 30s so even without messaging we
	-- eventually converge. Also re-rolls demand at UTC midnight.
	task.spawn(function()
		while true do
			local listings = self:_readListings()
			self._cache = listings
			self._cacheStaleAt = os.time() + 30
			-- Broadcast to clients that subscribed.
			for _, player in ipairs(Players:GetPlayers()) do
				self.Client.ListingsUpdated:Fire(player, listings)
			end
			task.wait(30)
		end
	end)
	task.spawn(function()
		-- Run an initial demand refresh, then re-check just past midnight UTC.
		self:_refreshDemand()
		while true do
			local TimeUtil = require(ReplicatedStorage.Shared.Util.TimeUtil)
			local secs = TimeUtil.secondsUntilUTCMidnight()
			-- +5s slack so we're firmly into the new UTC day.
			task.wait(secs + 5)
			self:_refreshDemand()
		end
	end)
end

-- ====================================================================
-- CLIENT API
-- ====================================================================

function MarketService.Client:Browse(_player: Player): {Types.MarketListing}
	-- Return the cached snapshot. Server's periodic refresh keeps this fresh.
	return self.Server._cache or {}
end

function MarketService.Client:GetDemand(_player: Player): {speciesId: string?, multiplier: number, expiresAt: number}
	return self.Server._demandSpike
end

-- List an item. Server validates ownership, prices, and active-listing cap.
function MarketService.Client:Create(player: Player, itemUid: string, price: number): {ok: boolean, reason: string?, listing: any?}
	local self = self.Server
	if not self._listLimiter:check(player) then return { ok = false, reason = "rate_limit" } end

	if typeof(price) ~= "number" or price ~= price then
		return { ok = false, reason = "bad_price" }
	end
	price = math.floor(price)
	if price < GameConfig.Economy.MinListingPrice or price > GameConfig.Economy.MaxListingPrice then
		return { ok = false, reason = "price_out_of_range" }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local item = PlayerDataService:FindItemByUid(player, itemUid)
	if not item then return { ok = false, reason = "not_owned" } end

	-- Active listings cap: count this player's existing listings in cache + extras
	-- granted by their MarketStall tier.
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end
	local extra = 0
	local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
	for _, b in ipairs(data.buildings) do
		local def = BuildingCatalog[b.kind]
		if def and def.tiers[b.tier].marketStallExtraListings then
			extra += def.tiers[b.tier].marketStallExtraListings
		end
	end
	local cap = GameConfig.Economy.MaxActiveListingsPerPlayer + extra

	local listing: Types.MarketListing
	-- We have to remove the item from inventory atomically with adding the
	-- listing or an exploiter could double-spend. Sequence here is:
	--   1. Read+update DataStore (CAS) to add the listing.
	--   2. Only on success, remove the item from the player's profile.
	-- If the DataStore write fails the player keeps the item.
	local addedListing
	local ok, err = pcall(function()
		self._marketStore:UpdateAsync(MARKET_INDEX_KEY, function(old)
			old = old or {}
			old = pruneExpired(old)
			-- Re-check cap inside the transaction (caps may have updated cross-server).
			local mine = 0
			for _, l in ipairs(old) do
				if l.sellerId == player.UserId then mine += 1 end
			end
			if mine >= cap then
				addedListing = nil
				return nil  -- abort write
			end
			local newListing: Types.MarketListing = {
				listingId = UidUtil.new("lst"),
				sellerId = player.UserId,
				sellerName = player.Name,
				itemKind = item.kind,
				speciesId = (item :: any).speciesId,
				goodId = (item :: any).goodId,
				weightKg = (item :: any).weightKg,
				count = (item :: any).count or 1,
				price = price,
				listedAt = os.time(),
				expiresAt = os.time() + GameConfig.Economy.ListingTTLSeconds,
			}
			table.insert(old, newListing)
			addedListing = newListing
			return old
		end)
	end)

	if not ok then
		warn("[MarketService] DataStore Create failed:", err)
		return { ok = false, reason = "datastore_error" }
	end
	if not addedListing then
		return { ok = false, reason = "listing_cap_reached" }
	end

	-- Now safe to remove from inventory.
	PlayerDataService:RemoveItemByUid(player, itemUid)

	-- Best-effort cross-server invalidation.
	self:_publishCacheRefresh()
	-- Update local cache immediately so the seller sees it before the periodic
	-- refresh ticks.
	if self._cache then
		table.insert(self._cache, addedListing)
		self.Client.ListingsUpdated:Fire(player, self._cache)
	end

	return { ok = true, listing = addedListing }
end

-- Buy a listing. Server validates the listing still exists, charges the buyer,
-- pays the seller (minus fee), and removes the listing.
function MarketService.Client:Buy(player: Player, listingId: string): {ok: boolean, reason: string?}
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	local boughtListing
	local ok, err = pcall(function()
		self._marketStore:UpdateAsync(MARKET_INDEX_KEY, function(old)
			old = old or {}
			old = pruneExpired(old)
			for i, l in ipairs(old) do
				if l.listingId == listingId then
					if l.sellerId == player.UserId then
						return nil -- can't buy your own listing
					end
					if data.coins < l.price then
						return nil -- not enough coins
					end
					boughtListing = l
					table.remove(old, i)
					return old
				end
			end
			return nil
		end)
	end)

	if not ok then
		warn("[MarketService] DataStore Buy failed:", err)
		return { ok = false, reason = "datastore_error" }
	end
	if not boughtListing then
		return { ok = false, reason = "listing_unavailable" }
	end

	-- Apply demand spike multiplier to the *seller payout* only (buyer pays
	-- the listed price; the spike rewards selling rare items today).
	local demandMul = 1.0
	if boughtListing.speciesId then
		demandMul = self:GetDemandMultiplier(boughtListing.speciesId)
	end
	local fee = math.floor(boughtListing.price * GameConfig.Economy.MarketFeePct)
	local payoutBase = boughtListing.price - fee
	local payout = math.floor(payoutBase * demandMul)

	-- Charge buyer.
	if not PlayerDataService:TrySpendCoins(player, boughtListing.price) then
		-- Race: someone else's transaction sent our DataStore data through but
		-- the buyer's coins changed in the same window. Refund the listing —
		-- best we can do is re-list it so the seller doesn't lose their item.
		pcall(function()
			self._marketStore:UpdateAsync(MARKET_INDEX_KEY, function(old)
				old = old or {}
				table.insert(old, boughtListing)
				return old
			end)
		end)
		return { ok = false, reason = "not_enough_coins" }
	end

	-- Add the item to the buyer's inventory. Reconstruct from listing fields.
	local item: any
	if boughtListing.itemKind == "Fish" then
		item = {
			uid = UidUtil.new("fish"),
			kind = "Fish",
			speciesId = boughtListing.speciesId,
			weightKg = boughtListing.weightKg,
			caughtAt = os.time(),
		}
	else
		item = {
			uid = UidUtil.new("good"),
			kind = "Good",
			goodId = boughtListing.goodId,
			count = boughtListing.count,
		}
	end
	PlayerDataService:AddItem(player, item)

	-- Pay the seller. They might be online on this server or a different one;
	-- if they're online here we credit immediately, otherwise the next time
	-- they log in we settle via the offline payouts queue.
	-- For v1: only credit if online; otherwise drop the coin into a per-user
	-- DataStore queue.
	local seller = Players:GetPlayerByUserId(boughtListing.sellerId)
	if seller then
		PlayerDataService:AddCoins(seller, payout, "market_sale")
		local sellerData = PlayerDataService:GetProfile(seller)
		if sellerData then sellerData.stats.totalSold += 1 end
	else
		-- Offline payout: stash into a side DataStore. Simple per-user list of
		-- pending coin grants applied on next login.
		local pendingStore = DataStoreService:GetDataStore("TidesPendingPayouts_v1")
		pcall(function()
			pendingStore:UpdateAsync("u_" .. boughtListing.sellerId, function(old)
				old = old or { coins = 0 }
				old.coins += payout
				return old
			end)
		end)
	end

	-- Quest hook for the seller (only if online here).
	if seller then
		local QuestService = Knit.GetService("QuestService")
		QuestService:OnSoldAtMarket(seller, boughtListing.price)
	end

	-- Invalidate caches.
	self:_publishCacheRefresh()
	if self._cache then
		for i, l in ipairs(self._cache) do
			if l.listingId == listingId then
				table.remove(self._cache, i)
				break
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			self.Client.ListingsUpdated:Fire(p, self._cache)
		end
	end

	return { ok = true }
end

-- Cancel your own listing — get the item back, no fee.
function MarketService.Client:Cancel(player: Player, listingId: string): {ok: boolean, reason: string?}
	local self = self.Server
	local cancelledListing
	local ok = pcall(function()
		self._marketStore:UpdateAsync(MARKET_INDEX_KEY, function(old)
			old = old or {}
			for i, l in ipairs(old) do
				if l.listingId == listingId and l.sellerId == player.UserId then
					cancelledListing = l
					table.remove(old, i)
					return old
				end
			end
			return nil
		end)
	end)
	if not ok or not cancelledListing then
		return { ok = false, reason = "not_found" }
	end

	-- Return item to inventory.
	local item: any
	if cancelledListing.itemKind == "Fish" then
		item = {
			uid = UidUtil.new("fish"),
			kind = "Fish",
			speciesId = cancelledListing.speciesId,
			weightKg = cancelledListing.weightKg,
			caughtAt = os.time(),
		}
	else
		item = {
			uid = UidUtil.new("good"),
			kind = "Good",
			goodId = cancelledListing.goodId,
			count = cancelledListing.count,
		}
	end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddItem(player, item)

	self:_publishCacheRefresh()
	return { ok = true }
end

-- ====================================================================
-- QUICK SELL — sells a single inventory item to the dock NPC for the
-- species base price * weight multiplier. Pays out *less* than the global
-- market would, so listing remains the more rewarding path. Lets solo
-- players earn coins without waiting for buyers.
-- ====================================================================
function MarketService.Client:QuickSell(player: Player, itemUid: string): {ok: boolean, reason: string?, coinsEarned: number?}
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local item = PlayerDataService:FindItemByUid(player, itemUid)
	if not item then return { ok = false, reason = "not_owned" } end

	local payout = 0
	if item.kind == "Fish" then
		local f
		for _, candidate in ipairs(FishCatalog.fish) do
			if candidate.id == item.speciesId then f = candidate; break end
		end
		if not f then return { ok = false, reason = "unknown_species" } end
		local minW, maxW = f.weightRange[1], f.weightRange[2]
		local frac = (item.weightKg - minW) / math.max(maxW - minW, 0.0001)
		local mul = 1 + math.clamp(frac, 0, 1) * 0.5
		-- Dock NPC pays 60% of fair value — incentive to use the global market
		-- when you've got time to wait for buyers.
		payout = math.floor(f.basePrice * mul * 0.6)
	elseif item.kind == "Good" then
		-- Goods catalog isn't built yet; flat rate for now.
		payout = 30 * (item.count or 1)
	end

	if payout <= 0 then return { ok = false, reason = "no_value" } end

	PlayerDataService:RemoveItemByUid(player, itemUid)
	PlayerDataService:AddCoins(player, payout, "quick_sell")

	-- Quest hook: counts as a sale at market for daily quest progress.
	local QuestService = Knit.GetService("QuestService")
	QuestService:OnSoldAtMarket(player, payout)

	return { ok = true, coinsEarned = payout }
end

-- Server-callable: settle pending offline payouts on login.
function MarketService:SettlePendingPayouts(player: Player)
	local pendingStore = DataStoreService:GetDataStore("TidesPendingPayouts_v1")
	local ok, payload = pcall(function()
		return pendingStore:UpdateAsync("u_" .. player.UserId, function(old)
			if not old or old.coins == 0 then return nil end
			-- Wipe by returning empty.
			local payout = old.coins
			return { coins = 0, _settled = payout }
		end)
	end)
	if ok and payload and payload._settled and payload._settled > 0 then
		local PlayerDataService = Knit.GetService("PlayerDataService")
		PlayerDataService:AddCoins(player, payload._settled, "market_offline_payout")
	end
end

return MarketService
