--!strict
-- PlayerDataService.lua
-- Authoritative source of player Profile data. Wraps ProfileService so other
-- services never touch DataStores directly — they just call:
--   PlayerDataService:GetProfile(player) -> Profile?
--   PlayerDataService:UpdateProfile(player, mutator)
-- and receive a clean, typed Profile table. ProfileService handles the
-- session-locking, retries, and auto-save concerns.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local ProfileService  = require(ReplicatedStorage.Shared.Vendor.ProfileService)
local GameConfig      = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types           = require(ReplicatedStorage.Shared.Types)

type Profile = Types.Profile

-- ====================================================================
-- PROFILE TEMPLATE
-- ====================================================================
-- The default profile granted to new players. ProfileService deep-copies this
-- and merges any missing fields into existing profiles on load (so adding new
-- fields here doesn't require a migration).
local PROFILE_TEMPLATE: Profile = {
	coins = 500,            -- starting coins for first rod and a stall
	lureTokens = 0,
	level = 1,
	xp = 0,
	inventory = {},
	buildings = {},         -- starter dock is granted on first load (see :_grantStarterAssets)
	plotIndex = nil,        -- world-plot slot index; set on first join, stable forever
	aquariumStock = {},     -- [aquariumUid] -> { FishItem, ... }
	cosmetics = {},
	rodTier = 1,
	streak = {
		current = 0,
		longest = 0,
		lastLoginUtcDay = nil,
		weekStartedAt = 0,
	},
	dailyQuests = {},
	yesterdayQuests = {},
	questsRefreshedDay = nil,
	crewId = nil,
	stats = {
		totalCatches = 0,
		totalSold = 0,
		totalCoinsEarned = 0,
		caughtSpecies = {},
	},
	-- Bait. baitStash is a map of baitId → unit count; Reconcile adds it as
	-- an empty table for existing profiles (safe default). equippedBaitId stays
	-- nil for existing profiles — code reads it as nil via normal table lookup.
	baitStash = {},
	equippedBaitId = nil,

	-- Rod selection. equippedRodId is the named rod the player has chosen;
	-- it drives castWindowBonus / catchWeightBonus in FishingService and also
	-- sets rodTier for fish species access. "driftwood" is the safe default
	-- for all existing profiles via ProfileService:Reconcile().
	equippedRodId = "driftwood",

	-- Tutorial state machine. New fields are picked up by profile:Reconcile()
	-- on load, so existing saves get a default-not_started slot — but the
	-- TutorialService:_isReturningVet check below force-completes any profile
	-- whose stats show prior play (catches/sales > 0). That keeps existing
	-- players from being re-onboarded after a deploy.
	tutorial = {
		state = "not_started",        -- "not_started" | "greet" | "cast_intro" | "first_catch" | "first_sale" | "first_repair" | "daily_quest_hook" | "complete"
		lineIndex = 1,                -- which line in the current beat's dialogue
		startedAt = nil,
		completedAt = nil,
		beginnerAssistsRemaining = 3,
		seededQuestId = nil,          -- id of the beat-6 seeded quest, used to detect Accept
		flags = {
			seenGlobalMarketHint = false,
		},
	},
	-- Audio/Motion preferences. Reconcile adds this table (with these defaults)
	-- to existing profiles on load, so no migration / version bump is needed.
	settings = {
		audioMuted = GameConfig.Settings.DefaultMuted,
		masterVolume = GameConfig.Settings.DefaultMasterVolume,
		motionMode = GameConfig.Settings.DefaultMotionMode,
	},

	schemaVersion = 1,
}

-- ====================================================================
-- SERVICE DEFINITION
-- ====================================================================
local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",

	-- Client-callable / observable surface. Clients can request a snapshot
	-- of their own profile and subscribe to deltas. We do NOT replicate the
	-- entire profile to clients on every change — that's expensive and leaks
	-- balance secrets to exploiters. Instead, services emit targeted signals
	-- (CoinsChanged, InventoryChanged, etc.) with just the relevant slice.
	Client = {
		ProfileLoaded     = Knit.CreateSignal(),  -- fired once per session, after load
		CoinsChanged      = Knit.CreateSignal(),  -- (newCoins, newLureTokens)
		XPChanged         = Knit.CreateSignal(),  -- (newLevel, newXp, xpForNextLevel)
		RodTierChanged    = Knit.CreateSignal(),  -- (newTier)
		EquippedRodChanged = Knit.CreateSignal(), -- (rodId)
		InventoryChanged  = Knit.CreateSignal(),  -- (snapshot)
		BuildingsChanged  = Knit.CreateSignal(),  -- (snapshot)
		QuestsChanged     = Knit.CreateSignal(),  -- (snapshot)
	},

	-- Server-only fields:
	_profileStore = nil,        -- ProfileService store handle
	_profiles = {},             -- [Player] -> active Profile (ProfileService Profile object)
	_loaded = {},               -- [Player] -> bindable "is fully loaded" flag
})

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function PlayerDataService:KnitInit()
	-- Studio: use a sandbox key so live data isn't polluted by playtests.
	-- Production: use the real key (versioned in GameConfig).
	local storeKey = GameConfig.DataStores.ProfileStore
	if RunService:IsStudio() then
		storeKey = storeKey .. "_studio"
	end
	self._profileStore = ProfileService.GetProfileStore(storeKey, PROFILE_TEMPLATE)
end

function PlayerDataService:KnitStart()
	-- Hook player join/leave. Use Players:GetPlayers() too, in case any player
	-- joined before Knit started up (rare but possible on a slow server).
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_onPlayerAdded(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
end

-- ====================================================================
-- LOAD / UNLOAD
-- ====================================================================

function PlayerDataService:_onPlayerAdded(player: Player)
	-- LoadProfileAsync respects session locking — if the same UserId is logged
	-- in elsewhere, this yields until that session releases the lock or we time out.
	local profile = self._profileStore:LoadProfileAsync("Player_" .. player.UserId, "ForceLoad")
	if not profile then
		-- Couldn't load (rare — DataStore down, locked too long, etc.). The safest
		-- thing is to kick the player so they try again rather than letting them
		-- play with a fresh template that would overwrite their save.
		player:Kick("Couldn't load your save data. Please rejoin in a moment.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile() -- pull in any new template fields added since last login

	-- If the profile is released mid-session (player kicked from another server
	-- claiming the lock, or shutdown), kick them so they don't keep mutating a
	-- detached profile.
	profile:ListenToRelease(function()
		self._profiles[player] = nil
		if player.Parent then
			player:Kick("Your save has been released by another session.")
		end
	end)

	-- Player may have left while we were loading. If so, release immediately.
	if not player.Parent then
		profile:Release()
		return
	end

	self._profiles[player] = profile
	self:_grantStarterAssets(player)

	-- Tell the client. We pass a deep copy so client can't accidentally mutate
	-- server state (Knit RemoteSignals serialize, but defense-in-depth).
	self.Client.ProfileLoaded:Fire(player, self:_publicSnapshot(profile.Data))
end

function PlayerDataService:_onPlayerRemoving(player: Player)
	local profile = self._profiles[player]
	if profile then
		-- Release saves the data and unlocks the session. If we don't call this
		-- the player can't load on another server until the lock times out.
		profile:Release()
	end
	self._profiles[player] = nil
end

-- Grant first-time players a starter dock so they can fish from minute one.
function PlayerDataService:_grantStarterAssets(player: Player)
	local data = self:GetProfile(player)
	if not data then return end
	if #data.buildings == 0 then
		local UidUtil = require(ReplicatedStorage.Shared.Util.UidUtil)
		table.insert(data.buildings, {
			uid = UidUtil.new("bld"),
			kind = "Dock",
			tier = 1,
			gridX = 8,    -- center-ish of plot
			gridZ = 0,    -- flush with water edge
			rotation = 0,
			placedAt = os.time(),
		})
	end
end

-- ====================================================================
-- PUBLIC API (server-side, used by other services)
-- ====================================================================

-- Returns the raw Profile.Data table (mutable). Callers that mutate it MUST
-- also fire the relevant Changed signal so clients update — see the helper
-- methods below for safer alternatives.
function PlayerDataService:GetProfile(player: Player): Profile?
	local p = self._profiles[player]
	return p and p.Data or nil
end

-- Convenience: yields until the profile is loaded. Useful for services that
-- might run their first tick before a player's profile finishes loading.
function PlayerDataService:WaitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 10)
	while os.clock() < deadline do
		local data = self:GetProfile(player)
		if data then return data end
		task.wait(0.1)
		if not player.Parent then return nil end
	end
	return nil
end

-- ============ Currency helpers — every coin change goes through here ============

function PlayerDataService:AddCoins(player: Player, amount: number, reason: string?)
	local data = self:GetProfile(player); if not data then return end
	data.coins += amount
	if amount > 0 then
		data.stats.totalCoinsEarned += amount
	end
	self.Client.CoinsChanged:Fire(player, data.coins, data.lureTokens)
	-- Optional analytics hook: print(reason) and route to AnalyticsService later.
end

function PlayerDataService:TrySpendCoins(player: Player, amount: number): boolean
	local data = self:GetProfile(player); if not data then return false end
	if data.coins < amount then return false end
	data.coins -= amount
	self.Client.CoinsChanged:Fire(player, data.coins, data.lureTokens)
	return true
end

function PlayerDataService:AddLureTokens(player: Player, amount: number)
	local data = self:GetProfile(player); if not data then return end
	data.lureTokens += amount
	self.Client.CoinsChanged:Fire(player, data.coins, data.lureTokens)
end

-- ============ XP / level — single curve, doc'd inline ============

-- XP curve: cumulative XP to reach level L is 50 * L^2. Quadratic so early
-- levels feel quick and late levels reward long-term play. Tweak the 50 to
-- pace progression without changing per-fish XP yields.
local function xpForLevel(level: number): number
	return 50 * level * level
end

function PlayerDataService:AddXP(player: Player, amount: number)
	local data = self:GetProfile(player); if not data then return end
	data.xp += amount
	-- Walk levels in case a single grant pushes through several. Important
	-- for Mythic catches that yield 280 XP early game.
	while data.xp >= xpForLevel(data.level + 1) do
		data.level += 1
	end
	self.Client.XPChanged:Fire(player, data.level, data.xp, xpForLevel(data.level + 1))
end

-- ============ Rod tier ============

-- Single writer for rodTier. Today only ShopService:BuyRodTier calls this;
-- any future upgrade path (achievement, story beat) should route through here
-- too so the RodTierChanged signal always fires and the HUD chip stays live.
function PlayerDataService:SetRodTier(player: Player, tier: number)
	local data = self:GetProfile(player); if not data then return end
	data.rodTier = tier
	self.Client.RodTierChanged:Fire(player, tier)
end

-- Single writer for the equipped named rod. Validates the rodId exists in
-- RodCatalog, then syncs rodTier so fish species access stays consistent.
-- Called by RodService:EquipRod after XP validation.
function PlayerDataService:SetEquippedRod(player: Player, rodId: string)
	local data = self:GetProfile(player); if not data then return end
	local RodCatalog = require(ReplicatedStorage.Shared.Config.RodCatalog)
	local rod = RodCatalog.byId[rodId]
	if not rod then return end
	data.equippedRodId = rodId
	data.rodTier = rod.tier
	self.Client.EquippedRodChanged:Fire(player, rodId)
	self.Client.RodTierChanged:Fire(player, rod.tier)
end

-- ============ Inventory ============

function PlayerDataService:AddItem(player: Player, item: any)
	local data = self:GetProfile(player); if not data then return end
	table.insert(data.inventory, item)
	self.Client.InventoryChanged:Fire(player, data.inventory)
end

-- Remove the inventory entry whose .uid == uid. Returns the removed item or nil.
function PlayerDataService:RemoveItemByUid(player: Player, uid: string): any?
	local data = self:GetProfile(player); if not data then return nil end
	for i, item in ipairs(data.inventory) do
		if item.uid == uid then
			local removed = table.remove(data.inventory, i)
			self.Client.InventoryChanged:Fire(player, data.inventory)
			return removed
		end
	end
	return nil
end

function PlayerDataService:FindItemByUid(player: Player, uid: string): any?
	local data = self:GetProfile(player); if not data then return nil end
	for _, item in ipairs(data.inventory) do
		if item.uid == uid then return item end
	end
	return nil
end

-- ============ Buildings ============

function PlayerDataService:AddBuilding(player: Player, building: any)
	local data = self:GetProfile(player); if not data then return end
	table.insert(data.buildings, building)
	self.Client.BuildingsChanged:Fire(player, data.buildings)
end

function PlayerDataService:RemoveBuildingByUid(player: Player, uid: string): boolean
	local data = self:GetProfile(player); if not data then return false end
	for i, b in ipairs(data.buildings) do
		if b.uid == uid then
			table.remove(data.buildings, i)
			self.Client.BuildingsChanged:Fire(player, data.buildings)
			return true
		end
	end
	return false
end

-- ============ Quests ============

function PlayerDataService:SetQuests(player: Player, quests: any)
	local data = self:GetProfile(player); if not data then return end
	data.dailyQuests = quests
	data.questsRefreshedDay = require(ReplicatedStorage.Shared.Util.TimeUtil).currentUTCDay()
	self.Client.QuestsChanged:Fire(player, data.dailyQuests)
end

function PlayerDataService:NudgeQuestsChanged(player: Player)
	local data = self:GetProfile(player); if not data then return end
	self.Client.QuestsChanged:Fire(player, data.dailyQuests)
end

-- ============ Snapshot for client ============

-- The on-load snapshot. Strip server-only fields if any are added in the
-- future; for now Profile is fine to ship as-is since it doesn't contain
-- secrets.
function PlayerDataService:_publicSnapshot(data: Profile): Profile
	return data
end

-- ====================================================================
-- CLIENT-CALLABLE METHODS (Knit auto-exposes Client/* methods)
-- ====================================================================

-- Client requests a fresh snapshot — used on UI re-init (e.g. after teleport).
function PlayerDataService.Client:GetSnapshot(player: Player): Profile?
	return self.Server:GetProfile(player)
end

-- Client persists a partial Settings change (mute / master volume / motion mode).
-- Server validates every field — the client requests, the server decides. These
-- are pure presentation prefs, so there's no anti-exploit surface beyond keeping
-- the stored values well-formed. Returns the merged settings for reconciliation.
function PlayerDataService.Client:UpdateSettings(player: Player, partial: any): any?
	local data = self.Server:GetProfile(player)
	if not data or type(partial) ~= "table" then return nil end

	local settings = data.settings
	if type(settings) ~= "table" then
		settings = {
			audioMuted = GameConfig.Settings.DefaultMuted,
			masterVolume = GameConfig.Settings.DefaultMasterVolume,
			motionMode = GameConfig.Settings.DefaultMotionMode,
		}
		data.settings = settings
	end

	if type(partial.audioMuted) == "boolean" then
		settings.audioMuted = partial.audioMuted
	end
	if type(partial.masterVolume) == "number" then
		settings.masterVolume = math.clamp(partial.masterVolume, 0, 1)
	end
	if type(partial.motionMode) == "string" then
		for _, mode in ipairs(GameConfig.Settings.MotionModes) do
			if partial.motionMode == mode then
				settings.motionMode = partial.motionMode
				break
			end
		end
	end

	return settings
end

return PlayerDataService
