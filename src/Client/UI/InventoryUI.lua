--!strict
-- InventoryUI.lua
-- Scrollable grid of inventory items. Each item card shows species/good name,
-- weight (for fish), and a "Sell on market" action that opens the listing
-- prompt. Built fresh on each open — inventory is small (≲ a few hundred
-- entries) so we don't need virtualized lists.

local UIUtil = require(script.Parent.UIUtil)

local InventoryUI = {}

export type InventoryHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (items: {any}) -> (),
}

-- onSellRequest(itemUid, suggestedPrice) — called when the user taps "List".
-- onQuickSell(itemUid) — called when the user taps "Sell" (instant dock NPC sale).
-- We pass a *suggested* price for listings computed client-side; the server validates.
function InventoryUI.show(items: {any}, onSellRequest: (string, number) -> (), onQuickSell: (string) -> (), suggestedPriceFor: (any) -> number): InventoryHandle
	local gui = UIUtil.makeScreenGui("InventoryUI")

	-- Modal backdrop — taps outside the panel close the UI on touch devices.
	local backdrop = UIUtil.makeFrame({
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
	})
	backdrop.Parent = gui

	local panel = UIUtil.makePanel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0.85, 0),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local panelMax = Instance.new("UISizeConstraint"); panelMax.MaxSize = Vector2.new(720, 720); panelMax.Parent = panel
	panel.Parent = gui

	local title = UIUtil.makeLabel("Inventory", "title", {
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -64, 0, 30),
	})
	title.Parent = panel

	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(80, 32),
		BackgroundColor3 = UIUtil.Palette.Wood,
	})
	closeBtn.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 12, 0, 56)
	list.Size = UDim2.new(1, -24, 1, -68)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local grid = Instance.new("UIGridLayout")
	-- Cards are 220x96 — fits 1 column on a 380px phone, 2 on tablet, 3 on desktop.
	-- Padding/scaling propagates from the parent UIScale.
	grid.CellSize = UDim2.fromOffset(220, 96)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	local listPad = Instance.new("UIPadding"); listPad.PaddingTop = UDim.new(0, 4); listPad.PaddingBottom = UDim.new(0, 8); listPad.Parent = list

	local function rarityColor(speciesId: string?): Color3
		if not speciesId then return UIUtil.Palette.Cream end
		-- We don't have FishCatalog wired into the UI to keep coupling minimal.
		-- Tint by hashed first byte so duplicates are visually similar even
		-- without a lookup. (For the real game, swap to catalog rarity color.)
		local b = string.byte(speciesId, 1) or 0
		local choices = { UIUtil.Palette.Common, UIUtil.Palette.Uncommon, UIUtil.Palette.Rare, UIUtil.Palette.Mythic }
		return choices[(b % 4) + 1]
	end

	local function buildCard(item: any, idx: number)
		local card = UIUtil.makePanel({
			Name = item.uid,
			BackgroundColor3 = UIUtil.Palette.Teal,
			LayoutOrder = idx,
		})
		card.Parent = list

		-- Color stripe on the left to telegraph rarity at a glance.
		local stripe = UIUtil.makeFrame({
			Name = "Stripe",
			Size = UDim2.new(0, 6, 1, 0),
			BackgroundColor3 = rarityColor(item.speciesId),
		})
		stripe.Parent = card

		local nameText = item.kind == "Fish"
			and ((item.speciesId :: string):gsub("_", " "))
			or ((item.goodId or "Item"):gsub("_", " "))
		local nameLbl = UIUtil.makeLabel(nameText, "title", {
			Position = UDim2.new(0, 16, 0, 6),
			Size = UDim2.new(1, -16, 0, 24),
			TextSize = 16,
		})
		nameLbl.Parent = card

		local subtext = ""
		if item.kind == "Fish" then
			subtext = ("%.1f kg"):format(item.weightKg or 0)
		else
			subtext = ("x%d"):format(item.count or 1)
		end
		local sub = UIUtil.makeLabel(subtext, "caption", {
			Position = UDim2.new(0, 16, 0, 28),
			Size = UDim2.new(1, -16, 0, 18),
		})
		sub.Parent = card

		-- Two actions per card. "Sell" is the instant dock NPC sale (faster,
		-- less coin). "List" puts it on the global market (more coin, has
		-- to wait for a buyer). Stacked vertically so they fit on a phone.
		local quickBtn = UIUtil.makeButton("Sell", function()
			onQuickSell(item.uid)
		end, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -96, 1, -8),
			Size = UDim2.fromOffset(80, 32),
			BackgroundColor3 = UIUtil.Palette.Wood,
		})
		quickBtn.Parent = card

		local listBtn = UIUtil.makeButton("List", function()
			onSellRequest(item.uid, suggestedPriceFor(item))
		end, {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -8, 1, -8),
			Size = UDim2.fromOffset(80, 32),
		})
		listBtn.Parent = card
	end

	local function refresh(items_: {any})
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		if #items_ == 0 then
			local empty = UIUtil.makeLabel("No catches yet — head to the dock!", "body", {
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			empty.Parent = list
		else
			for i, item in ipairs(items_) do buildCard(item, i) end
		end
	end
	refresh(items)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

return InventoryUI
