--!strict
-- TutorialService.lua
-- Server-authoritative state machine for the 0–25 minute first-session
-- tutorial. Spawns a Mira NPC per player, drives the 6 beats, listens
-- to gameplay signals from Fishing/Harbor/Market services, and persists
-- progress on the player profile so re-joins continue mid-tutorial.
--
-- Architecture rules (CLAUDE.md):
--   * Server is the source of truth for tutorial state. Client requests
--     transitions; this service validates and applies.
--   * State transitions are idempotent — double-fire is a no-op.
--   * Tutorial is one-shot: once tutorial.state == "complete", this
--     service refuses to change it back. No replay path.
--   * Per-player isolation: each player has their own Mira + own state.
--     No global tutorial flow shared between players.
--   * NPC logic lives in src/Server/NPCs/Mira.lua. This service owns the
--     storyline only.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")

local Knit         = require(ReplicatedStorage.Packages.Knit)
local GameConfig   = require(ReplicatedStorage.Shared.Config.GameConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local GridUtil     = require(ReplicatedStorage.Shared.Util.GridUtil)

local Mira = require(script.Parent.Parent.NPCs.Mira)
type MiraInstance = Mira.MiraInstance

local TUNE = GameConfig.Tutorial

local TutorialService = Knit.CreateService({
	Name = "TutorialService",
	Client = {
		-- Full snapshot of tutorial state for this player. Fired on every
		-- transition AND on initial profile load. Client doesn't need to
		-- diff — it just re-renders from the snapshot.
		StateUpdate     = Knit.CreateSignal(),
		-- Mira lifecycle. Sent only to the owning player. Non-owner
		-- clients hide the Mira model via local visibility scan
		-- (TutorialController handles that without a server signal).
		MiraSpawned     = Knit.CreateSignal(),  -- (worldPosition)
		MiraDespawned   = Knit.CreateSignal(),
		-- What the controller should highlight right now. Sent as a string
		-- key ("cast_button", "market_stall", etc.) so the controller
		-- decides what that means visually.
		HighlightSet    = Knit.CreateSignal(),  -- (key | nil)
		-- HUD waypoint nudge — only used in beat 3 if the player doesn't
		-- approach the stall on their own.
		WaypointSet     = Knit.CreateSignal(),  -- (worldPosition | nil)
		-- Flash-only hint for the global market button (beat 4).
		FlashElement    = Knit.CreateSignal(),  -- (key)
	},

	-- internal
	_mira          = {},  -- [Player] -> MiraInstance
	_stuckTimers   = {},  -- [Player] -> { lastCastAttempt: clock, beat2Started: clock }
	_waypointTimers = {}, -- [Player] -> task handle
	_wanderConn    = nil :: any,
})

-- ====================================================================
-- INTERNAL HELPERS
-- ====================================================================

local function getDialogueLines(beatName: string): {string}
	local beat = TutorialConfig.Beats[beatName]
	if not beat then return {} end
	return TutorialConfig.Lines[beat.dialogueKey] or {}
end

local function getBeat(beatName: string)
	return TutorialConfig.Beats[beatName]
end

-- Compute the dock-edge spawn position for Mira given a plot origin and
-- the player's starter dock (gridX=8, gridZ=0). She stands 6 studs along
-- the dock-edge (positive X direction), one stud back from the water
-- edge so she doesn't block the cast point. PLATE_TOP=1.5 matches
-- HarborService's plate height so she stands on the dock surface.
local function miraSpawnForPlot(plotOrigin: CFrame): (Vector3, Vector3)
	local dockGridX, dockGridZ = 8, 0
	local dockLocal = GridUtil.gridToLocal(dockGridX, dockGridZ)
	-- 6 studs offset along the plot's X axis (positive = along the dock
	-- edge away from the corner) plus a small Z offset to keep Mira
	-- *behind* the dock edge rather than over the water.
	local offsetLocal = Vector3.new(dockLocal.X + TUNE.MiraSpawnOffsetStuds, 3.5, dockLocal.Z + 4)
	local pos = (plotOrigin * CFrame.new(offsetLocal)).Position
	-- Face the player's likely spawn direction — back toward the plot
	-- center, away from the water. Plot center is at +PlotSize/2.
	local plotCenter = (plotOrigin * CFrame.new(GameConfig.Harbor.PlotSizeStuds / 2, 3.5, GameConfig.Harbor.PlotSizeStuds / 2)).Position
	return pos, plotCenter
end

-- Send the full state snapshot to the owning client. Client uses this to
-- re-render dialogue and any active highlights.
function TutorialService:_pushState(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local t = data.tutorial; if not t then return end

	local beatMeta = getBeat(t.state)
	local lines = getDialogueLines(t.state)
	-- Beat 5 has affordability-conditional dialogue. Pick the right
	-- array up front so a re-join lands on the correct line for the
	-- player's current coin count.
	if t.state == "first_repair" then
		if data.coins >= TUNE.RepairCostCoins then
			lines = TutorialConfig.Lines.first_repair_ready
		end
	end
	self.Client.StateUpdate:Fire(player, {
		state          = t.state,
		lineIndex      = t.lineIndex,
		lines          = lines,
		speakerName    = TutorialConfig.SpeakerName,
		advanceOn      = beatMeta and beatMeta.advanceOn or "dialogue_end",
		highlight      = beatMeta and beatMeta.highlight or nil,
	})
end

-- Idempotent. Sets tutorial state and lineIndex, pushes to client,
-- runs entry hook for the new beat. Use this for every transition.
function TutorialService:_enterBeat(player: Player, beatName: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local t = data.tutorial; if not t then return end

	-- Defensive: never roll a "complete" profile backwards. Tutorial is
	-- one-shot; subsequent _enterBeat calls (e.g. from a delayed race)
	-- bail out cleanly.
	if t.state == "complete" then return end
	-- Defensive: don't re-enter the beat we're already in. Stops dialogue
	-- from flickering back to line 1 on double-fire.
	if t.state == beatName then return end

	t.state = beatName
	t.lineIndex = 1
	if beatName == "greet" and not t.startedAt then
		t.startedAt = os.time()
	end

	self:_pushState(player)
	self:_onBeatEnter(player, beatName)
end

-- Per-beat entry hooks. Most are no-ops because the dialogue is the
-- entire entry side-effect; some kick off timers (beat 2 stuck) or
-- expensive UI (beat 4 global-market flash).
function TutorialService:_onBeatEnter(player: Player, beatName: string)
	if beatName == "cast_intro" then
		-- Reset the stuck timer; player just entered the beat.
		self._stuckTimers[player] = {
			beatStartedAt = os.clock(),
			lastCastAt    = nil,
			nudgeFiredAt  = 0,
			analyticsFired = false,
		}
	elseif beatName == "first_catch" then
		-- Waypoint to stall fires only if player doesn't approach in
		-- Beat3WaypointDelaySeconds. Cancel any previous waypoint timer.
		if self._waypointTimers[player] then
			task.cancel(self._waypointTimers[player])
		end
		local token = task.delay(TUNE.Beat3WaypointDelaySeconds, function()
			local data = Knit.GetService("PlayerDataService"):GetProfile(player)
			if not data or not data.tutorial then return end
			if data.tutorial.state ~= "first_catch" then return end
			-- Compute stall position from plot origin + a stub offset.
			-- For v1 the stall lives at the dock building. Pointing at
			-- the player's dock is good enough until a dedicated stall
			-- building exists.
			local origin = Knit.GetService("HarborService"):GetPlotOrigin(player)
			if origin then
				local dock = GridUtil.gridToLocal(8, 0)
				local stallPos = (origin * CFrame.new(dock.X + 2, 2, dock.Z + 2)).Position
				self.Client.WaypointSet:Fire(player, stallPos)
			end
		end)
		self._waypointTimers[player] = token
	elseif beatName == "first_sale" then
		-- Mid-beat decoration: flash the global market button once so
		-- the player notices it without being forced to engage.
		self.Client.FlashElement:Fire(player, "market_button")
		local data = Knit.GetService("PlayerDataService"):GetProfile(player)
		if data and data.tutorial then
			data.tutorial.flags.seenGlobalMarketHint = true
		end
	elseif beatName == "first_repair" then
		-- Encouragement repeat cadence — re-armed each beat entry so a
		-- rejoin doesn't immediately re-fire a stale nudge.
		self._stuckTimers[player] = {
			beat5LastNudge = os.clock(),
		}
		self:_checkBeat5Affordable(player)
	end
end

-- Called from dialogue Advance and from gameplay-success listeners.
-- Walks the BeatOrder list to find what comes next, then calls
-- :_enterBeat. If we're at the last beat, no-op (completion is fired
-- explicitly from QuestService:AcceptFirstQuest path).
function TutorialService:_advanceBeat(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local t = data.tutorial; if not t then return end

	local cur = t.state
	for i, beatName in ipairs(TutorialConfig.BeatOrder) do
		if beatName == cur then
			local next_ = TutorialConfig.BeatOrder[i + 1]
			if next_ then
				self:_enterBeat(player, next_)
			end
			return
		end
	end
end

-- ====================================================================
-- BEAT 5 HELPERS
-- ====================================================================

function TutorialService:_checkBeat5Affordable(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	local t = data.tutorial; if not t or t.state ~= "first_repair" then return end

	-- Re-push a state snapshot whose lineIndex jumps to the "ready" key
	-- once the player has 40 coins. The state name stays "first_repair";
	-- the dialogue swap is handled client-side by reading the *_ready
	-- alternate Lines table when coins >= cost. To keep the contract
	-- simple, we send a one-shot dialogue swap event.
	if data.coins >= TUNE.RepairCostCoins then
		self.Client.StateUpdate:Fire(player, {
			state          = t.state,
			lineIndex      = 1,
			lines          = TutorialConfig.Lines.first_repair_ready,
			speakerName    = TutorialConfig.SpeakerName,
			advanceOn      = "gameplay",
			highlight      = "dock_building",
		})
	end
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function TutorialService:KnitStart()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local FishingService    = Knit.GetService("FishingService")
	local MarketService     = Knit.GetService("MarketService")
	local HarborService     = Knit.GetService("HarborService")

	-- Player join: wait for profile + plot, then bootstrap state.
	--
	-- NOTE: pre-launch behavior. There's no "returning-vet auto-complete"
	-- because the game has no real live players yet — every dev profile
	-- with stats > 0 is a playtester who DOES want to see the tutorial.
	-- Post-launch, add a check here that flips state to "complete" for
	-- existing profiles whose stats indicate prior play, so legacy
	-- players don't get onboarded after a deploy. Use the /tutorialreset
	-- admin command in the meantime to wipe state and re-trigger.
	local function onJoin(player: Player)
		local data = PlayerDataService:WaitForProfile(player, 30); if not data then return end
		self:_bootstrapPlayer(player)
	end

	Players.PlayerAdded:Connect(onJoin)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onJoin, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)

	-- ----------------------------------------------------------------
	-- GAMEPLAY HOOKS
	-- ----------------------------------------------------------------
	FishingService.CaughtServer:Connect(function(player, _fishId)
		self:_onFishCaught(player)
	end)
	FishingService.CastStartedServer:Connect(function(player)
		local timer = self._stuckTimers[player]
		if timer then timer.lastCastAt = os.clock() end
	end)
	MarketService.SoldServer:Connect(function(player, _payout, _kind)
		self:_onSold(player)
	end)
	HarborService.BuildingUpgradedServer:Connect(function(player, _uid, kind, oldTier, newTier)
		self:_onBuildingUpgraded(player, kind, oldTier, newTier)
	end)

	-- Coin gain hook for beat 5's waiting state. Re-check every coin
	-- change; if the player has just crossed the 40-coin line, swap to
	-- the "you've got enough" dialogue.
	PlayerDataService.Client.CoinsChanged:Connect(function(player, _newCoins, _lure)
		self:_checkBeat5Affordable(player)
	end)

	-- Stuck nudges + analytics + wander check. Single Heartbeat-throttled
	-- loop instead of per-player tasks so we keep the moving-parts count
	-- low. Doesn't run while no one is in tutorial.
	self._wanderConn = RunService.Heartbeat:Connect(function()
		self:_tick()
	end)
	-- Throttle the tick to once a second; Heartbeat:Wait + accumulator
	-- pattern lives inside _tick.
end

-- Time-based checks: beat 2 stuck nudges, wander recall, beat 3
-- proximity detection. Called every Heartbeat but only does real work
-- once per second (cheap O(active tutorial players)).
function TutorialService:_tick()
	local now = os.clock()
	self._lastTick = self._lastTick or 0
	if now - self._lastTick < 1.0 then return end
	self._lastTick = now

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local HarborService     = Knit.GetService("HarborService")

	for player, mira in pairs(self._mira) do
		local data = PlayerDataService:GetProfile(player); if not data or not data.tutorial then continue end
		local t = data.tutorial
		if t.state == "complete" then continue end

		-- Beat 2 stuck check.
		if t.state == "cast_intro" then
			local timer = self._stuckTimers[player]
			if timer and not timer.lastCastAt then
				local sinceStart = now - timer.beatStartedAt
				if sinceStart >= TUNE.Beat2StuckTimeoutSeconds and now - timer.nudgeFiredAt >= TUNE.Beat2StuckRepeatSeconds then
					-- Send the nudge dialogue. Cycles through the
					-- cast_intro_stuck lines based on how many times
					-- we've nudged.
					timer.nudgeFiredAt = now
					timer.nudgeCount = (timer.nudgeCount or 0) + 1
					local pool = TutorialConfig.Lines.cast_intro_stuck
					local line = pool[((timer.nudgeCount - 1) % #pool) + 1]
					self.Client.StateUpdate:Fire(player, {
						state       = t.state,
						lineIndex   = 1,
						lines       = { line },
						speakerName = TutorialConfig.SpeakerName,
						advanceOn   = "gameplay",
						highlight   = "cast_button",
					})
				end
				if sinceStart >= TUNE.Beat2AnalyticsStuckSeconds and not timer.analyticsFired then
					timer.analyticsFired = true
					print(string.format("[Analytics] TutorialStuck player=%s beat=cast_intro elapsed=%ds", player.Name, math.floor(sinceStart)))
				end
			end
		end

		-- Beat 5 waiting-state encouragement: every 30s while the player
		-- can't afford the repair, Mira repeats "Catch a few more —
		-- you're almost there." Cleared when coins >= cost (the
		-- CoinsChanged hook swaps to the "ready" line directly).
		if t.state == "first_repair" and data.coins < TUNE.RepairCostCoins then
			local timer = self._stuckTimers[player]
			if timer and now - (timer.beat5LastNudge or 0) >= TUNE.Beat5EncouragementRepeatSeconds then
				timer.beat5LastNudge = now
				self.Client.StateUpdate:Fire(player, {
					state       = t.state,
					lineIndex   = 1,
					lines       = TutorialConfig.Lines.first_repair_waiting,
					speakerName = TutorialConfig.SpeakerName,
					advanceOn   = "gameplay",
					highlight   = "dock_building",
				})
			end
		end

		-- Beat 3 stall proximity.
		if t.state == "first_catch" then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local origin = HarborService:GetPlotOrigin(player)
			if hrp and origin then
				local dock = GridUtil.gridToLocal(8, 0)
				local stallPos = (origin * CFrame.new(dock.X + 2, 2, dock.Z + 2)).Position
				local hasFish = false
				for _, item in ipairs(data.inventory) do
					if item.kind == "Fish" then hasFish = true; break end
				end
				if hasFish and (hrp.Position - stallPos).Magnitude < TUNE.Beat3StallProximityStuds then
					self:_advanceBeat(player)
					-- Clear the waypoint when the player arrives so it
					-- doesn't keep pointing after success.
					self.Client.WaypointSet:Fire(player, nil)
				end
			end
		end

		-- Wander recall — disabled by default. The previous behavior
		-- respawned Mira next to the player every tick once they
		-- stepped outside the 80-stud radius, which read as "Mira is
		-- chasing me." Reinstate behind a config flag only after we
		-- have a proper one-shot debounce + walk-toward-player anim.
		-- For now Mira stays put on the dock and the player walks
		-- back to her, which is the cozy-game-correct behavior anyway.
	end
end

-- ====================================================================
-- BOOTSTRAP / CLEANUP
-- ====================================================================

function TutorialService:_bootstrapPlayer(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local HarborService     = Knit.GetService("HarborService")
	local FishingService    = Knit.GetService("FishingService")

	local data = PlayerDataService:GetProfile(player); if not data then return end
	local t = data.tutorial
	if not t then
		-- Profile pre-dates the tutorial system. Reconcile should have
		-- filled it; bail defensively if not.
		return
	end

	if t.state == "complete" then
		-- No Mira, no dialogue. Just sync the state to the client so its
		-- HUD knows the tutorial is over.
		self:_pushState(player)
		return
	end

	-- First-time player: teleport to the dock so Mira's spawn position
	-- is meaningful. TODO: HarborService should own first-spawn
	-- placement permanently (out of scope for this task).
	if t.state == "not_started" then
		-- Wait briefly for the plot to exist (HarborService runs in
		-- parallel and may not have finished yet).
		local origin
		for _ = 1, 30 do
			origin = HarborService:GetPlotOrigin(player)
			if origin then break end
			task.wait(0.1)
			if not player.Parent then return end
		end
		if origin then
			local char = player.Character or player.CharacterAdded:Wait()
			local hrp = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
			if hrp then
				local dock = GridUtil.gridToLocal(8, 0)
				hrp.CFrame = origin * CFrame.new(dock.X + 4, 6, dock.Z + 6)
			end
		end
		self:_enterBeat(player, "greet")
	else
		-- Mid-tutorial rejoin. Push current state, spawn Mira at the
		-- current dock spawn position regardless of which beat. The
		-- client picks up dialogue at t.lineIndex (which we don't reset
		-- so the player resumes mid-line if they logged out
		-- mid-conversation).
		self:_pushState(player)
	end

	-- Wire up beginner assist if the player has assists left.
	if t.beginnerAssistsRemaining and t.beginnerAssistsRemaining > 0 then
		FishingService:SetAssistMultiplier(player, TUNE.BeginnerAssistMultiplier)
	end

	-- Spawn Mira (any state other than complete; we already returned for
	-- complete above).
	self:_spawnMiraFor(player)
end

function TutorialService:_cleanupPlayer(player: Player)
	local mira = self._mira[player]
	if mira then mira:Despawn() end
	self._mira[player] = nil
	self._stuckTimers[player] = nil
	if self._waypointTimers[player] then
		task.cancel(self._waypointTimers[player])
		self._waypointTimers[player] = nil
	end
end

function TutorialService:_spawnMiraFor(player: Player)
	if self._mira[player] then return end
	local HarborService = Knit.GetService("HarborService")
	local origin = HarborService:GetPlotOrigin(player)
	if not origin then return end
	local pos, lookAt = miraSpawnForPlot(origin)
	local mira = Mira.Spawn(player, pos, lookAt)
	self._mira[player] = mira
	self.Client.MiraSpawned:Fire(player, pos)
end

function TutorialService:_recallMira(player: Player)
	local mira = self._mira[player]
	if not mira then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	-- Re-spawn near the player. Cheaper than WalkTo since the player may
	-- have run far enough that the walk would take 30 seconds.
	mira:Despawn()
	self._mira[player] = nil
	local nearby = hrp.Position + Vector3.new(4, 0, 0)
	local newMira = Mira.Spawn(player, nearby, hrp.Position)
	self._mira[player] = newMira
	self.Client.MiraSpawned:Fire(player, nearby)
	-- Recall line — one-shot dialogue overlay, doesn't change state.
	self.Client.StateUpdate:Fire(player, {
		state       = "wander_recall",  -- not a real beat; client treats as transient
		lineIndex   = 1,
		lines       = TutorialConfig.Lines.wander_recall,
		speakerName = TutorialConfig.SpeakerName,
		advanceOn   = "transient",
	})
end

-- ====================================================================
-- BEAT-SPECIFIC HANDLERS
-- ====================================================================

function TutorialService:_onFishCaught(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local FishingService    = Knit.GetService("FishingService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.tutorial then return end
	local t = data.tutorial

	-- Decrement beginner assist counter (only on success — failed casts
	-- don't drain assists, per spec).
	if t.beginnerAssistsRemaining and t.beginnerAssistsRemaining > 0 then
		t.beginnerAssistsRemaining -= 1
		if t.beginnerAssistsRemaining <= 0 then
			FishingService:ClearAssist(player)
		end
	end

	-- Beat 2 -> Beat 3 transition: first catch from cast_intro.
	if t.state == "cast_intro" then
		self:_enterBeat(player, "first_catch")
	end
end

function TutorialService:_onSold(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.tutorial then return end
	local t = data.tutorial
	if t.state == "first_sale" then
		self:_advanceBeat(player)
	end
end

function TutorialService:_onBuildingUpgraded(player: Player, kind: string, oldTier: number, newTier: number)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.tutorial then return end
	local t = data.tutorial
	-- Beat 5 success: Dock specifically, tier 1 -> 2. We trust the
	-- HarborVisualUpdate signal (via this server signal) so admin tools
	-- or any other upgrade path still triggers the beat.
	if t.state == "first_repair" and kind == "Dock" and oldTier == 1 and newTier == 2 then
		self:_advanceBeat(player)
	end
end

-- ====================================================================
-- COMPLETION (called from QuestService.Client:AcceptFirstQuest)
-- ====================================================================
function TutorialService:CompleteFromQuestAccept(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local FishingService    = Knit.GetService("FishingService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.tutorial then return end
	local t = data.tutorial
	if t.state == "complete" then return end

	local startedAt = t.startedAt or os.time()
	t.state = "complete"
	t.completedAt = os.time()
	-- Forfeit any unused assists. Per spec: completing forfeits remaining.
	t.beginnerAssistsRemaining = 0
	FishingService:ClearAssist(player)

	-- Play farewell, then despawn Mira.
	self.Client.StateUpdate:Fire(player, {
		state       = "farewell",
		lineIndex   = 1,
		lines       = TutorialConfig.Lines.farewell,
		speakerName = TutorialConfig.SpeakerName,
		advanceOn   = "transient",
	})
	task.delay(3.0, function()
		local mira = self._mira[player]
		if mira then
			-- Brief walk-off animation: walk 12 studs away from her
			-- current facing, then despawn.
			local from = mira:GetPosition()
			mira:WalkTo(from + Vector3.new(-10, 0, 0))
			task.delay(1.2, function()
				if self._mira[player] == mira then
					mira:Despawn()
					self._mira[player] = nil
					self.Client.MiraDespawned:Fire(player)
				end
			end)
		end
	end)

	-- Push the final state so HUD/tutorial UI fully retire.
	task.delay(4.5, function()
		self:_pushState(player)
	end)

	local duration = os.time() - startedAt
	print(string.format("[Analytics] Tutorial complete in %d seconds (player=%s)", duration, player.Name))
end

-- ====================================================================
-- CLIENT-CALLABLE
-- ====================================================================

-- Snapshot pull (used on controller init).
function TutorialService.Client:GetState(player: Player)
	local data = Knit.GetService("PlayerDataService"):GetProfile(player)
	if not data or not data.tutorial then return nil end
	local t = data.tutorial
	local beatMeta = getBeat(t.state)
	local lines = getDialogueLines(t.state)
	-- Mirror the affordability-aware logic from :_pushState so a snapshot
	-- pull right after a coin grant returns the correct dialogue.
	if t.state == "first_repair" and data.coins >= TUNE.RepairCostCoins then
		lines = TutorialConfig.Lines.first_repair_ready
	end
	return {
		state       = t.state,
		lineIndex   = t.lineIndex,
		lines       = lines,
		speakerName = TutorialConfig.SpeakerName,
		advanceOn   = beatMeta and beatMeta.advanceOn or "dialogue_end",
		highlight   = beatMeta and beatMeta.highlight or nil,
	}
end

-- Player pressed Continue on the dialogue box.
function TutorialService.Client:AdvanceDialogue(player: Player)
	local self = self.Server
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data or not data.tutorial then return end
	local t = data.tutorial
	if t.state == "complete" then return end

	local beatMeta = getBeat(t.state)
	if not beatMeta then return end  -- transient overlay (recall/farewell) — ignore advance
	local lines = TutorialConfig.Lines[beatMeta.dialogueKey] or {}

	if t.lineIndex < #lines then
		t.lineIndex += 1
		self:_pushState(player)
		return
	end

	-- On last line:
	if beatMeta.advanceOn == "dialogue_end" then
		self:_advanceBeat(player)
	end
	-- For "gameplay" beats we just stay put — next advance comes from
	-- the gameplay hook (catch / sell / upgrade / accept). The dialogue
	-- box closes itself client-side on the last line.
end

-- Dismiss + re-open: state preserved; controller hides UI on Dismiss
-- and shows the "talk to Mira" prompt; ReopenDialogue is a no-op on
-- the server (state is already correct), it just re-pushes the
-- snapshot so the controller can re-render.
function TutorialService.Client:ReopenDialogue(player: Player)
	local self = self.Server
	self:_pushState(player)
end

return TutorialService
