--!strict
-- FishingService.lua
-- Server-authoritative fishing. Client never decides what was caught — it
-- only sends timing decisions. The server runs a small state machine per
-- pending cast:
--
--   preCast        -- StartCast: fish secretly chosen, timing window sent
--     │
--     │  ClaimCast hits green
--     ▼
--   reeling        -- BiteStarted signal fired (weight + tier + difficulty)
--     │
--     ├── ReleaseReel(perfectFraction)  → catch granted (2x XP if perfect)
--     └── ReportEscape                  → consolation XP, no fish
--
-- Path-A contract additions (over the original single-shot ClaimCast):
--   * BiteStarted client signal: { castId, weightKg, tier, difficulty }
--   * ReleaseReel(castId, perfectFraction) client RPC
--   * ReportEscape(castId) client RPC
-- Replay-attack defense extended: a separate ReelClaimWindow gives the
-- reel phase a longer window than the pre-cast claim, but still bounded.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types        = require(ReplicatedStorage.Shared.Types)
local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)
local Signal       = require(ReplicatedStorage.Packages.Signal)

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
		-- Fired when ClaimCast lands in the green zone. Tells the client to
		-- transition from cast meter to reel mini-game.
		--   payload: { castId, weightKg, tier ("light"|"medium"|"heavy"|"legendary"), difficulty (0..1) }
		BiteStarted = Knit.CreateSignal(),
		-- Final result of a cast: { success, reason?, fish?, weightKg?, coinsEarned?, xpGained?, perfectFraction? }
		CastResolved = Knit.CreateSignal(),
	},

	-- internal state. Stage transitions: preCast -> reeling -> (success/escape).
	-- Each cast entry: {
	--   castId, fishId, greenCenter, greenSize, startedAt,
	--   stage, weightKg?, tier?, biteStartedAt?,
	-- }
	_pendingCasts = {},
	_castLimiter = nil :: any,
	_lastCastAt = {},    -- [Player] -> os.clock() of last cast; for cooldown
	-- Server-internal Signals for cross-service hooks. Convention TODO
	-- (tracked in CLAUDE.md follow-up): client RemoteSignals should adopt
	-- a "Remote" prefix; server Signals shouldn't need a "Server" suffix.
	-- Don't rename today — additive only.
	CaughtServer    = Signal.new(),  -- (player, fishId)
	CastStartedServer = Signal.new(), -- (player) — fires every successful StartCast (any green-zone, before claim)
	-- TUTORIAL ASSIST: per-player multiplier applied to the *validation*
	-- green zone width. Client never sees this number — the display width
	-- sent in StartCast stays at the raw fish value, so the player sees a
	-- "lucky near-miss" become a real catch. Default 1.0 (no assist).
	-- TutorialService is the only writer; it sets this on profile load if
	-- tutorial.beginnerAssistsRemaining > 0, and clears it back to 1.0 on
	-- tutorial completion or when the counter exhausts.
	_assistMultiplier = {},  -- [Player] -> number (default 1.0)
})

-- ====================================================================
-- WEIGHT -> TIER mapping. The client uses this to scale reel difficulty
-- visuals (zone speed, zone width, indicator drift). Server is the
-- source of truth so a hacked client can't lie about a fish being easy.
-- ====================================================================
local function weightToTier(weightKg: number): string
	if weightKg < 2 then return "light" end
	if weightKg < 10 then return "medium" end
	if weightKg < 40 then return "heavy" end
	return "legendary"
end

-- 0..1 difficulty number. Lets the client lerp between tier-driven
-- parameters smoothly even when weight is close to a tier boundary.
local function weightToDifficulty(weightKg: number): number
	-- Asymptotic: a 100 kg fish is ~0.95. Tuneable curve.
	return math.clamp(1 - 1 / (1 + weightKg / 20), 0, 1)
end

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

local function rollFish(ctx: {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number, rareMultiplier: number}): Fish?
	-- Step 1: build the eligible pool, bucketed by rarity.
	local buckets: {[string]: {Fish}} = { Common = {}, Uncommon = {}, Rare = {}, Mythic = {} }
	for _, f in ipairs(FishCatalog.fish) do
		if fishMatches(f, ctx) then
			table.insert(buckets[f.rarity], f)
		end
	end

	-- Step 2: weighted rarity roll. If the player has an active bait buff,
	-- multiply Uncommon/Rare/Mythic weights by ctx.rareMultiplier so the
	-- premium catches actually become reachable. Common is left alone so
	-- buffs aren't redundant with bigger rod tier.
	local totalWeight = 0
	local adjusted = {}
	for rarity, weight in pairs(GameConfig.Fishing.RarityWeights) do
		if #buckets[rarity] > 0 then
			local w = (rarity == "Common") and weight or (weight * ctx.rareMultiplier)
			adjusted[rarity] = w
			totalWeight += w
		end
	end
	if totalWeight == 0 then
		return nil  -- nothing in the world bites here right now (e.g. wrong rod tier)
	end
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
		self._assistMultiplier[player] = nil
		self._castLimiter:reset(player)
	end)
end

-- ====================================================================
-- TUTORIAL-FACING API
-- ====================================================================
-- TutorialService calls these. Kept here (not in TutorialService) so the
-- assist state lives next to the cast validation it influences. Defensive
-- against tutorial-replay exploits: TutorialService is responsible for
-- never re-enabling assist on a profile whose tutorial.state == "complete";
-- this service just trusts the caller.

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
-- CONTEXT — pulled from companion services. We require these inside
-- functions (lazily) to avoid circular requires at module load.
-- ====================================================================
function FishingService:_getContext(player: Player): {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number, rareMultiplier: number}?
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local TideService       = Knit.GetService("TideService")
	local WeatherService    = Knit.GetService("WeatherService")

	local data = PlayerDataService:GetProfile(player)
	if not data then return nil end

	-- Biome detection: simplest version reads a StringValue tagged on the
	-- character by WorldService. Default to Shoreline if unknown.
	local biome = "Shoreline"
	local char = player.Character
	if char then
		local hint = char:FindFirstChild("CurrentBiome")
		if hint and hint:IsA("StringValue") then
			biome = hint.Value
		end
	end

	-- Active bait buff multiplier. Decay on read so an expired buff doesn't
	-- linger on the profile (matches ShopService behavior).
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
	-- DISPLAY width — what the client renders on its cast meter. Center is
	-- chosen using the display width so the visible green band never clips
	-- off the edges of the bar.
	local displaySize = fish.greenZoneSize
	local center = displaySize / 2 + math.random() * (1 - displaySize)
	-- VALIDATION width — what the server actually checks against in
	-- ClaimCast. Wider than display when the tutorial's beginner assist is
	-- active; identical otherwise. Center is clamped so the (wider) zone
	-- still fits 0..1 (never let assist push the validation zone off-bar,
	-- since that would let players catch by clicking outside the meter).
	local assistMul = self._assistMultiplier[player] or 1.0
	local validationSize = math.min(1.0, displaySize * assistMul)
	-- Re-clamp center so the *validation* zone is on-bar [0, 1].
	local half = validationSize / 2
	local validationCenter = math.clamp(center, half, 1 - half)
	self._pendingCasts[player] = {
		castId = castId,
		fishId = fish.id,
		-- Validation values used inside ClaimCast. Never sent to client.
		greenCenter = validationCenter,
		greenSize = validationSize,
		-- Display values, only kept for debug / future telemetry.
		displayCenter = center,
		displaySize = displaySize,
		assistApplied = assistMul > 1.0,
		startedAt = os.clock(),
		stage = "preCast",
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

	-- Notify any server-side listeners (e.g. TutorialService's stuck-timer)
	-- that the player has at least *attempted* a cast. Fires once per
	-- successful StartCast regardless of whether the claim later lands.
	self.CastStartedServer:Fire(player)

	return {
		castId = castId,
		-- Always send the DISPLAY values to the client. Tutorial's beginner
		-- assist widens validation only — the client meter stays narrow so
		-- the assist is invisible.
		greenCenter = center,
		greenSize = displaySize,
		period = GameConfig.Fishing.CastMeterPeriod,
	}
end

-- Internal: grant the catch. Called by ReleaseReel after the player has
-- successfully completed the reel phase. perfectFraction is the server-
-- validated ratio in [0, 1]; if it clears PerfectThreshold, XP doubles.
function FishingService:_grantCatch(player: Player, pending: any, perfectFraction: number)
	local fish = fishById[pending.fishId]
	if not fish then
		self.Client.CastResolved:Fire(player, { success = false, reason = "internal_no_fish" })
		return
	end

	local weight = pending.weightKg or fish.weightRange[1]

	local item: Types.FishItem = {
		uid = UidUtil.new("fish"),
		kind = "Fish",
		speciesId = fish.id,
		weightKg = weight,
		caughtAt = os.time(),
	}

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddItem(player, item)

	local FT = GameConfig.Fishing.FeelTuning
	local isPerfect = perfectFraction >= FT.PerfectThreshold
	local xpToGrant = fish.xp
	if isPerfect then
		xpToGrant = math.floor(fish.xp * FT.PerfectBonusMultiplier + 0.5)
	end
	PlayerDataService:AddXP(player, xpToGrant)

	local data = PlayerDataService:GetProfile(player)
	if data then
		data.stats.totalCatches += 1
		data.stats.caughtSpecies[fish.id] = (data.stats.caughtSpecies[fish.id] or 0) + 1
	end

	if math.random() < GameConfig.Fishing.LureTokenDropChance then
		PlayerDataService:AddLureTokens(player, 1)
	end

	local QuestService = Knit.GetService("QuestService")
	QuestService:OnFishCaught(player, fish.id)

	-- Server-side hook for TutorialService (decrements assist counter, drives
	-- beat 3 entry). Fired AFTER profile mutation so listeners see the new
	-- catch count. No tutorial-coupling lives in FishingService itself.
	self.CaughtServer:Fire(player, fish.id)

	self.Client.CastResolved:Fire(player, {
		success = true,
		fish = fish,
		weightKg = weight,
		coinsEarned = 0,
		xpGained = xpToGrant,
		perfectFraction = perfectFraction,
		perfect = isPerfect,
	})
end

-- Client released the cast meter. If marker is inside the green zone, we
-- transition into the reel mini-game (stage = "reeling") and fire
-- BiteStarted. Outside the zone, the cast is resolved as a miss and the
-- pending entry is dropped.
function FishingService.Client:ClaimCast(player: Player, castId: string, marker: number): {stage: string, reason: string?, weightKg: number?, tier: string?, difficulty: number?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId then
		return { stage = "error", reason = "no_pending_cast" }
	end
	if pending.stage ~= "preCast" then
		-- Defensive: a double-claim while already reeling. Don't mutate.
		return { stage = "error", reason = "wrong_stage" }
	end

	if os.clock() - pending.startedAt > GameConfig.AntiExploit.CatchClaimWindowSeconds then
		self._pendingCasts[player] = nil
		self.Client.CastResolved:Fire(player, { success = false, reason = "claim_too_late" })
		return { stage = "error", reason = "claim_too_late" }
	end

	if typeof(marker) ~= "number" or marker ~= marker then -- NaN guard
		self._pendingCasts[player] = nil
		return { stage = "error", reason = "bad_marker" }
	end
	marker = math.clamp(marker, 0, 1)

	local fish = fishById[pending.fishId]
	if not fish then
		self._pendingCasts[player] = nil
		return { stage = "error", reason = "internal_no_fish" }
	end

	local greenLow  = pending.greenCenter - pending.greenSize / 2
	local greenHigh = pending.greenCenter + pending.greenSize / 2
	if marker < greenLow or marker > greenHigh then
		self._pendingCasts[player] = nil
		self.Client.CastResolved:Fire(player, { success = false, reason = "missed" })
		return { stage = "missed" }
	end

	-- Green zone hit. Roll the catch weight now so the client gets accurate
	-- difficulty for the reel phase, and so ReleaseReel doesn't need to
	-- re-roll (which would let exploiters time their ReleaseReel calls to
	-- get lucky weight rolls).
	local minW, maxW = fish.weightRange[1], fish.weightRange[2]
	local weight = minW + math.random() * (maxW - minW)
	weight = math.floor(weight * 10 + 0.5) / 10

	local tier = weightToTier(weight)
	local difficulty = weightToDifficulty(weight)

	pending.stage = "reeling"
	pending.weightKg = weight
	pending.tier = tier
	pending.biteStartedAt = os.clock()

	-- Schedule a reel-phase timeout in case the client never sends
	-- ReleaseReel / ReportEscape (network drop, app suspend on mobile).
	-- ReelTimeoutSeconds is wider than CastTimeoutSeconds because the player
	-- actively engages this phase.
	local reelDeadlineId = pending.castId
	task.delay(GameConfig.Fishing.ReelTimeoutSeconds, function()
		local p = self._pendingCasts[player]
		if p and p.castId == reelDeadlineId and p.stage == "reeling" then
			self._pendingCasts[player] = nil
			self.Client.CastResolved:Fire(player, { success = false, reason = "reel_timeout" })
		end
	end)

	self.Client.BiteStarted:Fire(player, {
		castId = castId,
		weightKg = weight,
		tier = tier,
		difficulty = difficulty,
	})

	return { stage = "biting", weightKg = weight, tier = tier, difficulty = difficulty }
end

-- Client completed the reel mini-game. perfectFraction is the player's
-- claimed ratio of perfect-zone time to total successful-tracking time.
-- Server validates timing + range; bonus XP is granted only if the
-- fraction clears PerfectThreshold.
function FishingService.Client:ReleaseReel(player: Player, castId: string, perfectFraction: number): {success: boolean, reason: string?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId then
		return { success = false, reason = "no_pending_cast" }
	end
	if pending.stage ~= "reeling" then
		return { success = false, reason = "wrong_stage" }
	end

	-- Validate perfectFraction shape. NaN, negative, > 1 → reject (treat as
	-- 0 rather than fail the whole catch; the player still pulled the fish).
	if typeof(perfectFraction) ~= "number" or perfectFraction ~= perfectFraction then
		perfectFraction = 0
	else
		perfectFraction = math.clamp(perfectFraction, 0, 1)
	end

	local FT = GameConfig.Fishing.FeelTuning
	-- Minimum plausible reel time: the perfect-zone double-counts toward
	-- ReelHoldDuration, so the absolute fastest legitimate completion is
	-- ReelHoldDuration / PerfectBonusMultiplier. Below that and the client
	-- is lying. Allow a small grace for network jitter.
	local elapsed = os.clock() - (pending.biteStartedAt or 0)
	local minLegitTime = (FT.ReelHoldDuration / FT.PerfectBonusMultiplier) - 0.25
	if elapsed < minLegitTime then
		-- Treat as a successful catch but zero out the perfect bonus —
		-- don't punish lag, but don't reward speedhacks either.
		perfectFraction = 0
	end

	self._pendingCasts[player] = nil
	self:_grantCatch(player, pending, perfectFraction)
	return { success = true }
end

-- Client lost the reel mini-game (indicator hit the edge). Server confirms
-- and grants a tiny consolation XP drop — the player still engaged with the
-- minigame and we don't want a punishing dead-end.
function FishingService.Client:ReportEscape(player: Player, castId: string): {success: boolean, reason: string?}
	local self = self.Server
	local pending = self._pendingCasts[player]
	if not pending or pending.castId ~= castId then
		return { success = false, reason = "no_pending_cast" }
	end
	if pending.stage ~= "reeling" then
		return { success = false, reason = "wrong_stage" }
	end

	-- Tiny consolation XP — clamped low so escaping isn't a farm.
	local consolation = math.max(1, math.floor((pending.weightKg or 1) / 4))
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddXP(player, consolation)

	self._pendingCasts[player] = nil
	self.Client.CastResolved:Fire(player, {
		success = false,
		reason = "escaped",
		xpGained = consolation,
	})
	return { success = true }
end

return FishingService
