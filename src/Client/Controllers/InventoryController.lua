--!strict
-- InventoryController.lua
-- Opens the InventoryUI on demand and forwards "list this item" requests to
-- the MarketController. Subscribes to InventoryChanged so the open panel
-- live-updates when a fish is sold or a buy lands an item.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local InventoryUI = require(script.Parent.Parent.UI.InventoryUI)

-- Load FishCatalog client-side so we can compute a sensible suggested price.
local FishCatalog = require(ReplicatedStorage.Shared.Config.FishCatalog)
local fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do fishById[f.id] = f end

local InventoryController = Knit.CreateController({
	Name = "InventoryController",
	_handle = nil :: any,
	_holdFishController = nil :: any,
})

local function suggestedPriceFor(item: any): number
	-- Suggested price = base * (1 + (weight - min) / (max - min) * 0.5).
	-- Server applies the same formula when validating, so listings stay
	-- close to fair value unless a player intentionally over- or under-cuts.
	if item.kind ~= "Fish" then
		return 50  -- placeholder for goods until we add a goods catalog
	end
	local f = fishById[item.speciesId]
	if not f then return 10 end
	local minW, maxW = f.weightRange[1], f.weightRange[2]
	local frac = (item.weightKg - minW) / math.max(maxW - minW, 0.0001)
	local mul = 1 + math.clamp(frac, 0, 1) * 0.5
	return math.floor(f.basePrice * mul)
end

function InventoryController:KnitStart()
	self._holdFishController = Knit.GetController("HoldFishController")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService.InventoryChanged:Connect(function(items)
		if self._handle then self._handle.refresh(items) end
	end)
end

function InventoryController:Open()
	if self._handle then self._handle.close() end
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local snap = PlayerDataService:GetSnapshot():expect()
	local items = snap and snap.inventory or {}
	local MarketUI = require(script.Parent.Parent.UI.MarketUI)
	local MarketService = Knit.GetService("MarketService")
	local holdCtrl = self._holdFishController
	self._handle = InventoryUI.show(items,
		-- onListRequest: open the price prompt for global market listing.
		function(itemUid, suggested)
			MarketUI.showSellPrompt(suggested, function(finalPrice)
				MarketService:Create(itemUid, finalPrice):andThen(function(res)
					if not res.ok then
						warn("[Inventory] Listing failed:", res.reason)
					end
				end)
			end, function() end)
		end,
		-- onQuickSell: instant dock NPC sale, no prompt.
		function(itemUid)
			MarketService:QuickSell(itemUid):andThen(function(res)
				if not res.ok then
					warn("[Inventory] Quick sell failed:", res.reason)
				else
					print(("[Inventory] Sold for %d coins"):format(res.coinsEarned or 0))
				end
			end)
		end,
		suggestedPriceFor,
		-- onHoldFish: detach fish from inventory and hold it in-world.
		holdCtrl and function(itemUid, speciesId, modifiers, weightKg)
			local f = fishById[speciesId]
			local wMin = f and f.weightRange[1] or 0
			local wMax = f and f.weightRange[2] or 1
			holdCtrl:HoldFish(itemUid, speciesId, modifiers, weightKg, wMin, wMax)
		end or nil
	)
end

function InventoryController:Close()
	if self._handle then self._handle.close(); self._handle = nil end
end

return InventoryController
