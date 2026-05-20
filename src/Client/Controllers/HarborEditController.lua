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
local GuiService       = game:GetService("GuiService")
local SoundService     = game:GetService("SoundService")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local GridUtil   = require(ReplicatedStorage.Shared.Util.GridUtil)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local HarborEditUI = require(script.Parent.Parent.UI.HarborEditUI)
local UIUtil = require(script.Parent.Parent.UI.UIUtil)

-- Finds or lazily creates the coin-clink Sound in SoundService.
-- SoundId is intentionally blank until a real asset is uploaded; Play() on
-- an empty SoundId is a silent no-op so the call site doesn't need to guard.
local function findOrMakeCoinClinkSound(): Sound
	local existing = SoundService:FindFirstChild("CoinClink")
	if existing and existing:IsA("Sound") then return existing :: Sound end
	local s = Instance.new("Sound")
	s.Name     = "CoinClink"
	s.SoundId  = ""   -- TODO: replace with real coin-clink rbxasset id
	s.Volume   = 0.6
	s.Parent   = SoundService
	return s
end

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
	_upgrading = false,     -- in upgrade mode: world clicks upgrade the hit building
	_hoverHighlight = nil :: Highlight?,
})

function HarborEditController:KnitStart()
	local HarborService = Knit.GetService("HarborService")
	HarborService.PlotAssigned:Connect(function(origin, size)
		self._plotOrigin = origin
		self._plotSize = size
	end)

	-- Placement / upgrade confirmation FX. Coin-clink always plays; particle
	-- burst is skipped when the player has ReducedMotionEnabled (accessibility).
	HarborService.HarborVisualUpdate:Connect(function(_uid: string, _kind: string, _tier: number, worldPos: Vector3)
		findOrMakeCoinClinkSound():Play()
		if not GuiService.ReducedMotionEnabled then
			self:_burstPlacementFX(worldPos)
		end
	end)

	-- World-click handler. Branches by current mode:
	--   * demolish on: raycast and remove the building hit.
	--   * upgrade on: raycast and upgrade the building hit.
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
		elseif self._upgrading then
			self:_doUpgrade()
		elseif self._kind then
			self:_confirm()
		end
	end)
end

function HarborEditController:Toggle()
	if self._active then self:_close() else self:_open() end
end

function HarborEditController:Close()
	if self._active then self:_close() end
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
			function() self:_toggleUpgrade() end,
			function() self:_close() end
		)
		-- One Highlight Instance shared by demolish + upgrade hover. We just
		-- re-tint it on mode change so we don't pay for two of them. Parented
		-- to Workspace because Highlights must descend from Workspace or
		-- PlayerGui to render.
		local hi = Instance.new("Highlight")
		hi.Name = "HarborEditHover"
		hi.FillTransparency = 0.6
		hi.OutlineColor = Color3.fromRGB(255, 255, 255)
		hi.OutlineTransparency = 0
		hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hi.Enabled = false
		hi.Parent = Workspace
		self._hoverHighlight = hi
		self:_startEditLoop()
	end)
end

-- Demolish mode toggles a flag and clears the placement ghost. While on,
-- world clicks raycast onto placed buildings and remove the one hit.
function HarborEditController:_toggleDemolish()
	self._demolishing = not self._demolishing
	if self._demolishing then
		-- Drop the placement ghost and cancel upgrade — mutually exclusive.
		if self._ghost then self._ghost:Destroy(); self._ghost = nil end
		self._kind = nil
		if self._upgrading then
			self._upgrading = false
			if self._ui then self._ui.setUpgradeActive(false) end
		end
	end
	if self._ui then self._ui.setDemolishActive(self._demolishing) end
end

-- Upgrade mode mirrors demolish but calls HarborService:Upgrade. Modes are
-- exclusive — turning upgrade on cancels demolish (and vice versa) so the
-- next world click has exactly one interpretation.
function HarborEditController:_toggleUpgrade()
	self._upgrading = not self._upgrading
	if self._upgrading then
		if self._ghost then self._ghost:Destroy(); self._ghost = nil end
		self._kind = nil
		if self._demolishing then
			self._demolishing = false
			if self._ui then self._ui.setDemolishActive(false) end
		end
	end
	if self._ui then self._ui.setUpgradeActive(self._upgrading) end
end

function HarborEditController:_doDemolish()
	local part = self:_raycastForAnchor()
	if not part then return end
	local uid = part.Name
	local kind = part:GetAttribute("kind") or "building"
	-- Demolition is destructive and unrefunded — surface a confirm popup
	-- so a stray click can't wipe a tier-3 building. Cancel keeps the
	-- player in demolish mode for another attempt.
	self:_confirmDemolish(uid, tostring(kind))
end

function HarborEditController:_doUpgrade()
	local part = self:_raycastForAnchor()
	if not part then return end
	local uid = part.Name
	local HarborService = Knit.GetService("HarborService")
	HarborService:Upgrade(uid):andThen(function(res)
		if not res.ok then
			warn("[HarborEdit] Upgrade failed:", res.reason)
		end
	end)
end

-- Confirmation popup before destroying a building. Dark backdrop +
-- centered panel with Cancel/Demolish buttons. Demolish is the dangerous
-- action (red Danger variant); Cancel is the default focus-friendly
-- secondary. Built inline because this is the only confirm dialog in
-- the codebase — when a second use site appears, factor out into UI/.
function HarborEditController:_confirmDemolish(uid: string, kind: string)
	local P = UIUtil.Palette
	local gui, _ = UIUtil.makeScreenGui("DemolishConfirm")
	gui.DisplayOrder = 20  -- above HUD and tutorial dialogue (5)

	-- Dark backdrop catches input behind the panel.
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = P.Shadow
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Parent = gui

	local panel = UIUtil.makePanel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 180),
	})
	panel.Parent = gui

	local title = UIUtil.makeLabel("Demolish " .. kind .. "?", "title", {
		Position = UDim2.new(0, 20, 0, 18),
		Size = UDim2.new(1, -40, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	title.Parent = panel

	local body = UIUtil.makeLabel(
		"This is permanent and you won't get the coins back.",
		"body",
		{
			Position = UDim2.new(0, 20, 0, 52),
			Size = UDim2.new(1, -40, 0, 56),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = P.CreamSoft,
		}
	)
	body.Parent = panel

	local function close()
		gui:Destroy()
	end

	local cancelBtn = UIUtil.makeButton("Cancel", function() close() end, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 20, 1, -18),
		Size = UDim2.fromOffset(140, 44),
		variant = "ghost",
	})
	cancelBtn.Parent = panel

	local confirmBtn = UIUtil.makeButton("Demolish", function()
		close()
		self:_remove(uid)
	end, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -18),
		Size = UDim2.fromOffset(140, 44),
		variant = "danger",
	})
	confirmBtn.Parent = panel
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
	if self._hoverHighlight then self._hoverHighlight:Destroy(); self._hoverHighlight = nil end
	self._kind = nil
	self._demolishing = false
	self._upgrading = false
	-- Restore the HUD that we hid in _open.
	Knit.GetController("HUDController"):SetVisible(true)
end

function HarborEditController:_selectKind(kind: string)
	-- Picking a building cancels both modes (mutually exclusive).
	if self._demolishing then
		self._demolishing = false
		if self._ui then self._ui.setDemolishActive(false) end
	end
	if self._upgrading then
		self._upgrading = false
		if self._ui then self._ui.setUpgradeActive(false) end
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
			self:_updateHoverHighlight(Color3.fromRGB(255, 70, 70))
		elseif self._upgrading then
			self:_updateHoverHighlight(Color3.fromRGB(220, 180, 88))
		else
			if self._hoverHighlight and self._hoverHighlight.Adornee then
				self._hoverHighlight.Enabled = false
				self._hoverHighlight.Adornee = nil
			end
			self:_updateGhost()
		end
	end)
end

-- Hover highlight shared by demolish (red) and upgrade (gold). Re-tinted
-- on every Heartbeat so toggling modes immediately re-colors. Same
-- exclude-the-visuals filter as _doDemolish so we hit the invisible server
-- anchor instead of the decorative client model.
function HarborEditController:_updateHoverHighlight(tint: Color3)
	local hi = self._hoverHighlight
	if not hi then return end
	hi.FillColor = tint
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
-- Walk up from a hit instance to find a building anchor or building model,
-- then return the server anchor Part (Name=uid, "kind" attribute set).
-- Raycasting against the visible model (full-size, easy to aim at) is
-- more reliable than hunting the 1×1×1 invisible server anchor directly.
function HarborEditController:_raycastForAnchor(): BasePart?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local mouse = Players.LocalPlayer:GetMouse()
	local screenRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = Players.LocalPlayer.Character
		and { Players.LocalPlayer.Character } or {}
	local result = Workspace:Raycast(screenRay.Origin, screenRay.Direction.Unit * 1000, params)
	if not result then return nil end

	-- Walk up the hit instance until we find something with a "kind" attribute.
	-- The attribute lives on the server anchor Part OR on the visual Model.
	local inst: Instance? = result.Instance
	while inst and inst ~= Workspace do
		if inst:GetAttribute("kind") then
			if inst:IsA("BasePart") then
				-- Hit the server anchor directly.
				return inst
			elseif inst:IsA("Model") then
				-- Hit a visual model — find its corresponding server anchor by uid.
				local uid = inst.Name
				for _, folder in ipairs(Workspace:GetChildren()) do
					if folder.Name:sub(1, 5) == "Plot_" then
						local anchor = folder:FindFirstChild(uid)
						if anchor and anchor:IsA("BasePart") then
							return anchor
						end
					end
				end
				return nil
			end
		end
		inst = inst.Parent
	end
	return nil
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
	local sizeStuds = Vector3.new(w * GridUtil.CELL, 8, d * GridUtil.CELL)
	self._ghost.Size = sizeStuds
	-- Match GridUtil.gridToWorld: footprint bottom-center on the plate, then lift ghost center.
	local worldCF = GridUtil.gridToWorld(self._plotOrigin, gx, gz, def.footprint, self._rotation)
	self._ghost.CFrame = worldCF * CFrame.new(0, sizeStuds.Y / 2, 0)
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

-- Brief gold-sparkle burst at `worldPos`. Caller is responsible for checking
-- ReducedMotionEnabled before calling — this function always emits particles.
function HarborEditController:_burstPlacementFX(worldPos: Vector3)
	local VT = GameConfig.Harbor.VisualTuning
	local host = Instance.new("Part")
	host.Anchored     = true
	host.CanCollide   = false
	host.CanQuery     = false
	host.CanTouch     = false
	host.Transparency = 1
	host.Size         = Vector3.new(1, 1, 1)
	host.Position     = worldPos + Vector3.new(0, 2, 0)
	host.Parent       = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 180)),
	})
	emitter.LightEmission   = 0.8
	emitter.LightInfluence  = 0
	emitter.Lifetime        = NumberRange.new(0.5, 1.0)
	emitter.Speed           = NumberRange.new(8, 14)
	emitter.SpreadAngle     = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate   = 0   -- emit on demand only
	emitter.Parent = host
	emitter:Emit(VT.ParticleBurstCount)
	-- Destroy after the longest particle lifetime has drained.
	task.delay(VT.ParticleBurstDuration + 1.0, function()
		if host.Parent then host:Destroy() end
	end)
end

return HarborEditController
