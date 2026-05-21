--!strict
-- QuestTemplates.lua
-- The shape-pool for daily quests. Each template is a *shape* that the
-- daily roll fills in with concrete parameters. Service logic (sampling,
-- progress, claiming) lives in QuestService; this file is data + small
-- pure functions only so designers can add quests without touching
-- service code.
--
-- IMPORTANT — Stable IDs
-- ----------------------
-- A template's `id` is FOREVER once shipped. It lands in player profiles
-- (Quest.templateId) and stays there until the quest expires. Never
-- rename an id. To retire a template, mark it with `deprecated = true`
-- so the daily roll skips it but existing in-flight quests still resolve
-- against their stored shape.
--
-- Adding a new template
-- ---------------------
-- 1. Pick a stable id with the convention `<category>_<verb>_<modifier>`.
-- 2. Drop it in the table below.
-- 3. Make sure the `trigger` signal exists in services/. If it doesn't,
--    QuestService will warn at boot and the template won't roll. That's
--    intentional — we don't ship quests players can't complete.
--
-- Parameter types
-- ---------------
-- `int`             — math.random(min, max)
-- `float`           — uniform in [min, max]
-- `weighted_pick`   — one of `options` by weight. Each option has
--                     {value, weight, displayName}.
-- `pick`            — one of `options` uniformly. `options` is a list of
--                     {value, displayName}.
--
-- matchFn / progressFn / rewardFormula are all pure functions of their
-- inputs. They run on the server hot path per fish/sale/etc. Keep them
-- O(1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)
local GameConfig  = require(ReplicatedStorage.Shared.Config.GameConfig)

export type ParameterDef = {
	type: string,                -- "int" | "float" | "weighted_pick" | "pick"
	min: number?,
	max: number?,
	options: {any}?,
}

-- World-state snapshot handed to canRollForToday. Built once per daily
-- roll by QuestService. Only carries state that is *stable for the whole
-- UTC day* — demand spike, etc. Intra-day state (weather, tide, time of
-- day) is deliberately excluded: a quest rolled at midnight must not
-- depend on what the weather happened to be at midnight.
export type RollContext = {
	demandSpeciesId: string?,    -- today's demand spike species id, if rolled
	demandFish: any?,            -- full FishCatalog entry for the demand species
}

export type Template = {
	id: string,
	category: string,            -- "fishing" | "market" | "social" | "building" | "exploration"
	difficulty: string,          -- "easy" | "medium" | "hard" | "tutorial"
	textTemplate: string,
	parameters: {[string]: ParameterDef},
	trigger: string,             -- signal name advancing this quest
	-- Whether this template is excluded from the normal daily roll. The
	-- tutorial seed is the only such template today.
	excludeFromRoll: boolean?,
	deprecated: boolean?,
	-- Pure functions. Receive the event payload + rolled params; return
	-- whether the event counts and how much progress to add.
	matchFn: (event: any, params: any, profile: any?) -> boolean,
	progressFn: (event: any, params: any, currentProgress: number) -> (number, number),  -- newProgress, target
	-- Reward shape (Types.QuestReward) for this roll. Uses the difficulty
	-- band from GameConfig.Quests.DifficultyRewardScale to derive coins/xp.
	rewardFormula: (params: any, difficulty: string) -> any,
	-- Optional gate keyed on the *player*: returns false if this player
	-- can't roll this template (no crew, doesn't own a Smokehouse, etc.).
	-- Absent → always player-eligible.
	canRollFor: ((profile: any) -> boolean)?,
	-- Optional gate keyed on *world state* (RollContext): returns false
	-- if today's world doesn't support this template — e.g. the demand
	-- species is too tightly gated to be a fair daily. Absent → always
	-- world-eligible. This is the one place world-state eligibility logic
	-- lives; QuestService just calls it, no per-template special cases.
	canRollForToday: ((context: RollContext) -> boolean)?,
}

local QuestTemplates = {}

-- ====================================================================
-- HELPERS
-- ====================================================================

-- Coin/XP from the difficulty band, scaled by `n` (param magnitude).
-- Easy quests want ~5min completion: a "catch 5" should be ~easy.coinsMin.
-- Hard quests want ~45min: a "catch 30" should hit ~hard.coinsMax.
local function bandReward(difficulty: string, scale: number): {coins: number, xp: number}
	local band = GameConfig.Quests.DifficultyRewardScale[difficulty]
		or GameConfig.Quests.DifficultyRewardScale.easy
	local coins = math.floor(band.coinsMin + (band.coinsMax - band.coinsMin) * math.clamp(scale, 0, 1))
	local xp    = math.floor(band.xpMin    + (band.xpMax    - band.xpMin)    * math.clamp(scale, 0, 1))
	return { coins = coins, xp = xp }
end

local function fishByRarity(rarity: string): {string}
	local out = {}
	for _, f in ipairs(FishCatalog.fish) do
		if f.rarity == rarity then table.insert(out, f.id) end
	end
	return out
end

-- Lookup a species' biomes — used by canRollFor on biome templates to
-- avoid rolling biomes that have no fish at all.
local function biomeHasFish(biomeId: string): boolean
	for _, f in ipairs(FishCatalog.fish) do
		for _, b in ipairs(f.biomes) do
			if b == biomeId then return true end
		end
	end
	return false
end

-- ====================================================================
-- FISHING TEMPLATES (7)
-- ====================================================================

QuestTemplates.fishing_catch_n = {
	id = "fishing_catch_n",
	category = "fishing",
	difficulty = "easy",  -- difficulty is fluid: same template rolls easy/medium/hard via params
	textTemplate = "Catch {N} {rarityName} fish",
	parameters = {
		N = { type = "int", min = 3, max = 18 },
		rarity = {
			type = "weighted_pick",
			options = {
				{ value = "Common",   weight = 60, displayName = "common" },
				{ value = "Uncommon", weight = 30, displayName = "uncommon" },
				{ value = "Rare",     weight = 10, displayName = "rare" },
			},
		},
	},
	trigger = "FishCaught",
	matchFn = function(event, params, _profile)
		return event.fish and event.fish.rarity == params.rarity
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		-- Heavier reward for rarer fish via the band, scaled by N.
		local nScale = math.clamp((params.N - 3) / 15, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.fishing_catch_biome = {
	id = "fishing_catch_biome",
	category = "fishing",
	difficulty = "easy",
	textTemplate = "Catch {N} fish from the {biomeName}",
	parameters = {
		N = { type = "int", min = 4, max = 12 },
		biome = {
			type = "pick",
			options = {
				{ value = "Shoreline", displayName = "Shoreline" },
				{ value = "Pier",      displayName = "Pier" },
				{ value = "Reef",      displayName = "Reef" },
				-- DeepWater / Trench gated by rod tier — only roll if the
				-- player owns the rod to fish them. canRollFor below.
			},
		},
	},
	trigger = "FishCaught",
	matchFn = function(event, params, _profile)
		if not event.fish then return false end
		for _, b in ipairs(event.fish.biomes) do
			if b == params.biome then return true end
		end
		return false
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 4) / 10, 0, 1)
		return bandReward(difficulty, nScale)
	end,
	canRollFor = function(_profile)
		return biomeHasFish("Shoreline")  -- always true; safety check for catalog churn
	end,
} :: Template

QuestTemplates.fishing_catch_weight = {
	id = "fishing_catch_weight",
	category = "fishing",
	difficulty = "medium",
	textTemplate = "Catch a fish weighing {weight}kg or more",
	parameters = {
		weight = { type = "float", min = 2.0, max = 6.5 },
	},
	trigger = "FishCaught",
	matchFn = function(event, params, _profile)
		return (event.weightKg or 0) >= params.weight
	end,
	progressFn = function(_event, _params, _currentProgress)
		return 1, 1   -- one big catch completes
	end,
	rewardFormula = function(params, difficulty)
		-- Heavier target = harder; scale across the 2..6.5 range.
		local wScale = math.clamp((params.weight - 2.0) / 4.5, 0, 1)
		return bandReward(difficulty, wScale)
	end,
} :: Template

QuestTemplates.fishing_catch_window = {
	id = "fishing_catch_window",
	category = "fishing",
	difficulty = "medium",
	textTemplate = "Catch {N} fish during the {timeWindowName}",
	parameters = {
		N = { type = "int", min = 5, max = 12 },
		timeWindow = {
			type = "pick",
			options = {
				{ value = "Morning", displayName = "Morning" },
				{ value = "Day",     displayName = "Day" },
				{ value = "Dusk",    displayName = "Dusk" },
				{ value = "Night",   displayName = "Night" },
			},
		},
	},
	trigger = "FishCaught",
	matchFn = function(event, params, _profile)
		return event.timeOfDay == params.timeWindow
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 5) / 7, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.fishing_catch_weather = {
	id = "fishing_catch_weather",
	category = "fishing",
	difficulty = "medium",
	textTemplate = "Catch {N} fish during {weatherName}",
	parameters = {
		N = { type = "int", min = 4, max = 10 },
		weather = {
			type = "pick",
			options = {
				-- Storm intentionally not on the easy list — rolls separately.
				{ value = "Clear",  displayName = "clear skies" },
				{ value = "Cloudy", displayName = "cloudy skies" },
				{ value = "Rain",   displayName = "the rain" },
				{ value = "Fog",    displayName = "the fog" },
			},
		},
	},
	trigger = "FishCaught",
	matchFn = function(event, params, _profile)
		return event.weather == params.weather
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 4) / 6, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.fishing_perfect_n = {
	id = "fishing_perfect_n",
	category = "fishing",
	difficulty = "hard",
	textTemplate = "Land {N} perfect catches",
	parameters = {
		N = { type = "int", min = 2, max = 5 },
	},
	trigger = "FishCaught",
	matchFn = function(event, _params, _profile)
		return event.isPerfect == true
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 2) / 3, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.fishing_catch_demand = {
	id = "fishing_catch_demand",
	category = "fishing",
	difficulty = "hard",
	-- displayName resolved at roll-time from the demand species.
	textTemplate = "Catch {N} {speciesName} (today's demand)",
	parameters = {
		N = { type = "int", min = 4, max = 10 },
		-- species is filled in at roll-time from TidesDemand_v1, not from a
		-- weighted_pick. QuestService injects it before the textTemplate
		-- substitution runs. If demand isn't rolled yet the template
		-- is skipped for the day.
	},
	trigger = "FishCaught",
	matchFn = function(event, params, _profile)
		return event.fish and event.fish.id == params.species
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 4) / 6, 0, 1)
		return bandReward(difficulty, nScale)
	end,
	-- World-state gate. The species param is injected from the demand
	-- spike at build-time, so we must not roll this unless:
	--   1. A demand species is actually rolled (early-startup edge case), AND
	--   2. It's broadly catchable — Common/Uncommon rarity with at least
	--      two biome windows AND two time-of-day windows. This protects
	--      against the "Catch 8 Ghost Pipefish" case where a tightly-gated
	--      species (single biome + Fog-only + rod-tier-2) becomes an
	--      uncompletable cozy-session daily. Tune the thresholds here, not
	--      in QuestService.
	canRollForToday = function(context)
		local fish = context.demandFish
		if not context.demandSpeciesId or not fish then return false end
		if fish.rarity ~= "Common" and fish.rarity ~= "Uncommon" then return false end
		if not fish.biomes or #fish.biomes < 2 then return false end
		if not fish.timeOfDay or #fish.timeOfDay < 2 then return false end
		return true
	end,
} :: Template

-- ====================================================================
-- MARKET TEMPLATES (4)
-- ====================================================================

QuestTemplates.market_sell_n = {
	id = "market_sell_n",
	category = "market",
	difficulty = "easy",
	textTemplate = "Sell {N} items at the dock or market",
	parameters = {
		N = { type = "int", min = 3, max = 10 },
	},
	trigger = "Sold",
	matchFn = function(_event, _params, _profile)
		return true   -- any sale counts
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 3) / 7, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.market_sell_value = {
	id = "market_sell_value",
	category = "market",
	difficulty = "medium",
	textTemplate = "Earn {coins} coins from sales",
	parameters = {
		coins = { type = "int", min = 200, max = 1500 },
	},
	trigger = "Sold",
	matchFn = function(_event, _params, _profile)
		return true
	end,
	progressFn = function(event, params, currentProgress)
		local p = currentProgress + (event.payout or 0)
		return p, params.coins
	end,
	rewardFormula = function(params, difficulty)
		local cScale = math.clamp((params.coins - 200) / 1300, 0, 1)
		return bandReward(difficulty, cScale)
	end,
} :: Template

QuestTemplates.market_list_n = {
	id = "market_list_n",
	category = "market",
	difficulty = "easy",
	textTemplate = "List {N} items on the global market",
	parameters = {
		N = { type = "int", min = 1, max = 5 },
	},
	trigger = "Listed",
	matchFn = function(_event, _params, _profile)
		return true
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 1) / 4, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.market_buy_n = {
	id = "market_buy_n",
	category = "market",
	difficulty = "medium",
	textTemplate = "Buy {N} items from the global market",
	parameters = {
		N = { type = "int", min = 1, max = 3 },
	},
	trigger = "Bought",
	matchFn = function(_event, _params, _profile)
		return true
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 1) / 2, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

-- ====================================================================
-- SOCIAL TEMPLATES (2)
-- ====================================================================
-- Note: `social_gift_tip` and `social_crew_progress` were specced but
-- removed per design call — tipping flow and crew weekly quests don't
-- exist yet. Re-add when those systems land (see Phase 3 tasks).

QuestTemplates.social_visit_harbors = {
	id = "social_visit_harbors",
	category = "social",
	difficulty = "easy",
	textTemplate = "Visit {N} other players' harbors",
	parameters = {
		N = { type = "int", min = 1, max = 3 },
	},
	trigger = "HarborVisited",
	matchFn = function(event, _params, _profile)
		-- Visits to your own plot don't count. QuestService injects
		-- visitorUserId into the event; profile has no UserId field.
		return event.hostUserId ~= nil and event.hostUserId ~= event.visitorUserId
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 1) / 2, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.social_emote_n = {
	id = "social_emote_n",
	category = "social",
	difficulty = "easy",
	textTemplate = "Use {N} different emotes",
	parameters = {
		N = { type = "int", min = 2, max = 4 },
	},
	trigger = "EmoteUsed",
	matchFn = function(_event, _params, _profile)
		return true
	end,
	-- Progress tracks UNIQUE emoteIds — we stash a set on the quest's
	-- progressState side-table (mutated through QuestService since the
	-- progress integer alone can't represent uniqueness).
	progressFn = function(event, params, currentProgress)
		-- QuestService recognises `_uniqueEmotes` and dedupes there.
		-- Here we just emit "candidate" progress; service uses event.emoteId
		-- to dedupe before applying.
		if event._isNewEmote == false then
			return currentProgress, params.N
		end
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 2) / 2, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

-- ====================================================================
-- BUILDING TEMPLATES (2) — building_decorate_n dropped, see TODO below
-- ====================================================================

QuestTemplates.building_upgrade_any = {
	id = "building_upgrade_any",
	category = "building",
	difficulty = "medium",
	textTemplate = "Upgrade any building by 1 tier",
	parameters = {},
	trigger = "BuildingUpgraded",
	matchFn = function(_event, _params, _profile)
		return true
	end,
	progressFn = function(_event, _params, _currentProgress)
		return 1, 1
	end,
	rewardFormula = function(_params, difficulty)
		return bandReward(difficulty, 0.5)
	end,
} :: Template

-- TODO(decorative-props): `building_decorate_n` was specced but DROPPED
-- until the decorative-props system exists. Reason: no decorative
-- buildings exist — the catalog is the 6 functional cores only — so the
-- template could only count *any* placement, which overlaps
-- building_upgrade_any and reads as a confusing duplicate. Same
-- treatment as the dropped social_gift_tip / social_crew_progress
-- templates. When the decorative-props feature lands (separate task):
-- add `isDecorative` to BuildingCatalog entries (lanterns/crates/buoys/
-- rope coils/fountains = true; Dock/MarketStall/Smokehouse/Lighthouse/
-- BaitShop/Guildhall = false), restore this template with
-- matchFn = function(event) return event.isDecorative == true end, and
-- re-add it to QuestTemplates.All. Stable id stays "building_decorate_n".
-- HarborService.BuildingPlacedServer already fires (player, building,
-- isDecorative) so the plumbing is ready; only the catalog flag + this
-- template are missing.

QuestTemplates.building_earn_passive = {
	id = "building_earn_passive",
	category = "building",
	difficulty = "hard",
	textTemplate = "Earn {coins} coins from passive building income",
	parameters = {
		coins = { type = "int", min = 150, max = 800 },
	},
	trigger = "PassiveIncome",
	matchFn = function(_event, _params, _profile)
		return true
	end,
	progressFn = function(event, params, currentProgress)
		local p = currentProgress + (event.coinsGranted or 0)
		return p, params.coins
	end,
	rewardFormula = function(params, difficulty)
		local cScale = math.clamp((params.coins - 150) / 650, 0, 1)
		return bandReward(difficulty, cScale)
	end,
} :: Template

-- ====================================================================
-- EXPLORATION TEMPLATES (3)
-- ====================================================================

QuestTemplates.exploration_biomes_visited = {
	id = "exploration_biomes_visited",
	category = "exploration",
	difficulty = "medium",
	textTemplate = "Fish in {N} different biomes",
	parameters = {
		N = { type = "int", min = 2, max = 3 },
	},
	trigger = "FishCaught",
	-- Progress increments only when the caught fish's primary biome (the
	-- biome the player is fishing FROM, which the server picks the closest
	-- biome to the cast position — for v1 we use the fish's first biome
	-- entry as a proxy) hasn't been seen yet today.
	matchFn = function(event, _params, _profile)
		return event.fish ~= nil
	end,
	progressFn = function(event, params, currentProgress)
		if event._isNewBiome == false then return currentProgress, params.N end
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(params, difficulty)
		local nScale = math.clamp((params.N - 2) / 1, 0, 1)
		return bandReward(difficulty, nScale)
	end,
} :: Template

QuestTemplates.exploration_tides = {
	id = "exploration_tides",
	category = "exploration",
	difficulty = "medium",
	textTemplate = "Catch fish during {N} different tide states",
	parameters = {
		N = { type = "int", min = 2, max = 2 },  -- only high/low exist; max is 2
	},
	trigger = "FishCaught",
	matchFn = function(event, _params, _profile)
		return event.tide == "High" or event.tide == "Low"
	end,
	progressFn = function(event, params, currentProgress)
		if event._isNewTide == false then return currentProgress, params.N end
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(_params, difficulty)
		return bandReward(difficulty, 0.5)
	end,
} :: Template

QuestTemplates.exploration_full_day = {
	id = "exploration_full_day",
	category = "exploration",
	difficulty = "hard",
	textTemplate = "Catch fish during all 4 time windows in one day",
	parameters = {},  -- target is always 4
	trigger = "FishCaught",
	matchFn = function(event, _params, _profile)
		return event.timeOfDay ~= nil
	end,
	progressFn = function(event, _params, currentProgress)
		if event._isNewTimeWindow == false then return currentProgress, 4 end
		return currentProgress + 1, 4
	end,
	rewardFormula = function(_params, difficulty)
		return bandReward(difficulty, 1.0)
	end,
} :: Template

-- ====================================================================
-- TUTORIAL SEED — NEVER ROLLS via the normal daily roll
-- ====================================================================
-- Used exactly once: when the player accepts the beat-6 quest at the end
-- of the tutorial. The seeded quest becomes one of the 3 daily quest
-- slots for that one day; next day's refresh runs the normal rotation.
QuestTemplates.tutorial_seed_catch5 = {
	id = "tutorial_seed_catch5",
	category = "fishing",
	difficulty = "tutorial",
	textTemplate = "Catch {N} fish (welcome aboard!)",
	parameters = {
		-- N is locked at GameConfig.Tutorial.FirstQuestTarget — the daily
		-- roll never samples this template, so the param is filled by
		-- QuestService:SeedTutorialQuest directly.
		N = { type = "int", min = 5, max = 5 },
	},
	trigger = "FishCaught",
	excludeFromRoll = true,
	matchFn = function(event, _params, _profile)
		return event.fish ~= nil
	end,
	progressFn = function(_event, params, currentProgress)
		return currentProgress + 1, params.N
	end,
	rewardFormula = function(_params, _difficulty)
		-- Locked to the tutorial config so a difficulty band tweak doesn't
		-- change the first-quest payout.
		return {
			coins = GameConfig.Tutorial.FirstQuestRewardCoins,
			xp = 40,
		}
	end,
} :: Template

-- ====================================================================
-- INDEX
-- ====================================================================
-- A flat list for iteration (sampling, validation). Order is *not*
-- meaningful — the daily roll uses category+difficulty buckets.
QuestTemplates.All = {
	-- fishing (7)
	QuestTemplates.fishing_catch_n,
	QuestTemplates.fishing_catch_biome,
	QuestTemplates.fishing_catch_weight,
	QuestTemplates.fishing_catch_window,
	QuestTemplates.fishing_catch_weather,
	QuestTemplates.fishing_perfect_n,
	QuestTemplates.fishing_catch_demand,
	-- market (4)
	QuestTemplates.market_sell_n,
	QuestTemplates.market_sell_value,
	QuestTemplates.market_list_n,
	QuestTemplates.market_buy_n,
	-- social (2)
	QuestTemplates.social_visit_harbors,
	QuestTemplates.social_emote_n,
	-- building (2) — building_decorate_n dropped until decorative-props
	-- system exists (see TODO above its former definition).
	QuestTemplates.building_upgrade_any,
	QuestTemplates.building_earn_passive,
	-- exploration (3)
	QuestTemplates.exploration_biomes_visited,
	QuestTemplates.exploration_tides,
	QuestTemplates.exploration_full_day,
	-- tutorial seed lives in the index for lookup-by-id but excludeFromRoll
	-- keeps the daily roll from picking it.
	QuestTemplates.tutorial_seed_catch5,
}

-- Lookup helper used by QuestService for in-flight quests on profile load.
function QuestTemplates.byId(id: string): Template?
	for _, t in ipairs(QuestTemplates.All) do
		if t.id == id then return t end
	end
	return nil
end

return QuestTemplates
