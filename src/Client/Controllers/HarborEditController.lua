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
})

function HarborEditController:KnitStart()
	local HarborService = Knit.GetService("HarborService")
	HarborService.PlotAssigned:Connect(function(origin, size)
		self._plotOrigin = origin
		self._plotSize = size
	end)

	-- World-click placement: left-click anywhere outside UI confirms the
	-- current ghost. Much faster than reaching for the "Place" button on PC.
	-- gameProcessedEvent is true when the click was over a UI element, so
	-- this never steals clicks from buttons.
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not self._active then return end
		if not self._kind then return end  -- nothing selected
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
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
		self._ui = HarborEditUI.show(catalog,
			function(kind) self:_selectKind(kind) end,
			function() self._rotation = (self._rotation + 90) % 360 end,
			function() self:_confirm() end,
			function() self:_close() end
		)
		self:_startGhostLoop()
	end)
end

function HarborEditController:_close()
	self._active = false
	if self._ui then self._ui.close(); self._ui = nil end
	if self._ghost then self._ghost:Destroy(); self._ghost = nil end
	if self._heartbeatConn then self._heartbeatConn:Disconnect(); self._heartbeatConn = nil end
	self._kind = nil
end

function HarborEditController:_selectKind(kind: string)
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

-- Heartbeat: place the ghost at the player's current targeted grid cell.
-- We project the camera-forward onto a horizontal plane at plot height.
function HarborEditController:_startGhostLoop()
	if self._heartbeatConn then self._heartbeatConn:Disconnect() end
	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		if not self._active or not self._ghost or not self._kind or not self._plotOrigin then return end

		local mouse = Players.LocalPlayer:GetMouse()
		local hit = mouse.Hit -- world-space CFrame the cursor is over
		-- Convert to plot-local. Plot origin is the corner of the plot.
		local local_ = self._plotOrigin:PointToObjectSpace(hit.Position)
		-- Snap to grid.
		local gx, gz = GridUtil.snap(Vector3.new(local_.X, 0, local_.Z))
		-- Clamp to plot bounds so the ghost can't fly off.
		local def = self._catalog[self._kind]
		local w, d = def.footprint[1], def.footprint[2]
		if self._rotation == 90 or self._rotation == 270 then w, d = d, w end
		gx = math.clamp(gx, 0, GridUtil.CELLS_PER_AXIS - w)
		gz = math.clamp(gz, 0, GridUtil.CELLS_PER_AXIS - d)
		local localPos = GridUtil.gridToLocal(gx, gz)
		local sizeStuds = Vector3.new(w * GridUtil.CELL, 8, d * GridUtil.CELL)
		self._ghost.Size = sizeStuds
		self._ghost.CFrame = self._plotOrigin * CFrame.new(localPos.X + sizeStuds.X / 2, sizeStuds.Y / 2, localPos.Z + sizeStuds.Z / 2)
		-- Stash the snapped coords on the part so :_confirm can read them
		-- without recomputing.
		self._ghost:SetAttribute("gx", gx)
		self._ghost:SetAttribute("gz", gz)
	end)
end

function HarborEditController:_confirm()
	if not self._ghost or not self._kind then return end
	local gx = self._ghost:GetAttribute("gx") :: number
	local gz = self._ghost:GetAttribute("gz") :: number
	local HarborService = Knit.GetService("HarborService")
	HarborService:Place(self._kind, gx, gz, self._rotation):andThen(function(res)
		if not res.ok then
			warn("[Harbor] Place failed:", res.reason)
		end
	end)
end

return HarborEditController
