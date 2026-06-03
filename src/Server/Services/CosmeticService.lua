--!strict
-- CosmeticService.lua
-- Server-authoritative cosmetic equip/unequip + ownership. Validates against
-- the catalog, tracks owned cosmetics separately from equipped slots, and
-- broadcasts CosmeticsChanged to the client.
--
-- Profile fields:
--   data.cosmetics      = { hat: string?, coat: string?, boots: string? }   -- equipped
--   data.ownedCosmetics = {[cosmeticId]: true}                              -- owned set
-- Types: Types.Cosmetics (src/Shared/Types.lua:118-122)
-- Catalog: CosmeticsCatalog (src/Shared/Config/CosmeticsCatalog.lua)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit             = require(ReplicatedStorage.Packages.Knit)
local GameConfig       = require(ReplicatedStorage.Shared.Config.GameConfig)
local CosmeticsCatalog = require(ReplicatedStorage.Shared.Config.CosmeticsCatalog)

local CosmeticService = Knit.CreateService({
	Name = "CosmeticService",
	Client = {
		CosmeticsChanged = Knit.CreateSignal(),  -- (cosmetics: Types.Cosmetics)
	},
})

-- ====================================================================
-- HELPERS
-- ====================================================================

local function getCosmeticsData(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return nil end
	if not data.cosmetics then
		data.cosmetics = {}
	end
	return data.cosmetics
end

local function getOwnedCosmetics(player: Player): {[string]: boolean}
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return {} end
	if not data.ownedCosmetics then
		data.ownedCosmetics = {}
	end
	return data.ownedCosmetics
end

local function fireChanged(player: Player, cosmetics: any)
	CosmeticService.Client.CosmeticsChanged:Fire(player, cosmetics)
end

-- ====================================================================
-- CLIENT API
-- ====================================================================

function CosmeticService.Client:GetCosmetics(player: Player): {hat: string?, coat: string?, boots: string?}
	return getCosmeticsData(player) or {}
end

function CosmeticService.Client:GetOwnedCosmetics(player: Player): {[string]: boolean}
	return getOwnedCosmetics(player)
end

-- Grant a cosmetic to the player's ownership set. Called by streak rewards
-- (QuestService) and by the Robux purchase path (ProcessReceipt handler).
-- Idempotent: granting an already-owned cosmetic is a no-op.
function CosmeticService.Client:GrantCosmetic(player: Player, cosmeticId: string): {ok: boolean, reason: string?}
	local def = CosmeticsCatalog.byId[cosmeticId]
	if not def then
		return { ok = false, reason = "unknown_cosmetic" }
	end

	local owned = getOwnedCosmetics(player)
	owned[cosmeticId] = true

	-- Auto-equip if nothing is in that slot yet (first-time grant feel-good).
	local cosmetics = getCosmeticsData(player)
	if cosmetics and not cosmetics[def.slot] then
		cosmetics[def.slot] = cosmeticId
		fireChanged(player, cosmetics)
	end

	return { ok = true }
end

-- Equip a cosmetic to its designated slot. Validates the cosmetic exists in the
-- catalog AND the player owns it before writing.
function CosmeticService.Client:EquipCosmetic(player: Player, cosmeticId: string): {ok: boolean, reason: string?}
	local def = CosmeticsCatalog.byId[cosmeticId]
	if not def then
		return { ok = false, reason = "unknown_cosmetic" }
	end

	-- Ownership check: player must own the cosmetic to equip it.
	local owned = getOwnedCosmetics(player)
	if not owned[cosmeticId] then
		return { ok = false, reason = "not_owned" }
	end

	local cosmetics = getCosmeticsData(player)
	if not cosmetics then
		return { ok = false, reason = "no_profile" }
	end

	cosmetics[def.slot] = cosmeticId
	fireChanged(player, cosmetics)
	return { ok = true }
end

-- Unequip a cosmetic from a slot. Restores the slot to nil (bare/default look).
function CosmeticService.Client:UnequipCosmetic(player: Player, slot: string): {ok: boolean, reason: string?}
	if slot ~= "hat" and slot ~= "coat" and slot ~= "boots" then
		return { ok = false, reason = "invalid_slot" }
	end

	local cosmetics = getCosmeticsData(player)
	if not cosmetics then
		return { ok = false, reason = "no_profile" }
	end

	cosmetics[slot] = nil
	fireChanged(player, cosmetics)
	return { ok = true }
end

return CosmeticService
