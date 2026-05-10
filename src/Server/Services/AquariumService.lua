--!strict
-- AquariumService.lua
-- Players deposit fish from inventory into a placed Aquarium building. Each
-- fish in an aquarium contributes to a passive XP + coin trickle on the
-- harbor income tick. Fish in aquariums are *not* in the main inventory —
-- you can withdraw them back at any time.

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local FishCatalog     = require(ReplicatedStorage.Shared.Config.FishCatalog)
local Types           = require(ReplicatedStorage.Shared.Types)

-- Per-rarity reward values applied each income tick, per fish in aquarium.
-- Tuning: Common fills the aquarium fast but pays nearly nothing; Mythic
-- gives a real reason to hunt rare species and *keep* one for display.
local RARITY_INCOME = {
	Common   = { coins = 1,  xp = 0 },
	Uncommon = { coins = 3,  xp = 1 },
	Rare     = { coins = 10, xp = 2 },
	Mythic   = { coins = 30, xp = 6 },
}

local fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do fishById[f.id] = f end

local AquariumService = Knit.CreateService({
	Name = "AquariumService",
	Client = {
		AquariumChanged = Knit.CreateSignal(),  -- (aquariumUid, contents)
	},
})

-- ====================================================================
-- HELPERS
-- ====================================================================

-- Find a placed building by uid on a given player's plot. Returns nil if
-- it's not theirs (preventing cross-plot exploits).
local function findOwnedBuilding(player: Player, uid: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return nil end
	for _, b in ipairs(data.buildings) do
		if b.uid == uid then return b, data end
	end
	return nil
end

local function aquariumCapacity(building: any): number
	local def = BuildingCatalog[building.kind]
	if not def then return 0 end
	local tier = def.tiers[building.tier]
	return (tier and tier.aquariumCapacity) or 0
end

-- ====================================================================
-- LIFECYCLE — income tick is owned by HarborService, so we just expose a
-- :PayoutFor(player) helper it can call.
-- ====================================================================

-- Compute the per-tick aquarium reward for one player and apply it.
-- Returns total coins awarded (mostly for tests/logging).
function AquariumService:PayoutFor(player: Player): number
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return 0 end

	local coins = 0
	local xp = 0
	for _, building in ipairs(data.buildings) do
		if building.kind ~= "Aquarium" then continue end
		local stock = data.aquariumStock[building.uid]
		if not stock then continue end
		for _, item in ipairs(stock) do
			local f = fishById[item.speciesId]
			if not f then continue end
			local r = RARITY_INCOME[f.rarity]
			if r then
				coins += r.coins
				xp += r.xp
			end
		end
	end
	if coins > 0 then PlayerDataService:AddCoins(player, coins, "aquarium") end
	if xp > 0 then PlayerDataService:AddXP(player, xp) end
	return coins
end

-- ====================================================================
-- CLIENT API
-- ====================================================================

function AquariumService.Client:GetContents(player: Player, aquariumUid: string): {Types.FishItem}?
	local self = self.Server
	local building, data = findOwnedBuilding(player, aquariumUid)
	if not building or not data then return nil end
	if building.kind ~= "Aquarium" then return nil end
	return data.aquariumStock[aquariumUid] or {}
end

function AquariumService.Client:Deposit(player: Player, aquariumUid: string, itemUid: string): {ok: boolean, reason: string?}
	local self = self.Server
	local building, data = findOwnedBuilding(player, aquariumUid)
	if not building or not data then return { ok = false, reason = "not_found" } end
	if building.kind ~= "Aquarium" then return { ok = false, reason = "not_aquarium" } end

	-- Capacity check.
	local stock = data.aquariumStock[aquariumUid]
	if not stock then
		stock = {}
		data.aquariumStock[aquariumUid] = stock
	end
	if #stock >= aquariumCapacity(building) then
		return { ok = false, reason = "full" }
	end

	-- Pull from inventory. Only fish allowed in aquariums.
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local item = PlayerDataService:FindItemByUid(player, itemUid)
	if not item then return { ok = false, reason = "not_owned" } end
	if item.kind ~= "Fish" then return { ok = false, reason = "not_a_fish" } end

	-- Move it. We use the same item table so the uid (and weight, caughtAt)
	-- are preserved — players can withdraw the *exact* fish they deposited.
	PlayerDataService:RemoveItemByUid(player, itemUid)
	table.insert(stock, item)

	self.Client.AquariumChanged:Fire(player, aquariumUid, stock)
	return { ok = true }
end

function AquariumService.Client:Withdraw(player: Player, aquariumUid: string, itemUid: string): {ok: boolean, reason: string?}
	local self = self.Server
	local building, data = findOwnedBuilding(player, aquariumUid)
	if not building or not data then return { ok = false, reason = "not_found" } end

	local stock = data.aquariumStock[aquariumUid]
	if not stock then return { ok = false, reason = "empty" } end
	for i, item in ipairs(stock) do
		if item.uid == itemUid then
			table.remove(stock, i)
			-- Put back into inventory.
			local PlayerDataService = Knit.GetService("PlayerDataService")
			PlayerDataService:AddItem(player, item)
			self.Client.AquariumChanged:Fire(player, aquariumUid, stock)
			return { ok = true }
		end
	end
	return { ok = false, reason = "not_in_aquarium" }
end

return AquariumService
