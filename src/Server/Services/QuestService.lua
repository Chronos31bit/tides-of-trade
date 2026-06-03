--!strict
-- QuestService.lua
-- Daily quests + login streak rewards.
--
-- Architecture:
--   * Quest *shapes* (18 templates) live in QuestTemplates.lua.
--   * Per-player *rolls* live on profile.dailyQuests / profile.yesterdayQuests.
--   * Refresh trigger: profile.questsRefreshedDay != currentUTCDay → roll.
--     On profile load AND once a minute (in case a player straddles midnight UTC).
--   * Daily roll is seeded by (UserId, utcDay) so the same player on the
--     same UTC day always gets the same 3 quests. Stops reroll exploits.
--   * Quest progress is event-driven: services fire signals (CaughtServer,
--     SoldServer, …); QuestService maps the signal to a trigger key and
--     walks the player's 3 active quests calling matchFn/progressFn.
--
-- Tutorial integration:
--   * The first roll after tutorial completion uses SeedTutorialQuest:
--     1 tutorial_seed_catch5 + 2 normally rolled quests. Bypasses category
--     rotation just for that one roll. Subsequent days roll normally.
--
-- Reward grant path:
--   * Quest claim → _grantRewards(player, quest.reward) → PlayerData methods.
--   * Streak rewards auto-grant (no Claim button — they're passive).
--   * No central RewardService yet; single caller, premature abstraction.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local QuestTemplates = require(ReplicatedStorage.Shared.Config.QuestTemplates)
local Types        = require(ReplicatedStorage.Shared.Types)
local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
local TimeUtil     = require(ReplicatedStorage.Shared.Util.TimeUtil)
local FishCatalog  = require(ReplicatedStorage.Shared.Config.FishCatalog)
local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)

type Template = QuestTemplates.Template
type Quest = Types.Quest

local QuestService = Knit.CreateService({
	Name = "QuestService",
	Client = {
		-- Full daily snapshot. Fires on profile load, daily roll, claim,
		-- instantly on quest completion, and on incremental progress
		-- (coalesced via SnapshotPushDebounceSeconds).
		QuestsRefreshed = Knit.CreateSignal(),  -- (snapshot: { today, yesterday, streak, refreshesAt })
		-- Fired when a quest crosses from incomplete → complete on the
		-- server. Client uses this to slide in the completion popup.
		QuestCompleted  = Knit.CreateSignal(),  -- (questId)
		-- Streak day advanced. Auto-granted reward is included.
		StreakAdvanced  = Knit.CreateSignal(),  -- (streakDay, reward)
		-- Targeted toasts (no full snapshot replicate).
		QuestCompletedToast = Knit.CreateSignal(),  -- ({ questId, renderedText })
		StreakMilestone     = Knit.CreateSignal(),  -- ({ day })
		-- Fired when a player returns after an extended absence with a
		-- small coin grant. Client uses this for a "Welcome back!" toast.
		WelcomeBack         = Knit.CreateSignal(),  -- ({ daysAway, coinsGranted })
	},

	-- Per-player debounce handles for the QuestsChanged push.
	_persistTimers = {},   -- [Player] -> task handle

	-- Set of signal names we know how to handle. Templates whose `trigger`
	-- isn't in here are skipped at boot.
	_availableTriggers = {} :: {[string]: boolean},
})

-- ====================================================================
-- AVAILABLE-TRIGGER CHECK
-- ====================================================================
-- We mark a trigger "available" if the backing service exists and exposes
-- the Signal we'd attach to. Templates whose trigger isn't available log
-- a warning at boot and never roll.
local function detectAvailableTriggers(): {[string]: boolean}
	local triggers: {[string]: boolean} = {}

	local ok, FishingService = pcall(Knit.GetService, "FishingService")
	if ok and FishingService and (FishingService :: any).CaughtServer then
		triggers.FishCaught = true
	end

	local ok2, MarketService = pcall(Knit.GetService, "MarketService")
	if ok2 and MarketService then
		if (MarketService :: any).SoldServer then triggers.Sold = true end
		if (MarketService :: any).ListedServer then triggers.Listed = true end
		if (MarketService :: any).BoughtServer then triggers.Bought = true end
	end

	local ok3, HarborService = pcall(Knit.GetService, "HarborService")
	if ok3 and HarborService then
		if (HarborService :: any).BuildingUpgradedServer then triggers.BuildingUpgraded = true end
		if (HarborService :: any).BuildingPlacedServer then triggers.BuildingPlaced = true end
		if (HarborService :: any).PassiveIncomeServer then triggers.PassiveIncome = true end
	end

	local ok4, SocialService = pcall(Knit.GetService, "SocialService")
	if ok4 and SocialService then
		if (SocialService :: any).HarborVisitedServer then triggers.HarborVisited = true end
		if (SocialService :: any).EmoteUsedServer then triggers.EmoteUsed = true end
	end

	return triggers
end

-- ====================================================================
-- TEXT RENDERING — single source so localisation is a one-file change later
-- ====================================================================
local function paramDisplayValue(tpl: Template, paramName: string, value: any): any
	local def = tpl.parameters[paramName]
	if not def then return value end
	if def.type == "weighted_pick" or def.type == "pick" then
		for _, opt in ipairs(def.options :: any) do
			if opt.value == value then return opt.displayName or tostring(opt.value) end
		end
	end
	if def.type == "float" then
		return string.format("%.1f", value)
	end
	return value
end

-- Resolve each {token} exactly once, by name. Deterministic regardless
-- of params iteration order (the old pairs()-loop form could render the
-- raw species id instead of the display name depending on hash order).
-- Resolution rules per token:
--   * direct param hit  → display-formatted value (float→1dp, pick→
--     displayName, else tostring)
--   * "{xxxName}"        → display value of param "xxx"
--   * unknown token      → left literally so the gap is visible in QA
function QuestService.RenderQuestText(template: Template, params: any): string
	return (template.textTemplate:gsub("{(%w+)}", function(token: string): string
		if params[token] ~= nil then
			return tostring(paramDisplayValue(template, token, params[token]))
		end
		local base = token:match("^(.-)Name$")
		if base and params[base] ~= nil then
			return tostring(paramDisplayValue(template, base, params[base]))
		end
		return "{" .. token .. "}"
	end))
end

-- ====================================================================
-- SEEDED RNG — same player + same UTC day = same daily quests
-- ====================================================================
-- We can't use math.randomseed because that's shared global state and
-- would perturb other math.random calls. Random.new() gives us an
-- isolated stream.
local function seededRandom(userId: number, utcDay: string): Random
	-- Cheap, deterministic seed. The numeric form of "YYYY-MM-DD" is
	-- monotone day-to-day so adjacent days give very different streams.
	local dayNum = 0
	for c in utcDay:gmatch("%d") do
		dayNum = dayNum * 10 + tonumber(c) :: number
	end
	return Random.new(userId * 1000003 + dayNum)
end

-- ====================================================================
-- PARAMETER SAMPLING
-- ====================================================================
local function sampleParam(rng: Random, def: any): any
	if def.type == "int" then
		return rng:NextInteger(def.min, def.max)
	elseif def.type == "float" then
		return def.min + rng:NextNumber() * (def.max - def.min)
	elseif def.type == "weighted_pick" then
		local totalW = 0
		for _, o in ipairs(def.options) do totalW += o.weight end
		local roll = rng:NextNumber() * totalW
		local acc = 0
		for _, o in ipairs(def.options) do
			acc += o.weight
			if roll <= acc then return o.value end
		end
		return def.options[#def.options].value
	elseif def.type == "pick" then
		return def.options[rng:NextInteger(1, #def.options)].value
	end
	error("unknown parameter type: " .. tostring(def.type))
end

-- ====================================================================
-- ROLL CONTEXT — world-state snapshot for canRollForToday gates
-- ====================================================================
-- Built once per daily roll. Carries only day-stable state (demand
-- spike). QuestService never inspects this itself — templates do, via
-- their canRollForToday function. Keeps eligibility logic out of here.
function QuestService:_buildRollContext(): QuestTemplates.RollContext
	local demandSpeciesId: string? = nil
	local demandFish: any = nil
	local ok, MarketService = pcall(Knit.GetService, "MarketService")
	if ok and MarketService then
		local spike = (MarketService :: any)._demandSpike
		if spike and spike.speciesId then
			demandSpeciesId = spike.speciesId
			for _, f in ipairs(FishCatalog.fish) do
				if f.id == demandSpeciesId then demandFish = f; break end
			end
		end
	end
	return { demandSpeciesId = demandSpeciesId, demandFish = demandFish }
end

-- ====================================================================
-- TEMPLATE ELIGIBILITY
-- ====================================================================
-- True when the template can roll. Three gates, no per-template special
-- cases: (1) structural (excludeFromRoll/deprecated/trigger available),
-- (2) player gate canRollFor(profile), (3) world gate
-- canRollForToday(context).
local function isTemplateEligible(self: any, tpl: Template, profile: any, context: any): boolean
	if tpl.excludeFromRoll then return false end
	if tpl.deprecated then return false end
	if not self._availableTriggers[tpl.trigger] then return false end
	if tpl.canRollFor and not tpl.canRollFor(profile) then return false end
	if tpl.canRollForToday and not tpl.canRollForToday(context) then return false end
	return true
end

-- Build the list of templates eligible for a (category, difficulty) bucket.
local function eligibleForBucket(self: any, profile: any, category: string, difficulty: string, context: any): {Template}
	local out: {Template} = {}
	for _, tpl in ipairs(QuestTemplates.All) do
		if tpl.category == category and tpl.difficulty == difficulty and isTemplateEligible(self, tpl, profile, context) then
			table.insert(out, tpl)
		end
	end
	return out
end

-- ====================================================================
-- ROLL ONE QUEST
-- ====================================================================
local function buildQuestFromTemplate(rng: Random, tpl: Template, profile: any, utcDay: string, difficulty: string, context: any): Quest?
	local params: {[string]: any} = {}
	for name, def in pairs(tpl.parameters) do
		params[name] = sampleParam(rng, def)
	end
	-- Demand template: inject species + speciesName from the roll context.
	-- canRollForToday already guaranteed demandFish is present and fair,
	-- so this branch never hits the nil path during a normal roll — the
	-- guard stays as defence-in-depth.
	if tpl.id == "fishing_catch_demand" then
		if context and context.demandSpeciesId and context.demandFish then
			params.species = context.demandSpeciesId
			params.speciesName = context.demandFish.displayName or context.demandSpeciesId
		else
			return nil
		end
	end

	local renderedText = QuestService.RenderQuestText(tpl, params)
	local reward = tpl.rewardFormula(params, difficulty)
	-- progressFn is called with currentProgress=0 to learn the target.
	-- For most templates target == params.N or params.coins.
	local _newProgress, target = tpl.progressFn({}, params, 0)

	local utcMidnight = os.time() + TimeUtil.secondsUntilUTCMidnight()
	return {
		id = ("daily_%s_%s"):format(utcDay, UidUtil.new()),
		templateId = tpl.id,
		params = params,
		progress = 0,
		target = target,
		difficulty = difficulty,
		reward = reward,
		completed = false,
		claimed = false,
		rolledForUtcDay = utcDay,
		-- Quest claimable through the grace window after midnight UTC.
		expiresAt = utcMidnight + GameConfig.Quests.RolloverGraceHours * 3600,
		progressState = {},
		renderedText = renderedText,
		category = tpl.category,
	}
end

-- ====================================================================
-- ROLL THE FULL DAILY SET
-- ====================================================================
-- UTC weekday: "YYYY-MM-DD" → Lua wday (Sun=1..Sat=7). We re-map to Mon=1..Sun=7
-- to match CategoryRotation indexing convention.
local function utcWeekdayMonStart(utcDay: string): number
	local y, m, d = utcDay:match("(%d+)-(%d+)-(%d+)")
	local t = os.time({year = tonumber(y) :: number, month = tonumber(m) :: number, day = tonumber(d) :: number, hour = 12, min = 0, sec = 0})
	local wday = tonumber(os.date("!*t", t).wday) :: number  -- 1=Sun..7=Sat
	-- Map Sun(1)→7, Mon(2)→1, …, Sat(7)→6.
	return ((wday + 5) % 7) + 1
end

function QuestService:_rollDailySet(player: Player, profile: any): {Quest}
	local utcDay = TimeUtil.currentUTCDay()
	local weekday = utcWeekdayMonStart(utcDay)
	local rotation = GameConfig.Quests.CategoryRotation[weekday]
		or GameConfig.Quests.CategoryRotation[1]
	local difficulties = GameConfig.Quests.DifficultyDistribution

	local rng = seededRandom(player.UserId, utcDay)
	local context = self:_buildRollContext()

	local quests: {Quest} = {}
	for i = 1, GameConfig.Quests.DailyCount do
		local category = rotation[i] or rotation[#rotation]
		local difficulty = difficulties[i] or "easy"
		local pool = eligibleForBucket(self, profile, category, difficulty, context)
		-- Fallback chain so a slot is NEVER empty when the category has
		-- *any* eligible template:
		--   1. (category, difficulty) bucket
		--   2. same category, any difficulty (e.g. fishing_catch_demand
		--      gated out of the hard-fishing slot → fishing_perfect_n or
		--      any other eligible fishing template fills it instead)
		-- Only if the whole category is unrollable (trigger missing) does
		-- the slot get skipped — a deliberate "Phase 3 plumbing missing"
		-- signal, not silent breakage.
		if #pool == 0 then
			for _, tpl in ipairs(QuestTemplates.All) do
				if tpl.category == category and isTemplateEligible(self, tpl, profile, context) then
					table.insert(pool, tpl)
				end
			end
		end
		if #pool == 0 then
			continue
		end
		local pick = pool[rng:NextInteger(1, #pool)]
		local q = buildQuestFromTemplate(rng, pick, profile, utcDay, difficulty, context)
		if q then table.insert(quests, q) end
	end
	return quests
end

-- ====================================================================
-- ROLLOVER LOGIC
-- ====================================================================
-- Called when questsRefreshedDay != currentUTCDay (profile load or
-- midnight tick). Moves completed-unclaimed → yesterdayQuests, drops
-- incomplete, then rolls a fresh set.
function QuestService:_rolloverAndRoll(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end

	local today = TimeUtil.currentUTCDay()
	-- Detect schema drift: pre-rewrite quests lack templateId. If any
	-- quest in the bag is on the old shape, force a re-roll so the
	-- player isn't stuck with quests that never advance.
	local hasOldShape = false
	for _, q in ipairs(data.dailyQuests or {}) do
		if not q.templateId then hasOldShape = true; break end
	end
	if data.questsRefreshedDay == today and #data.dailyQuests > 0 and not hasOldShape then
		return -- already current
	end

	-- Move completed-unclaimed → yesterday. Drop incomplete.
	local yesterday: {Quest} = {}
	for _, q in ipairs(data.dailyQuests or {}) do
		if q.completed and not q.claimed then
			table.insert(yesterday, q)
		end
	end
	data.yesterdayQuests = yesterday

	-- Roll new.
	local rolled = self:_rollDailySet(player, data)
	data.dailyQuests = rolled
	data.questsRefreshedDay = today
	self:_pushSnapshot(player)
end

-- ====================================================================
-- TUTORIAL SEED
-- ====================================================================
-- Builds the special tutorial quest. Called from AcceptFirstQuest. The
-- seeded quest replaces slot 1 of the daily set; slots 2/3 are normal
-- rolls. Bypasses the category rotation entirely so the tutorial doesn't
-- depend on what day it is.
function QuestService:_seedTutorialQuest(player: Player, profile: any): Quest
	local tpl = QuestTemplates.byId("tutorial_seed_catch5")
		or error("tutorial_seed_catch5 template missing")
	local utcDay = TimeUtil.currentUTCDay()
	-- N is locked to the tutorial config value (not sampled). Build a
	-- deterministic params table and reuse buildQuestFromTemplate so the
	-- shape matches.
	local rng = seededRandom(player.UserId, utcDay)
	-- Empty context: the tutorial seed has no world-state dependency.
	local q = buildQuestFromTemplate(rng, tpl, profile, utcDay, "tutorial", {})
		or error("failed to build tutorial seed quest")
	-- Override sampled N with the tutorial config value (the template's
	-- min/max are both 5 today but make the source-of-truth explicit).
	q.params.N = GameConfig.Tutorial.FirstQuestTarget
	q.target = GameConfig.Tutorial.FirstQuestTarget
	q.renderedText = QuestService.RenderQuestText(tpl, q.params)
	return q
end

-- ====================================================================
-- TUTORIAL HANDOFF (client-callable) — unchanged contract from v1
-- ====================================================================
function QuestService.Client:AcceptFirstQuest(player: Player): {ok: boolean, reason: string?, quests: any?}
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	local tutorial = data.tutorial
	if not tutorial then return { ok = false, reason = "no_tutorial" } end
	if tutorial.state == "complete" then
		return { ok = false, reason = "already_complete" }
	end
	if tutorial.state ~= "daily_quest_hook" then
		return { ok = false, reason = "wrong_beat", quests = data.dailyQuests }
	end

	-- Build the daily set: tutorial seed + (DailyCount-1) normal rolls.
	-- Normal rolls happen against the seeded RNG so the same player on the
	-- same day gets the same supporting quests.
	local quests: {Quest} = { self:_seedTutorialQuest(player, data) }
	local utcDay = TimeUtil.currentUTCDay()
	local rotation = GameConfig.Quests.CategoryRotation[utcWeekdayMonStart(utcDay)]
		or GameConfig.Quests.CategoryRotation[1]
	local difficulties = GameConfig.Quests.DifficultyDistribution
	local rng = seededRandom(player.UserId, utcDay)
	local context = self:_buildRollContext()
	-- Burn the first sample so the seeded quest doesn't get its supporting
	-- quests with the same RNG state.
	rng:NextNumber()
	for i = 2, GameConfig.Quests.DailyCount do
		local cat = rotation[i] or rotation[#rotation]
		local diff = difficulties[i] or "easy"
		local pool = eligibleForBucket(self, data, cat, diff, context)
		if #pool == 0 then
			for _, tpl in ipairs(QuestTemplates.All) do
				if tpl.category == cat and isTemplateEligible(self, tpl, data, context) then
					table.insert(pool, tpl)
				end
			end
		end
		if #pool > 0 then
			local pick = pool[rng:NextInteger(1, #pool)]
			local q = buildQuestFromTemplate(rng, pick, data, utcDay, diff, context)
			if q then table.insert(quests, q) end
		end
	end

	data.dailyQuests = quests
	data.yesterdayQuests = {}
	data.questsRefreshedDay = utcDay
	self:_pushSnapshot(player)

	-- Hand control back to TutorialService to flip state -> "complete".
	tutorial.seededQuestId = quests[1].id
	local TutorialService = Knit.GetService("TutorialService")
	TutorialService:CompleteFromQuestAccept(player)

	return { ok = true, quests = self:_publicSnapshot(data) }
end

-- ====================================================================
-- EVENT ROUTING
-- ====================================================================
-- For each player's active quests, look up the template, run matchFn,
-- then progressFn. Marks completion + pushes snapshot.
function QuestService:_applyEvent(player: Player, trigger: string, event: any)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	if not data.dailyQuests or #data.dailyQuests == 0 then return end

	local changed = false
	local completedSomething = false
	for _, q in ipairs(data.dailyQuests) do
		if q.completed then continue end
		local tpl = QuestTemplates.byId(q.templateId)
		if not tpl then continue end
		if tpl.trigger ~= trigger then continue end
		if not tpl.matchFn(event, q.params, data) then continue end

		-- Uniqueness gates for the few templates that need them. We do
		-- this here (rather than inside progressFn) so the dedup set
		-- lives on the persisted progressState.
		q.progressState = q.progressState or {}
		if tpl.id == "social_emote_n" then
			q.progressState.emotes = q.progressState.emotes or {}
			if q.progressState.emotes[event.emoteId] then
				event._isNewEmote = false
			else
				q.progressState.emotes[event.emoteId] = true
				event._isNewEmote = true
			end
		elseif tpl.id == "exploration_biomes_visited" then
			local biome = event.biome
			if biome then
				q.progressState.biomes = q.progressState.biomes or {}
				if q.progressState.biomes[biome] then
					event._isNewBiome = false
				else
					q.progressState.biomes[biome] = true
					event._isNewBiome = true
				end
			end
		elseif tpl.id == "exploration_tides" then
			q.progressState.tides = q.progressState.tides or {}
			if q.progressState.tides[event.tide] then
				event._isNewTide = false
			else
				q.progressState.tides[event.tide] = true
				event._isNewTide = true
			end
		elseif tpl.id == "exploration_full_day" then
			q.progressState.windows = q.progressState.windows or {}
			if q.progressState.windows[event.timeOfDay] then
				event._isNewTimeWindow = false
			else
				q.progressState.windows[event.timeOfDay] = true
				event._isNewTimeWindow = true
			end
		end

		local newProgress, target = tpl.progressFn(event, q.params, q.progress)
		if newProgress ~= q.progress then
			q.progress = math.min(newProgress, target)
			q.target = target
			changed = true
			if q.progress >= q.target then
				q.completed = true
				completedSomething = true
				self.Client.QuestCompleted:Fire(player, q.id)
				self.Client.QuestCompletedToast:Fire(player, {
					questId = q.id,
					renderedText = q.renderedText or "",
				})
			end
		end
	end

	if completedSomething then
		-- Completion must feel instant: the card flip + Claim button need
		-- to land in sync with the QuestCompleted popup. Cancel any pending
		-- coalesced push and snapshot now.
		local pending = self._persistTimers[player]
		if pending then task.cancel(pending); self._persistTimers[player] = nil end
		self:_pushSnapshot(player)
	elseif changed then
		self:_schedulePersist(player)
	end
end

-- Coalesce snapshot pushes so a player catching one fish per second
-- doesn't blast QuestsChanged 60 times a minute — but keep the window
-- short so the progress bar still feels live. This is a *network-push*
-- coalescer only: the profile table is already mutated in memory, and
-- ProfileService owns the actual DataStore autosave, so there is no
-- DataStore thrash to guard against here. (The old 5s value made the
-- tracker feel laggy for zero persistence benefit.)
function QuestService:_schedulePersist(player: Player)
	if self._persistTimers[player] then return end  -- already scheduled
	self._persistTimers[player] = task.delay(GameConfig.Quests.SnapshotPushDebounceSeconds, function()
		self._persistTimers[player] = nil
		self:_pushSnapshot(player)
	end)
end

-- ====================================================================
-- EVENT BUILDERS — turn signal payloads into typed event tables
-- ====================================================================
-- Helper: pick the "primary" biome for a fish. For multi-biome species
-- we use the first biome in the catalog entry as a stable proxy. Long
-- term this should come from the cast position; v1 keeps it data-driven.
local function primaryBiomeFor(fish: any): string?
	if not fish or not fish.biomes then return nil end
	return fish.biomes[1]
end

function QuestService:_buildFishCaughtEvent(fish: any, weightKg: number, isPerfect: boolean): any
	local WeatherService = Knit.GetService("WeatherService")
	local TideService    = Knit.GetService("TideService")
	return {
		fish = fish,
		weightKg = weightKg,
		isPerfect = isPerfect,
		weather = WeatherService:GetWeather(),
		timeOfDay = WeatherService:GetTimeOfDay(),
		tide = TideService:GetTide(),
		biome = primaryBiomeFor(fish),
	}
end

-- ====================================================================
-- LOGIN STREAK
-- ====================================================================
local function rewardForStreakDay(day: number): any?
	local rewards = GameConfig.Quests.LoginStreakRewards
	local direct = rewards[day]
	if direct then return direct end
	if day > 28 then
		return GameConfig.Quests.LoginStreakReward28Plus
	end
	-- Mid-cycle days without an explicit reward (8-13, 15-20, 22-27) fall
	-- back to the corresponding 1-7 reward (day 8 → day 1, day 15 → day 1, etc.).
	local cycleDay = ((day - 1) % 7) + 1
	return rewards[cycleDay]
end

function QuestService:_grantRewards(player: Player, reward: any)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	if reward.coins and reward.coins > 0 then
		PlayerDataService:AddCoins(player, reward.coins, "quest_or_streak")
	end
	if reward.xp and reward.xp > 0 then
		PlayerDataService:AddXP(player, reward.xp)
	end
	if reward.lureTokens and reward.lureTokens > 0 then
		PlayerDataService:AddLureTokens(player, reward.lureTokens)
	end
	if reward.items then
		for _, it in ipairs(reward.items) do
			PlayerDataService:AddItem(player, {
				uid = UidUtil.new("good"),
				kind = "Good",
				goodId = it.id,
				count = it.count or 1,
			})
		end
	end
end

function QuestService:_handleLoginStreak(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local streak = data.streak
	if not streak then
		streak = { current = 0, longest = 0, lastLoginUtcDay = nil, weekStartedAt = 0 }
		data.streak = streak
	end

	local today = TimeUtil.currentUTCDay()
	if streak.lastLoginUtcDay == today then return end  -- already credited

	if streak.lastLoginUtcDay and TimeUtil.isConsecutiveUTCDay(streak.lastLoginUtcDay, today) then
		streak.current += 1
	else
		-- Streak reset: check for welcome-back eligibility before zeroing.
		if streak.lastLoginUtcDay then
			local daysAway = TimeUtil.daysBetween(streak.lastLoginUtcDay, today)
			if daysAway >= GameConfig.Quests.WelcomeBackThresholdDays then
				local bonus = GameConfig.Quests.WelcomeBackCoins
				PlayerDataService:AddCoins(player, bonus, "welcome_back")
				self.Client.WelcomeBack:Fire(player, { daysAway = daysAway, coinsGranted = bonus })
			end
		end
		streak.current = 1
		streak.weekStartedAt = os.time()
	end
	if streak.current > streak.longest then streak.longest = streak.current end
	streak.lastLoginUtcDay = today

	if table.find(GameConfig.Quests.StreakMilestoneToastDays, streak.current) then
		self.Client.StreakMilestone:Fire(player, { day = streak.current })
	end

	local reward = rewardForStreakDay(streak.current)
	if reward then
		self:_grantRewards(player, reward)
		self.Client.StreakAdvanced:Fire(player, streak.current, reward)
	end
end

-- ====================================================================
-- CLAIM
-- ====================================================================
function QuestService.Client:Claim(player: Player, questId: string): {ok: boolean, reason: string?, reward: any?}
	local self = self.Server
	if not self._claimLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	if typeof(questId) ~= "string" or #questId == 0 or #questId > 64 then
		return { ok = false, reason = "bad_quest_id" }
	end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	-- Search today's quests first.
	local function tryClaim(list: {Quest}, fromYesterday: boolean): ({ok: boolean, reason: string?, reward: any?})?
		for _, q in ipairs(list) do
			if q.id ~= questId then continue end
			if not q.completed then return { ok = false, reason = "not_completed" } end
			if q.claimed then return { ok = false, reason = "already_claimed" } end
			if fromYesterday and os.time() > q.expiresAt then
				return { ok = false, reason = "expired" }
			end
			q.claimed = true
			self:_grantRewards(player, q.reward)
			self:_pushSnapshot(player)
			return { ok = true, reward = q.reward }
		end
		return nil
	end

	local result = tryClaim(data.dailyQuests or {}, false)
	if result then return result end
	result = tryClaim(data.yesterdayQuests or {}, true)
	if result then return result end
	return { ok = false, reason = "not_found" }
end

-- ====================================================================
-- SNAPSHOT
-- ====================================================================
function QuestService:_publicSnapshot(data: any): any
	return {
		today = data.dailyQuests or {},
		yesterday = data.yesterdayQuests or {},
		streak = data.streak or { current = 0, longest = 0, lastLoginUtcDay = nil, weekStartedAt = 0 },
		-- Server epoch seconds at which the daily refresh fires.
		refreshesAt = os.time() + TimeUtil.secondsUntilUTCMidnight(),
	}
end

function QuestService:_pushSnapshot(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	-- Keep the legacy QuestsChanged signal firing too — older HUD/UI may
	-- still listen on the simpler dailyQuests-only payload.
	PlayerDataService.Client.QuestsChanged:Fire(player, data.dailyQuests)
	self.Client.QuestsRefreshed:Fire(player, self:_publicSnapshot(data))
end

-- Client snapshot pull (UI re-init).
function QuestService.Client:GetSnapshot(player: Player): any?
	local data = Knit.GetService("PlayerDataService"):GetProfile(player)
	if not data then return nil end
	return QuestService:_publicSnapshot(data)
end

-- ====================================================================
-- YESTERDAY GRACE EXPIRY
-- ====================================================================
-- Wipe expired yesterday quests. Called from the periodic tick.
function QuestService:_pruneExpiredYesterday(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.yesterdayQuests then return end
	if #data.yesterdayQuests == 0 then return end
	local now = os.time()
	local kept: {Quest} = {}
	for _, q in ipairs(data.yesterdayQuests) do
		if now <= q.expiresAt then table.insert(kept, q) end
	end
	if #kept ~= #data.yesterdayQuests then
		data.yesterdayQuests = kept
		self:_pushSnapshot(player)
	end
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function QuestService:KnitStart()
	-- Silent-drop limiter on the reward-granting Claim path. Tuned generously
	-- so honest play never trips (3 dailies + grace = peak ~6/min in any
	-- realistic scenario).
	self._claimLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxQuestClaimsPerMinute, 60)

	-- Detect which signals are available; warn on missing.
	self._availableTriggers = detectAvailableTriggers()
	for _, tpl in ipairs(QuestTemplates.All) do
		if tpl.excludeFromRoll or tpl.deprecated then continue end
		if not self._availableTriggers[tpl.trigger] then
			warn(string.format(
				"[QuestService] Template '%s' requires trigger '%s' which is not available. Template will not roll.",
				tpl.id, tpl.trigger
			))
		end
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local FishingService    = Knit.GetService("FishingService")
	local MarketService     = Knit.GetService("MarketService")
	local HarborService     = Knit.GetService("HarborService")
	local SocialService     = Knit.GetService("SocialService")

	-- ----------------- player lifecycle -----------------
	local function onJoin(player: Player)
		local data = PlayerDataService:WaitForProfile(player, 30); if not data then return end
		-- Heal pre-rewrite profiles that still have the v1 streak/lastLogin
		-- layout. Pre-launch only; once the v1 layout is wiped this branch
		-- becomes dead code.
		if not data.streak then
			data.streak = { current = 0, longest = 0, lastLoginUtcDay = nil, weekStartedAt = 0 }
		end
		if not data.yesterdayQuests then
			data.yesterdayQuests = {}
		end
		self:_handleLoginStreak(player)
		self:_rolloverAndRoll(player)
		self:_pushSnapshot(player)

		local MarketService2 = Knit.GetService("MarketService")
		MarketService2:SettlePendingPayouts(player)
		MarketService2:SettleExpiredListings(player)
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local handle = self._persistTimers[player]
		if handle then task.cancel(handle) end
		self._persistTimers[player] = nil
		self._claimLimiter:reset(player)
	end)

	-- ----------------- signal listeners -----------------
	if self._availableTriggers.FishCaught then
		FishingService.CaughtServer:Connect(function(player, fish, weightKg, isPerfect)
			local event = self:_buildFishCaughtEvent(fish, weightKg, isPerfect)
			self:_applyEvent(player, "FishCaught", event)
		end)
	end
	if self._availableTriggers.Sold then
		MarketService.SoldServer:Connect(function(player, payout, channel)
			-- Map "quick"|"market" → "dock"|"global" for templates that care.
			local mapped = channel == "quick" and "dock" or "global"
			self:_applyEvent(player, "Sold", { payout = payout, channel = mapped })
		end)
	end
	if self._availableTriggers.Listed then
		MarketService.ListedServer:Connect(function(player, listing)
			self:_applyEvent(player, "Listed", { listing = listing })
		end)
	end
	if self._availableTriggers.Bought then
		MarketService.BoughtServer:Connect(function(player, listing)
			self:_applyEvent(player, "Bought", { listing = listing })
		end)
	end
	if self._availableTriggers.BuildingUpgraded then
		HarborService.BuildingUpgradedServer.Event:Connect(function(player, building, oldTier, newTier)
			self:_applyEvent(player, "BuildingUpgraded", { kind = building.kind, oldTier = oldTier, newTier = newTier })
		end)
	end
	if self._availableTriggers.BuildingPlaced then
		HarborService.BuildingPlacedServer.Event:Connect(function(player, building)
			self:_applyEvent(player, "BuildingPlaced", { building = building, isDecorative = false })
		end)
	end
	if self._availableTriggers.PassiveIncome then
		HarborService.PassiveIncomeServer.Event:Connect(function(player, coinsGranted)
			self:_applyEvent(player, "PassiveIncome", { coinsGranted = coinsGranted })
		end)
	end
	if self._availableTriggers.HarborVisited then
		SocialService.HarborVisitedServer:Connect(function(visitor, hostUserId)
			-- Inject the visitor's UserId so the template's matchFn can
			-- skip self-visits without needing access to the Player object.
			self:_applyEvent(visitor, "HarborVisited", {
				hostUserId = hostUserId,
				visitorUserId = visitor.UserId,
			})
		end)
	end
	if self._availableTriggers.EmoteUsed then
		SocialService.EmoteUsedServer:Connect(function(player, emoteId)
			self:_applyEvent(player, "EmoteUsed", { emoteId = emoteId })
		end)
	end

	-- ----------------- midnight scheduler -----------------
	-- Two responsibilities: (a) re-roll everyone's quests just after UTC
	-- midnight; (b) prune expired yesterday-grace quests.
	task.spawn(function()
		while true do
			local secs = TimeUtil.secondsUntilUTCMidnight()
			task.wait(secs + 5)  -- +5s slack so we're firmly in the new UTC day
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(function()
					self:_rolloverAndRoll(player)
				end)
			end
		end
	end)
	-- Per-minute pruning + safety re-check (covers profile-load races and
	-- straddle-midnight players we somehow missed).
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				self:_rolloverAndRoll(player)
				self:_pruneExpiredYesterday(player)
			end
		end
	end)
end

return QuestService
