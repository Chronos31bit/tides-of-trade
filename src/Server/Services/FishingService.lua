--!strict
-- FishingService.lua
-- Server-authoritative fishing. Client never decides what was caught — it
-- only sends "I started a cast" and "I released the meter at marker=X". The
-- server picks the eligible fish pool, rolls the species, and grants the
-- catch only if the timing release is within the green zone.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types        = require(ReplicatedStorage.Shared.Types)
local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)

-- Load the fish catalog. Rojo syncs .json as ModuleScripts whose return value
-- is the parsed table.
local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)

type Fish = {
	id: string,
	displayName: string,
	rarity: string,
	biomes: {string},
	timeOfDay: {string},
	weather: {string},
	tide: string,
	basePrice: number,
	xp: number,
	weightRange: {number},
	rodMinTier: number,
	greenZoneSize: number,
}

local FishingService = Knit.CreateService({
	Name = "FishingService",
	Client = {
		-- Server -> client: "you have a bite, here's the timing window".
		-- We send the green zone center+size so the client can render it,
		-- but the *result* is computed server-side from the release marker.
		BiteStarted = Knit.CreateSignal(),
		-- Final result of a cast: { success, fish?, weightKg?, coinsEarned?, xpGained? }
		CastResolved = Knit.CreateSignal(),
	},

	-- internal state
	_pendingCasts = {},  -- [Player] -> {castId, fishId, greenCenter, greenSize, startedAt}
	_castLimiter = nil :: any,
	_lastCastAt = {},    -- [Player] -> os.clock() of last cast; for cooldown
})

-- ====================================================================
-- INDEX FISH BY ID for O(1) lookup
-- ====================================================================
local fishById: {[string]: Fish} = {}
for _, f in ipairs(FishCatalog.fish) do
	fishById[f.id] = f
end

-- ====================================================================
-- ELIGIBILITY: filter the catalog down to "what could plausibly bite right now"
-- ====================================================================
-- Inputs come from TideService, WeatherService, and the player's location-derived
-- biome. We pick a single fish from the eligible pool, weighted by rarity.
local function fishMatches(fish: Fish, ctx: {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number}): boolean
	if fish.rodMinTier > ctx.rodTier then return false end

	local function listContains(list: {string}, value: string): boolean
		for _, v in ipairs(list) do
			if v == value or v == "Any" then return true end
		end
		return false
	end

	if not listContains(fish.biomes, ctx.biome) then return false end
	if not listContains(fish.timeOfDay, ctx.timeOfDay) then return false end
	if not listContains(fish.weather, ctx.weather) then return false end
	if fish.tide ~= "Any" and fish.tide ~= ctx.tide then return false end
	return true
end

local function rollFish(ctx: {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number}): Fish?
	-- Step 1: build the eligible pool, bucketed by rarity.
	local buckets: {[string]: {Fish}} = { Common = {}, Uncommon = {}, Rare = {}, Mythic = {} }
	for _, f in ipairs(FishCatalog.fish) do
		if fishMatches(f, ctx) then
			table.insert(buckets[f.rarity], f)
		end
	end

	-- Step 2: pick a rarity using the weighted roll, but only from non-empty buckets.
	-- This way the player isn't wasting casts on a rarity tier with no eligible fish.
	local totalWeight = 0
	for rarity, weight in pairs(GameConfig.Fishing.RarityWeights) do
		if #buckets[rarity] > 0 then
			totalWeight += weight
		end
	end
	if totalWeight == 0 then
		return nil  -- nothing in the world bites here right now (e.g. wrong rod tier)
	end
	local roll = math.random() * totalWeight
	local chosenRarity: string? = nil
	for rarity, weight in pairs(GameConfig.Fishing.RarityWeights) do
		if #buckets[rarity] > 0 then
			roll -= weight
			if roll <= 0 then
				chosenRarity = rarity
				break
			end
		end
	end
	if not chosenRarity then return nil end

	-- Step 3: uniform pick within the chosen bucket.
	local pool = buckets[chosenRarity]
	return pool[math.random(1, #pool)]
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function FishingService:KnitInit()
	self._castLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxCastsPerMinute, 60)
end

function FishingService:KnitStart()
	-- Cleanup state on player leave so we don't leak across sessions.
	Players.PlayerRemoving:Connect(function(player)
		self._pendingCasts[player] = nil
		self._lastCastAt[player] = nil
		self._castLimiter:reset(player)
	end)
end

-- ====================================================================
-- CONTEXT — pulled from companion services. We require these inside
-- functions (lazily) to avoid circular requires at module load.
-- ====================================================================
function FishingService:_getContext(player: Player): {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number}?
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local TideService       = Knit.GetService("TideService")
	local WeatherService    = Knit.GetService("WeatherService")

	local data = PlayerDataService:GetProfile(player)
	if not data then return nil end

	-- Biome detection: simplest version reads a StringValue tagged on the
	-- Humanoid by the world (the world author tags water volumes as biome
	-- zones via CollectionService). Default to Shoreline if unknown.
	local biome = "Shoreline"
	local char = player.Character
	if char then
		local hint = char:FindFirstChild("CurrentBiome")
		if hint and hint:IsA("StringValue") then
			biome = hint.Value
		end
	end

	return {
		biome = biome,
		timeOfDay = WeatherService:GetTimeOfDay(),
		weather = WeatherService:GetWeather(),
		tide = TideService:GetTide(),
		rodTier = data.rodTier,
	}
end

-- ====================================================================
-- CLIENT API: cast + claim
-- ====================================================================

-- Client says "I started a cast". Server picks the fish secretly, sends
-- the timing window, and waits for the matching claim.
function FishingService.Client:StartCast(player: Player): {castId: string, greenCenter: number, greenSize: number, period: number}?
	local self = self.Server
	-- ---- rod-equipped gate ----
	-- Tools auto-reparent to the Character on equip; absence here means the
	-- rod is sitting in the Backpack (or doesn't exist). Either way: no cast.
	local char = player.Character
	if not char or not char:FindFirstChild("Fishing Rod") then
		return nil
	end
	-- ---- rate limiting & cooldown ----
	if not self._castLimiter:check(player) then return nil end
	local last = self._lastCastAt[player] or 0
	if os.clock() - last < GameConfig.Fishing.CastCooldownSeconds then return nil end
	self._lastCastAt[player] = os.clock()

	local ctx = self:_getContext(player)
	if not ctx then return nil end

	local fish = rollFish(ctx)
	if not fish then
		-- No fish biting. We still tell the client so the UI can show "no bite",
		-- but we don't reserve a pending cast slot.
		return nil
	end

	-- Generate a one-shot castId so the claim can't be replayed.
	local castId = UidUtil.new("cast")
	-- Green zone center is randomized in [greenSize/2, 1 - greenSize/2] so it
	-- never clips off the edges of the meter.
	local size = fish.greenZoneSize
	local center = size / 2 + math.random() * (1 - size)
	self._pendingCasts[player] = {
		castId = castId,
		fishId = fish.id,
		greenCenter = center,
		greenSize = size,
		startedAt = os.clock(),
	}

	-- Auto-expire the pending cast if the client never claims.
	task.delay(GameConfig.Fishing.CastTimeoutSeconds, function()
		local pending = self._pendingCasts[player]
		if pending and pending.castId == castId then
			self._pendingCasts[player] = nil
			-- Notify client of timeout so UI clears.
			self.Client.CastResolved:Fire(player, { success = false, reason = "timeout" })
		end
	end)

	return {
		castId = castId,
		greenCenter = center,
		greenSize = size,
		period = GameConfig.Fishing.CastMeterPeriod,
	}
end

-- Client says "I released the meter at marker=X (0..1)". Server validates
-- the timing and either grants the catch or fails it.
function FishingService.Client:ClaimCast(player: Player, castId: string, marker: number): {success: boolean, reason: string?, fish: any?, weightKg: number?, coinsEarned: number?, xpGained: number?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId then
		return { success = false, reason = "no_pending_cast" }
	end

	-- Window check: discard claims outside the legitimate cast window. Stops
	-- replay attacks where an exploiter records a winning marker and re-sends.
	if os.clock() - pending.startedAt > GameConfig.AntiExploit.CatchClaimWindowSeconds then
		self._pendingCasts[player] = nil
		return { success = false, reason = "claim_too_late" }
	end

	-- Sanitize marker — clients are untrusted.
	if typeof(marker) ~= "number" or marker ~= marker then -- NaN guard
		self._pendingCasts[player] = nil
		return { success = false, reason = "bad_marker" }
	end
	marker = math.clamp(marker, 0, 1)

	local fish = fishById[pending.fishId]
	self._pendingCasts[player] = nil
	if not fish then
		return { success = false, reason = "internal_no_fish" }
	end

	local greenLow  = pending.greenCenter - pending.greenSize / 2
	local greenHigh = pending.greenCenter + pending.greenSize / 2
	if marker < greenLow or marker > greenHigh then
		self.Client.CastResolved:Fire(player, { success = false, reason = "missed" })
		return { success = false, reason = "missed" }
	end

	-- Success! Roll weight uniformly within the species' range.
	local minW, maxW = fish.weightRange[1], fish.weightRange[2]
	local weight = minW + math.random() * (maxW - minW)
	-- Round to one decimal for nicer UI.
	weight = math.floor(weight * 10 + 0.5) / 10

	-- Build inventory item.
	local item: Types.FishItem = {
		uid = UidUtil.new("fish"),
		kind = "Fish",
		speciesId = fish.id,
		weightKg = weight,
		caughtAt = os.time(),
	}

	-- Apply rewards via PlayerDataService — this fires client signals for us.
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddItem(player, item)
	PlayerDataService:AddXP(player, fish.xp)

	-- Update stats so quests can read them.
	local data = PlayerDataService:GetProfile(player)
	if data then
		data.stats.totalCatches += 1
		data.stats.caughtSpecies[fish.id] = (data.stats.caughtSpecies[fish.id] or 0) + 1
	end

	-- Lure token drop (premium currency).
	if math.random() < GameConfig.Fishing.LureTokenDropChance then
		PlayerDataService:AddLureTokens(player, 1)
	end

	-- Notify the QuestService so any active "CatchSpecies"/"CatchAnyFish"/"EarnCoins"
	-- quests can advance. Done via a service call, not an event, so the order
	-- of completion and reward grants is deterministic.
	local QuestService = Knit.GetService("QuestService")
	QuestService:OnFishCaught(player, fish.id)

	local result = {
		success = true,
		fish = fish,
		weightKg = weight,
		coinsEarned = 0,         -- coins come from selling, not catching, intentionally
		xpGained = fish.xp,
	}
	self.Client.CastResolved:Fire(player, result)
	return result
end

return FishingService
