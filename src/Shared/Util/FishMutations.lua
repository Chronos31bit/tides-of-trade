--!strict
-- FishMutations.lua
-- Client-only. Applies Grow-a-Garden-style mesh mutations to a held fish:
-- hue cycles, material swaps, Highlights, PointLights — directly on the
-- BaseParts. Replaces the old particle-cloud system (FishParticles.lua).
--
-- Public API:
--   handle = FishMutations.attach(part, mods, opts)
--     part : BasePart                       — the anchor part (PrimaryPart of fish)
--     mods : {string}                       — modifier ids (resolved via ModifierMutations)
--     opts : { viewport: boolean?,          — true for ViewportFrame previews
--              intensity: number? }         — 0..1 multiplier on highlight transparency
--   handle:Destroy()                        — removes Highlight/PointLight, restores
--                                              Color/Material/Transparency snapshots,
--                                              and unregisters Heartbeat tickers.
--
-- A single module-level Heartbeat loop drives all active color cycles, pulses,
-- and flickers — no per-fish RunService connection. Tickers self-prune when
-- their target part is destroyed or unparented.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local GameConfig        = require(ReplicatedStorage.Shared.Config.GameConfig)
local MotionUtil        = require(script.Parent.MotionUtil)

local ModifierMutations = require(ReplicatedStorage.Shared.Config.ModifierMutations)

local FishMutations = {}

-- ====================================================================
-- Shared ticker loop — one Heartbeat connection drives every active fish.
-- ====================================================================

type Ticker = {
	id          : number,
	part        : BasePart,
	startedAt   : number,
	periodSec   : number,
	tick        : (now: number, phase: number, self: Ticker) -> (),
	-- Used by some tickers to remember last-applied state for flicker debounce.
	scratch     : {[string]: any},
}

local _tickers: {[number]: Ticker} = {}
local _nextTickerId = 0
local _heartbeatConn: RBXScriptConnection? = nil

local function _startHeartbeatIfNeeded()
	if _heartbeatConn then return end
	_heartbeatConn = RunService.Heartbeat:Connect(function()
		if MotionUtil.reducedMotionEnabled() then
			-- Decoration off — freeze tickers but keep the loop running so
			-- it resumes immediately when the user toggles reduced motion off.
			return
		end
		local now = os.clock()
		for id, t in pairs(_tickers) do
			local p = t.part
			if not p or not p.Parent then
				_tickers[id] = nil
			else
				local phase = ((now - t.startedAt) / math.max(t.periodSec, 1e-3)) % 1
				t.tick(now, phase, t)
			end
		end
	end)
end

local function _addTicker(t: Ticker): number
	_nextTickerId += 1
	t.id = _nextTickerId
	_tickers[_nextTickerId] = t
	_startHeartbeatIfNeeded()
	return _nextTickerId
end

local function _removeTicker(id: number)
	_tickers[id] = nil
end

-- ====================================================================
-- HSV → RGB (used by hueRotate color cycle).
-- ====================================================================

local function _hsvToColor3(h: number, s: number, v: number): Color3
	return Color3.fromHSV(h % 1, math.clamp(s, 0, 1), math.clamp(v, 0, 1))
end

local function _lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

-- ====================================================================
-- Multi-part walker — visual effects on a single passed BasePart only
-- color a fin or scale. Apply tint/material/transparency across every
-- BasePart in the parent Model so the whole fish reads as mutated.
-- ====================================================================

local function _meshParts(anchor: BasePart): {BasePart}
	local out: {BasePart} = { anchor }
	local parent = anchor.Parent
	if parent and parent:IsA("Model") then
		for _, d in ipairs(parent:GetDescendants()) do
			if d:IsA("BasePart") and d ~= anchor then
				table.insert(out, d :: BasePart)
			end
		end
	end
	return out
end

-- ====================================================================
-- Effect application order. Lower = applied first. Crucial so a tintLock
-- never overwrites a colorCycle's per-frame writes, and materialLock wins
-- when stacked.
-- ====================================================================

local ORDER: {[string]: number} = {
	materialLock      = 1,
	tintLock          = 2,
	transparency      = 3,
	colorCycle        = 4,
	pulseTransparency = 5,
	highlight         = 6,
	pointLight        = 7,
	shell             = 8,
	decal             = 9,
	attachedParticle  = 10,
	fire              = 11,
	smoke             = 12,
	sparkles          = 13,
	beam              = 14,
}

-- ====================================================================
-- Handle — caller owns disposal.
-- ====================================================================

export type MutationHandle = {
	Destroy: (self: MutationHandle) -> (),
}

type _HandleState = {
	tickerIds   : {number},
	createdInst : {Instance},                         -- Highlights, PointLights
	originals   : {[BasePart]: {Color: Color3, Material: Enum.Material, Transparency: number}},
	highlightBy : {[BasePart]: Highlight},            -- per-anchor-part merge target
	_destroyed  : boolean,
}

local function _snapshot(state: _HandleState, p: BasePart)
	if state.originals[p] then return end
	state.originals[p] = { Color = p.Color, Material = p.Material, Transparency = p.Transparency }
end

local function _ensureHighlight(state: _HandleState, anchor: BasePart, opts: {viewport: boolean?}): Highlight
	local existing = state.highlightBy[anchor]
	if existing then return existing end
	local h = Instance.new("Highlight")
	h.Adornee = anchor.Parent and anchor.Parent:IsA("Model") and anchor.Parent or anchor
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	if opts.viewport then
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	end
	h.Parent = anchor
	state.highlightBy[anchor] = h
	table.insert(state.createdInst, h)
	return h
end

-- ====================================================================
-- Effect appliers.
-- ====================================================================

local function _applyMaterialLock(state, anchor, parts, effect, _opts)
	for _, p in ipairs(parts) do
		_snapshot(state, p)
		p.Material = effect.material
	end
end

local function _applyTintLock(state, anchor, parts, effect, _opts)
	for _, p in ipairs(parts) do
		_snapshot(state, p)
		p.Color = effect.color
	end
end

local function _applyTransparency(state, anchor, parts, effect, _opts)
	for _, p in ipairs(parts) do
		_snapshot(state, p)
		p.Transparency = effect.value
	end
end

local function _applyColorCycle(state, anchor, parts, effect, _opts)
	for _, p in ipairs(parts) do _snapshot(state, p) end
	local mode = effect.mode
	if mode == "hueRotate" then
		local sat = effect.saturation or 0.85
		local val = effect.value or 1.0
		local id = _addTicker({
			id = 0, part = anchor, startedAt = os.clock(), periodSec = effect.periodSec,
			scratch = {},
			tick = function(_now, phase, _self)
				local c = _hsvToColor3(phase, sat, val)
				for _, p in ipairs(parts) do p.Color = c end
			end,
		})
		table.insert(state.tickerIds, id)
	elseif mode == "lerpLoop" then
		local palette: {Color3} = effect.palette or { Color3.new(1,1,1) }
		local n = #palette
		local id = _addTicker({
			id = 0, part = anchor, startedAt = os.clock(), periodSec = effect.periodSec,
			scratch = {},
			tick = function(_now, phase, _self)
				local pos = phase * n
				local i = math.floor(pos)
				local f = pos - i
				local a = palette[(i % n) + 1]
				local b = palette[((i + 1) % n) + 1]
				local c = _lerpColor(a, b, f)
				for _, p in ipairs(parts) do p.Color = c end
			end,
		})
		table.insert(state.tickerIds, id)
	elseif mode == "flicker" then
		local palette: {Color3} = effect.palette or { Color3.new(1,1,1) }
		local n = #palette
		local id = _addTicker({
			id = 0, part = anchor, startedAt = os.clock(), periodSec = effect.periodSec * n,
			scratch = { lastIdx = -1 },
			tick = function(_now, phase, self)
				local idx = math.floor(phase * n) + 1
				if idx ~= self.scratch.lastIdx then
					self.scratch.lastIdx = idx
					local c = palette[idx]
					for _, p in ipairs(parts) do p.Color = c end
				end
			end,
		})
		table.insert(state.tickerIds, id)
	end
end

local function _applyPulseTransparency(state, anchor, parts, effect, _opts)
	for _, p in ipairs(parts) do _snapshot(state, p) end
	local lo, hi = effect.min, effect.max
	local id = _addTicker({
		id = 0, part = anchor, startedAt = os.clock(), periodSec = effect.periodSec,
		scratch = {},
		tick = function(_now, phase, _self)
			-- Sine bounce 0..1..0 over the period.
			local s = (math.sin(phase * math.pi * 2 - math.pi / 2) + 1) * 0.5
			local v = lo + (hi - lo) * s
			for _, p in ipairs(parts) do p.Transparency = v end
		end,
	})
	table.insert(state.tickerIds, id)
end

local function _applyHighlight(state, anchor, _parts, effect, opts)
	local h = _ensureHighlight(state, anchor, opts)
	local intensityT = opts.intensity or 1.0
	if effect.fillColor then h.FillColor = effect.fillColor end
	if effect.outlineColor then h.OutlineColor = effect.outlineColor end
	if effect.fillT ~= nil then
		-- Higher intensity → lower transparency (more visible).
		h.FillTransparency = 1 - (1 - effect.fillT) * intensityT
	end
	if effect.outlineT ~= nil then
		h.OutlineTransparency = 1 - (1 - effect.outlineT) * intensityT
	end
	if effect.flickerHz and effect.flickerHz > 0 then
		local baseOutlineT = h.OutlineTransparency
		local period = 1 / effect.flickerHz
		local id = _addTicker({
			id = 0, part = anchor, startedAt = os.clock(), periodSec = period,
			scratch = { on = false },
			tick = function(_now, phase, self)
				local on = phase < 0.5
				if on ~= self.scratch.on then
					self.scratch.on = on
					h.OutlineTransparency = on and baseOutlineT or 1
				end
			end,
		})
		table.insert(state.tickerIds, id)
	end
end

local function _applyPointLight(state, anchor, _parts, effect, opts)
	if opts.viewport then return end  -- ViewportFrame ignores world lights.
	local pl = Instance.new("PointLight")
	pl.Color      = effect.color
	pl.Range      = effect.range
	pl.Brightness = effect.brightness
	pl.Shadows    = false
	pl.Parent     = anchor
	table.insert(state.createdInst, pl)
	if effect.flickerHz and effect.flickerHz > 0 then
		local baseBrightness = effect.brightness
		local period = 1 / effect.flickerHz
		local id = _addTicker({
			id = 0, part = anchor, startedAt = os.clock(), periodSec = period,
			scratch = { on = false },
			tick = function(_now, phase, self)
				local on = phase < 0.5
				if on ~= self.scratch.on then
					self.scratch.on = on
					pl.Brightness = on and baseBrightness or (baseBrightness * 0.2)
				end
			end,
		})
		table.insert(state.tickerIds, id)
	end
end

-- shell: wraps the anchor mesh with overridable Material/Color/Transparency.
-- shape = "mesh" (default) clones the part so the wrapper inherits silhouette
--                  (good for golden plating, crystal coating).
-- shape = "cube" builds a single Block part sized to the parent Model's
--                  bounding box + padding — reads as "encased in a cube of X"
--                  rather than a ghost fish (good for frozen ice block).
-- For "cube" shape, only ONE shell is created per attach() call regardless
-- of how many parts the fish has, and it covers the whole bounding volume.
local function _applyShell(state, anchor, parts, effect, _opts)
	local shape = effect.shape or "mesh"
	if shape == "cube" then
		local container: Instance = (anchor.Parent and anchor.Parent:IsA("Model")) and anchor.Parent or anchor
		local cf: CFrame, size: Vector3
		if container:IsA("Model") then
			cf, size = (container :: Model):GetBoundingBox()
		else
			cf, size = anchor.CFrame, anchor.Size
		end
		local pad = effect.padding or 0.5
		local block = Instance.new("Part")
		block.Name           = "MutationShell_Cube"
		block.Shape          = Enum.PartType.Block
		block.Size           = size + Vector3.new(pad, pad, pad)
		block.CFrame         = cf
		block.Anchored       = false
		block.CanCollide     = false
		block.CanTouch       = false
		block.CanQuery       = false
		block.Massless       = true
		block.CastShadow     = false
		block.Material       = effect.material or Enum.Material.Ice
		block.Color          = effect.color or Color3.fromRGB(200, 235, 255)
		block.Transparency   = effect.transparency or 0.35
		block.Reflectance    = effect.reflectance or 0.35
		block.Parent         = anchor
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchor
		weld.Part1 = block
		weld.Parent = block
		table.insert(state.createdInst, block)
		return
	end

	-- shape == "mesh": clone each part into a wrapper.
	for _, p in ipairs(parts) do
		local shell = p:Clone()
		for _, d in ipairs(shell:GetDescendants()) do
			if not (d:IsA("SpecialMesh") or d:IsA("MeshPart") or d:IsA("DataModelMesh")) then
				d:Destroy()
			end
		end
		shell.Name           = (p.Name or "Shell") .. "_Shell"
		shell.Anchored       = false
		shell.CanCollide     = false
		shell.CanTouch       = false
		shell.CanQuery       = false
		shell.Massless       = true
		shell.CastShadow     = false
		shell.Size           = p.Size * (effect.scale or 1.18)
		shell.Material       = effect.material or Enum.Material.Glass
		shell.Color          = effect.color or Color3.fromRGB(220, 240, 255)
		shell.Transparency   = effect.transparency or 0.5
		shell.Reflectance    = effect.reflectance or 0
		shell.CFrame         = p.CFrame
		shell.Parent         = p
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = p
		weld.Part1 = shell
		weld.Parent = shell
		table.insert(state.createdInst, shell)
	end
end

-- decal: attaches a Decal to the requested faces. Default = all 6 faces so
-- the texture wraps no matter which way the fish faces.
local function _applyDecal(state, anchor, parts, effect, _opts)
	local faces: {Enum.NormalId} = effect.faces or {
		Enum.NormalId.Front, Enum.NormalId.Back,
		Enum.NormalId.Left,  Enum.NormalId.Right,
		Enum.NormalId.Top,   Enum.NormalId.Bottom,
	}
	for _, p in ipairs(parts) do
		for _, face in ipairs(faces) do
			local d = Instance.new("Decal")
			d.Texture          = effect.texture
			d.Face             = face
			d.Color3           = effect.color or Color3.new(1, 1, 1)
			d.Transparency     = effect.transparency or 0
			d.ZIndex           = effect.zIndex or 0
			d.Parent           = p
			table.insert(state.createdInst, d)
		end
	end
end

-- attachedParticle: small, focused ParticleEmitter directly on the anchor
-- part (not a floating cloud). Use for sparkles, electric arcs, frost crystals.
-- Skipped in viewport mode (ViewportFrame ignores ParticleEmitters).
local function _applyAttachedParticle(state, anchor, _parts, effect, opts)
	if opts.viewport then return end
	local pe = Instance.new("ParticleEmitter")
	if effect.texture        then pe.Texture        = effect.texture end
	pe.Color           = effect.color           or ColorSequence.new(Color3.new(1, 1, 1))
	pe.LightEmission   = effect.lightEmission   or 1.0
	pe.LightInfluence  = effect.lightInfluence  or 0.0
	pe.Lifetime        = effect.lifetime        or NumberRange.new(0.4, 0.8)
	pe.Rate            = effect.rate            or 12
	pe.Size            = effect.size            or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency    = effect.transparency    or NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(0.85, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Speed           = effect.speed           or NumberRange.new(0.3, 1.2)
	pe.SpreadAngle     = effect.spreadAngle     or Vector2.new(180, 180)
	if effect.rotation     then pe.Rotation     = effect.rotation end
	if effect.rotSpeed     then pe.RotSpeed     = effect.rotSpeed end
	if effect.acceleration then pe.Acceleration = effect.acceleration end
	pe.EmissionDirection = effect.emissionDirection or Enum.NormalId.Top
	pe.Parent = anchor
	table.insert(state.createdInst, pe)
end

-- fire: Roblox built-in Fire instance — orange/red flame visual with the
-- engine's own texture/animation. Cheaper than a custom ParticleEmitter and
-- reads as "flames" instantly. Skipped in viewport (Fire doesn't render
-- inside ViewportFrame lighting).
local function _applyFire(state, anchor, _parts, effect, opts)
	if opts.viewport then return end
	local f = Instance.new("Fire")
	f.Color          = effect.color          or Color3.fromRGB(255, 130, 30)
	f.SecondaryColor = effect.secondaryColor or Color3.fromRGB(120, 30, 10)
	f.Size           = effect.size           or 5
	f.Heat           = effect.heat           or 8
	f.Parent         = anchor
	table.insert(state.createdInst, f)
end

-- smoke: Roblox built-in Smoke instance — billowing cloud.
local function _applySmoke(state, anchor, _parts, effect, opts)
	if opts.viewport then return end
	local s = Instance.new("Smoke")
	s.Color       = effect.color       or Color3.fromRGB(120, 120, 120)
	s.Size        = effect.size        or 3
	s.Opacity     = effect.opacity     or 0.6
	s.RiseVelocity= effect.riseVelocity or 2
	s.Parent      = anchor
	table.insert(state.createdInst, s)
end

-- sparkles: Roblox built-in Sparkles — dense flickering star points.
local function _applySparkles(state, anchor, _parts, effect, opts)
	if opts.viewport then return end
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = effect.color or Color3.fromRGB(255, 255, 200)
	sp.Parent       = anchor
	table.insert(state.createdInst, sp)
end

-- beam: arc between two attachments. Used for shocked/storm electricity,
-- rainbow trail, void tendrils. Creates 2 attachments offset along axis +
-- a Beam between them. width/segments/color/lightEmission tunable.
local function _applyBeam(state, anchor, _parts, effect, opts)
	if opts.viewport then return end
	local a0 = Instance.new("Attachment")
	a0.Name = "MutBeamA0"
	a0.Position = effect.offsetA or Vector3.new(-1, 0, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Name = "MutBeamA1"
	a1.Position = effect.offsetB or Vector3.new( 1, 0, 0)
	a1.Parent = anchor
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color         = effect.color or ColorSequence.new(Color3.new(1, 1, 1))
	b.Width0        = effect.width0 or 0.3
	b.Width1        = effect.width1 or 0.3
	b.LightEmission = effect.lightEmission or 1.0
	b.LightInfluence= 0
	b.FaceCamera    = true
	b.Segments      = effect.segments or 12
	b.CurveSize0    = effect.curveSize or 0.6
	b.CurveSize1    = effect.curveSize or -0.6
	if effect.texture then
		b.Texture        = effect.texture
		b.TextureLength  = effect.textureLength or 1
		b.TextureSpeed   = effect.textureSpeed or 2
		b.TextureMode    = Enum.TextureMode.Stretch
	end
	if effect.transparency then b.Transparency = effect.transparency end
	b.Parent = anchor
	table.insert(state.createdInst, a0)
	table.insert(state.createdInst, a1)
	table.insert(state.createdInst, b)
end

local APPLIERS = {
	materialLock      = _applyMaterialLock,
	tintLock          = _applyTintLock,
	transparency      = _applyTransparency,
	colorCycle        = _applyColorCycle,
	pulseTransparency = _applyPulseTransparency,
	highlight         = _applyHighlight,
	pointLight        = _applyPointLight,
	shell             = _applyShell,
	decal             = _applyDecal,
	attachedParticle  = _applyAttachedParticle,
	fire              = _applyFire,
	smoke             = _applySmoke,
	sparkles          = _applySparkles,
	beam              = _applyBeam,
}

-- ====================================================================
-- Public API.
-- ====================================================================

export type AttachOpts = { viewport: boolean?, intensity: number? }

function FishMutations.attach(part: BasePart, mods: {string}, opts: AttachOpts?): MutationHandle
	local opts2: AttachOpts = opts or {}
	local state: _HandleState = {
		tickerIds   = {},
		createdInst = {},
		originals   = {},
		highlightBy = {},
		_destroyed  = false,
	}

	-- Empty mods → return a no-op handle.
	if #mods == 0 then
		return {
			Destroy = function(_self) end,
		} :: MutationHandle
	end

	local parts = _meshParts(part)

	-- Flatten + sort all effects across all modifiers by ORDER so stacking
	-- behavior is deterministic (materialLock before tintLock before cycles).
	type Pending = { mod: string, idx: number, effect: any, ord: number }
	local pending: {Pending} = {}
	for _, modId in ipairs(mods) do
		local entries = (ModifierMutations :: any)[modId]
		if entries then
			for i, eff in ipairs(entries) do
				table.insert(pending, {
					mod    = modId,
					idx    = i,
					effect = eff,
					ord    = ORDER[eff.kind] or 99,
				})
			end
		end
	end
	table.sort(pending, function(a, b)
		if a.ord ~= b.ord then return a.ord < b.ord end
		return a.idx < b.idx
	end)

	-- Snapshot original state for every part that *might* be mutated, so
	-- :Destroy() can fully restore even when reduced motion later flipped on.
	for _, p in ipairs(parts) do _snapshot(state, p) end

	-- Under reduced motion, skip color cycles, pulses, and flickers — but
	-- still apply static tint/material/transparency/highlight/pointLight.
	local reduced = MotionUtil.reducedMotionEnabled()

	for _, pe in ipairs(pending) do
		local kind = pe.effect.kind
		if reduced and (kind == "colorCycle" or kind == "pulseTransparency"
				or kind == "fire" or kind == "smoke" or kind == "sparkles") then
			-- Skip animated effects under reduced motion.
		elseif reduced and kind == "attachedParticle" then
			local effCopy = table.clone(pe.effect)
			effCopy.rate = 0
			local fn = APPLIERS[kind]
			if fn then fn(state, part, parts, effCopy, opts2) end
		elseif reduced and (kind == "highlight" or kind == "pointLight") and pe.effect.flickerHz then
			local effCopy = table.clone(pe.effect)
			effCopy.flickerHz = nil
			local fn = APPLIERS[kind]
			if fn then fn(state, part, parts, effCopy, opts2) end
		else
			local fn = APPLIERS[kind]
			if fn then fn(state, part, parts, pe.effect, opts2) end
		end
	end

	local handle: MutationHandle = {} :: MutationHandle
	function handle:Destroy()
		if state._destroyed then return end
		state._destroyed = true
		for _, id in ipairs(state.tickerIds) do _removeTicker(id) end
		for _, inst in ipairs(state.createdInst) do
			if inst and inst.Parent then inst:Destroy() end
		end
		for p, snap in pairs(state.originals) do
			if p and p.Parent then
				p.Color        = snap.Color
				p.Material     = snap.Material
				p.Transparency = snap.Transparency
			end
		end
	end

	return handle
end

-- Suppress unused-warning for the still-required GameConfig import — kept
-- so future per-modifier visual flags in GameConfig (e.g. globalIntensity)
-- can be wired without an import shuffle.
local _ = GameConfig

return FishMutations
