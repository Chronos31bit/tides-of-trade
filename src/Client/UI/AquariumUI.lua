--!strict
-- AquariumUI.lua (rewrite)
-- Two-column manager: left = fish currently in this aquarium, right =
-- inventory available to deposit. Tap an item to move it across.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

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
	local gui = UIUtil.makeScreenGui("AquariumUI")

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.94, 0, 0.88, 0)
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = P.TealDeeper; ps.Thickness = 1.5; ps.Transparency = 0.25; ps.Parent = panel
	local pcap = Instance.new("UISizeConstraint"); pcap.MaxSize = Vector2.new(940, 740); pcap.Parent = panel
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 20, 0, 14)
	title.Size = UDim2.new(0.5, 0, 0, 30)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = P.Cream
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Aquarium"
	title.Parent = panel

	-- Capacity counter on the right of the title.
	local capLbl = Instance.new("TextLabel")
	capLbl.BackgroundTransparency = 1
	capLbl.AnchorPoint = Vector2.new(1, 0)
	capLbl.Position = UDim2.new(1, -120, 0, 18)
	capLbl.Size = UDim2.fromOffset(100, 26)
	capLbl.Font = Enum.Font.GothamBold
	capLbl.TextSize = 16
	capLbl.TextColor3 = P.Gold
	capLbl.TextXAlignment = Enum.TextXAlignment.Right
	capLbl.Text = ("0 / %d"):format(capacity)
	capLbl.Parent = panel

	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(84, 36),
		BackgroundColor3 = P.Wood,
	})
	closeBtn.Parent = panel

	-- ----------------------------------------------------------------
	-- Two-column body.
	-- ----------------------------------------------------------------
	local function makeColumn(headerText: string, xAnchor: number)
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Position = UDim2.new(xAnchor, xAnchor == 0 and 16 or 0, 0, 60)
		col.Size = UDim2.new(0.5, xAnchor == 0 and -20 or -16, 1, -76)
		col.Parent = panel

		local header = Instance.new("TextLabel")
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, 0, 0, 22)
		header.Font = Enum.Font.GothamBold
		header.TextSize = 13
		header.TextColor3 = P.CreamSoft
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = headerText:upper()
		header.Parent = col

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
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 10); sc.Parent = scroll
		scroll.Parent = col

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
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
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = P.TealDark
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 8); rc.Parent = row
		row.Parent = parent

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 12, 0, 4)
		name.Size = UDim2.new(1, -100, 0, 22)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextColor3 = P.Cream
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = titleCase(item.speciesId or "fish")
		name.Parent = row

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.new(0, 12, 0, 26)
		sub.Size = UDim2.new(1, -100, 0, 16)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 12
		sub.TextColor3 = P.CreamSoft
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Text = ("%.1f kg"):format(item.weightKg or 0)
		sub.Parent = row

		local btn = UIUtil.makeButton(action, onClick, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(76, 34),
			BackgroundColor3 = (action == "Take") and P.Wood or P.Sunset,
		})
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
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 36)
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 14
			empty.TextColor3 = P.CreamSoft
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = "Empty — add fish from inventory →"
			empty.Parent = leftScroll
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
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 36)
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 14
			empty.TextColor3 = P.CreamSoft
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = "No fish in inventory."
			empty.Parent = rightScroll
		else
			for _, item in ipairs(fish) do
				buildCard(rightScroll, item, "Add", function() onDeposit(item.uid) end)
			end
		end
	end
	refresh(contents, inventory, capacity)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

return AquariumUI
