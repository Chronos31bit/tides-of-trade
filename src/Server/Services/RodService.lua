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

	local tool = buildRodTool()
	-- Tool.Activated fires server-side when the player taps/clicks while the
	-- tool is equipped. We forward that to the client controller via Knit
	-- signal so the existing FishingController flow is preserved.
	tool.Activated:Connect(function()
		self.Client.RodActivated:Fire(player)
	end)
	tool.Parent = backpack
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
