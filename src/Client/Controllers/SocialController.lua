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
		print(("[Crew] %s: %s"):format(fromName, message))
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

function SocialController:Open()
	if self._open then self:_close() return end
	self._open = true
	local SocialService = Knit.GetService("SocialService")
	self._handle = SocialUI.show(EMOTES, function(emoteId)
		SocialService:PlayEmote(emoteId)
	end, function()
		self._open = false
		self._handle = nil
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
