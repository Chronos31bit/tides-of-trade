--!strict
-- Mira.lua
-- Captain Mira — the tutorial NPC. First (and currently only) NPC in the
-- game, so this module owns its own spawn/despawn/walk primitives.
-- When a second NPC arrives, refactor the shared bits up into an
-- NpcService and have this file consume that. Until then: additive,
-- self-contained.
--
-- Per-player visibility: Mira is spawned server-side in Workspace, but a
-- RemoteSignal (fired by TutorialService) tells every non-owner client to
-- set LocalTransparencyModifier=1 on her parts. Owner client sees her
-- normally. Standard Roblox "personal NPC" pattern — avoids per-player
-- physics replicas while keeping server-authoritative animation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local GameConfig    = require(ReplicatedStorage.Shared.Config.GameConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)

local Mira = {}
Mira.__index = Mira

export type MiraInstance = {
	owner: Player,
	model: Model,
	rootPart: BasePart,
	_alive: boolean,

	WalkTo: (self: MiraInstance, position: Vector3) -> (),
	FacePlayer: (self: MiraInstance) -> (),
	FacePosition: (self: MiraInstance, position: Vector3) -> (),
	Despawn: (self: MiraInstance) -> (),
	GetPosition: (self: MiraInstance) -> Vector3,
}

-- ====================================================================
-- VISUAL BUILD — placeholder humanoid model
-- ====================================================================
-- Built procedurally so the project boots without art assets. Replace
-- `buildPlaceholderModel` with a ReplicatedStorage.Assets.Mira:Clone()
-- once a real model is supplied. The rest of this module (spawn point,
-- walk path, visibility filter) is asset-agnostic.
local function buildPlaceholderModel(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Mira"

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Anchored = true
	hrp.CanCollide = false
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Color = Color3.fromRGB(140, 100, 80)
	hrp.Material = Enum.Material.SmoothPlastic
	hrp.Transparency = 1
	hrp.Parent = model

	-- Body: simple two-block silhouette so she reads as a person from a
	-- distance. Cream coat (top), wood trousers (bottom). All anchored;
	-- WalkTo CFrames the whole model, no physics.
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Anchored = true
	torso.CanCollide = false
	torso.Size = Vector3.new(2, 2.4, 1)
	torso.Color = Color3.fromRGB(244, 230, 200)  -- cream
	torso.Material = Enum.Material.Fabric
	torso.Parent = model

	local legs = Instance.new("Part")
	legs.Name = "Legs"
	legs.Anchored = true
	legs.CanCollide = false
	legs.Size = Vector3.new(2, 2, 1)
	legs.Color = Color3.fromRGB(78, 58, 40)  -- wood dark
	legs.Material = Enum.Material.Fabric
	legs.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Anchored = true
	head.CanCollide = false
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.Color = Color3.fromRGB(220, 180, 150)
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model

	-- Floating name tag — visible to everyone (including non-owner
	-- clients, since SetTransparency for the body parts doesn't touch
	-- BillboardGuis). That's intentional: other players can see "this
	-- harbor has a captain" without seeing the puppet itself.
	local nameTag = Instance.new("BillboardGui")
	nameTag.Name = "NameTag"
	nameTag.Size = UDim2.fromOffset(180, 36)
	nameTag.StudsOffset = Vector3.new(0, 2.4, 0)
	nameTag.AlwaysOnTop = true
	nameTag.Adornee = head
	nameTag.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(244, 230, 200)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = TutorialConfig.SpeakerName
	nameLabel.Parent = nameTag

	model.PrimaryPart = hrp
	return model, hrp
end

-- Stack the body parts relative to the rootPart. Y=0 of the rootPart is
-- the center of the character; legs sit below, torso above, head above
-- torso. Re-runs whenever WalkTo finishes.
local function alignBodyParts(model: Model, root: BasePart)
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local legs  = model:FindFirstChild("Legs") :: BasePart?
	local head  = model:FindFirstChild("Head") :: BasePart?
	if torso then torso.CFrame = root.CFrame * CFrame.new(0, 1.2, 0) end
	if legs  then legs.CFrame  = root.CFrame * CFrame.new(0, -1.0, 0) end
	if head  then head.CFrame  = root.CFrame * CFrame.new(0, 3.1, 0) end
end

-- ====================================================================
-- PUBLIC API
-- ====================================================================

-- Spawn Mira at the given world position, parented under the player's
-- plot folder (so cleanup follows the plot naturally). Returns a
-- MiraInstance handle for WalkTo / Despawn etc.
function Mira.Spawn(player: Player, position: Vector3, facing: Vector3?): MiraInstance
	local model, root = buildPlaceholderModel()
	local lookAt = facing and (position + (facing - position).Unit * 4) or (position + Vector3.new(0, 0, 4))
	root.CFrame = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
	alignBodyParts(model, root)

	-- Parent under a dedicated container in Workspace. We avoid the
	-- plot folder so plot teardown doesn't accidentally rip Mira out
	-- mid-tutorial (plot is per-player; Mira is also per-player but
	-- managed by TutorialService directly).
	local container = Workspace:FindFirstChild("TutorialNPCs")
	if not container then
		container = Instance.new("Folder")
		container.Name = "TutorialNPCs"
		container.Parent = Workspace
	end
	-- Tag the owner on the model BEFORE parenting so the attribute
	-- replicates atomically with the ChildAdded event. If set after,
	-- the client-side visibility filter races and may apply
	-- LocalTransparencyModifier=1 to the owner's own Mira (the body
	-- parts go invisible while the name tag stays visible — a clear
	-- symptom of this race).
	model.Name = ("Mira_%d"):format(player.UserId)
	model:SetAttribute("ownerUserId", player.UserId)
	model.Parent = container

	-- Add an interaction prompt so the player can re-trigger Mira's
	-- current dialogue line from anywhere (E on PC, on-screen prompt on
	-- mobile). Dialogue logic still lives in TutorialController — this
	-- prompt just fires a BindableEvent the controller subscribes to.
	local hostPart = model:FindFirstChild("Head") :: BasePart?
	if hostPart then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"
		prompt.ObjectText = "Captain Mira"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = hostPart
	end

	local instance: MiraInstance = setmetatable({
		owner = player,
		model = model,
		rootPart = root,
		_alive = true,
	}, Mira) :: any
	return instance
end

function Mira:GetPosition(): Vector3
	return self.rootPart.Position
end

-- Tween-walk to a target position over a duration scaled by distance.
-- No pathfinding — Mira walks in straight lines on the dock plate
-- where there's nothing to collide with. If we ever introduce
-- obstacles on the plot, swap this for PathfindingService.
function Mira:WalkTo(position: Vector3)
	if not self._alive then return end
	local from = self.rootPart.Position
	local target = Vector3.new(position.X, from.Y, position.Z)
	local distance = (target - from).Magnitude
	local duration = math.clamp(distance / 8, 0.4, 4)  -- ~8 studs/sec

	local goalCFrame = CFrame.lookAt(target, target + (target - from).Unit * 4 + Vector3.new(0, 0, 0.01))
	local tween = TweenService:Create(
		self.rootPart,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = goalCFrame }
	)
	tween:Play()
	-- Update body parts every frame for the duration so they trail the
	-- root. Heartbeat-driven because it's pure visual lerping; cheap.
	local conn
	local startedAt = os.clock()
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		if not self._alive or os.clock() - startedAt > duration + 0.05 then
			if conn then conn:Disconnect() end
			return
		end
		alignBodyParts(self.model, self.rootPart)
	end)
	tween.Completed:Once(function()
		if conn then conn:Disconnect() end
		if self._alive then alignBodyParts(self.model, self.rootPart) end
	end)
end

function Mira:FacePosition(position: Vector3)
	if not self._alive then return end
	local pos = self.rootPart.Position
	local lookY = pos.Y
	self.rootPart.CFrame = CFrame.lookAt(pos, Vector3.new(position.X, lookY, position.Z))
	alignBodyParts(self.model, self.rootPart)
end

function Mira:FacePlayer()
	if not self._alive then return end
	local char = self.owner.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	self:FacePosition(hrp.Position)
end

function Mira:Despawn()
	if not self._alive then return end
	self._alive = false
	-- Brief fade-out before destroy so a complete-tutorial despawn doesn't
	-- pop. ReducedMotion respect handled by the caller (TutorialService
	-- can skip the animation by just calling :Destroy directly).
	local parts = {}
	for _, child in ipairs(self.model:GetDescendants()) do
		if child:IsA("BasePart") then table.insert(parts, child) end
	end
	for _, p in ipairs(parts) do
		TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
	end
	task.delay(0.5, function()
		if self.model and self.model.Parent then self.model:Destroy() end
	end)
end

return Mira
