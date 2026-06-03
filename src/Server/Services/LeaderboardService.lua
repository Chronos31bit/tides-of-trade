--!strict
-- LeaderboardService.lua
-- Cross-server leaderboards backed by OrderedDataStores. Players are ranked
-- by (a) total catches and (b) unique species caught. Scores are written on
-- session-end; client fetches are rate-limited per config.

local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit             = require(ReplicatedStorage.Packages.Knit)
local GameConfig       = require(ReplicatedStorage.Shared.Config.GameConfig)

local LB = GameConfig.Leaderboard
local TOP_N = LB.TopN
local COOLDOWN = LB.RefreshCooldownSec

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {},
})

-- Per-session throttle: user → last fetch os.clock()
local _lastFetch: {[Player]: number} = {}

-- Write the player's score to both OrderedDataStores. Called on session-end
-- so we don't hammer DataStores every catch. Silent on failure — leaderboards
-- are non-critical.
local function writeScores(userId: number, displayName: string, totalCatches: number, speciesCount: number)
	local ok, err

	local catchesStore = DataStoreService:GetOrderedDataStore(LB.DataStores.Catches)
	ok, err = pcall(function()
		catchesStore:SetAsync(tostring(userId), totalCatches)
	end)
	if not ok then
		warn("[Leaderboard] Catches write failed:", err)
	end

	local speciesStore = DataStoreService:GetOrderedDataStore(LB.DataStores.Species)
	ok, err = pcall(function()
		speciesStore:SetAsync(tostring(userId), speciesCount)
	end)
	if not ok then
		warn("[Leaderboard] Species write failed:", err)
	end

	-- Store display name keyed by userId so the client can resolve names.
	local namesStore = DataStoreService:GetDataStore("TidesLB_Names_v1")
	pcall(function()
		namesStore:SetAsync(tostring(userId), displayName)
	end)
end

-- Fetch top N from an OrderedDataStore. Returns { {userId, score} }.
local function fetchTopN(storeName: string, n: number)
	local store = DataStoreService:GetOrderedDataStore(storeName)
	local pages = store:GetSortedAsync(false, n)
	local results = {}
	local page = pages:GetCurrentPage()
	for _, entry in ipairs(page) do
		table.insert(results, { entry.key, entry.value })
		if #results >= n then break end
	end
	return results
end

-- Resolve display names for a set of userIds. Returns {[userId]: displayName}.
local function resolveNames(userIds: {string}): {[string]: string}
	local namesStore = DataStoreService:GetDataStore("TidesLB_Names_v1")
	local names: {[string]: string} = {}
	for _, uid in ipairs(userIds) do
		local ok, name = pcall(function()
			return namesStore:GetAsync(uid)
		end)
		if ok and name then
			names[uid] = name
		else
			names[uid] = "[Player " .. uid .. "]"
		end
	end
	return names
end

-- Client: Get top-N entries for a leaderboard axis.
function LeaderboardService.Client:GetTopN(player: Player, axis: string): {ok: boolean, entries: any?, reason: string?}
	local now = os.clock()
	local last = _lastFetch[player] or 0
	if now - last < COOLDOWN then
		return { ok = false, reason = "rate_limited" }
	end
	_lastFetch[player] = now

	local storeName: string?
	if axis == "catches" then
		storeName = LB.DataStores.Catches
	elseif axis == "species" then
		storeName = LB.DataStores.Species
	else
		return { ok = false, reason = "unknown_axis" }
	end

	local ok, raw = pcall(fetchTopN, storeName, TOP_N)
	if not ok then
		warn("[Leaderboard] Fetch failed:", raw)
		return { ok = false, reason = "datastore_error" }
	end

	local userIds = {}
	for _, entry in ipairs(raw) do
		table.insert(userIds, entry[1])
	end
	local names = resolveNames(userIds)

	local entries = {}
	for i, entry in ipairs(raw) do
		table.insert(entries, {
			rank = i,
			displayName = names[entry[1]] or "[Unknown]",
			score = entry[2],
		})
	end
	return { ok = true, entries = entries }
end

function LeaderboardService:KnitStart()
	-- On player leave, write final scores.
	Players.PlayerRemoving:Connect(function(player)
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local data = PlayerDataService:GetProfile(player)
		if not data then return end
		local stats = data.stats
		if not stats then return end
		local speciesCount = 0
		if stats.caughtSpecies then
			for _, _ in pairs(stats.caughtSpecies) do speciesCount += 1 end
		end
		writeScores(player.UserId, player.Name, stats.totalCatches or 0, speciesCount)
	end)
end

return LeaderboardService
