--!strict
-- RodService.lua
-- Spawns a fishing rod Tool into the player's Backpack on character spawn.
-- The Tool is the equipment-state gate: clicks/taps only trigger fishing
-- when the rod is *equipped* (Tool.Activated). Removing the rod tool from
-- the player while in Studio testing is a fast way to verify the gate
-- (clicks shouldn't cast).

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit             = require(ReplicatedStorage.Packages.Knit)
local GameConfig       = require(ReplicatedStorage.Shared.Config.GameConfig)
local RodTierUtil      = require(ReplicatedStorage.Shared.Util.RodTierUtil)

local RodCatalog = require(ReplicatedStorage.Shared.Config.RodCatalog)

local RodService = Knit.CreateService({
	Name = "RodService",
	Client = {
		-- Fired when the player Activated the rod tool. Client controllers
		-- listen and trigger the cast/release flow.
		RodActivated = Knit.CreateSignal(),
	},
})

-- ====================================================================
-- HOW TO SWAP THE ROD VISUAL (three options, pick one)
-- ====================================================================
-- The Tool needs a child part named exactly "Handle" (or any BasePart with
-- RequiresHandle=true). Whatever that handle looks like is what the player
-- sees in their hands. Three ways to upgrade from this placeholder:
--
-- OPTION A — Custom MeshPart (best quality, requires a 3D model)
--   1. In Studio: Insert > MeshPart, set its MeshId to your uploaded
--      asset id (rbxassetid://YOUR_ID). Set TextureId for diffuse.
--   2. Drag that MeshPart into ReplicatedStorage > Assets > Rod (create
--      that path), and rename it "Handle".
--   3. Replace this whole function body with:
--          local tool = ReplicatedStorage.Assets.Rod:Clone()
--          tool.Name = "Fishing Rod"
--          tool.CanBeDropped = false
--          return tool
--      (Or leave the buildRodTool fallback for when the asset is missing.)
--
-- OPTION B — Toolbox/Marketplace asset (fast, free models exist)
--   1. Open the Toolbox in Studio, search for "fishing rod".
--   2. Drag a model into Workspace; rename its main part to "Handle".
--   3. Drag the Tool/Model into ReplicatedStorage.Assets.Rod and clone
--      from there as in Option A.
--
-- OPTION C — Better-looking placeholder (no asset upload required)
--   Tweak the Part below: try Material = SmoothPlastic, Color a richer
--   wood tone, add a SpecialMesh of MeshType.Cylinder to round it,
--   parent extra parts (reel, line) and weld them. Keep Handle as the
--   base name.
-- ====================================================================
local function buildRodTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Fishing Rod"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "Tap or click to cast"

	-- HANDLE — the main body of the rod. This is what gets welded to the
	-- player's hand grip. Must be named exactly "Handle".
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 4.5)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Color = Color3.fromRGB(94, 60, 38)   -- richer wood tone
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	-- Cylinder mesh so it's not a square stick.
	local handleMesh = Instance.new("SpecialMesh")
	handleMesh.MeshType = Enum.MeshType.Cylinder
	-- SpecialMesh on a Cylinder needs the part rotated; instead use Brick
	-- with a Scale that approximates a rod. Drop the mesh and rely on the
	-- Part itself with a thinner profile.
	handleMesh.Parent = handle
	handle.Parent = tool

	-- TIP — tapered light section, welded to one end of the handle.
	local tip = Instance.new("Part")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.12, 0.12, 1.6)
	tip.Material = Enum.Material.SmoothPlastic
	tip.Color = Color3.fromRGB(238, 220, 188)
	tip.TopSurface = Enum.SurfaceType.Smooth
	tip.BottomSurface = Enum.SurfaceType.Smooth
	tip.Parent = tool
	local tipWeld = Instance.new("WeldConstraint")
	tipWeld.Part0 = handle
	tipWeld.Part1 = tip
	tipWeld.Parent = handle
	tip.CFrame = handle.CFrame * CFrame.new(0, 0, -((handle.Size.Z + tip.Size.Z) / 2))

	-- REEL — small disc-shaped part near the grip end for visual interest.
	local reel = Instance.new("Part")
	reel.Name = "Reel"
	reel.Size = Vector3.new(0.6, 0.6, 0.3)
	reel.Material = Enum.Material.Metal
	reel.Color = Color3.fromRGB(160, 130, 90)
	reel.TopSurface = Enum.SurfaceType.Smooth
	reel.BottomSurface = Enum.SurfaceType.Smooth
	reel.Parent = tool
	local reelWeld = Instance.new("WeldConstraint")
	reelWeld.Part0 = handle
	reelWeld.Part1 = reel
	reelWeld.Parent = handle
	reel.CFrame = handle.CFrame * CFrame.new(0, -0.25, handle.Size.Z * 0.35)

	return tool
end

-- Try to clone a per-tier rod model from ReplicatedStorage.Assets.Rods.<id>.
-- Returns nil if the path doesn't exist, in which case _grantRod falls back to
-- the in-code placeholder. The assetPath is read from RodCatalog.assetPath.
local function cloneRodAsset(rod: any): Tool?
	local rodFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not rodFolder then return nil end
	rodFolder = rodFolder:FindFirstChild("Rods")
	if not rodFolder then return nil end
	if not rod.assetPath then return nil end
	-- Parse "Assets.Rods.driftwood" → find "driftwood" under Assets/Rods
	local parts = {}
	for part in string.gmatch(rod.assetPath, "[^.]+") do
		table.insert(parts, part)
	end
	local source: Instance? = rodFolder
	for i = 3, #parts do -- skip "Assets" and "Rods"
		source = source:FindFirstChild(parts[i])
		if not source then return nil end
	end
	if not source or not source:IsA("Tool") then return nil end
	if not source:FindFirstChild("Handle") then return nil end
	local clone = (source :: Tool):Clone()
	clone.Name = "Fishing Rod"
	clone.RequiresHandle = true
	clone.CanBeDropped = false
	clone.ToolTip = "Tap or click to cast"
	return clone
end

function RodService:_grantRod(player: Player)
	-- Remove any stale rod (rejoin / respawn) before re-issuing.
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local existing = backpack:FindFirstChild("Fishing Rod")
		if existing then existing:Destroy() end
	end
	local char = player.Character
	if char then
		local equipped = char:FindFirstChild("Fishing Rod")
		if equipped then equipped:Destroy() end
	end

	-- Resolve the player's equipped rod. Default to driftwood if no profile.
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	local rodId = data and data.equippedRodId or "driftwood"
	local rod = RodCatalog.byId[rodId]

	-- Prefer a per-tier rod model from ReplicatedStorage.Assets.Rods.<id>;
	-- fall back to the in-code placeholder if the asset isn't uploaded yet.
	local tool = (rod and cloneRodAsset(rod)) or buildRodTool()
	tool.Activated:Connect(function()
		self.Client.RodActivated:Fire(player)
	end)
	tool.Parent = backpack
end

-- Populate GameConfig.Fishing.RodTierUnlocks[*].speciesUnlocked from
-- FishCatalog and log the per-tier breakdown so a glance at the server
-- output verifies the gating data. Warns about any fish missing an explicit
-- rodMinTier (defaulted to tier 1) so the catalog can be filled in.
function RodService:KnitInit()
	local grouping = RodTierUtil.populate(GameConfig.Fishing.RodTierUnlocks)
	for t = 1, grouping.maxTier do
		local newCount = #(grouping.newAtTier[t] or {})
		local cumulative = grouping.countAtOrBelow[t] or 0
		print(("[RodService] RodTierUnlocks: tier %d unlocks %d new species (%d catchable at or below tier %d)")
			:format(t, newCount, cumulative, t))
	end
	if #grouping.missing > 0 then
		warn(("[RodService] %d fish have no explicit rodMinTier (defaulted to tier 1) — fill these in FishCatalog: %s")
			:format(#grouping.missing, table.concat(grouping.missing, ", ")))
	else
		print("[RodService] All fish have an explicit rodMinTier.")
	end
end

-- ====================================================================
-- CLIENT API — rod equip
-- ====================================================================

-- Client requests to equip a named rod. Server validates:
--   1. rodId exists in RodCatalog
--   2. player.level >= rod.unlockLevel (level gate; never trust client)
-- On success, PlayerDataService:SetEquippedRod syncs equippedRodId + rodTier.
function RodService.Client:EquipRod(player: Player, rodId: string): {ok: boolean, reason: string?}
	local rod = RodCatalog.byId[rodId]
	if not rod then
		return { ok = false, reason = "unknown_rod" }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:GetProfile(player)
	if not data then
		return { ok = false, reason = "no_profile" }
	end

	local requiredLevel = GameConfig.Rods.UnlockLevel[rodId] or 1
	if data.level < requiredLevel then
		return { ok = false, reason = "level_too_low" }
	end

	PlayerDataService:SetEquippedRod(player, rodId)
	-- Re-grant so the player immediately sees the new rod visual.
	self:_grantRod(player)
	return { ok = true }
end

function RodService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function() self:_grantRod(player) end)
		if player.Character then self:_grantRod(player) end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function() self:_grantRod(p) end)
		if p.Character then self:_grantRod(p) end
	end
end

return RodService
