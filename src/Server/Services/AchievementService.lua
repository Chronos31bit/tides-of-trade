--!strict
-- AchievementService.lua
-- Lifetime achievement system. Listens to server signals (same taps as
-- QuestService), evaluates AchievementCatalog entries, records progress and
-- unlocks in the player's profile, and fires AchievementUnlocked to clients.
--
-- One-time-unlock only: once an achievement is unlocked, its progress stops
-- incrementing. No coin rewards per pillar 2 — XP and cosmetics only.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit              = require(ReplicatedStorage.Packages.Knit)
local GameConfig        = require(ReplicatedStorage.Shared.Config.GameConfig)
local AchievementCatalog = require(ReplicatedStorage.Shared.Config.AchievementCatalog)
local Types             = require(ReplicatedStorage.Shared.Types)

type AchievementEntry = Types.AchievementEntry

-- Build a lookup by triggerKey for fast evaluation.
local _byTrigger: {[string]: {AchievementEntry}} = {}
for _, entry in ipairs(AchievementCatalog) do
	if not _byTrigger[entry.triggerKey] then
		_byTrigger[entry.triggerKey] = {}
	end
	table.insert(_byTrigger[entry.triggerKey], entry)
end

local AchievementService = Knit.CreateService({
	Name = "AchievementService",
	Client = {
		-- Fired when a player unlocks a new achievement.
		AchievementUnlocked = Knit.CreateSignal(),  -- ({id, displayName, description, reward})
	},
})

-- ====================================================================
-- HELPERS
-- ====================================================================

function AchievementService:_grantReward(player: Player, entry: AchievementEntry)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local reward = entry.reward
	if not reward then return end

	if reward.xp and reward.xp > 0 then
		PlayerDataService:AddXP(player, reward.xp)
	end
	-- Cosmetic grants deferred until CosmeticsService ships (v1: XP only).
	-- if reward.cosmeticId and #reward.cosmeticId > 0 then
	-- 	PlayerDataService:AddCosmetic(player, reward.cosmeticId)
	-- end
end

-- Walk all catalog entries that match `triggerKey`. For each, check if the
-- player has already unlocked it; if not, increment progress. When progress
-- crosses the target, record the unlock, fire the signal, and grant the reward.
function AchievementService:_evaluateTrigger(player: Player, triggerKey: string)
	local entries = _byTrigger[triggerKey]
	if not entries then return end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return end

	-- Lazy-init achievements table on first evaluation (Reconcile-safe).
	if not data.achievements then
		data.achievements = {}
	end

	local unlockedAny = false

	for _, entry in ipairs(entries) do
		local state = data.achievements[entry.id]
		if not state then
			state = { progress = 0 }
			data.achievements[entry.id] = state
		end

		-- Already unlocked — skip.
		if state.unlockedAt then
			continue
		end

		state.progress = (state.progress or 0) + 1

		if state.progress >= entry.target then
			state.unlockedAt = os.time()
			unlockedAny = true

			self:_grantReward(player, entry)

			self.Client.AchievementUnlocked:Fire(player, {
				id = entry.id,
				displayName = entry.displayName,
				description = entry.description,
				reward = entry.reward,
			})
		end
	end

	if unlockedAny then
		PlayerDataService:UpdateProfile(player, function(_profile)
			-- No-op: the data.achievements mutations above are already on
			-- the live profile table; UpdateProfile just marks it dirty.
		end)
	end
end

-- ====================================================================
-- CLIENT METHODS
-- ====================================================================

function AchievementService.Client:GetAchievements(_player: Player): {[string]: {progress: number, unlockedAt: number?}}
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(_player)
	if not data or not data.achievements then
		return {}
	end
	-- Return a shallow snapshot so the client can't mutate the live table.
	local snap: {[string]: {progress: number, unlockedAt: number?}} = {}
	for id, state in pairs(data.achievements) do
		snap[id] = {
			progress = state.progress,
			unlockedAt = state.unlockedAt,
		}
	end
	return snap
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function AchievementService:KnitInit()
end

function AchievementService:KnitStart()
	local FishingService  = Knit.GetService("FishingService")
	local MarketService   = Knit.GetService("MarketService")
	local HarborService   = Knit.GetService("HarborService")
	local SocialService   = Knit.GetService("SocialService")

	-- Same signal taps as QuestService — each event evaluates matching
	-- achievement entries.

	-- Fishing
	if FishingService.CaughtServer then
		FishingService.CaughtServer:Connect(function(player, _fish, _weightKg, _isPerfect)
			self:_evaluateTrigger(player, "FishCaught")
		end)
	end

	-- Market
	if MarketService.SoldServer then
		MarketService.SoldServer:Connect(function(player, _payout, _channel)
			self:_evaluateTrigger(player, "Sold")
		end)
	end

	-- Harbor
	if HarborService.BuildingUpgradedServer and HarborService.BuildingUpgradedServer.Event then
		HarborService.BuildingUpgradedServer.Event:Connect(function(player, _building, _oldTier, _newTier)
			self:_evaluateTrigger(player, "BuildingUpgraded")
		end)
	end

	-- Social
	if SocialService.HarborVisitedServer then
		SocialService.HarborVisitedServer:Connect(function(visitor, _hostUserId)
			self:_evaluateTrigger(visitor, "HarborVisited")
		end)
	end
	if SocialService.CrewChangedServer then
		SocialService.CrewChangedServer:Connect(function(player, action)
			if action == "joined" then
				self:_evaluateTrigger(player, "CrewJoined")
			end
		end)
	end
end

return AchievementService
