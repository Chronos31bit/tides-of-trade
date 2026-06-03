--!strict
-- AchievementCatalog.lua
-- Seed achievements for the lifetime achievement system.
--
-- Each entry has a stable string `id` (forever once shipped — never rename),
-- a `triggerKey` that maps to the server event, a numeric `target`, and a
-- `reward` drawn from XP and/or cosmetics. No coin rewards per pillar 2.
--
-- triggerKey values:
--   FishCaught        — from FishingService.CaughtServer(player, fish, weightKg, isPerfect)
--   Sold              — from MarketService.SoldServer(player, payout, channel)
--   BuildingUpgraded  — from HarborService.BuildingUpgradedServer(player, building, oldTier, newTier)
--   HarborVisited     — from SocialService.HarborVisitedServer(visitor, hostUserId)
--   EmoteUsed         — from SocialService.EmoteUsedServer(player, emoteId)
--   CrewJoined        — from SocialService.CrewChangedServer(player, action) where action == "joined"

export type AchievementEntry = {
	id: string,
	displayName: string,
	description: string,
	triggerKey: string,
	target: number,
	reward: {
		xp: number?,
		cosmeticId: string?,
	},
}

local catalog: {AchievementEntry} = {
	-- ========== FISHING ==========
	{
		id = "first_catch",
		displayName = "First Catch",
		description = "Catch your first fish.",
		triggerKey = "FishCaught",
		target = 1,
		reward = { xp = 25 },
	},
	{
		id = "angler_100",
		displayName = "Angler",
		description = "Catch 100 fish.",
		triggerKey = "FishCaught",
		target = 100,
		reward = { xp = 100 },
	},
	{
		id = "master_angler_500",
		displayName = "Master Angler",
		description = "Catch 500 fish.",
		triggerKey = "FishCaught",
		target = 500,
		reward = { xp = 250 },
	},

	-- ========== MARKET ==========
	{
		id = "first_sale",
		displayName = "First Sale",
		description = "Sell your first item at the market or dock.",
		triggerKey = "Sold",
		target = 1,
		reward = { xp = 25 },
	},
	{
		id = "market_mogul_50",
		displayName = "Market Mogul",
		description = "Sell 50 items.",
		triggerKey = "Sold",
		target = 50,
		reward = { xp = 100 },
	},

	-- ========== HARBOR ==========
	{
		id = "first_upgrade",
		displayName = "First Upgrade",
		description = "Upgrade your first building.",
		triggerKey = "BuildingUpgraded",
		target = 1,
		reward = { xp = 50 },
	},
	{
		id = "builder_10",
		displayName = "Builder",
		description = "Upgrade buildings 10 times.",
		triggerKey = "BuildingUpgraded",
		target = 10,
		reward = { xp = 150 },
	},

	-- ========== SOCIAL ==========
	{
		id = "crew_mate",
		displayName = "Crew Mate",
		description = "Join or create a crew.",
		triggerKey = "CrewJoined",
		target = 1,
		reward = { xp = 50 },
	},
	{
		id = "harbor_visitor",
		displayName = "Harbor Visitor",
		description = "Visit another player's harbor.",
		triggerKey = "HarborVisited",
		target = 1,
		reward = { xp = 25 },
	},
	{
		id = "social_butterfly_10",
		displayName = "Social Butterfly",
		description = "Visit 10 other harbors.",
		triggerKey = "HarborVisited",
		target = 10,
		reward = { xp = 100 },
	},
}

return catalog
