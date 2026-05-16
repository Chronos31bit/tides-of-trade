--!strict
-- QuestService.lua
-- Daily quests + login streak rewards. Quests refresh at UTC midnight; the
-- server checks each player's questsRefreshedDay on login and re-rolls if
-- it doesn't match today. We also re-check every 60s in case a player stays
-- online across midnight.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types        = require(ReplicatedStorage.Shared.Types)
local UidUtil      = require(ReplicatedStorage.Shared.Util.UidUtil)
local TimeUtil     = require(ReplicatedStorage.Shared.Util.TimeUtil)
local FishCatalog  = require(ReplicatedStorage.Shared.Config.FishCatalog)

local QuestService = Knit.CreateService({
	Name = "QuestService",
	Client = {
		QuestsRefreshed = Knit.CreateSignal(), -- (quests)
		LoginReward     = Knit.CreateSignal(), -- (day, reward)
	},
})

-- ====================================================================
-- QUEST GENERATION
-- ====================================================================
-- A fish missing an explicit numeric rodMinTier is treated as tier 1 (kept
-- catchable for everyone). Matches RodTierUtil's defaulting rule.
local function fishTier(f: any): number
	local raw = f.rodMinTier
	if typeof(raw) == "number" and raw == raw and raw >= 1 then
		return math.floor(raw)
	end
	return 1
end

-- `profile` is required so CatchSpecies can only ever pick a species the
-- player's current rod can actually hook. Without this a tier-1 player could
-- be handed "catch 8 Lantern Squid" (rodMinTier 2) — an impossible daily.
local function rollQuest(profile: Types.Profile): Types.Quest
	local template = GameConfig.Quests.Templates[math.random(1, #GameConfig.Quests.Templates)]
	local target = math.random(template.targetMin, template.targetMax)
	local kind = template.kind
	local speciesId: string? = nil
	if kind == "CatchSpecies" then
		local rodTier = profile.rodTier or 1
		-- Eligible = catchable with the current rod AND low-rarity (the
		-- original cozy intent: never hand out a grindy Rare/Mythic-species
		-- daily). At tier 1 this is the Commons; tier 2+ adds the Uncommons.
		local pool = {}
		for _, f in ipairs(FishCatalog.fish) do
			if (f.rarity == "Common" or f.rarity == "Uncommon") and fishTier(f) <= rodTier then
				table.insert(pool, f.id)
			end
		end
		if #pool > 0 then
			speciesId = pool[math.random(1, #pool)]
		else
			-- Safety net: should be unreachable (Commons are all tier 1), but
			-- if the catalog ever changes such that no low-rarity species fits
			-- this rod, fall back to a guaranteed-completable any-fish quest
			-- rather than ship an impossible one.
			warn(("[QuestService] No tier<=%d low-rarity species for CatchSpecies roll; falling back to CatchAnyFish."):format(rodTier))
			kind = "CatchAnyFish"
		end
	end
	local today = TimeUtil.currentUTCDay()
	return {
		id = ("daily_%s_%s"):format(today, UidUtil.new()),
		kind = kind,
		target = target,
		progress = 0,
		speciesId = speciesId,
		rewardCoins = template.coins,
		rewardXp = template.xp,
		completed = false,
		claimed = false,
		expiresAt = os.time() + TimeUtil.secondsUntilUTCMidnight(),
	}
end

function QuestService:_refreshIfNeeded(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end

	-- Tutorial gate: no daily quests are rolled until the player completes
	-- the onboarding flow. AcceptFirstQuest is the explicit handoff. Pre-
	-- tutorial players still get an empty dailyQuests table; HUD shows
	-- "Loading…" until the handoff fires (acceptable since the tutorial UI
	-- is the only thing on screen during this period).
	local tutorial = data.tutorial
	if tutorial and tutorial.state ~= "complete" then
		return
	end

	local today = TimeUtil.currentUTCDay()
	if data.questsRefreshedDay == today and #data.dailyQuests > 0 then
		return -- already current
	end

	local quests = {}
	for _ = 1, GameConfig.Quests.DailyCount do
		table.insert(quests, rollQuest(data))
	end
	PlayerDataService:SetQuests(player, quests)
	self.Client.QuestsRefreshed:Fire(player, quests)
end

-- ====================================================================
-- TUTORIAL HANDOFF
-- ====================================================================
-- Called by TutorialController when the player presses Accept on the
-- seeded beat-6 quest. Server completes the tutorial state AND rolls the
-- normal daily set (3 quests). The seeded "catch 5 fish, 100 coins"
-- quest becomes one of those 3 — we replace one of the rolled
-- CatchAnyFish-style quests with the seeded one if any rolled, otherwise
-- append the seeded quest (still respecting DailyCount: we drop the last
-- rolled quest to keep the count fixed at 3).
function QuestService:_seedFirstQuest(): Types.Quest
	return {
		id = ("daily_seed_%s_%s"):format(TimeUtil.currentUTCDay(), UidUtil.new()),
		kind = "CatchAnyFish",
		target = GameConfig.Tutorial.FirstQuestTarget,
		progress = 0,
		speciesId = nil,
		rewardCoins = GameConfig.Tutorial.FirstQuestRewardCoins,
		rewardXp = 40,
		completed = false,
		claimed = false,
		expiresAt = os.time() + TimeUtil.secondsUntilUTCMidnight(),
	}
end

function QuestService.Client:AcceptFirstQuest(player: Player): {ok: boolean, reason: string?, quests: any?}
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	local tutorial = data.tutorial
	-- Defensive: only accept the handoff from the correct beat. Idempotent
	-- on double-fire (race between client retry and server timeout).
	if not tutorial then return { ok = false, reason = "no_tutorial" } end
	if tutorial.state == "complete" then
		return { ok = false, reason = "already_complete" }
	end
	if tutorial.state ~= "daily_quest_hook" then
		return { ok = false, reason = "wrong_beat", quests = data.dailyQuests }
	end

	-- Build the daily set with the seeded quest replacing one of the rolled
	-- ones. Roll DailyCount-1 random quests, then prepend the seed.
	local quests: {any} = { self:_seedFirstQuest() }
	for _ = 2, GameConfig.Quests.DailyCount do
		table.insert(quests, rollQuest(data))
	end
	PlayerDataService:SetQuests(player, quests)
	self.Client.QuestsRefreshed:Fire(player, quests)

	-- Hand control back to TutorialService to flip state -> "complete" and
	-- run despawn / cleanup. We don't mutate tutorial state from here so
	-- there's a single source of truth for "what's the tutorial doing now".
	local TutorialService = Knit.GetService("TutorialService")
	tutorial.seededQuestId = quests[1].id
	TutorialService:CompleteFromQuestAccept(player)

	return { ok = true, quests = quests }
end

-- ====================================================================
-- LOGIN STREAK
-- ====================================================================
function QuestService:_handleLoginStreak(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end

	local today = TimeUtil.currentUTCDay()
	if data.lastLoginDay == today then
		return -- already credited today
	end

	if data.lastLoginDay and TimeUtil.isConsecutiveUTCDay(data.lastLoginDay, today) then
		data.loginStreak += 1
	else
		data.loginStreak = 1 -- skipped a day or first ever login
	end
	data.lastLoginDay = today

	-- Day in cycle is ((streak-1) mod 7) + 1 so day 8 wraps to day 1, day 14 wraps too.
	local dayInCycle = ((data.loginStreak - 1) % 7) + 1
	local reward = GameConfig.LoginRewards[dayInCycle]
	if reward then
		if reward.kind == "Coins" then
			PlayerDataService:AddCoins(player, reward.amount, "login_streak")
		elseif reward.kind == "LureToken" then
			PlayerDataService:AddLureTokens(player, reward.amount)
		elseif reward.kind == "RareLure" then
			-- Day 7 guaranteed Rare lure — added to inventory as a Good.
			PlayerDataService:AddItem(player, {
				uid = UidUtil.new("good"),
				kind = "Good",
				goodId = "rare_lure",
				count = reward.amount,
			})
		end
		self.Client.LoginReward:Fire(player, dayInCycle, reward)
	end
end

-- ====================================================================
-- HOOKS — called by other services when relevant actions happen
-- ====================================================================

function QuestService:OnFishCaught(player: Player, speciesId: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local changed = false
	for _, q in ipairs(data.dailyQuests) do
		if q.completed then continue end
		if q.kind == "CatchAnyFish" then
			q.progress += 1
			changed = true
		elseif q.kind == "CatchSpecies" and q.speciesId == speciesId then
			q.progress += 1
			changed = true
		end
		if q.progress >= q.target then
			q.completed = true
		end
	end
	if changed then
		PlayerDataService:NudgeQuestsChanged(player)
	end
end

function QuestService:OnSoldAtMarket(player: Player, salePrice: number)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local changed = false
	for _, q in ipairs(data.dailyQuests) do
		if q.completed then continue end
		if q.kind == "SellAtMarket" then
			q.progress += 1
			changed = true
		elseif q.kind == "EarnCoins" then
			q.progress += salePrice
			changed = true
		end
		if q.progress >= q.target then
			q.completed = true
		end
	end
	if changed then
		PlayerDataService:NudgeQuestsChanged(player)
	end
end

function QuestService:OnHarborVisited(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	for _, q in ipairs(data.dailyQuests) do
		if q.kind == "VisitHarbor" and not q.completed then
			q.progress += 1
			if q.progress >= q.target then q.completed = true end
		end
	end
	PlayerDataService:NudgeQuestsChanged(player)
end

-- ====================================================================
-- CLAIM
-- ====================================================================
function QuestService.Client:ClaimReward(player: Player, questId: string): {ok: boolean, reason: string?, coins: number?, xp: number?}
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	for _, q in ipairs(data.dailyQuests) do
		if q.id == questId then
			if not q.completed then return { ok = false, reason = "not_completed" } end
			if q.claimed then return { ok = false, reason = "already_claimed" } end
			q.claimed = true
			PlayerDataService:AddCoins(player, q.rewardCoins, "quest")
			PlayerDataService:AddXP(player, q.rewardXp)
			PlayerDataService:NudgeQuestsChanged(player)
			return { ok = true, coins = q.rewardCoins, xp = q.rewardXp }
		end
	end
	return { ok = false, reason = "not_found" }
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function QuestService:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")

	Players.PlayerAdded:Connect(function(player)
		local data = PlayerDataService:WaitForProfile(player, 30); if not data then return end
		self:_handleLoginStreak(player)
		self:_refreshIfNeeded(player)
		-- Also settle any market payouts that came in while offline.
		local MarketService = Knit.GetService("MarketService")
		MarketService:SettlePendingPayouts(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local data = PlayerDataService:WaitForProfile(player, 30); if not data then return end
			self:_handleLoginStreak(player)
			self:_refreshIfNeeded(player)
		end)
	end

	-- Periodic refresh check for players still logged in across midnight UTC.
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in ipairs(Players:GetPlayers()) do
				self:_refreshIfNeeded(player)
			end
		end
	end)
end

return QuestService
