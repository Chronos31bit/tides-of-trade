--!strict
-- RodSelectController.lua
-- Owns the rod-rack panel. Opens when the rod chip is tapped; closes when
-- the player taps the backdrop or taps the chip again. Calls RodService:EquipRod
-- on the server and refreshes the panel on success.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit              = require(ReplicatedStorage.Packages.Knit)
local RodCatalog        = require(ReplicatedStorage.Shared.Config.RodCatalog)
local RodSelectUI       = require(script.Parent.Parent.UI.RodSelectUI)

-- Guard: Rojo can sync two ModuleScript instances under Controllers when a
-- file is renamed/moved; AddControllersDeep would require both and the second
-- Knit.CreateController call crashes with "already exists". Return the already-
-- registered controller on the second require so startup doesn't blow up.
do
	local ok, existing = pcall(Knit.GetController, "RodSelectController")
	if ok and existing then return existing end
end

local RodSelectController = Knit.CreateController({
	Name = "RodSelectController",
	_handle             = nil :: any,  -- RodSelectUI.Handle while open, nil when closed
	_playerXp           = 0,
	_equippedId         = "driftwood",
	_playerDataService  = nil :: any,  -- set in KnitStart
})

function RodSelectController:KnitStart()
	local pds = Knit.GetService("PlayerDataService")
	self._playerDataService = pds

	-- Snapshot from profile load so the panel has correct data on first open.
	pds:GetSnapshot():andThen(function(snap)
		if snap then
			self._playerXp   = snap.xp or 0
			self._equippedId = snap.equippedRodId or "driftwood"
		end
	end)

	-- Keep XP and equipped rod current so the panel reflects live progression
	-- without needing a re-open.
	pds.XPChanged:Connect(function(_level, xp, _next)
		self._playerXp = xp
		if self._handle then
			self._handle.refresh(self._equippedId, self._playerXp)
		end
	end)

	pds.EquippedRodChanged:Connect(function(rodId)
		self._equippedId = rodId
		if self._handle then
			self._handle.refresh(self._equippedId, self._playerXp)
		end
	end)
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

function RodSelectController:Open()
	if self._handle then return end  -- already open

	self._handle = RodSelectUI.show(
		RodCatalog.rods,
		self._playerXp,
		self._equippedId,
		function(rodId: string)
			-- Optimistic local update so the panel feels instant.
			self._equippedId = rodId
			if self._handle then
				self._handle.refresh(self._equippedId, self._playerXp)
			end

			-- Server validation (XP gate). Rolls back the optimistic update on
			-- rejection so the UI stays honest.
			local RodService = Knit.GetService("RodService")
			RodService:EquipRod(rodId):andThen(function(res)
				if not res.ok then
					warn("[RodSelect] EquipRod rejected:", res.reason)
					-- EquippedRodChanged will NOT fire on failure; revert manually.
					self._playerDataService:GetSnapshot():andThen(function(snap)
						if snap then
							self._equippedId = snap.equippedRodId or "driftwood"
							if self._handle then
								self._handle.refresh(self._equippedId, self._playerXp)
							end
						end
					end)
				end
			end)
		end
	)

	-- Clear the handle reference when the panel is closed via the backdrop or
	-- the close button (both destroy the gui, which we can't hook without
	-- polling — so we use the close function as a proxy).
	local originalClose = self._handle.close
	self._handle.close = function()
		originalClose()
		self._handle = nil
	end
end

function RodSelectController:Close()
	if self._handle then
		self._handle.close()
		self._handle = nil
	end
end

function RodSelectController:Toggle()
	if self._handle then
		self:Close()
	else
		self:Open()
	end
end

function RodSelectController:IsOpen(): boolean
	return self._handle ~= nil
end

return RodSelectController
