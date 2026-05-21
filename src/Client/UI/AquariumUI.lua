--!strict
-- AquariumUI.lua
-- Two-column manager: left = fish currently in this aquarium, right =
-- inventory available to deposit. Tap a row's action button to move it
-- across. No Danger-red anywhere — deposit/withdraw are calm actions.

local UIUtil = require(script.Parent.UIUtil)

local P    = UIUtil.Palette
local SP   = UIUtil.Spacing
local RAD  = UIUtil.Radii

local AquariumUI = {}

export type AquariumHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (contents: {any}, inventory: {any}, capacity: number) -> (),
}

local function titleCase(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function AquariumUI.show(
	contents: {any},
	inventory: {any},
	capacity: number,
	onDeposit: (string) -> (),
	onWithdraw: (string) -> ()
): AquariumHandle
	local shell
	shell = UIUtil.makeModalShell({
		name = "AquariumUI",
		title = "Aquarium",
		onClose = function() if shell then shell.destroy() end end,
		width = 720,
		heightScale = 0.88,
	})
	local gui  = shell.gui
	local body = shell.body

	-- Capacity counter lives in the header to the left of the close button.
	local capLbl = UIUtil.makeLabel(("0 / %d"):format(capacity), "subtitle", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(UIUtil.Modal.CloseButtonPx + UIUtil.Spacing.xl), 0.5, 0),
		Size = UDim2.fromOffset(120, 26),
		Font = Enum.Font.GothamBold,
		TextColor3 = P.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = shell.header,
	})

	local function makeColumn(headerText: string, xAnchor: number)
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Position = UDim2.new(xAnchor, xAnchor == 0 and 0 or SP.sm, 0, 0)
		col.Size = UDim2.new(0.5, xAnchor == 0 and -SP.sm or -SP.sm, 1, 0)
		col.Parent = body

		UIUtil.makeLabel(headerText:upper(), "subtitle", {
			Size = UDim2.new(1, 0, 0, 22),
			Font = Enum.Font.GothamBold,
			TextColor3 = P.CreamSoft,
			Parent = col,
		})

		local scroll = Instance.new("ScrollingFrame")
		scroll.BackgroundColor3 = P.Teal
		scroll.BackgroundTransparency = 0
		scroll.BorderSizePixel = 0
		scroll.Position = UDim2.new(0, 0, 0, 30)
		scroll.Size = UDim2.new(1, 0, 1, -30)
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = P.TealDeeper
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, RAD.md); sc.Parent = scroll
		scroll.Parent = col

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, SP.sm); pad.PaddingBottom = UDim.new(0, SP.sm)
		pad.PaddingLeft = UDim.new(0, SP.sm); pad.PaddingRight = UDim.new(0, SP.sm)
		pad.Parent = scroll

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.Parent = scroll
		return scroll
	end

	local leftScroll  = makeColumn("In Aquarium  (tap to remove)", 0)
	local rightScroll = makeColumn("Inventory  (tap to add)",       0.5)

	local function buildCard(parent: ScrollingFrame, item: any, action: string, onClick: () -> ())
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 52)
		row.BackgroundColor3 = P.TealDark
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, RAD.sm); rc.Parent = row
		row.Parent = parent

		UIUtil.makeLabel(titleCase(item.speciesId or "fish"), "body", {
			Position = UDim2.new(0, SP.md, 0, SP.xs),
			Size = UDim2.new(1, -110, 0, 22),
			Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		UIUtil.makeLabel(("%.1f kg"):format(item.weightKg or 0), "caption", {
			Position = UDim2.new(0, SP.md, 0, 26),
			Size = UDim2.new(1, -110, 0, 18),
			Parent = row,
		})

		local btn
		if action == "Take" then
			btn = UIUtil.makeSecondaryButton(action, onClick, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SP.sm, 0.5, 0),
				Size = UDim2.fromOffset(80, UIUtil.MinTouchPx),
			})
		else
			btn = UIUtil.makePrimaryButton(action, onClick, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -SP.sm, 0.5, 0),
				Size = UDim2.fromOffset(80, UIUtil.MinTouchPx),
			})
		end
		btn.Parent = row
	end

	local function refresh(contents_: {any}, inv: {any}, cap_: number)
		capLbl.Text = ("%d / %d"):format(#contents_, cap_)

		for _, c in ipairs(leftScroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for _, c in ipairs(rightScroll:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end

		if #contents_ == 0 then
			UIUtil.makeLabel("Empty — add fish from inventory →", "subtitle", {
				Size = UDim2.new(1, 0, 0, 36),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = leftScroll,
			})
		else
			for _, item in ipairs(contents_) do
				buildCard(leftScroll, item, "Take", function() onWithdraw(item.uid) end)
			end
		end

		-- Only fish can go in aquariums.
		local fish = {}
		for _, item in ipairs(inv) do
			if item.kind == "Fish" then table.insert(fish, item) end
		end
		if #fish == 0 then
			UIUtil.makeLabel("No fish in inventory.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 36),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = rightScroll,
			})
		else
			for _, item in ipairs(fish) do
				buildCard(rightScroll, item, "Add", function() onDeposit(item.uid) end)
			end
		end
	end
	refresh(contents, inventory, capacity)

	return {
		gui = gui,
		close = function() shell.destroy() end,
		refresh = refresh,
	}
end

return AquariumUI
