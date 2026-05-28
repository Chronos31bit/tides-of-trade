--!strict
-- NotificationUI.lua
-- Bottom-center ephemeral toast stack. Layout from NotificationUI_Template;
-- FIFO cap, hold then fade dismiss. ReducedMotion: fade only (no slide).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)
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

local function req(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[NotificationUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function scaledDuration(sec: number): number
	if MotionUtil.reducedMotionEnabled() then
		return sec * RM_SCALE
	end
	return sec
end

function NotificationUI.create(): { push: (string) -> (), destroy: () -> () }
	local gui = TemplateLoader.spawn("Notification", { instanceName = "NotificationUI" })
	gui.Enabled = true

	local stack = req(gui, "StackContainer", "Frame") :: Frame
	stack.Position = UDim2.new(0.5, 0, 1, -CFG.BottomOffsetPx)

	local toastTemplate = req(gui, "Toast_Template", "Frame") :: Frame

	local active: { ToastEntry } = {}
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
		if entry.cleaned then
			return
		end
		entry.cleaned = true
		entry.holdToken = nil
		removeFromActive(entry)
		if entry.frame.Parent then
			entry.frame:Destroy()
		end
	end

	local function dismissEntry(entry: ToastEntry, immediate: boolean?)
		if entry.dismissing then
			return
		end
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

		task.delay(fadeSec + 0.15, function()
			cleanupEntry(entry)
		end)
	end

	local function showToast(text: string)
		nextOrder += 1

		local toast = toastTemplate:Clone()
		toast.Name = "Toast"
		toast.Visible = true
		toast.LayoutOrder = nextOrder
		toast.BackgroundTransparency = 1

		local label = req(toast, "MessageLabel", "TextLabel") :: TextLabel
		label.Text = text
		label.TextTransparency = 1

		local stroke = toast:FindFirstChildOfClass("UIStroke")
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

		-- Fade only — no slide (required under ReducedMotion; same for default).
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
