--!strict
-- MarketUI.lua
-- Browse global listings; tap to buy. The current demand spike (species +
-- multiplier) is shown as a banner so players know which catch to chase today.

local UIUtil = require(script.Parent.UIUtil)

local MarketUI = {}

export type MarketHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (listings: {any}, demand: {speciesId: string?, multiplier: number, expiresAt: number}) -> (),
}

function MarketUI.show(initialListings: {any}, initialDemand: any, onBuy: (string) -> ()): MarketHandle
	local gui = UIUtil.makeScreenGui("MarketUI")

	local backdrop = UIUtil.makeFrame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
	})
	backdrop.Parent = gui

	local panel = UIUtil.makePanel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.88, 0),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local panelMax = Instance.new("UISizeConstraint"); panelMax.MaxSize = Vector2.new(820, 760); panelMax.Parent = panel
	panel.Parent = gui

	local title = UIUtil.makeLabel("Global Market", "title", {
		Position = UDim2.new(0, 16, 0, 12),
		Size = UDim2.new(1, -100, 0, 28),
	})
	title.Parent = panel
	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(80, 32),
		BackgroundColor3 = UIUtil.Palette.Wood,
	})
	closeBtn.Parent = panel

	-- Demand spike banner: nothing to display until refresh runs, but we
	-- create the slot so refresh can update text in place.
	local demandBanner = UIUtil.makePanel({
		Name = "Demand",
		Position = UDim2.new(0, 12, 0, 56),
		Size = UDim2.new(1, -24, 0, 36),
		BackgroundColor3 = UIUtil.Palette.SunsetDeep,
	})
	demandBanner.Parent = panel
	local demandLbl = UIUtil.makeLabel("Loading demand...", "body", {
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -24, 1, 0),
	})
	demandLbl.Parent = demandBanner

	-- Scrolling list of listings.
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 12, 0, 100)
	list.Size = UDim2.new(1, -24, 1, -112)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local function buildRow(listing: any, i: number)
		local row = UIUtil.makePanel({
			Name = listing.listingId,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = UIUtil.Palette.Teal,
			LayoutOrder = i,
		})
		row.Parent = list

		local nameText: string
		if listing.itemKind == "Fish" then
			nameText = (listing.speciesId :: string):gsub("_", " ") .. (" • %.1f kg"):format(listing.weightKg or 0)
		else
			nameText = (listing.goodId or "Item"):gsub("_", " ") .. (" • x%d"):format(listing.count or 1)
		end
		local nameLbl = UIUtil.makeLabel(nameText, "body", {
			Position = UDim2.new(0, 12, 0, 6),
			Size = UDim2.new(0.6, 0, 0, 22),
		})
		nameLbl.Parent = row
		local sellerLbl = UIUtil.makeLabel("by " .. listing.sellerName, "caption", {
			Position = UDim2.new(0, 12, 0, 28),
			Size = UDim2.new(0.6, 0, 0, 16),
		})
		sellerLbl.Parent = row

		local priceLbl = UIUtil.makeLabel(("%d coins"):format(listing.price), "title", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -110, 0.5, 0),
			Size = UDim2.fromOffset(120, 28),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = UIUtil.Palette.Gold,
		})
		priceLbl.Parent = row

		local buyBtn = UIUtil.makeButton("Buy", function() onBuy(listing.listingId) end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(96, 40),
		})
		buyBtn.Parent = row
	end

	local function refresh(listings_: {any}, demand: any)
		-- Update banner.
		if demand and demand.speciesId then
			demandLbl.Text = ("Demand spike! %s pays x%.1f today"):format((demand.speciesId :: string):gsub("_", " "), demand.multiplier)
		else
			demandLbl.Text = "No demand spike right now."
		end

		-- Wipe + rebuild listing rows. For our scale (≲ a few hundred listings)
		-- a full rebuild is cheaper than reconciling diffs.
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		if #listings_ == 0 then
			local empty = UIUtil.makeLabel("Market is empty. Be the first to list a catch!", "body", {
				Size = UDim2.new(1, 0, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			empty.Parent = list
		else
			for i, l in ipairs(listings_) do buildRow(l, i) end
		end
	end
	refresh(initialListings, initialDemand)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

-- Standalone "create listing" prompt — small modal for the seller to enter
-- a price.
function MarketUI.showSellPrompt(suggestedPrice: number, onConfirm: (number) -> (), onCancel: () -> ())
	local gui = UIUtil.makeScreenGui("MarketSellPrompt")
	local backdrop = UIUtil.makeFrame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
	})
	backdrop.Parent = gui
	local panel = UIUtil.makePanel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.7, 0, 0, 220),
		BackgroundColor3 = UIUtil.Palette.TealDark,
	})
	local panelMax = Instance.new("UISizeConstraint"); panelMax.MaxSize = Vector2.new(440, 220); panelMax.Parent = panel
	panel.Parent = gui

	local title = UIUtil.makeLabel("List for sale", "title", {
		Position = UDim2.new(0, 16, 0, 14),
		Size = UDim2.new(1, -32, 0, 28),
	})
	title.Parent = panel

	local input = Instance.new("TextBox")
	input.PlaceholderText = "Price in coins"
	input.Text = tostring(suggestedPrice)
	input.Font = Enum.Font.GothamMedium
	input.TextSize = 18
	input.TextColor3 = UIUtil.Palette.Cream
	input.BackgroundColor3 = UIUtil.Palette.Teal
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Position = UDim2.new(0, 16, 0, 60)
	input.Size = UDim2.new(1, -32, 0, 44)
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 6); ic.Parent = input
	input.Parent = panel

	local cancel = UIUtil.makeButton("Cancel", function() gui:Destroy(); onCancel() end, {
		Position = UDim2.new(0, 16, 1, -60),
		Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = UIUtil.Palette.Wood,
	})
	cancel.Parent = panel
	local confirm = UIUtil.makeButton("Confirm", function()
		local n = tonumber(input.Text) or suggestedPrice
		gui:Destroy()
		onConfirm(math.floor(n))
	end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 1, -60),
		Size = UDim2.fromOffset(140, 44),
	})
	confirm.Parent = panel
end

return MarketUI
