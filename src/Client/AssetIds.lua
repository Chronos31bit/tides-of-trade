--!strict
-- AssetIds.lua
-- Central registry of asset IDs the client references.
-- Sound sources are in assets/audio/sources/*.mp3 — upload each to Roblox Creator
-- Dashboard, then paste the numeric ID (rbxassetid://<id>) into the matching slot below.
-- Empty SoundIds skip playback silently (see SoundController:Play).

local AssetIds = {
	-- Sounds
	Sounds = {
		-- Soft water splash on cast-land (FishingController, vol 0.6, positional).
		-- SOURCE: assets/audio/sources/cast_splash.mp3 — upload to Roblox → paste ID here.
		CastSplash = "rbxassetid://97793133621610",
		-- Warm success sting on catch (FishingController, vol 0.6).
		-- SOURCE: assets/audio/sources/catch_success.mp3
		CatchSuccess = "rbxassetid://134827733154477",
		-- Soft miss on failed catch (FishingController, vol 0.4).
		-- SOURCE: assets/audio/sources/catch_fail.mp3
		CatchFail = "rbxassetid://119190588550650",
		-- Short ding when marker enters perfect zone (CastMeter, vol 0.35).
		-- SOURCE: assets/audio/sources/perfect_flash.mp3
		PerfectFlash = "rbxassetid://90366275533414",
		-- Bite / tug when reel phase starts (FishingController).
		-- SOURCE: assets/audio/sources/fish_bite.mp3
		FishBite = "rbxassetid://130672948013724",
		-- Gentle harbor waves loop (~22s CC0 loop, Freesound #852826 by kkenny101).
		-- SOURCE: assets/audio/sources/ambient_ocean.mp3
		AmbientOcean = "rbxassetid://97024260633648",
		-- Cozy harbor music loop (89.5s, "The calm theme" by BloodPixelHero, CC BY 4.0).
		-- ATTRIBUTION REQUIRED: credit BloodPixelHero in Settings/Credits screen.
		-- SOURCE: assets/audio/sources/music_harbor_theme.mp3
		MusicHarborTheme = "rbxassetid://116499952247778",
		-- Harbor tier upgrade FX (HarborVisualController, vol 0.5).
		-- SOURCE: assets/audio/sources/harbor_upgrade.mp3
		HarborUpgrade = "rbxassetid://117525060567787",
		-- Coin clink on harbor place/upgrade (HarborEditController, vol 0.45).
		-- SOURCE: assets/audio/sources/coin_clink.mp3
		CoinClink = "rbxassetid://114446160695929",
	},

	-- Images
	Images = {
		-- TODO: 1px-wide repeating texture for the fishing line Beam.
		-- A subtle off-white gradient works best.
		BeamTexture  = "",
		-- TODO: ring sprite for ripple expansion (alpha falloff at center
		-- and edge so it reads as a wavefront, not a disc). Leaving empty
		-- falls back to the geometric Cylinder ripple in FishingController.
		RippleRing   = "",
		-- TODO: 80x80 fish icon sheet keyed by species id. The reveal card
		-- currently shows a placeholder dark square when this is missing.
		FishIconSheet = "",
	},
}

return AssetIds
