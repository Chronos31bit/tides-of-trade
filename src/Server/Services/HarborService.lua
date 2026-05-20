--!strict
-- HarborService.lua
-- Owns plot allocation and building placement / upgrade / removal. All grid
-- math is shared with the client (GridUtil) but only the server's answer is
-- authoritative — clients can preview placement freely, but the server
-- re-runs every check before mutating the profile.

local Players          = game:GetService("Players")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Knit             = require(ReplicatedStorage.Packages.Knit)
local GameConfig       = require(ReplicatedStorage.Shared.Config.GameConfig)
local BuildingCatalog  = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local GridUtil         = require(ReplicatedStorage.Shared.Util.GridUtil)
local UidUtil          = require(ReplicatedStorage.Shared.Util.UidUtil)
local RateLimiter      = require(ReplicatedStorage.Shared.Util.RateLimiter)

-- ====================================================================
-- BUILDING_ANCHOR_TAG — CollectionService tag on every server-side
-- invisible interaction anchor. The client HarborVisualController uses
-- this to discover anchors (so it can fade-attach visuals at the same
-- location), and ShopController / AquariumController / RodService still
-- pick up the anchor's ProximityPrompt without code change.
-- ====================================================================
local BUILDING_ANCHOR_TAG = "BuildingAnchor"

local HarborService = Knit.CreateService({
	Name = "HarborService",
	Client = {
		PlotAssigned     = Knit.CreateSignal(),  -- (originCFrame, sizeStuds)
		BuildingPlaced   = Knit.CreateSignal(),  -- (building)
		BuildingRemoved  = Knit.CreateSignal(),  -- (uid)
		BuildingUpgraded = Knit.CreateSignal(),  -- (uid, newTier)
		-- Fires to the placing/upgrading player only. Carries enough context
		-- for WorldFXController/HarborEditController to play placement FX.
		-- (uid: string, kind: string, tier: number, worldPos: Vector3)
		HarborVisualUpdate = Knit.CreateSignal(),
	},

	-- Server-only BindableEvents for sibling services.
	-- Named to match what QuestService and HarborVisualService listen for.
	-- Connect via .Event:Connect(...) — BindableEvent API.
	BuildingPlacedServer   = Instance.new("BindableEvent"),  -- (player, building)
	BuildingUpgradedServer = Instance.new("BindableEvent"),  -- (player, building, oldTier, newTier)
	PassiveIncomeServer    = Instance.new("BindableEvent"),  -- (player, coinsGranted)
	OnBuildingRemoved      = Instance.new("BindableEvent"),  -- (player, uid)
	OnPlotReleased         = Instance.new("BindableEvent"),  -- (player)

	-- internal state
	_plotOrigins = {}, -- [Player] -> CFrame (top-left corner of their plot in world)
	_plotFolders = {}, -- [Player] -> Instance (Folder for invisible anchor parts)
	_buildLimiter = nil :: any,
	_incomeAccumulator = {}, -- [Player] -> seconds since last income tick (debounced by lifecycle)
})

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function HarborService:KnitInit()
	self._buildLimiter = RateLimiter.new(GameConfig.AntiExploit.MaxBuildOpsPerMinute, 60)
end

function HarborService:KnitStart()
	-- We need PlayerDataService loaded before we can hand out plots.
	local PlayerDataService = Knit.GetService("PlayerDataService")

	local function setupPlayer(player: Player)
		local data = PlayerDataService:WaitForProfile(player, 30)
		if not data then return end
		self:_assignPlot(player)
		self:_spawnExistingBuildings(player)
		-- Teleport to their plot on every spawn so they land on the dock
		-- plate rather than falling into the water.
		player.CharacterAdded:Connect(function(character)
			task.spawn(function() self:_spawnOnPlot(player, character) end)
		end)
		if player.Character then
			task.spawn(function() self:_spawnOnPlot(player, player.Character) end)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(setupPlayer, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(setupPlayer, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:_releasePlot(player)
		self._buildLimiter:reset(player)
	end)

	-- Income tick: every IncomeTickSeconds, every player earns from their buildings.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Harbor.IncomeTickSeconds)
			self:_payAllPassiveIncome()
		end
	end)
end

-- ====================================================================
-- SPAWN HELPER
-- ====================================================================
function HarborService:_spawnOnPlot(player: Player, character: Model)
	local origin = self._plotOrigins[player]
	if not origin then return end
	-- WaitForChild handles the brief window between CharacterAdded firing
	-- and the HumanoidRootPart being parented into the character model.
	local hrp = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not hrp then return end
	-- Small yield so the physics engine has registered the plate before we
	-- move the character onto it; without it the character can fall through.
	task.wait(0.1)
	if not player.Parent then return end  -- player left during yield
	hrp.CFrame = origin * CFrame.new(
		GameConfig.Harbor.PlotSizeStuds / 2,
		6,
		GameConfig.Harbor.PlotSizeStuds / 2
	)
end

-- ====================================================================
-- PLOT ALLOCATION
-- ====================================================================
-- Plots are arranged in a 4x4 grid in the world starting at world (0,0,0).
-- For up to 16 concurrent players this trivially scales; beyond that, swap
-- this for a free-list. StreamingEnabled keeps far-away plots cheap.
local PLOT_GRID_DIM = 4
local PLOT_SPACING_STUDS = GameConfig.Harbor.PlotSizeStuds + 40 -- 40 stud canal between plots

local function indexToOrigin(index: number): CFrame
	-- index 0..(PLOT_GRID_DIM^2 - 1) -> world position
	local row = math.floor(index / PLOT_GRID_DIM)
	local col = index % PLOT_GRID_DIM
	-- Plot origin = top-left corner of the plot in world (raised above water).
	return CFrame.new(col * PLOT_SPACING_STUDS, GameConfig.Harbor.PlotElevationStuds, row * PLOT_SPACING_STUDS)
end

function HarborService:_assignPlot(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)

	local assigned: number
	if data and data.plotIndex then
		-- Returning player: restore their saved slot so the same player always
		-- gets the same patch of coastline, even across server restarts.
		assigned = data.plotIndex
	else
		-- First join: find a free slot with a linear scan. With StreamingEnabled,
		-- far-away plots are dormant so the cap rarely matters in practice.
		local taken: {[number]: boolean} = {}
		for _, origin in pairs(self._plotOrigins) do
			local col = math.floor(origin.X / PLOT_SPACING_STUDS + 0.5)
			local row = math.floor(origin.Z / PLOT_SPACING_STUDS + 0.5)
			taken[row * PLOT_GRID_DIM + col] = true
		end
		assigned = #Players:GetPlayers() + 100  -- overflow default if grid is full
		for i = 0, PLOT_GRID_DIM * PLOT_GRID_DIM - 1 do
			if not taken[i] then
				assigned = i
				break
			end
		end
		if data then
			data.plotIndex = assigned
		end
	end

	local origin = indexToOrigin(assigned)
	self._plotOrigins[player] = origin

	-- Build a server-side folder to hold visual building parts. Real games
	-- would clone meshes from ReplicatedStorage.Assets.Buildings.<kind>; here
	-- we placeholder with simple parts so the project boots in Studio without
	-- art assets.
	local folder = Instance.new("Folder")
	folder.Name = ("Plot_%d_%s"):format(assigned, player.Name)
	folder.Parent = Workspace
	self._plotFolders[player] = folder

	-- Plot footprint plate — dock surface. Top = PlotElevationStuds + 1.5 studs.
	local plate = Instance.new("Part")
	plate.Anchored = true
	plate.CanCollide = true
	plate.Size = Vector3.new(GameConfig.Harbor.PlotSizeStuds, 1, GameConfig.Harbor.PlotSizeStuds)
	-- Plate center Y: PlotPlateTopStuds is the surface; plate is 1 stud thick.
	local plateCenterY = GameConfig.Harbor.PlotPlateTopStuds - 0.5
	plate.Position = origin.Position + Vector3.new(GameConfig.Harbor.PlotSizeStuds / 2, plateCenterY, GameConfig.Harbor.PlotSizeStuds / 2)
	plate.Material = Enum.Material.WoodPlanks
	plate.Color = Color3.fromRGB(120, 90, 60)
	plate.Name = "PlotPlate"
	plate.Parent = folder

	-- Owner nameplate floating over the plot so visitors know whose harbor
	-- they're on. BillboardGui scales by distance for free legibility.
	local nameTag = Instance.new("Part")
	nameTag.Anchored = true
	nameTag.CanCollide = false
	nameTag.Transparency = 1
	nameTag.Size = Vector3.new(1, 1, 1)
	nameTag.Position = origin.Position + Vector3.new(GameConfig.Harbor.PlotSizeStuds / 2, 14, GameConfig.Harbor.PlotSizeStuds / 2)
	nameTag.Name = "NameTag"
	nameTag.Parent = folder
	local bb = Instance.new("BillboardGui")
	bb.Adornee = nameTag
	bb.Size = UDim2.fromOffset(220, 40)
	bb.AlwaysOnTop = true
	bb.Parent = nameTag
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 22
	lbl.TextColor3 = Color3.fromRGB(244, 230, 200)
	lbl.TextStrokeTransparency = 0.5
	lbl.Text = ("%s's Harbor"):format(player.DisplayName)
	lbl.Parent = bb

	self.Client.PlotAssigned:Fire(player, origin, GameConfig.Harbor.PlotSizeStuds)
end

function HarborService:_releasePlot(player: Player)
	-- Notify visual service BEFORE we drop our own references so it can
	-- still resolve the player's UserId from `player` (which is valid until
	-- this function returns, even mid-PlayerRemoving).
	self.OnPlotReleased:Fire(player)
	self._plotOrigins[player] = nil
	local folder = self._plotFolders[player]
	if folder then folder:Destroy() end
	self._plotFolders[player] = nil
end

-- ====================================================================
-- VISUAL SPAWN — invisible interaction anchor only.
--
-- Per Path A of the harbor visual system, the *visible* building model is
-- cloned client-side by HarborVisualController. This server function now
-- creates only an invisible 1×1×1 stud anchor at the building's grid
-- position so:
--   1. ProximityPrompts (Aquarium / Dock rod shop / Bait Shop) still live
--      on a server-replicated Part — visitors can interact with another
--      player's harbor without coupling to the client visual model.
--   2. The anchor is tagged BuildingAnchor + carries kind/tier attributes
--      + the building uid as its Name, so the client controller (and any
--      future server feature) can locate it via CollectionService.
-- ====================================================================
function HarborService:_spawnBuildingVisual(player: Player, building: any)
	local folder = self._plotFolders[player]; if not folder then return end
	local origin = self._plotOrigins[player]; if not origin then return end
	local def = BuildingCatalog[building.kind]; if not def then return end

	-- World CFrame at the footprint bottom-center (shared math with the client).
	local worldCF = GridUtil.gridToWorld(origin, building.gridX, building.gridZ, def.footprint, building.rotation)

	-- TODO: replace this invisible stub with a cloned Model from
	-- ReplicatedStorage.Assets.Buildings[building.kind] (one Model per tier,
	-- or a single Model whose PrimaryPart is scaled/recolored per tier).
	-- Each tier's visual must be obviously different from 30 studs away
	-- (pillar 3) — minimum 1.5× Scale per tier on the PrimaryPart.
	local anchor = Instance.new("Part")
	anchor.Name = building.uid
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = true   -- must be true so _raycastForAnchor (demolish/upgrade hover) can hit it
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	-- Anchor sits a bit above the plate so ProximityPrompts trigger range
	-- works naturally for players standing at ground level.
	anchor.CFrame = worldCF * CFrame.new(0, 2, 0)
	anchor:SetAttribute("kind", building.kind)
	anchor:SetAttribute("tier", building.tier)
	anchor:SetAttribute("ownerUserId", player.UserId)
	anchor.Parent = folder
	CollectionService:AddTag(anchor, BUILDING_ANCHOR_TAG)

	local function makePrompt(action: string, object: string)
		local p = Instance.new("ProximityPrompt")
		p.ActionText = action
		p.ObjectText = object
		p.HoldDuration = 0
		p.MaxActivationDistance = 12
		p.RequiresLineOfSight = false
		p.Parent = anchor
	end

	if building.kind == "Aquarium" then
		makePrompt("Open Aquarium", "Aquarium")
	elseif building.kind == "Smokehouse" then
		makePrompt("Open Smokehouse", "Smokehouse")
	elseif building.kind == "Dock" then
		-- At tier 1 the dock is still "broken" — show the repair prompt so the
		-- tutorial beat can be completed. The anchor is destroyed and respawned
		-- after the upgrade, so this prompt disappears automatically.
		if building.tier == 1 then
			local repairPrompt = Instance.new("ProximityPrompt")
			repairPrompt.ActionText    = "Repair Dock"
			repairPrompt.ObjectText    = "Dock"
			repairPrompt.HoldDuration  = 0
			repairPrompt.MaxActivationDistance = 12
			repairPrompt.RequiresLineOfSight   = false
			repairPrompt:SetAttribute("buildingUid", building.uid)
			repairPrompt.Parent = anchor
		end
		makePrompt("Buy Rod Upgrade", "Rod Shop")
	elseif building.kind == "BaitShop" then
		makePrompt("Open Bait Shop", "Bait Shop")
	end

	-- Tier upgrades are Harbor Edit only (one prompt per anchor — a world
	-- "Upgrade" prompt would hide Open Smokehouse / Open Aquarium / etc.).
end

function HarborService:_spawnExistingBuildings(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return end
	for _, b in ipairs(data.buildings) do
		self:_spawnBuildingVisual(player, b)
	end
end

function HarborService:_destroyBuildingVisual(player: Player, uid: string)
	local folder = self._plotFolders[player]; if not folder then return end
	local part = folder:FindFirstChild(uid)
	if part then part:Destroy() end
end

-- ====================================================================
-- PASSIVE INCOME
-- ====================================================================
function HarborService:_payAllPassiveIncome()
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local AquariumService = Knit.GetService("AquariumService")
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataService:GetProfile(player); if not data then continue end
		local total = 0
		for _, b in ipairs(data.buildings) do
			local def = BuildingCatalog[b.kind]; if not def then continue end
			local tier = def.tiers[b.tier]
			if tier and tier.incomePerTick then
				total += tier.incomePerTick
			end
		end
		if total > 0 then
			PlayerDataService:AddCoins(player, total, "harbor_income")
			self.PassiveIncomeServer:Fire(player, total)
		end
		-- Aquarium payouts handled in their own service since they're driven
		-- by stock rather than a flat per-tick number on the building.
		AquariumService:PayoutFor(player)
		Knit.GetService("SmokehouseService"):TickFor(player)
	end
end

-- ====================================================================
-- PLACEMENT VALIDATION (shared logic)
-- ====================================================================
-- Returns (ok, reason). Reasons let the client surface a useful tooltip
-- without leaking placement strategy.
function HarborService:_validatePlacement(player: Player, kind: string, gridX: number, gridZ: number, rotation: number): (boolean, string?)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return false, "no_profile" end

	local def = BuildingCatalog[kind]
	if not def then return false, "unknown_building" end

	if rotation ~= 0 and rotation ~= 90 and rotation ~= 180 and rotation ~= 270 then
		return false, "bad_rotation"
	end

	if #data.buildings >= GameConfig.Harbor.MaxBuildingsPerPlot then
		return false, "plot_full"
	end

	if not GridUtil.inBounds(gridX, gridZ, def.footprint, rotation) then
		return false, "out_of_bounds"
	end

	local occ = GridUtil.buildOccupancy(data.buildings)
	local ok, _conflictUid = GridUtil.checkPlacement(occ, gridX, gridZ, def.footprint, rotation)
	if not ok then return false, "overlap" end

	return true, nil
end

-- ====================================================================
-- CLIENT API
-- ====================================================================

-- Returns the catalog so the client can build its placement menu.
function HarborService.Client:GetBuildingCatalog(_player: Player): any
	return BuildingCatalog
end

function HarborService.Client:Place(player: Player, kind: string, gridX: number, gridZ: number, rotation: number): {ok: boolean, reason: string?, building: any?}
	local self = self.Server
	if not self._buildLimiter:check(player) then return { ok = false, reason = "rate_limit" } end

	local ok, reason = self:_validatePlacement(player, kind, gridX, gridZ, rotation)
	if not ok then return { ok = false, reason = reason } end

	local def = BuildingCatalog[kind] :: any
	local bldCfg = GameConfig.Buildings[kind]
	if not bldCfg then return { ok = false, reason = "unknown_building" } end
	local tier1Cost = bldCfg.tierCosts[1]

	local PlayerDataService = Knit.GetService("PlayerDataService")
	if tier1Cost > 0 and not PlayerDataService:TrySpendCoins(player, tier1Cost) then
		return { ok = false, reason = "not_enough_coins" }
	end

	local building = {
		uid = UidUtil.new("bld"),
		kind = kind,
		tier = 1,
		gridX = gridX,
		gridZ = gridZ,
		rotation = rotation,
		placedAt = os.time(),
	}
	if kind == "Smokehouse" then
		building.preserveSlots = {}
	end
	PlayerDataService:AddBuilding(player, building)
	self:_spawnBuildingVisual(player, building)
	self.Client.BuildingPlaced:Fire(player, building)
	self.BuildingPlacedServer:Fire(player, building)
	local origin = self._plotOrigins[player]
	if origin then
		local worldCF = GridUtil.gridToWorld(origin, building.gridX, building.gridZ, def.footprint, building.rotation)
		self.Client.HarborVisualUpdate:Fire(player, building.uid, building.kind, 1, worldCF.Position)
	end
	return { ok = true, building = building }
end

function HarborService.Client:Upgrade(player: Player, uid: string): {ok: boolean, reason: string?, newTier: number?}
	local self = self.Server
	if not self._buildLimiter:check(player) then return { ok = false, reason = "rate_limit" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player); if not data then return { ok = false, reason = "no_profile" } end

	for _, b in ipairs(data.buildings) do
		if b.uid == uid then
			local def = BuildingCatalog[b.kind]
			if not def then return { ok = false, reason = "unknown_building" } end
			local nextTierIdx = b.tier + 1
			-- Gate on the catalog tier first (it defines behavior; GameConfig
			-- only stores costs, so both must agree a tier exists).
			if not def.tiers[nextTierIdx] then return { ok = false, reason = "max_tier" } end
			local bldCfg = GameConfig.Buildings[b.kind]
			if not bldCfg then return { ok = false, reason = "unknown_building" } end
			local nextCost = bldCfg.tierCosts[nextTierIdx]
			if not nextCost then return { ok = false, reason = "max_tier" } end
			if not PlayerDataService:TrySpendCoins(player, nextCost) then
				return { ok = false, reason = "not_enough_coins" }
			end
			local oldTier = b.tier
			b.tier = nextTierIdx
			-- Refresh the invisible anchor's tier attribute. The visible
			-- model is animated client-side by HarborVisualController.
			self:_destroyBuildingVisual(player, uid)
			self:_spawnBuildingVisual(player, b)
			-- Force a profile broadcast since we mutated in place.
			PlayerDataService.Client.BuildingsChanged:Fire(player, data.buildings)
			self.Client.BuildingUpgraded:Fire(player, uid, nextTierIdx)
			self.BuildingUpgradedServer:Fire(player, b, oldTier, nextTierIdx)
			local origin = self._plotOrigins[player]
			if origin then
				local worldCF = GridUtil.gridToWorld(origin, b.gridX, b.gridZ, def.footprint, b.rotation)
				self.Client.HarborVisualUpdate:Fire(player, uid, b.kind, nextTierIdx, worldCF.Position)
			end
			return { ok = true, newTier = nextTierIdx }
		end
	end
	return { ok = false, reason = "not_found" }
end

function HarborService.Client:Remove(player: Player, uid: string): {ok: boolean, reason: string?}
	local self = self.Server
	if not self._buildLimiter:check(player) then return { ok = false, reason = "rate_limit" } end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)

	-- If we're tearing down an aquarium or smokehouse, return contents to inventory.
	if data then
		for _, b in ipairs(data.buildings) do
			if b.uid == uid and b.kind == "Aquarium" then
				local stock = data.aquariumStock[uid]
				if stock then
					for _, item in ipairs(stock) do
						PlayerDataService:AddItem(player, item)
					end
					data.aquariumStock[uid] = nil
				end
				break
			elseif b.uid == uid and b.kind == "Smokehouse" then
				Knit.GetService("SmokehouseService"):RefundAllSlots(player, b)
				break
			end
		end
	end

	local removed = PlayerDataService:RemoveBuildingByUid(player, uid)
	if not removed then return { ok = false, reason = "not_found" } end

	self:_destroyBuildingVisual(player, uid)
	self.Client.BuildingRemoved:Fire(player, uid)
	self.OnBuildingRemoved:Fire(player, uid)
	-- No refund — discourages churn-griefing and keeps building tier1 cost as
	-- meaningful sink. Game design call; flip to 50% refund if telemetry shows
	-- players hesitate to experiment with placement.
	return { ok = true }
end

-- Server-callable for SocialService teleport flow.
function HarborService:GetPlotOrigin(player: Player): CFrame?
	return self._plotOrigins[player]
end

-- Client-callable: bring me back to my own plot. Used by the HUD Home
-- button. Server-authoritative so an exploiter can't smuggle a CFrame
-- and end up off-map.
function HarborService.Client:GoHome(player: Player): {ok: boolean, reason: string?}
	local self = self.Server
	local origin = self._plotOrigins[player]
	if not origin then return { ok = false, reason = "no_plot" } end
	local char = player.Character
	if not char then return { ok = false, reason = "no_character" } end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return { ok = false, reason = "no_rootpart" } end
	-- Land just above the dock plate so the player doesn't intersect it.
	hrp.CFrame = origin * CFrame.new(GameConfig.Harbor.PlotSizeStuds / 2, 6, GameConfig.Harbor.PlotSizeStuds / 2)
	return { ok = true }
end

return HarborService
