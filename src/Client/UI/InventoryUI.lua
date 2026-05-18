--!strict
-- InventoryUI.lua (rewrite)
-- Modal grid of inventory cards. Each card has a rarity stripe down the
-- left edge, name + weight, and two action buttons: Sell (instant dock NPC)
-- and List (open market price prompt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIUtil         = require(script.Parent.UIUtil)
local FishCatalogRaw = require(ReplicatedStorage.Shared.Config.FishCatalog)
local GameConfig     = require(ReplicatedStorage.Shared.Config.GameConfig)

local P = UIUtil.Palette

local InventoryUI = {}

export type InventoryHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (items: {any}) -> (),
}

local _fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalogRaw.fish) do _fishById[f.id] = f end

local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB( 70, 200, 110),
	Rare      = Color3.fromRGB( 60, 140, 240),
	Epic      = Color3.fromRGB(160,  80, 240),
	Legendary = Color3.fromRGB(255, 165,  30),
	Mythic    = Color3.fromRGB(220,  60,  80),
	Divine    = Color3.fromRGB(200, 220, 255),
}
local MOD_COLORS: {[string]: Color3} = {
	shiny        = Color3.fromRGB(255, 220,  60),
	giant        = Color3.fromRGB(120, 200, 120),
	glowing      = Color3.fromRGB(100, 180, 255),
	lucky        = Color3.fromRGB(200, 120, 255),
	ancient      = Color3.fromRGB(210, 140,  60),
	prismatic    = Color3.fromRGB(255, 100, 160),
	elder        = Color3.fromRGB(255, 240, 180),
	cursed       = Color3.fromRGB(120,  40, 160),
	magnetic     = Color3.fromRGB( 80, 200, 220),
	barnacled    = Color3.fromRGB(140, 180, 100),
	tide_kissed  = Color3.fromRGB( 60, 200, 220),
	storm_forged = Color3.fromRGB(180,  80, 255),
	moon_touched = Color3.fromRGB(200, 200, 255),
	dawn_blessed = Color3.fromRGB(255, 200, 120),
	fog_shrouded = Color3.fromRGB(160, 180, 200),
}
local _modDisplayNames: {[string]: string} = {}
for _, m in ipairs(GameConfig.FishModifiers) do _modDisplayNames[m.id] = m.displayName end

local function rarityColor(speciesId: string?): Color3
	local fish = speciesId and _fishById[speciesId]
	return RARITY_COLORS[(fish and fish.rarity) or "Common"] or RARITY_COLORS.Common
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
	grid.CellSize = UDim2.fromOffset(240, 116)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	local function buildCard(item: any, idx: number)
		local isFish = item.kind == "Fish"
		local card = Instance.new("Frame")
		card.BackgroundColor3 = P.Teal
		card.BorderSizePixel = 0
		card.LayoutOrder = idx
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = P.TealDeeper; cs.Thickness = 1; cs.Transparency = 0.5; cs.Parent = card
		card.Parent = list

		-- Rarity stripe on the left edge (Fish only).
		if isFish then
			local stripe = Instance.new("Frame")
			stripe.BackgroundColor3 = rarityColor(item.speciesId)
			stripe.BorderSizePixel = 0
			stripe.Size = UDim2.new(0, 6, 1, 0)
			stripe.Parent = card
		end

		local nameText: string
		if isFish then
			nameText = (item.speciesId or "fish"):gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
		else
			nameText = (item.goodId or "Item"):gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
		end
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 16, 0, 6)
		name.Size = UDim2.new(1, -100, 0, 22)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 16
		name.TextColor3 = P.Cream
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = nameText
		name.Parent = card

		-- Rarity badge pill — top-right, Fish items only.
		if isFish then
			local fishData = _fishById[item.speciesId]
			local fishRarity = (fishData and fishData.rarity) or "Common"
			local rCol = rarityColor(item.speciesId)
			local badge = Instance.new("Frame")
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, -8, 0, 6)
			badge.Size = UDim2.fromOffset(0, 18)
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.BackgroundColor3 = rCol
			badge.BackgroundTransparency = 0.70
			badge.BorderSizePixel = 0
			local bCorner = Instance.new("UICorner"); bCorner.CornerRadius = UDim.new(0, 9); bCorner.Parent = badge
			local bStroke = Instance.new("UIStroke"); bStroke.Color = rCol; bStroke.Thickness = 1; bStroke.Parent = badge
			local bPad = Instance.new("UIPadding")
			bPad.PaddingLeft  = UDim.new(0, 6)
			bPad.PaddingRight = UDim.new(0, 6)
			bPad.Parent = badge
			local badgeLbl = Instance.new("TextLabel")
			badgeLbl.BackgroundTransparency = 1
			badgeLbl.Size = UDim2.fromScale(1, 1)
			badgeLbl.Font = Enum.Font.GothamBold
			badgeLbl.TextSize = 10
			badgeLbl.TextColor3 = rCol
			badgeLbl.Text = fishRarity:upper()
			badgeLbl.Parent = badge
			badge.Parent = card
		end

		-- Modifier pill row — Fish only, below the name label.
		local subY = 28
		if isFish then
			local mods = item.modifiers or {}
			if #mods > 0 then
				local pillRow = Instance.new("Frame")
				pillRow.BackgroundTransparency = 1
				pillRow.Position = UDim2.new(0, 16, 0, 30)
				pillRow.Size = UDim2.new(1, -20, 0, 16)
				pillRow.Parent = card
				local rowLayout = Instance.new("UIListLayout")
				rowLayout.FillDirection = Enum.FillDirection.Horizontal
				rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
				rowLayout.Padding = UDim.new(0, 4)
				rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
				rowLayout.Parent = pillRow
				local maxVisible = math.min(#mods, 3)
				for i = 1, maxVisible do
					local modId = mods[i]
					local color = MOD_COLORS[modId] or Color3.fromRGB(160, 160, 160)
					local pill = Instance.new("Frame")
					pill.Size = UDim2.fromOffset(0, 16)
					pill.AutomaticSize = Enum.AutomaticSize.X
					pill.BackgroundColor3 = color
					pill.BackgroundTransparency = 0.25
					pill.BorderSizePixel = 0
					pill.LayoutOrder = i
					local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 8); pc.Parent = pill
					local pp = Instance.new("UIPadding")
					pp.PaddingLeft  = UDim.new(0, 6)
					pp.PaddingRight = UDim.new(0, 6)
					pp.Parent = pill
					local pillLbl = Instance.new("TextLabel")
					pillLbl.BackgroundTransparency = 1
					pillLbl.Size = UDim2.fromScale(1, 1)
					pillLbl.Font = Enum.Font.Gotham
					pillLbl.TextSize = 9
					pillLbl.TextColor3 = Color3.new(1, 1, 1)
					pillLbl.Text = _modDisplayNames[modId] or modId
					pillLbl.Parent = pill
					pill.Parent = pillRow
				end
				if #mods > 3 then
					local overflowLbl = Instance.new("TextLabel")
					overflowLbl.BackgroundTransparency = 1
					overflowLbl.Size = UDim2.fromOffset(24, 16)
					overflowLbl.Font = Enum.Font.Gotham
					overflowLbl.TextSize = 9
					overflowLbl.TextColor3 = P.CreamSoft
					overflowLbl.Text = "+" .. (#mods - 3)
					overflowLbl.LayoutOrder = 4
					overflowLbl.Parent = pillRow
				end
			end
			subY = 48
		end

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.new(0, 16, 0, subY)
		sub.Size = UDim2.new(1, -32, 0, 16)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 12
		sub.TextColor3 = P.CreamSoft
		sub.TextXAlignment = Enum.TextXAlignment.Left
		if isFish then
			sub.Text = ("%.1f kg"):format(item.weightKg or 0)
		else
			sub.Text = ("× %d"):format(item.count or 1)
		end
		sub.Parent = card

		-- Two action buttons in the bottom-right.
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
