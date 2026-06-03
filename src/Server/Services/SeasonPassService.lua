--!strict
-- SeasonPassService.lua
-- Seasonal free-track progression. Players earn season-pass XP from everyday
-- gameplay (catch, sell, build, visit, emote) and advance through 20 tiers.
-- Milestone tiers grant rewards (XP, lure tokens) — claim button on the client.
--
-- No paid track at launch (cosmetic monetization design pending per pillar 2).
-- The season boundary is defined in GameConfig.SeasonPass; a future iteration
-- can add rotation logic (season start/end timestamps, seasonal themes).

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local RateLimiter  = require(ReplicatedStorage.Shared.Util.RateLimiter)

local SeasonPassService = Knit.CreateService({
	Name = "SeasonPassService",
	Client = {
		-- Fired when the player's season-pass state changes (XP gain, tier claim).
		SeasonPassUpdated = Knit.CreateSignal(),  -- ({xp, tier, tierCount, xpPerTier, claimedTiers})
	},
})

-- ====================================================================
-- HELPERS
-- ====================================================================

-- Derive current tier from XP (1-indexed, clamped to TierCount).
local function currentTier(xp: number): number
	local cfg = GameConfig.SeasonPass
	return math.min(math.floor(xp / cfg.XPPerTier) + 1, cfg.TierCount)
end

function SeasonPassService:_grantEventXP(player: Player, eventKey: string)
	local cfg = GameConfig.SeasonPass
	local eventXP = cfg.EventXP and cfg.EventXP[eventKey] or 0
	if eventXP <= 0 then return end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return end

	-- Lazy-init (Reconcile-safe for existing profiles).
	if data.seasonPassXp == nil then data.seasonPassXp = 0 end
	if data.seasonPassClaimedTiers == nil then data.seasonPassClaimedTiers = {} end

	data.seasonPassXp += eventXP

	local tier = currentTier(data.seasonPassXp)
	self.Client.SeasonPassUpdated:Fire(player, {
		xp = data.seasonPassXp,
		tier = tier,
		tierCount = cfg.TierCount,
		xpPerTier = cfg.XPPerTier,
		claimedTiers = data.seasonPassClaimedTiers,
	})
end

-- ====================================================================
-- CLIENT METHODS
-- ====================================================================

function SeasonPassService.Client:GetSeasonPass(_player: Player): {xp: number, tier: number, tierCount: number, xpPerTier: number, claimedTiers: {[number]: boolean}, freeRewards: any}
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(_player)
	local cfg = GameConfig.SeasonPass

	local xp = (data and data.seasonPassXp) or 0
	local claimedTiers: {[number]: boolean} = (data and data.seasonPassClaimedTiers) or {}

	return {
		xp = xp,
		tier = currentTier(xp),
		tierCount = cfg.TierCount,
		xpPerTier = cfg.XPPerTier,
		claimedTiers = claimedTiers,
		freeRewards = cfg.FreeRewards,
	}
end

function SeasonPassService.Client:ClaimTier(player: Player, tier_: number): {ok: boolean, reason: string?}
	local self = self.Server
	if typeof(tier_) ~= "number" or tier_ < 1 or tier_ > GameConfig.SeasonPass.TierCount then
		return { ok = false, reason = "bad_tier" }
	end
	-- Rate-limit claims to 20/min (generous — only 5 milestones in current config).
	if not self._claimLimiter:check(player) then return { ok = false, reason = "rate_limit" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return { ok = false, reason = "no_profile" } end

	if data.seasonPassClaimedTiers == nil then data.seasonPassClaimedTiers = {} end
	if data.seasonPassClaimedTiers[tier_] then return { ok = false, reason = "already_claimed" } end

	local currentTier_ = currentTier(data.seasonPassXp or 0)
	if tier_ > currentTier_ then return { ok = false, reason = "tier_not_reached" } end

	local reward = GameConfig.SeasonPass.FreeRewards[tier_]
	if not reward then return { ok = false, reason = "no_reward_at_tier" } end

	-- Mark claimed.
	data.seasonPassClaimedTiers[tier_] = true

	-- Grant reward.
	if reward.xp and reward.xp > 0 then
		PlayerDataService:AddXP(player, reward.xp)
	end
	if reward.lureTokens and reward.lureTokens > 0 then
		PlayerDataService:AddLureTokens(player, reward.lureTokens)
	end

	-- Push updated state to client.
	self.Client.SeasonPassUpdated:Fire(player, {
		xp = data.seasonPassXp or 0,
		tier = currentTier_,
		tierCount = GameConfig.SeasonPass.TierCount,
		xpPerTier = GameConfig.SeasonPass.XPPerTier,
		claimedTiers = data.seasonPassClaimedTiers,
	})

	return { ok = true }
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function SeasonPassService:KnitInit()
	self._claimLimiter = RateLimiter.new(20, 60)
end

function SeasonPassService:KnitStart()
	local FishingService  = Knit.GetService("FishingService")
	local MarketService   = Knit.GetService("MarketService")
	local HarborService   = Knit.GetService("HarborService")
	local SocialService   = Knit.GetService("SocialService")

	-- Same signal taps as QuestService + AchievementService.

	if FishingService.CaughtServer then
		FishingService.CaughtServer:Connect(function(player, _fish, _weightKg, _isPerfect)
			self:_grantEventXP(player, "FishCaught")
		end)
	end

	if MarketService.SoldServer then
		MarketService.SoldServer:Connect(function(player, _payout, _channel)
			self:_grantEventXP(player, "Sold")
		end)
	end

	if HarborService.BuildingUpgradedServer and HarborService.BuildingUpgradedServer.Event then
		HarborService.BuildingUpgradedServer.Event:Connect(function(player, _building, _oldTier, _newTier)
			self:_grantEventXP(player, "BuildingUpgraded")
		end)
	end

	if SocialService.HarborVisitedServer then
		SocialService.HarborVisitedServer:Connect(function(visitor, _hostUserId)
			self:_grantEventXP(visitor, "HarborVisited")
		end)
	end

	if SocialService.EmoteUsedServer then
		SocialService.EmoteUsedServer:Connect(function(player, _emoteId)
			self:_grantEventXP(player, "EmoteUsed")
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self._claimLimiter:reset(player)
	end)
end

return SeasonPassService
