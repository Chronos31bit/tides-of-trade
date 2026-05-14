--!strict
-- HarborVisualService.lua
-- Server-authoritative *state broadcaster* for harbor visuals. Owns no
-- physical Instances and never clones Models — that's the client's job
-- (HarborVisualController). This service just:
--   1) maintains an in-memory cache of every player's current building list
--      and plot origin,
--   2) fires HarborVisualUpdate to all clients whenever a building is
--      placed, upgraded, or removed,
--   3) on new-player join, replays the cached state to that one player so
--      they see existing harbors (their own + everyone else's) populated
--      without animation,
--   4) on player leave, fires HarborVisualClear so other clients can drop
--      that plot's visuals cleanly (StreamingEnabled doesn't always tear
--      down promptly).
--
-- HarborService calls into this service via the OnBuilding* methods.
-- We use ownerUserId (Player.UserId) as the plot identifier — the current
-- codebase has no separate plotId concept; the plot belongs to the player.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

export type VisualUpdate = {
	ownerUserId: number,
	plotOriginCFrame: CFrame,
	buildingId: string,
	kind: string,
	oldTier: number?,
	newTier: number?,
	gridX: number,
	gridZ: number,
	rotation: number,
	animate: boolean,
}

local HarborVisualService = Knit.CreateService({
	Name = "HarborVisualService",
	Client = {
		-- (update: VisualUpdate). Sent to every player via :FireAll so visitors
		-- can render other harbors. Client decides whether to spawn / animate
		-- based on payload.oldTier vs payload.newTier.
		HarborVisualUpdate = Knit.CreateSignal(),
		-- (ownerUserId). Fired when a player leaves so clients can purge their
		-- visuals without waiting on StreamingEnabled timing.
		HarborVisualClear  = Knit.CreateSignal(),
	},

	-- Cache: [playerUserId] = { plotOrigin: CFrame, buildings: { [uid] = building } }
	_state = {},
})

-- ====================================================================
-- INTERNAL HELPERS
-- ====================================================================
local function ensureEntry(self, userId: number)
	local e = self._state[userId]
	if not e then
		e = { plotOrigin = CFrame.new(), buildings = {} }
		self._state[userId] = e
	end
	return e
end

local function makePayload(userId: number, plotOrigin: CFrame, building: any, oldTier: number?, newTier: number?, animate: boolean): VisualUpdate
	return {
		ownerUserId = userId,
		plotOriginCFrame = plotOrigin,
		buildingId = building.uid,
		kind = building.kind,
		oldTier = oldTier,
		newTier = newTier,
		gridX = building.gridX,
		gridZ = building.gridZ,
		rotation = building.rotation,
		animate = animate,
	}
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function HarborVisualService:KnitStart()
	-- New joiners pull current state via the GetSnapshot Client method on
	-- their own KnitStart — that handles the race where a FireAll from
	-- HarborService.RebroadcastForPlayer goes out before they've connected
	-- the signal. Doing a server-side PlayerAdded replay too would be 2x
	-- redundant; clients dedupe but the bandwidth is wasted.
	Players.PlayerRemoving:Connect(function(leaver)
		-- HarborService also fires its own leave hook (clear plot folder etc.).
		-- We just drop our cache and tell every remaining client to purge.
		self._state[leaver.UserId] = nil
		self.Client.HarborVisualClear:FireAll(leaver.UserId)
	end)
end

-- ====================================================================
-- SERVER API (called by HarborService)
-- ====================================================================

-- Called once after HarborService has placed the player's plot and spawned
-- their persisted buildings. Fires one update per existing building to all
-- clients with animate=false (no upgrade tween, just fresh spawn).
function HarborVisualService:RebroadcastForPlayer(player: Player, plotOrigin: CFrame, buildings: {any})
	local entry = ensureEntry(self, player.UserId)
	entry.plotOrigin = plotOrigin
	entry.buildings = {}
	for _, b in ipairs(buildings) do
		entry.buildings[b.uid] = b
		-- FireAll so every existing client renders the joiner's harbor.
		self.Client.HarborVisualUpdate:FireAll(
			makePayload(player.UserId, plotOrigin, b, nil, b.tier, false)
		)
	end
end

function HarborVisualService:OnBuildingPlaced(player: Player, building: any)
	local entry = ensureEntry(self, player.UserId)
	-- Tolerate a missing plot origin (shouldn't happen — HarborService always
	-- calls Rebroadcast first — but defensive).
	if entry.plotOrigin == CFrame.new() then
		local HarborService = Knit.GetService("HarborService")
		local origin = HarborService:GetPlotOrigin(player)
		if origin then entry.plotOrigin = origin end
	end
	entry.buildings[building.uid] = building
	self.Client.HarborVisualUpdate:FireAll(
		makePayload(player.UserId, entry.plotOrigin, building, nil, building.tier, false)
	)
end

function HarborVisualService:OnBuildingUpgraded(player: Player, building: any, oldTier: number)
	local entry = ensureEntry(self, player.UserId)
	entry.buildings[building.uid] = building
	self.Client.HarborVisualUpdate:FireAll(
		makePayload(player.UserId, entry.plotOrigin, building, oldTier, building.tier, true)
	)
end

-- Client-callable: dump the entire current visual state. Used by clients on
-- their KnitStart to fill in any plot whose initial broadcast went out before
-- they were connected to the signal. Idempotent on the client side because
-- HarborVisualController dedupes against its existing-visual map.
function HarborVisualService.Client:GetSnapshot(_player: Player): { VisualUpdate }
	local svc = self.Server
	local out: { VisualUpdate } = {}
	for userId, entry in pairs(svc._state) do
		for _, b in pairs(entry.buildings) do
			table.insert(out, makePayload(userId, entry.plotOrigin, b, nil, b.tier, false))
		end
	end
	return out
end

function HarborVisualService:OnBuildingRemoved(player: Player, uid: string)
	local entry = self._state[player.UserId]
	if not entry then return end
	local existing = entry.buildings[uid]
	if not existing then return end
	entry.buildings[uid] = nil
	-- Removal is signaled with newTier = nil. Old tier kept for symmetry, but
	-- the client only checks newTier == nil.
	self.Client.HarborVisualUpdate:FireAll({
		ownerUserId = player.UserId,
		plotOriginCFrame = entry.plotOrigin,
		buildingId = uid,
		kind = existing.kind,
		oldTier = existing.tier,
		newTier = nil,
		gridX = existing.gridX,
		gridZ = existing.gridZ,
		rotation = existing.rotation,
		animate = false,
	})
end

return HarborVisualService
