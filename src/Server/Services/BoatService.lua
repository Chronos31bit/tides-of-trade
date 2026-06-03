--!strict
-- BoatService.lua
-- Server-authoritative "Set Sail" menu backend (Option B from the boats
-- design doc). Validates dock tier, teleports player to band anchor pads,
-- and returns them home. Client requests; server decides.
--
-- SailTo(destination) — validates dock tier + valid band → sets HRP CFrame
--   to the band's pad position → WorldService biome resolver picks up the
--   new zone within 1 second.
-- SailHome() — returns the player to their plot dock origin.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local GameConfig      = require(ReplicatedStorage.Shared.Config.GameConfig)
local RateLimiter     = require(ReplicatedStorage.Shared.Util.RateLimiter)

local VALID_DESTINATIONS = {
	Shoreline = true,
	Pier      = true,
	Reef      = true,
	DeepWater = true,
	Trench    = true,
	Home      = true,
}

local BoatService = Knit.CreateService({
	Name = "BoatService",
	Client = {
		SailResolved = Knit.CreateSignal(),  -- (destination: string) — client uses for fade timing
	},

	_sailLimiter = nil :: any,
})

function BoatService:KnitInit()
	self._sailLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxSailOpsPerMinute, 60)
end

function BoatService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		self._sailLimiter:reset(player)
	end)
end

-- ====================================================================
-- RESOLVE DOCK TIER
-- ====================================================================

function BoatService:_getPlayerDockTier(player: Player): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return 1 end

	local best = 0
	for _, b in ipairs(data.buildings) do
		if b.kind == "Dock" and b.tier > best then
			best = b.tier
		end
	end
	return best > 0 and best or 1
end

-- ====================================================================
-- SAIL TO — teleport player to a deep band anchor pad
-- ====================================================================

function BoatService.Client:SailTo(player: Player, destination: string): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._sailLimiter:check(player) then
		return { ok = false, reason = "rate_limit" }
	end

	if typeof(destination) ~= "string" or not VALID_DESTINATIONS[destination] then
		return { ok = false, reason = "bad_destination" }
	end

	if destination == "Home" then
		return BoatService.Client:SailHome(player)
	end

	local cfg = GameConfig.Boats
	local requiredTier = cfg.AccessByDockTier[destination]
	if not requiredTier then
		return { ok = false, reason = "bad_destination" }
	end

	local dockTier = self:_getPlayerDockTier(player)
	if dockTier < requiredTier then
		return { ok = false, reason = "dock_tier_too_low" }
	end

	local padPos = cfg.PadPositions[destination]
	if not padPos then
		return { ok = false, reason = "no_pad" }
	end

	local char = player.Character
	if not char then
		return { ok = false, reason = "no_character" }
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { ok = false, reason = "no_hrp" }
	end

	-- Teleport to the pad. WorldService's 1 Hz biome resolver will pick up
	-- the new position and stamp character.CurrentBiome within a second.
	hrp.CFrame = CFrame.new(padPos) * CFrame.new(0, 4, 0)

	-- Tell the client to play the sail fade (so it syncs with the teleport).
	self.Client.SailResolved:Fire(player, destination)

	return { ok = true }
end

-- ====================================================================
-- SAIL HOME — return player to their own plot dock
-- ====================================================================

function BoatService.Client:SailHome(player: Player): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._sailLimiter:check(player) then
		return { ok = false, reason = "rate_limit" }
	end

	local HarborService = Knit.GetService("HarborService")
	local origin = HarborService:GetPlotOrigin(player)
	if not origin then
		return { ok = false, reason = "no_plot" }
	end

	local char = player.Character
	if not char then
		return { ok = false, reason = "no_character" }
	end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { ok = false, reason = "no_hrp" }
	end

	-- Land near the dock, not on top of the plot origin exactly.
	hrp.CFrame = origin * CFrame.new(4, 6, 8)

	self.Client.SailResolved:Fire(player, "Home")

	return { ok = true }
end

return BoatService
