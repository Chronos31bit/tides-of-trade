--!strict
-- SoundController.lua
-- Central client audio: asset IDs from AssetIds, tunables from GameConfig.
-- Callers use Play(name) / Stop(name); no direct SoundService usage elsewhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AssetIds = require(script.Parent.Parent.AssetIds)

local AMBIENT_NAME = "AmbientOcean"
local MUSIC_NAME = "MusicHarborTheme"
local RAIN_LOOP_NAME = "RainLoop"
local WIND_LOOP_NAME = "WindStorm"
local FOG_LOOP_NAME = "FogAmbient"
-- Background loops driven by KnitStart + WorldFXController. _applyMuteState
-- and _duckLoops iterate this list, so adding a new loop slot is one line
-- here plus an entry in AssetIds.Sounds. Empty/invalid SoundIds are silently
-- skipped (see isValidSoundId) so listing a slot before its audio uploads
-- is safe.
local LOOP_NAMES = { AMBIENT_NAME, MUSIC_NAME, RAIN_LOOP_NAME, WIND_LOOP_NAME, FOG_LOOP_NAME }
local AUDIO_FOLDER_NAME = "TidesAudio"
local POSITIONAL_ROLLOFF = 80

export type PlayOpts = {
	volume: number?,
	position: Vector3?,
	loop: boolean?,
}

local function isValidSoundId(id: string?): boolean
	if not id or id == "" then return false end
	if id == "rbxassetid://0" then return false end
	return true
end

local function normalizeSoundId(id: string): string
	if string.find(id, "rbxassetid://", 1, true) then
		return id
	end
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

local function isLoopName(name: string): boolean
	for _, n in ipairs(LOOP_NAMES) do
		if n == name then return true end
	end
	return false
end

local SoundController = Knit.CreateController({
	Name = "SoundController",
	_trove = nil :: any,
	_audioFolder = nil :: Folder?,
	_managed = {} :: {[string]: Sound},
	_userMuted = false,
	_platformMuted = false,
	_masterMuted = false,
	_ambientTargetVolume = 0.4,
	_musicTargetVolume = 0.16,
	_duckTrove = nil :: any,
	_duckGeneration = 0,
	_audioFocusHandlesFocus = false,
})

function SoundController:IsMuted(): boolean
	return self._userMuted or self._platformMuted or self._masterMuted
end

function SoundController:SetMuted(muted: boolean)
	self._userMuted = muted
	self:_applyMuteState()
end

function SoundController:ToggleMuted(): boolean
	self._userMuted = not self._userMuted
	self:_applyMuteState()
	return self._userMuted
end

function SoundController:SetAmbientVolume(volume: number)
	self._ambientTargetVolume = math.clamp(volume, 0, 1)
	local ambient = self._managed[AMBIENT_NAME]
	if ambient and ambient.IsPlaying and not self:IsMuted() then
		ambient.Volume = self._ambientTargetVolume
	end
end

function SoundController:SetMusicVolume(volume: number)
	self._musicTargetVolume = math.clamp(volume, 0, 1)
	local music = self._managed[MUSIC_NAME]
	if music and music.IsPlaying and not self:IsMuted() then
		music.Volume = self._musicTargetVolume
	end
end

function SoundController:_getLoopTargetVolume(name: string): number
	if name == MUSIC_NAME then
		return self._musicTargetVolume
	end
	return self._ambientTargetVolume
end

function SoundController:Stop(name: string)
	local sound = self._managed[name]
	if not sound then return end
	sound:Stop()
end

-- Smoothly tween a managed loop's volume to targetVolume over fadeSeconds.
-- If the loop hasn't been created yet (e.g. first time playing on weather
-- change) and targetVolume > 0, creates and starts the loop. If targetVolume
-- is 0, fades out and stops at the end. Empty/invalid asset IDs no-op silently.
function SoundController:FadeLoop(name: string, targetVolume: number, fadeSeconds: number)
	if self:IsMuted() and targetVolume > 0 then return end

	local sound = self._managed[name]
	if not sound then
		if targetVolume <= 0 then return end
		sound = self:_getOrCreateManaged(name)
		if not sound then return end
		sound.Looped = true
		sound.Volume = 0
		if not sound.IsPlaying then
			sound:Play()
		end
	end

	if fadeSeconds <= 0 then
		sound.Volume = targetVolume
		if targetVolume <= 0 then
			sound:Stop()
		elseif not sound.IsPlaying then
			sound:Play()
		end
		return
	end

	if targetVolume > 0 and not sound.IsPlaying then
		sound:Play()
	end

	local info = TweenInfo.new(fadeSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(sound, info, { Volume = targetVolume })
	if targetVolume <= 0 then
		tween.Completed:Connect(function()
			if sound and sound.Parent then
				sound:Stop()
			end
		end)
	end
	tween:Play()
end

function SoundController:_getSoundId(name: string): string?
	local sounds = AssetIds.Sounds
	local id = sounds[name]
	if type(id) ~= "string" then return nil end
	return id
end

function SoundController:_ensureKnitState()
	if not self._managed then
		self._managed = {}
	end
	if not self._trove then
		self._trove = Trove.new()
	end
end

function SoundController:_ensureAudioFolder(): Folder
	self:_ensureKnitState()
	if self._audioFolder and self._audioFolder.Parent then
		return self._audioFolder
	end
	local existing = SoundService:FindFirstChild(AUDIO_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		self._audioFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = AUDIO_FOLDER_NAME
	folder.Parent = SoundService
	self._audioFolder = folder
	self._trove:Add(folder)
	return folder
end

function SoundController:_getOrCreateManaged(name: string): Sound?
	self:_ensureKnitState()
	local existing = self._managed[name]
	if existing and existing.Parent then return existing end

	local rawId = self:_getSoundId(name)
	if not isValidSoundId(rawId) then return nil end

	local folder = self:_ensureAudioFolder()
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = normalizeSoundId(rawId :: string)
	if isLoopName(name) then
		sound.Looped = true
	end
	sound.Parent = folder
	self._managed[name] = sound
	return sound
end

-- Mute common place-level ambient objects so only TidesAudio runs.
function SoundController:_silencePlaceAudio()
	local blockNames = { "Sound", "Music", "BGM", "Ambient", "BackgroundMusic" }
	for _, parent in ipairs({ Workspace, SoundService }) do
		for _, childName in ipairs(blockNames) do
			local inst = parent:FindFirstChild(childName)
			if inst and inst:IsA("Sound") then
				inst:Stop()
				inst.Volume = 0
				inst.Looped = false
			end
		end
	end
end

function SoundController:_applyMuteState()
	local muted = self:IsMuted()
	for _, name in ipairs(LOOP_NAMES) do
		local loop = self._managed[name]
		if loop then
			if muted then
				loop:Stop()
			elseif isValidSoundId(self:_getSoundId(name)) then
				loop.Volume = self:_getLoopTargetVolume(name)
				if not loop.IsPlaying then
					loop:Play()
				end
			end
		end
	end
end

function SoundController:_bindMasterVolume()
	-- UserGameSettings.MasterVolume requires RobloxScript capability; guard every
	-- access so a Studio permission gap never crashes KnitInit.
	local ok, settings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	if not ok or not settings then return end

	local function sync()
		local readOk, mv = pcall(function()
			return settings.MasterVolume
		end)
		if not readOk then return end
		self._masterMuted = mv <= 0
		self:_applyMuteState()
	end

	local connectOk, conn = pcall(function()
		return settings:GetPropertyChangedSignal("MasterVolume"):Connect(sync)
	end)
	if connectOk and conn then
		self._trove:Add(conn)
	end

	sync()
end

function SoundController:_bindWindowFocus()
	self._trove:Add(UserInputService.WindowFocusReleased:Connect(function()
		self._platformMuted = true
		self:_applyMuteState()
	end))
	self._trove:Add(UserInputService.WindowFocused:Connect(function()
		-- When AudioFocusService is binding focus signals it is authoritative
		-- (mobile / console), so defer the restore to it. On desktop Studio
		-- AFS isn't available (_audioFocusHandlesFocus stays false), so the
		-- WindowFocused signal is the only thing that ever un-mutes us after
		-- the user alt-tabs back from Cursor / browser / another app.
		if self._audioFocusHandlesFocus then return end
		self._platformMuted = false
		self:_applyMuteState()
	end))
end

function SoundController:_bindAudioFocus()
	local ok, focusSvc = pcall(function()
		return game:GetService("AudioFocusService")
	end)
	if not ok or focusSvc == nil then return end

	-- API surface varies by platform; bind defensively.
	local function onLost()
		self._platformMuted = true
		self:_applyMuteState()
	end
	local function onGained()
		self._platformMuted = false
		self:_applyMuteState()
	end

	local bound = 0
	for _, eventName in ipairs({ "AudioFocusLost", "FocusLost", "LostFocus" }) do
		local sig = (focusSvc :: any)[eventName]
		if typeof(sig) == "RBXScriptSignal" then
			self._trove:Add(sig:Connect(onLost))
			bound += 1
		end
	end
	for _, eventName in ipairs({ "AudioFocusGained", "FocusGained", "GainedFocus" }) do
		local sig = (focusSvc :: any)[eventName]
		if typeof(sig) == "RBXScriptSignal" then
			self._trove:Add(sig:Connect(onGained))
			bound += 1
		end
	end
	-- Only defer WindowFocused restore when we actually subscribed to focus events.
	self._audioFocusHandlesFocus = bound > 0
end

-- Ducks every currently-playing loop in LOOP_NAMES (ocean + music) so a
-- one-shot SFX always sits above the bed. Each loop ducks to its own
-- baseline * DuckDb, then releases back to its own baseline — music
-- doesn't get pulled to ambient's level or vice versa.
function SoundController:_duckLoops()
	local playing: {{ sound: Sound, name: string }} = {}
	for _, name in ipairs(LOOP_NAMES) do
		local ok, sound = pcall(function()
			return self:_getOrCreateManaged(name)
		end)
		if ok and sound and sound.IsPlaying then
			table.insert(playing, { sound = sound, name = name })
		end
	end
	if #playing == 0 then return end

	local audioCfg = GameConfig.Audio
	local duckMultiplier = 10 ^ (audioCfg.DuckDb / 20)

	self._duckGeneration += 1
	local generation = self._duckGeneration

	if self._duckTrove then
		self._duckTrove:Destroy()
	end
	self._duckTrove = Trove.new()

	local attackInfo = TweenInfo.new(audioCfg.DuckAttack, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local releaseInfo = TweenInfo.new(audioCfg.DuckRelease, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, entry in ipairs(playing) do
		local sound = entry.sound
		local loopName = entry.name
		local baseVolume = self:_getLoopTargetVolume(loopName)
		local targetDucked = baseVolume * duckMultiplier

		local attackTween = TweenService:Create(sound, attackInfo, { Volume = targetDucked })
		self._duckTrove:Add(attackTween)
		attackTween:Play()

		self._duckTrove:Add(attackTween.Completed:Connect(function()
			attackTween:Destroy()
			if generation ~= self._duckGeneration then return end

			task.delay(audioCfg.DuckMinHold, function()
				if generation ~= self._duckGeneration then return end
				if not sound.Parent then return end

				-- Re-read the baseline at release time so a SetMusicVolume /
				-- SetAmbientVolume call mid-duck restores to the new target.
				local restoreTarget = self:_getLoopTargetVolume(loopName)
				local releaseTween = TweenService:Create(sound, releaseInfo, { Volume = restoreTarget })
				self._duckTrove:Add(releaseTween)
				releaseTween:Play()
				releaseTween.Completed:Connect(function()
					releaseTween:Destroy()
				end)
			end)
		end))
	end
end

function SoundController:_playManagedLoop(name: string, opts: PlayOpts?)
	local sound = self:_getOrCreateManaged(name)
	if not sound then return end

	local volume = if opts and opts.volume then opts.volume else 0.6
	sound.Looped = true
	sound.Volume = volume

	if name == AMBIENT_NAME then
		self._ambientTargetVolume = volume
	elseif name == MUSIC_NAME then
		self._musicTargetVolume = volume
	end

	if not sound.IsPlaying then
		sound:Play()
	end
end

function SoundController:_playOneShot(name: string, opts: PlayOpts?)
	local rawId = self:_getSoundId(name)
	if not isValidSoundId(rawId) then return end

	local volume = if opts and opts.volume then opts.volume else 0.6
	local soundId = normalizeSoundId(rawId :: string)

	if not isLoopName(name) then
		self:_duckLoops()
	end

	if opts and opts.position then
		pcall(function()
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.new(0.1, 0.1, 0.1)
			part.CFrame = CFrame.new(opts.position)
			part.Parent = Workspace

			local s = Instance.new("Sound")
			s.SoundId = soundId
			s.Volume = volume
			s.RollOffMaxDistance = POSITIONAL_ROLLOFF
			s.Parent = part
			s:Play()
			s.Ended:Connect(function()
				part:Destroy()
			end)
		end)
	else
		pcall(function()
			local s = Instance.new("Sound")
			s.SoundId = soundId
			s.Volume = volume
			SoundService:PlayLocalSound(s)
		end)
	end
end

function SoundController:Play(name: string, opts: PlayOpts?)
	if self:IsMuted() then return end

	local rawId = self:_getSoundId(name)
	if not isValidSoundId(rawId) then return end

	local loop = opts and opts.loop
	if loop or isLoopName(name) then
		self:_playManagedLoop(name, opts)
	else
		self:_playOneShot(name, opts)
	end
end

function SoundController:KnitInit()
	self._trove = Trove.new()
	self._userMuted = GameConfig.UI.SoundMutedByDefault
	self._ambientTargetVolume = GameConfig.Audio.AmbientBaseVolume
	-- MusicBaseVolume is optional in GameConfig.Audio for backward compat
	-- with older config snapshots; fall back to the field default if missing.
	self._musicTargetVolume = GameConfig.Audio.MusicBaseVolume or self._musicTargetVolume

	self:_bindMasterVolume()
	self:_bindWindowFocus()
	self:_bindAudioFocus()
end

function SoundController:KnitStart()
	self:_silencePlaceAudio()
	if self:IsMuted() then return end

	if isValidSoundId(self:_getSoundId(AMBIENT_NAME)) then
		self:Play(AMBIENT_NAME, {
			loop = true,
			volume = self._ambientTargetVolume,
		})
	end

	-- MusicHarborTheme is empty in AssetIds.lua until a custom upload lands,
	-- so this call is a silent no-op for now (isValidSoundId guard inside
	-- _playManagedLoop -> _getOrCreateManaged). Once an ID is pasted in,
	-- the music loop starts on next session join with no further code work.
	if isValidSoundId(self:_getSoundId(MUSIC_NAME)) then
		self:Play(MUSIC_NAME, {
			loop = true,
			volume = self._musicTargetVolume,
		})
	end
end

function SoundController:KnitStop()
	self._duckGeneration += 1
	if self._duckTrove then
		self._duckTrove:Destroy()
		self._duckTrove = nil
	end
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
	table.clear(self._managed)
end

return SoundController
