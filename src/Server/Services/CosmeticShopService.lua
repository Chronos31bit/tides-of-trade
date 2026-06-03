--!strict
-- CosmeticShopService.lua
-- Robux purchase path for cosmetics. Sets MarketplaceService.ProcessReceipt
-- to handle developer-product purchases. Each product maps to a cosmetic ID
-- in GameConfig.CosmeticShop.Products. Idempotent: re-processing the same
-- PurchaseId grants nothing (checked via DataStore).
--
-- Must be running on every server because ProcessReceipt fires on whichever
-- server the player happens to be on when the purchase completes.

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Knit             = require(ReplicatedStorage.Packages.Knit)
local GameConfig       = require(ReplicatedStorage.Shared.Config.GameConfig)
local CosmeticsCatalog = require(ReplicatedStorage.Shared.Config.CosmeticsCatalog)

local CosmeticShopService = Knit.CreateService({
	Name = "CosmeticShopService",
	_purchaseStore = nil :: any,
})

function CosmeticShopService:KnitInit()
	self._purchaseStore = DataStoreService:GetDataStore("TidesCosmeticPurchases_v1")
end

function CosmeticShopService:KnitStart()
	-- ProcessReceipt is a global callback set once per server. KnitStart is the
	-- right time — all services (including CosmeticService + PlayerDataService)
	-- are initialized but players may not have joined yet.
	local self = self
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end
end

-- ====================================================================
-- PROCESS RECEIPT
-- ====================================================================

function CosmeticShopService:_processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local productId: number = receiptInfo.ProductId
	local playerId: number = receiptInfo.PlayerId
	local purchaseId: string = receiptInfo.PurchaseId

	-- Validate: product must exist in our config.
	local productMap = GameConfig.CosmeticShop.Products
	local cosmeticId = productMap[productId]
	if not cosmeticId then
		warn("[CosmeticShop] Unknown productId:", productId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Validate: cosmetic must exist in the catalog.
	local def = CosmeticsCatalog.byId[cosmeticId]
	if not def then
		warn("[CosmeticShop] Unknown cosmeticId:", cosmeticId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Idempotency check: record the PurchaseId in a DataStore so re-processing
	-- (Roblox may retry) doesn't double-grant.
	local alreadyProcessed = false
	local ok = pcall(function()
		alreadyProcessed = self._purchaseStore:GetAsync(purchaseId)
	end)
	if not ok then
		warn("[CosmeticShop] DataStore read failed for purchase", purchaseId, "— will retry")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if alreadyProcessed then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Find the player. They should be on this server since ProcessReceipt fires
	-- where the purchase was initiated, but guard against edge cases.
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		warn("[CosmeticShop] Player not on server for purchase", purchaseId, "— will retry on next join")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Grant the cosmetic.
	local CosmeticService = Knit.GetService("CosmeticService")
	local grantResult = CosmeticService.Client:GrantCosmetic(player, cosmeticId)
	if not grantResult.ok then
		warn("[CosmeticShop] GrantCosmetic failed:", grantResult.reason)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Persist the purchase id so a retry is a no-op.
	local saveOk = pcall(function()
		self._purchaseStore:SetAsync(purchaseId, true)
	end)
	if not saveOk then
		-- Already granted the cosmetic — retry won't double-grant because the
		-- DataStore read above will catch it on the next attempt, but if both
		-- fail we still want to return Granted so the player gets their item.
		warn("[CosmeticShop] DataStore write failed for purchase", purchaseId)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return CosmeticShopService
