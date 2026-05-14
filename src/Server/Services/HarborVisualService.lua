--!strict
-- HarborVisualService.lua
-- Authoritative broadcaster of harbor visual state.
--
-- HarborService owns placement / upgrade / removal (server state). This
-- service is the side-channel that tells *every* client what their copy of
-- the world should look like. The split lets visitors see another player's
-- harbor without the visitor's profile mutating, and keeps HarborService
-- focused on validation + persistence.
--
-- Three signals out (all client-broadcast):
--   HarborVisualUpdate({plotOwnerId, plotOrigin, building, oldTier, newTier})
--       — fresh spawn (oldTier == nil) OR upgrade (newTier > oldTier).
--   HarborVisualRemove(plotOwnerId, buildingUid)
--       — single building destroyed.
--   HarborVisualClear(plotOwnerId)
--       — full plot teardown (player left).
--
-- Replay scope confirmed by design Q&A:
--   * On any placement/upgrade/removal: FireAllClients.
--   * On a player join: replay every OTHER online player's buildings to the
--     joiner only (so visitors see existing harbors). The joiner's own
--     buildings are broadcast via the same path when their ProfileLoaded
--     fires on the HarborService spawn flow.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local HarborVisualService = Knit.CreateService({
	Name = "HarborVisualService",
	Client = {
		HarborVisualUpdate = Knit.CreateSignal(),
		HarborVisualRemove = Knit.CreateSignal(),
		HarborVisualClear  = Knit.CreateSignal(),
	},
})

-- ====================================================================
-- HELPERS
-- ====================================================================
local function makePayload(plotOwnerId: number, plotOrigin: CFrame, building: any, oldTier: number?, newTier: number)
	-- Shallow-copy the building so downstream mutations on the profile
	-- don't ripple into the in-flight RemoteEvent payload.
	return {
		plotOwnerId = plotOwnerId,
		plotOrigin = plotOrigin,
		building = {
			uid = building.uid,
			kind = building.kind,
			tier = newTier,
			gridX = building.gridX,
			gridZ = building.gridZ,
			rotation = building.rotation,
		},
		oldTier = oldTier,
		newTier = newTier,
	}
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function HarborVisualService:KnitStart()
	local HarborService     = Knit.GetService("HarborService")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	-- ---- Broadcast on every placement/upgrade/removal --------------
	HarborService.OnBuildingPlaced.Event:Connect(function(owner: Player, building: any)
		local origin = HarborService:GetPlotOrigin(owner); if not origin then return end
		self.Client.HarborVisualUpdate:FireAll(makePayload(owner.UserId, origin, building, nil, building.tier))
	end)

	HarborService.OnBuildingUpgraded.Event:Connect(function(owner: Player, building: any, oldTier: number, newTier: number)
		local origin = HarborService:GetPlotOrigin(owner); if not origin then return end
		self.Client.HarborVisualUpdate:FireAll(makePayload(owner.UserId, origin, building, oldTier, newTier))
	end)

	HarborService.OnBuildingRemoved.Event:Connect(function(owner: Player, uid: string)
		self.Client.HarborVisualRemove:FireAll(owner.UserId, uid)
	end)

	-- Plot teardown on leave. HarborService fires this BEFORE clearing its
	-- _plotFolders / _plotOrigins, so any straggler downstream still works.
	HarborService.OnPlotReleased.Event:Connect(function(owner: Player)
		self.Client.HarborVisualClear:FireAll(owner.UserId)
	end)

	-- ---- Initial broadcast for a newly-loaded profile ---------------
	-- HarborService gates its spawn flow on PlayerDataService:WaitForProfile,
	-- then calls _spawnBuildingVisual for each existing building — but that
	-- only creates the server anchor (no client visuals). Push the visual
	-- spawn out to ALL clients here so the owner AND any visitors see them.
	local function broadcastInitialBuildings(player: Player)
		local data = PlayerDataService:GetProfile(player); if not data then return end
		local origin = HarborService:GetPlotOrigin(player); if not origin then return end
		for _, b in ipairs(data.buildings) do
			self.Client.HarborVisualUpdate:FireAll(makePayload(player.UserId, origin, b, nil, b.tier))
		end
	end

	-- ---- Replay existing harbors when a player joins ---------------
	-- The joining client needs to see everyone else's harbor too. Wait for
	-- HarborService to finish plot assignment for the joiner (so we don't
	-- race their own broadcast), then send each other player's state.
	local function onJoin(joiner: Player)
		-- Give HarborService a moment to assign the joiner's plot. We don't
		-- have a direct hook for "plot assigned" server-side, so polling the
		-- per-player origin map is the lowest-coupling option.
		local deadline = os.clock() + 30
		while os.clock() < deadline do
			if HarborService:GetPlotOrigin(joiner) then break end
			task.wait(0.5)
		end

		-- Broadcast the joiner's own buildings (FireAll so everyone sees them).
		broadcastInitialBuildings(joiner)

		-- Send every OTHER online player's state to just the joiner.
		for _, other in ipairs(Players:GetPlayers()) do
			if other == joiner then continue end
			local data = PlayerDataService:GetProfile(other); if not data then continue end
			local origin = HarborService:GetPlotOrigin(other); if not origin then continue end
			for _, b in ipairs(data.buildings) do
				self.Client.HarborVisualUpdate:Fire(joiner, makePayload(other.UserId, origin, b, nil, b.tier))
			end
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onJoin, player)
	end)
	-- Players that joined before this service started (rare; small server boot
	-- race) get the same treatment.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, player)
	end
end

return HarborVisualService
