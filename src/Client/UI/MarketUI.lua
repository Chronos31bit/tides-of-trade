--!strict
-- MarketUI.lua
-- Browse global listings; buy with one tap. Demand spike banner shows
-- which species pays a premium today. Uses the shared modal shell so
-- the chrome (backdrop / panel / header / close) matches every other
-- modal in the game.

local UIUtil = require(script.Parent.UIUtil)

local P    = UIUtil.Palette
local SP   = UIUtil.Spacing
local RAD  = UIUtil.Radii
local TYPE = UIUtil.Typography

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
	local shell
	shell = UIUtil.makeModalShell({
		name = "MarketUI",
		title = "Global Market",
		onClose = function() if shell then shell.destroy() end end,
		width = 700,
		heightScale = 0.88,
	})
	local gui  = shell.gui
	local body = shell.body

	-- Demand banner at the top of the body.
	local demand = Instance.new("Frame")
	demand.Size = UDim2.new(1, 0, 0, 44)
	demand.BackgroundColor3 = P.SunsetDeep
	demand.BorderSizePixel = 0
	local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, RAD.md); dc.Parent = demand
	demand.Parent = body

	local dDot = Instance.new("Frame")
	dDot.BackgroundColor3 = P.Sunset
	dDot.BorderSizePixel = 0
	dDot.AnchorPoint = Vector2.new(0, 0.5)
	dDot.Position = UDim2.new(0, SP.md, 0.5, 0)
	dDot.Size = UDim2.fromOffset(10, 10)
	local ddcr = Instance.new("UICorner"); ddcr.CornerRadius = UDim.new(1, 0); ddcr.Parent = dDot
	dDot.Parent = demand

	local demandLbl = UIUtil.makeLabel("Loading demand…", "body", {
		Position = UDim2.new(0, SP.xl + 6, 0, 0),
		Size = UDim2.new(1, -(SP.xl + 6 + SP.md), 1, 0),
		Font = Enum.Font.GothamBold,
		Parent = demand,
	})

	-- Listings scroll fills the remainder of the body.
	local listTop = 44 + SP.md
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, listTop)
	list.Size = UDim2.new(1, 0, 1, -listTop)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, SP.sm)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function buildRow(listing: any, i: number)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = P.Teal
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, RAD.md); rc.Parent = row
		row.Parent = list

		local nameText: string
		if listing.itemKind == "Fish" then
			nameText = ("%s · %.1f kg"):format(titleCase(listing.speciesId or "fish"), listing.weightKg or 0)
		else
			nameText = ("%s · × %d"):format(titleCase(listing.goodId or "Item"), listing.count or 1)
		end

		UIUtil.makeLabel(nameText, "subtitle", {
			Position = UDim2.new(0, SP.md, 0, SP.sm),
			Size = UDim2.new(0.55, 0, 0, 22),
			Font = Enum.Font.GothamBold,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		UIUtil.makeLabel("by " .. listing.sellerName, "caption", {
			Position = UDim2.new(0, SP.md, 0, 30),
			Size = UDim2.new(0.55, 0, 0, 18),
			Parent = row,
		})

		UIUtil.makeLabel(("%d coins"):format(listing.price), "body", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -120, 0.5, 0),
			Size = UDim2.fromOffset(120, 26),
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			TextColor3 = P.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})

		-- Reserved slot for the future price-history sparkline. Empty for
		-- now (zero-height); MarketController v2 can mount a graph here
		-- without restructuring the row.
		local sparkline = Instance.new("Frame")
		sparkline.Name = "SparklineSlot"
		sparkline.BackgroundTransparency = 1
		sparkline.AnchorPoint = Vector2.new(1, 1)
		sparkline.Position = UDim2.new(1, -110, 1, -4)
		sparkline.Size = UDim2.fromOffset(96, 0)
		sparkline.Parent = row

		local buyBtn = UIUtil.makePrimaryButton("Buy", function() onBuy(listing.listingId) end, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -SP.sm, 0.5, 0),
			Size = UDim2.fromOffset(96, UIUtil.MinTouchPx),
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
			UIUtil.makeLabel("Market is empty — be the first to list a catch.", "subtitle", {
				Size = UDim2.new(1, 0, 0, 60),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = list,
			})
			return
		end
		for i, l in ipairs(listings_) do buildRow(l, i) end
	end
	refresh(initialListings, initialDemand)

	return {
		gui = gui,
		close = function() shell.destroy() end,
		refresh = refresh,
	}
end

-- Small modal to choose a listing price. Reuses the shared shell so it
-- matches the rest of the chrome.
function MarketUI.showSellPrompt(suggestedPrice: number, onConfirm: (number) -> (), onCancel: () -> ())
	local shell
	shell = UIUtil.makeModalShell({
		name = "MarketSellPrompt",
		title = "List on the global market",
		onClose = function()
			if shell then shell.destroy() end
			onCancel()
		end,
		width = 440,
		heightScale = 0.32,
	})

	local body = shell.body

	local input = Instance.new("TextBox")
	input.PlaceholderText = "Price in coins"
	input.Text = tostring(suggestedPrice)
	input.Font = TYPE.body.font
	input.TextSize = math.max(18, UIUtil.MinFontPx)
	input.TextColor3 = P.Cream
	input.PlaceholderColor3 = P.CreamSoft
	input.BackgroundColor3 = P.Teal
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Position = UDim2.new(0, 0, 0, 0)
	input.Size = UDim2.new(1, 0, 0, 48)
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, RAD.md); ic.Parent = input
	input.Parent = body

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.AnchorPoint = Vector2.new(0, 1)
	btnRow.Position = UDim2.new(0, 0, 1, 0)
	btnRow.Size = UDim2.new(1, 0, 0, UIUtil.MinTouchPx)
	btnRow.Parent = body

	local cancel = UIUtil.makeGhostButton("Cancel", function()
		shell.destroy()
		onCancel()
	end, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(120, UIUtil.MinTouchPx),
	})
	cancel.Parent = btnRow

	local confirm = UIUtil.makePrimaryButton("Confirm", function()
		local n = tonumber(input.Text) or suggestedPrice
		shell.destroy()
		onConfirm(math.floor(n))
	end, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(140, UIUtil.MinTouchPx),
	})
	confirm.Parent = btnRow
end

return MarketUI
