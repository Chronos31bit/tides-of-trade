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
local function rollQuest(): Types.Quest
	local template = GameConfig.Quests.Templates[math.random(1, #GameConfig.Quests.Templates)]
	local target = math.random(template.targetMin, template.targetMax)
	local speciesId: string? = nil
	if template.kind == "CatchSpecies" then
		-- Bias toward Common/Uncommon — players with low rod tier shouldn't
		-- get a Mythic-only daily.
		local pool = {}
		for _, f in ipairs(FishCatalog.fish) do
			if f.rarity == "Common" or f.rarity == "Uncommon" then
				table.insert(pool, f.id)
			end
		end
		speciesId = pool[math.random(1, #pool)]
	end
	local today = TimeUtil.currentUTCDay()
	return {
		id = ("daily_%s_%s"):format(today, UidUtil.new()),
		kind = template.kind,
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

	local today = TimeUtil.currentUTCDay()
	if data.questsRefreshedDay == today and #data.dailyQuests > 0 then
		return -- already current
	end

	local quests = {}
	for _ = 1, GameConfig.Quests.DailyCount do
		table.insert(quests, rollQuest())
	end
	PlayerDataService:SetQuests(player, quests)
	self.Client.QuestsRefreshed:Fire(player, quests)
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
