--!strict
-- FishCodexController.lua
-- Owns the fish codex panel (collection screen). Subscribes to CodexChanged
-- for live discovery updates and ProfileLoaded for the initial snapshot.
-- The codex shows every species in FishCatalog: discovered fish render in
-- full color with rarity badge + count; undiscovered show as silhouettes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit          = require(ReplicatedStorage.Packages.Knit)
local FishCatalog   = require(ReplicatedStorage.Shared.Config.FishCatalog)
local FishCodexUI   = require(script.Parent.Parent.UI.FishCodexUI)

-- Guard: duplicate-require crash prevention (see RodSelectController).
do
	local ok, existing = pcall(Knit.GetController, "FishCodexController")
	if ok and existing then return existing end
end

-- Build byId lookup from the flat fish array so we can resolve species by id
-- from CodexChanged. FishCatalog ships as { fish = {FishDef} } with no byId.
local fishById: {[string]: any} = {}
for _, f in ipairs(FishCatalog.fish) do
	fishById[f.id] = f
end

local FishCodexController = Knit.CreateController({
	Name = "FishCodexController",
	_handle        = nil :: any,  -- FishCodexUI.Handle while open
	_caughtSpecies = {} :: {[string]: number},  -- [fishId] = count
	_totalSpecies  = 0,
})

function FishCodexController:KnitStart()
	local pds = Knit.GetService("PlayerDataService")

	-- Load initial snapshot from profile.
	pds:GetSnapshot():andThen(function(snap)
		if snap and snap.stats and snap.stats.caughtSpecies then
			self._caughtSpecies = snap.stats.caughtSpecies
			self:_countDiscovered()
		end
	end)

	-- Live discovery events. Fires when a new species is first caught.
	pds.CodexChanged:Connect(function(speciesId, caughtSpecies)
		self._caughtSpecies = caughtSpecies
		self:_countDiscovered()
		if self._handle then
			self._handle.refresh(self._caughtSpecies, self._discovered)
		end
		-- Toast the newest discovery so the player sees immediate feedback.
		-- The speciesId is the one that just went from 0→1.
		if speciesId then
			local fish = fishById[speciesId]
			if fish then
				self:_toast(fish.displayName, fish.rarity)
			end
		end
	end)
end

function FishCodexController:_countDiscovered()
	local n = 0
	for _ in pairs(self._caughtSpecies) do
		n += 1
	end
	self._discovered = n
	self._totalSpecies = #FishCatalog.fish
end

-- Mini-toast: brief notification that a new species was discovered.
-- Uses NotificationController if available; falls back to a simple print.
function FishCodexController:_toast(displayName: string, rarity: string)
	local ok, nc = pcall(Knit.GetController, "NotificationController")
	if ok and nc and nc.push then
		nc:push("New Discovery!", displayName .. " (" .. rarity .. ") added to your Codex.")
	else
		print("[FishCodex] New species:", displayName, "(" .. rarity .. ")")
	end
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

function FishCodexController:Open()
	if self._handle then return end

	self._handle = FishCodexUI.show({
		fishCatalog   = FishCatalog.fish,
		caughtSpecies = self._caughtSpecies,
		discovered    = self._discovered or 0,
		totalSpecies  = self._totalSpecies,
		onClose       = function()
			self._handle = nil
		end,
	})
end

function FishCodexController:Close()
	if self._handle then
		self._handle.close()
		self._handle = nil
	end
end

function FishCodexController:Toggle()
	if self._handle then
		self:Close()
	else
		self:Open()
	end
end

function FishCodexController:IsOpen(): boolean
	return self._handle ~= nil
end

return FishCodexController
