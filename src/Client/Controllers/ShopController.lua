--!strict
-- ShopController.lua
-- Opens rod-tier shop (when Dock ProximityPrompt triggers) and bait shop
-- (BaitShop ProximityPrompt). One ShopUI module, two different row sets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local ShopUI = require(script.Parent.Parent.UI.ShopUI)

local ShopController = Knit.CreateController({
	Name = "ShopController",
	_handle = nil :: any,
})

local function priceText(amount: number): string
	if amount == 0 then return "FREE" end
	return ("%d coins"):format(amount)
end

-- ====================================================================
-- ROD SHOP — sequential upgrades. Past tiers show "Owned", current shows
-- the cost, future tiers are locked.
-- ====================================================================
function ShopController:OpenRodShop()
	local ShopService = Knit.GetService("ShopService")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	-- Fetch in parallel to keep open-time snappy.
	local rodsP = ShopService:GetRodCatalog()
	local snapP = PlayerDataService:GetSnapshot()
	rodsP:andThen(function(rods)
		snapP:andThen(function(snap)
			local currentTier = (snap and snap.rodTier) or 1
			local rows = {}
			-- Walk tiers in order so the player sees a clear progression.
			-- Lua iter over numeric keys isn't ordered; sort first.
			local tiers = {}
			for tier in pairs(rods) do table.insert(tiers, tier) end
			table.sort(tiers)

			for _, tier in ipairs(tiers) do
				local rod = rods[tier]
				local owned = tier <= currentTier
				local isNext = tier == currentTier + 1
				local label, priceStr, disabled
				if owned then
					label = "Owned"; priceStr = "Owned"; disabled = true
				elseif isNext then
					label = "Buy"; priceStr = priceText(rod.cost); disabled = false
				else
					label = "Locked"; priceStr = priceText(rod.cost); disabled = true
				end
				table.insert(rows, {
					id = tier,
					name = ("Tier %d — %s"):format(tier, rod.name),
					description = rod.description,
					priceText = priceStr,
					disabled = disabled,
					buyLabel = label,
				})
			end

			if self._handle then self._handle.close() end
			self._handle = ShopUI.show("Rod Shop", rows, function(tierId)
				ShopService:BuyRodTier(tierId :: number):andThen(function(res)
					if not res.ok then
						warn("[Shop] BuyRodTier:", res.reason)
					else
						-- Re-open the shop to refresh rows with the new current tier.
						self:OpenRodShop()
					end
				end)
			end)
		end)
	end)
end

-- ====================================================================
-- BAIT SHOP — purchases activate an immediate buff; we show the player's
-- current buff at the top of the row list as an info row.
-- ====================================================================
function ShopController:OpenBaitShop()
	local ShopService = Knit.GetService("ShopService")
	local baitsP = ShopService:GetBaitCatalog()
	local buffP  = ShopService:GetActiveBuff()

	baitsP:andThen(function(baits)
		buffP:andThen(function(buff)
			local rows = {}
			-- Header info row (disabled button) so the player sees their
			-- current buff state before choosing.
			if buff then
				local remaining = math.max(0, (buff.expiresAt or 0) - os.time())
				table.insert(rows, {
					id = "_active",
					name = ("Active bait: %s"):format(buff.kind),
					description = ("Boost active for %d more seconds."):format(remaining),
					priceText = "Active",
					disabled = true,
					buyLabel = "—",
				})
			else
				table.insert(rows, {
					id = "_none",
					name = "No bait active",
					description = "Buy bait below to boost your next casts.",
					priceText = "—",
					disabled = true,
					buyLabel = "—",
				})
			end

			-- Stable order: walk known ids, sorted by cost.
			local entries = {}
			for id, b in pairs(baits) do table.insert(entries, { id = id, b = b }) end
			table.sort(entries, function(a, b) return a.b.cost < b.b.cost end)
			for _, e in ipairs(entries) do
				table.insert(rows, {
					id = e.id,
					name = e.b.name,
					description = e.b.description,
					priceText = priceText(e.b.cost),
					disabled = false,
					buyLabel = "Buy",
				})
			end

			if self._handle then self._handle.close() end
			self._handle = ShopUI.show("Bait Shop", rows, function(baitId)
				if typeof(baitId) ~= "string" then return end
				if baitId:sub(1, 1) == "_" then return end  -- header row, no-op
				ShopService:BuyBait(baitId):andThen(function(res)
					if not res.ok then
						warn("[Shop] BuyBait:", res.reason)
					else
						-- Re-open the shop so the active-buff header refreshes.
						self:OpenBaitShop()
					end
				end)
			end)
		end)
	end)
end

-- ====================================================================
-- LIFECYCLE — listen for ProximityPrompts on Dock/BaitShop parts.
-- ====================================================================
function ShopController:KnitStart()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText == "Buy Rod Upgrade" then
			self:OpenRodShop()
		elseif prompt.ActionText == "Open Bait Shop" then
			self:OpenBaitShop()
		end
	end)
end

return ShopController
