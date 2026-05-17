--!strict
-- FishingService.lua
-- Server-authoritative fishing. Three-phase contract:
--
--   1. StartCast()       — server picks species, ROLLS WEIGHT, returns the
--                          timing window so the client can render the cast
--                          meter. Pending state = "casting".
--   2. ClaimCast(marker) — client reports the timing release. Server checks
--                          the marker against the green zone:
--                            * miss  → fires CastResolved(success=false, missed)
--                            * hit   → transitions pending state to "reeling",
--                                      fires BiteStarted(weight,tier,difficulty)
--                                      so the client can run the reel mini-game.
--   3. ReleaseReel(frac) — client reports the perfect-zone fraction of its
--                          reel mini-game. Server grants the catch; awards a
--                          2× XP bonus when frac ≥ FT.PerfectThreshold.
--      ReportEscape()     — client reports the fish slipped off (indicator
--                          fell off the back edge). Server confirms, grants
--                          small consolation XP.
--
-- The reel mini-game is client-driven (server doesn't tick the meter); it's
-- gated by a minimum elapsed time (MinReelSeconds) and the ReelTimeoutSeconds
-- window so a tampered client can't insta-claim or hold a pending state open.
-- The client only ever sends `perfectFraction` — a scalar. The fish identity,
-- weight, and rewards are all set on the server before the client knew them.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types        = require(ReplicatedStorage.Shared.Types)
local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Signal       = require(ReplicatedStorage.Packages.Signal)

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
		-- Server -> client: bite confirmed. Sends the WEIGHT and weight TIER
		-- (light/medium/heavy/legendary) so the client can scale reel-mini-game
		-- difficulty visuals. We do NOT send fish id/rarity — the reveal still
		-- belongs to CastResolved.
		BiteStarted = Knit.CreateSignal(),
		-- Final result of a cast (miss, escape, or catch).
		-- Shape: { success, reason?, fish?, weightKg?, coinsEarned?, xpGained?, perfect? }
		CastResolved = Knit.CreateSignal(),
	},

	_pendingCasts = {},  -- [Player] -> pending cast state (see _newPending)
	_castLimiter = nil :: any,
	_lastCastAt = {},
	-- Server-internal signals for cross-service hooks (QuestService, TutorialService).
	CaughtServer      = Signal.new(),  -- (player, fish, weightKg, isPerfect)
	CastStartedServer = Signal.new(),  -- (player)
	-- Tutorial beginner assist: widens the *validation* zone without changing
	-- the display zone. TutorialService is the only writer.
	_assistMultiplier = {},  -- [Player] -> number (default 1.0)
})

-- ====================================================================
-- INDEX FISH BY ID for O(1) lookup
-- ====================================================================
local fishById: {[string]: Fish} = {}
for _, f in ipairs(FishCatalog.fish) do
	fishById[f.id] = f
end

-- ====================================================================
-- WEIGHT → TENSION TIER. Used by the client for reel-mini-game scaling.
-- Mirror the tier table in FishingController; keep the boundaries here
-- so the server is the source of truth.
-- ====================================================================
local function weightToTier(weightKg: number): string
	if weightKg < 2 then return "light"
	elseif weightKg < 10 then return "medium"
	elseif weightKg < 40 then return "heavy"
	else return "legendary" end
end

-- 0..1 difficulty hint. Clamped so the lightest fish still feels alive.
local function difficultyFor(weightKg: number): number
	return math.clamp(weightKg / 50, 0.1, 1.0)
end

-- ====================================================================
-- ELIGIBILITY: filter the catalog down to "what could plausibly bite right now"
-- ====================================================================
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

local function rollFish(ctx: {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number, rareMultiplier: number}): Fish?
	local buckets: {[string]: {Fish}} = { Common = {}, Uncommon = {}, Rare = {}, Mythic = {} }
	for _, f in ipairs(FishCatalog.fish) do
		if fishMatches(f, ctx) then
			table.insert(buckets[f.rarity], f)
		end
	end

	local totalWeight = 0
	local adjusted = {}
	for rarity, weight in pairs(GameConfig.Fishing.RarityWeights) do
		if #buckets[rarity] > 0 then
			local w = (rarity == "Common") and weight or (weight * ctx.rareMultiplier)
			adjusted[rarity] = w
			totalWeight += w
		end
	end
	if totalWeight == 0 then return nil end
	local roll = math.random() * totalWeight
	local chosenRarity: string? = nil
	for rarity, weight in pairs(adjusted) do
		roll -= weight
		if roll <= 0 then
			chosenRarity = rarity
			break
		end
	end
	if not chosenRarity then return nil end

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
	Players.PlayerRemoving:Connect(function(player)
		self._pendingCasts[player] = nil
		self._lastCastAt[player] = nil
		self._assistMultiplier[player] = nil
		self._castLimiter:reset(player)
	end)
end

-- ====================================================================
-- TUTORIAL-FACING API
-- ====================================================================
function FishingService:SetAssistMultiplier(player: Player, multiplier: number)
	self._assistMultiplier[player] = math.max(1.0, multiplier or 1.0)
end

function FishingService:ClearAssist(player: Player)
	self._assistMultiplier[player] = nil
end

function FishingService:GetAssistMultiplier(player: Player): number
	return self._assistMultiplier[player] or 1.0
end

-- ====================================================================
-- CONTEXT
-- ====================================================================
function FishingService:_getContext(player: Player): {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number, rareMultiplier: number}?
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local TideService       = Knit.GetService("TideService")
	local WeatherService    = Knit.GetService("WeatherService")

	local data = PlayerDataService:GetProfile(player)
	if not data then return nil end

	local biome = "Shoreline"
	local char = player.Character
	if char then
		local hint = char:FindFirstChild("CurrentBiome")
		if hint and hint:IsA("StringValue") then
			biome = hint.Value
		end
	end

	local rareMul = 1.0
	if data.activeBuff then
		if os.time() < data.activeBuff.expiresAt then
			rareMul = data.activeBuff.rareWeightMultiplier or 1.0
		else
			data.activeBuff = nil
		end
	end

	return {
		biome = biome,
		timeOfDay = WeatherService:GetTimeOfDay(),
		weather = WeatherService:GetWeather(),
		tide = TideService:GetTide(),
		rodTier = data.rodTier,
		rareMultiplier = rareMul,
	}
end

-- ====================================================================
-- CLIENT API: cast → claim → reel
-- ====================================================================

-- 1) Client says "I started a cast". Server picks the species AND rolls the
-- weight up-front so that BiteStarted (fired later on ClaimCast hit) can ship
-- the weight without exposing the species. Pending phase = "casting".
function FishingService.Client:StartCast(player: Player): {castId: string, greenCenter: number, greenSize: number, period: number}?
	local self = self.Server
	local char = player.Character
	if not char or not char:FindFirstChild("Fishing Rod") then
		return nil
	end
	if not self._castLimiter:check(player) then return nil end
	local last = self._lastCastAt[player] or 0
	if os.clock() - last < GameConfig.Fishing.CastCooldownSeconds then return nil end
	self._lastCastAt[player] = os.clock()

	local ctx = self:_getContext(player)
	if not ctx then return nil end

	local fish = rollFish(ctx)
	if not fish then return nil end

	-- Pre-roll the weight here so BiteStarted (on hit) can deliver it without
	-- a second random call later. Rounded to 1 decimal for UI parity.
	local minW, maxW = fish.weightRange[1], fish.weightRange[2]
	local weight = minW + math.random() * (maxW - minW)
	weight = math.floor(weight * 10 + 0.5) / 10

	local castId = UidUtil.new("cast")
	local displaySize = fish.greenZoneSize
	local center = displaySize / 2 + math.random() * (1 - displaySize)
	-- Validation zone: widened by tutorial assist without changing the display.
	local assistMul = self._assistMultiplier[player] or 1.0
	local validationSize = math.min(1.0, displaySize * assistMul)
	local half = validationSize / 2
	local validationCenter = math.clamp(center, half, 1 - half)

	self._pendingCasts[player] = {
		castId = castId,
		fishId = fish.id,
		weightKg = weight,
		greenCenter = validationCenter,
		greenSize = validationSize,
		displayCenter = center,
		displaySize = displaySize,
		assistApplied = assistMul > 1.0,
		startedAt = os.clock(),
		reelStartedAt = nil,
		phase = "casting",
	}

	-- Cast-phase timeout (no claim within CastTimeoutSeconds → fail).
	task.delay(GameConfig.Fishing.CastTimeoutSeconds, function()
		local pending = self._pendingCasts[player]
		if pending and pending.castId == castId and pending.phase == "casting" then
			self._pendingCasts[player] = nil
			self.Client.CastResolved:Fire(player, { success = false, reason = "timeout" })
		end
	end)

	self.CastStartedServer:Fire(player)

	return {
		castId = castId,
		greenCenter = center,
		greenSize = displaySize,
		period = GameConfig.Fishing.CastMeterPeriod,
	}
end

-- 2) Client says "I released the cast meter at marker=X". Server validates
-- the timing. Miss → CastResolved(missed). Hit → BiteStarted, and the
-- player enters the reel phase.
function FishingService.Client:ClaimCast(player: Player, castId: string, marker: number): {result: string, reason: string?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId or pending.phase ~= "casting" then
		return { result = "error", reason = "no_pending_cast" }
	end

	if os.clock() - pending.startedAt > GameConfig.AntiExploit.CatchClaimWindowSeconds then
		self._pendingCasts[player] = nil
		return { result = "error", reason = "claim_too_late" }
	end

	if typeof(marker) ~= "number" or marker ~= marker then
		self._pendingCasts[player] = nil
		return { result = "error", reason = "bad_marker" }
	end
	marker = math.clamp(marker, 0, 1)

	local fish = fishById[pending.fishId]
	if not fish then
		self._pendingCasts[player] = nil
		return { result = "error", reason = "internal_no_fish" }
	end

	local greenLow  = pending.greenCenter - pending.greenSize / 2
	local greenHigh = pending.greenCenter + pending.greenSize / 2
	if marker < greenLow or marker > greenHigh then
		self._pendingCasts[player] = nil
		self.Client.CastResolved:Fire(player, { success = false, reason = "missed" })
		return { result = "miss" }
	end

	-- Detect whether the marker landed inside the inner perfect zone. We use
	-- the *display* center/size (what the player saw), not the possibly-wider
	-- validation zone, so the check matches what the UI showed.
	local perfHalf = (pending.displaySize * GameConfig.Fishing.FeelTuning.PerfectZoneFraction) / 2
	pending.castPerfect = math.abs(marker - pending.displayCenter) <= perfHalf

	-- HIT → transition to reel. Weight & tier travel to the client via
	-- BiteStarted; fish identity stays server-side until CastResolved.
	pending.phase = "reeling"
	pending.reelStartedAt = os.clock()

	local tier = weightToTier(pending.weightKg)
	local difficulty = difficultyFor(pending.weightKg)

	-- Reel-phase timeout. Independent of the cast-phase timer.
	task.delay(GameConfig.Fishing.ReelTimeoutSeconds, function()
		local p = self._pendingCasts[player]
		if p and p.castId == castId and p.phase == "reeling" then
			self._pendingCasts[player] = nil
			self.Client.CastResolved:Fire(player, { success = false, reason = "reel_timeout" })
		end
	end)

	self.Client.BiteStarted:Fire(player, {
		castId = castId,
		weightKg = pending.weightKg,
		tier = tier,
		difficulty = difficulty,
	})
	return { result = "bite" }
end

-- 3a) Client says "I completed the reel mini-game with perfectFraction=X".
-- Server grants the catch and applies the perfect bonus on the XP only
-- (coins still come from selling, not catching).
function FishingService.Client:ReleaseReel(player: Player, castId: string, perfectFraction: number): {success: boolean, reason: string?, perfect: boolean?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId or pending.phase ~= "reeling" then
		return { success = false, reason = "no_pending_reel" }
	end

	-- Sanitize the client-reported fraction. The server doesn't tick the reel
	-- meter, so we can't verify the *value* of perfectFraction beyond range —
	-- but we *can* verify the player actually held the reel state long enough
	-- for the mini-game to be plausible.
	if typeof(perfectFraction) ~= "number" or perfectFraction ~= perfectFraction then
		perfectFraction = 0
	end
	perfectFraction = math.clamp(perfectFraction, 0, 1)

	local reelDuration = os.clock() - (pending.reelStartedAt or pending.startedAt)
	if reelDuration < GameConfig.AntiExploit.MinReelSeconds then
		-- Insta-claim. Treat as exploit; nullify the cast.
		self._pendingCasts[player] = nil
		self.Client.CastResolved:Fire(player, { success = false, reason = "reel_too_fast" })
		return { success = false, reason = "reel_too_fast" }
	end

	local fish = fishById[pending.fishId]
	local weight = pending.weightKg
	local castPerfect = pending.castPerfect == true  -- capture before clearing
	self._pendingCasts[player] = nil
	if not fish then
		return { success = false, reason = "internal_no_fish" }
	end

	local FT = GameConfig.Fishing.FeelTuning
	local perfect = perfectFraction >= FT.PerfectThreshold

	-- Perfect cast: the marker landed in the gold inner strip → heavier fish.
	if castPerfect then
		local boosted = math.floor(weight * (1 + FT.PerfectCastWeightBonus) * 10 + 0.5) / 10
		weight = math.min(boosted, fish.weightRange[2] * 1.5)
	end

	local xpAward = fish.xp
	local perfectCoins = 0
	if perfect then
		xpAward = math.floor(xpAward * FT.PerfectBonusMultiplier)
		-- Perfect reel: award an instant coin bonus on top of the normal sell value.
		perfectCoins = math.floor((fish.basePrice or 0) * FT.PerfectReelCoinFraction)
		if perfectCoins > 0 then
			PlayerDataService:AddCoins(player, perfectCoins, "perfect_catch")
		end
	end

	local item: Types.FishItem = {
		uid = UidUtil.new("fish"),
		kind = "Fish",
		speciesId = fish.id,
		weightKg = weight,
		caughtAt = os.time(),
	}

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddItem(player, item)
	PlayerDataService:AddXP(player, xpAward)

	local data = PlayerDataService:GetProfile(player)
	if data then
		data.stats.totalCatches += 1
		data.stats.caughtSpecies[fish.id] = (data.stats.caughtSpecies[fish.id] or 0) + 1
	end

	if math.random() < GameConfig.Fishing.LureTokenDropChance then
		PlayerDataService:AddLureTokens(player, 1)
	end

	self.CaughtServer:Fire(player, fish, weight, perfect)

	local result = {
		success = true,
		fish = fish,
		weightKg = weight,
		coinsEarned = perfectCoins,
		xpGained = xpAward,
		perfect = perfect,
		castPerfect = castPerfect,
	}
	self.Client.CastResolved:Fire(player, result)
	return { success = true, perfect = perfect }
end

-- 3b) Client says "the fish slipped off the line". Consolation XP, no item.
function FishingService.Client:ReportEscape(player: Player, castId: string): {success: boolean, reason: string?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId or pending.phase ~= "reeling" then
		return { success = false, reason = "no_pending_reel" }
	end
	self._pendingCasts[player] = nil

	local consolation = GameConfig.Fishing.EscapeConsolationXP
	if consolation and consolation > 0 then
		local PlayerDataService = Knit.GetService("PlayerDataService")
		PlayerDataService:AddXP(player, consolation)
	end

	self.Client.CastResolved:Fire(player, {
		success = false,
		reason = "escaped",
		xpGained = consolation or 0,
	})
	return { success = true }
end

return FishingService
