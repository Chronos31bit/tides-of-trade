--!strict
-- HarborVisualController.lua
-- Passive renderer for harbor state. Subscribes to HarborVisualService's
-- HarborVisualUpdate / HarborVisualClear RemoteSignals and turns those state
-- snapshots into actual Models, debris, and upgrade tweens.
--
-- Responsibilities, in priority order:
--   1) Fresh spawn (oldTier == nil): clone the appropriate Model and PivotTo.
--   2) Upgrade transition (newTier > oldTier): fade + scale old out, fade +
--      overshoot new in, particle burst, audio TODO, mobile haptic.
--   3) Removal (newTier == nil): destroy the Model and its debris.
--   4) Initial debris: tier-1 buildings get deterministic procedural debris.
--      Despawned with a fade when the building upgrades past tier 1.
--
-- This controller does NOT decide tier — it just renders whatever the server
-- pushes. Reads BuildingCatalog only to look up footprint, never to compute
-- gameplay outcomes.
--
-- Architectural notes:
--   * One Trove per visual Model. Destroying the Trove cleans every tween,
--     particle emitter, and connection tied to that building.
--   * Pending payloads queue: if a HarborVisualUpdate arrives before the
--     ReplicatedStorage.Assets.Buildings folder has been populated by the
--     server's BuildAssetPlaceholders script, we cache the payload and
--     replay on folder-ready. Belt-and-braces — in practice the server
--     script runs before any client signals fire.
--   * StreamingEnabled: when the player teleports far from a plot, the
--     server-side anchor parts unstream. Our client Models are parented to
--     Workspace and not subject to streaming, so they stay rendered. This
--     is the prompt's required behaviour ("StreamingEnabled compatibility").

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BuildingCatalog = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local MotionUtil = require(ReplicatedStorage.Shared.Util.MotionUtil)
local GridUtil   = require(ReplicatedStorage.Shared.Util.GridUtil)

local VT  = GameConfig.Harbor.VisualTuning
local CELL = GameConfig.Harbor.GridCellStuds

-- Tag used for every debris part. CollectionService tag lets the cleanup
-- pass walk a flat list instead of remembering which model owns what.
local DEBRIS_TAG = "HarborDebris"

local HarborVisualController = Knit.CreateController({
	Name = "HarborVisualController",
	-- _visuals[ownerUserId][buildingId] = {
	--   model: Model,
	--   debris: { Part, ... },
	--   trove: Trove,
	-- }
	_visuals = {},
	-- Per-plot debris count for the budget cap.
	_debrisCount = {},
	-- Folder under Workspace that holds all client-rendered visuals so they
	-- never collide with server-spawned anchor parts.
	_root = nil :: Folder?,
})

-- ====================================================================
-- ASSET LOOKUP
-- ====================================================================

local function getAssetsRoot(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local buildings = assets:FindFirstChild("Buildings")
	if not buildings then return nil end
	return buildings :: Folder
end

local function getVisualTemplate(kind: string, tier: number): Model?
	local root = getAssetsRoot(); if not root then return nil end
	local kindFolder = root:FindFirstChild(kind); if not kindFolder then return nil end
	local tierFolder = kindFolder:FindFirstChild(("tier%d"):format(tier))
	if not tierFolder then return nil end
	local visual = tierFolder:FindFirstChild("Visual")
	if visual and visual:IsA("Model") then return visual end
	return nil
end

-- Fallback for missing art: a neutral gray block sized to the footprint so
-- a typo / missing tier never leaves a building invisible.
local function makeFallbackModel(kind: string, tier: number): Model
	warn(("[HarborVisualController] Missing asset %s/tier%d, using fallback block."):format(kind, tier))
	local def = BuildingCatalog[kind]
	local w, d = (def and def.footprint[1]) or 2, (def and def.footprint[2]) or 2
	local model = Instance.new("Model")
	model.Name = "Fallback_" .. kind .. "_t" .. tostring(tier)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(w * CELL, 4 + tier * 1.5, d * CELL)
	part.Color = Color3.fromRGB(140, 140, 140)
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new(0, part.Size.Y / 2, 0)
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- ====================================================================
-- POSITIONING
-- ====================================================================

local function pivotForBuilding(plotOrigin: CFrame, kind: string, gridX: number, gridZ: number, rotation: number): CFrame
	local def = BuildingCatalog[kind]
	local w, d = (def and def.footprint[1]) or 1, (def and def.footprint[2]) or 1
	if rotation == 90 or rotation == 270 then w, d = d, w end
	local local_ = GridUtil.gridToLocal(gridX, gridZ)
	-- Plate top sits at local Y = 1.5 (matches HarborService's PLATE_TOP).
	-- Building Models' PrimaryPart anchors at the model's base center, so the
	-- pivot Y is the plate top, NOT plate top + halfHeight.
	local PLATE_TOP = 1.5
	local centerLocal = Vector3.new(local_.X + (w * CELL) / 2, PLATE_TOP, local_.Z + (d * CELL) / 2)
	return plotOrigin * CFrame.new(centerLocal) * CFrame.Angles(0, math.rad(rotation), 0)
end

-- ====================================================================
-- INSTANTIATE A BUILDING
-- ====================================================================

local function setModelTransparency(model: Model, t: number)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = t
		end
	end
end

function HarborVisualController:_instantiate(payload: any): Model
	local template = getVisualTemplate(payload.kind, payload.newTier) or makeFallbackModel(payload.kind, payload.newTier)
	local model = template:Clone()
	model.Name = ("%s_%s_t%d"):format(payload.kind, payload.buildingId, payload.newTier)
	model.Parent = self._root
	-- Client visuals are pure decoration. We set CanQuery=false on each part
	-- as a hint to Workspace:Raycast / mouse picking, but HarborEditController's
	-- raycast also explicitly excludes the HarborVisuals_Client_* folder —
	-- belt and braces, because a playtest revealed Roblox sometimes ignored
	-- the CanQuery write here for reasons we never tracked down.
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanQuery = false
		end
	end
	local cf = pivotForBuilding(payload.plotOriginCFrame, payload.kind, payload.gridX, payload.gridZ, payload.rotation)
	-- PivotTo positions the model's pivot (PrimaryPart.CFrame) at `cf`.
	-- For our placeholders the PrimaryPart is at the model's center; for
	-- future real art it could be anywhere. Either way, we want the model's
	-- BOTTOM to sit at the plate-top. Apply a one-shot vertical lift using
	-- the model's bounding box so any author's PrimaryPart placement is
	-- handled the same way.
	model:PivotTo(cf)
	-- Lift the model so its bounding-box BOTTOM sits at cf.Y (= plate top).
	-- Without this, PivotTo plants the PrimaryPart's center at plate top
	-- which buries half the building. Bounding-box math works regardless
	-- of where the author placed the PrimaryPart.
	local boundCF, sz = model:GetBoundingBox()
	local lift = cf.Position.Y - (boundCF.Position.Y - sz.Y / 2)
	if math.abs(lift) > 0.001 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
	end
	return model
end

-- ====================================================================
-- DEBRIS
-- ====================================================================

-- Per-(owner, building) deterministic Random. Same player, same building,
-- always same debris layout — survives rejoin without storing anything.
local function debrisRandom(ownerUserId: number, buildingId: string): Random
	local hash = ownerUserId * 2654435761
	for i = 1, #buildingId do
		hash = (hash * 31 + string.byte(buildingId, i)) % 2147483647
	end
	return Random.new(hash)
end

local DEBRIS_KINDS = {
	-- {name, sizeMin..sizeMax (X,Y,Z), color}, all approximate.
	{ name = "Plank",     size = Vector3.new(3.5, 0.4, 0.6),  color = Color3.fromRGB(110, 80, 50)  },
	{ name = "Weed",      size = Vector3.new(1.0, 0.5, 1.0),  color = Color3.fromRGB(70, 110, 60)  },
	{ name = "Driftwood", size = Vector3.new(2.0, 0.7, 0.8),  color = Color3.fromRGB(95, 75, 55)   },
	{ name = "Bucket",    size = Vector3.new(1.2, 1.2, 1.2),  color = Color3.fromRGB(120, 80, 60)  },
}

function HarborVisualController:_spawnDebris(payload: any): { Part }
	local owner = payload.ownerUserId
	self._debrisCount[owner] = self._debrisCount[owner] or 0

	local rng = debrisRandom(owner, payload.buildingId)
	local count = rng:NextInteger(VT.DebrisPerBuildingMin, VT.DebrisPerBuildingMax)
	-- Per-plot cap. If we'd exceed it, reduce the per-building spawn.
	local remaining = math.max(0, VT.DebrisMaxPerPlot - self._debrisCount[owner])
	if remaining <= 0 then return {} end
	count = math.min(count, remaining)

	local center = pivotForBuilding(payload.plotOriginCFrame, payload.kind, payload.gridX, payload.gridZ, payload.rotation).Position

	local spawned: { Part } = {}
	for i = 1, count do
		local kindIdx = rng:NextInteger(1, #DEBRIS_KINDS)
		local kindDef = DEBRIS_KINDS[kindIdx]
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(1.5, VT.DebrisRadiusStuds)
		local offset = Vector3.new(math.cos(angle) * radius, kindDef.size.Y / 2, math.sin(angle) * radius)
		local yaw = rng:NextNumber() * math.pi * 2

		local part = Instance.new("Part")
		part.Name = "Debris_" .. kindDef.name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false  -- decoration; mouse picking ignores it
		part.Size = kindDef.size
		part.Color = kindDef.color
		part.Material = Enum.Material.Wood
		part.CFrame = CFrame.new(center + offset) * CFrame.Angles(0, yaw, 0)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		CollectionService:AddTag(part, DEBRIS_TAG)
		part.Parent = self._root
		table.insert(spawned, part)
	end
	self._debrisCount[owner] += #spawned
	return spawned
end

function HarborVisualController:_fadeOutDebris(entry: any, owner: number)
	if not entry.debris then return end
	-- Capture the debris list locally before we null it on the entry, so the
	-- delayed destroy closure can still iterate it.
	local debrisRef = entry.debris
	local duration = VT.DebrisFadeOutDuration
	if MotionUtil.reducedMotionEnabled() then
		duration = duration * VT.ReducedMotionDurationScale
	end
	for _, part in ipairs(debrisRef) do
		local tween = MotionUtil.tween(part, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		entry.trove:Add(tween)
	end
	self._debrisCount[owner] = math.max(0, (self._debrisCount[owner] or 0) - #debrisRef)
	entry.debris = nil
	task.delay(duration + 0.05, function()
		for _, part in ipairs(debrisRef) do
			if part and part.Parent then part:Destroy() end
		end
	end)
end

-- ====================================================================
-- UPGRADE TRANSITION
-- ====================================================================

-- Drive Model:ScaleTo via a tweened NumberValue. TweenService can't directly
-- target a method, but a NumberValue Changed handler is the clean Roblox
-- idiom — and per-frame `ScaleTo` for a 1.5s one-shot has negligible cost.
local function tweenModelScale(trove: any, model: Model, fromScale: number, toScale: number, info: TweenInfo): Tween
	local nv = Instance.new("NumberValue")
	nv.Value = fromScale
	model:ScaleTo(fromScale)
	local conn = nv:GetPropertyChangedSignal("Value"):Connect(function()
		if model and model.Parent then model:ScaleTo(nv.Value) end
	end)
	local tween = TweenService:Create(nv, info, { Value = toScale })
	tween:Play()
	trove:Add(conn)
	trove:Add(nv)
	trove:Add(tween)
	return tween
end

-- Particle burst at the model's pivot. Lives 1s after Enabled=false so
-- already-emitted particles get to finish their natural lifetime.
local function spawnParticleBurst(trove: any, model: Model)
	if not model.PrimaryPart then return end
	local attach = Instance.new("Attachment")
	attach.Name = "UpgradeBurst"
	attach.Parent = model.PrimaryPart

	local emitter = Instance.new("ParticleEmitter")
	-- TODO: replace with a real shimmer/sparkle texture (soft edges, no hard
	-- outlines). Default texture is the warning checkerboard; we keep it
	-- visually obvious in placeholder land.
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, 6, 0)
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	emitter.LightEmission = 0.4
	emitter.Parent = attach

	emitter:Emit(VT.ParticleBurstCount)
	-- Disable continuous emission immediately; lifetime grace handled below.
	emitter.Enabled = false

	trove:Add(emitter)
	trove:Add(attach)
	-- Drain delay so the last emitted particle dies before we yank the
	-- Attachment. Otherwise particles snap-die mid-flight.
	task.delay(1.0, function()
		if attach and attach.Parent then attach:Destroy() end
	end)
end

-- Play an upgrade sound at the model's location. Asset ID is a TODO.
local function playUpgradeSound(model: Model)
	if not model.PrimaryPart then return end
	local sound = Instance.new("Sound")
	-- TODO asset: "ka-chunk + chime" upgrade sound. Aesthetic: warm, woody,
	-- with a chime tail. Volume 0.5. Replace SoundId below when art lands.
	sound.SoundId = "rbxassetid://0"
	sound.Volume = 0.5
	sound.RollOffMaxDistance = 80
	sound.Parent = model.PrimaryPart
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
	-- Defensive: if the asset is the null TODO id, Roblox emits no Ended.
	task.delay(2.0, function() if sound and sound.Parent then sound:Destroy() end end)
end

-- Fire a single mid-strength haptic pulse on mobile. Gamepad shrug — the
-- upgrade is environmental, the prompt explicitly said no controller rumble
-- for building upgrades (camera shake also explicitly forbidden).
local function pulseHapticOnMobile()
	if not UserInputService.TouchEnabled then return end
	-- Pop into a pcall: HapticService API throws on devices without motors,
	-- which on mobile is "most of them".
	pcall(function()
		local HapticService = game:GetService("HapticService")
		HapticService:SetMotor(Enum.UserInputType.Touch, Enum.VibrationMotor.Small, 0.5)
		task.wait(0.1)
		HapticService:SetMotor(Enum.UserInputType.Touch, Enum.VibrationMotor.Small, 0)
	end)
end

function HarborVisualController:_animateUpgrade(entry: any, oldModel: Model, newModel: Model)
	local trove = entry.trove
	local reduced = MotionUtil.reducedMotionEnabled()
	local scale = reduced and VT.ReducedMotionDurationScale or 1
	local fadeOutDur = VT.UpgradeFadeOutDuration * scale
	local fadeInDur = VT.UpgradeFadeInDuration * scale
	local settleDur = VT.UpgradeSettleDuration * scale

	-- Reduced motion: skip scale overshoot, skip particles, just transparency.
	if reduced then
		-- Fade old out
		for _, desc in ipairs(oldModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				local t = MotionUtil.tween(desc, TweenInfo.new(fadeOutDur, Enum.EasingStyle.Quad), { Transparency = 1 })
				trove:Add(t)
			end
		end
		-- Fade new in (already at Transparency=1)
		for _, desc in ipairs(newModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				local t = MotionUtil.tween(desc, TweenInfo.new(fadeInDur, Enum.EasingStyle.Quad), { Transparency = 0 })
				trove:Add(t)
			end
		end
		task.delay(fadeOutDur + fadeInDur + 0.05, function()
			if oldModel and oldModel.Parent then oldModel:Destroy() end
		end)
		return
	end

	-- Normal path. ---------------------------------------------------------
	-- 0.0s -> fadeOutDur: old fades, shrinks 1.0 -> 0.85.
	local oldFadeInfo = TweenInfo.new(fadeOutDur, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, desc in ipairs(oldModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			trove:Add(MotionUtil.tween(desc, oldFadeInfo, { Transparency = 1 }))
		end
	end
	tweenModelScale(trove, oldModel, 1.0, 0.85, oldFadeInfo)

	-- ParticleSpawnDelay: burst on the *new* model so it appears to "pop" in.
	task.delay(VT.ParticleSpawnDelay, function()
		if newModel and newModel.Parent then spawnParticleBurst(trove, newModel) end
	end)
	task.delay(VT.AudioSpawnDelay, function()
		if newModel and newModel.Parent then playUpgradeSound(newModel) end
	end)
	task.delay(VT.HapticSpawnDelay, function()
		pulseHapticOnMobile()
	end)

	-- New model overshoot. Starts at scale 0.85 (matches old's ending scale)
	-- and Back/Out to 1.05 over fadeInDur, then Quad/Out settles to 1.0.
	local fadeInInfo = TweenInfo.new(fadeInDur, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, desc in ipairs(newModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			trove:Add(MotionUtil.tween(desc, fadeInInfo, { Transparency = 0 }))
		end
	end
	local overshootTween = tweenModelScale(trove, newModel, 0.85, VT.UpgradeOvershoot, fadeInInfo)
	overshootTween.Completed:Connect(function()
		if not newModel or not newModel.Parent then return end
		tweenModelScale(
			trove,
			newModel,
			VT.UpgradeOvershoot,
			1.0,
			TweenInfo.new(settleDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		)
	end)

	-- Cleanup old model when the fade-out is fully done. We do this in a
	-- delayed task rather than off the Tween.Completed of a single part
	-- because GetDescendants is unordered.
	task.delay(fadeOutDur + 0.05, function()
		if oldModel and oldModel.Parent then oldModel:Destroy() end
	end)
end

-- ====================================================================
-- PUBLIC LOOKUP — HarborEditController uses this to find the visible
-- model for a building uid (e.g. to attach a Highlight on hover). We
-- expose only a read accessor; the caller never mutates the Trove or
-- Model directly.
-- ====================================================================

function HarborVisualController:GetVisualModel(buildingUid: string): Model?
	for _, plotMap in pairs(self._visuals) do
		local entry = plotMap[buildingUid]
		if entry and entry.model and entry.model.Parent then
			return entry.model
		end
	end
	return nil
end

-- Returns a flat list of building metadata for a specific plot owner.
-- HarborEditController calls this for the local player to compute a
-- client-side overlap preview while the placement ghost is moving.
function HarborVisualController:GetBuildingsForOwner(ownerUserId: number): {{kind: string, gridX: number, gridZ: number, rotation: number, uid: string}}
	local out = {}
	local plotMap = self._visuals[ownerUserId]
	if not plotMap then return out end
	for uid, entry in pairs(plotMap) do
		if entry.kind then
			table.insert(out, {
				kind = entry.kind,
				gridX = entry.gridX,
				gridZ = entry.gridZ,
				rotation = entry.rotation,
				uid = uid,
			})
		end
	end
	return out
end

-- ====================================================================
-- DISPATCH
-- ====================================================================

function HarborVisualController:_applyUpdate(payload: any)
	local owner = payload.ownerUserId
	local buildingId = payload.buildingId
	self._visuals[owner] = self._visuals[owner] or {}
	local plotMap = self._visuals[owner]
	local existing = plotMap[buildingId]

	-- Removal: server says newTier is nil. Drop the model + debris cleanly.
	if payload.newTier == nil then
		if existing then
			if existing.debris then
				self._debrisCount[owner] = math.max(0, (self._debrisCount[owner] or 0) - #existing.debris)
			end
			existing.trove:Destroy()
			plotMap[buildingId] = nil
		end
		return
	end

	-- Fresh spawn (no prior visual): no animation, just instantiate.
	if not existing then
		local trove = Trove.new()
		local model = self:_instantiate(payload)
		trove:Add(model)
		local entry: any = {
			model = model,
			debris = nil,
			trove = trove,
			-- Cache metadata for HarborEditController's overlap preview.
			kind = payload.kind,
			gridX = payload.gridX,
			gridZ = payload.gridZ,
			rotation = payload.rotation,
			ownerUserId = payload.ownerUserId,
		}
		plotMap[buildingId] = entry
		-- Tier 1 spawns also bring in procedural debris (rundown-harbor feel).
		if payload.newTier == 1 then
			entry.debris = self:_spawnDebris(payload)
			for _, p in ipairs(entry.debris) do trove:Add(p) end
		end
		return
	end

	-- Tier change. Same buildingId; if newTier == oldTier, it's a re-broadcast
	-- (e.g. another player joined and the server replayed); ignore.
	if payload.newTier == payload.oldTier then return end
	if payload.oldTier == nil then
		-- Re-broadcast for an existing visual. Refresh in place if the tier
		-- happens to have changed since we last knew (shouldn't, but safe).
		return
	end

	-- Real upgrade. Instantiate the new model at the same pivot, animate.
	local oldModel = existing.model
	local newModel = self:_instantiate(payload)
	setModelTransparency(newModel, 1)
	existing.model = newModel
	-- The trove still references the old model; that's fine — Roblox
	-- Instance:Destroy is idempotent so the later trove cleanup is a no-op
	-- on the already-destroyed old model. We DO need to add the new model
	-- so eventual building-removal still tears it down.
	existing.trove:Add(newModel)
	if payload.animate then
		self:_animateUpgrade(existing, oldModel, newModel)
	else
		-- No animation requested: snap (used e.g. on resync).
		setModelTransparency(newModel, 0)
		if oldModel and oldModel.Parent then oldModel:Destroy() end
	end

	-- Debris fade-out: any building leaving tier 1 sheds its debris.
	if payload.oldTier == 1 and payload.newTier > 1 and existing.debris then
		self:_fadeOutDebris(existing, owner)
	end
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================

function HarborVisualController:KnitStart()
	-- Root container for client-rendered visuals. Anchored under Workspace
	-- (not StarterPlayer) so it survives respawn but stays local.
	local root = Instance.new("Folder")
	root.Name = "HarborVisuals_Client_" .. Players.LocalPlayer.Name
	root.Parent = Workspace
	self._root = root

	-- Wait for the asset folder to replicate. BuildAssetPlaceholders.server.lua
	-- creates it at server boot, but ReplicatedStorage replication to a new
	-- client is async, so we don't assume it's there yet. Fallback models cover
	-- the timeout case so a slow replication never leaves a building invisible.
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets", 10)
		if assets then assets:WaitForChild("Buildings", 5) end
	end)

	local HarborVisualService = Knit.GetService("HarborVisualService")

	-- 1) Connect to live updates FIRST so we don't miss any while the snapshot
	--    request is in flight. Duplicate snapshot entries are idempotent
	--    because _applyUpdate ignores oldTier=nil payloads for buildings that
	--    already have a visual.
	HarborVisualService.HarborVisualUpdate:Connect(function(payload)
		if type(payload) ~= "table" or not payload.buildingId then return end
		self:_applyUpdate(payload)
	end)

	HarborVisualService.HarborVisualClear:Connect(function(ownerUserId)
		local plotMap = self._visuals[ownerUserId]
		if not plotMap then return end
		for _, entry in pairs(plotMap) do
			entry.trove:Destroy()
		end
		self._visuals[ownerUserId] = nil
		self._debrisCount[ownerUserId] = 0
	end)

	-- 2) Pull the full current state. Covers the race where the server's
	--    PlayerAdded replay fires before our Connect() above lands.
	HarborVisualService:GetSnapshot():andThen(function(snapshot)
		if type(snapshot) ~= "table" then return end
		for _, payload in ipairs(snapshot) do
			self:_applyUpdate(payload)
		end
	end)
end

return HarborVisualController
