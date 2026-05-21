--!strict
-- DialogueUI.lua
-- Reusable typewriter dialogue box for NPCs. Built for the Captain Mira
-- tutorial flow but parameterized on speaker name + portrait so it can
-- be reused for the bait-shop NPC, market trader, etc. as those land.
--
-- Z-index: panel sits at ZIndex 5 (HUD is 1-4, modals are 10+). World
-- continues running underneath — this is NOT a modal.
-- Mobile: bottom-of-screen panel ~30% of viewport height, 44px continue
-- button, portrait left, text right, speaker name top.
-- Reduced motion: skips slide-up + typewriter; shows full text instantly.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService       = game:GetService("GuiService")
local RunService       = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local UIUtil     = require(script.Parent.UIUtil)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local TUNE = GameConfig.Tutorial

local DialogueUI = {}
DialogueUI.__index = DialogueUI

export type DialogueUIInstance = {
	gui: ScreenGui,
	panel: Frame,
	textLabel: TextLabel,
	speakerLabel: TextLabel,
	continueButton: TextButton,
	portrait: Frame,
	closeButton: TextButton,

	_currentLine: string,
	_typewriterToken: number,
	_visible: boolean,
	_onContinue: (() -> ())?,
	_onClose: (() -> ())?,
	_reducedMotion: boolean,

	SetLine: (self: DialogueUIInstance, line: string, speakerName: string?) -> (),
	Show: (self: DialogueUIInstance) -> (),
	Hide: (self: DialogueUIInstance) -> (),
	SetOnContinue: (self: DialogueUIInstance, cb: () -> ()) -> (),
	SetOnClose: (self: DialogueUIInstance, cb: () -> ()) -> (),
	IsTyping: (self: DialogueUIInstance) -> boolean,
	Destroy: (self: DialogueUIInstance) -> (),
}

-- ====================================================================
-- BUILD
-- ====================================================================
function DialogueUI.create(speakerName: string): DialogueUIInstance
	local gui, _scale = UIUtil.makeScreenGui("TutorialDialogue", nil, { respectTopbar = true })
	-- Dialogue sits above HUD and QuestTracker, below modals + CatchReveal.
	gui.DisplayOrder = UIUtil.DisplayOrder.Dialogue

	-- Outer panel: bottom-anchored ABOVE the HUD action bar (which sits
	-- ~108px tall at the bottom of the screen). Starts offscreen (Y=1.1)
	-- and slides up on Show. Slimmer height (22%) so the dialogue
	-- doesn't dominate the screen when the player needs to interact
	-- with HUD buttons during the tutorial.
	local panel = UIUtil.makePanel({
		Name = "DialoguePanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1.1, 0),  -- offscreen until Show
		Size = UDim2.new(0.96, 0, 0.22, 0),
	})
	panel.Parent = gui

	-- Speaker name label, top-left inside the panel.
	local speakerLabel = UIUtil.makeLabel(speakerName, "title", {
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -32, 0, 22),
		TextColor3 = UIUtil.Palette.Sunset,
	})
	speakerLabel.Parent = panel

	-- Portrait placeholder — 80x80 square on the left. Real asset wired
	-- in later via TutorialConfig.MiraPortraitAssetId.
	local portrait = UIUtil.makeSoftPanel({
		Name = "Portrait",
		Position = UDim2.new(0, 16, 0, 38),
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = UIUtil.Palette.Wood,
	})
	portrait.Parent = panel
	local portraitInitial = UIUtil.makeLabel("M", "display", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3 = UIUtil.Palette.Cream,
	})
	portraitInitial.Parent = portrait
	-- TODO: replace with an ImageLabel when TutorialConfig.MiraPortraitAssetId
	-- is set. Keep the Frame as a fallback so the layout doesn't shift.

	-- Dialogue body text — to the right of the portrait, wraps.
	local textLabel = UIUtil.makeLabel("", "body", {
		Name = "DialogueText",
		Position = UDim2.new(0, 110, 0, 38),
		Size = UDim2.new(1, -220, 1, -56),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 16,
	})
	textLabel.Parent = panel

	-- Continue button, bottom-right inside the panel. 44px minimum hit
	-- target per accessibility rules in CLAUDE.md.
	local continueButton = UIUtil.makeButton("Continue ▸", function() end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -10),
		Size = UDim2.fromOffset(140, 44),
	})
	continueButton.Parent = panel

	local instance: DialogueUIInstance = setmetatable({
		gui = gui,
		panel = panel,
		textLabel = textLabel,
		speakerLabel = speakerLabel,
		continueButton = continueButton,
		portrait = portrait,
		closeButton = nil :: TextButton?, -- set below after instance exists
		_currentLine = "",
		_typewriterToken = 0,
		_visible = false,
		_onContinue = nil,
		_onClose = nil,
		_reducedMotion = GuiService.ReducedMotionEnabled,
	}, DialogueUI) :: any

	-- Watch the accessibility flag in case the user toggles mid-session.
	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		instance._reducedMotion = GuiService.ReducedMotionEnabled
	end)

	continueButton.Activated:Connect(function()
		-- First press while typing: finish the line immediately. Second
		-- press: advance via callback.
		if instance:IsTyping() then
			instance._typewriterToken += 1  -- cancel running typewriter
			instance.textLabel.Text = instance._currentLine
		else
			if instance._onContinue then instance._onContinue() end
		end
	end)

	-- Close (X) button, top-right. Hides UI without advancing state —
	-- the "talk to Mira" prompt appears via TutorialController.
	instance.closeButton = UIUtil.makeCloseButton(function()
		if instance._onClose then instance._onClose() end
	end, {
		Parent = panel,
		BackgroundTransparency = 1,
		TextColor3 = UIUtil.Palette.CreamSoft,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 6),
		Size = UDim2.fromOffset(UIUtil.MinTouchPx, 28),
	})

	return instance
end

-- ====================================================================
-- API
-- ====================================================================

function DialogueUI:IsTyping(): boolean
	return self.textLabel.Text ~= self._currentLine
end

function DialogueUI:SetLine(line: string, speakerName: string?)
	self._currentLine = line
	if speakerName then self.speakerLabel.Text = speakerName end

	-- Cancel any running typewriter. _typewriterToken increments
	-- monotonically; the running loop checks its captured token against
	-- the current one each tick and bails if stale.
	self._typewriterToken += 1
	local token = self._typewriterToken

	if self._reducedMotion then
		self.textLabel.Text = line
		return
	end

	self.textLabel.Text = ""
	local charsPerSecond = TUNE.TypewriterCharsPerSecond
	local secondsPerChar = 1 / math.max(charsPerSecond, 1)
	task.spawn(function()
		local i = 0
		while i < #line do
			task.wait(secondsPerChar)
			if self._typewriterToken ~= token then return end
			i += 1
			self.textLabel.Text = string.sub(line, 1, i)
		end
	end)
end

function DialogueUI:Show()
	if self._visible then return end
	self._visible = true
	self.gui.Enabled = true

	if self._reducedMotion then
		self.panel.Position = UDim2.new(0.5, 0, 1, -120)
		self.panel.BackgroundTransparency = 1
		MotionUtil.tween(self.panel,
			TweenInfo.new(TUNE.DialogueReducedMotionFadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0 }
		)
	else
		self.panel.Position = UDim2.new(0.5, 0, 1.1, 0)
		MotionUtil.tween(self.panel,
			TweenInfo.new(TUNE.DialogueSlideInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 1, -120) }
		)
	end
end

function DialogueUI:Hide()
	if not self._visible then return end
	self._visible = false
	-- Cancel typewriter so a re-Show starts fresh.
	self._typewriterToken += 1
	self.gui.Enabled = false
end

function DialogueUI:SetOnContinue(cb: () -> ())
	self._onContinue = cb
end

function DialogueUI:SetOnClose(cb: () -> ())
	self._onClose = cb
end

function DialogueUI:Destroy()
	self._typewriterToken += 1
	if self.gui then self.gui:Destroy() end
end

return DialogueUI
