--!strict
-- GridUtil.lua
-- Pure functions for converting between grid coords and world studs, plus
-- collision/bounds checks for building placement. Lives in Shared so both
-- the client preview ghost and the server validator use identical math —
-- if the client lies about position, the server arithmetic catches it.

local GameConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))
local BuildingCatalog = require(game:GetService("ReplicatedStorage").Shared.Config.BuildingCatalog)

local GridUtil = {}

local PLOT = GameConfig.Harbor.PlotSizeStuds
local CELL = GameConfig.Harbor.GridCellStuds
local CELLS_PER_AXIS = PLOT / CELL  -- 80/4 = 20

-- Convert a grid (x, z) cell to world position relative to plot origin.
-- Plot origin is the corner of the plot; grid (0,0) is that same corner.
function GridUtil.gridToLocal(gridX: number, gridZ: number): Vector3
	return Vector3.new(gridX * CELL, 0, gridZ * CELL)
end

-- Inverse — snap any local position to the nearest valid grid cell.
function GridUtil.snap(localPos: Vector3): (number, number)
	local gx = math.floor(localPos.X / CELL + 0.5)
	local gz = math.floor(localPos.Z / CELL + 0.5)
	return gx, gz
end

-- Returns true if a footprint of (w, d) cells placed at (gx, gz) with the
-- given rotation fits entirely within the plot bounds.
function GridUtil.inBounds(gx: number, gz: number, footprint: {number}, rotation: number): boolean
	local w, d = footprint[1], footprint[2]
	-- 90/270 rotations swap width and depth.
	if rotation == 90 or rotation == 270 then
		w, d = d, w
	end
	if gx < 0 or gz < 0 then return false end
	if gx + w > CELLS_PER_AXIS then return false end
	if gz + d > CELLS_PER_AXIS then return false end
	return true
end

-- Returns the set of cells occupied by a building. We materialize it as a
-- {[key]: true} table (key = "x,z") so collision checks are O(footprint).
function GridUtil.occupiedCells(gx: number, gz: number, footprint: {number}, rotation: number): {[string]: boolean}
	local w, d = footprint[1], footprint[2]
	if rotation == 90 or rotation == 270 then
		w, d = d, w
	end
	local cells: {[string]: boolean} = {}
	for dx = 0, w - 1 do
		for dz = 0, d - 1 do
			cells[(gx + dx) .. "," .. (gz + dz)] = true
		end
	end
	return cells
end

-- Build the occupied-cell map for an entire list of placed buildings.
-- Used by HarborService when validating a new placement.
function GridUtil.buildOccupancy(buildings: {any}): {[string]: string}
	-- value is the building uid that owns the cell — useful for "what's here?" UX.
	local occ: {[string]: string} = {}
	for _, b in ipairs(buildings) do
		local def = BuildingCatalog[b.kind]
		if not def then continue end
		local cells = GridUtil.occupiedCells(b.gridX, b.gridZ, def.footprint, b.rotation)
		for k in pairs(cells) do
			occ[k] = b.uid
		end
	end
	return occ
end

-- Returns false (and the conflicting uid) if any of the proposed cells overlap
-- an existing building. Caller should also call inBounds first.
function GridUtil.checkPlacement(occupancy: {[string]: string}, gx: number, gz: number, footprint: {number}, rotation: number): (boolean, string?)
	local cells = GridUtil.occupiedCells(gx, gz, footprint, rotation)
	for k in pairs(cells) do
		if occupancy[k] then
			return false, occupancy[k]
		end
	end
	return true, nil
end

-- ====================================================================
-- gridToWorld — used by HarborVisualController to position cloned Models.
--
-- Returns a CFrame at the *footprint's bottom-center on the plot plate*,
-- already rotated by `rotation` around Y. A Model whose PrimaryPart sits
-- at its footprint bottom-center can be PivotTo'd directly to this CFrame.
--
-- footprint axes are pre-swapped here for 90/270° rotations so the
-- returned position centers the rotated footprint correctly. The caller
-- still passes the unrotated footprint from BuildingCatalog.
-- ====================================================================
function GridUtil.gridToWorld(plotOrigin: CFrame, gridX: number, gridZ: number, footprint: {number}, rotation: number): CFrame
	local w, d = footprint[1], footprint[2]
	if rotation == 90 or rotation == 270 then
		w, d = d, w
	end
	local local_ = GridUtil.gridToLocal(gridX, gridZ)
	local PLATE_TOP = GameConfig.Harbor.PlotPlateTopStuds
	local centerX = local_.X + (w * CELL) / 2
	local centerZ = local_.Z + (d * CELL) / 2
	return plotOrigin
		* CFrame.new(centerX, PLATE_TOP, centerZ)
		* CFrame.Angles(0, math.rad(rotation), 0)
end

-- Place a building so its bbox bottom-center sits on plateCF (position + Y rotation).
-- Does not rely on Model pivot or PrimaryPart — fixes bbox-center sink.
function GridUtil.placeModelOnPlate(model: Model, plateCF: CFrame)
	-- 1) Raise/lower so bbox bottom meets plate surface Y.
	local bbCF, bbSize = model:GetBoundingBox()
	local SURFACE_EPS = 0.05
	local lift = plateCF.Position.Y - (bbCF.Position.Y - bbSize.Y / 2) + SURFACE_EPS
	if math.abs(lift) > 0.001 then
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CFrame = desc.CFrame + Vector3.new(0, lift, 0)
			end
		end
	end

	-- 2) Slide XZ so bottom-center matches plate footprint center.
	bbCF, bbSize = model:GetBoundingBox()
	local pivotPos = Vector3.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2, bbCF.Position.Z)
	local xz = Vector3.new(plateCF.Position.X - pivotPos.X, 0, plateCF.Position.Z - pivotPos.Z)
	if xz.Magnitude > 0.001 then
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CFrame = desc.CFrame + xz
			end
		end
		pivotPos += xz
	end

	-- 3) Rotate around footprint bottom-center to match building rotation.
	local _, targetRy, _ = plateCF:ToEulerAnglesYXZ()
	local rot = CFrame.Angles(0, targetRy, 0)
	local pivotCF = CFrame.new(pivotPos)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CFrame = pivotCF * rot * pivotCF:Inverse() * desc.CFrame
		end
	end
end

GridUtil.CELLS_PER_AXIS = CELLS_PER_AXIS
GridUtil.CELL = CELL
GridUtil.PLOT = PLOT
GridUtil.PLATE_TOP = GameConfig.Harbor.PlotPlateTopStuds

return GridUtil
