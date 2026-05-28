--!strict
-- SettingsController.lua
-- Owns the Settings hub: creates SettingsUI, applies persisted preferences on
-- join, and routes user changes to (1) the live client systems and (2) the
-- server for persistence.
--
-- Data flow per change:
--   1. mirror to a Player attribute (instant local read by MotionUtil /
--      SoundController), and apply to the live system right away;
--   2. ask the server to persist it (PlayerDataService:UpdateSettings) so it
--      survives rejoin. The server validates — client requests, server decides.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit  = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)

local ATTR = GameConfig.Settings

local SettingsController = Knit.CreateController({
	Name = "SettingsController",
	_ui = nil :: any,
	_trove = nil :: any,
	_open = false,
})

function SettingsController:KnitStart()
	self._trove = Trove.new()

	local player = Players.LocalPlayer
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local SoundController = Knit.GetController("SoundController")

	-- Trailing debounce for the volume slider — it fires continuously while
	-- dragging, so we apply audio live but only persist the settled value.
	local pendingVolume: number? = nil
	local volumeSaveQueued = false
	local function persistVolume(v: number)
		pendingVolume = v
		if volumeSaveQueued then return end
		volumeSaveQueued = true
		task.delay(0.3, function()
			volumeSaveQueued = false
			PlayerDataService:UpdateSettings({ masterVolume = pendingVolume }):catch(warn)
		end)
	end

	local uiOk, uiOrErr = pcall(function()
		self._ui = SettingsUI.create({
			onMuteChanged = function(muted: boolean)
				player:SetAttribute(ATTR.AttrAudioMuted, muted)
				SoundController:SetMuted(muted)
				PlayerDataService:UpdateSettings({ audioMuted = muted }):catch(warn)
			end,
			onMasterVolume = function(volume: number)
				player:SetAttribute(ATTR.AttrMasterVolume, volume)
				SoundController:SetMasterVolume(volume)
				persistVolume(volume)
			end,
			onMotionMode = function(mode: string)
				-- MotionUtil reads this attribute and recomputes automatically.
				player:SetAttribute(ATTR.AttrMotionMode, mode)
				PlayerDataService:UpdateSettings({ motionMode = mode }):catch(warn)
			end,
			onClosed = function()
				self._open = false
			end,
		})
	end)
	if not uiOk then
		warn("[SettingsController] SettingsUI.create failed:", uiOrErr)
		return
	end
	self._trove:Add(function()
		if self._ui then
			self._ui.destroy()
			self._ui = nil
		end
	end)

	-- Apply authoritative profile settings: mirror to attributes, push to live
	-- systems, and reflect in the UI controls (setters don't re-fire callbacks).
	local function applySettings(settings: any)
		if not settings then return end
		local muted = settings.audioMuted == true
		local volume = if type(settings.masterVolume) == "number" then settings.masterVolume else ATTR.DefaultMasterVolume
		local mode = if type(settings.motionMode) == "string" then settings.motionMode else ATTR.DefaultMotionMode

		player:SetAttribute(ATTR.AttrAudioMuted, muted)
		player:SetAttribute(ATTR.AttrMasterVolume, volume)
		player:SetAttribute(ATTR.AttrMotionMode, mode)

		SoundController:SetMasterVolume(volume)
		SoundController:SetMuted(muted)

		if self._ui then
			self._ui.setMuted(muted)
			self._ui.setMasterVolume(volume)
			self._ui.setMotionMode(mode)
		end
	end

	-- Initial snapshot covers the case where ProfileLoaded already fired before
	-- this controller started; ProfileLoaded covers the normal join order.
	PlayerDataService:GetSnapshot():andThen(function(snap)
		if snap then applySettings(snap.settings) end
	end):catch(warn)

	self._trove:Add(PlayerDataService.ProfileLoaded:Connect(function(snap)
		if snap then applySettings(snap.settings) end
	end))
end

function SettingsController:Open()
	if not self._ui then return end
	self._open = true
	self._ui.show()
end

function SettingsController:Close()
	if not self._ui then return end
	self._open = false
	self._ui.hide()
end

function SettingsController:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

function SettingsController:KnitStop()
	if self._trove then
		self._trove:Destroy()
		self._trove = nil
	end
end

return SettingsController
