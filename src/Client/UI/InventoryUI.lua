--!strict
-- InventoryUI.lua (rewrite)
-- Modal grid of inventory cards. Each card has a rarity stripe down the
-- left edge, name + weight, and two action buttons: Sell (instant dock NPC)
-- and List (open market price prompt).

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local InventoryUI = {}

export type InventoryHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (items: {any}) -> (),
}

-- Pseudo-rarity color based on the species id's first byte. We don't
-- import the catalog here to keep the UI module decoupled from data;
-- consistent-enough coloring for solo testing.
local RARITY_TINTS = { P.Common, P.Uncommon, P.Rare, P.Mythic }
local function rarityTint(speciesId: string?): Color3
	if not speciesId then return P.Common end
	local b = string.byte(speciesId, 1) or 0
	return RARITY_TINTS[(b % 4) + 1]
end

function InventoryUI.show(
	items: {any},
	onListRequest: (string, number) -> (),
	onQuickSell: (string) -> (),
	suggestedPriceFor: (any) -> number
): InventoryHandle
	local gui = UIUtil.makeScreenGui("InventoryUI")

	-- Full-screen darkening backdrop.
	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	-- Solid panel.
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0.85, 0)
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	local pcorner = Instance.new("UICorner"); pcorner.CornerRadius = UDim.new(0, 14); pcorner.Parent = panel
	local pstroke = Instance.new("UIStroke"); pstroke.Color = P.TealDeeper; pstroke.Thickness = 1.5; pstroke.Transparency = 0.25; pstroke.Parent = panel
	local pcap = Instance.new("UISizeConstraint"); pcap.MaxSize = Vector2.new(820, 720); pcap.Parent = panel
	panel.Parent = gui

	-- Title row.
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 20, 0, 14)
	title.Size = UDim2.new(1, -120, 0, 30)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = P.Cream
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Inventory"
	title.Parent = panel

	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(84, 36),
		BackgroundColor3 = P.Wood,
	})
	closeBtn.Parent = panel

	-- Scrolling grid.
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 14, 0, 60)
	list.Size = UDim2.new(1, -28, 1, -74)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(240, 96)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	local function buildCard(item: any, idx: number)
		local card = Instance.new("Frame")
		card.BackgroundColor3 = P.Teal
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = P.TealDeeper; cs.Thickness = 1; cs.Transparency = 0.5; cs.Parent = card
		card.Parent = list

		-- Rarity stripe on the left edge.
		local stripe = Instance.new("Frame")
		stripe.BackgroundColor3 = rarityTint(item.speciesId)
		stripe.BorderSizePixel = 0
		stripe.Size = UDim2.new(0, 6, 1, 0)
		stripe.Parent = card

		local nameText: string
		if item.kind == "Fish" then
			-- Title-case the species id ("harbor_mackerel" -> "Harbor Mackerel").
			nameText = (item.speciesId or "fish"):gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
		else
			nameText = (item.goodId or "Item"):gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
		end
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 16, 0, 6)
		name.Size = UDim2.new(1, -32, 0, 22)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 16
		name.TextColor3 = P.Cream
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = nameText
		name.Parent = card

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.new(0, 16, 0, 28)
		sub.Size = UDim2.new(1, -32, 0, 16)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 12
		sub.TextColor3 = P.CreamSoft
		sub.TextXAlignment = Enum.TextXAlignment.Left
		if item.kind == "Fish" then
			sub.Text = ("%.1f kg"):format(item.weightKg or 0)
		else
			sub.Text = ("× %d"):format(item.count or 1)
		end
		sub.Parent = card

		-- Two stacked action buttons in the bottom-right.
		local sellBtn = UIUtil.makeButton("Sell", function() onQuickSell(item.uid) end, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -94, 1, -8),
			Size = UDim2.fromOffset(80, 30),
			BackgroundColor3 = P.Wood,
		})
		sellBtn.Parent = card

		local listBtn = UIUtil.makeButton("List", function()
			onListRequest(item.uid, suggestedPriceFor(item))
		end, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -8),
			Size = UDim2.fromOffset(80, 30),
			BackgroundColor3 = P.Sunset,
		})
		listBtn.Parent = card
	end

	local function refresh(items_: {any})
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		if #items_ == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 60)
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 16
			empty.TextColor3 = P.CreamSoft
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = "No catches yet — head to the dock!"
			empty.Parent = list
			return
		end
		for i, item in ipairs(items_) do buildCard(item, i) end
	end
	refresh(items)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

return InventoryUI
