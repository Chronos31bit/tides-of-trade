--!strict
-- NotificationUI.lua
-- Bottom-center ephemeral toast stack. Max N visible (FIFO drop), hold
-- then dismiss. Motion via MotionUtil; ReducedMotion = fade-only + halved
-- durations.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIUtil     = require(script.Parent.UIUtil)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local NotificationUI = {}

local CFG = UIUtil.Notification
local RM_SCALE = GameConfig.Harbor.VisualTuning.ReducedMotionDurationScale

type ToastEntry = {
	frame: Frame,
	label: TextLabel,
	stroke: UIStroke?,
	holdToken: {}?,
	dismissing: boolean,
	cleaned: boolean,
	dismiss: (immediate: boolean?) -> (),
}

local function scaledDuration(sec: number): number
	if MotionUtil.reducedMotionEnabled() then
		return sec * RM_SCALE
	end
	return sec
end

function NotificationUI.create(): { push: (string) -> (), destroy: () -> () }
	-- Same coordinate space as HUD (below Roblox top bar). Parent to ScreenGui
	-- like HUD.lua — siblings of UIScale, not under it (UIScale only scales
	-- its own descendants).
	local gui = UIUtil.makeScreenGui("NotificationUI", nil, { respectTopbar = true })
	gui.DisplayOrder = UIUtil.DisplayOrder.Notification

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(0.5, 1)
	stack.Position = UDim2.new(0.5, 0, 1, -CFG.BottomOffsetPx)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	stack.Size = UDim2.fromOffset(340, 0)
	stack.BackgroundTransparency = 1
	stack.ZIndex = 10
	stack.Parent = gui

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, UIUtil.Spacing.sm)
	list.Parent = stack

	local active: {ToastEntry} = {}
	local nextOrder = 0

	local function removeFromActive(entry: ToastEntry)
		for i, e in ipairs(active) do
			if e == entry then
				table.remove(active, i)
				break
			end
		end
	end

	local function cleanupEntry(entry: ToastEntry)
		if entry.cleaned then return end
		entry.cleaned = true
		entry.holdToken = nil
		removeFromActive(entry)
		if entry.frame.Parent then
			entry.frame:Destroy()
		end
	end

	local function dismissEntry(entry: ToastEntry, immediate: boolean?)
		if entry.dismissing then return end
		entry.dismissing = true
		entry.holdToken = nil

		if immediate then
			cleanupEntry(entry)
			return
		end

		local fadeSec = scaledDuration(CFG.FadeSec)
		local fadeInfo = TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		MotionUtil.tween(entry.label, fadeInfo, { TextTransparency = 1 })
		MotionUtil.tween(entry.frame, fadeInfo, { BackgroundTransparency = 1 })
		if entry.stroke then
			MotionUtil.tween(entry.stroke, fadeInfo, { Transparency = 1 })
		end

		-- Guaranteed teardown even if a tween is interrupted (hot-reload, reparent).
		task.delay(fadeSec + 0.15, function()
			cleanupEntry(entry)
		end)
	end

	local function showToast(text: string)
		nextOrder += 1

		local toast = UIUtil.makePanel({
			Name = "Toast",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			LayoutOrder = nextOrder,
			ZIndex = 10,
		})
		toast.BackgroundTransparency = 1
		local stroke = toast:FindFirstChildOfClass("UIStroke")

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, UIUtil.Spacing.md)
		pad.PaddingRight = UDim.new(0, UIUtil.Spacing.md)
		pad.PaddingTop = UDim.new(0, UIUtil.Spacing.sm)
		pad.PaddingBottom = UDim.new(0, UIUtil.Spacing.sm)
		pad.Parent = toast

		local label = UIUtil.makeLabel(text, "body", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = 1,
		})
		label.Parent = toast

		toast.Parent = stack

		local entry: ToastEntry = {
			frame = toast,
			label = label,
			stroke = stroke,
			holdToken = nil,
			dismissing = false,
			cleaned = false,
			dismiss = function(immediate: boolean?)
				dismissEntry(entry, immediate)
			end,
		}
		table.insert(active, entry)

		local fadeSec = scaledDuration(CFG.FadeSec)
		local fadeInfo = TweenInfo.new(fadeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		MotionUtil.tween(entry.label, fadeInfo, { TextTransparency = 0 })
		MotionUtil.tween(entry.frame, fadeInfo, { BackgroundTransparency = 0 })

		local holdToken = {}
		entry.holdToken = holdToken
		task.delay(scaledDuration(CFG.HoldSec), function()
			if entry.holdToken ~= holdToken or entry.dismissing or entry.cleaned then
				return
			end
			dismissEntry(entry, false)
		end)
	end

	local function push(text: string)
		while #active >= CFG.MaxQueue do
			local oldest = active[1]
			oldest.dismiss(true)
		end
		showToast(text)
	end

	local function destroy()
		for i = #active, 1, -1 do
			active[i].dismiss(true)
		end
		gui:Destroy()
	end

	return { push = push, destroy = destroy }
end

return NotificationUI
