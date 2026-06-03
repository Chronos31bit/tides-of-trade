--!strict
-- CosmeticShopController.lua
-- Opens the Robux cosmetic shop. Triggered by ProximityPrompt ("Cosmetic Shop")
-- on the Dock, or programmatically via Open(). Lists purchasable cosmetics,
-- marks owned items, and initiates native Roblox purchases.
--
-- Server-side purchase processing is handled by CosmeticShopService.

local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Knit        = require(ReplicatedStorage.Packages.Knit)
local Trove       = require(ReplicatedStorage.Packages.Trove)
local GameConfig  = require(ReplicatedStorage.Shared.Config.GameConfig)
local CosmeticShopUI = require(script.Parent.Parent.UI.CosmeticShopUI)

local CosmeticShopController = Knit.CreateController({
	Name = "CosmeticShopController",
	_trove = nil :: any,
	_handle = nil :: any,
})

function CosmeticShopController:KnitStart()
	self._trove = Trove.new()

	-- Open from Dock ProximityPrompt.
	self._trove:Connect(ProximityPromptService.PromptTriggered, function(prompt, _player)
		if prompt.ActionText == "Cosmetic Shop" then
			self:Open()
		end
	end)
end

function CosmeticShopController:Open()
	if self._handle then
		self._handle.close()
		self._handle = nil
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")

	PlayerDataService:GetSnapshot():andThen(function(snap: any)
		if not snap then return end

		-- Build product list from GameConfig + CosmeticsCatalog.
		local productMap = GameConfig.CosmeticShop.Products
		local products: {{productId: number, cosmeticId: string, price: number}} = {}
		for productId, cosmeticId in pairs(productMap) do
			if productId ~= 0 then  -- Skip placeholder.
				table.insert(products, {
					productId = productId,
					cosmeticId = cosmeticId,
					price = 0,  -- Price is on the Roblox side; client doesn't need it.
				})
			end
		end

		-- Build owned lookup from profile cosmetics.
		local owned: {[string]: boolean} = {}
		local cosmetics = snap.cosmetics
		if cosmetics then
			for slot, id in pairs(cosmetics) do
				if type(id) == "string" then
					owned[id] = true
				end
			end
		end

		self._handle = CosmeticShopUI.show({
			products = products,
			owned = owned,
			onClose = function()
				local h = self._handle
				self._handle = nil
				if h then h.close() end
			end,
		})
	end):catch(function(err)
		warn("[CosmeticShop] Failed to open:", err)
	end)
end

function CosmeticShopController:Close()
	if self._handle then
		self._handle.close()
		self._handle = nil
	end
end

return CosmeticShopController
