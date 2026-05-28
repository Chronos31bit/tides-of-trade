--!strict
-- SettingsUI.lua
-- The Settings hub modal. Three collapsible sections — Audio, Motion, Credits —
-- stacked in a scrolling body inside UIKit.ModalShell. Pure presentation: it
-- reports user intent via the callbacks passed to create() and reflects
-- server/profile state via the returned handle's setters. SettingsController
-- owns the wiring; this module never touches SoundController/persistence directly.
--
-- All sizing/color/font come from UIKit tokens — no inline literals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig    = require(ReplicatedStorage.Shared.Config.GameConfig)
local CreditsConfig = require(ReplicatedStorage.Shared.Config.CreditsConfig)
local UIKit         = require(script.Parent.UIKit)

local SettingsUI = {}

export type Callbacks = {
	onMuteChanged: ((muted: boolean) -> ())?,
	onMasterVolume: ((volume: number) -> ())?,
	onMotionMode: ((mode: string) -> ())?,
	-- Fired whenever the modal closes (backdrop tap, X button, or hide()),
	-- so the owner can keep its open/closed state in sync.
	onClosed: (() -> ())?,
}

export type Handle = {
	show: () -> (),
	hide: () -> (),
	destroy: () -> (),
	-- Reflect authoritative (profile) state in the controls, without firing callbacks.
	setMuted: (muted: boolean) -> (),
	setMasterVolume: (volume: number) -> (),
	setMotionMode: (mode: string) -> (),
}

-- Display labels for the motion-mode segmented control. Order is intentional:
-- Auto first (the default / recommended), then the two explicit overrides.
local MOTION_OPTIONS = {
	{ mode = "auto", label = "Auto" },
	{ mode = "off", label = "Always Off" },
	{ mode = "reduced", label = "Always Reduced" },
}

function SettingsUI.create(callbacks: Callbacks?): Handle
	local cb = callbacks or {}
	local P = UIKit.Palette

	local shell
	shell = UIKit.ModalShell({
		name = "Settings",
		title = "Settings",
		-- Reusable: closing hides the GUI instead of destroying it, so the
		-- controller can re-open the same instance with state preserved.
		onClose = function()
			if shell then shell.gui.Enabled = false end
			if cb.onClosed then cb.onClosed() end
		end,
	})

	-- Scrolling container so the sections fit any phone height.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Sections"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = P.BorderMid
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = shell.body

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, UIKit.Spacing.md)
	list.Parent = scroll

	-- Keep cards clear of the scrollbar.
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingRight = UDim.new(0, UIKit.Spacing.sm)
	scrollPad.Parent = scroll

	-- ---------------------------------------------------------------
	-- AUDIO
	-- ---------------------------------------------------------------
	local audio = UIKit.CollapsibleCard({
		title = "Audio",
		startOpen = true,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 0),
	})
	audio.card.Parent = scroll

	local volLabel = UIKit.Label("Master volume", "body", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 0,
	})
	volLabel.Parent = audio.body

	local slider = UIKit.Slider({
		value = GameConfig.Settings.DefaultMasterVolume,
		min = 0,
		max = 1,
		step = GameConfig.Settings.VolumeStep,
		onChanged = function(v)
			if cb.onMasterVolume then cb.onMasterVolume(v) end
		end,
		LayoutOrder = 1,
	})
	slider.frame.Parent = audio.body

	local muteToggle = UIKit.Toggle({
		label = "Mute all sound",
		value = GameConfig.Settings.DefaultMuted,
		onChanged = function(on)
			if cb.onMuteChanged then cb.onMuteChanged(on) end
		end,
		LayoutOrder = 2,
	})
	muteToggle.frame.Parent = audio.body

	-- ---------------------------------------------------------------
	-- MOTION
	-- ---------------------------------------------------------------
	local motion = UIKit.CollapsibleCard({
		title = "Motion",
		startOpen = true,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
	})
	motion.card.Parent = scroll

	local motionHint = UIKit.Label(
		"Reduce on-screen animation. Auto follows your device's accessibility setting.",
		"caption",
		{
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			LayoutOrder = 0,
		}
	)
	motionHint.Parent = motion.body

	local segRow = Instance.new("Frame")
	segRow.Name = "ModeRow"
	segRow.BackgroundTransparency = 1
	segRow.BorderSizePixel = 0
	segRow.Size = UDim2.new(1, 0, 0, UIKit.MinTouchPx)
	segRow.LayoutOrder = 1
	segRow.Parent = motion.body

	local segLayout = Instance.new("UIListLayout")
	segLayout.FillDirection = Enum.FillDirection.Horizontal
	segLayout.SortOrder = Enum.SortOrder.LayoutOrder
	segLayout.Padding = UDim.new(0, UIKit.Spacing.sm)
	segLayout.Parent = segRow

	local selectedMode = GameConfig.Settings.DefaultMotionMode
	local modeButtons: { [string]: TextButton } = {}

	local function refreshModes()
		for mode, btn in pairs(modeButtons) do
			local on = (mode == selectedMode)
			btn.BackgroundColor3 = if on then P.Mint else P.Parchment
			btn.TextColor3 = if on then P.Cream else P.InkSoft
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if on then P.MintDark else P.BorderMid
			end
		end
	end

	-- Segmented buttons are plain TextButtons (token-styled) rather than
	-- UIKit.Button so we fully own the selected/unselected colors — UIKit.Button's
	-- hover feedback would fight the persistent selected tint.
	for i, opt in ipairs(MOTION_OPTIONS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Mode_" .. opt.mode
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1 / #MOTION_OPTIONS, -UIKit.Spacing.sm, 1, 0)
		btn.Font = UIKit.Typography.caption.font
		btn.TextSize = math.max(UIKit.Typography.caption.size, UIKit.MinFontPx)
		btn.Text = opt.label
		btn.TextWrapped = true
		btn.LayoutOrder = i
		btn.Parent = segRow

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, UIKit.Radii.md)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.2
		stroke.Transparency = 0.25
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = btn

		local mode = opt.mode
		btn.Activated:Connect(function()
			selectedMode = mode
			refreshModes()
			if cb.onMotionMode then cb.onMotionMode(mode) end
		end)

		modeButtons[mode] = btn
	end
	refreshModes()

	-- ---------------------------------------------------------------
	-- CREDITS  (schema-driven from CreditsConfig — adding an entry is one line)
	-- ---------------------------------------------------------------
	local credits = UIKit.CollapsibleCard({
		title = "Credits",
		startOpen = true,
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 0),
	})
	credits.card.Parent = scroll

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
		nameLbl.Parent = credits.body

		-- License + link. Roblox can't reliably open URLs in a normal experience,
		-- so the link renders as readable text — sufficient for CC BY attribution.
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
		licLbl.Parent = credits.body
	end

	-- Start hidden; the controller shows it when the HUD gear is tapped.
	shell.close()

	return {
		show = function() shell.open() end,
		hide = function() shell.close() end,
		destroy = function() shell.destroy() end,
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
