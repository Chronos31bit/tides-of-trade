--!strict
-- SettingsUI.lua
-- Settings hub: bottom-right panel from SettingsUI_Template. Audio, Motion, Credits.
-- Pure presentation — callbacks report intent; SettingsController owns wiring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage.Shared.Config.GameConfig)
local CreditsConfig = require(ReplicatedStorage.Shared.Config.CreditsConfig)
local MotionUtil    = require(ReplicatedStorage.Shared.Util.MotionUtil)
local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit         = require(script.Parent.UIKit)

local SettingsUI = {}

export type Callbacks = {
	onMuteChanged: ((muted: boolean) -> ())?,
	onMasterVolume: ((volume: number) -> ())?,
	onMotionMode: ((mode: string) -> ())?,
	onClosed: (() -> ())?,
}

export type Handle = {
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
	setMuted: (muted: boolean) -> (),
	setMasterVolume: (volume: number) -> (),
	setMotionMode: (mode: string) -> (),
}

local MOTION_OPTIONS = {
	{ mode = "auto", label = "Auto" },
	{ mode = "off", label = "Always Off" },
	{ mode = "reduced", label = "Always Reduced" },
}

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[SettingsUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

function SettingsUI.create(callbacks: Callbacks?): Handle
	local cb = callbacks or {}
	local P = UIKit.Palette
	local H = GameConfig.UI.SettingsHub

	local gui = TemplateLoader.spawn("Settings", { instanceName = "SettingsUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local closeBtn = req(req(panel, "Header", "Frame"), "Close", "TextButton") :: TextButton
	local sections = req(req(panel, "Body", "Frame"), "Sections", "ScrollingFrame") :: ScrollingFrame

	local audioBody = req(req(sections, "AudioSection", "Frame"), "AudioBody", "Frame") :: Frame
	local sliderMount = req(audioBody, "VolumeSliderMount", "Frame") :: Frame
	local muteMount = req(audioBody, "MuteToggleMount", "Frame") :: Frame

	local motionBody = req(req(sections, "MotionSection", "Frame"), "MotionBody", "Frame") :: Frame
	local modeRow = req(motionBody, "ModeRow", "Frame") :: Frame
	local creditsBody = req(req(sections, "CreditsSection", "Frame"), "CreditsBody", "Frame") :: Frame

	local fadeDuration = H.FadeDuration
	local slideOffsetPx = H.SlideOffsetPx
	local meta = gui:FindFirstChild("Meta")
	if meta and meta:IsA("Folder") then
		local fadeVal = meta:FindFirstChild("FadeDuration")
		if fadeVal and fadeVal:IsA("NumberValue") then
			fadeDuration = fadeVal.Value
		end
		local slideVal = meta:FindFirstChild("SlideOffsetPx")
		if slideVal and slideVal:IsA("NumberValue") then
			slideOffsetPx = slideVal.Value
		end
	end

	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -H.MarginPx, 1, -H.MarginPx)
	panel.Size = UDim2.fromOffset(H.PanelWidthPx, H.PanelHeightPx)

	local slider = UIKit.Slider({
		value = GameConfig.Settings.DefaultMasterVolume,
		min = 0,
		max = 1,
		step = GameConfig.Settings.VolumeStep,
		onChanged = function(v)
			if cb.onMasterVolume then cb.onMasterVolume(v) end
		end,
		LayoutOrder = 0,
	})
	slider.frame.Parent = sliderMount

	local muteToggle = UIKit.Toggle({
		label = "Mute all sound",
		value = GameConfig.Settings.DefaultMuted,
		onChanged = function(on)
			if cb.onMuteChanged then cb.onMuteChanged(on) end
		end,
		LayoutOrder = 0,
	})
	muteToggle.frame.Parent = muteMount

	local selectedMode = GameConfig.Settings.DefaultMotionMode
	local modeButtons: { [string]: TextButton } = {}

	local function refreshModes()
		for mode, btn in pairs(modeButtons) do
			local on = (mode == selectedMode)
			btn.BackgroundColor3 = if on then P.Mint else P.Parchment
			btn.TextColor3 = if on then P.Cream else P.InkSoft
			local s = btn:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = if on then P.MintDark else P.BorderMid
			end
		end
	end

	for _, opt in ipairs(MOTION_OPTIONS) do
		local btn = modeRow:FindFirstChild("Mode_" .. opt.mode)
		if btn and btn:IsA("TextButton") then
			modeButtons[opt.mode] = btn
			btn.Activated:Connect(function()
				selectedMode = opt.mode
				refreshModes()
				if cb.onMotionMode then cb.onMotionMode(opt.mode) end
			end)
		end
	end
	refreshModes()

	for i, entry in ipairs(CreditsConfig) do
		local nameLbl = UIKit.Label(
			string.format("%s — %s", entry.title, entry.author),
			"body",
			{
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				LayoutOrder = i * 10,
			}
		)
		nameLbl.Parent = creditsBody

		local licLine = entry.license
		local url = entry.sourceUrl or entry.licenseUrl
		if url then
			licLine = string.format("%s  •  %s", entry.license, url)
		end
		local licLbl = UIKit.Label(licLine, "caption", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = i * 10 + 1,
		})
		licLbl.Parent = creditsBody
	end

	local isOpen = false
	local closed = false
	local restPos = panel.Position
	local fromPos = UDim2.new(
		restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + slideOffsetPx
	)
	local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function finishClose()
		gui.Enabled = false
		if cb.onClosed then cb.onClosed() end
	end

	local function hide()
		if not isOpen or closed then return end
		isOpen = false
		if UIKit.reducedMotion() then
			finishClose()
			return
		end
		MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = 1 })
		MotionUtil.tweenOrSnap(panel, fadeInfo, {
			BackgroundTransparency = 1,
			Position = fromPos,
		})
		task.delay(fadeDuration, finishClose)
	end

	local function show()
		if isOpen or closed then return end
		isOpen = true
		panel.BackgroundTransparency = 1
		backdrop.BackgroundTransparency = 1
		gui.Enabled = true
		if UIKit.reducedMotion() then
			panel.Position = restPos
			panel.BackgroundTransparency = 0
			backdrop.BackgroundTransparency = H.BackdropAlpha
		else
			panel.Position = fromPos
			MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = H.BackdropAlpha })
			MotionUtil.tweenOrSnap(panel, fadeInfo, { BackgroundTransparency = 0, Position = restPos })
		end
	end

	backdrop.Activated:Connect(hide)
	closeBtn.Activated:Connect(hide)

	gui.Enabled = false

	return {
		show = show,
		hide = hide,
		destroy = function()
			closed = true
			if gui.Parent then gui:Destroy() end
		end,
		setMuted = function(muted: boolean)
			muteToggle.set(muted)
		end,
		setMasterVolume = function(volume: number)
			slider.set(volume)
		end,
		setMotionMode = function(mode: string)
			selectedMode = mode
			refreshModes()
		end,
	}
end

return SettingsUI
