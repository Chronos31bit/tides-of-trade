--!strict
-- AssetIds.lua
-- Central registry of asset IDs the client references. Most are TODOs to
-- be filled in when art/audio ships. Code paths handle empty SoundIds by
-- silently skipping playback (see FishingController:_playSound).

local AssetIds = {
	-- Sounds
	Sounds = {
		-- TODO: replace with a real splash asset id ("rbxassetid://NNN").
		-- Used in FishingController on cast-land. Volume tuned to 0.6.
		CastSplash  = "",
		-- TODO: a soft "ka-ching" on successful catch.
		CatchSuccess = "",
		-- TODO: a small "miss" or string-snap on failed catch.
		CatchFail    = "",
		-- TODO: short "ding" when the marker enters the perfect zone.
		PerfectFlash = "",
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
