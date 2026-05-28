--!strict
-- GameConfig.lua
-- Single source of truth for tunable economy + world numbers.
-- Anything you'd want a designer to twiddle without touching service code lives here.

local GameConfig = {}

-- ====================================================================
-- ECONOMY
-- ====================================================================
GameConfig.Economy = {
	-- 5% transaction fee on every market sale. Sinks coins out of the economy.
	-- Tune up if inflation creeps; tune down if listings dry up.
	MarketFeePct = 0.05,

	-- Hard cap on simultaneous active listings per player. Prevents one whale
	-- from spamming the global board and starving other listings of visibility.
	MaxActiveListingsPerPlayer = 10,

	-- Minimum and maximum coin price you can list a single item for.
	-- Min stops dust-listing griefs; max stops gold-laundering exploits.
	MinListingPrice = 1,
	MaxListingPrice = 1_000_000,

	-- Listings auto-expire after this many seconds (48h). Server sweeps expired
	-- listings on a timer in MarketService.
	ListingTTLSeconds = 48 * 60 * 60,

	-- Daily demand spike: one species pays this multiplier for 24h.
	-- Drives login engagement ("which fish today?").
	DemandSpikeMultiplier = 2.5,

	-- Smokehouse conversion: preserved goods sell for this multiple of raw fish.
	SmokehouseMultiplier = 3.0,
}

-- ====================================================================
-- BIOMES — used by FishCatalog, FishingService, and the world generator
-- ====================================================================
GameConfig.Biomes = {
	Shoreline  = "Shoreline",   -- safe starter zone, plentiful commons
	Pier       = "Pier",        -- harbor-adjacent, similar to shoreline
	Reef       = "Reef",        -- mid-game, more variety
	DeepWater  = "DeepWater",   -- requires boat/dock tier 2+
	Trench     = "Trench",      -- end-game, mythics only at high tide
}

-- ====================================================================
-- TIDES — drives the 20-minute high/low cycle
-- ====================================================================
GameConfig.Tides = {
	-- Total period: 20 real minutes per full low->high->low cycle.
	-- The world spends ~half the cycle in High and ~half in Low, with short
	-- transition windows in between (handled in TideService).
	CycleSeconds = 20 * 60,

	-- Fraction of cycle classified as High tide (the rest is Low).
	-- 0.45 leaves a 5% transition margin on each side.
	HighFraction = 0.45,
}

-- ====================================================================
-- WEATHER — probabilistic state machine, ticked by WeatherService
-- ====================================================================
GameConfig.Weather = {
	-- How often (seconds) the weather may roll a transition.
	TickSeconds = 90,

	-- Per-tick transition probabilities. Rows sum to 1.0.
	-- Layout: From -> To -> probability.
	-- Sticky weights (Clear->Clear, etc.) keep states from flickering.
	Transitions = {
		Clear  = { Clear = 0.70, Cloudy = 0.25, Fog    = 0.05 },
		Cloudy = { Cloudy = 0.55, Clear = 0.20, Rain   = 0.20, Fog = 0.05 },
		Rain   = { Rain   = 0.55, Cloudy = 0.30, Storm  = 0.15 },
		Storm  = { Storm  = 0.40, Rain   = 0.55, Cloudy = 0.05 },
		Fog    = { Fog    = 0.55, Clear  = 0.25, Cloudy = 0.20 },
	},

	-- Replicated on Workspace for client rain/SFX (atmosphere is server Lighting).
	WorkspaceAttribute = "TidesWeather",
	WorkspaceLockedAttribute = "TidesWeatherLocked",

	-- Server Lighting presets (WeatherVisuals). Atmosphere + Clouds tween on server.
	Visuals = {
		Clear = {
			Density = 0.28, Haze = 0.9,
			Color = Color3.fromRGB(232, 200, 168),
			Brightness = 2.4, ExposureCompensation = 0,
			CloudCover = 0.12, CloudDensity = 0.15,
			CcEnabled = true, CcTint = Color3.fromRGB(255, 248, 240), CcSaturation = 0.05, CcContrast = 0,
		},
		Cloudy = {
			Density = 0.48, Haze = 1.8,
			Color = Color3.fromRGB(185, 190, 200),
			Brightness = 2.0, ExposureCompensation = -0.05,
			CloudCover = 0.45, CloudDensity = 0.4,
			CcEnabled = true, CcTint = Color3.fromRGB(220, 225, 235), CcSaturation = -0.1, CcContrast = 0.05,
		},
		Rain = {
			Density = 0.62, Haze = 2.4,
			Color = Color3.fromRGB(130, 145, 165),
			Brightness = 1.6, ExposureCompensation = -0.25,
			CloudCover = 0.72, CloudDensity = 0.65,
			CcEnabled = true, CcTint = Color3.fromRGB(140, 160, 190), CcSaturation = -0.2, CcContrast = 0.1,
			FogStart = 40,
			FogEnd = 900,
			FogColor = Color3.fromRGB(120, 135, 155),
		},
		Storm = {
			Density = 0.78, Haze = 3.2,
			Color = Color3.fromRGB(85, 90, 105),
			Brightness = 1.0, ExposureCompensation = -0.55,
			CloudCover = 0.92, CloudDensity = 0.88,
			CcEnabled = true, CcTint = Color3.fromRGB(90, 100, 120), CcSaturation = -0.35, CcContrast = 0.15,
			FogStart = 25,
			FogEnd = 650,
			FogColor = Color3.fromRGB(75, 82, 98),
		},
		Fog = {
			Density = 0.68, Haze = 3.4,
			Color = Color3.fromRGB(195, 202, 212),
			Brightness = 1.5, ExposureCompensation = -0.35,
			CloudCover = 0.78, CloudDensity = 0.72,
			CcEnabled = true, CcTint = Color3.fromRGB(215, 222, 232), CcSaturation = -0.45, CcContrast = -0.08,
			FogStart = 12,
			FogEnd = 380,
			FogColor = Color3.fromRGB(188, 198, 210),
		},
	},

	-- Client rain (WorldFXController). Matches SuperCatHeroes "Great RAIN Particles in 5 Minutes":
	-- https://www.youtube.com/watch?v=mp9N77bqVX8 — sparkle texture, squash 3, size 0.2,
	-- FacingCameraWorldUp, rate 500, LockedToPart, follows HRP + offset (world-upright).
	Rain = {
		UseTutorialFollower = true,
		FollowOffsetStuds = Vector3.new(0, 25, 0),
		PartFootprintStuds = 50,
		Lifetime = 1,
		ReducedMotionRateMultiplier = 0.45,
		BuiltInTextureId = "rbxasset://textures/particles/sparkles_main.dds",
		PlaceholderTextureId = "rbxassetid://419625073",
		FallbackTextureId = "rbxasset://textures/particles/sparkles_main.dds",
		PreferBuiltInTexture = true,
		EmitterRate = 500,
		EmitterRateStorm = 650,
		EmitterSpeed = NumberRange.new(25, 25),
		EmitterSquash = 3,
		EmitterSize = 0.2,
		EmitterSpreadAngle = Vector2.new(0, 0),
		LightEmission = 0.5,
		LightInfluence = 0,
		LockedToPart = true,
		UseFacingCameraWorldUp = true,
		ParticleColor = Color3.fromRGB(200, 220, 245),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.5),
			NumberSequenceKeypoint.new(0.85, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		}),
		StartupEmitBurst = 0,
		WindSwaySpreadDegrees = 0,
		-- Legacy grid keys (unused when UseTutorialFollower).
		GlobalGridCount = 1,
		GlobalCellSizeStuds = 50,
		GlobalHeightStuds = 25,
		GlobalFollowIntervalSeconds = 0,
		RateBudgetRain = 500,
		RateBudgetStorm = 650,
		UseBoxEmissionShape = false,
		AlwaysUseProceduralEmitters = true,
		ProceduralSpreadAngle = Vector2.new(0, 0),
		ProceduralLifetime = 1,
		ProceduralSpeed = NumberRange.new(25, 25),
		ProceduralSize = NumberSequence.new(0.2),
	},

	-- Server-side tween duration for weather → Lighting/Atmosphere/CC changes.
	-- Initial boot apply uses 0 (snap). Subsequent changes use DurationSeconds.
	Transition = {
		DurationSeconds = 2.5,
		ReducedMotionDurationScale = 0.4,
	},

	-- Distance fog (Lighting.FogStart/End) is applied client-side; particles stay off for cozy harbor.
	DistanceFog = {
		ClearFogEnd = 100000,
	},

	-- Fog: atmosphere + distance fog (tutorial-style); optional particles off by default.
	Fog = {
		EnableParticleFog = false,
		Lifetime = 10,
		SpeedRange = NumberRange.new(0.15, 0.4),
		TexturePlaceholderId = "rbxasset://textures/particles/smoke_main.dds",
		GlobalGridCount = 1,
		GlobalCellSizeStuds = 120,
		SheetHeightOffsetStuds = 1,
		GlobalRecenterStuds = 40,
		GlobalFollowIntervalSeconds = 0.15,
		RateBudget = 12,
		UseBoxEmissionShape = false,
		AlwaysUseProceduralEmitters = true,
		StartupEmitBurst = 0,
		SpreadAngle = Vector2.new(180, 12),
		ReducedMotionRateMultiplier = 0.5,
		UseParticlesWhenTemplateMissing = false,
	},

	-- Storm lightning subsystem (WorldFXController._lightningLoop).
	-- Rate-limited to >= 8s between flashes to satisfy CLAUDE.md no-strobe rule
	-- (3 changes/sec ceiling). Disabled when ReducedMotionEnabled = true.
	Lightning = {
		MinIntervalSeconds = 8,
		MaxIntervalSeconds = 15,
		FlashAttackSeconds = 0.05,
		FlashHoldSeconds = 0.05,
		FlashDecaySeconds = 0.10,
		FlashBrightnessDelta = 0.75,
		FlashSaturationDelta = 0.15,
		ThunderDelayRangeSeconds = NumberRange.new(0.9, 1.8),
	},

	-- Per-weather loop volumes used by WorldFXController._applyWeatherSounds.
	-- Empty AssetIds slots are silent no-ops (SoundController guards on empty).
	Sound = {
		RainVolume = 0.5,
		StormRainVolume = 0.7,
		WindVolume = 0.35,
		ThunderVolume = 0.6,
		FogAmbientVolume = 0.25,
		CrossfadeSeconds = 1.5,
	},
}

-- Sorted list of every Markov weather state (admin GUI + validation).
local _adminWeatherStates: {string} = {}
for state in pairs(GameConfig.Weather.Transitions) do
	table.insert(_adminWeatherStates, state)
end
table.sort(_adminWeatherStates)

-- ====================================================================
-- TIME OF DAY — Lighting.ClockTime breakpoints
-- ====================================================================
GameConfig.TimeOfDay = {
	-- The Roblox day is 24 ClockTime units (game hours). We map:
	--   Morning: 5..9
	--   Day:     9..17
	--   Dusk:    17..20
	--   Night:   20..5  (wraps midnight)
	-- WeatherService advances ClockTime so a full day is real-life ~24 minutes.
	MinutesPerGameDay = 24,
}

-- ====================================================================
-- HARBOR
-- ====================================================================
GameConfig.Harbor = {
	-- Plot is 80x80 studs as required. Grid cells are 4 studs so buildings
	-- snap cleanly. 80/4 = 20x20 grid of placement cells per plot.
	PlotSizeStuds = 80,
	GridCellStuds = 4,
	-- How far above world Y=0 (water line) the plot corner sits.
	PlotElevationStuds = 7,
	-- Y offset from plot corner to the walkable plate surface (1-stud plate centered at Y=1).
	PlotPlateTopStuds = 1.5,

	-- Cap concurrent buildings per plot to keep the network and physics budget
	-- in check with StreamingEnabled.
	MaxBuildingsPerPlot = 60,

	-- Passive income tick interval (seconds). Buildings produce coins per tick.
	IncomeTickSeconds = 60,

	-- ----------------------------------------------------------------
	-- VISUAL TUNING — every magic number for the visible harbor
	-- transformation system. Drives upgrade tween timing, particle
	-- burst, debris spawn density, and reduced-motion scaling.
	-- Designer-friendly: tweak these without hunting through HarborVisualController.
	-- ----------------------------------------------------------------
	VisualTuning = {
		UpgradeTransitionDuration = 1.5,
		UpgradeFadeOutDuration    = 0.5,
		UpgradeFadeInDuration     = 1.0,
		UpgradeOvershoot          = 1.05,
		UpgradeSettleDuration     = 0.3,
		ParticleBurstCount        = 30,
		ParticleBurstDuration     = 0.3,
		ParticleSpawnDelay        = 0.4,
		AudioSpawnDelay           = 0.4,
		HapticSpawnDelay          = 0.4,
		DebrisFadeOutDuration     = 0.5,
		DebrisPerBuildingMin      = 3,
		DebrisPerBuildingMax      = 5,
		DebrisRadiusStuds         = 6,
		DebrisMaxPerPlot          = 30,
		ReducedMotionDurationScale = 0.5,
		-- Per-tier Model:ScaleTo on placed visuals (tier 1 = rundown scale).
		TierModelScale = { 1.0, 1.35, 1.7 },
	},
}

-- ====================================================================
-- BUILDINGS — all coin costs live here so designers can tune the build
-- economy in one place without touching BuildingCatalog's structural
-- data (footprints, behavior flags, description text).
-- tierCosts[1] = placement cost; [2]/[3] = upgrade costs into that tier.
-- ====================================================================
-- Per-rarity base aquarium income per fish per harbor income tick (see Harbor.IncomeTickSeconds).
GameConfig.Aquarium = {
	-- Aquarium modal slot grid (3 wide — fills column without a 4th empty gutter).
	SlotGridColumns   = 3,
	SlotCellWidthPx   = 152,
	SlotCellHeightPx  = 180,
	-- Coins / xp per fish per harbor income tick (see Harbor.IncomeTickSeconds).
	-- sellPriceMul on modifiers compounds on coins (see AquariumIncome.lua).
	RarityIncome = {
		Common    = { coins = 1,  xp = 0 },
		Uncommon  = { coins = 3,  xp = 1 },
		Rare      = { coins = 10, xp = 2 },
		Epic      = { coins = 16, xp = 3 },
		Legendary = { coins = 22, xp = 4 },
		Mythic    = { coins = 30, xp = 6 },
		Divine    = { coins = 45, xp = 8 },
	},
}

GameConfig.Buildings = {
	Dock        = { tierCosts = { 0,     40,     9000  } },
	MarketStall = { tierCosts = { 800,   3500,   12000 } },
	Smokehouse  = { tierCosts = { 1500,  6000,   18000 }, PreserveTimeSec = 300 },
	Lighthouse  = { tierCosts = { 2000,  7500,   22000 }, RarityBumpChance = { 0.15, 0.28, 0.45 } },
	BaitShop    = { tierCosts = { 600,   2400,   8000  } },
	Aquarium    = { tierCosts = { 1200,  5000,   16000 } },
	Guildhall   = { tierCosts = { 5000,  15000,  40000 } },
}

-- ====================================================================
-- FISHING
-- ====================================================================
GameConfig.Fishing = {
	-- Cast meter oscillation period (seconds). Lower = harder. Read by the server
	-- to supply the timing window; client uses CastMeter.OscillationPeriod below.
	CastMeterPeriod = 1.4,

	-- Client-side cast meter layout and feel. All values the designer would tune.
	CastMeter = {
		OscillationPeriod  = 1.4,   -- seconds per full marker sweep
		BarHeightPx        = 160,   -- logical px height of the vertical bar
		BarWidthPx         = 20,    -- logical px width of the vertical bar
		CastButtonSizePx   = 80,    -- diameter of the cast-release circle
		-- Distance from screen bottom to the BOTTOM EDGE of the cast button.
		-- Nav bar is 88px tall + 20px safe-area gap = 108px. 10px clearance → 118.
		CastButtonBottomPx = 118,
		BarButtonGapPx     = 8,     -- gap between top of button and bottom of bar
		-- Reel bar Y anchor: distance from screen bottom to bar center (thumb zone).
		ReelBarBottomPx    = 200,
		-- Min seconds between loss-state indicator pulses (strobing guard).
		LossFlashMinIntervalSec = 0.4,
	},

	-- Minimum cooldown between casts (anti-spam, anti-exploit).
	CastCooldownSeconds = 0.5,

	-- How long the meter stays up before the cast auto-fails.
	CastTimeoutSeconds = 8.0,

	-- Reel mini-game window. After the bite (ClaimCast hit), the player has
	-- this many seconds to either complete the hold or escape, otherwise the
	-- pending cast is reaped and CastResolved fires with reason="reel_timeout".
	ReelTimeoutSeconds = 12.0,

	-- Consolation XP granted when a fish escapes during the reel phase.
	EscapeConsolationXP = 5,

	-- Lure Token drop chance per successful catch (premium soft currency).
	LureTokenDropChance = 0.02, -- 2% per catch

	-- Rarity weights when rolling which fish from the eligible pool to award.
	-- Higher = more common. These are *post-filter* weights — only fish that
	-- match the current biome/tide/weather/time get rolled at all.
	RarityWeights = {
		Common    = 50,
		Uncommon  = 25,
		Rare      = 13,
		Epic      =  7,
		Legendary =  3,
		Mythic    =  1.5,
		Divine    =  0.5,
	},

	-- Rarity → tension tier for the reel mini-game. Primary difficulty axis.
	-- Weight still influences zone oscillation speed as a secondary modifier.
	RarityTierMap = {
		Common    = "light",
		Uncommon  = "light",
		Rare      = "medium",
		Epic      = "medium",
		Legendary = "heavy",
		Mythic    = "heavy",
		Divine    = "legendary",
	},

	-- 0..1 difficulty base per rarity. Weight adds a small nudge (+0.00–0.10).
	RarityDifficultyBase = {
		Common    = 0.10,
		Uncommon  = 0.20,
		Rare      = 0.38,
		Epic      = 0.52,
		Legendary = 0.70,
		Mythic    = 0.85,
		Divine    = 1.00,
	},

	-- Zone and label tint colors for the reel mini-game, keyed by rarity.
	-- Matches the RANK palette in RodCatalog.lua so the visual language is consistent.
	RarityColors = {
		Common    = Color3.fromRGB(176, 182, 190),
		Uncommon  = Color3.fromRGB(120, 205, 135),
		Rare      = Color3.fromRGB( 95, 165, 240),
		Epic      = Color3.fromRGB(185, 120, 235),
		Legendary = Color3.fromRGB(245, 180,  75),
		Mythic    = Color3.fromRGB(240,  95, 140),
		Divine    = Color3.fromRGB(255, 225, 150),
	},

	-- ----------------------------------------------------------------
	-- FEEL TUNING — every magic number for the cast/reel/reveal UI.
	-- Designer-friendly: tweak these without hunting through controllers.
	--
	-- Reel-related values (ReelHoldDuration / ReelZoneSpeed*) are
	-- referenced by the future server-validated reel mini-game (Path A
	-- of the polish plan). They're harmless to keep here today; the
	-- current single-phase contract just ignores them.
	-- ----------------------------------------------------------------
	FeelTuning = {
		CastShakeMagnitude        = 0.3,
		CastShakeDuration         = 0.25,
		RippleMaxRadius           = 4,
		RippleDuration            = 0.8,
		RippleCount               = 2,
		HapticIntensity           = 0.4,
		HapticDuration            = 0.08,
		MeterTransitionDuration   = 0.3,
		ReelHoldDuration          = 2.0,
		ReelZoneSpeedBase         = 1.2,
		ReelZoneSpeedPerKg        = 0.04,
		PerfectZoneFraction       = 0.25,
		PerfectBonusMultiplier    = 2.0,
		PerfectThreshold          = 0.8,
		-- Perfect-cast: marker lands in the inner gold strip → fish is heavier.
		BaseGreenZoneScale        = 1.35,   -- global multiplier on fish.greenZoneSize; widens all zones without catalog edits
		PerfectCastWeightBonus    = 0.15,   -- +15% weight, capped at 1.5× catalog max
		-- Perfect-reel: award immediate coins = fraction of the fish's base market price.
		PerfectReelCoinFraction   = 0.20,   -- 20% of fish.basePrice awarded on completion
		RevealSlideInDuration     = 0.5,
		RevealAutoDismissAfter    = 3.0,
		MythicBorderCycleDuration = 1.5,
	},

	-- ----------------------------------------------------------------
	-- ROD TIER UNLOCKS — declarative tier slots. `speciesUnlocked` is
	-- left empty here and populated at server boot from FishCatalog by
	-- RodTierUtil.populate (RodService:KnitInit). Keyed by tier number.
	--
	-- Intentionally species-ONLY: the rod display name / cost /
	-- description already live in ShopService.RODS (the rod shop's
	-- catalog, client-exposed via ShopService:GetRodCatalog). Duplicating
	-- them here would let the two drift apart, so the tooltip pulls names
	-- from the shop catalog and counts/species from FishCatalog via
	-- RodTierUtil. Biomes are NOT listed because rod tier does not gate
	-- biomes in this game — only per-fish rodMinTier gates catches.
	--
	-- Slot count must cover every rodMinTier the catalog uses (currently
	-- 1..5). RodTierUtil only populates slots that exist here.
	RodTierUnlocks = {
		[1] = { speciesUnlocked = {} },
		[2] = { speciesUnlocked = {} },
		[3] = { speciesUnlocked = {} },
		[4] = { speciesUnlocked = {} },
		[5] = { speciesUnlocked = {} },
	},
}

-- ====================================================================
-- UI — client-only presentation tunables (no gameplay effect)
--
-- Design tokens here are the single source of truth for spacing, radii,
-- typography, modal chrome, touch/font floors, and ScreenGui z-order.
-- UIUtil.lua re-exports these via UIUtil.Spacing / UIUtil.Radii /
-- UIUtil.Typography for ergonomic access from feature UIs. Tune values
-- here without touching UI module code.
-- ====================================================================
GameConfig.UI = {
	-- Mobile-first accessibility floors. Every interactive button must
	-- size >= MinTouchPx; every TextLabel must size >= MinFontPx after
	-- UIScale. UIUtil.makePrimaryButton etc. enforce these in Studio.
	MinTouchPx = 44,
	MinFontPx  = 12,
	MinPhoneWidth = 380,
	-- Portrait phones (viewport width <= MinPhoneWidth): UIScale never drops below this
	-- so 44px design touch targets stay >= 44px on screen (e.g. 380×667).
	MinAutoScalePortrait = 1,

	-- 8px-multiple grid. Use names, not raw numbers, in feature UI.
	Spacing = {
		xs  = 4,
		sm  = 8,
		md  = 12,
		lg  = 16,
		xl  = 24,
		xxl = 32,
	},

	-- Corner radii. `pill` is effectively round (used as a UDim offset
	-- value, capped by the smaller edge of the parent).
	Radii = {
		sm   = 6,
		md   = 10,
		lg   = 12,
		xl   = 16,
		pill = 999,
	},

	-- Type ramp. Floor on `caption` is 12 — the accessibility minimum.
	-- Body is the default label size used by UIUtil.makeLabel(..., "body").
	Typography = {
		display  = { font = Enum.Font.GothamBlack,    size = 28 },
		title    = { font = Enum.Font.GothamBold,     size = 20 },
		subtitle = { font = Enum.Font.GothamSemibold, size = 16 },
		body     = { font = Enum.Font.GothamMedium,   size = 15 },
		caption  = { font = Enum.Font.Gotham,         size = 12 },
	},

	-- Modal chrome shared by every full-screen modal (Inventory, Market,
	-- Harbor, Rod, Bait, Aquarium, Shop, Social, demolish-confirm).
	-- UIUtil.makeModalShell reads these on construction.
	Modal = {
		MaxWidthPx     = 440,   -- UISizeConstraint cap so panels stay phone-shaped on tablet/desktop
		BackdropAlpha  = 0.55,  -- final BackgroundTransparency on the fullscreen backdrop
		FadeDuration   = 0.18,
		SlideOffsetPx  = 16,    -- panel slides up by this much on open (skipped under ReducedMotion)
		HeaderHeightPx = 56,    -- height of title bar with close button
		CloseButtonPx  = 44,    -- diameter of the X button (touch floor)
		BodyPaddingPx  = 16,    -- inner padding from panel edge to body content
	},

	-- Catch reveal card — top edge aligns with HUD Wallet top (Wallet Position Y).
	CatchReveal = {
		RestTopOffsetPx        = 16,   -- fallback when HUD Wallet not mounted yet
		-- Mirror of legacy bottom offscreen offset (was Position Y scale 1, offset 240).
		OffscreenTopOffsetPx     = 240,
	},

	-- ScreenGui DisplayOrder map. Higher = drawn on top. Layering is the
	-- single source of truth for "what sits above what". Each ScreenGui
	-- in src/Client/UI/* sets `gui.DisplayOrder = DisplayOrder.<role>`
	-- on construction so the order is grep-able + tunable here.
	DisplayOrder = {
		World        = 0,   -- world-anchored BillboardGuis (waypoint, prompts)
		HUD          = 10,  -- bottom action bar, currency wallet, rod chip
		QuestTracker = 12,  -- right-edge tracker tab + popups
		Dialogue     = 20,  -- Mira NPC chat box
		CastMeter    = 30,  -- fishing overlay (above HUD, below modals)
		Notification = 31,  -- bottom-center toast stack (above cast thumb)
		Modal        = 40,  -- Inventory, Market, Harbor, Rod, Bait, Aquarium, Shop, Social
		CatchReveal  = 50,  -- celebration overlay above all modals
		Tutorial     = 60,  -- highlight overlay, sits above everything
		Admin        = 70,  -- admin weather / dev tools (above tutorial)
	},

	-- HUD rod-tier chip + its tap/long-press tooltip.
	RodTierChip = {
		-- Tooltip auto-dismisses after this many seconds of no interaction.
		TooltipInactivitySeconds = 12,
		-- Fade in/out duration. Under ReducedMotion the slide is skipped but
		-- the fade still plays (halved) — a fade is the reduced-motion-safe
		-- form of "appear".
		TooltipFadeDuration      = 0.18,
		-- Slide-in vertical offset (px). Skipped entirely under ReducedMotion.
		TooltipSlideOffsetPx     = 14,
		-- Tier-change glow pulse duration (decorative; snapped under RM).
		GlowPulseDuration        = 0.45,
		-- Max example species names shown in the "next tier" preview.
		NextTierExampleLimit     = 5,
		-- Hold this long (seconds) on touch to count as a long-press open.
		LongPressSeconds         = 0.35,
		-- Max-tier accent colour cycle period (reuses the mythic-frame feel).
		MaxTierCycleDuration     = 1.5,
		-- Single source of truth for the tooltip's "how to upgrade" line.
		-- The Rod Shop exists (ShopService:BuyRodTier), so this points at it
		-- rather than a placeholder. Edit this one string if the path moves.
		UpgradeHintText          = "Upgrade your rod at the Rod Shop on the dock.",
	},

	-- Default mute for SoundController until settings UI persists preference.
	SoundMutedByDefault = false,

	-- Ephemeral bottom-center toasts (market sale, demand spike, quests).
	Notification = {
		MaxQueue = 3,
		HoldSec = 3,
		SlideSec = 0.25,
		FadeSec = 0.30,
		-- Above HUD action bar: 20px inset + 88px bar + 12px gap (see HUD.lua).
		BottomOffsetPx = 120,
	},
}

-- ====================================================================
-- TUTORIAL — first-session onboarding tunables
-- ====================================================================
-- Every magic number for the 0–25 minute flow lives here. Dialogue lines
-- themselves are in src/Shared/Config/TutorialConfig.lua (kept separate
-- so writers can edit voice without touching numeric tuning).
GameConfig.Tutorial = {
	-- Multiplier applied to the *validation* green zone width for the first
	-- N successful casts. The visual width stays normal — players see what
	-- looks like a near-miss become a catch. Server-only knob.
	BeginnerAssistMultiplier        = 1.8,
	BeginnerAssistCount             = 3,

	-- Beat 2: cast-stuck nudges. First nudge after 90s of no cast attempt,
	-- repeats every 60s. Analytics-only stuck event at 4 minutes.
	Beat2StuckTimeoutSeconds        = 90,
	Beat2StuckRepeatSeconds         = 60,
	Beat2AnalyticsStuckSeconds      = 240,

	-- Beat 3: if the player catches but doesn't head to the stall, drop a
	-- HUD waypoint pointing at the market stall after this many seconds.
	Beat3WaypointDelaySeconds       = 60,
	Beat3StallProximityStuds        = 8,

	-- Beat 5: re-encouragement cadence while the player waits to afford
	-- the dock repair. Re-checks on every coin gain via PlayerData hooks.
	Beat5EncouragementRepeatSeconds = 30,
	RepairCostCoins                 = 40,

	-- Beat 6: the seeded daily quest's reward.
	FirstQuestRewardCoins           = 100,
	FirstQuestTarget                = 5,        -- catch 5 fish

	-- Mira spawn anchor (along dock-edge offset from dock-building corner).
	MiraSpawnOffsetStuds            = 6,

	-- If the player roams more than this many studs from their plot
	-- origin, Mira despawns and respawns near them with a recall line.
	WanderRecallDistanceStuds       = 80,
	WanderRecallCheckSeconds        = 2,

	-- DialogueUI feel.
	TypewriterCharsPerSecond        = 40,
	DialogueSlideInDuration         = 0.4,
	DialogueReducedMotionFadeIn     = 0.2,
	DialogueZIndex                  = 5,

	-- How long a dialogue line stays on screen before auto-hiding (no
	-- gameplay impact — state is preserved, player can re-open via the
	-- "Talk" ProximityPrompt on Mira). Keeps the dialogue panel out of
	-- the way during fishing / interacting with HUD.
	DialogueAutoDismissSeconds         = 8,
	DialogueAutoDismissTransientSeconds = 4,
}

-- ====================================================================
-- QUESTS — daily refresh at midnight UTC
-- ====================================================================
-- All tunable knobs for the daily-quest system. Quest *shapes* live in
-- src/Shared/Config/QuestTemplates.lua; this block sets the dials around
-- them: how many slots per day, which categories rotate when, what each
-- difficulty band pays out, and how long completed-but-unclaimed quests
-- linger after midnight.
GameConfig.Quests = {
	DailyCount = 3,
	-- After midnight UTC, completed-but-unclaimed quests move to
	-- profile.yesterdayQuests and stay claimable for this many hours.
	-- Incomplete quests are discarded outright (cozy: no streak stress).
	RolloverGraceHours = 24,

	-- Weekday rotation. UTC weekdays use Mon=1..Sun=7. Each day picks
	-- exactly 3 categories so the daily roll always spans 3 distinct
	-- categories — no day of three fishing quests.
	CategoryRotation = {
		[1] = { "fishing", "market", "social" },        -- Monday
		[2] = { "fishing", "market", "social" },        -- Tuesday
		[3] = { "fishing", "building", "exploration" }, -- Wednesday
		[4] = { "fishing", "building", "exploration" }, -- Thursday
		[5] = { "fishing", "market", "social" },        -- Friday
		[6] = { "fishing", "building", "exploration" }, -- Saturday
		[7] = { "fishing", "market", "exploration" },   -- Sunday
	},

	-- Difficulty mix per day. Today's roll always picks 1 easy + 1 medium
	-- + 1 hard quest, mapped onto the 3 rotation categories in that order
	-- (easy → first rotation category, etc.). Adjust if the daily feels
	-- too breezy or grindy.
	DifficultyDistribution = { "easy", "medium", "hard" },

	-- Reward bands per difficulty. Templates' rewardFormula picks within
	-- these via a per-template "param scale" (e.g. larger N → closer to
	-- the band max). Easy ≈ 5 min play, medium ≈ 15 min, hard ≈ 45 min.
	DifficultyRewardScale = {
		easy     = { coinsMin = 60,  coinsMax = 120, xpMin = 25,  xpMax = 50  },
		medium   = { coinsMin = 100, coinsMax = 200, xpMin = 50,  xpMax = 100 },
		hard     = { coinsMin = 250, coinsMax = 500, xpMin = 150, xpMax = 300 },
		-- Tutorial seed is a special case — rewardFormula reads
		-- GameConfig.Tutorial.FirstQuestRewardCoins directly, ignoring
		-- this band.
		tutorial = { coinsMin = 100, coinsMax = 100, xpMin = 40,  xpMax = 40  },
	},

	-- Login-streak rewards. Day 7 is the headline (guaranteed Rare lure).
	-- Day 14/21/28 are cosmetic placeholders — the cosmetic catalog
	-- doesn't exist yet, so QuestService grants them as Good items with
	-- the placeholder ids until cosmetics ship. After day 28 the streak
	-- continues earning the day-28+ entry every day until the streak
	-- breaks; we never reset the streak just because they "finished".
	LoginStreakRewards = {
		[1]  = { coins = 50  },
		[2]  = { coins = 75  },
		[3]  = { coins = 100 },
		[4]  = { coins = 150 },
		[5]  = { coins = 200 },
		[6]  = { coins = 300 },
		-- Day 7: keep existing `rare_lure` goodId (stable IDs are forever).
		[7]  = { items = { { id = "rare_lure", count = 1 } } },
		[14] = { items = { { id = "cosmetic_streak_14", count = 1 } } },  -- TODO: cosmetic catalog
		[21] = { items = { { id = "cosmetic_streak_21", count = 1 } } },  -- TODO
		[28] = { items = { { id = "cosmetic_streak_28", count = 1 } } },  -- TODO
	},
	-- After day 28 reward this every day until streak breaks.
	LoginStreakReward28Plus = { coins = 200 },

	-- Login-streak days that fire StreakMilestone toast (in addition to rewards).
	StreakMilestoneToastDays = { 7, 14, 30, 50, 100 },

	-- Coalescing window for the QuestsChanged network push during
	-- incremental progress. NOT a DataStore batch — the profile is mutated
	-- in memory immediately and ProfileService owns the autosave, so there
	-- is no thrash to guard against. Quest *completion* bypasses this and
	-- pushes instantly so the card flip lands with the popup. Keep this
	-- small; 0.3–0.5s coalesces rapid catches without feeling laggy.
	SnapshotPushDebounceSeconds = 0.4,

	-- How long the completion popup stays visible before auto-collapsing
	-- to a tab badge. The reward stays claimable from the tracker either way.
	CompletionPopupDuration = 8,
}

-- ====================================================================
-- CREW / GUILD
-- ====================================================================
GameConfig.Crew = {
	MaxMembers = 8,
	BaseCrewSlotsCost = 0, -- first crew is free; extra slots via game pass
}

-- ====================================================================
-- SOCIAL — emotes, harbor board (future)
-- ====================================================================
GameConfig.Social = {
	Emotes = {
		FadeInSeconds  = 0.15,
		FadeOutSeconds = 0.15,
		MaxConcurrent  = 1, -- per character; stop oldest when exceeded
	},
}

-- ====================================================================
-- ANTI-EXPLOIT
-- ====================================================================
GameConfig.AntiExploit = {
	-- Per-player rate limits. Server drops requests above these thresholds.
	-- Tuning rule (cozy pillar): set generously so legit play never trips.
	-- Limits are silent-drop only — never surface "you're going too fast"
	-- to the player. Server logs over-limit events for analytics.
	MaxCastsPerMinute       = 30,
	MaxListingsPerMinute    = 5,
	MaxBuildOpsPerMinute    = 60,
	MaxBuysPerMinute        = 20,  -- comfortable bulk-buy ceiling
	MaxQuickSellsPerMinute  = 60,  -- one per inventory slot, fast
	MaxCancelsPerMinute     = 20,  -- mirrors buys
	MaxQuestClaimsPerMinute = 20,  -- 3 dailies + grace; 20 is well above any honest peak
	MaxCrewOpsPerMinute     = 10,  -- create/join/leave; rare in honest play
	MaxCrewChatsPerMinute   = 20,  -- ~1 every 3s, generous for chatty crews
	MaxEmotesPerMinute      = 30,  -- one every 2s; dance parties still work
	MaxVisitsPerMinute      = 6,   -- TeleportService is heavy; visiting is intentional
	MaxAquariumOpsPerMinute = 60,
	MaxSmokehouseOpsPerMinute = 30,
	MaxShopOpsPerMinute     = 20,
	MaxRodEquipsPerMinute   = 20,
	MaxBaitEquipsPerMinute  = 30,
	MaxTutorialOpsPerMinute = 30,
	MaxSnapshotPullsPerMinute = 30, -- coarse limiter on read-only getters
	MaxReelClaimsPerMinute  = 60,   -- one per cast; upstream gated by StartCast

	-- If a client claims a catch outside this window after server says "fish
	-- on the line", reject. Tight window = exploiters can't replay old hooks.
	CatchClaimWindowSeconds = 6,

	-- Minimum elapsed seconds between bite and ReleaseReel claim.
	-- Below this, the reel mini-game couldn't have been played honestly.
	MinReelSeconds = 0.5,
}

-- ====================================================================
-- RODS — level thresholds to unlock each named rod tier.
-- Display data (catchWeightBonus, color) lives in RodCatalog.lua.
-- Thresholds live here so designers can tune progression without
-- touching the catalog. Keys must match RodCatalog rod ids exactly.
-- Level curve: cumulative XP to reach level L = 50 * L^2 (PlayerDataService).
-- ====================================================================
GameConfig.Rods = {
	-- Keyed by rod id; ascends with RodCatalog tier (apex = abyssal).
	UnlockLevel = {
		driftwood = 1,   -- t1  starter rod, always available
		bamboo    = 2,   -- t2  ~10-20 fish caught
		ironwood  = 4,   -- t3  ~40-60 fish caught
		coral     = 7,   -- t4  solid mid-game milestone
		tempest   = 12,  -- t5  dedicated players
		leviathan = 17,  -- t6  late-game push
		aurora    = 24,  -- t7  prestige territory
		celestial = 33,  -- t8  months of play
		eclipse   = 43,  -- t9  veteran flex
		abyssal   = 56,  -- t10 apex — top of the rack
	},
}

-- ====================================================================
-- FISH MODIFIERS — rare mutations that spawn on caught fish.
-- Each modifier rolls independently per catch (dropChance = per-catch
-- probability). Multiple modifiers can stack on one fish.
-- Effect fields (all optional):
--   weightMul    : multiply resolved weight by this value
--   xpMul        : multiply XP award by this value
--   coinInstant  : grant fish.basePrice × this as instant coins on catch
--   lureBonus    : immediately grant this many extra lure tokens
-- Modifiers are stored on FishItem.modifiers for display in inventory
-- and future market-price integration. Stable ids — never rename.
-- ====================================================================
GameConfig.FishModifiers = {
	-- ── NEW random modifiers — GAG-style mesh mutations (see ModifierMutations.lua) ──
	{ id = "rainbow",      displayName = "Rainbow",      dropChance = 0.005, coinInstant = 2.0, weightMul = 2.0, xpMul = 2.0, sellPriceMul = 2.0 },
	{ id = "golden",       displayName = "Golden",       dropChance = 0.012, coinInstant = 1.0,                sellPriceMul = 1.60 },
	{ id = "silver",       displayName = "Silver",       dropChance = 0.025,                                   sellPriceMul = 1.30 },
	{ id = "frozen",       displayName = "Frozen",       dropChance = 0.045, weightMul = 1.15,                 sellPriceMul = 1.20 },
	{ id = "inferno",      displayName = "Inferno",      dropChance = 0.030,                xpMul = 2.0                          },
	{ id = "shocked",      displayName = "Shocked",      dropChance = 0.040,                xpMul = 1.5,       lureBonus = 1     },
	{ id = "radioactive",  displayName = "Radioactive",  dropChance = 0.018,                xpMul = 2.5,       sellPriceMul = 1.25 },
	{ id = "crystal",      displayName = "Crystal",      dropChance = 0.020,                                   sellPriceMul = 1.40 },
	{ id = "colossal",     displayName = "Colossal",     dropChance = 0.040, weightMul = 1.5                                     },
	{ id = "tiny",         displayName = "Tiny",         dropChance = 0.030, coinInstant = 0.5, weightMul = 0.4                  },
	{ id = "bloodlust",    displayName = "Bloodlust",    dropChance = 0.025,                xpMul = 3.0,       sellPriceMul = 0.60 },
	{ id = "voidtouched",  displayName = "Voidtouched",  dropChance = 0.008,                xpMul = 4.0,       sellPriceMul = 1.70 },
	{ id = "ghostly",      displayName = "Ghostly",      dropChance = 0.030,                                   lureBonus = 2     },
	{ id = "disco",        displayName = "Disco",        dropChance = 0.012, coinInstant = 1.5,                sellPriceMul = 1.30 },
	{ id = "ancientcore",  displayName = "Ancient Core", dropChance = 0.018,                xpMul = 3.0,       sellPriceMul = 1.50 },
	-- ── World-state modifiers — dropChance=0, assigned by world state ───
	{ id = "tide_kissed",  displayName = "Tide-Kissed",  dropChance = 0,                    sellPriceMul = 1.25 },
	{ id = "storm_forged", displayName = "Storm-Forged", dropChance = 0,                    sellPriceMul = 1.50 },
	{ id = "moon_touched", displayName = "Moon-Touched", dropChance = 0,     xpMul = 1.25,  sellPriceMul = 1.15 },
	{ id = "dawn_blessed", displayName = "Dawn-Blessed", dropChance = 0,     xpMul = 1.20,  sellPriceMul = 1.10 },
	{ id = "fog_shrouded", displayName = "Fog-Shrouded", dropChance = 0,     lureBonus = 1, sellPriceMul = 1.20 },
	-- ── DEPRECATED — never roll (dropChance=0). Kept for legacy inventory items.
	-- ── ModifierMutations.lua still defines visuals for each so old fish render correctly.
	{ id = "shiny",        displayName = "Shiny",        dropChance = 0, deprecated = true, coinInstant = 1.0, sellPriceMul = 1.25 },
	{ id = "giant",        displayName = "Giant",        dropChance = 0, deprecated = true, weightMul = 1.4 },
	{ id = "glowing",      displayName = "Glowing",      dropChance = 0, deprecated = true, xpMul = 1.5 },
	{ id = "lucky",        displayName = "Lucky",        dropChance = 0, deprecated = true, lureBonus = 1 },
	{ id = "ancient",      displayName = "Ancient",      dropChance = 0, deprecated = true, xpMul = 3.0, sellPriceMul = 1.50 },
	{ id = "prismatic",    displayName = "Prismatic",    dropChance = 0, deprecated = true, coinInstant = 2.0, weightMul = 2.0, xpMul = 2.0, sellPriceMul = 2.0 },
	{ id = "elder",        displayName = "Elder",        dropChance = 0, deprecated = true, xpMul = 5.0, sellPriceMul = 1.80 },
	{ id = "cursed",       displayName = "Cursed",       dropChance = 0, deprecated = true, xpMul = 3.0, sellPriceMul = 0.50 },
	{ id = "magnetic",     displayName = "Magnetic",     dropChance = 0, deprecated = true, lureBonus = 3 },
	{ id = "barnacled",    displayName = "Barnacled",    dropChance = 0, deprecated = true, weightMul = 1.6 },
}

-- ====================================================================
-- BAIT
-- ====================================================================
-- Tunable knobs for the bait-shop purchase flow. Catalog data (names,
-- costs, rarityBoost values, maxStack) lives in BaitCatalog.lua so
-- designers can edit it without touching this file.
GameConfig.Bait = {
	-- RateLimiter window for BuyBait: at most RateLimitMax purchases in
	-- RateLimitWindowSec seconds per player.
	RateLimitMax       = 1,
	RateLimitWindowSec = 1,

	-- Maximum qty a player may request in a single BuyBait call.
	-- Prevents one-click drain exploits; also caps the UI "Buy" step.
	MaxBuyQty = 10,
}

-- ====================================================================
-- DATASTORE KEYS
-- ====================================================================
GameConfig.DataStores = {
	-- Bump this suffix to wipe all data (e.g. "ProfileV2"). Only do that if
	-- you intentionally want a fresh economy — there is no auto-migration.
	ProfileStore = "TidesProfile_v1",
	-- Cross-server market index — listings are stored as values keyed by
	-- listingId, with a sorted index for browsing.
	MarketStore  = "TidesMarket_v1",
	-- Daily demand spike — single key written by master server each UTC day.
	DemandStore  = "TidesDemand_v1",
}

-- ====================================================================
-- MODIFIER GLOW — per-modifier UIStroke settings for inventory pills.
-- Color drives the pill border glow; Thickness/Transparency tune visibility.
-- When 2+ modifiers appear on a card, the highest-priority modifier's Color
-- is also applied to the card's outer frame stroke.
-- ====================================================================
GameConfig.ModifierGlow = {
	-- New roll-eligible set
	rainbow      = { Color = Color3.fromRGB(255, 120, 200), Thickness = 3.0, Transparency = 0.10 },
	golden       = { Color = Color3.fromRGB(255, 215,  60), Thickness = 2.5, Transparency = 0.15 },
	silver       = { Color = Color3.fromRGB(220, 225, 240), Thickness = 2.0, Transparency = 0.25 },
	frozen       = { Color = Color3.fromRGB(140, 220, 255), Thickness = 2.0, Transparency = 0.20 },
	inferno      = { Color = Color3.fromRGB(255, 130,  50), Thickness = 2.5, Transparency = 0.15 },
	shocked      = { Color = Color3.fromRGB(255, 240,  80), Thickness = 2.0, Transparency = 0.20 },
	radioactive  = { Color = Color3.fromRGB(120, 255, 100), Thickness = 2.5, Transparency = 0.15 },
	crystal      = { Color = Color3.fromRGB(200, 230, 255), Thickness = 2.0, Transparency = 0.25 },
	colossal     = { Color = Color3.fromRGB(120, 220, 130), Thickness = 2.0, Transparency = 0.25 },
	tiny         = { Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5, Transparency = 0.30 },
	bloodlust    = { Color = Color3.fromRGB(220,  40,  40), Thickness = 2.5, Transparency = 0.15 },
	voidtouched  = { Color = Color3.fromRGB(170,  80, 255), Thickness = 2.5, Transparency = 0.15 },
	ghostly      = { Color = Color3.fromRGB(240, 245, 255), Thickness = 2.0, Transparency = 0.30 },
	disco        = { Color = Color3.fromRGB(255,  80, 200), Thickness = 2.5, Transparency = 0.20 },
	ancientcore  = { Color = Color3.fromRGB(220, 170,  90), Thickness = 2.0, Transparency = 0.25 },
	-- World-state
	tide_kissed  = { Color = Color3.fromRGB( 60, 200, 180), Thickness = 2.0, Transparency = 0.25 },
	storm_forged = { Color = Color3.fromRGB(120, 120, 200), Thickness = 2.5, Transparency = 0.20 },
	moon_touched = { Color = Color3.fromRGB(200, 200, 255), Thickness = 2.0, Transparency = 0.20 },
	dawn_blessed = { Color = Color3.fromRGB(255, 180, 100), Thickness = 2.0, Transparency = 0.20 },
	fog_shrouded = { Color = Color3.fromRGB(180, 200, 210), Thickness = 1.5, Transparency = 0.30 },
	-- Deprecated (kept for legacy items)
	shiny        = { Color = Color3.fromRGB(255, 230,  80), Thickness = 2.0, Transparency = 0.20 },
	giant        = { Color = Color3.fromRGB( 80, 200, 255), Thickness = 2.0, Transparency = 0.30 },
	glowing      = { Color = Color3.fromRGB(255, 200,  60), Thickness = 2.5, Transparency = 0.15 },
	lucky        = { Color = Color3.fromRGB(100, 230, 100), Thickness = 1.5, Transparency = 0.30 },
	ancient      = { Color = Color3.fromRGB(180, 140,  60), Thickness = 2.0, Transparency = 0.25 },
	prismatic    = { Color = Color3.fromRGB(200, 100, 255), Thickness = 3.0, Transparency = 0.10 },
	elder        = { Color = Color3.fromRGB(120,  80, 200), Thickness = 2.5, Transparency = 0.20 },
	cursed       = { Color = Color3.fromRGB(180,  40,  40), Thickness = 2.0, Transparency = 0.25 },
	magnetic     = { Color = Color3.fromRGB( 60, 180, 220), Thickness = 1.5, Transparency = 0.30 },
	barnacled    = { Color = Color3.fromRGB(140, 120,  80), Thickness = 1.5, Transparency = 0.35 },
}

-- ====================================================================
-- MESSAGINGSERVICE TOPICS — used for cross-server market notifications
-- ====================================================================
GameConfig.Topics = {
	MarketListed   = "TidesMarket_Listed",
	MarketSold     = "TidesMarket_Sold",
	MarketCanceled = "TidesMarket_Canceled",
	DemandRotated  = "TidesMarket_Demand",
}

-- ====================================================================
-- ASSETS
-- ====================================================================
-- Canonical paths under ReplicatedStorage for art assets. All service and
-- controller code that resolves building models sources the path from here
-- so it can be updated in one place if the folder hierarchy changes.
--
-- Lookup convention used by HarborVisualController:
--   Assets.Buildings[kind]["tier" .. N] / Visual   (Model instance)
GameConfig.Assets = {
	BuildingModels = "Assets.Buildings",
	Fish           = "Assets.Fish",
	Emotes         = "Assets.Animations",
}

-- ====================================================================
-- FISH HELD — weight-to-size mapping for the in-world held-fish model.
-- MinStuds: max-dimension target when fish is at its species weightRange min.
-- MaxStuds: max-dimension target when fish is at its species weightRange max.
-- ====================================================================
GameConfig.FishHeld = {
	-- Dramatic range: a max-weight fish is ~13× the volume of a min-weight fish.
	-- Tweakers: change MaxStuds to taste. MinStuds should stay ≥ 0.4.
	MinStuds = 0.5,
	MaxStuds = 8.0,
}

-- ====================================================================
-- AUDIO — client SoundController (ducking, ambient baseline).
-- Asset IDs live in src/Client/AssetIds.lua only.
-- ====================================================================
GameConfig.Audio = {
	DuckDb = -6,
	DuckAttack = 0.08,
	DuckRelease = 0.25,
	DuckMinHold = 0.35,
	AmbientBaseVolume = 0.28,
	-- MusicHarborTheme baseline. Sits below AmbientBaseVolume so the ocean
	-- stays the dominant cue and the music is the warm glow underneath.
	-- Ducked together with ambient on SFX (see SoundController:_duckLoops).
	MusicBaseVolume = 0.16,
}

-- ====================================================================
-- SETTINGS — player-facing Audio/Motion preferences (Settings hub UI).
-- Persisted server-side in Profile.settings; mirrored to Player attributes
-- (names below) for instant client reads by MotionUtil / SoundController.
-- ====================================================================
GameConfig.Settings = {
	-- Player attribute names (the live, presentation-layer cache). Stable
	-- strings — kept here so MotionUtil, SoundController, SettingsController
	-- and PlayerDataService all agree without duplicating literals.
	AttrAudioMuted   = "Setting_AudioMuted",   -- boolean
	AttrMasterVolume = "Setting_MasterVolume", -- number 0..1
	AttrMotionMode   = "Setting_MotionMode",   -- "auto" | "off" | "reduced"

	-- Defaults seeded into new profiles (and read when an attribute is unset).
	DefaultMuted        = GameConfig.UI.SoundMutedByDefault, -- reuse existing toggle
	DefaultMasterVolume = 1.0,
	DefaultMotionMode   = "auto",

	-- Master-volume slider granularity.
	VolumeStep = 0.05,

	-- Valid motion modes. "auto" follows GuiService.ReducedMotionEnabled;
	-- "off" forces full motion; "reduced" forces the reduced path.
	MotionModes = { "auto", "off", "reduced" },
}

-- ====================================================================
-- FISH BITE FEEDBACK — client-only (FishingController._onBite).
-- Sound asset id: AssetIds.Sounds.FishBite
-- ====================================================================
GameConfig.FishBite = {
	SoundVolume          = 0.7,
	CameraNudgeMagnitude = 0.3,
	CameraNudgeDuration  = 0.30,
	ButtonPulseScale     = 1.15,
	ButtonPulseDuration  = 0.15,
	VignetteAlpha        = 0.08,
	VignetteFadeDuration = 0.30,
}

-- ====================================================================
-- MODIFIER VISUALS — held-fish density (see HoldFishController, FishMutations).
-- ====================================================================
GameConfig.FishMutationVisuals = {
	HeldParticleRateScale    = 0.45,
	HeldLightBrightnessScale = 0.5,
	DefaultParticleSpread    = Vector2.new(35, 35),
	-- FishMutations: strip MeshPart.TextureID / SurfaceAppearance / SpecialMesh.TextureId
	-- so materialLock+tint show on all fish models (held, inventory viewport, preview).
	ClearMeshTextureOnMutation = true,
	DefaultMetalReflectance  = 0.4,
	-- Body-only size modifiers (no aura / particles).
	ModifierBodyScale = {
		tiny     = 0.65,
		colossal = 1.45,
	},
	-- Bag / catch-reveal ViewportFrame thumbnails (particles + stronger highlight read).
	ViewportParticleRateScale     = 2.5,
	ViewportAttachmentEmitCount   = 18,
	ViewportParticleSizeMul       = 2.2,
	ViewportHighlightFillMul      = 0.45,
	ViewportHighlightOutlineMul   = 0.55,
}

-- ====================================================================
-- ADMIN — dev tools (AdminService / AdminController). Whitelist in AdminService.
-- ====================================================================
GameConfig.Admin = {
	-- Every key in GameConfig.Weather.Transitions (Clear, Cloudy, Rain, Storm, Fog).
	WeatherStates = _adminWeatherStates,
	-- Studio playtests: weather panel open on join (F8 still toggles).
	OpenWeatherPanelInStudio = true,
}

-- ====================================================================
-- BIOME TEST HUB — Studio-only. Values consumed by BiomeTestService and
-- BiomeDebugController. Guard: RunService:IsStudio() in each file.
-- ====================================================================
GameConfig.BiomeTest = {
	HubCenter      = Vector3.new(-300, 0, 300),
	PlatformHeight = 4,
	PlatformSizeX  = 200,
	PlatformSizeZ  = 40,
	PadSize        = 16,
	PadHeight      = 0.5,
	PadSpacing     = 34,

	LabelStudsOffset = Vector3.new(0, 6, 0),

	-- Teleport destinations for each biome's sensor zone centre.
	-- Pier has no sensor zone so it will still resolve as Shoreline.
	TeleportTargets = {
		Shoreline = Vector3.new(600, 2, 550),
		Pier      = Vector3.new(520, 2, 660),
		Reef      = Vector3.new(600, 2, 1020),
		DeepWater = Vector3.new(600, 2, 1160),
		Trench    = Vector3.new(600, 2, 1400),
	},

	PadColors = {
		Shoreline = Color3.fromRGB(210, 190, 130),
		Pier      = Color3.fromRGB(160, 120,  80),
		Reef      = Color3.fromRGB( 70, 200, 200),
		DeepWater = Color3.fromRGB( 20,  60, 130),
		Trench    = Color3.fromRGB( 10,  20,  50),
	},
}

return GameConfig
