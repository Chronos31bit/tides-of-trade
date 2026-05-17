--!strict
-- BaitShopUI.lua
-- Mobile-first bait shop panel (target 380px portrait, scales up on desktop).
-- Shows every bait in BaitCatalog, the player's current stock and equipped state,
-- the price after BaitShop discount, and Buy / Equip buttons.
-- All interactivity goes through callbacks — no Knit/service calls here.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

-- Tier colours reuse the rarity palette so bait chips read consistently with
-- catch-reveal badges and the cast-meter colour coding.
local TIER_COLOUR: {[string]: Color3} = {
	Common   = P.Common,
	Uncommon = P.Uncommon,
	Rare     = P.Rare,
	Epic     = P.Gold,
}

local BaitShopUI = {}

export type BaitHandle = {
	close:        () -> (),
	refreshStash: (stash: {[string]: number}, equippedBaitId: string?) -> (),
}

export type BaitDef = {
	id: string,
	displayName: string,
	tier: string,
	rarityBoost: number,
	baseCost: number,
	maxStack: number,
}

-- ====================================================================
-- INTERNAL — build a single bait row card
-- ====================================================================
local ROW_HEIGHT = 88

local function buildRow(
	parent:       ScrollingFrame,
	bait:         BaitDef,
	count:        number,
	equipped:     boolean,
	discountPct:  number,
	layoutOrder:  number,
	onBuy:        () -> (),
	onEquip:      () -> ()
): Frame
	local discountedCost = math.max(1, math.ceil(bait.baseCost * (1 - discountPct)))

	local row = Instance.new("Frame")
	row.Name = "Row_" .. bait.id
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = equipped and P.TealLight or P.Teal
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 10); rc.Parent = row
	if equipped then
		local stroke = Instance.new("UIStroke")
		stroke.Color = P.Gold
		stroke.Thickness = 2
		stroke.Transparency = 0.1
		stroke.Parent = row
	end
	row.Parent = parent

	-- ── Tier badge (left edge) ────────────────────────────────────────
	local badge = Instance.new("Frame")
	badge.Name = "TierBadge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 10, 0.5, 0)
	badge.Size = UDim2.fromOffset(8, 48)
	badge.BackgroundColor3 = TIER_COLOUR[bait.tier] or P.Common
	badge.BorderSizePixel = 0
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0.5, 0); bc.Parent = badge
	badge.Parent = row

	-- ── Name + description ───────────────────────────────────────────
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 26, 0, 10)
	nameLabel.Size = UDim2.new(0.42, 0, 0, 22)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = P.Cream
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = bait.displayName
	nameLabel.Parent = row

	local tierLabel = Instance.new("TextLabel")
	tierLabel.BackgroundTransparency = 1
	tierLabel.Position = UDim2.new(0, 26, 0, 30)
	tierLabel.Size = UDim2.new(0.42, 0, 0, 16)
	tierLabel.Font = Enum.Font.Gotham
	tierLabel.TextSize = 12
	tierLabel.TextColor3 = TIER_COLOUR[bait.tier] or P.CreamSoft
	tierLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierLabel.Text = bait.tier
	tierLabel.Parent = row

	local boostStr = (bait.rarityBoost == 1.0) and "No rarity boost"
		or (("%.1f× rare weight"):format(bait.rarityBoost))
	local descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 26, 0, 50)
	descLabel.Size = UDim2.new(0.42, 0, 0, 28)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 11
	descLabel.TextColor3 = P.CreamSoft
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.Text = boostStr
	descLabel.Parent = row

	-- ── Stock counter ─────────────────────────────────────────────────
	local stockLabel = Instance.new("TextLabel")
	stockLabel.BackgroundTransparency = 1
	stockLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	stockLabel.Position = UDim2.new(0.53, 0, 0.5, 0)
	stockLabel.Size = UDim2.fromOffset(48, 22)
	stockLabel.Font = Enum.Font.GothamBold
	stockLabel.TextSize = 14
	stockLabel.TextColor3 = count > 0 and P.Gold or P.CreamSoft
	stockLabel.TextXAlignment = Enum.TextXAlignment.Center
	stockLabel.Text = tostring(count)
	stockLabel.Parent = row

	local stockCaption = Instance.new("TextLabel")
	stockCaption.BackgroundTransparency = 1
	stockCaption.AnchorPoint = Vector2.new(0.5, 0)
	stockCaption.Position = UDim2.new(0.53, 0, 0.5, 4)
	stockCaption.Size = UDim2.fromOffset(48, 14)
	stockCaption.Font = Enum.Font.Gotham
	stockCaption.TextSize = 10
	stockCaption.TextColor3 = P.CreamSoft
	stockCaption.TextXAlignment = Enum.TextXAlignment.Center
	stockCaption.Text = "held"
	stockCaption.Parent = row

	-- ── Price label ───────────────────────────────────────────────────
	local priceLabel = Instance.new("TextLabel")
	priceLabel.BackgroundTransparency = 1
	priceLabel.AnchorPoint = Vector2.new(1, 0.5)
	priceLabel.Position = UDim2.new(1, -126, 0.5, 0)
	priceLabel.Size = UDim2.fromOffset(70, 22)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextSize = 13
	priceLabel.TextColor3 = discountPct > 0 and P.Success or P.Gold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Text = discountedCost .. "c"
	priceLabel.Parent = row

	-- ── Equip button ──────────────────────────────────────────────────
	local equipBtn = UIUtil.makeButton(
		equipped and "Equipped" or "Equip",
		onEquip,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(86, 44),
			BackgroundColor3 = equipped and P.GoldDeep or (count > 0 and P.Wood or P.TealDark),
			variant = "secondary",
		}
	)
	if equipped then
		equipBtn.TextColor3 = P.Cream
	elseif count == 0 then
		equipBtn.TextColor3 = P.CreamSoft
	end
	equipBtn.Parent = row

	-- ── Buy button ────────────────────────────────────────────────────
	local buyBtn = UIUtil.makeButton(
		"Buy",
		onBuy,
		{
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -104, 0.5, 0),
			Size = UDim2.fromOffset(72, 44),
			BackgroundColor3 = count >= bait.maxStack and P.TealDark or P.Sunset,
			variant = "primary",
		}
	)
	if count >= bait.maxStack then
		buyBtn.TextColor3 = P.CreamSoft
	end
	buyBtn.Parent = row

	return row
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

function BaitShopUI.show(
	baits:         {BaitDef},
	initialStash:  {[string]: number},
	equippedBaitId: string?,
	discountPct:   number,
	onBuy:         (baitId: string, qty: number) -> (),
	onEquip:       (baitId: string?) -> ()
): BaitHandle
	local gui = UIUtil.makeScreenGui("BaitShopUI")

	-- Semi-transparent full-screen backdrop for tap-to-close.
	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui

	-- Main panel — max 380px wide to match the mobile-first design target.
	local panel = UIUtil.makePanel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position    = UDim2.fromScale(0.5, 0.5),
		Size        = UDim2.new(0.94, 0, 0.88, 0),
	})
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(380, 700)
	cap.Parent = panel
	panel.Parent = gui

	-- ── Header ────────────────────────────────────────────────────────
	local titleText = "Bait Shop"
	if discountPct > 0 then
		titleText = ("Bait Shop  −%d%%"):format(math.round(discountPct * 100))
	end
	local titleLabel = UIUtil.makeLabel(titleText, "title", {
		Position = UDim2.new(0, 14, 0, 12),
		Size     = UDim2.new(1, -100, 0, 28),
	})
	titleLabel.Parent = panel

	local closeBtn = UIUtil.makeButton("✕", function()
		gui:Destroy()
	end, {
		AnchorPoint      = Vector2.new(1, 0),
		Position         = UDim2.new(1, -10, 0, 10),
		Size             = UDim2.fromOffset(44, 44),
		BackgroundColor3 = P.Wood,
		variant          = "secondary",
	})
	closeBtn.Parent = panel

	if discountPct > 0 then
		local discLabel = UIUtil.makeLabel(
			("BaitShop discount active"):format(),
			"caption",
			{
				Position = UDim2.new(0, 14, 0, 38),
				Size     = UDim2.new(1, -28, 0, 14),
			}
		)
		discLabel.TextColor3 = P.Success
		discLabel.Parent = panel
	end

	local listTop = discountPct > 0 and 58 or 46

	-- ── Scrolling bait list ───────────────────────────────────────────
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 10, 0, listTop)
	list.Size = UDim2.new(1, -20, 1, -(listTop + 10))
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = P.TealDeeper
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	-- Rebuild the entire list from scratch (called on open and on stash refresh).
	local function rebuild(stash: {[string]: number}, equipped: string?)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, bait in ipairs(baits) do
			local count     = stash[bait.id] or 0
			local isEquipped = equipped == bait.id
			buildRow(
				list,
				bait,
				count,
				isEquipped,
				discountPct,
				i,
				function() onBuy(bait.id, 1) end,
				function()
					if isEquipped then
						onEquip(nil)
					else
						onEquip(bait.id)
					end
				end
			)
		end
	end

	rebuild(initialStash, equippedBaitId)

	-- Tap backdrop to close.
	backdrop.Activated:Connect(function() gui:Destroy() end)

	return {
		close = function() gui:Destroy() end,
		refreshStash = function(newStash: {[string]: number}, newEquipped: string?)
			rebuild(newStash, newEquipped)
		end,
	}
end

return BaitShopUI
