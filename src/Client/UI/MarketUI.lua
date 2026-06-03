--!strict
-- MarketUI.lua
-- Browse global listings; buy with confirm tap. Demand spike banner at top.
-- Layout from StarterGuiAssets.MarketUI_Template; behavior wiring only.
--
-- MarketService.Client signals (wired in MarketController):
--   ListingsUpdated(listings) — periodic + post-trade broadcast
--   DemandRotated(speciesId, multiplier) — daily demand spike rotation
-- onBuy(listingId) -> MarketService:Buy(listingId)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIKit = require(script.Parent.UIKit)
local UIUtil = require(script.Parent.UIUtil)
local FishCatalogRaw = require(ReplicatedStorage.Shared.Config.FishCatalog)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)

local P = UIUtil.Palette
local M = UIUtil.Modal

local MarketUI = {}

export type MarketHandle = {
	gui: ScreenGui,
	close: () -> (),
	refresh: (listings: {any}, demand: any) -> (),
}

local _fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalogRaw.fish) do
	_fishById[f.id] = f
end

local BUY_CONFIRM_W = 168
local BUY_CONFIRM_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function requireChild(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(`[MarketUI] Missing {className} "{name}" under {parent:GetFullName()}`, 2)
	end
	return child
end

local function titleCase(s: string): string
	return (s:gsub("_", " "):gsub("(%a)([%w]*)", function(a: string, b: string)
		return a:upper() .. b
	end))
end

local function listingSearchText(listing: any): string
	local parts: {string} = { listing.sellerName or "" }
	if listing.itemKind == "Fish" then
		table.insert(parts, listing.speciesId or "")
	elseif listing.goodId then
		table.insert(parts, listing.goodId)
	end
	return table.concat(parts, " "):lower()
end

function MarketUI.show(initialListings: {any}, initialDemand: any, initialPriceHistory: {[string]: {{price: number, ts: number}}}, onBuy: (string) -> ()): MarketHandle
	local reducedMotion = MotionUtil.reducedMotionEnabled()
	local searchQuery = ""
	local allListings: {any} = initialListings
	local lastDemand: any = initialDemand
	local priceHistory: {[string]: {{price: number, ts: number}}} = initialPriceHistory or {}

	local gui = TemplateLoader.spawn("Market", { instanceName = "MarketUI" })
	local backdrop = requireChild(gui, "Backdrop", "TextButton") :: TextButton
	local panel = requireChild(gui, "Panel", "Frame") :: Frame
	local closeBtn = requireChild(requireChild(panel, "Header", "Frame"), "Close", "TextButton") :: TextButton
	local body = requireChild(panel, "Body", "Frame") :: Frame

	local demandLbl = requireChild(requireChild(body, "DemandBanner", "Frame"), "DemandLabel", "TextLabel") :: TextLabel
	local searchBox = requireChild(requireChild(body, "SearchRow", "Frame"), "SearchBox", "TextBox") :: TextBox
	local listingScroll = requireChild(body, "ListingScroll", "ScrollingFrame") :: ScrollingFrame
	local rowTpl = requireChild(body, "ListingRow_Template", "Frame")

	local fadeDuration = M.FadeDuration
	local slideOffsetPx = M.SlideOffsetPx
	local meta = gui:FindFirstChild("Meta")
	if meta and meta:IsA("Folder") then
		local fadeVal = meta:FindFirstChild("FadeDuration")
		if fadeVal and fadeVal:IsA("NumberValue") then
			fadeDuration = fadeVal.Value
		end
		local slideVal = meta:FindFirstChild("SlideOffsetPx")
		if slideVal and slideVal:IsA("NumberValue") then
			slideOffsetPx = slideVal.Value
		end
	end

	local closed = false
	local restPos = panel.Position
	local fromPos = UDim2.new(
		restPos.X.Scale, restPos.X.Offset,
		restPos.Y.Scale, restPos.Y.Offset + slideOffsetPx
	)
	local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function destroy()
		if closed then
			return
		end
		closed = true
		if gui.Parent then
			gui:Destroy()
		end
	end

	local function clearRows()
		for _, c in ipairs(listingScroll:GetChildren()) do
			if c:IsA("Frame") and c ~= rowTpl then
				c:Destroy()
			end
		end
	end

	local function buildRow(listing: any, i: number)
		local row = rowTpl:Clone()
		row.Name = "Row_" .. (listing.listingId or i)
		row.Visible = true
		row.LayoutOrder = i
		row.Parent = listingScroll

		local speciesId = listing.speciesId
		local fishData = speciesId and _fishById[speciesId] or nil
		local rarity = (fishData and fishData.rarity) or "Common"
		local rCol = UIUtil.rarityColor(rarity)

		local fishNameLbl = requireChild(row, "FishName", "TextLabel") :: TextLabel
		local sellerLbl = requireChild(row, "SellerLabel", "TextLabel") :: TextLabel
		local priceLbl = requireChild(row, "PriceLabel", "TextLabel") :: TextLabel
		local rarityChip = requireChild(row, "RarityChip", "Frame") :: Frame
		local rarityLbl = requireChild(rarityChip, "RarityLabel", "TextLabel") :: TextLabel
		local thumb = requireChild(row, "FishThumb", "ViewportFrame") :: ViewportFrame

		if listing.itemKind == "Fish" then
			fishNameLbl.Text = ("%s · %.1f kg"):format(titleCase(listing.speciesId or "fish"), listing.weightKg or 0)
			rarityChip.Visible = true
			rarityChip.BackgroundColor3 = rCol
			rarityLbl.Text = rarity:upper()
			thumb.Visible = true
			UIKit.attachFishThumb(thumb, listing.speciesId or "", {
				modifiers = listing.modifiers or {},
				scaleTarget = 1.8,
			})
		else
			fishNameLbl.Text = ("%s · × %d"):format(titleCase(listing.goodId or "Item"), listing.count or 1)
			rarityChip.Visible = false
			thumb.Visible = false
		end

		sellerLbl.Text = "by " .. (listing.sellerName or "Unknown")
		priceLbl.Text = ("%d coins"):format(listing.price or 0)

		local buyBtn = requireChild(row, "BuyButton", "TextButton") :: TextButton
		local buyConfirm = requireChild(row, "BuyConfirm", "Frame")
		local confirmBtn = requireChild(buyConfirm, "ConfirmBtn", "TextButton") :: TextButton
		local cancelBtn = requireChild(buyConfirm, "CancelBtn", "TextButton") :: TextButton
		local confirming = false

		local function hideBuyConfirm()
			confirming = false
			if MotionUtil.reducedMotionEnabled() then
				buyConfirm.Visible = false
				buyConfirm.Size = UDim2.fromOffset(0, UIUtil.MinTouchPx)
				buyBtn.Visible = true
			else
				MotionUtil.tween(buyConfirm, BUY_CONFIRM_TWEEN, { Size = UDim2.fromOffset(0, UIUtil.MinTouchPx) })
				task.delay(BUY_CONFIRM_TWEEN.Time, function()
					if buyConfirm.Parent then
						buyConfirm.Visible = false
						buyBtn.Visible = true
					end
				end)
			end
		end

		local function showBuyConfirmBar()
			if confirming then
				return
			end
			confirming = true
			buyBtn.Visible = false
			buyConfirm.Visible = true
			if MotionUtil.reducedMotionEnabled() then
				buyConfirm.Size = UDim2.fromOffset(BUY_CONFIRM_W, UIUtil.MinTouchPx)
			else
				buyConfirm.Size = UDim2.fromOffset(0, UIUtil.MinTouchPx)
				MotionUtil.tween(buyConfirm, BUY_CONFIRM_TWEEN, {
					Size = UDim2.fromOffset(BUY_CONFIRM_W, UIUtil.MinTouchPx),
				})
			end
		end

		buyBtn.Activated:Connect(showBuyConfirmBar)
		confirmBtn.Activated:Connect(function()
			if not confirming then
				return
			end
			hideBuyConfirm()
			onBuy(listing.listingId)
		end)
		cancelBtn.Activated:Connect(function()
			if not confirming then
				return
			end
			hideBuyConfirm()
		end)

		-- Sparkline: render recent price history if available.
		if listing.itemKind == "Fish" and speciesId then
			local samples = priceHistory[speciesId:lower()]
			if samples and #samples >= 2 then
				local sparklineSlot = row:FindFirstChild("SparklineSlot")
				if sparklineSlot and sparklineSlot:IsA("Frame") then
					local sparkW = M.SparklineWidth or 72
					local sparkH = M.SparklineHeight or 18
					sparklineSlot.Size = UDim2.new(0, sparkW, 0, sparkH)
					sparklineSlot.Visible = true

					local maxPrice = 0
					local minPrice = math.huge
					for _, s in ipairs(samples) do
						if s.price > maxPrice then maxPrice = s.price end
						if s.price < minPrice then minPrice = s.price end
					end
					local range = math.max(maxPrice - minPrice, 1)

					local barCount = math.min(#samples, 12)
					local barW = math.floor(sparkW / barCount) - 1
					for j = #samples - barCount + 1, #samples do
						local s = samples[j]
						local frac = math.clamp((s.price - minPrice) / range, 0.05, 1)
						local barH = math.max(2, math.floor(frac * sparkH))

						local bar = Instance.new("Frame")
						bar.Name = "SparkBar_" .. j
						bar.BorderSizePixel = 0
						bar.BackgroundColor3 = P.Sunset
						bar.AnchorPoint = Vector2.new(0, 1)
						bar.Size = UDim2.new(0, barW, 0, barH)
						bar.Position = UDim2.new(0, (j - (#samples - barCount + 1)) * (barW + 1), 1, 0)
						bar.Parent = sparklineSlot
					end
				end
			end
		end
	end

	local function filterListings(listings_: {any}): {any}
		if searchQuery == "" then
			return listings_
		end
		local q = searchQuery:lower()
		local out: {any} = {}
		for _, listing in ipairs(listings_) do
			if string.find(listingSearchText(listing), q, 1, true) then
				table.insert(out, listing)
			end
		end
		return out
	end

	local function refresh(listings_: {any}, demand_: any)
		allListings = listings_
		if demand_ ~= nil then
			lastDemand = demand_
		end

		if lastDemand and lastDemand.speciesId then
			demandLbl.Text = ("Demand spike: %s pays × %.1f today"):format(
				titleCase(lastDemand.speciesId),
				lastDemand.multiplier or 1
			)
		else
			demandLbl.Text = "No demand spike right now."
		end

		clearRows()
		local visible = filterListings(listings_)
		if #visible == 0 then
			local msg = if #listings_ == 0
				then "Market is empty — be the first to list a catch."
				else "No listings match your search."
			UIUtil.makeLabel(msg, "subtitle", {
				Size = UDim2.new(1, 0, 0, 60),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = P.CreamSoft,
				LayoutOrder = 1,
				Parent = listingScroll,
			})
			return
		end
		for i, listing in ipairs(visible) do
			buildRow(listing, i)
		end
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		searchQuery = searchBox.Text
		refresh(allListings, lastDemand)
	end)

	local function requestClose()
		destroy()
	end

	backdrop.Activated:Connect(requestClose)
	closeBtn.Activated:Connect(requestClose)

	panel.BackgroundTransparency = 1
	backdrop.BackgroundTransparency = 1
	if reducedMotion then
		panel.Position = restPos
		panel.BackgroundTransparency = 0
		backdrop.BackgroundTransparency = M.BackdropAlpha
	else
		panel.Position = fromPos
		MotionUtil.tweenOrSnap(backdrop, fadeInfo, { BackgroundTransparency = M.BackdropAlpha })
		MotionUtil.tweenOrSnap(panel, fadeInfo, { BackgroundTransparency = 0, Position = restPos })
	end

	refresh(initialListings, initialDemand)

	return {
		gui = gui,
		close = requestClose,
		refresh = refresh,
	}
end

-- Small modal to choose a listing price. Still uses runtime modal shell (sell flow).
function MarketUI.showSellPrompt(suggestedPrice: number, onConfirm: (number) -> (), onCancel: () -> ())
	local shell
	shell = UIUtil.makeModalShell({
		name = "MarketSellPrompt",
		title = "List on the global market",
		onClose = function()
			if shell then
				shell.destroy()
			end
			onCancel()
		end,
		width = 440,
		heightScale = 0.32,
	})

	local body = shell.body
	local TYPE = UIUtil.Typography

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
	local ic = Instance.new("UICorner")
	ic.CornerRadius = UDim.new(0, UIUtil.Radii.md)
	ic.Parent = input
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
