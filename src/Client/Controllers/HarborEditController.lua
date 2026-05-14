--!strict
-- HarborEditController.lua
-- Build mode. Renders a translucent "ghost" preview part at the cursor's
-- snapped grid position. Confirm calls HarborService:Place which is fully
-- server-validated. We do client-side validation just for UX (red ghost when
-- placement would fail) — the source of truth is the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local Players          = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GridUtil = require(ReplicatedStorage.Shared.Util.GridUtil)
local HarborEditUI = require(script.Parent.Parent.UI.HarborEditUI)

local HarborEditController = Knit.CreateController({
	Name = "HarborEditController",
	_active = false,
	_ui = nil :: any,
	_ghost = nil :: BasePart?,
	_kind = nil :: string?,
	_rotation = 0,
	_plotOrigin = nil :: CFrame?,
	_plotSize = 80,
	_catalog = nil :: any,
	_heartbeatConn = nil :: RBXScriptConnection?,
	_demolishing = false,   -- in demolish mode: world clicks remove buildings
	_demolishHighlight = nil :: Highlight?,
})

function HarborEditController:KnitStart()
	local HarborService = Knit.GetService("HarborService")
	HarborService.PlotAssigned:Connect(function(origin, size)
		self._plotOrigin = origin
		self._plotSize = size
	end)

	-- World-click handler. Branches by current mode:
	--   * demolish on: raycast and remove the building hit.
	--   * placement (kind selected): confirm the ghost.
	-- gameProcessedEvent skip ensures clicks on UI panels don't fire either.
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not self._active then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		if self._demolishing then
			self:_doDemolish()
		elseif self._kind then
			self:_confirm()
		end
	end)
end

function HarborEditController:Toggle()
	if self._active then self:_close() else self:_open() end
end

function HarborEditController:_open()
	local HarborService = Knit.GetService("HarborService")
	HarborService:GetBuildingCatalog():andThen(function(catalog)
		self._catalog = catalog
		self._active = true
		-- Hide the HUD while editing — the build palette and action bar
		-- both anchor to the bottom of the screen and were overlapping.
		Knit.GetController("HUDController"):SetVisible(false)
		self._ui = HarborEditUI.show(catalog,
			function(kind) self:_selectKind(kind) end,
			function() self._rotation = (self._rotation + 90) % 360 end,
			function() self:_confirm() end,
			function() self:_toggleDemolish() end,
			function() self:_close() end
		)
		-- One Highlight Instance is enough — we re-target it as the cursor
		-- moves over different buildings. Parented to Workspace because
		-- Roblox requires Highlights to be a descendant of the workspace
		-- or PlayerGui to render; Workspace is the simplest.
		local hi = Instance.new("Highlight")
		hi.Name = "DemolishHover"
		hi.FillColor = Color3.fromRGB(255, 70, 70)
		hi.FillTransparency = 0.6
		hi.OutlineColor = Color3.fromRGB(255, 255, 255)
		hi.OutlineTransparency = 0
		hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hi.Enabled = false
		hi.Parent = Workspace
		self._demolishHighlight = hi
		self:_startEditLoop()
	end)
end

-- Demolish mode toggles a flag and clears the placement ghost. While on,
-- world clicks raycast onto placed buildings and remove the one hit.
function HarborEditController:_toggleDemolish()
	self._demolishing = not self._demolishing
	if self._demolishing then
		-- Drop the placement ghost while demolishing — they're mutually
		-- exclusive interactions.
		if self._ghost then self._ghost:Destroy(); self._ghost = nil end
		self._kind = nil
	end
	if self._ui then self._ui.setDemolishActive(self._demolishing) end
end

function HarborEditController:_doDemolish()
	local part = self:_raycastForAnchor()
	if not part then return end
	self:_remove(part.Name)
end

function HarborEditController:_remove(uid: string)
	local HarborService = Knit.GetService("HarborService")
	HarborService:Remove(uid):andThen(function(res)
		if not res.ok then
			warn("[HarborEdit] Remove failed:", res.reason)
		end
	end)
end

function HarborEditController:_close()
	self._active = false
	if self._ui then self._ui.close(); self._ui = nil end
	if self._ghost then self._ghost:Destroy(); self._ghost = nil end
	if self._heartbeatConn then self._heartbeatConn:Disconnect(); self._heartbeatConn = nil end
	if self._demolishHighlight then self._demolishHighlight:Destroy(); self._demolishHighlight = nil end
	self._kind = nil
	self._demolishing = false
	-- Restore the HUD that we hid in _open.
	Knit.GetController("HUDController"):SetVisible(true)
end

function HarborEditController:_selectKind(kind: string)
	-- Picking a building cancels demolish mode (mutually exclusive).
	if self._demolishing then
		self._demolishing = false
		if self._ui then self._ui.setDemolishActive(false) end
	end
	self._kind = kind
	if self._ghost then self._ghost:Destroy() end
	-- Build a translucent placeholder. Real game would clone a model from
	-- ReplicatedStorage.Assets.Buildings[kind].
	local def = self._catalog[kind]
	if not def then return end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0.5
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(120, 200, 220)
	local w, d = def.footprint[1], def.footprint[2]
	part.Size = Vector3.new(w * GridUtil.CELL, 8, d * GridUtil.CELL)
	part.Parent = Workspace
	self._ghost = part
end

-- Heartbeat: positions the placement ghost AND updates the demolish hover
-- highlight. Single connection so we don't pay Heartbeat overhead twice.
function HarborEditController:_startEditLoop()
	if self._heartbeatConn then self._heartbeatConn:Disconnect() end
	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		if not self._active then return end
		if self._demolishing then
			self:_updateDemolishHover()
		else
			if self._demolishHighlight and self._demolishHighlight.Adornee then
				self._demolishHighlight.Enabled = false
				self._demolishHighlight.Adornee = nil
			end
			self:_updateGhost()
		end
	end)
end

-- Demolish hover: raycast under cursor, find the hit anchor's uid, look up
-- the matching visible model in HarborVisualController, set as Highlight
-- adornee. Same exclude-the-visuals filter as _doDemolish so we hit the
-- invisible server anchor instead of the decorative client model.
function HarborEditController:_updateDemolishHover()
	local hi = self._demolishHighlight
	if not hi then return end
	local part = self:_raycastForAnchor()
	if not part then
		hi.Enabled = false
		hi.Adornee = nil
		return
	end
	local uid = part.Name
	local HarborVisualController = Knit.GetController("HarborVisualController")
	local model = HarborVisualController:GetVisualModel(uid)
	if not model then
		-- No visual found (race during stream-in) — fall back to the anchor
		-- so the player at least sees *something* hovering.
		hi.Adornee = part
	else
		hi.Adornee = model
	end
	hi.Enabled = true
end

-- Encapsulates the raycast used by both demolish hover and demolish click.
-- Excludes the HarborVisuals_Client_* folders (decorative cloned visuals)
-- so the ray always lands on the invisible server anchor or terrain/plate.
function HarborEditController:_raycastForAnchor(): BasePart?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local mouse = Players.LocalPlayer:GetMouse()
	local screenRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local exclude: { Instance } = {}
	if Players.LocalPlayer.Character then table.insert(exclude, Players.LocalPlayer.Character) end
	for _, child in ipairs(Workspace:GetChildren()) do
		local name = child.Name
		if name:sub(1, #"HarborVisuals_Client_") == "HarborVisuals_Client_" then
			table.insert(exclude, child)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(screenRay.Origin, screenRay.Direction.Unit * 1000, params)
	if not result then return nil end
	local part = result.Instance
	if not part:GetAttribute("kind") then return nil end
	return part
end

-- Ghost positioning. Same logic as before, plus a client-side overlap
-- preview: ghost tints red if the snapped cell collides with any building
-- already on the local plot. Server still re-validates on Place, but this
-- keeps the player from wasting clicks on visibly-occupied cells.
function HarborEditController:_updateGhost()
	if not self._ghost or not self._kind or not self._plotOrigin then return end
	local mouse = Players.LocalPlayer:GetMouse()
	local hit = mouse.Hit
	local local_ = self._plotOrigin:PointToObjectSpace(hit.Position)
	local gx, gz = GridUtil.snap(Vector3.new(local_.X, 0, local_.Z))
	local def = self._catalog[self._kind]
	local w, d = def.footprint[1], def.footprint[2]
	if self._rotation == 90 or self._rotation == 270 then w, d = d, w end
	gx = math.clamp(gx, 0, GridUtil.CELLS_PER_AXIS - w)
	gz = math.clamp(gz, 0, GridUtil.CELLS_PER_AXIS - d)
	local localPos = GridUtil.gridToLocal(gx, gz)
	local sizeStuds = Vector3.new(w * GridUtil.CELL, 8, d * GridUtil.CELL)
	self._ghost.Size = sizeStuds
	self._ghost.CFrame = self._plotOrigin * CFrame.new(localPos.X + sizeStuds.X / 2, sizeStuds.Y / 2, localPos.Z + sizeStuds.Z / 2)
	self._ghost:SetAttribute("gx", gx)
	self._ghost:SetAttribute("gz", gz)

	-- Tint red if the cell would collide with an existing building. This
	-- consults the client's known visuals (HarborVisualController stores them
	-- on update); it's authoritative for the player's own plot because every
	-- Place/Remove pushes a HarborVisualUpdate before this snapshot loops.
	local HarborVisualController = Knit.GetController("HarborVisualController")
	local mine = HarborVisualController:GetBuildingsForOwner(Players.LocalPlayer.UserId)
	local occ = GridUtil.buildOccupancy(mine)
	local ok = GridUtil.checkPlacement(occ, gx, gz, def.footprint, self._rotation)
	self._ghost.Color = ok and Color3.fromRGB(120, 200, 220) or Color3.fromRGB(220, 100, 100)
end

function HarborEditController:_confirm()
	if not self._ghost or not self._kind then return end
	local gx = self._ghost:GetAttribute("gx") :: number
	local gz = self._ghost:GetAttribute("gz") :: number
	local kind = self._kind
	local HarborService = Knit.GetService("HarborService")
	HarborService:Place(kind, gx, gz, self._rotation):andThen(function(res)
		if not res.ok then
			if res.reason == "overlap" and res.conflictUid then
				warn(("[Harbor] Place failed: overlap with %s (cell %d,%d). Demolish that to free the spot."):format(res.conflictUid, gx, gz))
			else
				warn("[Harbor] Place failed:", res.reason)
			end
		end
	end)
end

return HarborEditController
