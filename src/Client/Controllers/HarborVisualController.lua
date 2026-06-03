--!strict
-- HarborVisualController.lua
-- Renders every online player's harbor as cloned Models from
-- ReplicatedStorage.Assets.Buildings.<kind>.<tierN>. Driven entirely by
-- broadcasts from HarborVisualService — the client never decides what
-- to render, only how to play the cosmetic transition.
--
-- Lifecycle:
--   HarborVisualUpdate (oldTier=nil)   → fresh spawn, no animation.
--   HarborVisualUpdate (newTier>oldTier) → upgrade transition.
--   HarborVisualRemove                 → single building destroyed.
--   HarborVisualClear                  → drop the whole plot's visuals.
--
-- Known v1 limitation (confirmed in design Q&A): client renders every
-- online player's harbor regardless of distance. StreamingEnabled does
-- NOT cull client-locally-spawned parts. If profiling shows part-count
-- pain on busy servers, add distance-based hide/show here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local HapticService     = game:GetService("HapticService")

local Knit            = require(ReplicatedStorage.Packages.Knit)
local Trove           = require(ReplicatedStorage.Packages.Trove)
local GridUtil              = require(ReplicatedStorage.Shared.Util.GridUtil)
local GameConfig            = require(ReplicatedStorage.Shared.Config.GameConfig)
local BuildingCatalog       = require(ReplicatedStorage.Shared.Config.BuildingCatalog)
local MotionUtil            = require(ReplicatedStorage.Shared.Util.MotionUtil)
local BuildingModelFactory  = require(ReplicatedStorage.Shared.Util.BuildingModelFactory)
local BuildingAssetUtil     = require(ReplicatedStorage.Shared.Util.BuildingAssetUtil)

local VT = GameConfig.Harbor.VisualTuning

local DEBRIS_TAG = "HarborDebris"
local BUILDING_ANCHOR_TAG = "BuildingAnchor"

local HarborVisualController = Knit.CreateController({
	Name = "HarborVisualController",
	_root = nil :: Folder?,
	-- [plotKey(string)] = {
	--   buildings = { [uid] = { model, trove, building, plotOrigin } },
	--   debrisCount = number,
	-- }
	_plots = {} :: {[string]: any},
})

-- ====================================================================
-- ROOT / PLOT FOLDERS
-- ====================================================================
function HarborVisualController:_ensureRoot(): Folder
	if self._root and self._root.Parent == Workspace then return self._root :: Folder end
	local existing = Workspace:FindFirstChild("HarborVisuals")
	if existing and existing:IsA("Folder") then
		self._root = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "HarborVisuals"
	f.Parent = Workspace
	self._root = f
	return f
end

function HarborVisualController:_plotFolder(plotOwnerId: number): Folder
	local root = self:_ensureRoot()
	local name = tostring(plotOwnerId)
	local f = root:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = root
	return f
end

function HarborVisualController:_plotState(plotOwnerId: number)
	local key = tostring(plotOwnerId)
	local s = self._plots[key]
	if not s then
		s = { buildings = {}, debrisCount = 0 }
		self._plots[key] = s
	end
	return s
end

-- ====================================================================
-- BUILD / POSITION
-- ====================================================================
local function normalizeBuildingTier(kind: string, tier: any): number
	local def = BuildingCatalog[kind]
	local maxTier = if def then #def.tiers else 3
	local t = if typeof(tier) == "number" then tier else 1
	return math.clamp(math.floor(t + 0.5), 1, maxTier)
end

function HarborVisualController:_buildModel(plotOwnerId: number, plotOrigin: CFrame, building: any): Model
	local def = BuildingCatalog[building.kind]
	local footprint = (def and def.footprint) or {2, 2}
	local tier = normalizeBuildingTier(building.kind, building.tier)
	building = table.clone(building)
	building.tier = tier

	local asset = BuildingAssetUtil.getVisualTemplate(building.kind, tier)
	local model
	if asset then
		model = asset:Clone()
	else
		warn(("[HarborVisualController] No mesh at ReplicatedStorage.Assets.Buildings.%s.tier%d.Visual — using procedural placeholder. See scripts/Studio/MCP_HarborBuildings.md"):format(building.kind, tier))
		model = BuildingModelFactory.build(building.kind, tier, footprint)
	end
	model.Name = building.uid

	-- Studio meshes are already tier-sized; only scale procedural fallbacks.
	if model:GetAttribute("ProceduralPlaceholder") then
		local tierScales = VT.TierModelScale
		local tierScale = (tierScales and tierScales[tier]) or 1
		pcall(function() model:ScaleTo(tierScale) end)
	else
		pcall(function() model:ScaleTo(1) end)
	end

	local worldCF = GridUtil.gridToWorld(plotOrigin, building.gridX, building.gridZ, footprint, building.rotation)
	if not model.PrimaryPart then
		warn(("[HarborVisualController] %s tier %d missing PrimaryPart"):format(building.kind, building.tier))
	end
	GridUtil.placeModelOnPlate(model, worldCF)

	model.Name = building.uid
	model:SetAttribute("plotOwnerId", plotOwnerId)
	model:SetAttribute("kind", building.kind)
	model:SetAttribute("tier", building.tier)

	-- Guard against duplicate models for one uid. A world replay or a live-sync
	-- reload can re-enter _buildModel while an earlier clone of the same uid is
	-- still parented (and possibly untracked in _plots). Destroy any stale
	-- namesake first so demolish — which removes only the *tracked* model — can
	-- never leave an orphaned twin behind.
	local targetFolder = self:_plotFolder(plotOwnerId)
	local stale = targetFolder:FindFirstChild(building.uid)
	if stale then stale:Destroy() end

	model.Parent = targetFolder
	CollectionService:AddTag(model, "HarborBuilding")
	return model
end

-- Cache each BasePart's original transparency on the part itself so we can
-- restore exactly the asset's intended look after a fade-in (e.g. Aquarium
-- glass is partially transparent at rest).
local function snapshotTransparencies(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part:SetAttribute("origTransparency", part.Transparency)
		end
	end
end

local function setAllTransparency(model: Model, t: number)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = t
		end
	end
end

local function tweenAllToOriginalTransparency(model: Model, info: TweenInfo, trove: any)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local target = part:GetAttribute("origTransparency")
			if typeof(target) ~= "number" then target = 0 end
			local t = MotionUtil.tweenOrSnap(part, info, { Transparency = target })
			if t then
				trove:Add(t)
				t.Completed:Connect(function() t:Destroy() end)
			end
		end
	end
end

local function tweenAllTransparencyTo(model: Model, target: number, info: TweenInfo, trove: any)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local t = MotionUtil.tweenOrSnap(part, info, { Transparency = target })
			if t then
				trove:Add(t)
				t.Completed:Connect(function() t:Destroy() end)
			end
		end
	end
end

-- ====================================================================
-- UPDATE DISPATCH
-- ====================================================================
function HarborVisualController:_onUpdate(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.plotOwnerId) ~= "number" then
		warn("[HarborVisualController] Ignoring HarborVisualUpdate with invalid payload")
		return
	end
	local plotOwnerId: number = payload.plotOwnerId
	local plotOrigin = GridUtil.unpackPlotOrigin(payload.plotOrigin)
	if not plotOrigin then
		warn("[HarborVisualController] HarborVisualUpdate missing plotOrigin")
		return
	end
	local building: any       = payload.building
	local oldTier: number?    = payload.oldTier
	local newTier: number     = payload.newTier

	local state = self:_plotState(plotOwnerId)
	local existing = state.buildings[building.uid]

	if oldTier == nil then
		-- Fresh spawn (replay or first place). Re-position only when tier/kind match;
		-- otherwise rebuild so a tier-3 model cannot stick after a tier-1 place.
		if existing and existing.model and existing.model.Parent then
			local sameTier = normalizeBuildingTier(building.kind, existing.building.tier)
				== normalizeBuildingTier(building.kind, newTier)
			local sameKind = existing.building.kind == building.kind
			if sameTier and sameKind then
				local def = BuildingCatalog[building.kind]
				local footprint = (def and def.footprint) or { 2, 2 }
				local worldCF = GridUtil.gridToWorld(plotOrigin, building.gridX, building.gridZ, footprint, building.rotation)
				GridUtil.placeModelOnPlate(existing.model, worldCF)
				return
			end
			existing.trove:Destroy()
			state.buildings[building.uid] = nil
		end
		if existing then
			existing.trove:Destroy()
			state.buildings[building.uid] = nil
		end
		self:_spawnFresh(plotOwnerId, plotOrigin, building, newTier)
	elseif newTier > oldTier then
		self:_animateUpgrade(plotOwnerId, plotOrigin, building, oldTier, newTier)
	else
		-- Same or lower tier (rare; degrade not in current contract). Rebuild.
		if existing then existing.trove:Destroy() end
		state.buildings[building.uid] = nil
		self:_spawnFresh(plotOwnerId, plotOrigin, building, newTier)
	end
end

function HarborVisualController:_spawnFresh(plotOwnerId: number, plotOrigin: CFrame, building: any, tier: number)
	local b = table.clone(building); b.tier = tier
	local model = self:_buildModel(plotOwnerId, plotOrigin, b)
	snapshotTransparencies(model)
	local trove = Trove.new()
	trove:Add(model)
	local state = self:_plotState(plotOwnerId)
	state.buildings[b.uid] = { model = model, trove = trove, building = b, plotOrigin = plotOrigin }
	-- Rundown look — debris around every tier-1 building (per design Q&A:
	-- tier 1 IS the "broken" state, no separate "broken" tier exists).
	if tier == 1 then
		self:_spawnDebris(plotOwnerId, b, plotOrigin)
	end
end

function HarborVisualController:_onRemove(plotOwnerId: number, buildingUid: string)
	local state = self:_plotState(plotOwnerId)
	local entry = state.buildings[buildingUid]
	if entry then
		entry.trove:Destroy()
		state.buildings[buildingUid] = nil
	end
	-- Belt-and-suspenders: destroy any model still named after this uid in the
	-- plot folder. Normally the tracked trove above already removed it, but an
	-- untracked duplicate (left by a prior replay/reload) would otherwise survive
	-- as a ghost — the exact "demolish leaves the model" symptom. Silent in the
	-- common case (no namesake left); warns only when it actually cleans one.
	local folder = self:_ensureRoot():FindFirstChild(tostring(plotOwnerId))
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and child.Name == buildingUid then
				warn(("[HarborVisualController] _onRemove cleaned an untracked leftover model for uid %s (duplicate from a prior replay/reload)"):format(buildingUid))
				child:Destroy()
			end
		end
	end
	self:_clearDebrisForBuilding(plotOwnerId, buildingUid, true)
end

function HarborVisualController:_onClear(plotOwnerId: number)
	local key = tostring(plotOwnerId)
	local state = self._plots[key]
	if state then
		for _, entry in pairs(state.buildings) do
			if entry.trove then entry.trove:Destroy() end
		end
	end
	self._plots[key] = nil
	local folder = self:_ensureRoot():FindFirstChild(key)
	if folder then folder:Destroy() end
end

-- ====================================================================
-- UPGRADE ANIMATION
-- Old model: fade transparent + shrink (0.85). New model: starts hidden &
-- tiny, fades in + scale 0.85 → overshoot (1.05) → settle (1.0).
--
-- Scale is driven by Model:ScaleTo() via a NumberValue tween — that gives
-- us a TweenService-driven scale without manual Heartbeat lerps.
-- ====================================================================
function HarborVisualController:_animateUpgrade(plotOwnerId: number, plotOrigin: CFrame, building: any, oldTier: number, newTier: number)
	local reduced = MotionUtil.reducedMotionEnabled()
	local timeScale = reduced and VT.ReducedMotionDurationScale or 1.0

	local state = self:_plotState(plotOwnerId)
	local entry = state.buildings[building.uid]
	if not entry then
		-- Upgrade arrived for a building we don't have. Spawn fresh at new tier.
		self:_spawnFresh(plotOwnerId, plotOrigin, building, newTier)
		return
	end

	local oldModel = entry.model
	local oldTrove = entry.trove

	-- Build the new model in place, fully invisible.
	local newBuilding = table.clone(building); newBuilding.tier = newTier
	local newModel = self:_buildModel(plotOwnerId, plotOrigin, newBuilding)
	snapshotTransparencies(newModel)
	setAllTransparency(newModel, 1)
	-- Start the new model at 0.85 scale around its PrimaryPart pivot. If
	-- reduced motion is on, skip the overshoot and snap to final.
	if not reduced then
		pcall(function() newModel:ScaleTo(0.85) end)
	end

	-- New trove early so the upgrade animation's tweens are owned by the new entry.
	local newTrove = Trove.new()
	newTrove:Add(newModel)

	-- ---- 0.0s – 0.5s: OLD fade-out + shrink ----------------------
	local fadeOutInfo = TweenInfo.new(VT.UpgradeFadeOutDuration * timeScale, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tweenAllTransparencyTo(oldModel, 1, fadeOutInfo, oldTrove)
	if not reduced then
		local oldScale = Instance.new("NumberValue")
		oldScale.Value = 1.0
		local conn = oldScale:GetPropertyChangedSignal("Value"):Connect(function()
			if oldModel.Parent then
				pcall(function() oldModel:ScaleTo(oldScale.Value) end)
			end
		end)
		local oldScaleTween = TweenService:Create(oldScale, fadeOutInfo, { Value = 0.85 })
		oldScaleTween:Play()
		oldTrove:Add(oldScale)
		oldTrove:Add(conn)
		oldTrove:Add(oldScaleTween)
		oldScaleTween.Completed:Connect(function() oldScaleTween:Destroy() end)
	end

	-- ---- 0.4s: particle burst, audio, haptic ---------------------
	task.delay(VT.ParticleSpawnDelay * timeScale, function()
		if not newModel.Parent then return end
		if not reduced then self:_particleBurst(newModel, newTrove) end
		Knit.GetController("SoundController"):Play("HarborUpgrade", { volume = 0.5 })
		self:_upgradeHaptic()
	end)

	-- ---- 0.5s: dispose OLD, fade NEW in + scale overshoot --------
	task.delay(VT.UpgradeFadeOutDuration * timeScale, function()
		if oldTrove then oldTrove:Destroy() end

		local fadeInInfo = TweenInfo.new(VT.UpgradeFadeInDuration * timeScale, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		tweenAllToOriginalTransparency(newModel, fadeInInfo, newTrove)

		if reduced then
			pcall(function() newModel:ScaleTo(1.0) end)
		else
			-- Scale chain: 0.85 → 1.05 (overshoot via Back/Out), then 1.05 → 1.0 (settle).
			local newScale = Instance.new("NumberValue")
			newScale.Value = 0.85
			local conn = newScale:GetPropertyChangedSignal("Value"):Connect(function()
				if newModel.Parent then
					pcall(function() newModel:ScaleTo(newScale.Value) end)
				end
			end)
			newTrove:Add(newScale)
			newTrove:Add(conn)

			local overshootDur = math.max(0.01, (VT.UpgradeFadeInDuration - VT.UpgradeSettleDuration)) * timeScale
			local overshootInfo = TweenInfo.new(overshootDur, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local overTween = TweenService:Create(newScale, overshootInfo, { Value = VT.UpgradeOvershoot })
			overTween:Play()
			newTrove:Add(overTween)
			overTween.Completed:Connect(function()
				overTween:Destroy()
				local settleInfo = TweenInfo.new(VT.UpgradeSettleDuration * timeScale, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local settleTween = TweenService:Create(newScale, settleInfo, { Value = 1.0 })
				settleTween:Play()
				newTrove:Add(settleTween)
				settleTween.Completed:Connect(function() settleTween:Destroy() end)
			end)
		end

		-- Wire the new entry. If old tier was 1, despawn its debris in parallel.
		state.buildings[building.uid] = {
			model = newModel,
			trove = newTrove,
			building = newBuilding,
			plotOrigin = plotOrigin,
		}
		if oldTier == 1 then
			self:_clearDebrisForBuilding(plotOwnerId, building.uid, false)
		end
	end)
end

-- ====================================================================
-- PARTICLE BURST — temp Attachment + ParticleEmitter on the new model's
-- PrimaryPart. ~30 particles over 0.3s, then drain for 1s before cleanup.
-- ====================================================================
function HarborVisualController:_particleBurst(model: Model, trove: any)
	local primary = model.PrimaryPart; if not primary then return end
	local att = Instance.new("Attachment")
	att.Name = "UpgradeBurstAtt"
	att.Position = Vector3.new(0, primary.Size.Y / 2, 0) -- top of base
	att.Parent = primary
	local pe = Instance.new("ParticleEmitter")
	-- TODO: rbxassetid for upgrade-burst particle texture.
	-- Aesthetic: soft white-gold sparkle, ~32×32 sprite, alpha falloff to
	-- transparent edges, slight glow. Match the gold of TIER_COLORS.Mythic
	-- from CatchRevealUI so currencies of "specialness" feel consistent.
	pe.Texture = ""
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Lifetime = NumberRange.new(0.6, 1.0)
	pe.Rate = math.floor(VT.ParticleBurstCount / VT.ParticleBurstDuration)
	pe.Speed = NumberRange.new(8, 14)
	pe.SpreadAngle = Vector2.new(45, 45)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = att
	trove:Add(att)

	-- Disable emission after the burst, then despawn the attachment after
	-- emitted particles have drained (longest Lifetime + a little slack).
	task.delay(VT.ParticleBurstDuration, function()
		if att.Parent then pe.Enabled = false end
		task.delay(1.0, function() if att.Parent then att:Destroy() end end)
	end)
end

-- ====================================================================
-- HAPTIC
-- ====================================================================
function HarborVisualController:_upgradeHaptic()
	-- Mobile: single medium pulse via the Touch motor. Gamepad gets a small
	-- bump for parity (cheap, no opt-in needed). PC: noop.
	if not UserInputService.TouchEnabled and not UserInputService.GamepadEnabled then
		return
	end
	pcall(function()
		if UserInputService.GamepadEnabled then
			HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0.4)
			task.delay(0.12, function()
				pcall(function() HapticService:SetMotor(Enum.UserInputType.Gamepad1, Enum.VibrationMotor.Large, 0) end)
			end)
		end
	end)
end

-- ====================================================================
-- DEBRIS — deterministic per (plotOwnerId, buildingUid). Tagged
-- HarborDebris and carries a buildingUid attribute so the upgrade
-- transition can fade debris belonging to one specific building.
-- ====================================================================
local function debrisSeed(plotOwnerId: number, buildingUid: string): number
	local s = 0
	for i = 1, #buildingUid do s = (s * 31 + string.byte(buildingUid, i)) % 2 ^ 31 end
	return s + plotOwnerId
end

function HarborVisualController:_spawnDebris(plotOwnerId: number, building: any, plotOrigin: CFrame)
	local state = self:_plotState(plotOwnerId)
	if state.debrisCount >= VT.DebrisMaxPerPlot then return end

	local def = BuildingCatalog[building.kind]; if not def then return end
	local worldCF = GridUtil.gridToWorld(plotOrigin, building.gridX, building.gridZ, def.footprint, building.rotation)
	local center = worldCF.Position

	local rng = Random.new(debrisSeed(plotOwnerId, building.uid))
	local target = rng:NextInteger(VT.DebrisPerBuildingMin, VT.DebrisPerBuildingMax)
	-- Cull to plot budget.
	local room = VT.DebrisMaxPerPlot - state.debrisCount
	if target > room then target = room end

	local folder = self:_plotFolder(plotOwnerId)
	for _ = 1, target do
		local theta = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber() * VT.DebrisRadiusStuds
		local px = center.X + math.cos(theta) * radius
		local pz = center.Z + math.sin(theta) * radius
		local yRot = rng:NextNumber() * math.pi * 2
		local kindRoll = rng:NextInteger(1, 4)

		local part: BasePart
		if kindRoll == 1 then
			-- broken plank
			part = Instance.new("Part")
			part.Size = Vector3.new(0.4, 0.3, 2.5)
			part.Material = Enum.Material.WoodPlanks
			part.Color = Color3.fromRGB(90, 65, 40)
		elseif kindRoll == 2 then
			-- weed clump
			part = Instance.new("Part")
			part.Size = Vector3.new(1.2, 0.5, 1.2)
			part.Material = Enum.Material.Grass
			part.Color = Color3.fromRGB(80, 110, 60)
		elseif kindRoll == 3 then
			-- driftwood (wedge for shape variety)
			part = Instance.new("WedgePart")
			part.Size = Vector3.new(0.8, 0.6, 1.8)
			part.Material = Enum.Material.Wood
			part.Color = Color3.fromRGB(110, 85, 60)
		else
			-- rusted bucket (cylinder standing on end)
			part = Instance.new("Part")
			part.Shape = Enum.PartType.Cylinder
			part.Size = Vector3.new(1.1, 0.9, 0.9)  -- after Z 90° rotation: Y becomes height
			part.Material = Enum.Material.Metal
			part.Color = Color3.fromRGB(120, 70, 40)
		end

		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part:SetAttribute("buildingUid", building.uid)

		if kindRoll == 4 then
			-- Cylinder caps default on X; rotate around Z by 90° to stand it upright.
			part.CFrame = CFrame.new(px, 1.7, pz) * CFrame.Angles(0, yRot, math.pi / 2)
		else
			part.CFrame = CFrame.new(px, 1.7 + part.Size.Y / 2, pz) * CFrame.Angles(0, yRot, 0)
		end
		part.Parent = folder
		CollectionService:AddTag(part, DEBRIS_TAG)
		state.debrisCount += 1
	end
end

-- Fade out (or snap-destroy if reduced motion) every debris part tagged
-- to this building. `immediate=true` skips the fade — used on building
-- removal, where we don't want the debris hanging around.
function HarborVisualController:_clearDebrisForBuilding(plotOwnerId: number, buildingUid: string, immediate: boolean)
	local folder = self:_ensureRoot():FindFirstChild(tostring(plotOwnerId))
	if not folder then return end
	local reduced = MotionUtil.reducedMotionEnabled()
	local state = self:_plotState(plotOwnerId)
	local fadeInfo = TweenInfo.new(VT.DebrisFadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart")
			and part:GetAttribute("buildingUid") == buildingUid
			and CollectionService:HasTag(part, DEBRIS_TAG)
		then
			state.debrisCount = math.max(0, state.debrisCount - 1)
			if immediate or reduced then
				part:Destroy()
			else
				local fade = TweenService:Create(part, fadeInfo, { Transparency = 1 })
				fade:Play()
				fade.Completed:Connect(function()
					fade:Destroy()
					if part.Parent then part:Destroy() end
				end)
			end
		end
	end
end

-- ====================================================================
-- PUBLIC QUERIES — used by HarborEditController for hover highlight and
-- ghost overlap-check.
-- ====================================================================

-- Returns the live visual Model for a building uid, or nil if not spawned yet.
function HarborVisualController:GetVisualModel(uid: string): Model?
	for _, state in pairs(self._plots) do
		local entry = state.buildings[uid]
		if entry then return entry.model end
	end
	return nil
end

-- Returns the building data tables for every building owned by userId,
-- in the same shape as profile.buildings so GridUtil.buildOccupancy works.
function HarborVisualController:GetBuildingsForOwner(userId: number): {any}
	local key = tostring(userId)
	local state = self._plots[key]
	if not state then return {} end
	local out = {}
	for _, entry in pairs(state.buildings) do
		table.insert(out, entry.building)
	end
	return out
end

-- ====================================================================
-- LIFECYCLE
-- ====================================================================
function HarborVisualController:KnitStart()
	if self._knitStartDone then
		return
	end
	self._knitStartDone = true
	print("[HarborVisualController] KnitStart")
	self:_ensureRoot()
	local HarborVisualService = Knit.GetService("HarborVisualService")
	local PlayerDataService = Knit.GetService("PlayerDataService")

	HarborVisualService.HarborVisualUpdate:Connect(function(payload)
		local ok, err = pcall(function()
			self:_onUpdate(payload)
		end)
		if not ok then
			warn("[HarborVisualController] HarborVisualUpdate failed:", err)
		end
	end)
	HarborVisualService.HarborVisualRemove:Connect(function(plotOwnerId: number, buildingUid: string)
		self:_onRemove(plotOwnerId, buildingUid)
	end)
	HarborVisualService.HarborVisualClear:Connect(function(plotOwnerId: number)
		self:_onClear(plotOwnerId)
	end)

	-- Profile / building snapshots can arrive after the first replay.
	PlayerDataService.ProfileLoaded:Connect(function()
		task.defer(function()
			self:_requestWorldReplay(1)
		end)
	end)
	PlayerDataService.BuildingsChanged:Connect(function()
		task.defer(function()
			self:_requestWorldReplay(1)
		end)
	end)

	-- Server anchors can appear after the first replay; resync visuals.
	local anchorDebounce = false
	self._trove = self._trove or Trove.new()
	self._trove:Add(CollectionService:GetInstanceAddedSignal(BUILDING_ANCHOR_TAG):Connect(function()
		if anchorDebounce then return end
		anchorDebounce = true
		task.delay(0.5, function()
			anchorDebounce = false
			self:_requestWorldReplay(1)
		end)
	end))

	self:_requestWorldReplay()
end

-- Count spawned harbor building models under HarborVisuals.
function HarborVisualController:_countBuildingModels(): number
	local root = self:_ensureRoot()
	local count = 0
	for _, child in ipairs(root:GetChildren()) do
		for _, m in ipairs(child:GetChildren()) do
			if m:IsA("Model") then
				count += 1
			end
		end
	end
	return count
end

-- Server join-replay can race KnitStart (events deferred) or run before
-- profiles are ready. Retry briefly so the dock is not empty on first join.
function HarborVisualController:_requestWorldReplay(attempt: number?)
	local attemptNum = attempt or 1
	local maxAttempts = 4
	local HarborVisualService = Knit.GetService("HarborVisualService")

	local replayPending = true
	task.delay(8, function()
		if replayPending then
			warn("[HarborVisualController] RequestWorldReplay still pending after 8s — retrying")
			self:_requestWorldReplay((attemptNum :: number) + 1)
		end
	end)

	HarborVisualService:RequestWorldReplay():andThen(function()
		replayPending = false
		local deadline = os.clock() + 2.5
		local count = 0
		while os.clock() < deadline do
			task.wait()
			count = self:_countBuildingModels()
			if count > 0 then break end
		end

		print(("[HarborVisualController] Replay done — %d building model(s) in HarborVisuals (attempt %d)"):format(count, attemptNum))
		if count == 0 and attemptNum < maxAttempts then
			task.delay(0.75 * attemptNum, function()
				self:_requestWorldReplay(attemptNum + 1)
			end)
			return
		end
		if count == 0 then
			warn("[HarborVisualController] No building visuals after retries — install ReplicatedStorage.Assets.Buildings (see scripts/Studio/MCP_HarborBuildings.md) or check Output for spawn errors")
		end
	end):catch(function(err)
		warn("[HarborVisualController] RequestWorldReplay failed:", err)
	end)
end

return HarborVisualController
