--!strict
-- MarketController.lua
-- Owns the global market browser UI. Refreshes on ListingsUpdated /
-- DemandRotated server signals. Buys are pessimistic: we send the request,
-- wait for the result, and surface failures (e.g. "listing_unavailable") as
-- toasts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local MarketUI = require(script.Parent.Parent.UI.MarketUI)

local MarketController = Knit.CreateController({
	Name = "MarketController",
	_handle = nil :: any,
	_lastListings = {},
	_lastDemand = { multiplier = 1.0 },
})

local BUY_FAIL_MSG: {[string]: string} = {
	listing_unavailable = "That listing is gone.",
	not_enough_coins = "Not enough coins.",
	no_profile = "Profile not ready yet.",
	datastore_error = "Market is busy — try again.",
}

function MarketController:KnitStart()
	local MarketService = Knit.GetService("MarketService")

	-- Cache server pushes so we have something to show instantly when Open()
	-- runs, instead of an empty panel that fills in a half-second later.
	MarketService.ListingsUpdated:Connect(function(listings)
		self._lastListings = listings
		if self._handle then self._handle.refresh(listings, self._lastDemand) end
	end)
	MarketService.DemandRotated:Connect(function(speciesId, multiplier)
		self._lastDemand = { speciesId = speciesId, multiplier = multiplier }
		if self._handle then self._handle.refresh(self._lastListings, self._lastDemand) end
	end)

	-- Open from MarketStall ProximityPrompt.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText == "Open Market" then
			self:Open()
		end
	end)

	-- Initial pull so we don't rely on the periodic 30s refresh.
	MarketService:Browse():andThen(function(listings)
		self._lastListings = listings or {}
	end)
	MarketService:GetDemand():andThen(function(demand)
		self._lastDemand = demand or { multiplier = 1.0 }
	end)
end

function MarketController:Open()
	if self._handle then self._handle.close() end
	local MarketService = Knit.GetService("MarketService")
	local NotificationController = Knit.GetController("NotificationController")

	-- Fetch price history for all unique fish species in current listings.
	local priceHistory: {[string]: {{price: number, ts: number}}} = {}
	local seenSpecies: {[string]: boolean} = {}
	local futures = {}
	for _, listing in ipairs(self._lastListings) do
		if listing.itemKind == "Fish" and listing.speciesId then
			local key = listing.speciesId:lower()
			if not seenSpecies[key] then
				seenSpecies[key] = true
				table.insert(futures, MarketService:GetPriceHistory(listing.speciesId):andThen(function(samples)
					if samples and #samples > 0 then
						priceHistory[key] = samples
					end
				end))
			end
		end
	end

	-- Build the UI immediately. Sparklines populate as price history arrives
	-- (server in-memory cache returns instantly for known species, so sparklines
	-- typically render on the first frame). Subsequent ListingsUpdated signals
	-- trigger refresh() which re-reads the shared priceHistory table.
	self._handle = MarketUI.show(self._lastListings, self._lastDemand, priceHistory, function(listingId)
		MarketService:Buy(listingId):andThen(function(res)
			if not res.ok then
				local reason = res.reason or ""
				NotificationController:Toast(BUY_FAIL_MSG[reason] or "Purchase failed.")
			end
		end)
	end)
end

function MarketController:Close()
	if self._handle then self._handle.close(); self._handle = nil end
end

return MarketController
