--!strict
-- CastMeter.lua
-- The timing-meter overlay shown during a cast. The marker oscillates 0..1
-- on a sine over `period` seconds. The green zone is supplied by the server
-- (greenCenter, greenSize). On release, the controller sends marker back to
-- the server which authoritatively decides hit/miss.

local RunService = game:GetService("RunService")
local UIUtil = require(script.Parent.UIUtil)

local CastMeter = {}

export type CastMeterHandle = {
	gui: ScreenGui,
	bar: Frame,
	greenZone: Frame,
	marker: Frame,
	-- Returns 0..1 marker position at the moment of release.
	stop: () -> number,
}

function CastMeter.show(greenCenter: number, greenSize: number, period: number): CastMeterHandle
	local gui = UIUtil.makeScreenGui("CastMeter")

	-- Centered horizontal bar near bottom-third of screen so it doesn't
	-- compete with the action bar.
	local bar = UIUtil.makePanel({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.66, 0),
		Size = UDim2.new(0.6, 0, 0, 24),
		BackgroundColor3 = UIUtil.Palette.WoodDark,
	})
	local barMax = Instance.new("UISizeConstraint"); barMax.MaxSize = Vector2.new(540, 24); barMax.Parent = bar
	bar.Parent = gui

	-- Green success zone — a translucent panel inside the bar.
	local green = UIUtil.makeFrame({
		Name = "Green",
		Position = UDim2.new(greenCenter - greenSize / 2, 0, 0, 0),
		Size = UDim2.new(greenSize, 0, 1, 0),
		BackgroundColor3 = UIUtil.Palette.Uncommon,
		BackgroundTransparency = 0.15,
	})
	green.Parent = bar
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 4); gc.Parent = green

	-- Moving marker — a tall thin slice.
	local marker = UIUtil.makeFrame({
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 6, 1.4, 0),
		BackgroundColor3 = UIUtil.Palette.Cream,
	})
	marker.Parent = bar

	-- Oscillation: position = (sin(2*pi * t/period) + 1) / 2  — pure 0..1 ping-pong.
	local startT = os.clock()
	local conn: RBXScriptConnection? = nil
	local lastMarker = 0.5
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - startT
		local p = (math.sin(t / period * math.pi * 2) + 1) / 2
		lastMarker = p
		marker.Position = UDim2.new(p, 0, 0.5, 0)
	end)

	local handle: CastMeterHandle = {
		gui = gui,
		bar = bar,
		greenZone = green,
		marker = marker,
		stop = function()
			if conn then conn:Disconnect(); conn = nil end
			task.delay(0.4, function() gui:Destroy() end)
			return lastMarker
		end,
	}
	return handle
end

return CastMeter
