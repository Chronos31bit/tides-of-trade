--!strict
-- BaitShopController.lua
-- Opens BaitShopUI from the Dock "Buy Bait" prompt (day-1 access) or a
-- placed BaitShop building prompt. Discount comes from the Dock tier.

local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local Trove           = require(ReplicatedStorage.Packages.Trove)
local BaitCatalog     = require(ReplicatedStorage.Shared.Config.BaitCatalog)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local BaitShopUI      = require(script.Parent.Parent.UI.BaitShopUI)

local BaitShopController = Knit.CreateController({
	Name       = "BaitShopController",
	_trove     = nil :: any,
	_handle    = nil :: any,  -- open BaitShopUI handle, or nil
	_stashConn = nil :: any,  -- live-refresh connection, active only while panel is open
})

-- ====================================================================
-- HELPERS
-- ====================================================================

local function discountFromSnapshot(snap: any): number
	if not snap or not snap.buildings then return 0 end
	for _, building in ipairs(snap.buildings) do
		if building.kind == "Dock" then
			local def      = BuildingCatalog.Dock
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

	-- Only wire the prompt here — no service proxy access so nothing can
	-- block or error before this connection is established.
	self._trove:Connect(ProximityPromptService.PromptTriggered, function(prompt, _player)
		local action = prompt.ActionText
		if action == "Buy Bait" or action == "Open Bait Shop" then
			self:_open()
		end
	end)
end

-- ====================================================================
-- PANEL
-- ====================================================================

function BaitShopController:_closePanel()
	if self._stashConn then
		self._stashConn:Disconnect()
		self._stashConn = nil
	end
	if self._handle then
		self._handle.close()
		self._handle = nil
	end
end

function BaitShopController:_open()
	local BaitService       = Knit.GetService("BaitService")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	self:_closePanel()

	PlayerDataService:GetSnapshot():andThen(function(snap: any)
		local stash          = (snap and snap.baitStash)     or {}
		local equippedBaitId = snap and snap.equippedBaitId
		local discountPct    = discountFromSnapshot(snap)

		self._handle = BaitShopUI.show(
			BaitCatalog.baits,
			stash,
			equippedBaitId,
			discountPct,
			function(baitId: string, qty: number)
				BaitService:BuyBait(baitId, qty):andThen(function(res: any)
					if not res.ok then
						warn("[BaitShop] BuyBait:", res.reason)
					end
				end)
			end,
			function(baitId: string?)
				BaitService:EquipBait(baitId):andThen(function(res: any)
					if not res.ok then
						warn("[BaitShop] EquipBait:", res.reason)
					end
				end)
			end
		)

		-- Wire the live-refresh connection only while the panel is open.
		-- Guard against nil in case the BaitService proxy isn't fully ready.
		local stashSignal = BaitService.BaitStashChanged
		if stashSignal then
			self._stashConn = stashSignal:Connect(function(
				newStash: {[string]: number},
				newEquipped: string?
			)
				if self._handle then
					self._handle.refreshStash(newStash, newEquipped)
				end
			end)
		end
	end)
end

return BaitShopController
