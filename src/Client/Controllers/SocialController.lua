--!strict
-- SocialController.lua
-- v1 social UI: emote buttons via SocialService round-trip. Crew browser
-- placeholder card lives in SocialUI; this controller opens/closes the panel,
-- forwards PlayEmote, and plays emote animations on EmotePlayed.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local SocialUI   = require(script.Parent.Parent.UI.SocialUI)
local UIKit      = require(script.Parent.Parent.UI.UIKit)

local EMOTES = { "wave", "dance", "fish_pose", "salute", "bow" }

-- How many crew-chat messages to retain client-side so the panel can replay
-- recent history when reopened. Matches SocialUI's MAX_CHAT_ROWS render cap.
local MAX_CHAT_LOG = 50

type EmoteState = {
	tracks: { AnimationTrack },
	char: Model?,
}

local SocialController = Knit.CreateController({
	Name = "SocialController",
	_open = false,
	_handle = nil :: any,
	_emoteTrove = nil :: any,
	_animFolder = nil :: Folder?,
	_activeByUserId = {} :: {[number]: EmoteState},
	_warnedMissingAssets = false,
	_chatLog = {} :: { {from: string, message: string} },
	_mutedNames = {} :: {[string]: boolean},
})

local function emoteCfg(): {[string]: any}
	return (GameConfig :: any).Social.Emotes
end

function SocialController:_resolveAnimFolder(): Folder?
	if self._animFolder then
		return self._animFolder
	end
	local path = GameConfig.Assets.Emotes
	local node: Instance = ReplicatedStorage
	for segment in string.gmatch(path, "[^%.]+") do
		local child = node:FindFirstChild(segment)
		if not child then
			if not self._warnedMissingAssets then
				self._warnedMissingAssets = true
				warn(("[SocialController] Missing %s — run scripts/Studio/CommandBar_SetupEmoteAnimations.luau"):format(path))
			end
			return nil
		end
		node = child
	end
	if node:IsA("Folder") then
		self._animFolder = node
		return node
	end
	return nil
end

function SocialController:_stopEmotesForUser(userId: number, fadeOut: number?)
	local state = self._activeByUserId[userId]
	if not state then return end
	local fade = fadeOut or emoteCfg().FadeOutSeconds
	for _, track in ipairs(state.tracks) do
		if track.IsPlaying then
			track:Stop(fade)
		end
	end
	table.clear(state.tracks)
end

function SocialController:_clearUserState(userId: number)
	self:_stopEmotesForUser(userId, 0)
	self._activeByUserId[userId] = nil
end

function SocialController:_bindPlayer(player: Player)
	self._emoteTrove:Add(player.CharacterAdded:Connect(function()
		self:_stopEmotesForUser(player.UserId, 0)
		local state = self._activeByUserId[player.UserId]
		if state then
			state.char = player.Character
		end
	end))
end

-- future: emote particles (skipped when UIKit.reducedMotion())
local function maybeEmoteParticles(_char: Model, _emoteId: string)
	if UIKit.reducedMotion() then
		return
	end
end

function SocialController:_playEmoteForUser(userId: number, emoteId: string)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local folder = self:_resolveAnimFolder()
	if not folder then return end

	local animInst = folder:FindFirstChild(emoteId)
	if not animInst or not animInst:IsA("Animation") then
		warn(("[SocialController] No Animation for emote %q in %s"):format(emoteId, GameConfig.Assets.Emotes))
		return
	end

	local cfg = emoteCfg()
	local fadeIn: number = cfg.FadeInSeconds
	local fadeOut: number = cfg.FadeOutSeconds
	local maxConcurrent: number = cfg.MaxConcurrent

	self:_stopEmotesForUser(userId, fadeOut)

	local state = self._activeByUserId[userId]
	if not state then
		state = { tracks = {}, char = char }
		self._activeByUserId[userId] = state
	else
		state.char = char
	end

	local track = humanoid:LoadAnimation(animInst)
	track.Priority = Enum.AnimationPriority.Action
	track:Play(fadeIn)
	table.insert(state.tracks, track)

	while #state.tracks > maxConcurrent do
		local oldest = table.remove(state.tracks, 1)
		if oldest and oldest.IsPlaying then
			oldest:Stop(fadeOut)
		end
	end

	maybeEmoteParticles(char, emoteId)
end

function SocialController:KnitStart()
	self._emoteTrove = Trove.new()

	local SocialService = Knit.GetService("SocialService")
	self._emoteTrove:Add(SocialService.EmotePlayed:Connect(function(userId, emoteId)
		self:_playEmoteForUser(userId, emoteId)
	end))
	self._emoteTrove:Add(SocialService.CrewChat:Connect(function(fromName, message)
		self:_onCrewChat(fromName, message)
	end))

	self._emoteTrove:Add(Players.PlayerRemoving:Connect(function(player)
		self:_clearUserState(player.UserId)
	end))

	for _, player in ipairs(Players:GetPlayers()) do
		self:_bindPlayer(player)
	end
	self._emoteTrove:Add(Players.PlayerAdded:Connect(function(player)
		self:_bindPlayer(player)
	end))

	task.defer(function()
		self:_resolveAnimFolder()
	end)
end

-- Crew-chat messages arrive here (server fans out to every member on this
-- server, including the sender). Keep a capped history so reopening the panel
-- replays recent chatter, and live-append when the panel is open.
function SocialController:_onCrewChat(fromName: string, message: string)
	table.insert(self._chatLog, { from = fromName, message = message })
	while #self._chatLog > MAX_CHAT_LOG do
		table.remove(self._chatLog, 1)
	end
	-- Skip muted senders in live chat (but keep in log for panel replay).
	if self._mutedNames[fromName] then return end
	if self._open and self._handle then
		self._handle.appendChat(fromName, message)
	end
end

function SocialController:Open()
	if self._open then self:_close() return end
	self._open = true
	local SocialService = Knit.GetService("SocialService")

	-- Fetch crew members first so the panel opens with a complete view.
	-- The DataStore read may yield; we use .andThen to keep the open non-blocking.
	local function showPanel(crewMembers: { {userId: number, displayName: string} }?, hasCrew: boolean)
		self._handle = SocialUI.show({
			emotes = EMOTES,
			onPlayEmote = function(emoteId)
				SocialService:PlayEmote(emoteId)
			end,
			onVisit = function(userId)
				SocialService:VisitLocalHarbor(userId)
			end,
			onSendChat = hasCrew and function(message)
				SocialService:SendCrewChat(message)
			end or nil,
			crewMembers = crewMembers,
			initialChat = hasCrew and self._chatLog or {
				{ from = "System", message = "Join a crew to chat with crewmates." }
			},
			onClose = function()
				self._open = false
				self._handle = nil
			end,
			onMuteSender = function(fromName: string)
				self._mutedNames[fromName] = true
			end,
		})
	end

	SocialService:GetCrewMembers():andThen(function(result)
		if result and result.members then
			showPanel(result.members, true)
		else
			showPanel(nil, false)
		end
	end):catch(function()
		showPanel(nil, false)
	end)
end

function SocialController:_close()
	self._open = false
	if self._handle then self._handle.close(); self._handle = nil end
end

function SocialController:Close()
	if self._open then self:_close() end
end

return SocialController
