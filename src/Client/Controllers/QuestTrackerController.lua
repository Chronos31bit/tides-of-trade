--!strict
-- QuestTrackerController.lua
-- Owns the QuestTrackerUI lifecycle: builds it on KnitStart, subscribes
-- to QuestService.Client signals, runs the refresh countdown, and routes
-- Claim clicks back to the server. Holds no game state — every render
-- comes from a server snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local QuestTrackerUI = require(script.Parent.Parent.UI.QuestTrackerUI)

local QuestTrackerController = Knit.CreateController({
	Name = "QuestTrackerController",
	_handle = nil :: any,
	-- Cache the most recent snapshot so we can resolve a QuestCompleted
	-- event to its full quest object (the server fires (questId) only).
	_lastSnapshot = nil :: any,
})

function QuestTrackerController:KnitStart()
	local QuestService = Knit.GetService("QuestService")

	self._handle = QuestTrackerUI.create()

	local function onClaim(questId: string)
		QuestService:Claim(questId):andThen(function(result)
			-- Server-side errors don't need user-visible feedback in the
			-- common case (expired / already_claimed are edge events). The
			-- snapshot push that follows a successful claim will refresh
			-- the tracker on its own.
			if not result or not result.ok then
				return
			end
		end):catch(warn)
	end

	-- Snapshot wiring. Server pushes via QuestsRefreshed on profile load,
	-- daily roll, claim, and every (debounced) progress tick.
	local function applySnapshot(snap: any)
		if not snap then return end
		self._lastSnapshot = snap
		self._handle.refresh(snap, onClaim)
	end

	-- Initial pull. ProfileLoaded may have already fired before this
	-- controller spun up, so we don't rely on it alone.
	QuestService:GetSnapshot():andThen(applySnapshot):catch(warn)
	QuestService.QuestsRefreshed:Connect(applySnapshot)

	-- Completion popup. Resolve the questId against the last-known
	-- snapshot to find the full quest payload for the popup.
	QuestService.QuestCompleted:Connect(function(questId: string)
		local snap = self._lastSnapshot
		if not snap then return end
		for _, q in ipairs(snap.today or {}) do
			if q.id == questId then
				self._handle.queueCompletion(q, onClaim)
				return
			end
		end
	end)

	-- Streak popup (passive — auto-granted server-side).
	QuestService.StreakAdvanced:Connect(function(day: number, reward: any)
		self._handle.queueStreak(day, reward)
	end)

	-- Welcome-back popup (returning player bonus).
	QuestService.WelcomeBack:Connect(function(payload: {daysAway: number, coinsGranted: number})
		self._handle.queueWelcomeBack(payload.daysAway, payload.coinsGranted)
	end)

	-- Refresh countdown ticker. RunService.Heartbeat-throttled to 1 Hz.
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 1.0 then return end
		accum = 0
		self._handle.tickCountdown()
	end)
end

return QuestTrackerController
