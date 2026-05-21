--!strict
-- BaitShopUI.lua
-- Mobile-first bait shop panel, max 380px wide.
-- Row layout fits Buy + Equip inside a single 380px column without overflow:
--   [tier badge] [name / tier / boost · N held] [Buy Xc] [Equip / ✓]
-- Price and stock count are baked into button labels so we need no extra columns.

local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

local TIER_COLOUR: {[string]: Color3} = {
	Common   = P.Common,
	Uncommon = P.Uncommon,
	Rare     = P.Rare,
	Epic     = P.Gold,
}

local BaitShopUI = {}

export type BaitDef = {
	id: string,
	displayName: string,
	tier: string,
	rarityBoost: number,
	baseCost: number,
	maxStack: number,
}

export type BaitHandle = {
	close:        () -> (),
	refreshStash: (stash: {[string]: number}, equippedBaitId: string?) -> (),
}

-- ====================================================================
-- ROW BUILDER
-- ====================================================================

local function buildRow(
	parent:      ScrollingFrame,
	bait:        BaitDef,
	count:       number,
	equipped:    boolean,
	discountPct: number,
	order:       number,
	onBuy:       () -> (),
	onEquip:     () -> ()
): Frame
	local discounted = math.max(1, math.ceil(bait.baseCost * (1 - discountPct)))
	local maxed      = count >= bait.maxStack

	local row = Instance.new("Frame")
	row.Name             = "Row"
	row.Size             = UDim2.new(1, 0, 0, 80)
	row.BackgroundColor3 = equipped and P.TealLight or P.Teal
	row.BorderSizePixel  = 0
	row.LayoutOrder      = order
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 10); rc.Parent = row
	if equipped then
		local stroke = Instance.new("UIStroke")
		stroke.Color       = P.Gold
		stroke.Thickness   = 2
		stroke.Transparency = 0.1
		stroke.Parent      = row
	end
	row.Parent = parent

	-- Tier colour strip (left edge)
	local strip = Instance.new("Frame")
	strip.AnchorPoint       = Vector2.new(0, 0.5)
	strip.Position          = UDim2.new(0, 8, 0.5, 0)
	strip.Size              = UDim2.fromOffset(5, 44)
	strip.BackgroundColor3  = TIER_COLOUR[bait.tier] or P.Common
	strip.BorderSizePixel   = 0
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0.5, 0); sc.Parent = strip
	strip.Parent = row

	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position          = UDim2.new(0, 20, 0, 7)
	nameLabel.Size              = UDim2.fromOffset(168, 20)
	nameLabel.Font              = Enum.Font.GothamBold
	nameLabel.TextSize          = 15
	nameLabel.TextColor3        = P.Cream
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Left
	nameLabel.TextTruncate      = Enum.TextTruncate.AtEnd
	nameLabel.Text              = bait.displayName
	nameLabel.Parent            = row

	-- Tier text
	local tierLabel = Instance.new("TextLabel")
	tierLabel.BackgroundTransparency = 1
	tierLabel.Position          = UDim2.new(0, 20, 0, 27)
	tierLabel.Size              = UDim2.fromOffset(168, 14)
	tierLabel.Font              = Enum.Font.Gotham
	tierLabel.TextSize          = 12
	tierLabel.TextColor3        = TIER_COLOUR[bait.tier] or P.CreamSoft
	tierLabel.TextXAlignment    = Enum.TextXAlignment.Left
	tierLabel.Text              = bait.tier
	tierLabel.Parent            = row

	-- Boost + held count in one line — 12px floor (was 11).
	local boostStr = bait.rarityBoost == 1.0
		and "No boost"
		or ("%.1f× rares"):format(bait.rarityBoost)
	UIUtil.makeLabel(boostStr .. "  ·  " .. count .. " held", "caption", {
		Position    = UDim2.new(0, 20, 0, 46),
		Size        = UDim2.fromOffset(168, 16),
		Parent      = row,
	})

	-- Equip button (right-most, 90 × 44)
	local equipText = equipped and "✓ On" or (count > 0 and "Equip" or "Equip")
	local equipBtn = UIUtil.makeButton(equipText, onEquip, {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -8, 0.5, 0),
		Size             = UDim2.fromOffset(90, 44),
		BackgroundColor3 = equipped and P.GoldDeep or (count > 0 and P.Wood or P.TealDark),
		variant          = "secondary",
	})
	if not equipped and count == 0 then
		equipBtn.TextColor3 = P.CreamSoft
	end
	equipBtn.Parent = row

	-- Buy button ("Buy Xc"), to the left of Equip with an 8 px gap
	local buyText = maxed and "Full" or ("Buy " .. discounted .. "c")
	local buyBtn = UIUtil.makeButton(buyText, onBuy, {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -106, 0.5, 0),
		Size             = UDim2.fromOffset(90, 44),
		BackgroundColor3 = maxed and P.TealDark or P.Sunset,
		variant          = "primary",
	})
	if maxed then buyBtn.TextColor3 = P.CreamSoft end
	buyBtn.Parent = row

	return row
end

-- ====================================================================
-- PUBLIC
-- ====================================================================

function BaitShopUI.show(
	baits:          {BaitDef},
	initialStash:   {[string]: number},
	equippedBaitId: string?,
	discountPct:    number,
	onBuy:          (baitId: string, qty: number) -> (),
	onEquip:        (baitId: string?) -> ()
): BaitHandle

	local titleText = discountPct > 0
		and ("Bait Shop  ·  -%d%% dock"):format(math.round(discountPct * 100))
		or "Bait Shop"
	local shell
	shell = UIUtil.makeModalShell({
		name = "BaitShopUI",
		title = titleText,
		onClose = function() if shell then shell.destroy() end end,
		width = 440,
		heightScale = 0.88,
	})
	local gui  = shell.gui
	local body = shell.body

	-- Scrolling bait list fills the body.
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel        = 0
	list.Size                   = UDim2.fromScale(1, 1)
	list.ScrollBarThickness     = 4
	list.ScrollBarImageColor3   = P.TealDeeper
	list.CanvasSize             = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	list.Parent                 = body

	local layout = Instance.new("UIListLayout")
	layout.Padding      = UDim.new(0, 6)
	layout.SortOrder    = Enum.SortOrder.LayoutOrder   -- must be explicit; default varies
	layout.Parent       = list

	-- Rebuilds all rows from the current stash state.
	local function rebuild(stash: {[string]: number}, equipped: string?)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, bait in ipairs(baits) do
			local count      = stash[bait.id] or 0
			local isEquipped = equipped == bait.id
			buildRow(
				list, bait, count, isEquipped, discountPct, i,
				function() onBuy(bait.id, 1) end,
				function()
					if isEquipped then onEquip(nil) else onEquip(bait.id) end
				end
			)
		end
	end

	rebuild(initialStash, equippedBaitId)

	return {
		close        = function() shell.destroy() end,
		refreshStash = function(newStash, newEquipped)
			if gui.Parent then rebuild(newStash, newEquipped) end
		end,
	}
end

return BaitShopUI
