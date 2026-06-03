--!strict
-- SailUI.lua
-- "Set Sail" modal — lists destinations (Shoreline → Trench → Home) with
-- locked/unlocked state. Unlocked rows are tappable; locked rows are greyed
-- with a reason line. Uses UIUtil.makeModalShell for chrome.
--
-- Public API:
--   SailUI.show(opts) -> SailHandle
--     opts = {
--       destinations : { string },        -- ordered list of destination keys
--       access       : {[string]: number}, -- AccessByDockTier map
--       dockTier     : number,             -- player's current dock tier
--       onSail       : (destination) -> (),
--       onClose      : (() -> ())?,
--     }
--   handle.close()

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local SailUI = {}

export type SailShowOpts = {
	destinations: { string },
	access:       {[string]: number},
	dockTier:     number,
	onSail:       (destination: string) -> (),
	onClose:      (() -> ())?,
}

export type SailHandle = {
	gui:   ScreenGui,
	close: () -> (),
}

-- Friendly display names for each destination (stable keys).
local DISPLAY_NAMES: {[string]: string} = {
	Shoreline = "Shoreline",
	Pier      = "Pier",
	Reef      = "Reef",
	DeepWater = "Deep Water",
	Trench    = "Trench",
	Home      = "Home",
}

-- Flavor text per destination (shown below locked rows).
local FLAVOR: {[string]: string} = {
	Reef      = "Requires Dock Tier 2",
	DeepWater = "Requires Dock Tier 2",
	Trench    = "Requires Dock Tier 3 — the deepest waters",
	Home      = "Return to your harbor",
}

function SailUI.show(opts: SailShowOpts): SailHandle
	local destinations = opts.destinations
	local access = opts.access
	local dockTier = opts.dockTier
	local onSail = opts.onSail
	local onClose = opts.onClose

	local shell = UIUtil.makeModalShell({
		name = "SailUI",
		title = "Set Sail",
		onClose = onClose,
		bodyPadding = UIUtil.Spacing.sm,
	})

	local body = shell.body

	-- ---- DESTINATION LIST ----
	local list = Instance.new("ScrollingFrame")
	list.Name = "DestinationList"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, UIUtil.Spacing.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Build one row per destination + Home.
	for i, dest in ipairs(destinations) do
		local requiredTier = access[dest]
		local isUnlocked = requiredTier == nil or dockTier >= requiredTier
		local displayName = DISPLAY_NAMES[dest] or dest
		local isHome = dest == "Home"

		local row = Instance.new("Frame")
		row.Name = "Row_" .. dest
		row.BackgroundColor3 = if isUnlocked then P.Teal else P.TealDeeper
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, UIUtil.MinTouchPx + (if isUnlocked then 0 else 16))
		row.LayoutOrder = i
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, UIUtil.Radii.md)
		rowCorner.Parent = row
		row.Parent = list

		-- Destination name (left side).
		local nameLabel = UIUtil.makeLabel(displayName, "body", {
			Position = UDim2.new(0, UIUtil.Spacing.md, 0, 0),
			Size = UDim2.new(0.6, -(UIUtil.Spacing.md * 2), 0, UIUtil.MinTouchPx),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if isUnlocked then P.Cream else P.CreamSoft,
		})
		nameLabel.Parent = row

		if isUnlocked and not isHome then
			-- Tier badge (right side).
			local tierLabel = UIUtil.makeLabel(
				("Tier %d"):format(requiredTier or 1),
				"caption", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -(UIUtil.Spacing.md + 8), 0, 4),
					Size = UDim2.new(0, 60, 0, UIUtil.MinTouchPx - 8),
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = P.SunsetSoft,
				}
			)
			tierLabel.Parent = row
		elseif isHome then
			-- Home icon indicator.
			local homeLabel = UIUtil.makeLabel("🏠", "body", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -(UIUtil.Spacing.md), 0, 0),
				Size = UDim2.new(0, UIUtil.MinTouchPx, 0, UIUtil.MinTouchPx),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			homeLabel.Parent = row
		else
			-- Locked: reason line below name.
			local lockLabel = UIUtil.makeLabel("🔒", "body", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -(UIUtil.Spacing.md), 0, 0),
				Size = UDim2.new(0, UIUtil.MinTouchPx, 0, UIUtil.MinTouchPx),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			lockLabel.Parent = row

			local flavor = FLAVOR[dest] or "Locked"
			local reasonLabel = UIUtil.makeLabel(flavor, "caption", {
				Position = UDim2.new(0, UIUtil.Spacing.md, 0, UIUtil.MinTouchPx - 4),
				Size = UDim2.new(0.6, 0, 0, 16),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = P.CreamSoft,
			})
			reasonLabel.Parent = row
		end

		-- Make tappable if unlocked or Home.
		if isUnlocked then
			local btn = Instance.new("TextButton")
			btn.Name = "Tap_" .. dest
			btn.BackgroundTransparency = 1
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.Size = UDim2.fromScale(1, 1)
			btn.Parent = row

			btn.Activated:Connect(function()
				onSail(if isHome then "Home" else dest)
			end)
		end
	end

	-- Close on backdrop.
	local closed = false
	local function close()
		if closed then return end
		closed = true
		shell.close()
	end

	-- Override shell close with our tracked close.
	local originalClose = shell.close
	shell.close = function()
		close()
	end

	return {
		gui   = shell.gui,
		close = close,
	}
end

return SailUI
