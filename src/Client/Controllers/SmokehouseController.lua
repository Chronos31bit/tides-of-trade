--!strict
-- SmokehouseController.lua
-- ProximityPrompt opens SmokehouseUI for a specific building. Live-updates
-- via SmokehouseChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SmokehouseUI = require(script.Parent.Parent.UI.SmokehouseUI)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)

local SmokehouseController = Knit.CreateController({
	Name = "SmokehouseController",
	_handle = nil :: any,
	_currentUid = nil :: string?,
})

local function capacityForBuilding(kind: string, tier: number): number
	local def = BuildingCatalog[kind]
	if not def then return 0 end
	local t = def.tiers[tier]
	return (t and t.smokehouseSlots) or 0
end

function SmokehouseController:_dismiss()
	if self._handle then
		self._handle.destroy()
		self._handle = nil
	end
	self._currentUid = nil
	Knit.GetController("HUDController"):SetVisible(true)
end

function SmokehouseController:KnitStart()
	local SmokehouseService = Knit.GetService("SmokehouseService")

	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText ~= "Open Smokehouse" then return end
		local part = prompt.Parent :: BasePart
		if not part or not part:IsA("BasePart") then return end
		local kind = part:GetAttribute("kind")
		local tier = part:GetAttribute("tier")
		if kind ~= "Smokehouse" then return end
		self:Open(part.Name, capacityForBuilding(kind, tier or 1))
	end)

	local function refreshOpen(uid: string, slots: {[number]: any}?)
		if not self._handle or self._currentUid ~= uid then return end
		local PlayerDataService = Knit.GetService("PlayerDataService")
		PlayerDataService:GetSnapshot():andThen(function(snap)
			local inv = (snap and snap.inventory) or {}
			local cap = self:_capacityFor(snap, uid)
			self._handle.refresh(slots or {}, inv, cap)
		end)
	end

	SmokehouseService.SmokehouseChanged:Connect(function(uid, slots)
		refreshOpen(uid, slots)
	end)

	-- Tier upgrade while UI is open: capacity label must match new tier slots.
	Knit.GetService("PlayerDataService").BuildingsChanged:Connect(function(_buildings)
		if self._currentUid then
			SmokehouseService:GetSlots(self._currentUid):andThen(function(slots)
				refreshOpen(self._currentUid :: string, slots)
			end)
		end
	end)
end

function SmokehouseController:_capacityFor(snap: any, uid: string): number
	if not snap then return 0 end
	for _, b in ipairs(snap.buildings or {}) do
		if b.uid == uid and b.kind == "Smokehouse" then
			return capacityForBuilding(b.kind, b.tier)
		end
	end
	return 0
end

function SmokehouseController:Open(buildingUid: string, capacity: number)
	local SmokehouseService = Knit.GetService("SmokehouseService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local HUDController = Knit.GetController("HUDController")

	self:_dismiss()

	local snap = PlayerDataService:GetSnapshot():expect()
	local inv = (snap and snap.inventory) or {}

	SmokehouseService:GetSlots(buildingUid):andThen(function(slots)
		slots = slots or {}
		self._currentUid = buildingUid
		HUDController:SetVisible(false)

		self._handle = SmokehouseUI.show(slots, inv, capacity,
			function(fishUid)
				SmokehouseService:PlaceFishInSmokehouse(buildingUid, fishUid):andThen(function(res)
					if not res.ok then warn("[Smokehouse] place:", res.reason) end
				end)
			end,
			function(slotIndex)
				SmokehouseService:CancelFishInSmokehouse(buildingUid, slotIndex):andThen(function(res)
					if not res.ok then warn("[Smokehouse] cancel:", res.reason) end
				end)
			end,
			function(slotIndex)
				SmokehouseService:ClaimPreservedFish(buildingUid, slotIndex):andThen(function(res)
					if not res.ok then warn("[Smokehouse] claim:", res.reason) end
				end)
			end,
			function()
				self:_dismiss()
			end
		)
	end)
end

function SmokehouseController:Close()
	self:_dismiss()
end

return SmokehouseController
