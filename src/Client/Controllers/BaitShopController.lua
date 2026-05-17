--!strict
-- BaitShopController.lua
-- Opens the BaitShopUI when the player activates the "Open Bait Shop"
-- ProximityPrompt on any BaitShop building anchor. Listens to
-- BaitService.BaitStashChanged so the open panel refreshes live without
-- re-opening.

local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Knit           = require(ReplicatedStorage.Packages.Knit)
local Trove          = require(ReplicatedStorage.Packages.Trove)
local BaitCatalog    = require(ReplicatedStorage.Shared.Config.BaitCatalog)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local BaitShopUI     = require(script.Parent.Parent.UI.BaitShopUI)

local BaitShopController = Knit.CreateController({
	Name   = "BaitShopController",
	_trove  = nil :: any,
	_handle = nil :: any,  -- open BaitShopUI handle, or nil
})

-- ====================================================================
-- HELPERS
-- ====================================================================

-- Returns the baitDiscountPct from the player's Dock building tier.
-- Every player has a Dock, so this is always available (0 for tier 1).
local function discountFromSnapshot(snap: any): number
	if not snap or not snap.buildings then return 0 end
	for _, building in ipairs(snap.buildings) do
		if building.kind == "Dock" then
			local def = BuildingCatalog.Dock
			local tierData = def and def.tiers[building.tier]
			if tierData and tierData.baitDiscountPct then
				return tierData.baitDiscountPct
			end
		end
	end
	return 0
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function BaitShopController:KnitStart()
	self._trove = Trove.new()

	local BaitService       = Knit.GetService("BaitService")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	-- Live-refresh the open panel whenever the server confirms a stash change.
	self._trove:Connect(BaitService.BaitStashChanged, function(
		stash: {[string]: number},
		equippedBaitId: string?
	)
		if self._handle then
			self._handle.refreshStash(stash, equippedBaitId)
		end
	end)

	-- Open the bait shop from the Dock ("Buy Bait") or a placed BaitShop building.
	self._trove:Connect(ProximityPromptService.PromptTriggered, function(prompt, _player)
		local action = prompt.ActionText
		if action == "Buy Bait" or action == "Open Bait Shop" then
			self:_open()
		end
	end)
end

-- ====================================================================
-- OPEN PANEL
-- ====================================================================

function BaitShopController:_open()
	local BaitService       = Knit.GetService("BaitService")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	if self._handle then
		self._handle.close()
		self._handle = nil
	end

	-- Fetch snapshot to seed initial stash and discount state.
	PlayerDataService:GetSnapshot():andThen(function(snap: any)
		local stash         = (snap and snap.baitStash)      or {}
		local equippedBaitId = snap and snap.equippedBaitId
		local discountPct   = discountFromSnapshot(snap)

		self._handle = BaitShopUI.show(
			BaitCatalog.baits,
			stash,
			equippedBaitId,
			discountPct,
			-- onBuy: validate server-side; UI refreshes via BaitStashChanged signal.
			function(baitId: string, qty: number)
				BaitService:BuyBait(baitId, qty):andThen(function(res: any)
					if not res.ok then
						warn("[BaitShop] BuyBait failed:", res.reason)
					end
				end)
			end,
			-- onEquip: nil baitId = unequip.
			function(baitId: string?)
				BaitService:EquipBait(baitId):andThen(function(res: any)
					if not res.ok then
						warn("[BaitShop] EquipBait failed:", res.reason)
					end
				end)
			end
		)
	end)
end

return BaitShopController
