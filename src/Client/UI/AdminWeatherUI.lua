--!strict
-- AdminWeatherUI.lua
-- Admin-only panel to force every GameConfig.Weather.Transitions state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local UIUtil     = require(script.Parent.UIUtil)

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

function AdminWeatherUI.build(
	onPickWeather: (string) -> (),
	onAuto: () -> (),
	onTogglePanel: () -> ()
): AdminWeatherUI
	local gui, _scale = UIUtil.makeScreenGui("AdminWeather")
	gui.DisplayOrder = 70
	gui.Enabled = true

	local toggleBtn = UIUtil.makeSecondaryButton("Weather", onTogglePanel, {
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(88, 44),
	})
	toggleBtn.Parent = gui

	local panel = UIUtil.makePanel({
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 64),
		Size = UDim2.fromOffset(200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = UIUtil.Palette.TealDeeper,
		Visible = false,
	})
	panel.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = UIUtil.makeLabel(("Weather (%d states)"):format(#WEATHER_STATES), "subtitle", {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
	})
	title.Parent = panel

	local status = UIUtil.makeLabel("Current: …", "body", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, 56),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	})
	status.Parent = panel

	for i, weather in ipairs(WEATHER_STATES) do
		local btn = UIUtil.makeSecondaryButton(weather, function()
			onPickWeather(weather)
		end, {
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = 10 + i,
		})
		btn.Parent = panel
	end

	local autoBtn = UIUtil.makeGhostButton("Resume auto (Markov)", onAuto, {
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 100,
	})
	autoBtn.Parent = panel

	local hint = UIUtil.makeLabel("Tap Weather to hide · /weather Rain", "caption", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 12,
		TextTransparency = 0.2,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 101,
	})
	hint.Parent = panel

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
