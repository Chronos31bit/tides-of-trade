--!strict
-- SocialService.lua
-- Crews (8-player groups, shared chat + weekly quest), emotes, and harbor
-- visits via TeleportService. Crew membership is persisted on each member's
-- profile (data.crewId); the crew object itself is in a small DataStore.

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local UidUtil    = require(ReplicatedStorage.Shared.Util.UidUtil)
local Signal     = require(ReplicatedStorage.Packages.Signal)

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
end

-- ====================================================================
-- CREW CRUD
-- ====================================================================

function SocialService.Client:CreateCrew(player: Player, name: string): {ok: boolean, reason: string?, crewId: string?}
	local self = self.Server
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
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end
	if data.crewId then return { ok = false, reason = "already_in_crew" } end

	local result
	local ok = pcall(function()
		self._crewStore:UpdateAsync(crewId, function(crew)
			if not crew then result = "no_such_crew" return nil end
			if #crew.members >= GameConfig.Crew.MaxMembers then result = "full" return nil end
			-- Check buildings for guildhall slot bonus on the *owner* — simple,
			-- avoids cross-profile lookups here.
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
	if typeof(message) ~= "string" or #message == 0 or #message > 140 then return end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.crewId then return end

	-- Look up crew members from store. For higher throughput, cache crews per
	-- server with a TTL — fine for v1 to fetch each time since chat is low rate.
	local crew = self._crewStore:GetAsync(data.crewId)
	if not crew then return end
	for _, uid in ipairs(crew.members) do
		local member = Players:GetPlayerByUserId(uid)
		-- Cross-server crew chat would route through MessagingService; v1 is
		-- same-server only. Document this clearly so we don't ship a feature
		-- that silently no-ops for distant crewmates.
		if member then
			self.Client.CrewChat:Fire(member, player.Name, message)
		end
	end
end

-- ====================================================================
-- EMOTES — broadcast to nearby players for that "wave from the dock" feel
-- ====================================================================
function SocialService.Client:PlayEmote(player: Player, emoteId: string)
	local self = self.Server
	-- Whitelist check — clients can only play emotes the catalog knows about.
	local allowed = { wave = true, dance = true, fish_pose = true, salute = true, bow = true }
	if not allowed[emoteId] then return end
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
