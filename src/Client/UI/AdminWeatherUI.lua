--!strict
-- AdminWeatherUI.lua
-- Admin-only weather panel. Layout from AdminWeatherUI_Template.
-- Gated by AdminController + AdminService:IsAdmin() — do not spawn elsewhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

export type AdminWeatherUI = {
	gui: ScreenGui,
	setStatus: (weather: string, locked: boolean, attrWeather: string?, mismatch: boolean?) -> (),
	setPanelVisible: (visible: boolean) -> (),
	isPanelVisible: () -> boolean,
	destroy: () -> (),
}

local WEATHER_STATES = GameConfig.Admin.WeatherStates
local ATTR_NAME = GameConfig.Weather.WorkspaceAttribute

local AdminWeatherUI = {}

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[AdminWeatherUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

function AdminWeatherUI.build(
	onPickWeather: (string) -> (),
	onAuto: () -> (),
	onTogglePanel: () -> ()
): AdminWeatherUI
	local gui = TemplateLoader.spawn("AdminWeather", { instanceName = "AdminWeather" })

	local toggleBtn = req(gui, "ToggleButton", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local title = req(panel, "TitleLabel", "TextLabel") :: TextLabel
	local status = req(panel, "StatusLabel", "TextLabel") :: TextLabel
	local weatherList = req(panel, "WeatherButtonList", "Frame") :: Frame
	local devList = req(panel, "DevToggleList", "Frame") :: Frame
	local hint = req(panel, "HintLabel", "TextLabel") :: TextLabel
	local weatherTpl = req(gui, "WeatherButton_Template", "TextButton") :: TextButton
	local devTpl = req(gui, "DevToggle_Template", "TextButton") :: TextButton

	title.Text = ("Weather (%d states)"):format(#WEATHER_STATES)
	title.TextColor3 = P.Cream
	status.TextColor3 = P.Cream
	hint.TextColor3 = P.CreamSoft

	for i, weather in ipairs(WEATHER_STATES) do
		local btn = weatherTpl:Clone()
		btn.Name = "Weather_" .. weather
		btn.Visible = true
		btn.Text = weather
		btn.LayoutOrder = i
		btn.BackgroundColor3 = P.Teal
		btn.TextColor3 = P.Cream
		btn.Parent = weatherList
		UIKit.prepareInteractive(btn)
		btn.Activated:Connect(function()
			onPickWeather(weather)
		end)
	end

	local autoBtn = devTpl:Clone()
	autoBtn.Name = "AutoToggle"
	autoBtn.Visible = true
	autoBtn.Text = "Resume auto (Markov)"
	autoBtn.LayoutOrder = 1
	autoBtn.BackgroundTransparency = 0.35
	autoBtn.BackgroundColor3 = P.TealDark
	autoBtn.TextColor3 = P.CreamSoft
	autoBtn.Parent = devList
	UIKit.prepareInteractive(autoBtn)
	autoBtn.Activated:Connect(onAuto)

	UIKit.prepareInteractive(toggleBtn)
	toggleBtn.Activated:Connect(onTogglePanel)

	local panelVisible = false
	local lastAttr = ""
	local lastMismatch = false

	local function setStatus(weather: string, locked: boolean, attrWeather: string?, mismatch: boolean?)
		local lockText = if locked then "locked" else "auto"
		local attr = attrWeather or lastAttr
		if attrWeather then
			lastAttr = attrWeather
		end
		local showMismatch = mismatch == true
		if mismatch ~= nil then
			lastMismatch = showMismatch
		else
			showMismatch = lastMismatch
		end
		local mismatchText = if showMismatch then "\n⚠ Server mismatch" else ""
		status.Text = ("Current: %s (%s)\nAttr %s: %s%s"):format(
			weather,
			lockText,
			ATTR_NAME,
			attr ~= "" and attr or "?",
			mismatchText
		)
	end

	local function setPanelVisible(visible: boolean)
		panelVisible = visible
		panel.Visible = visible
	end

	local function isPanelVisible(): boolean
		return panelVisible
	end

	local function destroy()
		gui:Destroy()
	end

	return {
		gui = gui,
		setStatus = setStatus,
		setPanelVisible = setPanelVisible,
		isPanelVisible = isPanelVisible,
		destroy = destroy,
	}
end

return AdminWeatherUI
