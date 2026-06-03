--!strict
-- CosmeticShopUI.lua
-- Client-side cosmetic shop modal. Lists purchasable cosmetics with name,
-- slot, and description; marks owned items; prompts native Roblox purchase
-- for unowned items via MarketplaceService:PromptProductPurchase.
--
-- Public API:
--   CosmeticShopUI.show(opts) -> ShopHandle
--     opts = {
--       products    : { {productId: number, cosmeticId: string, price: number} },
--       owned       : {[string]: boolean},  -- owned cosmetic ids
--       onClose     : (() -> ())?,
--     }
--   handle.close()

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local UIUtil            = require(script.Parent.UIUtil)
local CosmeticsCatalog  = require(game:GetService("ReplicatedStorage").Shared.Config.CosmeticsCatalog)

local P = UIUtil.Palette

local CosmeticShopUI = {}

export type ShopProduct = {
	productId: number,
	cosmeticId: string,
	price: number,
}

export type ShopShowOpts = {
	products: { ShopProduct },
	owned:    {[string]: boolean},
	onClose:  (() -> ())?,
}

export type ShopHandle = {
	gui:   ScreenGui,
	close: () -> (),
}

-- Slot emoji for visual distinction.
local SLOT_ICON: {[string]: string} = {
	hat   = "🎩",
	coat  = "🧥",
	boots = "👢",
}

function CosmeticShopUI.show(opts: ShopShowOpts): ShopHandle
	local products = opts.products
	local owned = opts.owned
	local onClose = opts.onClose

	local shell = UIUtil.makeModalShell({
		name = "CosmeticShopUI",
		title = "Cosmetic Shop",
		onClose = onClose,
		bodyPadding = UIUtil.Spacing.sm,
	})

	local body = shell.body

	-- ---- PRODUCT LIST ----
	local list = Instance.new("ScrollingFrame")
	list.Name = "ProductList"
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

	for i, product in ipairs(products) do
		local cosmeticId = product.cosmeticId
		local def = CosmeticsCatalog.byId[cosmeticId]
		local isOwned = owned[cosmeticId] == true

		local row = Instance.new("Frame")
		row.Name = "Product_" .. cosmeticId
		row.BackgroundColor3 = P.Teal
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, UIUtil.MinTouchPx + 16)
		row.LayoutOrder = i
		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, UIUtil.Radii.md)
		rowCorner.Parent = row
		row.Parent = list

		-- Slot icon (left edge).
		local slotIcon = SLOT_ICON[def and def.slot or "hat"] or "👤"
		local iconLabel = UIUtil.makeLabel(slotIcon, "title", {
			Position = UDim2.new(0, UIUtil.Spacing.sm, 0, 0),
			Size = UDim2.new(0, UIUtil.MinTouchPx, 0, UIUtil.MinTouchPx),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		iconLabel.Parent = row

		-- Name + description (left side).
		local infoX = UIUtil.MinTouchPx + UIUtil.Spacing.sm * 2
		local nameText = def and def.displayName or cosmeticId
		if isOwned then
			nameText ..= "  (Owned)"
		end

		local nameLabel = UIUtil.makeLabel(nameText, "body", {
			Position = UDim2.new(0, infoX, 0, UIUtil.Spacing.xs),
			Size = UDim2.new(1, -(infoX + 100), 0, 20),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if isOwned then P.SunsetSoft else P.Cream,
		})
		nameLabel.Parent = row

		if def then
			local descLabel = UIUtil.makeLabel(def.description or "", "caption", {
				Position = UDim2.new(0, infoX, 0, 24),
				Size = UDim2.new(1, -(infoX + 100), 0, UIUtil.MinTouchPx - 28),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = P.CreamSoft,
			})
			descLabel.Parent = row
		end

		-- Purchase button / Owned badge (right side).
		if isOwned then
			local ownedLabel = UIUtil.makeLabel("Owned ✓", "caption", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(UIUtil.Spacing.sm), 0.5, 0),
				Size = UDim2.new(0, 80, 0, UIUtil.MinTouchPx - 8),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = P.Sunset,
			})
			ownedLabel.Parent = row
		else
			local buyBtn = UIUtil.makePrimaryButton(
				("R$ %d"):format(product.price),
				function()
					MarketplaceService:PromptProductPurchase(
						Players.LocalPlayer,
						product.productId
					)
				end, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -(UIUtil.Spacing.sm), 0.5, 0),
					Size = UDim2.new(0, 76, 0, UIUtil.MinTouchPx - 8),
				}
			)
			buyBtn.Name = "BuyBtn_" .. cosmeticId
			buyBtn.Parent = row
		end
	end

	-- Empty state.
	if #products == 0 then
		local emptyLabel = UIUtil.makeLabel(
			"Coming soon — check back for new cosmetics!",
			"body", {
				Size = UDim2.new(1, 0, 0, UIUtil.MinTouchPx * 2),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = list,
			}
		)
		emptyLabel.Parent = list
	end

	local closed = false
	local function close()
		if closed then return end
		closed = true
		shell.close()
	end

	return {
		gui   = shell.gui,
		close = close,
	}
end

return CosmeticShopUI
