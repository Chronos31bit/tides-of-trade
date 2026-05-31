--!strict
-- WorldFXController.lua
-- Client-side weather FX hub:
--   * global rain field (grid of box emitters, rate-budget capped)
--   * fog sheet at harbor height (optional GroundMist template; atmosphere-first)
--   * storm lightning flash (dedicated ColorCorrection, rate-limited >= 8 s)
--   * weather sound crossfade (RainLoop, WindStorm, FogAmbient, ThunderRumble)
--   * client-side weather ColorCorrection tween
--
-- Studio templates: see assets/weather/README.md

local GuiService        = game:GetService("GuiService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")

local Knit       = require(ReplicatedStorage.Packages.Knit)
local Trove      = require(ReplicatedStorage.Packages.Trove)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AssetIds       = require(script.Parent.Parent.AssetIds)
local MotionUtil     = require(ReplicatedStorage.Shared.Util.MotionUtil)
local WeatherVisuals = require(ReplicatedStorage.Shared.Util.WeatherVisuals)

local RAIN_CFG = GameConfig.Weather.Rain
local FOG_CFG  = GameConfig.Weather.Fog
local LIGHTNING_CFG = GameConfig.Weather.Lightning
local SOUND_CFG = GameConfig.Weather.Sound
local TRANS_CFG = GameConfig.Weather.Transition
local ATTR_WEATHER = GameConfig.Weather.WorkspaceAttribute

local LIGHTNING_CC_NAME = "TidesLightningFlash"
local RAIN_FIELD_NAME = "WorldFX_RainField"
local FOG_FIELD_NAME = "WorldFX_FogField"
-- Bump when rain field layout/texture changes so Play Solo rebuilds instead of reusing invisible emitters.
local RAIN_FIELD_REVISION = 5

local WorldFXController = Knit.CreateController({
	Name = "WorldFXController",
	_currentWeather = "Clear",
	_previousWeather = "Clear",
	_targetTideLevel = -1,
	_rainVolumeTemplate = nil :: Instance?,
	_stormRainTemplate = nil :: Instance?,
	_fogMistTemplate = nil :: Instance?,
	_rainTrove = nil :: any,
	_rainEmitters = {} :: {ParticleEmitter},
	_rainCells = {} :: {BasePart},
	_rainGridCenter = Vector3.zero,
	_rainKind = "" :: string,
	_rainRevision = 0,
	_fogTrove = nil :: any,
	_fogEmitters = {} :: {ParticleEmitter},
	_fogCells = {} :: {BasePart},
	_fogGridCenter = Vector3.zero,
	_lightningTrove = nil :: any,
	_lightningCC = nil :: ColorCorrectionEffect?,
	_baseSpread = Vector2.new(12, 12),
	_sound = nil :: any,
	_baseVol = 0.5,
	_useProceduralRain = false,
	_loggedRainSource = false,
	_initialApplied = false,
})

local function isRainyWeather(weather: string): boolean
	return weather == "Rain" or weather == "Storm"
end

local function rainTextureId(): string
	local override = AssetIds.Images and AssetIds.Images.RainStreak
	if type(override) == "string" and override ~= "" then
		return override
	end
	if RAIN_CFG.PreferBuiltInTexture and type(RAIN_CFG.BuiltInTextureId) == "string" then
		return RAIN_CFG.BuiltInTextureId
	end
	if type(RAIN_CFG.PlaceholderTextureId) == "string" and RAIN_CFG.PlaceholderTextureId ~= "" then
		return RAIN_CFG.PlaceholderTextureId
	end
	return RAIN_CFG.FallbackTextureId or "rbxasset://textures/particles/smoke_main.dds"
end

local function applyRainEmitterShape(emitter: ParticleEmitter)
	if RAIN_CFG.UseBoxEmissionShape then
		safeSetBoxEmission(emitter)
	end
end

local function applyFogEmitterShape(emitter: ParticleEmitter)
	if FOG_CFG.UseBoxEmissionShape then
		safeSetBoxEmission(emitter)
	end
end

local function fogTextureId(): string
	local override = AssetIds.Images and AssetIds.Images.FogMist
	if type(override) == "string" and override ~= "" then
		return override
	end
	return FOG_CFG.TexturePlaceholderId
end

local function adjustDuration(duration: number, reduced: boolean): number
	if reduced then
		return duration * TRANS_CFG.ReducedMotionDurationScale
	end
	return duration
end

local function pinPartForStreaming(part: BasePart)
	-- Client-local FX parts must not stream out while the player is nearby.
	local ok = pcall(function()
		(part :: any).StreamingMode = Enum.StreamingMode.Atomic
	end)
	if not ok then
		pcall(function()
			(part :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
	end
end

local function safeSetBoxEmission(emitter: ParticleEmitter)
	pcall(function()
		emitter.Shape = Enum.ParticleEmitterShape.Box
	end)
end

local function collectParticleEmitters(root: Instance): {ParticleEmitter}
	local list: {ParticleEmitter} = {}
	if root:IsA("ParticleEmitter") then
		table.insert(list, root)
		return list
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			table.insert(list, desc)
		end
	end
	return list
end

local function getFollowPosition(): Vector3?
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local player = Players.LocalPlayer
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return cam.CFrame.Position
end

-- Tutorial rain: world-upright sheet above HumanoidRootPart (no character yaw).
local function getRainFollowCFrame(): CFrame?
	local player = Players.LocalPlayer
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local offset = RAIN_CFG.FollowOffsetStuds or Vector3.new(0, 25, 0)
		return CFrame.new(hrp.Position + offset)
	end
	local base = getFollowPosition()
	if not base then
		return nil
	end
	local offset = RAIN_CFG.FollowOffsetStuds or Vector3.new(0, 25, 0)
	return CFrame.new(base + offset)
end

function WorldFXController:_rainKindForWeather(weather: string): string
	if weather == "Storm" and self._stormRainTemplate then
		return "StormTemplate"
	end
	if self._rainVolumeTemplate then
		return if weather == "Storm" then "RainTemplateStormMult" else "RainTemplate"
	end
	return "Procedural"
end

function WorldFXController:_resolveRainTemplate(weather: string): Instance?
	if weather == "Storm" and self._stormRainTemplate then
		return self._stormRainTemplate
	end
	return self._rainVolumeTemplate
end

function WorldFXController:_logRainSourceOnce(kind: string)
	if self._loggedRainSource then return end
	self._loggedRainSource = true
	print(("[WorldFX] Rain: %s"):format(kind))
end

local function applyRainTutorialStyle(emitter: ParticleEmitter)
	if RAIN_CFG.ParticleColor then
		emitter.Color = ColorSequence.new(RAIN_CFG.ParticleColor)
	end
	if RAIN_CFG.Transparency then
		emitter.Transparency = RAIN_CFG.Transparency
	end
	local lightEmission = RAIN_CFG.LightEmission
	if type(lightEmission) == "number" then
		emitter.LightEmission = lightEmission
	end
	emitter.LightInfluence = RAIN_CFG.LightInfluence or 0
	emitter.VelocityInheritance = 0
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Drag = 0

	local squash = RAIN_CFG.EmitterSquash
	if type(squash) == "number" then
		pcall(function()
			emitter.Squash = NumberSequence.new(squash)
		end)
	end

	local particleSize = RAIN_CFG.EmitterSize
	if type(particleSize) == "number" then
		emitter.Size = NumberSequence.new(particleSize)
	end

	if RAIN_CFG.UseFacingCameraWorldUp then
		pcall(function()
			emitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		end)
	end

	if RAIN_CFG.LockedToPart == true then
		emitter.LockedToPart = true
	end
end

function WorldFXController:_createProceduralRainEmitter(): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "WorldFX_Rain"
	pe.Texture = rainTextureId()
	pe.Lifetime = NumberRange.new(RAIN_CFG.Lifetime, RAIN_CFG.Lifetime)
	pe.Speed = RAIN_CFG.EmitterSpeed or RAIN_CFG.ProceduralSpeed
	pe.SpreadAngle = RAIN_CFG.EmitterSpreadAngle or RAIN_CFG.ProceduralSpreadAngle
	applyRainEmitterShape(pe)
	applyRainTutorialStyle(pe)
	self._baseSpread = RAIN_CFG.EmitterSpreadAngle or RAIN_CFG.ProceduralSpreadAngle
	return pe
end

function WorldFXController:_tearDownRain()
	if self._rainTrove then
		self._rainTrove:Destroy()
		self._rainTrove = nil
	end
	table.clear(self._rainEmitters)
	table.clear(self._rainCells)
	self._rainGridCenter = Vector3.zero
	self._rainKind = ""
	self._rainRevision = 0
end

function WorldFXController:_rainCellCount(): number
	local n = RAIN_CFG.GlobalGridCount
	return math.max(1, n) * math.max(1, n)
end

function WorldFXController:_computeRainRateBudget(weather: string, reduced: boolean): number
	local budget = if weather == "Storm"
		then (RAIN_CFG.EmitterRateStorm or RAIN_CFG.RateBudgetStorm)
		else (RAIN_CFG.EmitterRate or RAIN_CFG.RateBudgetRain)
	if reduced then
		budget *= RAIN_CFG.ReducedMotionRateMultiplier
	end
	return budget
end

function WorldFXController:_pickPrimaryEmitterSource(sources: {ParticleEmitter}): ParticleEmitter?
	local best: ParticleEmitter? = nil
	local bestRate = -1
	for _, src in ipairs(sources) do
		if src.Rate > bestRate then
			bestRate = src.Rate
			best = src
		end
	end
	return best
end

function WorldFXController:_tuneRainEmitter(emitter: ParticleEmitter, perCellRate: number, reduced: boolean)
	emitter.Texture = rainTextureId()
	emitter.Lifetime = NumberRange.new(RAIN_CFG.Lifetime, RAIN_CFG.Lifetime)
	emitter.Speed = RAIN_CFG.EmitterSpeed or RAIN_CFG.ProceduralSpeed
	emitter.Rate = perCellRate
	emitter.Enabled = true
	applyRainEmitterShape(emitter)
	applyRainTutorialStyle(emitter)
	local spread = RAIN_CFG.EmitterSpreadAngle or self._baseSpread
	emitter.SpreadAngle = if reduced then Vector2.new(0, 0) else spread
end

function WorldFXController:_setRainRates(weather: string, reduced: boolean, duration: number)
	local budget = self:_computeRainRateBudget(weather, reduced)
	local perCell = budget / self:_rainCellCount()
	for _, emitter in ipairs(self._rainEmitters) do
		if duration > 0 then
			local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(emitter, info, { Rate = perCell }):Play()
		else
			emitter.Rate = perCell
		end
	end
end

function WorldFXController:_repositionRainGrid(followCFrame: CFrame)
	if RAIN_CFG.UseTutorialFollower then
		for _, part in ipairs(self._rainCells) do
			part.CFrame = followCFrame
		end
		return
	end
	local pos = followCFrame.Position
	local gridN = RAIN_CFG.GlobalGridCount
	local half = math.floor(gridN / 2)
	local cell = RAIN_CFG.GlobalCellSizeStuds
	for index, part in ipairs(self._rainCells) do
		local gx = (index - 1) % gridN - half
		local gz = math.floor((index - 1) / gridN) - half
		part.CFrame = CFrame.new(pos.X + gx * cell, pos.Y, pos.Z + gz * cell)
	end
end

function WorldFXController:_startWindSway(emitters: {ParticleEmitter}, trove: any)
	local spread = RAIN_CFG.WindSwaySpreadDegrees
	local base = self._baseSpread
	local target = Vector2.new(base.X + spread, base.Y + spread)
	local info = TweenInfo.new(
		RAIN_CFG.WindSwayPeriodSeconds,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,
		true
	)
	for _, emitter in ipairs(emitters) do
		local tween = TweenService:Create(emitter, info, { SpreadAngle = target })
		tween:Play()
		trove:Add(tween)
	end
end

function WorldFXController:_createCellEmitter(
	template: Instance?,
	hostPart: BasePart,
	trove: any,
	perCellRate: number,
	reduced: boolean
): ParticleEmitter
	local pe: ParticleEmitter
	local forceProcedural = RAIN_CFG.AlwaysUseProceduralEmitters == true
	if template and not forceProcedural then
		local sources = collectParticleEmitters(template)
		local primary = self:_pickPrimaryEmitterSource(sources)
		if primary then
			pe = primary:Clone()
			pe.Name = "WorldFX_Rain"
			self._baseSpread = pe.SpreadAngle
		else
			pe = self:_createProceduralRainEmitter()
			self._useProceduralRain = true
		end
	else
		pe = self:_createProceduralRainEmitter()
		self._useProceduralRain = true
	end
	self:_tuneRainEmitter(pe, perCellRate, reduced)
	pe.Parent = hostPart
	local burst = RAIN_CFG.StartupEmitBurst
	if burst and burst > 0 then
		pe:Emit(burst)
	end
	trove:Add(pe)
	return pe
end

function WorldFXController:_buildRainField(weather: string, reduced: boolean)
	self:_tearDownRain()

	local followPos = getFollowPosition()
	local followCFrame = getRainFollowCFrame()
	if not followPos or not followCFrame then
		warn("[WorldFX] No follow position — rain deferred")
		return
	end

	local kind = self:_rainKindForWeather(weather)
	local template = self:_resolveRainTemplate(weather)
	self._useProceduralRain = template == nil
	self._rainKind = kind

	if template and not self._loggedRainSource then
		local logName = if weather == "Storm" and self._stormRainTemplate
			then "Assets.Weather.Storm.StormRain template (global grid)"
			else "Assets.Weather.Rain.RainVolume template (global grid)"
		self:_logRainSourceOnce(logName)
	elseif not template then
		self:_logRainSourceOnce("SuperCatHeroes tutorial rain (sparkle + squash 3)")
	end

	local trove = Trove.new()
	local fieldFolder = Instance.new("Folder")
	fieldFolder.Name = RAIN_FIELD_NAME
	fieldFolder.Parent = Workspace
	trove:Add(fieldFolder)

	local useTutorial = RAIN_CFG.UseTutorialFollower == true
	local gridN = if useTutorial then 1 else RAIN_CFG.GlobalGridCount
	local footprint = RAIN_CFG.PartFootprintStuds or RAIN_CFG.GlobalCellSizeStuds or 50
	local partSize = Vector3.new(footprint, 1, footprint)
	local budget = self:_computeRainRateBudget(weather, reduced)
	local perCellRate = budget / math.max(1, gridN * gridN)

	self._rainGridCenter = followCFrame.Position
	local emitters: {ParticleEmitter} = {}
	local cells: {BasePart} = {}

	for gz = 0, gridN - 1 do
		for gx = 0, gridN - 1 do
			local part = Instance.new("Part")
			part.Name = ("RainCell_%d_%d"):format(gx, gz)
			part.Size = partSize
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			pinPartForStreaming(part)
			part.Parent = fieldFolder

			local pe = self:_createCellEmitter(template, part, trove, perCellRate, reduced)
			table.insert(emitters, pe)
			table.insert(cells, part)
			trove:Add(part)
		end
	end

	self:_repositionRainGrid(followCFrame)

	if not reduced and (RAIN_CFG.WindSwaySpreadDegrees or 0) > 0 then
		self:_startWindSway(emitters, trove)
	end

	trove:Add(RunService.Heartbeat:Connect(function()
		if #cells == 0 then
			return
		end
		local cf = getRainFollowCFrame()
		if not cf then
			return
		end
		self._rainGridCenter = cf.Position
		self:_repositionRainGrid(cf)
	end))

	self._rainTrove = trove
	self._rainEmitters = emitters
	self._rainCells = cells
	self._rainRevision = RAIN_FIELD_REVISION
end

function WorldFXController:_applyRain(weather: string, duration: number)
	local reduced = MotionUtil.reducedMotionEnabled()
	local wantsRain = isRainyWeather(weather)

	if not wantsRain then
		self:_tearDownRain()
		return
	end

	local neededKind = self:_rainKindForWeather(weather)
	if #self._rainEmitters > 0 and self._rainKind == neededKind and self._rainRevision == RAIN_FIELD_REVISION then
		self:_setRainRates(weather, reduced, duration)
		return
	end

	local buildOk, buildErr = pcall(function()
		self:_buildRainField(weather, reduced)
	end)
	if not buildOk then
		warn("[WorldFX] _buildRainField error:", buildErr)
	elseif #self._rainEmitters == 0 then
		warn("[WorldFX] Rain field built with zero emitters")
	elseif duration > 0 and #self._rainEmitters > 0 then
		self:_setRainRates(weather, reduced, duration)
	end
end

function WorldFXController:_tearDownFog()
	if self._fogTrove then
		self._fogTrove:Destroy()
		self._fogTrove = nil
	end
	table.clear(self._fogEmitters)
	table.clear(self._fogCells)
	self._fogGridCenter = Vector3.zero
end

function WorldFXController:_fogCellCount(): number
	local n = FOG_CFG.GlobalGridCount
	return math.max(1, n) * math.max(1, n)
end

function WorldFXController:_computeFogRateBudget(reduced: boolean): number
	local budget = FOG_CFG.RateBudget
	if reduced then
		budget *= FOG_CFG.ReducedMotionRateMultiplier
	end
	return budget
end

function WorldFXController:_createProceduralFogEmitter(): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "WorldFX_Fog"
	pe.Texture = fogTextureId()
	pe.Lifetime = NumberRange.new(FOG_CFG.Lifetime, FOG_CFG.Lifetime)
	pe.Speed = FOG_CFG.SpeedRange
	pe.SpreadAngle = FOG_CFG.SpreadAngle
	pe.EmissionDirection = Enum.NormalId.Top
	pe.LightEmission = 0.08
	pe.LightInfluence = 0.4
	pe.Drag = 1.2
	pe.RotSpeed = NumberRange.new(-3, 3)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(0.5, 8),
		NumberSequenceKeypoint.new(1, 12),
	})
	pe.Color = ColorSequence.new(Color3.fromRGB(215, 220, 228))
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(0.4, 0.6),
		NumberSequenceKeypoint.new(0.8, 0.65),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	applyFogEmitterShape(pe)
	return pe
end

function WorldFXController:_tuneFogEmitter(emitter: ParticleEmitter, perCellRate: number)
	emitter.Texture = fogTextureId()
	emitter.Lifetime = NumberRange.new(FOG_CFG.Lifetime, FOG_CFG.Lifetime)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Speed = FOG_CFG.SpeedRange
	emitter.SpreadAngle = FOG_CFG.SpreadAngle
	emitter.Rate = perCellRate
	emitter.Enabled = true
	applyFogEmitterShape(emitter)
	-- Store templates are often nearly invisible; enforce readable mist.
	local firstKp = emitter.Transparency.Keypoints[1]
	if firstKp and firstKp.Value > 0.7 then
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.4, 0.42),
			NumberSequenceKeypoint.new(0.8, 0.48),
			NumberSequenceKeypoint.new(1, 0.9),
		})
	end
end

function WorldFXController:_repositionFogGrid(center: Vector3)
	local gridN = FOG_CFG.GlobalGridCount
	local half = math.floor(gridN / 2)
	local cell = FOG_CFG.GlobalCellSizeStuds
	local y = center.Y + FOG_CFG.SheetHeightOffsetStuds
	for index, part in ipairs(self._fogCells) do
		local gx = (index - 1) % gridN - half
		local gz = math.floor((index - 1) / gridN) - half
		part.CFrame = CFrame.new(center.X + gx * cell, y, center.Z + gz * cell)
	end
end

function WorldFXController:_createCellFogEmitter(
	template: Instance?,
	attachment: Attachment,
	trove: any,
	perCellRate: number
): ParticleEmitter
	local pe: ParticleEmitter
	local forceProcedural = FOG_CFG.AlwaysUseProceduralEmitters == true
	if template and not forceProcedural then
		local sources = collectParticleEmitters(template)
		local primary = self:_pickPrimaryEmitterSource(sources)
		if primary then
			pe = primary:Clone()
			pe.Name = "WorldFX_Fog"
		else
			pe = self:_createProceduralFogEmitter()
		end
	else
		pe = self:_createProceduralFogEmitter()
	end
	self:_tuneFogEmitter(pe, perCellRate)
	pe.Parent = attachment
	local burst = FOG_CFG.StartupEmitBurst
	if burst and burst > 0 then
		pe:Emit(burst)
	end
	trove:Add(pe)
	return pe
end

function WorldFXController:_buildFogField()
	self:_tearDownFog()

	if FOG_CFG.EnableParticleFog == false then
		return
	end

	local followPos = getFollowPosition()
	if not followPos then
		warn("[WorldFX] No follow position — fog deferred")
		return
	end

	local template = self._fogMistTemplate
	if not template and not FOG_CFG.UseParticlesWhenTemplateMissing then
		return
	end

	local reduced = MotionUtil.reducedMotionEnabled()
	local budget = self:_computeFogRateBudget(reduced)
	local perCellRate = budget / self:_fogCellCount()

	local trove = Trove.new()
	local fieldFolder = Instance.new("Folder")
	fieldFolder.Name = FOG_FIELD_NAME
	fieldFolder.Parent = Workspace
	trove:Add(fieldFolder)

	local gridN = FOG_CFG.GlobalGridCount
	local cellSize = FOG_CFG.GlobalCellSizeStuds
	local partSize = Vector3.new(cellSize, 1, cellSize)

	self._fogGridCenter = Vector3.new(followPos.X, followPos.Y, followPos.Z)
	local emitters: {ParticleEmitter} = {}
	local cells: {BasePart} = {}

	for gz = 0, gridN - 1 do
		for gx = 0, gridN - 1 do
			local part = Instance.new("Part")
			part.Name = ("FogCell_%d_%d"):format(gx, gz)
			part.Size = partSize
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			pinPartForStreaming(part)
			part.Parent = fieldFolder

			local attach = Instance.new("Attachment")
			attach.Name = "FogAttach"
			attach.Parent = part

			local pe = self:_createCellFogEmitter(template, attach, trove, perCellRate)
			table.insert(emitters, pe)
			table.insert(cells, part)
			trove:Add(part)
			trove:Add(attach)
		end
	end

	self:_repositionFogGrid(self._fogGridCenter)

	local interval = FOG_CFG.GlobalFollowIntervalSeconds
	local accum = 0
	trove:Add(RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < interval then
			return
		end
		accum = 0
		local pos = getFollowPosition()
		if not pos or #cells == 0 then
			return
		end
		self._fogGridCenter = Vector3.new(pos.X, pos.Y, pos.Z)
		self:_repositionFogGrid(self._fogGridCenter)
	end))

	self._fogTrove = trove
	self._fogEmitters = emitters
	self._fogCells = cells
end

function WorldFXController:_applyFog(weather: string, _duration: number)
	if weather ~= "Fog" then
		self:_tearDownFog()
		return
	end
	if #self._fogEmitters > 0 then
		return
	end
	local fogOk, fogErr = pcall(function()
		self:_buildFogField()
	end)
	if not fogOk then
		warn("[WorldFX] _buildFogField error:", fogErr)
	end
end

function WorldFXController:_ensureLightningCC(): ColorCorrectionEffect
	if self._lightningCC and self._lightningCC.Parent then
		return self._lightningCC
	end
	local existing = Lighting:FindFirstChild(LIGHTNING_CC_NAME)
	local cc: ColorCorrectionEffect
	if existing and existing:IsA("ColorCorrectionEffect") then
		cc = existing
	else
		if existing then existing:Destroy() end
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = LIGHTNING_CC_NAME
		cc.Brightness = 0
		cc.Saturation = 0
		cc.Contrast = 0
		cc.Enabled = true
		cc.Parent = Lighting
	end
	self._lightningCC = cc
	return cc
end

function WorldFXController:_fireOneLightning()
	if MotionUtil.reducedMotionEnabled() then return end
	local cc = self:_ensureLightningCC()
	cc.Brightness = 0
	cc.Saturation = 0

	local attackInfo = TweenInfo.new(LIGHTNING_CFG.FlashAttackSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local attack = TweenService:Create(cc, attackInfo, {
		Brightness = LIGHTNING_CFG.FlashBrightnessDelta,
		Saturation = LIGHTNING_CFG.FlashSaturationDelta,
	})
	attack.Completed:Connect(function()
		if not cc or not cc.Parent then return end
		task.wait(LIGHTNING_CFG.FlashHoldSeconds)
		local decayInfo = TweenInfo.new(LIGHTNING_CFG.FlashDecaySeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		TweenService:Create(cc, decayInfo, { Brightness = 0, Saturation = 0 }):Play()
	end)
	attack:Play()

	local range = LIGHTNING_CFG.ThunderDelayRangeSeconds
	local delay = range.Min + (range.Max - range.Min) * math.random()
	task.delay(delay, function()
		if self._currentWeather ~= "Storm" then return end
		local sc = self._sound
		if sc and type(sc.Play) == "function" then
			sc:Play("ThunderRumble", { volume = SOUND_CFG.ThunderVolume })
		end
	end)
end

function WorldFXController:_applyLightning(weather: string)
	if self._lightningTrove then
		self._lightningTrove:Destroy()
		self._lightningTrove = nil
	end
	if weather ~= "Storm" then
		if self._lightningCC then
			self._lightningCC.Brightness = 0
			self._lightningCC.Saturation = 0
		end
		return
	end
	if MotionUtil.reducedMotionEnabled() then return end

	local trove = Trove.new()
	self._lightningTrove = trove
	local active = true
	trove:Add(function() active = false end)

	task.spawn(function()
		while active and self._currentWeather == "Storm" do
			local minS = LIGHTNING_CFG.MinIntervalSeconds
			local maxS = LIGHTNING_CFG.MaxIntervalSeconds
			local wait_ = minS + (maxS - minS) * math.random()
			task.wait(wait_)
			if not active or self._currentWeather ~= "Storm" then break end
			self:_fireOneLightning()
		end
	end)
end

function WorldFXController:_applyWeatherSounds(weather: string, _previous: string, duration: number)
	local sc = self._sound
	if not sc or type(sc.FadeLoop) ~= "function" then return end
	local fade = if duration > 0 then duration else SOUND_CFG.CrossfadeSeconds

	if weather == "Rain" then
		sc:FadeLoop("RainLoop", SOUND_CFG.RainVolume, fade)
	elseif weather == "Storm" then
		sc:FadeLoop("RainLoop", SOUND_CFG.StormRainVolume, fade)
	else
		sc:FadeLoop("RainLoop", 0, fade)
	end

	if weather == "Storm" then
		sc:FadeLoop("WindStorm", SOUND_CFG.WindVolume, fade)
	else
		sc:FadeLoop("WindStorm", 0, fade)
	end

	if weather == "Fog" then
		sc:FadeLoop("FogAmbient", SOUND_CFG.FogAmbientVolume, fade)
	else
		sc:FadeLoop("FogAmbient", 0, fade)
	end
end

function WorldFXController:_onWeatherChanged(weather: string, previousWeather: string?, durationSeconds: number?)
	local duplicateSkip = false
	if self._initialApplied and weather == self._currentWeather then
		local rainOk = not isRainyWeather(weather) or #self._rainEmitters > 0
		local fogOk = weather ~= "Fog" or #self._fogEmitters > 0
		if rainOk and fogOk then
			duplicateSkip = true
		end
	end
	if duplicateSkip then
		return
	end
	self._previousWeather = previousWeather or self._currentWeather
	self._currentWeather = weather
	self._initialApplied = true

	local reduced = MotionUtil.reducedMotionEnabled()
	local duration = adjustDuration(durationSeconds or 0, reduced)

	local sound = self._sound
	local baseVol = self._baseVol
	if sound then
		if weather == "Storm" then
			sound:SetAmbientVolume(0.7)
		elseif weather == "Rain" then
			sound:SetAmbientVolume(0.55)
		else
			sound:SetAmbientVolume(baseVol)
		end
	end

	self:_applyRain(weather, duration)
	self:_applyFog(weather, duration)
	self:_applyLightning(weather)
	self:_applyWeatherSounds(weather, self._previousWeather, duration)
	WeatherVisuals.applyColorCorrection(weather, duration)
	WeatherVisuals.applyDistanceFog(weather, duration)
end

function WorldFXController:KnitStart()
	local TideService    = Knit.GetService("TideService")
	local WeatherService = Knit.GetService("WeatherService")
	local HarborService  = Knit.GetService("HarborService")
	local sound = Knit.GetController("SoundController")
	local baseVol = GameConfig.Audio.AmbientBaseVolume
	self._sound = sound
	self._baseVol = baseVol

	local trove = Trove.new()

	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	if assets then
		local weatherFolder = assets:FindFirstChild("Weather")
		if weatherFolder then
			local rainFolder = weatherFolder:FindFirstChild("Rain")
			local rainVol = rainFolder and rainFolder:FindFirstChild("RainVolume")
			if rainVol then
				self._rainVolumeTemplate = rainVol
			end
			-- Legacy: RainEmitter ParticleEmitter still works.
			local legacyEmitter = rainFolder and rainFolder:FindFirstChild("RainEmitter")
			if legacyEmitter and legacyEmitter:IsA("ParticleEmitter") and not self._rainVolumeTemplate then
				self._rainVolumeTemplate = legacyEmitter
			end

			local stormFolder = weatherFolder:FindFirstChild("Storm")
			local stormRain = stormFolder and stormFolder:FindFirstChild("StormRain")
			if stormRain then
				self._stormRainTemplate = stormRain
			end

			local fogFolder = weatherFolder:FindFirstChild("Fog")
			local groundMist = fogFolder and fogFolder:FindFirstChild("GroundMist")
			if groundMist then
				self._fogMistTemplate = groundMist
			end
		end
		if not self._rainVolumeTemplate then
			warn("[WorldFX] Missing Assets.Weather.Rain.RainVolume — using procedural rain")
		end
	else
		warn("[WorldFX] Missing ReplicatedStorage.Assets — using procedural rain")
	end
	TideService.TideChanged:Connect(function(state, level)
		self._targetTideLevel = level
		Workspace:SetAttribute("TideState", state)
		Workspace:SetAttribute("TideOffset", level * 1.5)
	end)

	local function handleWeather(weather: string, previousWeather: string?, durationSeconds: number?)
		if type(weather) ~= "string" or weather == "" then return end
		self:_onWeatherChanged(weather, previousWeather, durationSeconds)
	end

	trove:Add(WeatherService.WeatherChanged:Connect(handleWeather))

	trove:Add(Workspace:GetAttributeChangedSignal(ATTR_WEATHER):Connect(function()
		local weather = Workspace:GetAttribute(ATTR_WEATHER)
		if type(weather) == "string" then
			handleWeather(weather, self._currentWeather, 0)
		end
	end))

	local function retryWeatherFxIfNeeded(source: string)
		if isRainyWeather(self._currentWeather) and #self._rainEmitters == 0 then
			self:_applyRain(self._currentWeather, 0)
		end
		if self._currentWeather == "Fog" and #self._fogEmitters == 0 then
			self:_applyFog(self._currentWeather, 0)
		end
	end

	trove:Add(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		retryWeatherFxIfNeeded("camera")
	end))

	local player = Players.LocalPlayer
	if player then
		trove:Add(player.CharacterAdded:Connect(function()
			task.defer(function()
				retryWeatherFxIfNeeded("character")
			end)
		end))
		if player.Character then
			task.defer(function()
				retryWeatherFxIfNeeded("character_existing")
			end)
		end
	end

	trove:Add(GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
		if isRainyWeather(self._currentWeather) then
			self:_tearDownRain()
			self:_applyRain(self._currentWeather, 0)
		end
		if self._currentWeather == "Fog" then
			self:_tearDownFog()
			self:_applyFog(self._currentWeather, 0)
		end
		self:_applyLightning(self._currentWeather)
	end))

	HarborService.HarborVisualUpdate:Connect(function(uid: string, kind: string, tier: number, worldPos: Vector3)
		print(("[WorldFX] HarborVisualUpdate uid=%s kind=%s tier=%d pos=%s"):format(uid, kind, tier, tostring(worldPos)))
	end)

	local initial = Workspace:GetAttribute(ATTR_WEATHER)
	if type(initial) == "string" then
		handleWeather(initial, initial, 0)
	end

	WeatherService:GetWeatherState():andThen(function(payload: { weather: string, timeOfDay: string })
		handleWeather(payload.weather, payload.weather, 0)
	end)
end

return WorldFXController
