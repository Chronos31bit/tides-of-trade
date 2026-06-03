--!strict
-- SocialService.lua
-- Crews (8-player groups, shared chat + weekly quest), emotes, and harbor
-- visits via TeleportService. Crew membership is persisted on each member's
-- profile (data.crewId); the crew object itself is in a small DataStore.

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")
local TextService     = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local GameConfig      = require(ReplicatedStorage.Shared.Config.GameConfig)
local UidUtil         = require(ReplicatedStorage.Shared.Util.UidUtil)
local Signal          = require(ReplicatedStorage.Packages.Signal)
local RateLimiter     = require(ReplicatedStorage.Shared.Util.RateLimiter)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)

local SocialService = Knit.CreateService({
	Name = "SocialService",
	Client = {
		CrewChat    = Knit.CreateSignal(),  -- (fromName, message)
		EmotePlayed = Knit.CreateSignal(),  -- (userId, emoteId)
	},

	-- Server-internal Signals. QuestService listens to these to advance
	-- daily quest progress. Convention TODO: see HarborService note about
	-- Remote/Server affix sweep.
	HarborVisitedServer = Signal.new(),  -- (visitor, hostUserId)
	EmoteUsedServer     = Signal.new(),  -- (player, emoteId)

	_crewStore = nil :: any,
})

function SocialService:KnitInit()
	self._crewStore = DataStoreService:GetDataStore("TidesCrews_v1")
	-- Rate limiters. Silent-drop on over-limit per CLAUDE.md cozy pillar — the
	-- player never sees an error; the server just no-ops. Budgets in GameConfig
	-- are tuned generously so honest play never trips them.
	self._crewOpLimiter   = RateLimiter.new(GameConfig.AntiExploit.MaxCrewOpsPerMinute, 60)
	self._crewChatLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxCrewChatsPerMinute, 60)
	self._emoteLimiter    = RateLimiter.new(GameConfig.AntiExploit.MaxEmotesPerMinute, 60)
	self._visitLimiter    = RateLimiter.new(GameConfig.AntiExploit.MaxVisitsPerMinute, 60)
end

function SocialService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		self._crewOpLimiter:reset(player)
		self._crewChatLimiter:reset(player)
		self._emoteLimiter:reset(player)
		self._visitLimiter:reset(player)
	end)
end

-- ====================================================================
-- CREW CAPACITY — base slots + guildhall bonus
-- ====================================================================
-- Effective member cap = GameConfig.Crew.MaxMembers + the owner's best
-- guildhall bonus (BuildingCatalog.Guildhall.tiers[tier].guildhallCrewBonus).
-- We read the owner's *live* profile, so the bonus only applies when the owner
-- is on this server — there is no offline-profile read API, and CLAUDE.md bars
-- touching DataStores directly from gameplay code. When the owner is elsewhere
-- we fall back to the base cap. This mirrors the same-server-only stance crew
-- chat already takes below; cross-server cap resolution is deferred with it.
--
-- Non-yielding (GetPlayerByUserId / GetProfile / catalog lookups don't yield),
-- so it is safe to call inside an UpdateAsync transform.
function SocialService:_effectiveCrewCap(ownerId: number): number
	local base = GameConfig.Crew.MaxMembers
	if typeof(ownerId) ~= "number" then return base end

	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner then return base end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local ownerData = PlayerDataService:GetProfile(owner)
	if not ownerData then return base end

	-- Take the best bonus across all guildhalls the owner has placed (a player
	-- could have more than one; use the highest-tier one).
	local bestBonus = 0
	for _, b in ipairs(ownerData.buildings) do
		if b.kind == "Guildhall" then
			local def = BuildingCatalog.Guildhall
			local tier = def.tiers[b.tier]
			if tier and tier.guildhallCrewBonus and tier.guildhallCrewBonus > bestBonus then
				bestBonus = tier.guildhallCrewBonus
			end
		end
	end
	return base + bestBonus
end

-- ====================================================================
-- CREW CRUD
-- ====================================================================

function SocialService.Client:CreateCrew(player: Player, name: string): {ok: boolean, reason: string?, crewId: string?}
	local self = self.Server
	if not self._crewOpLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end
	if data.crewId then return { ok = false, reason = "already_in_crew" } end
	if typeof(name) ~= "string" or #name < 3 or #name > 20 then
		return { ok = false, reason = "bad_name" }
	end

	local crewId = UidUtil.new("crew")
	local ok, err = pcall(function()
		self._crewStore:SetAsync(crewId, {
			id = crewId,
			name = name,
			ownerId = player.UserId,
			members = { player.UserId },
			createdAt = os.time(),
		})
	end)
	if not ok then
		warn("[SocialService] CreateCrew DataStore failed:", err)
		return { ok = false, reason = "datastore_error" }
	end
	data.crewId = crewId
	return { ok = true, crewId = crewId }
end

function SocialService.Client:JoinCrew(player: Player, crewId: string): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._crewOpLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	if typeof(crewId) ~= "string" or #crewId == 0 or #crewId > 64 then
		return { ok = false, reason = "bad_crew_id" }
	end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end
	if data.crewId then return { ok = false, reason = "already_in_crew" } end

	local result
	local ok = pcall(function()
		self._crewStore:UpdateAsync(crewId, function(crew)
			if not crew then result = "no_such_crew" return nil end
			-- Effective cap = base + owner's guildhall bonus (see
			-- _effectiveCrewCap). Resolved against the owner's live profile, so
			-- tier-2 guildhall → 10, tier-3 → 12 when the owner is on-server.
			local cap = self:_effectiveCrewCap(crew.ownerId)
			if #crew.members >= cap then result = "full" return nil end
			table.insert(crew.members, player.UserId)
			return crew
		end)
	end)
	if not ok or result then return { ok = false, reason = result or "datastore_error" } end
	data.crewId = crewId
	return { ok = true }
end

function SocialService.Client:LeaveCrew(player: Player): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._crewOpLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end
	if not data.crewId then return { ok = false, reason = "not_in_crew" } end
	local crewId = data.crewId
	local ok = pcall(function()
		self._crewStore:UpdateAsync(crewId, function(crew)
			if not crew then return nil end
			for i, uid in ipairs(crew.members) do
				if uid == player.UserId then
					table.remove(crew.members, i)
					break
				end
			end
			return crew
		end)
	end)
	if not ok then return { ok = false, reason = "datastore_error" } end
	data.crewId = nil
	return { ok = true }
end

-- ====================================================================
-- CREW CHAT — server-fanout per message
-- ====================================================================
function SocialService.Client:SendCrewChat(player: Player, message: string)
	local self = self.Server
	-- Silent-drop on over-limit. Crew chat amplifies one client's traffic to
	-- N other clients, so the limit is essential. Cozy: never show "you're
	-- being too noisy" — the player just sees their own message not arrive.
	if not self._crewChatLimiter:check(player) then return end
	if typeof(message) ~= "string" or #message == 0 or #message > 140 then return end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.crewId then return end

	-- Look up crew members from store. For higher throughput, cache crews per
	-- server with a TTL — fine for v1 to fetch each time since chat is low rate.
	local crew = self._crewStore:GetAsync(data.crewId)
	if not crew then return end

	-- Server-side content filter via Roblox TextService. Must run
	-- server-side — clients cannot be trusted to filter their own
	-- text. pcall guards against TextService unavailability; on
	-- failure we silently drop the message (cozy pillar — never
	-- surface infrastructure errors to the player).
	local filteredMessage = message
	local filterOk = pcall(function()
		local filterResult = TextService:FilterStringAsync(
			message,
			player.UserId,
			Enum.TextFilterContext.PublicChat
		)
		filteredMessage = filterResult:GetNonChatStringForBroadcast()
	end)
	if not filterOk then
		return  -- silently drop; do NOT broadcast unfiltered text
	end

	for _, uid in ipairs(crew.members) do
		local member = Players:GetPlayerByUserId(uid)
		-- Cross-server crew chat would route through MessagingService; v1 is
		-- same-server only. Document this clearly so we don't ship a feature
		-- that silently no-ops for distant crewmates.
		if member then
			self.Client.CrewChat:Fire(member, player.Name, filteredMessage)
		end
	end
end

-- ====================================================================
-- EMOTES — broadcast to nearby players for that "wave from the dock" feel
-- ====================================================================
function SocialService.Client:PlayEmote(player: Player, emoteId: string)
	local self = self.Server
	-- Silent-drop on over-limit. Each emote fans out to every player on the
	-- server, so an unlimited-rate emote is a broadcast amplification attack.
	-- Generous budget keeps dance parties working.
	if not self._emoteLimiter:check(player) then return end
	-- Whitelist check — clients can only play emotes the catalog knows about.
	local allowed = { wave = true, dance = true, fish_pose = true, salute = true, bow = true }
	if typeof(emoteId) ~= "string" or not allowed[emoteId] then return end
	for _, other in ipairs(Players:GetPlayers()) do
		self.Client.EmotePlayed:Fire(other, player.UserId, emoteId)
	end
	-- Server-side fan-out for quest progress (social_emote_n).
	self.EmoteUsedServer:Fire(player, emoteId)
end

-- ====================================================================
-- VISIT HARBOR — TeleportService server-hop
-- ====================================================================
-- For v1 we teleport within the same place, just to the target player's plot.
-- A full multi-server "visit-by-username" needs TeleportService:TeleportAsync
-- with a friendly server hop. We expose both flows.

function SocialService.Client:VisitLocalHarbor(player: Player, targetUserId: number): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._visitLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	-- targetUserId goes into Players:GetPlayerByUserId and TeleportService;
	-- typeof guard is cheap defense-in-depth against bad client input.
	if typeof(targetUserId) ~= "number" or targetUserId ~= targetUserId
		or targetUserId <= 0 or targetUserId > 2^53 then
		return { ok = false, reason = "bad_target" }
	end
	targetUserId = math.floor(targetUserId)
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		-- Not on this server — initiate a cross-server teleport.
		local placeId = game.PlaceId
		local ok = pcall(function()
			TeleportService:TeleportToPlaceInstance(placeId, "", player) -- v1: just bounce; a richer impl matches by reservation
		end)
		return { ok = ok }
	end
	local HarborService = Knit.GetService("HarborService")
	local origin = HarborService:GetPlotOrigin(target)
	if not origin then return { ok = false, reason = "no_plot" } end

	-- Drop the visitor on the host's dock. Find the host's dock building and
	-- teleport to its world position.
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local hostData = PlayerDataService:GetProfile(target)
	if not hostData then return { ok = false, reason = "no_host_profile" } end
	local dock
	for _, b in ipairs(hostData.buildings) do
		if b.kind == "Dock" then dock = b break end
	end
	local landing = origin
	if dock then
		local GridUtil = require(ReplicatedStorage.Shared.Util.GridUtil)
		local local_ = GridUtil.gridToLocal(dock.gridX, dock.gridZ)
		landing = origin * CFrame.new(local_.X + 4, 6, local_.Z + 4)
	end
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		(char.HumanoidRootPart :: BasePart).CFrame = landing
	end

	-- Server-side fan-out for quest progress (social_visit_harbors).
	-- QuestService listens to this signal; no direct call so SocialService
	-- doesn't have a compile-time dependency on QuestService's API.
	self.HarborVisitedServer:Fire(player, targetUserId)
	return { ok = true }
end

return SocialService
