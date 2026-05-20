--!strict
-- HarborEditUI.lua (rewrite)
-- Build mode UI: hint banner at top center, action stack on the right,
-- horizontal palette at the bottom. All solid panels — no gradients, no
-- transparency, big readable text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIUtil = require(script.Parent.UIUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local P    = UIUtil.Palette
local SP   = UIUtil.Spacing
local RAD  = UIUtil.Radii

local HarborEditUI = {}

export type HarborEditHandle = {
	gui: ScreenGui,
	close: () -> (),
	setHint: (text: string) -> (),
	setRotationHint: (degrees: number) -> (),
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
	gui.DisplayOrder = UIUtil.DisplayOrder.Modal

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

	local rotateBtn = UIUtil.makeButton("Rotate 90°", onRotate, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(100, UIUtil.MinTouchPx),
		BackgroundColor3 = P.Wood,
	})
	rotateBtn.Parent = hint

	local hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.Position = UDim2.new(0, 16, 0, 0)
	hintLabel.Size = UDim2.new(1, -(16 + 100 + 12 + 16), 1, 0)
	hintLabel.Font = Enum.Font.GothamSemibold
	hintLabel.TextSize = 15
	hintLabel.TextColor3 = P.Cream
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.TextYAlignment = Enum.TextYAlignment.Center
	hintLabel.TextTruncate = Enum.TextTruncate.AtEnd
	hintLabel.Text = "Pick a building below."
	hintLabel.Parent = hint

	-- ----------------------------------------------------------------
	-- ACTION STACK — Place / Upgrade / Demolish / Cancel, right side.
	-- ----------------------------------------------------------------
	local actions = Instance.new("Frame")
	actions.AnchorPoint = Vector2.new(1, 0.5)
	actions.Position = UDim2.new(1, -16, 0.5, 0)
	actions.Size = UDim2.fromOffset(140, 296)
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

	local placeBtn = makeAction("Place", P.Sunset, onConfirm)
	placeBtn.LayoutOrder = 1
	placeBtn.Parent = actions

	-- Upgrade is a mode: while on, world-clicks call HarborService:Upgrade
	-- on whichever building was hit. Costs are taken from the catalog tier.
	local upgradeBtn = makeAction("Upgrade", P.Gold, onUpgrade)
	upgradeBtn.LayoutOrder = 2
	upgradeBtn.Parent = actions

	-- Demolish is a *mode*, not a one-shot. The controller flips a state
	-- flag and intercepts world clicks. The button itself just calls the
	-- callback (controller updates the label to "Demolishing…" when active).
	local demolishBtn = makeAction("Demolish", P.Danger, onDemolish)
	demolishBtn.LayoutOrder = 3
	demolishBtn.Parent = actions

	local cancelBtn = makeAction("Cancel", P.Wood, function()
		onCancel()
		gui:Destroy()
	end)
	cancelBtn.LayoutOrder = 4
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
	table.sort(sorted, function(a, b)
		local aCost = (GameConfig.Buildings[a.kind] and GameConfig.Buildings[a.kind].tierCosts[1]) or 0
		local bCost = (GameConfig.Buildings[b.kind] and GameConfig.Buildings[b.kind].tierCosts[1]) or 0
		return aCost < bCost
	end)

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

		-- Footprint subtitle — small cream-soft. 12px floor (was 11).
		UIUtil.makeLabel(("%d × %d cells"):format(def.footprint[1], def.footprint[2]), "caption", {
			Position = UDim2.new(0, SP.sm, 0, 32),
			Size = UDim2.new(1, -SP.lg, 0, 16),
			Parent = card,
		})

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
		local tier1Cost = (GameConfig.Buildings[entry.kind] and GameConfig.Buildings[entry.kind].tierCosts[1]) or 0
		cost.Text = (tier1Cost == 0) and "FREE" or (("%d coins"):format(tier1Cost))
		cost.Parent = card

		-- Hover/press feedback — routed through MotionUtil so the
		-- snap-to-final behaviour under ReducedMotion is honoured.
		local rest = P.Teal
		local hover = rest:Lerp(Color3.new(1, 1, 1), 0.08)
		local pressed = rest:Lerp(Color3.new(0, 0, 0), 0.2)
		local info = TweenInfo.new(0.08)
		card.MouseEnter:Connect(function() MotionUtil.tweenOrSnap(card, info, { BackgroundColor3 = hover }) end)
		card.MouseLeave:Connect(function() MotionUtil.tweenOrSnap(card, info, { BackgroundColor3 = rest }) end)
		card.MouseButton1Down:Connect(function() MotionUtil.tweenOrSnap(card, info, { BackgroundColor3 = pressed }) end)
		card.MouseButton1Up:Connect(function() MotionUtil.tweenOrSnap(card, info, { BackgroundColor3 = hover }) end)
		card.Activated:Connect(function()
			onSelect(entry.kind)
			hintLabel.Text = ("%s — %s  (tap Rotate, then Place)"):format(def.displayName, def.description)
		end)
	end

	local function rotationSuffix(degrees: number): string
		return ("  ·  facing %d°"):format(degrees % 360)
	end

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		hintLabel = hintLabel,
		setHint = function(text: string) hintLabel.Text = text end,
		setRotationHint = function(degrees: number)
			local base = hintLabel.Text
			local cut = base:find("  ·  facing ")
			if cut then base = base:sub(1, cut - 1) end
			hintLabel.Text = base .. rotationSuffix(degrees)
		end,
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

-- Confirmation popup before destroying a building. Uses the shared modal
-- shell so it matches the rest of the chrome. Demolish is the dangerous
-- action (red Danger variant); Cancel is the secondary.
function HarborEditUI.showDemolishConfirm(kind: string, onConfirm: () -> (), onCancel: (() -> ())?)
	local shell
	shell = UIUtil.makeModalShell({
		name = "DemolishConfirm",
		title = "Demolish " .. kind .. "?",
		onClose = function()
			if shell then shell.destroy() end
			if onCancel then onCancel() end
		end,
		width = 400,
		heightScale = 0.34,
	})

	local body = shell.body

	UIUtil.makeLabel(
		"This is permanent and you won't get the coins back.",
		"body",
		{
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, 1, -UIUtil.MinTouchPx - SP.md),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = P.CreamSoft,
			Parent = body,
		}
	)

	local cancelBtn = UIUtil.makeGhostButton("Cancel", function()
		shell.destroy()
		if onCancel then onCancel() end
	end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.fromOffset(140, UIUtil.MinTouchPx),
	})
	cancelBtn.Parent = body

	local confirmBtn = UIUtil.makeDangerButton("Demolish", function()
		shell.destroy()
		onConfirm()
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(140, UIUtil.MinTouchPx),
	})
	confirmBtn.Parent = body
end

return HarborEditUI
