--!strict
-- ShopController.lua
-- Opens the rod-tier shop when the Dock ProximityPrompt fires.
-- Bait shop is handled by BaitShopController.

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
-- LIFECYCLE — listen for ProximityPrompts on Dock/BaitShop parts.
-- ====================================================================
function ShopController:KnitStart()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText == "Buy Rod Upgrade" then
			self:OpenRodShop()
		elseif prompt.ActionText == "Repair Dock" then
			-- Direct dock-repair shortcut so tutorial beat 5 doesn't
			-- require finding the BUILD/Upgrade-mode flow. Server
			-- re-validates cost; if the player can't afford it, warn
			-- silently and let the dialogue's "Catch a few more" line
			-- keep them moving.
			local uid = prompt:GetAttribute("buildingUid")
			if not uid then return end
			Knit.GetService("HarborService"):Upgrade(uid):andThen(function(res)
				if not res.ok then
					warn("[Shop] Repair Dock failed:", res.reason)
				end
			end)
		end
	end)
end

return ShopController
