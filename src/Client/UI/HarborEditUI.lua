--!strict
-- HarborEditUI.lua (rewrite)
-- Build mode UI: hint banner at top center, action stack on the right,
-- horizontal palette at the bottom. All solid panels — no gradients, no
-- transparency, big readable text.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local HarborEditUI = {}

export type HarborEditHandle = {
	gui: ScreenGui,
	close: () -> (),
	setHint: (text: string) -> (),
	setDemolishActive: (active: boolean) -> (),
	setUpgradeActive: (active: boolean) -> (),
}

function HarborEditUI.show(
	catalog: any,
	onSelect: (string) -> (),
	onRotate: () -> (),
	onConfirm: () -> (),
	onDemolish: () -> (),
	onUpgrade: () -> (),
	onCancel: () -> ()
): HarborEditHandle
	local gui = UIUtil.makeScreenGui("HarborEditUI", nil, { respectTopbar = true })

	-- ----------------------------------------------------------------
	-- HINT BANNER — solid pill, top center.
	-- ----------------------------------------------------------------
	local hint = Instance.new("Frame")
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 16)
	hint.Size = UDim2.new(0.7, 0, 0, 48)
	hint.BackgroundColor3 = P.TealDark
	hint.BorderSizePixel = 0
	local hintCorner = Instance.new("UICorner"); hintCorner.CornerRadius = UDim.new(0, 10); hintCorner.Parent = hint
	local hintStroke = Instance.new("UIStroke"); hintStroke.Color = P.TealDeeper; hintStroke.Thickness = 1.5; hintStroke.Transparency = 0.3; hintStroke.Parent = hint
	local hintCap = Instance.new("UISizeConstraint"); hintCap.MaxSize = Vector2.new(720, 48); hintCap.Parent = hint
	hint.Parent = gui

	local hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.Position = UDim2.new(0, 16, 0, 0)
	hintLabel.Size = UDim2.new(1, -32, 1, 0)
	hintLabel.Font = Enum.Font.GothamSemibold
	hintLabel.TextSize = 15
	hintLabel.TextColor3 = P.Cream
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextYAlignment = Enum.TextYAlignment.Center
	hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
	hintLabel.Text = "Pick a building below."
	hintLabel.Parent = hint

	-- ----------------------------------------------------------------
	-- ACTION STACK — Rotate / Place / Cancel, right side.
	-- ----------------------------------------------------------------
	local actions = Instance.new("Frame")
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.Position = UDim2.new(1, -16, 0.5, 0)
	-- Five buttons now (added Upgrade), bump the stack height accordingly.
	actions.Size = UDim2.fromOffset(140, 356)
	actions.BackgroundTransparency = 1
	actions.Parent = gui

	local actLayout = Instance.new("UIListLayout")
	actLayout.Padding = UDim.new(0, 10)
	actLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actLayout.Parent = actions

	local function makeAction(label: string, tint: Color3, cb: () -> ()): TextButton
		local b = UIUtil.makeButton(label, cb, {
			Size = UDim2.fromOffset(140, 56),
			BackgroundColor3 = tint,
		})
		return b
	end

	local rotateBtn = makeAction("Rotate", P.Wood, onRotate)
	rotateBtn.LayoutOrder = 1
	rotateBtn.Parent = actions

	local placeBtn = makeAction("Place", P.Sunset, onConfirm)
	placeBtn.LayoutOrder = 2
	placeBtn.Parent = actions

	-- Upgrade is a mode: while on, world-clicks call HarborService:Upgrade
	-- on whichever building was hit. Costs are taken from the catalog tier.
	local upgradeBtn = makeAction("Upgrade", P.Gold, onUpgrade)
	upgradeBtn.LayoutOrder = 3
	upgradeBtn.Parent = actions

	-- Demolish is a *mode*, not a one-shot. The controller flips a state
	-- flag and intercepts world clicks. The button itself just calls the
	-- callback (controller updates the label to "Demolishing…" when active).
	local demolishBtn = makeAction("Demolish", P.Danger, onDemolish)
	demolishBtn.LayoutOrder = 4
	demolishBtn.Parent = actions

	local cancelBtn = makeAction("Cancel", P.Wood, function()
		onCancel()
		gui:Destroy()
	end)
	cancelBtn.LayoutOrder = 5
	cancelBtn.Parent = actions

	-- ----------------------------------------------------------------
	-- PALETTE — bottom horizontal scroller of building cards.
	-- ----------------------------------------------------------------
	local palette = Instance.new("Frame")
	palette.AnchorPoint = Vector2.new(0.5, 1)
	palette.Position = UDim2.new(0.5, 0, 1, -16)
	palette.Size = UDim2.new(0.86, 0, 0, 132)
	palette.BackgroundColor3 = P.TealDark
	palette.BorderSizePixel = 0
	local palCorner = Instance.new("UICorner"); palCorner.CornerRadius = UDim.new(0, 14); palCorner.Parent = palette
	local palStroke = Instance.new("UIStroke"); palStroke.Color = P.TealDeeper; palStroke.Thickness = 1.5; palStroke.Transparency = 0.3; palStroke.Parent = palette
	local palCap = Instance.new("UISizeConstraint"); palCap.MaxSize = Vector2.new(900, 132); palCap.Parent = palette
	palette.Parent = gui

	local palPad = Instance.new("UIPadding")
	palPad.PaddingTop = UDim.new(0, 12); palPad.PaddingBottom = UDim.new(0, 12)
	palPad.PaddingLeft = UDim.new(0, 12); palPad.PaddingRight = UDim.new(0, 12)
	palPad.Parent = palette

	local scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.ScrollingDirection = Enum.ScrollingDirection.X
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroller.ScrollBarThickness = 4
	scroller.ScrollBarImageColor3 = P.TealDeeper
	scroller.Parent = palette

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Parent = scroller

	-- ----------------------------------------------------------------
	-- BUILDING CARDS — solid teal block, big name top, cost bottom in gold.
	-- ----------------------------------------------------------------
	-- We sort by tier1 cost so the cheapest cards appear first (player
	-- intuition: start with what they can afford).
	local sorted = {}
	for kind, def in pairs(catalog) do
		table.insert(sorted, { kind = kind, def = def })
	end
	table.sort(sorted, function(a, b) return a.def.tiers[1].cost < b.def.tiers[1].cost end)

	for i, entry in ipairs(sorted) do
		local def = entry.def
		local card = Instance.new("TextButton")
		card.AutoButtonColor = false
		card.BackgroundColor3 = P.Teal
		card.BorderSizePixel = 0
		card.Text = ""
		card.Size = UDim2.fromOffset(150, 100)
		card.LayoutOrder = i
		card.Parent = scroller
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = P.TealDeeper; cs.Thickness = 1.2; cs.Transparency = 0.4; cs.Parent = card

		-- Building name — top half, big bold cream.
		local nameLbl = Instance.new("TextLabel")
		nameLbl.BackgroundTransparency = 1
		nameLbl.Position = UDim2.new(0, 8, 0, 8)
		nameLbl.Size = UDim2.new(1, -16, 0, 24)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 16
		nameLbl.TextColor3 = P.Cream
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Text = def.displayName
		nameLbl.Parent = card

		-- Footprint subtitle — small cream-soft.
		local foot = Instance.new("TextLabel")
		foot.BackgroundTransparency = 1
		foot.Position = UDim2.new(0, 8, 0, 32)
		foot.Size = UDim2.new(1, -16, 0, 14)
		foot.Font = Enum.Font.Gotham
		foot.TextSize = 11
		foot.TextColor3 = P.CreamSoft
		foot.TextXAlignment = Enum.TextXAlignment.Left
		foot.Text = ("%d × %d cells"):format(def.footprint[1], def.footprint[2])
		foot.Parent = card

		-- Cost — bottom, gold, GothamBold.
		local cost = Instance.new("TextLabel")
		cost.BackgroundTransparency = 1
		cost.AnchorPoint = Vector2.new(0, 1)
		cost.Position = UDim2.new(0, 8, 1, -8)
		cost.Size = UDim2.new(1, -16, 0, 22)
		cost.Font = Enum.Font.GothamBold
		cost.TextSize = 16
		cost.TextColor3 = P.Gold
		cost.TextXAlignment = Enum.TextXAlignment.Left
		cost.Text = (def.tiers[1].cost == 0) and "FREE" or (("%d coins"):format(def.tiers[1].cost))
		cost.Parent = card

		-- Hover/press feedback.
		local rest = P.Teal
		local hover = rest:Lerp(Color3.new(1, 1, 1), 0.08)
		local pressed = rest:Lerp(Color3.new(0, 0, 0), 0.2)
		local TweenService = game:GetService("TweenService")
		local tween = TweenInfo.new(0.08)
		card.MouseEnter:Connect(function() TweenService:Create(card, tween, { BackgroundColor3 = hover }):Play() end)
		card.MouseLeave:Connect(function() card.BackgroundColor3 = rest end)
		card.MouseButton1Down:Connect(function() TweenService:Create(card, tween, { BackgroundColor3 = pressed }):Play() end)
		card.MouseButton1Up:Connect(function() TweenService:Create(card, tween, { BackgroundColor3 = hover }):Play() end)
		card.Activated:Connect(function()
			onSelect(entry.kind)
			-- Update hint banner with selected building's description.
			hintLabel.Text = ("%s — %s"):format(def.displayName, def.description)
		end)
	end

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		setHint = function(text: string) hintLabel.Text = text end,
		setDemolishActive = function(active: boolean)
			-- Visual cue: when demolish is on, the button stays "lit" red and
			-- the hint banner explains what clicking does. Off restores it.
			demolishBtn.BackgroundColor3 = active and P.Danger or P.Danger:Lerp(Color3.new(0,0,0), 0.25)
			demolishBtn.Text = active and "Cancel Demolish" or "Demolish"
			if active then
				hintLabel.Text = "Click a placed building to remove it."
			end
		end,
		setUpgradeActive = function(active: boolean)
			upgradeBtn.BackgroundColor3 = active and P.Gold or P.Gold:Lerp(Color3.new(0,0,0), 0.25)
			upgradeBtn.Text = active and "Cancel Upgrade" or "Upgrade"
			if active then
				hintLabel.Text = "Click a placed building to upgrade it (costs coins)."
			end
		end,
	}
end

return HarborEditUI
