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
	-- Rod shop replaced by XP-gated rod rack.
	Knit.GetController("RodSelectController"):Toggle()
end

-- ====================================================================
-- LIFECYCLE — listen for ProximityPrompts on Dock/BaitShop parts.
-- ====================================================================
function ShopController:KnitStart()
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText == "Buy Rod Upgrade" then
			Knit.GetController("RodSelectController"):Toggle()
		elseif prompt.ActionText == "Repair Dock" then
			local uid = prompt:GetAttribute("buildingUid")
			if not uid then return end
			Knit.GetService("HarborService"):Upgrade(uid):andThen(function(res)
				if not res.ok then
					warn("[Shop] Upgrade failed:", res.reason)
				end
			end)
		end
	end)
end

return ShopController
