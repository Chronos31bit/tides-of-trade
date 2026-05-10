--!strict
-- HarborEditUI.lua
-- Build-mode UI: bottom palette of buildings, top hint with the selected
-- building's stats, "Confirm placement" button. The actual ghost preview is
-- driven by HarborEditController — this module only owns the menu chrome.

local UIUtil = require(script.Parent.UIUtil)

local HarborEditUI = {}

export type HarborEditHandle = {
	gui: ScreenGui,
	close: () -> (),
	-- onSelectBuilding(kind) is called when the user taps a palette item.
	-- onRotate / onConfirm / onCancel are wired by the controller.
}

function HarborEditUI.show(catalog: any, onSelect: (string) -> (), onRotate: () -> (), onConfirm: () -> (), onCancel: () -> ()): HarborEditHandle
	local gui = UIUtil.makeScreenGui("HarborEditUI")

	-- Top hint bar — shows what's selected and reminds user how to rotate.
	local hint = UIUtil.makePanel({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.new(0.86, 0, 0, 44),
		BackgroundColor3 = UIUtil.Palette.TealDark,
		BackgroundTransparency = 0.1,
	})
	local hintMax = Instance.new("UISizeConstraint"); hintMax.MaxSize = Vector2.new(720, 44); hintMax.Parent = hint
	hint.Parent = gui
	local hintLabel = UIUtil.makeLabel("Pick a building", "body", {
		Position = UDim2.new(0, 16, 0, 0),
		Size = UDim2.new(1, -32, 1, 0),
	})
	hintLabel.Parent = hint

	-- Right-side action stack: rotate / confirm / cancel.
	local actions = UIUtil.makeFrame({
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(140, 240),
		BackgroundTransparency = 1,
	})
	actions.Parent = gui
	local actLayout = Instance.new("UIListLayout")
	actLayout.Padding = UDim.new(0, 8); actLayout.Parent = actions

	local rotateBtn = UIUtil.makeButton("Rotate", onRotate, { Size = UDim2.fromOffset(140, 56), BackgroundColor3 = UIUtil.Palette.Wood })
	rotateBtn.Parent = actions
	local confirmBtn = UIUtil.makeButton("Place", onConfirm, { Size = UDim2.fromOffset(140, 56) })
	confirmBtn.Parent = actions
	local cancelBtn = UIUtil.makeButton("Cancel", function()
		onCancel()
		gui:Destroy()
	end, { Size = UDim2.fromOffset(140, 56), BackgroundColor3 = UIUtil.Palette.Danger })
	cancelBtn.Parent = actions

	-- Bottom palette: scroll-horizontal so phone players can swipe through
	-- buildings instead of scrolling vertically into the action bar.
	local palette = UIUtil.makePanel({
		Name = "Palette",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100),  -- sits above the action bar
		Size = UDim2.new(0.86, 0, 0, 96),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local palMax = Instance.new("UISizeConstraint"); palMax.MaxSize = Vector2.new(720, 96); palMax.Parent = palette
	palette.Parent = gui

	local scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.ScrollingDirection = Enum.ScrollingDirection.X
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroller.ScrollBarThickness = 4
	scroller.Parent = palette

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Parent = scroller
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8); pad.Parent = scroller

	for kind, def in pairs(catalog) do
		local card = UIUtil.makeButton(def.displayName, function()
			onSelect(kind)
			hintLabel.Text = ("%s — %s"):format(def.displayName, def.description)
		end, {
			Size = UDim2.fromOffset(140, 72),
			BackgroundColor3 = UIUtil.Palette.Teal,
			TextSize = 14,
		})
		card.Parent = scroller
		-- Append cost label below the name. We re-author the button content
		-- since UIUtil.makeButton sets Text directly.
		local cost = UIUtil.makeLabel(("%d coins"):format(def.tiers[1].cost), "caption", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -12, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = UIUtil.Palette.Gold,
		})
		cost.Parent = card
	end

	return {
		gui = gui,
		close = function() gui:Destroy() end,
	}
end

return HarborEditUI
