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

	local Players           = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService       = game:GetService("HttpService")
	local CollectionService = game:GetService("CollectionService")

	local Knit         = require(ReplicatedStorage.Packages.Knit)
	local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
	local Types        = require(ReplicatedStorage.Shared.Types)
	local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
	local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)
	local Signal       = require(ReplicatedStorage.Packages.Signal)

	local FishCatalog     = require(ReplicatedStorage.Shared.Config.FishCatalog)
	local RodCatalog      = require(ReplicatedStorage.Shared.Config.RodCatalog)
	local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)

	local BUILDING_ANCHOR_TAG = "BuildingAnchor"

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
			-- Server -> client: bite confirmed. Sends the WEIGHT, tension TIER
			-- (light/medium/heavy/legendary — derived from rarity), and RARITY string
			-- so the client can theme the reel-mini-game visuals. Fish id/species name
			-- are still withheld here — the reveal belongs to CastResolved.
			BiteStarted = Knit.CreateSignal(),
			-- Final result of a cast (miss, escape, or catch).
			-- Shape: { success, reason?, fish?, weightKg?, coinsEarned?, xpGained?, perfect? }
			CastResolved = Knit.CreateSignal(),
		},

		_pendingCasts = {},      -- [Player] -> pending cast state (see _newPending)
		_lighthouseCache = {},   -- [userId: number] -> { uid: string, position: Vector3, tier: number }
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
	-- RARITY → TENSION TIER. Primary difficulty axis is rarity; weight is a
	-- secondary modifier on zone oscillation speed only (via ReelZoneSpeedPerKg).
	-- ====================================================================
	local function rarityToTier(rarity: string): string
		return GameConfig.Fishing.RarityTierMap[rarity] or "light"
	end

	-- 0..1 difficulty scalar. Rarity provides the base; weight adds a small
	-- continuous nudge so a heavy Epic still feels slightly harder than a light one.
	local function difficultyFor(rarity: string, weightKg: number): number
		local base = GameConfig.Fishing.RarityDifficultyBase[rarity] or 0.1
		local weightNudge = math.clamp(weightKg / 200, 0, 0.10)
		return math.clamp(base + weightNudge, 0.0, 1.0)
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

	local function rollFish(ctx: {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number, rareMultiplier: number, lighthouseBumpChance: number?}): Fish?
		local buckets: {[string]: {Fish}} = { Common = {}, Uncommon = {}, Rare = {}, Epic = {}, Legendary = {}, Mythic = {}, Divine = {} }
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

		-- Lighthouse rarity bump: flat additive chance to upgrade one rarity tier.
		-- Only bumps if the higher-rarity bucket has eligible fish for this context.
		local bump = ctx.lighthouseBumpChance or 0
		if bump > 0 and math.random() < bump then
			local rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine" }
			for i, r in ipairs(rarityOrder) do
				if r == chosenRarity and i < #rarityOrder then
					local nextRarity = rarityOrder[i + 1]
					if buckets[nextRarity] and #buckets[nextRarity] > 0 then
						chosenRarity = nextRarity
					end
					break
				end
			end
		end

		local pool = buckets[chosenRarity]
		return pool[math.random(1, #pool)]
	end

	-- ====================================================================
	-- FISH MODIFIERS
	-- ====================================================================

	-- Build a modifier lookup keyed by id once at load time.
	local modifierById: {[string]: {id:string, displayName:string, dropChance:number, weightMul:number?, xpMul:number?, coinInstant:number?, lureBonus:number?}} = {}
	for _, mod in ipairs(GameConfig.FishModifiers) do
		modifierById[mod.id] = mod
	end

	-- Roll which modifiers (if any) apply to a single catch. Each modifier
	-- rolls its dropChance independently so multiple can land on one fish.
	local function rollModifiers(modifierLuckMultiplier: number?): {string}
		local result: {string} = {}
		for _, mod in ipairs(GameConfig.FishModifiers) do
			if math.random() < math.min(mod.dropChance * (modifierLuckMultiplier or 1.0), 1.0) then
				table.insert(result, mod.id)
			end
		end
		return result
	end

	-- Aggregate the numeric effects of a set of modifier ids. All multipliers
	-- compound; bonuses are summed. Called in ReleaseReel after weight is set.
	local function applyModifierEffects(
		modifiers: {string},
		weight: number,
		xpAward: number,
		fishBasePrice: number
	): (number, number, number, number) -- weight, xp, instantCoins, lureBonus
		local weightMul    = 1.0
		local xpMul        = 1.0
		local coinInstant  = 0.0
		local lureBonus    = 0

		for _, id in ipairs(modifiers) do
			local mod = modifierById[id]
			if mod then
				weightMul   = weightMul * (mod.weightMul   or 1.0)
				xpMul       = xpMul    * (mod.xpMul        or 1.0)
				coinInstant = coinInstant + (mod.coinInstant or 0.0)
				lureBonus   = lureBonus  + (mod.lureBonus   or 0)
			end
		end

		local finalWeight     = math.floor(weight * weightMul * 10 + 0.5) / 10
		local finalXp         = math.floor(xpAward * xpMul)
		local finalCoins      = math.floor(fishBasePrice * coinInstant)
		return finalWeight, finalXp, finalCoins, lureBonus
	end

	-- ====================================================================
	-- LIFECYCLE
	-- ====================================================================

	function FishingService:KnitInit()
		self._castLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxCastsPerMinute, 60)
		-- Coarse limiter shared across the three reel-pipeline remotes
		-- (ClaimCast, ReleaseReel, ReportEscape). Upstream is already gated by
		-- StartCast's limiter; this is defense-in-depth against stuck-pending
		-- spam. Silent-drop per CLAUDE.md cozy pillar.
		self._reelLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxReelClaimsPerMinute, 60)
	end

	function FishingService:KnitStart()
		Players.PlayerRemoving:Connect(function(player)
			self._pendingCasts[player] = nil
			self._lastCastAt[player] = nil
			self._assistMultiplier[player] = nil
			self._lighthouseCache[player.UserId] = nil
			self._castLimiter:reset(player)
			self._reelLimiter:reset(player)
		end)

		-- Populate cache for players who already have a lighthouse from a prior session.
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local function seedLighthouseCache(player: Player)
			task.spawn(function()
				local data = PlayerDataService:WaitForProfile(player, 30)
				if not data then return end
				for _, b in ipairs(data.buildings) do
					if b.kind == "Lighthouse" then
						self:_rebuildLighthouseCache(player, b)
						break
					end
				end
			end)
		end
		Players.PlayerAdded:Connect(seedLighthouseCache)
		for _, player in ipairs(Players:GetPlayers()) do
			seedLighthouseCache(player)
		end

		local HarborService = Knit.GetService("HarborService")

		HarborService.BuildingPlacedServer.Event:Connect(function(player, building)
			if building.kind ~= "Lighthouse" then return end
			self:_rebuildLighthouseCache(player, building)
		end)

		HarborService.BuildingUpgradedServer.Event:Connect(function(player, building, _oldTier, _newTier)
			if building.kind ~= "Lighthouse" then return end
			self:_rebuildLighthouseCache(player, building)
		end)

		HarborService.OnBuildingRemoved.Event:Connect(function(player, uid)
			local entry = self._lighthouseCache[player.UserId]
			if entry and entry.uid == uid then
				self._lighthouseCache[player.UserId] = nil
			end
		end)
	end

	-- ====================================================================
	-- LIGHTHOUSE CACHE
	-- ====================================================================
	-- Rebuilds the cached lighthouse entry for a player. Called whenever a
	-- Lighthouse is placed or upgraded so the cast-time proximity check always
	-- uses the current position and tier.
	function FishingService:_rebuildLighthouseCache(player: Player, building: {uid: string, kind: string, tier: number})
		local uid, tier = building.uid, building.tier
		for _, part in ipairs(CollectionService:GetTagged(BUILDING_ANCHOR_TAG)) do
			if part.Name == uid then
				self._lighthouseCache[player.UserId] = { uid = uid, position = part.Position, tier = tier }
				return
			end
		end
		-- Anchor not spawned yet (join-time race with HarborService) — wait for it.
		local conn
		conn = CollectionService:GetInstanceAddedSignal(BUILDING_ANCHOR_TAG):Connect(function(part)
			if part.Name == uid then
				conn:Disconnect()
				if player.Parent then
					self._lighthouseCache[player.UserId] = { uid = uid, position = part.Position, tier = tier }
				end
			end
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
	function FishingService:_getContext(player: Player): {biome: string, timeOfDay: string, weather: string, tide: string, rodTier: number, rareMultiplier: number, equippedRodId: string}?
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

		-- Biome fallback: deep bands silently downgrade to the highest unlocked
		-- biome when dock tier is insufficient. This closes the swim/spoof bypass
		-- without a failure state. Dock tier is read from the player's Dock building
		-- (default 1 — the inherited rundown dock — when no Dock record exists).
		local dockRequired = GameConfig.Biomes.DockTierRequired[biome]
		if dockRequired and dockRequired > 1 then
			local dockTier = 1
			for _, b in ipairs(data.buildings or {}) do
				local t = b.tier or 1
				if b.kind == "Dock" and t > dockTier then
					dockTier = t
				end
			end
			if dockTier < dockRequired then
				local order = GameConfig.Biomes.BandOrder
				local resolvedIdx = table.find(order, biome) or 1
				local allowed = order[1]  -- Shoreline floor (always tier 1)
				for i = 1, resolvedIdx do
					local band = order[i]
					if (GameConfig.Biomes.DockTierRequired[band] or 1) <= dockTier then
						allowed = band
					end
				end
				biome = allowed
			end
		end

		local BaitService = Knit.GetService("BaitService")
		local rareMul = BaitService:GetEquippedRarityBoost(player)

		return {
			biome = biome,
			timeOfDay = WeatherService:GetTimeOfDay(),
			weather = WeatherService:GetWeather(),
			tide = TideService:GetTide(),
			rodTier = data.rodTier,
			rareMultiplier = rareMul,
			equippedRodId = data.equippedRodId or "driftwood",
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

		local hrp = char:FindFirstChildOfClass("HumanoidRootPart")
		local castPosition: Vector3? = hrp and hrp.Position or nil

		local ctx = self:_getContext(player)
		if not ctx then return nil end

		local lhEntry = self._lighthouseCache[player.UserId]
		local bumpChance = 0.0
		local modifierLuckMultiplier = 1.0
		if lhEntry and castPosition then
			local radius = BuildingCatalog.Lighthouse.tiers[lhEntry.tier].lighthouseLureRadiusStuds
			local dist = (lhEntry.position - castPosition).Magnitude
			if dist <= radius then
				bumpChance = GameConfig.Buildings.Lighthouse.RarityBumpChance[lhEntry.tier]
			modifierLuckMultiplier = GameConfig.Buildings.Lighthouse.ModifierLuckMultiplier[lhEntry.tier]
			end
		elseif not lhEntry then
			-- No lighthouse in cache — either not built yet or cache miss.
		end
		ctx.lighthouseBumpChance = bumpChance

		-- Rod rarity boost: higher-tier rods increase odds of non-Common fish.
		local rod = RodCatalog.byId[ctx.equippedRodId]
		ctx.rareMultiplier = (ctx.rareMultiplier or 1.0) * (rod and rod.rarityMultiplier or 1.0)

		local fish = rollFish(ctx)
		if not fish then return nil end

		-- Pre-roll the weight here so BiteStarted (on hit) can deliver it without
		-- a second random call later. Rounded to 1 decimal for UI parity.
		local minW, maxW = fish.weightRange[1], fish.weightRange[2]
		local weight = minW + math.random() * (maxW - minW)
		weight = math.floor(weight * 10 + 0.5) / 10

		local castId = UidUtil.new("cast")
		-- Scale the green zone up globally so catches stay comfortable without
		-- a hidden per-rod validation expansion.
		local displaySize = math.min(fish.greenZoneSize * (GameConfig.Fishing.FeelTuning.BaseGreenZoneScale or 1.0), 0.80)
		local center = displaySize / 2 + math.random() * (1 - displaySize)
		-- Validation zone: rod no longer secretly widens it. What the player sees
		-- is what the server checks (tutorial assist multiplier still applies).
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
			equippedRodId = ctx.equippedRodId,  -- snapshot at cast time; immutable for this cast
			castPosition = castPosition,
			modifierLuckMultiplier = modifierLuckMultiplier,
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
		if not self._reelLimiter:check(player) then return { result = "error", reason = "rate_limit" } end
		if typeof(castId) ~= "string" or #castId == 0 or #castId > 64 then
			return { result = "error", reason = "bad_cast_id" }
		end
		local pending = self._pendingCasts[player]
		if not pending or pending.castId ~= castId or pending.phase ~= "casting" then
			return { result = "error", reason = "no_pending_cast" }
		end

		if os.clock() - pending.startedAt > GameConfig.AntiExploit.CatchClaimWindowSeconds then
			self._pendingCasts[player] = nil
			self.Client.CastResolved:Fire(player, { success = false, reason = "timeout" })
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

		-- Consume 1 bait on a successful cast (green-zone hit). Spawned so the
		-- stash-notify round-trip doesn't add latency to the ClaimCast response.
		task.spawn(function()
			Knit.GetService("BaitService"):ConsumeEquippedBait(player)
		end)

		-- HIT → transition to reel. Tier (rarity-derived) and rarity travel to
		-- the client via BiteStarted; fish species identity stays server-side until CastResolved.
		pending.phase = "reeling"
		pending.reelStartedAt = os.clock()

		local tier = rarityToTier(fish.rarity)
		local difficulty = difficultyFor(fish.rarity, pending.weightKg)

		-- Reel-phase timeout. Independent of the cast-phase timer.
		task.delay(GameConfig.Fishing.ReelTimeoutSeconds, function()
			local p = self._pendingCasts[player]
			if p and p.castId == castId and p.phase == "reeling" then
				self._pendingCasts[player] = nil
				self.Client.CastResolved:Fire(player, { success = false, reason = "reel_timeout" })
			end
		end)

		self.Client.BiteStarted:Fire(player, {
			castId     = castId,
			weightKg   = pending.weightKg,
			tier       = tier,
			difficulty = difficulty,
			rarity     = fish.rarity,
		})
		return { result = "bite" }
	end

	-- 3a) Client says "I completed the reel mini-game with perfectFraction=X".
	-- Server grants the catch and applies the perfect bonus on the XP only
	-- (coins still come from selling, not catching).
	function FishingService.Client:ReleaseReel(player: Player, castId: string, perfectFraction: number): {success: boolean, reason: string?, perfect: boolean?}
		local self = self.Server
		if not self._reelLimiter:check(player) then return { success = false, reason = "rate_limit" } end
		if typeof(castId) ~= "string" or #castId == 0 or #castId > 64 then
			return { success = false, reason = "bad_cast_id" }
		end
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
		-- Capped at MaxPerfectFractionAllowed — we cannot verify actual zone
		-- time server-side; cap limits the abuse window to a bounded multiplier.
		perfectFraction = math.min(perfectFraction, GameConfig.AntiExploit.MaxPerfectFractionAllowed)

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
		local snapRodId = pending.equippedRodId or "driftwood"
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

		-- Rod catchWeightBonus: flat kg added after catalog roll and perfect-cast boost.
		local equippedRod = RodCatalog.byId[snapRodId]
		local rodWeightBonus = equippedRod and equippedRod.catchWeightBonus or 0
		weight = math.floor((weight + rodWeightBonus) * 10 + 0.5) / 10

		local xpAward = fish.xp
		local perfectCoins = 0
		if perfect then
			xpAward = math.floor(xpAward * FT.PerfectBonusMultiplier)
			-- Perfect reel: award an instant coin bonus on top of the normal sell value.
			perfectCoins = math.floor((fish.basePrice or 0) * FT.PerfectReelCoinFraction)
		end

		-- Fish modifiers: each rolls independently; effects compound.
		local modifiers = rollModifiers(pending.modifierLuckMultiplier)
		-- World-state modifiers: assigned based on server conditions at catch time.
		do
			local TideService_    = Knit.GetService("TideService")
			local WeatherService_ = Knit.GetService("WeatherService")
			local tide    = TideService_:GetTide()
			local weather = WeatherService_:GetWeather()
			local tod     = WeatherService_:GetTimeOfDay()
			if tide    == "High"    then table.insert(modifiers, "tide_kissed")  end
			if weather == "Storm"   then table.insert(modifiers, "storm_forged") end
			if tod     == "Night"   then table.insert(modifiers, "moon_touched") end
			if tod     == "Morning" then table.insert(modifiers, "dawn_blessed") end
			if weather == "Fog"     then table.insert(modifiers, "fog_shrouded") end
		end
		local modCoins = 0
		local modLureBonus = 0
		if #modifiers > 0 then
			local modXp: number
			weight, modXp, modCoins, modLureBonus = applyModifierEffects(modifiers, weight, xpAward, fish.basePrice or 0)
			xpAward = modXp
		end

		local PlayerDataService = Knit.GetService("PlayerDataService")

		-- Coin grants (perfect + modifier) in one call to minimise signal churn.
		local totalInstantCoins = perfectCoins + modCoins
		if totalInstantCoins > 0 then
			PlayerDataService:AddCoins(player, totalInstantCoins, "catch_bonus")
		end

		local item: Types.FishItem = {
			uid       = UidUtil.new("fish"),
			kind      = "Fish",
			speciesId = fish.id,
			weightKg  = weight,
			caughtAt  = os.time(),
			modifiers = #modifiers > 0 and modifiers or nil,
		}

		PlayerDataService:AddItem(player, item)
		PlayerDataService:AddXP(player, xpAward)

		local data = PlayerDataService:GetProfile(player)
		local newBest = false
		if data then
			data.stats.totalCatches += 1
			local prevCount = data.stats.caughtSpecies[fish.id] or 0
			data.stats.caughtSpecies[fish.id] = prevCount + 1
			-- Fire CodexChanged when a new species is first discovered.
			if prevCount == 0 then
				PlayerDataService.Client.CodexChanged:Fire(player, fish.id, data.stats.caughtSpecies)
			end

			-- Personal-best tracking. `weight` is fully resolved here (perfect-cast,
			-- rod bonus, modifier effects already applied). Server-authoritative:
			-- the client only renders the resulting flag, never decides it.
			local CR = GameConfig.CatchRecords
			local pb = data.stats.personalBests[fish.id]
			local firstMod = (#modifiers > 0) and modifiers[1] or nil
			if pb == nil then
				data.stats.personalBests[fish.id] = {
					heaviestKg = weight,
					firstCaughtAt = os.time(),
					firstModifierId = firstMod,
				}
				newBest = CR.CelebrateFirstOfSpecies
			elseif weight > (pb.heaviestKg + CR.MinImprovementKg) then
				pb.heaviestKg = weight
				newBest = true
			end
		end

		-- Base lure token drop chance + any modifier lure bonus.
		if math.random() < GameConfig.Fishing.LureTokenDropChance then
			modLureBonus += 1
		end
		if modLureBonus > 0 then
			PlayerDataService:AddLureTokens(player, modLureBonus)
		end

		self.CaughtServer:Fire(player, fish, weight, perfect)

		local result = {
			success      = true,
			fish         = fish,
			weightKg     = weight,
			coinsEarned  = totalInstantCoins,
			xpGained     = xpAward,
			perfect      = perfect,
			castPerfect  = castPerfect,
			modifiers    = #modifiers > 0 and modifiers or nil,
			newPersonalBest = newBest or nil,
		}
		self.Client.CastResolved:Fire(player, result)
		return { success = true, perfect = perfect }
	end

	-- 3b) Client says "the fish slipped off the line". Consolation XP, no item.
	function FishingService.Client:ReportEscape(player: Player, castId: string): {success: boolean, reason: string?}
		local self = self.Server
		if not self._reelLimiter:check(player) then return { success = false, reason = "rate_limit" } end
		if typeof(castId) ~= "string" or #castId == 0 or #castId > 64 then
			return { success = false, reason = "bad_cast_id" }
		end
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

