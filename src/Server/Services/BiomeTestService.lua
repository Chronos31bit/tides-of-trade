--!strict
-- BiomeTestService.lua
-- Studio-only. Builds a raised teleport hub with one glowing pad per biome.
-- Stepping on a pad warps the player to that biome's sensor zone so terrain
-- visuals, water tints, and fish rolls can be tested without swimming across
-- the whole map.
--
-- Not loaded in live sessions: the RunService:IsStudio() guard at the top of
-- KnitStart returns immediately if the game is running on a real server.
--
-- SHIPS TO PROD — self-gated via IsStudio(). The guard was verified in a
-- published play-test: no BiomeTestHub Folder appears in Workspace, no
-- BiomePad_* Parts are created. Intended for removal post-launch when a
-- real biome-test workflow exists (see GameConfig.Debug.StripDebugServicesPostLaunch).
-- VERIFIED: IsStudio() guard confirmed working in published place. Safe to ship.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CFG = GameConfig.BiomeTest

-- Ordered so the pads read left-to-right by progression difficulty.
local BIOME_ORDER = { "Shoreline", "Pier", "Reef", "DeepWater", "Trench" }

local BiomeTestService = Knit.CreateService({
	Name = "BiomeTestService",
	_playerTroves    = {} :: { [Player]: any },
	_lastTeleportAt  = {} :: { [Player]: number },
	_hubFolder       = nil :: Folder?,
})

-- ====================================================================
-- HUB CONSTRUCTION
-- ====================================================================

local function makePart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name         = name
	p.Anchored     = true
	p.CanCollide   = true
	p.CanTouch     = true
	p.CanQuery     = false
	p.Size         = size
	p.CFrame       = cf
	p.Color        = color
	p.Material     = material
	p.CastShadow   = false
	return p
end

function BiomeTestService:_attachLabel(pad: Part, biome: string)
	local bb = Instance.new("BillboardGui")
	bb.Adornee        = pad
	bb.Size           = UDim2.fromOffset(220, 50)
	bb.StudsOffset    = CFG.LabelStudsOffset
	bb.AlwaysOnTop    = false
	bb.LightInfluence = 0
	bb.Parent         = pad

	local label = Instance.new("TextLabel")
	label.Size               = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font               = Enum.Font.GothamBold
	label.TextSize           = 17
	label.TextColor3         = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3   = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.4

	if biome == "Pier" then
		label.Text = "Pier  (→ Shoreline)"
	else
		label.Text = biome
	end

	label.Parent = bb
end

function BiomeTestService:_makePad(folder: Folder, biome: string, index: number): Part
	local center = CFG.HubCenter
	local padX   = center.X + (index - 2) * CFG.PadSpacing
	local padY   = center.Y + CFG.PlatformHeight + CFG.PadHeight / 2
	local padZ   = center.Z

	local pad = makePart(
		"BiomePad_" .. biome,
		Vector3.new(CFG.PadSize, CFG.PadHeight, CFG.PadSize),
		CFrame.new(padX, padY, padZ),
		CFG.PadColors[biome],
		Enum.Material.Neon
	)
	pad:SetAttribute("Biome", biome)
	pad.Parent = folder

	self:_attachLabel(pad, biome)
	return pad
end

function BiomeTestService:_buildHub(): Folder
	local folder = Instance.new("Folder")
	folder.Name   = "BiomeTestHub"
	folder.Parent = Workspace

	-- Base platform — neutral grey driftwood tone.
	local center = CFG.HubCenter
	local platform = makePart(
		"BiomeHubPlatform",
		Vector3.new(CFG.PlatformSizeX, CFG.PlatformHeight, CFG.PlatformSizeZ),
		CFrame.new(center.X, center.Y + CFG.PlatformHeight / 2, center.Z),
		Color3.fromRGB(90, 78, 65),
		Enum.Material.SmoothPlastic
	)
	platform.CanTouch = false
	platform.Parent   = folder

	-- Sign part above the platform.
	local sign = Instance.new("Part")
	sign.Name              = "BiomeHubSign"
	sign.Anchored          = true
	sign.CanCollide        = false
	sign.CanTouch          = false
	sign.CanQuery          = false
	sign.Size              = Vector3.new(1, 1, 1)
	sign.Transparency      = 1
	sign.CFrame            = CFrame.new(center.X, center.Y + CFG.PlatformHeight + 12, center.Z)
	sign.Parent            = folder

	local signBb = Instance.new("BillboardGui")
	signBb.Adornee        = sign
	signBb.Size           = UDim2.fromOffset(320, 40)
	signBb.StudsOffset    = Vector3.new(0, 0, 0)
	signBb.AlwaysOnTop    = false
	signBb.LightInfluence = 0
	signBb.Parent         = sign

	local signLabel = Instance.new("TextLabel")
	signLabel.Size               = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Font               = Enum.Font.GothamBold
	signLabel.TextSize           = 20
	signLabel.TextColor3         = Color3.fromRGB(255, 240, 200)
	signLabel.TextStrokeColor3   = Color3.fromRGB(0, 0, 0)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Text               = "[ BIOME TEST HUB ]"
	signLabel.Parent             = signBb

	for i, biome in ipairs(BIOME_ORDER) do
		self:_makePad(folder, biome, i)
	end

	return folder
end

-- ====================================================================
-- PLAYER WIRING
-- ====================================================================

function BiomeTestService:_teleport(player: Player, biome: string)
	local now = os.clock()
	if (self._lastTeleportAt[player] or 0) + 2 > now then return end
	self._lastTeleportAt[player] = now

	local target = CFG.TeleportTargets[biome]
	if not target then return end

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	hrp.CFrame = CFrame.new(target)
end

function BiomeTestService:_wirePads(player: Player, trove: any)
	if not self._hubFolder then return end

	for _, child in ipairs(self._hubFolder:GetChildren()) do
		if not child:IsA("Part") then continue end
		local biome = child:GetAttribute("Biome") :: string?
		if not biome then continue end

		local conn = child.Touched:Connect(function(hit: BasePart)
			local char = hit:FindFirstAncestorOfClass("Model")
			if not char or char ~= player.Character then return end
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then return end
			self:_teleport(player, biome)
		end)
		trove:Add(conn)
	end
end

function BiomeTestService:_onCharacterAdded(player: Player, _char: Model)
	-- Clean up previous character's connections.
	if self._playerTroves[player] then
		self._playerTroves[player]:Destroy()
	end
	local trove = Trove.new()
	self._playerTroves[player] = trove

	self:_wirePads(player, trove)
end

-- ====================================================================
-- KNIT LIFECYCLE
-- ====================================================================

function BiomeTestService:KnitInit() end

function BiomeTestService:KnitStart()
	if not RunService:IsStudio() then return end

	self._hubFolder = self:_buildHub()

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			self:_onCharacterAdded(player, char)
		end)
		if player.Character then
			self:_onCharacterAdded(player, player.Character)
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(char)
			self:_onCharacterAdded(player, char)
		end)
		if player.Character then
			self:_onCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		if self._playerTroves[player] then
			self._playerTroves[player]:Destroy()
			self._playerTroves[player] = nil
		end
		self._lastTeleportAt[player] = nil
	end)
end

return BiomeTestService
