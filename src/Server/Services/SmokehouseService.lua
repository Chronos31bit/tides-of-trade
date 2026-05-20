--!strict
-- SmokehouseService.lua
-- Players place raw fish into Smokehouse slots; after PreserveTimeSec the
-- server marks the slot ready. Claim moves a preserved Good into inventory.
-- Cancel returns the fish while still smoking (cozy: no failure state).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local GameConfig      = require(ReplicatedStorage.Shared.Config.GameConfig)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local UidUtil         = require(ReplicatedStorage.Shared.Util.UidUtil)
local RateLimiter     = require(ReplicatedStorage.Shared.Util.RateLimiter)

local PRESERVE_TIME = GameConfig.Buildings.Smokehouse.PreserveTimeSec

local SmokehouseService = Knit.CreateService({
	Name = "SmokehouseService",
	Client = {
		SmokehouseChanged = Knit.CreateSignal(),  -- (buildingUid, slots)
	},
	_smokeLimiter = nil :: any,
})

-- ====================================================================
-- HELPERS
-- ====================================================================

local function findOwnedBuilding(player: Player, uid: string)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return nil end
	for _, b in ipairs(data.buildings) do
		if b.uid == uid then return b, data end
	end
	return nil
end

local function ensurePreserveSlots(building: any)
	if not building.preserveSlots then
		building.preserveSlots = {}
	end
	return building.preserveSlots
end

local function smokehouseCapacity(building: any): number
	local def = BuildingCatalog[building.kind]
	if not def then return 0 end
	local tier = def.tiers[building.tier]
	return (tier and tier.smokehouseSlots) or 0
end

local function firstEmptySlot(slots: {[number]: any}, capacity: number): number?
	for i = 1, capacity do
		if slots[i] == nil then
			return i
		end
	end
	return nil
end

-- Mark ready as soon as elapsed (don't wait for the 60s harbor income tick).
local function finalizeSlotIfElapsed(slot: any)
	if slot.ready then return end
	if not slot.startedAt then return end
	if os.time() - slot.startedAt >= PRESERVE_TIME then
		slot.ready = true
		slot.goodId = "preserved_" .. slot.speciesId
	end
end

local function fireChanged(self: any, player: Player, buildingUid: string, building: any)
	self.Client.SmokehouseChanged:Fire(player, buildingUid, building.preserveSlots or {})
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function SmokehouseService:KnitInit()
	self._smokeLimiter = RateLimiter.new(
		GameConfig.AntiExploit.MaxSmokehouseOpsPerMinute, 60
	)
end

function SmokehouseService:KnitStart()
	Players.PlayerRemoving:Connect(function(player)
		self._smokeLimiter:reset(player)
	end)
end

-- ====================================================================
-- TICK — called from HarborService income loop
-- ====================================================================

function SmokehouseService:TickFor(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then return end

	local now = os.time()
	for _, building in ipairs(data.buildings) do
		if building.kind ~= "Smokehouse" then continue end
		local slots = ensurePreserveSlots(building)
		local changed = false
		for _, slot in pairs(slots) do
			if slot and slot.startedAt then
				local wasReady = slot.ready == true
				finalizeSlotIfElapsed(slot)
				if slot.ready and not wasReady then
					changed = true
				end
			end
		end
		if changed then
			fireChanged(self, player, building.uid, building)
		end
	end
end

-- Return slot contents to inventory (used when demolishing a smokehouse).
function SmokehouseService:RefundAllSlots(player: Player, building: any)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local slots = building.preserveSlots
	if not slots then return end

	for slotIndex, slot in pairs(slots) do
		if slot then
			if slot.ready and slot.goodId then
				PlayerDataService:AddItem(player, {
					uid = UidUtil.new("good"),
					kind = "Good",
					goodId = slot.goodId,
					count = 1,
					weightKg = slot.weightKg,
				})
			else
				PlayerDataService:AddItem(player, {
					uid = UidUtil.new("fish"),
					kind = "Fish",
					speciesId = slot.speciesId,
					weightKg = slot.weightKg,
					caughtAt = os.time(),
				})
			end
			slots[slotIndex] = nil
		end
	end
	building.preserveSlots = {}
end

-- ====================================================================
-- CLIENT API
-- ====================================================================

function SmokehouseService.Client:GetSlots(player: Player, buildingUid: string): {[number]: any}?
	if not self.Server._smokeLimiter:check(player) then return nil end
	local building = findOwnedBuilding(player, buildingUid)
	if not building or building.kind ~= "Smokehouse" then return nil end
	local slots = ensurePreserveSlots(building)
	for _, slot in pairs(slots) do
		if slot then finalizeSlotIfElapsed(slot) end
	end
	return slots
end

function SmokehouseService.Client:PlaceFishInSmokehouse(player: Player, buildingUid: string, fishUid: string): {ok: boolean, reason: string?, slotIndex: number?}
	local self = self.Server
	if not self._smokeLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	local building, _data = findOwnedBuilding(player, buildingUid)
	if not building then return { ok = false, reason = "not_found" } end
	if building.kind ~= "Smokehouse" then return { ok = false, reason = "not_smokehouse" } end

	local slots = ensurePreserveSlots(building)
	local cap = smokehouseCapacity(building)
	local slotIndex = firstEmptySlot(slots, cap)
	if not slotIndex then return { ok = false, reason = "full" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local item = PlayerDataService:FindItemByUid(player, fishUid)
	if not item then return { ok = false, reason = "not_owned" } end
	if item.kind ~= "Fish" then return { ok = false, reason = "not_a_fish" } end

	PlayerDataService:RemoveItemByUid(player, fishUid)
	slots[slotIndex] = {
		speciesId = item.speciesId,
		startedAt = os.time(),
		weightKg = item.weightKg,
	}

	fireChanged(self, player, buildingUid, building)
	return { ok = true, slotIndex = slotIndex }
end

function SmokehouseService.Client:CancelFishInSmokehouse(player: Player, buildingUid: string, slotIndex: number): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._smokeLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	local building = findOwnedBuilding(player, buildingUid)
	if not building then return { ok = false, reason = "not_found" } end
	if building.kind ~= "Smokehouse" then return { ok = false, reason = "not_smokehouse" } end
	if typeof(slotIndex) ~= "number"
		or slotIndex ~= math.floor(slotIndex)
		or slotIndex < 1
		or slotIndex > smokehouseCapacity(building)
	then
		return { ok = false, reason = "bad_slot" }
	end

	local slots = ensurePreserveSlots(building)
	local slot = slots[slotIndex]
	if not slot then return { ok = false, reason = "empty" } end
	if slot.ready then return { ok = false, reason = "already_ready" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddItem(player, {
		uid = UidUtil.new("fish"),
		kind = "Fish",
		speciesId = slot.speciesId,
		weightKg = slot.weightKg,
		caughtAt = os.time(),
	})
	slots[slotIndex] = nil

	fireChanged(self, player, buildingUid, building)
	return { ok = true }
end

function SmokehouseService.Client:ClaimPreservedFish(player: Player, buildingUid: string, slotIndex: number): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._smokeLimiter:check(player) then return { ok = false, reason = "rate_limit" } end
	local building = findOwnedBuilding(player, buildingUid)
	if not building then return { ok = false, reason = "not_found" } end
	if building.kind ~= "Smokehouse" then return { ok = false, reason = "not_smokehouse" } end
	if typeof(slotIndex) ~= "number"
		or slotIndex ~= math.floor(slotIndex)
		or slotIndex < 1
		or slotIndex > smokehouseCapacity(building)
	then
		return { ok = false, reason = "bad_slot" }
	end

	local slots = ensurePreserveSlots(building)
	local slot = slots[slotIndex]
	if not slot then return { ok = false, reason = "empty" } end
	finalizeSlotIfElapsed(slot)
	if not slot.ready or not slot.goodId then return { ok = false, reason = "not_ready" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:AddItem(player, {
		uid = UidUtil.new("good"),
		kind = "Good",
		goodId = slot.goodId,
		count = 1,
		weightKg = slot.weightKg,
	})
	slots[slotIndex] = nil

	fireChanged(self, player, buildingUid, building)
	return { ok = true }
end

return SmokehouseService
