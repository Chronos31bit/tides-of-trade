--!strict
-- BaitShopUI.lua
-- Template-driven bait shop panel (StarterGuiAssets.BaitShopUI_Template).

local CollectionService = game:GetService("CollectionService")

local TemplateLoader = require(script.Parent.TemplateLoader)
local UIUtil = require(script.Parent.UIUtil)

local P = UIUtil.Palette

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

local TILE_TAG = "TotBaitTile"

local function req(parent: Instance, name: string, class: string): Instance
	local c = parent:FindFirstChild(name)
	if not c or not c:IsA(class) then
		error(`[BaitShopUI] Missing {class} "{name}" under {parent:GetFullName()}`, 2)
	end
	return c
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

	local gui = TemplateLoader.spawn("BaitShop", { instanceName = "BaitShopUI" })
	local backdrop = req(gui, "Backdrop", "TextButton") :: TextButton
	local panel = req(gui, "Panel", "Frame") :: Frame
	local header = req(panel, "Header", "Frame") :: Frame
	local title = req(header, "Title", "TextLabel") :: TextLabel
	local closeBtn = req(header, "Close", "TextButton") :: TextButton
	local body = req(panel, "Body", "Frame") :: Frame

	local list = req(body, "BaitList", "ScrollingFrame") :: ScrollingFrame
	local tileTpl = req(body, "BaitTile_Template", "Frame") :: Frame

	title.Text = discountPct > 0
		and ("Bait Shop  ·  -%d%% dock"):format(math.round(discountPct * 100))
		or "Bait Shop"

	-- Rebuilds all rows from the current stash state.
	local function rebuild(stash: {[string]: number}, equipped: string?)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") and CollectionService:HasTag(c, TILE_TAG) then
				c:Destroy()
			end
		end

		for i, bait in ipairs(baits) do
			local count = stash[bait.id] or 0
			local isEquipped = equipped == bait.id
			local discounted = math.max(1, math.ceil(bait.baseCost * (1 - discountPct)))
			local maxed = count >= bait.maxStack

			local tile = tileTpl:Clone()
			tile.Visible = true
			tile.LayoutOrder = i
			tile.Name = "BaitTile_" .. bait.id
			tile.Parent = list
			CollectionService:AddTag(tile, TILE_TAG)

			local icon = req(tile, "Icon", "ImageLabel") :: ImageLabel
			local nameLbl = req(tile, "NameLabel", "TextLabel") :: TextLabel
			local effectLbl = req(tile, "EffectDescLabel", "TextLabel") :: TextLabel
			local priceLbl = req(tile, "PriceLabel", "TextLabel") :: TextLabel
			local buyBtn = req(tile, "BuyButton", "TextButton") :: TextButton
			local ownedBadge = req(tile, "OwnedCountBadge", "TextLabel") :: TextLabel

			nameLbl.Text = bait.displayName
			effectLbl.Text = bait.rarityBoost == 1.0 and "No boost" or ("%.1f× rares"):format(bait.rarityBoost)
			priceLbl.Text = discounted .. "c"

			ownedBadge.Visible = count > 0
			if count > 0 then
				ownedBadge.Text = tostring(count)
			end

			icon.Image = icon.Image -- left blank unless artists set it

			buyBtn.Text = maxed and "Full" or "Buy"
			buyBtn.BackgroundColor3 = maxed and P.TealDark or P.Sunset
			buyBtn.TextColor3 = maxed and P.CreamSoft or P.Cream
			buyBtn.Active = not maxed

			buyBtn.Activated:Connect(function()
				if maxed then return end
				onBuy(bait.id, 1)
			end)

			-- Equip is “tap the tile name area” for now: keep existing controller contract.
			-- (Equipped highlighting is not part of the template contract; we just forward the action.)
			if isEquipped then
				tile.BackgroundColor3 = P.TealLight
			else
				tile.BackgroundColor3 = P.Teal
			end
			tile.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					if isEquipped then onEquip(nil) else onEquip(bait.id) end
				end
			end)
		end
	end

	rebuild(initialStash, equippedBaitId)

	local closed = false
	local function destroy()
		if closed then return end
		closed = true
		if gui.Parent then gui:Destroy() end
	end

	backdrop.Activated:Connect(destroy)
	closeBtn.Activated:Connect(destroy)

	return {
		close = destroy,
		refreshStash = function(newStash, newEquipped)
			if gui.Parent then
				rebuild(newStash, newEquipped)
			end
		end,
	}
end

return BaitShopUI
