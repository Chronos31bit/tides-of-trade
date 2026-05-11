--!strict
-- MarketUI.lua (rewrite)
-- Browse global listings; buy with one tap. Demand spike banner shows
-- which species pays a premium today.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local MarketUI = {}

export type MarketHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (listings: {any}, demand: any) -> (),
}

local function titleCase(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function MarketUI.show(initialListings: {any}, initialDemand: any, onBuy: (string) -> ()): MarketHandle
	local gui = UIUtil.makeScreenGui("MarketUI")

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.92, 0, 0.88, 0)
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = P.TealDeeper; ps.Thickness = 1.5; ps.Transparency = 0.25; ps.Parent = panel
	local pcap = Instance.new("UISizeConstraint"); pcap.MaxSize = Vector2.new(900, 760); pcap.Parent = panel
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 20, 0, 14)
	title.Size = UDim2.new(1, -120, 0, 30)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = P.Cream
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Global Market"
	title.Parent = panel

	local closeBtn = UIUtil.makeButton("Close", function() gui:Destroy() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(84, 36),
		BackgroundColor3 = P.Wood,
	})
	closeBtn.Parent = panel

	-- Demand banner.
	local demand = Instance.new("Frame")
	demand.Position = UDim2.new(0, 14, 0, 60)
	demand.Size = UDim2.new(1, -28, 0, 42)
	demand.BackgroundColor3 = P.SunsetDeep
	demand.BorderSizePixel = 0
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, 10); dc.Parent = demand
	demand.Parent = panel

	local dDot = Instance.new("Frame")
	dDot.BackgroundColor3 = P.Sunset
	dDot.BorderSizePixel = 0
	dDot.AnchorPoint = Vector2.new(0, 0.5)
	dDot.Position = UDim2.new(0, 12, 0.5, 0)
	dDot.Size = UDim2.fromOffset(10, 10)
	local ddcr = Instance.new("UICorner"); ddcr.CornerRadius = UDim.new(1, 0); ddcr.Parent = dDot
	dDot.Parent = demand

	local demandLbl = Instance.new("TextLabel")
	demandLbl.BackgroundTransparency = 1
	demandLbl.Position = UDim2.new(0, 30, 0, 0)
	demandLbl.Size = UDim2.new(1, -42, 1, 0)
	demandLbl.Font = Enum.Font.GothamBold
	demandLbl.TextSize = 14
	demandLbl.TextColor3 = P.Cream
	demandLbl.TextXAlignment = Enum.TextXAlignment.Left
	demandLbl.Text = "Loading demand…"
	demandLbl.Parent = demand

	-- Listings.
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 14, 0, 116)
	list.Size = UDim2.new(1, -28, 1, -130)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function buildRow(listing: any, i: number)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = P.Teal
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 10); rc.Parent = row
		row.Parent = list

		local nameText: string
		if listing.itemKind == "Fish" then
			nameText = ("%s · %.1f kg"):format(titleCase(listing.speciesId or "fish"), listing.weightKg or 0)
		else
			nameText = ("%s · × %d"):format(titleCase(listing.goodId or "Item"), listing.count or 1)
		end

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 16, 0, 8)
		name.Size = UDim2.new(0.55, 0, 0, 22)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 16
		name.TextColor3 = P.Cream
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = nameText
		name.Parent = row

		local seller = Instance.new("TextLabel")
		seller.BackgroundTransparency = 1
		seller.Position = UDim2.new(0, 16, 0, 30)
		seller.Size = UDim2.new(0.55, 0, 0, 18)
		seller.Font = Enum.Font.Gotham
		seller.TextSize = 12
		seller.TextColor3 = P.CreamSoft
		seller.TextXAlignment = Enum.TextXAlignment.Left
		seller.Text = "by " .. listing.sellerName
		seller.Parent = row

		local price = Instance.new("TextLabel")
		price.BackgroundTransparency = 1
		price.AnchorPoint = Vector2.new(1, 0.5)
		price.Position = UDim2.new(1, -120, 0.5, 0)
		price.Size = UDim2.fromOffset(120, 26)
		price.Font = Enum.Font.GothamBold
		price.TextSize = 18
		price.TextColor3 = P.Gold
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.Text = ("%d coins"):format(listing.price)
		price.Parent = row

		local buyBtn = UIUtil.makeButton("Buy", function() onBuy(listing.listingId) end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(96, 40),
			BackgroundColor3 = P.Sunset,
		})
		buyBtn.Parent = row
	end

	local function refresh(listings_: {any}, demand_: any)
		if demand_ and demand_.speciesId then
			demandLbl.Text = ("Demand spike: %s pays × %.1f today"):format(titleCase(demand_.speciesId), demand_.multiplier)
		else
			demandLbl.Text = "No demand spike right now."
		end

		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		if #listings_ == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Size = UDim2.new(1, 0, 0, 60)
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 16
			empty.TextColor3 = P.CreamSoft
			empty.TextXAlignment = Enum.TextXAlignment.Center
			empty.Text = "Market is empty — be the first to list a catch."
			empty.Parent = list
			return
		end
		for i, l in ipairs(listings_) do buildRow(l, i) end
	end
	refresh(initialListings, initialDemand)

	return {
		gui = gui,
		close = function() gui:Destroy() end,
		refresh = refresh,
	}
end

-- Small modal to choose a listing price. Solid, opaque, clean.
function MarketUI.showSellPrompt(suggestedPrice: number, onConfirm: (number) -> (), onCancel: () -> ())
	local gui = UIUtil.makeScreenGui("MarketSellPrompt")

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.55
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.7, 0, 0, 220)
	panel.BackgroundColor3 = P.TealDark
	panel.BorderSizePixel = 0
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = P.TealDeeper; ps.Thickness = 1.5; ps.Transparency = 0.25; ps.Parent = panel
	local pcap = Instance.new("UISizeConstraint"); pcap.MaxSize = Vector2.new(440, 220); pcap.Parent = panel
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 18, 0, 16)
	title.Size = UDim2.new(1, -36, 0, 26)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = P.Cream
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "List on the global market"
	title.Parent = panel

	local input = Instance.new("TextBox")
	input.PlaceholderText = "Price in coins"
	input.Text = tostring(suggestedPrice)
	input.Font = Enum.Font.GothamMedium
	input.TextSize = 18
	input.TextColor3 = P.Cream
	input.PlaceholderColor3 = P.CreamSoft
	input.BackgroundColor3 = P.Teal
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Position = UDim2.new(0, 18, 0, 56)
	input.Size = UDim2.new(1, -36, 0, 48)
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 8); ic.Parent = input
	input.Parent = panel

	local cancel = UIUtil.makeButton("Cancel", function() gui:Destroy(); onCancel() end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(120, 44),
		BackgroundColor3 = P.Wood,
	})
	cancel.Parent = panel

	local confirm = UIUtil.makeButton("Confirm", function()
		local n = tonumber(input.Text) or suggestedPrice
		gui:Destroy()
		onConfirm(math.floor(n))
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(140, 44),
		BackgroundColor3 = P.Sunset,
	})
	confirm.Parent = panel
end

return MarketUI
