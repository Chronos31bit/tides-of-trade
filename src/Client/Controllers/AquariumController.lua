--!strict
-- AquariumController.lua
-- Listens for ProximityPrompt activations on aquarium parts. Opens the
-- AquariumUI for that specific aquarium. Subscribes to AquariumChanged so
-- the open panel updates live (e.g. when a deposit completes server-side).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local AquariumUI = require(script.Parent.Parent.UI.AquariumUI)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)

local AquariumController = Knit.CreateController({
	Name = "AquariumController",
	_handle = nil :: any,
	_currentUid = nil :: string?,
})

local function capacityForBuilding(kind: string, tier: number): number
	local def = BuildingCatalog[kind]
	if not def then return 0 end
	local t = def.tiers[tier]
	return (t and t.aquariumCapacity) or 0
end

function AquariumController:KnitStart()
	local AquariumService = Knit.GetService("AquariumService")

	-- ProximityPrompt fires on the part the prompt is parented to. We use
	-- the part's name (= building uid) to identify which aquarium.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, _player)
		if prompt.ActionText ~= "Open Aquarium" then return end
		local part = prompt.Parent :: BasePart
		if not part or not part:IsA("BasePart") then return end
		local kind = part:GetAttribute("kind")
		local tier = part:GetAttribute("tier")
		if kind ~= "Aquarium" then return end
		self:Open(part.Name, capacityForBuilding(kind, tier or 1))
	end)

	-- Live updates if server pushes a change.
	AquariumService.AquariumChanged:Connect(function(uid, contents)
		if self._handle and self._currentUid == uid then
			-- Pull current inventory snapshot to refresh the right column too.
			local PlayerDataService = Knit.GetService("PlayerDataService")
			PlayerDataService:GetSnapshot():andThen(function(snap)
				local inv = (snap and snap.inventory) or {}
				local cap = self:_capacityFor(snap, uid)
				self._handle.refresh(contents, inv, cap)
			end)
		end
	end)

	-- Keyboard shortcut for PC players: Q opens the *first* aquarium they own.
	-- Faster than walking up to the prompt during testing.
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Q then
			self:OpenFirstOwned()
		end
	end)
end

-- Look up capacity from the live snapshot — preferred over the cached
-- catalog value because tier upgrades shouldn't require re-opening UI.
function AquariumController:_capacityFor(snap: any, uid: string): number
	if not snap then return 0 end
	for _, b in ipairs(snap.buildings or {}) do
		if b.uid == uid and b.kind == "Aquarium" then
			return capacityForBuilding(b.kind, b.tier)
		end
	end
	return 0
end

function AquariumController:Open(aquariumUid: string, capacity: number)
	local AquariumService = Knit.GetService("AquariumService")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local snap = PlayerDataService:GetSnapshot():expect()
	local inv = (snap and snap.inventory) or {}
	AquariumService:GetContents(aquariumUid):andThen(function(contents)
		contents = contents or {}
		if self._handle then self._handle.close() end
		self._currentUid = aquariumUid
		self._handle = AquariumUI.show(contents, inv, capacity,
			function(itemUid)
				AquariumService:Deposit(aquariumUid, itemUid):andThen(function(res)
					if not res.ok then warn("[Aquarium] deposit:", res.reason) end
				end)
			end,
			function(itemUid)
				AquariumService:Withdraw(aquariumUid, itemUid):andThen(function(res)
					if not res.ok then warn("[Aquarium] withdraw:", res.reason) end
				end)
			end
		)
	end)
end

function AquariumController:OpenFirstOwned()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local snap = PlayerDataService:GetSnapshot():expect()
	if not snap then return end
	for _, b in ipairs(snap.buildings or {}) do
		if b.kind == "Aquarium" then
			self:Open(b.uid, capacityForBuilding(b.kind, b.tier))
			return
		end
	end
	print("[Aquarium] You don't own an aquarium yet. Build one in Build mode (B).")
end

return AquariumController
