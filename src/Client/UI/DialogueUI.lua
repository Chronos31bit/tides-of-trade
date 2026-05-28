--!strict
-- DialogueUI.lua
-- Text-only NPC dialogue panel (no TTS). Layout from DialogueUI_Template;
-- typewriter + slide/fade motion in script. World keeps running — not a modal.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TemplateLoader = require(script.Parent.TemplateLoader)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local TUNE = GameConfig.Tutorial

local DialogueUI = {}
DialogueUI.__index = DialogueUI

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[DialogueUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

export type DialogueUIInstance = {
	gui: ScreenGui,
	panel: Frame,
	textLabel: TextLabel,
	speakerLabel: TextLabel,
	continueButton: TextButton,
	portrait: Frame,
	closeButton: TextButton,
	_choiceButtonTemplate: TextButton,
	_choicesList: Frame,

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

function DialogueUI.create(speakerName: string): DialogueUIInstance
	local gui = TemplateLoader.spawn("Dialogue", { instanceName = "TutorialDialogue" })
	gui.Enabled = false

	local panel = req(gui, "Panel", "Frame") :: Frame
	local speakerLabel = req(panel, "SpeakerNameLabel", "TextLabel") :: TextLabel
	local portrait = req(panel, "PortraitFrame", "Frame") :: Frame
	local textLabel = req(panel, "BodyTextLabel", "TextLabel") :: TextLabel
	local continueButton = req(panel, "ContinueHint", "TextButton") :: TextButton
	local closeButton = req(panel, "CloseButton", "TextButton") :: TextButton
	local choicesList = req(panel, "ChoicesList", "Frame") :: Frame
	local choiceButtonTemplate = req(gui, "ChoiceButton_Template", "TextButton") :: TextButton

	speakerLabel.Text = speakerName

	local instance: DialogueUIInstance = setmetatable({
		gui = gui,
		panel = panel,
		textLabel = textLabel,
		speakerLabel = speakerLabel,
		continueButton = continueButton,
		portrait = portrait,
		closeButton = closeButton,
		_choiceButtonTemplate = choiceButtonTemplate,
		_choicesList = choicesList,
		_currentLine = "",
		_typewriterToken = 0,
		_visible = false,
		_onContinue = nil,
		_onClose = nil,
		_reducedMotion = GuiService.ReducedMotionEnabled,
	}, DialogueUI) :: any

	GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		instance._reducedMotion = GuiService.ReducedMotionEnabled
	end)

	continueButton.Activated:Connect(function()
		if instance:IsTyping() then
			instance._typewriterToken += 1
			instance.textLabel.Text = instance._currentLine
		else
			if instance._onContinue then
				instance._onContinue()
			end
		end
	end)

	closeButton.Activated:Connect(function()
		if instance._onClose then
			instance._onClose()
		end
	end)

	return instance
end

function DialogueUI:IsTyping(): boolean
	return self.textLabel.Text ~= self._currentLine
end

function DialogueUI:SetLine(line: string, speakerName: string?)
	self._currentLine = line
	if speakerName then
		self.speakerLabel.Text = speakerName
	end

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
			if self._typewriterToken ~= token then
				return
			end
			i += 1
			self.textLabel.Text = string.sub(line, 1, i)
		end
	end)
end

function DialogueUI:Show()
	if self._visible then
		return
	end
	self._visible = true
	self.gui.Enabled = true

	if self._reducedMotion then
		self.panel.Position = UDim2.new(0.5, 0, 1, -120)
		self.panel.BackgroundTransparency = 1
		MotionUtil.tween(
			self.panel,
			TweenInfo.new(TUNE.DialogueReducedMotionFadeIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0 }
		)
	else
		self.panel.Position = UDim2.new(0.5, 0, 1.1, 0)
		MotionUtil.tween(
			self.panel,
			TweenInfo.new(TUNE.DialogueSlideInDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 1, -120) }
		)
	end
end

function DialogueUI:Hide()
	if not self._visible then
		return
	end
	self._visible = false
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
	if self.gui then
		self.gui:Destroy()
	end
end

return DialogueUI
