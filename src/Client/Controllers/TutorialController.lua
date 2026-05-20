--!strict
-- TutorialController.lua
-- Drives the tutorial dialogue UI, highlights, waypoints, and the
-- per-player Mira visibility filter. Receives state snapshots from
-- TutorialService.StateUpdate and re-renders from those — never
-- decides state itself.
--
-- Non-owner Mira hiding: every client scans Workspace.TutorialNPCs on
-- ChildAdded and applies LocalTransparencyModifier=1 to every part
-- whose ownerUserId attribute is not the LocalPlayer.UserId. The owner
-- sees Mira; everyone else sees nothing for that specific Mira (but
-- still sees the floating name tag, which is intentional — visiting
-- players know a captain lives here).

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")
local GuiService       = game:GetService("GuiService")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local UIUtil     = require(script.Parent.Parent.UI.UIUtil)
local DialogueUI = require(script.Parent.Parent.UI.DialogueUI)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local TUNE = GameConfig.Tutorial
local LP = Players.LocalPlayer

local TutorialController = Knit.CreateController({
	Name = "TutorialController",
	_dialogue = nil :: any,
	_state = nil :: any,             -- last received state snapshot
	_dismissed = false,              -- player pressed X; show "talk to mira" prompt
	_talkPromptButton = nil :: any,
	_activeHighlight = nil :: any,
	_waypoint = nil :: any,
	_autoDismissToken = 0,           -- bumped per render; running task checks it to bail
	_objectiveGui = nil :: any,
	_objectiveLabel = nil :: any,
})

-- Per-beat objective text shown in the persistent pill at the top of
-- the screen. Distinct from the dialogue body (which is Mira's voice)
-- — this is the player-facing "what do I do next" cue and stays on
-- screen the entire time the beat is active.
local OBJECTIVE_TEXT: {[string]: string} = {
	greet            = "Talk to Captain Mira",
	cast_intro       = "Catch your first fish",
	first_catch      = "Bring the fish to Mira's stall",
	first_sale       = "Sell the fish at the stall",
	first_repair     = "Repair the dock (40 coins)",
	daily_quest_hook = "Accept your first daily quest",
}

-- ====================================================================
-- HIGHLIGHTS — visual cues over world objects or HUD elements
-- ====================================================================
-- Each highlight key maps to a function that returns the Instance to
-- highlight + the kind of highlight ("world" via SelectionBox, "hud"
-- via UIStroke tween). Centralized so adding new highlight keys is
-- one-line.

local function findMiraModel(): Model?
	local container = Workspace:FindFirstChild("TutorialNPCs")
	if not container then return nil end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("ownerUserId") == LP.UserId then
			return child
		end
	end
	return nil
end

local function findDockBuildingPart(): BasePart?
	-- HarborService spawns invisible anchor parts under
	-- Workspace.Plot_<n>_<PlayerName>; the part's Name is the building
	-- uid and attributes include kind/tier. Find the Dock anchor for
	-- the local player.
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Folder") and child.Name:find(LP.Name) then
			for _, part in ipairs(child:GetChildren()) do
				if part:IsA("BasePart") and part:GetAttribute("kind") == "Dock" then
					return part
				end
			end
		end
	end
	return nil
end

local function makeSelectionBox(adornee: Instance): SelectionBox
	local sb = Instance.new("SelectionBox")
	sb.Adornee = adornee
	sb.Color3 = UIUtil.Palette.Sunset
	sb.LineThickness = 0.12
	sb.SurfaceTransparency = 0.7
	sb.SurfaceColor3 = UIUtil.Palette.Sunset
	sb.Parent = adornee
	return sb
end

function TutorialController:_clearHighlight()
	if self._activeHighlight then
		if self._activeHighlight.Destroy then
			pcall(function() self._activeHighlight:Destroy() end)
		end
		self._activeHighlight = nil
	end
end

function TutorialController:_applyHighlight(key: string?)
	self:_clearHighlight()
	if not key then return end

	if key == "dock_building" then
		local part = findDockBuildingPart()
		if part then self._activeHighlight = makeSelectionBox(part) end
	elseif key == "market_stall" then
		-- No dedicated stall building yet — point at the dock part as
		-- the "stall" surrogate. When a real stall lands, swap the
		-- adornee here.
		local part = findDockBuildingPart()
		if part then self._activeHighlight = makeSelectionBox(part) end
	end
	-- cast_button / quest_tracker / global_market_flash are HUD elements;
	-- those are handled by HUD-side hint tweens via FlashElement and
	-- the highlight set is ignored for them client-side (we don't have
	-- structured access into HUDController's children from here without
	-- coupling).
end

-- ====================================================================
-- WAYPOINT — billboard arrow over a world position
-- ====================================================================
function TutorialController:_clearWaypoint()
	if self._waypoint then
		self._waypoint:Destroy()
		self._waypoint = nil
	end
end

function TutorialController:_setWaypoint(worldPos: Vector3)
	self:_clearWaypoint()
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = worldPos + Vector3.new(0, 8, 0)
	part.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Adornee = part
	bb.Size = UDim2.fromOffset(60, 60)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 36
	lbl.TextColor3 = UIUtil.Palette.Sunset
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = "▼"
	lbl.Parent = bb

	-- Gentle bob so the arrow reads as a UI element, not world geometry.
	-- Skip animation when ReducedMotion is on (MotionUtil snap-pattern).
	if not GuiService.ReducedMotionEnabled then
		task.spawn(function()
			while part.Parent do
				MotionUtil.tween(part, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Position = worldPos + Vector3.new(0, 10, 0),
				})
				task.wait(0.6)
				MotionUtil.tween(part, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Position = worldPos + Vector3.new(0, 8, 0),
				})
				task.wait(0.6)
			end
		end)
	end

	self._waypoint = part
end

-- ====================================================================
-- OBJECTIVE PILL — persistent "what to do next" indicator
-- ====================================================================
function TutorialController:_showObjective(text: string?)
	if not text or text == "" then
		self:_hideObjective()
		return
	end
	if not self._objectiveGui then
		local gui, _ = UIUtil.makeScreenGui("TutorialObjective", nil, { respectTopbar = true })
		gui.DisplayOrder = TUNE.DialogueZIndex
		local pill = UIUtil.makePanel({
			Name = "Pill",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.fromOffset(360, 44),
			BackgroundColor3 = UIUtil.Palette.TealDeeper,
		})
		pill.Parent = gui

		local arrow = UIUtil.makeLabel("▸", "title", {
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.fromOffset(20, 44),
			TextColor3 = UIUtil.Palette.Sunset,
		})
		arrow.Parent = pill

		local lbl = UIUtil.makeLabel("", "subtitle", {
			Position = UDim2.new(0, 36, 0, 0),
			Size = UDim2.new(1, -48, 1, 0),
			TextColor3 = UIUtil.Palette.Cream,
			TextSize = 14,
		})
		lbl.Parent = pill
		self._objectiveGui = gui
		self._objectiveLabel = lbl
	end
	self._objectiveLabel.Text = text
	self._objectiveGui.Enabled = true
end

function TutorialController:_hideObjective()
	if self._objectiveGui then self._objectiveGui.Enabled = false end
end

-- ====================================================================
-- "TALK TO MIRA" prompt — appears when dialogue is dismissed
-- ====================================================================
function TutorialController:_showTalkPrompt()
	if self._talkPromptButton then return end
	local gui, _ = UIUtil.makeScreenGui("TutorialTalkPrompt", nil, { respectTopbar = true })
	gui.DisplayOrder = TUNE.DialogueZIndex

	-- Top-center, below the objective pill (pill is at y=12, h=44, so
	-- this sits at y=64 with a small gap). Smaller than the default
	-- makeButton so it reads as a transient hint, not a primary CTA.
	local btn = UIUtil.makeButton("Talk to Captain Mira", function()
		self:_reopenDialogue()
	end, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(200, 36),
	})
	btn.Parent = gui
	self._talkPromptButton = gui
end

function TutorialController:_hideTalkPrompt()
	if self._talkPromptButton then
		self._talkPromptButton:Destroy()
		self._talkPromptButton = nil
	end
end

-- ====================================================================
-- DIALOGUE RENDER
-- ====================================================================

function TutorialController:_renderState(state: any)
	self._state = state
	if not state or state.state == "complete" then
		-- Tutorial done — tear everything down.
		if self._dialogue then self._dialogue:Hide() end
		self:_clearHighlight()
		self:_clearWaypoint()
		self:_hideTalkPrompt()
		self:_hideObjective()
		return
	end

	-- Persistent objective pill at the top of the screen. Updates on
	-- every state change so the player always knows what to do next
	-- even after the dialogue auto-hides. Transient overlays don't
	-- update it.
	if state.advanceOn ~= "transient" then
		self:_showObjective(OBJECTIVE_TEXT[state.state])
	end

	-- Refresh highlight based on the beat's hint.
	self:_applyHighlight(state.highlight)

	-- If the user dismissed dialogue with X, keep it hidden; the talk
	-- prompt is already on screen.
	if self._dismissed then return end

	-- Pull the line at state.lineIndex.
	local lines = state.lines or {}
	local idx = math.clamp(state.lineIndex or 1, 1, math.max(#lines, 1))
	local line = lines[idx] or ""
	if not self._dialogue then
		self._dialogue = DialogueUI.create(state.speakerName or TutorialConfig.SpeakerName)
		self:_wireDialogue()
	end
	self._dialogue:SetLine(line, state.speakerName)
	self._dialogue:Show()
	self:_refreshContinueLabel()
	self:_scheduleAutoDismiss(state)
end

-- Auto-hide the dialogue after a few seconds so it doesn't sit over the
-- cast meter / action bar while the player is mid-gameplay. State is
-- preserved server-side — the talk-to-Mira prompt and her
-- ProximityPrompt both re-open at the current line.
function TutorialController:_scheduleAutoDismiss(state: any)
	self._autoDismissToken += 1
	local token = self._autoDismissToken
	-- Transient overlays (wander_recall, farewell, repeat nudges) get a
	-- shorter timeout since their job is to flash and clear.
	local isTransient = state.advanceOn == "transient" or state.state == "wander_recall" or state.state == "farewell"
	local delaySec = isTransient
		and TUNE.DialogueAutoDismissTransientSeconds
		or TUNE.DialogueAutoDismissSeconds

	task.delay(delaySec, function()
		if self._autoDismissToken ~= token then return end
		if not self._dialogue then return end
		if self._dismissed then return end
		self._dialogue:Hide()
		-- No talk-prompt button on auto-dismiss — Mira's own
		-- ProximityPrompt is enough to re-engage. The floating button
		-- only appears on explicit X press, where the player
		-- specifically asked to dismiss but might forget about Mira.
	end)
end

function TutorialController:_wireDialogue()
	local TutorialService = Knit.GetService("TutorialService")
	local QuestService    = Knit.GetService("QuestService")
	self._dialogue:SetOnContinue(function()
		-- Special-case beat 6: on the last dialogue line, the Continue
		-- button doubles as the daily-quest Accept hook. Server flips
		-- tutorial.state to "complete" inside AcceptFirstQuest.
		local s = self._state
		if s and s.state == "daily_quest_hook" then
			local lines = s.lines or {}
			if s.lineIndex >= #lines then
				QuestService:AcceptFirstQuest()
				return
			end
		end
		-- Default path — server validates and advances.
		TutorialService:AdvanceDialogue()
	end)
	self._dialogue:SetOnClose(function()
		self._dismissed = true
		self._dialogue:Hide()
		self:_showTalkPrompt()
	end)
end

-- Refresh the Continue button's label depending on the current state.
-- Beat 6's final line says "Accept Quest" rather than "Continue ▸" so
-- the daily-quest handoff reads clearly. All other states use the
-- default label.
function TutorialController:_refreshContinueLabel()
	if not self._dialogue or not self._state then return end
	local s = self._state
	local lines = s.lines or {}
	local lastLine = s.lineIndex and s.lineIndex >= #lines
	if s.state == "daily_quest_hook" and lastLine then
		self._dialogue.continueButton.Text = "Accept Quest"
	else
		self._dialogue.continueButton.Text = "Continue ▸"
	end
end

function TutorialController:_reopenDialogue()
	self._dismissed = false
	self:_hideTalkPrompt()
	if self._state then self:_renderState(self._state) end
	-- Also nudge the server for a fresh snapshot in case state advanced
	-- while UI was dismissed.
	Knit.GetService("TutorialService"):ReopenDialogue()
end

-- ====================================================================
-- NON-OWNER MIRA VISIBILITY FILTER
-- ====================================================================
-- Run once per Mira model that appears in Workspace.TutorialNPCs. The
-- *owner* sees Mira normally; everyone else gets LocalTransparencyModifier=1
-- applied to every part (name tag stays visible since BillboardGui isn't
-- a BasePart).
local function applyVisibilityFilter(model: Model)
	-- Defensive: if the ownerUserId attribute isn't set yet, don't hide
	-- anything (better to briefly see another player's Mira than to
	-- accidentally hide our own when the attribute races behind the
	-- ChildAdded). Re-evaluates on attribute change.
	local function evaluate()
		local ownerId = model:GetAttribute("ownerUserId")
		local hide = ownerId ~= nil and ownerId ~= LP.UserId
		local mod = hide and 1 or 0
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = mod
			end
		end
	end
	evaluate()
	model:GetAttributeChangedSignal("ownerUserId"):Connect(evaluate)
	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			local ownerId = model:GetAttribute("ownerUserId")
			local hide = ownerId ~= nil and ownerId ~= LP.UserId
			descendant.LocalTransparencyModifier = hide and 1 or 0
		end
	end)
end

local function watchNPCContainer()
	local function hook(container: Instance)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") then applyVisibilityFilter(child) end
		end
		container.ChildAdded:Connect(function(child)
			if child:IsA("Model") then applyVisibilityFilter(child) end
		end)
	end
	local existing = Workspace:FindFirstChild("TutorialNPCs")
	if existing then
		hook(existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "TutorialNPCs" then hook(child) end
	end)
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function TutorialController:KnitStart()
	local TutorialService = Knit.GetService("TutorialService")
	local ProximityPromptService = game:GetService("ProximityPromptService")

	watchNPCContainer()

	-- ProximityPrompt on Mira (added server-side in NPCs/Mira.lua) re-
	-- opens the dialogue at the current state line. The prompt only
	-- fires on the owner client because Mira is invisible to others.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggerer)
		if triggerer ~= LP then return end
		if prompt.ObjectText ~= "Captain Mira" then return end
		self:_reopenDialogue()
	end)

	-- Initial state pull (in case StateUpdate already fired before this
	-- controller's KnitStart ran).
	TutorialService:GetState():andThen(function(state)
		if state then self:_renderState(state) end
	end)

	TutorialService.StateUpdate:Connect(function(state)
		self:_renderState(state)
	end)

	TutorialService.MiraSpawned:Connect(function(_pos)
		-- Refresh highlight now that the model exists; some highlights
		-- target Mira-adjacent geometry.
		if self._state then self:_applyHighlight(self._state.highlight) end
	end)

	TutorialService.MiraDespawned:Connect(function()
		self:_clearHighlight()
		self:_clearWaypoint()
	end)

	TutorialService.HighlightSet:Connect(function(key)
		self:_applyHighlight(key)
	end)

	TutorialService.WaypointSet:Connect(function(worldPos)
		if worldPos then
			self:_setWaypoint(worldPos)
		else
			self:_clearWaypoint()
		end
	end)

	TutorialService.FlashElement:Connect(function(key)
		-- Best-effort flash for HUD-internal elements. The HUD owns
		-- those buttons so we reach into PlayerGui by ScreenGui name to
		-- find them. Failure to find = silent no-op (tutorial spec says
		-- the flash is decoration, not load-bearing).
		if key == "market_button" then
			local pg = LP:FindFirstChildOfClass("PlayerGui")
			local hud = pg and pg:FindFirstChild("HUD")
			local btn = hud and hud:FindFirstChild("MarketButton", true)
			if btn and btn:IsA("GuiObject") then
				local original = btn.BackgroundColor3
				local tween = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 2, true)
				MotionUtil.tween(btn, tween, { BackgroundColor3 = UIUtil.Palette.Sunset })
				task.delay(2.5, function()
					btn.BackgroundColor3 = original
				end)
			end
		end
	end)
end

return TutorialController
