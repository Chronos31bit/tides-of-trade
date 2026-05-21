--!strict
-- TutorialConfig.lua
-- Every line of dialogue spoken in the 0–25 minute tutorial, plus the
-- per-beat metadata that drives TutorialService. Kept separate from
-- GameConfig.Tutorial (numeric tuning) so writers can edit Mira's voice
-- without scanning through balance knobs.
--
-- Editing dialogue is safe at any time — the runtime reads by beat key
-- + lineIndex, both of which are persisted on the profile. Adding lines
-- to a beat is fine. Removing or reordering lines mid-deploy will
-- mid-conversation a player who logs in on the old index; if you must,
-- bump the beat name (e.g. "greet" -> "greet_v2") so existing in-flight
-- profiles snap forward to line 1 of the new beat.

local TutorialConfig = {}

-- The ordered beat sequence. TutorialService walks this from index 1 and
-- advances to the next when each beat completes.
TutorialConfig.BeatOrder = {
	"greet",
	"cast_intro",
	"first_catch",
	"first_sale",
	"first_repair",
	"daily_quest_hook",
}

-- Dialogue tables. Each line is a single string. The "Continue" press
-- advances lineIndex; reaching past the last line of a beat triggers
-- :CompleteBeat for beats whose success condition is dialogue-only
-- (greet, daily_quest_hook's intro lines), or just waits for the gameplay
-- success condition (cast_intro, first_catch, etc.).
TutorialConfig.Lines = {
	greet = {
		"This place was your aunt's pride. It's a wreck now, but you've got good bones to work with.",
		"Let's start with the rod she left you.",
	},

	cast_intro = {
		"Hold to cast, release when the marker hits the green.",
	},
	-- Repeat-on-stuck nudges (Beat2StuckRepeatSeconds). Cycles through these.
	cast_intro_stuck = {
		"The rod's in your inventory — tap it and aim at the water.",
		"Hold the cast button, let the marker swing into the green band, then release.",
	},

	-- Two lines. Player presses Continue once after the catch reveal
	-- modal (catch reveal is z-index 10+, dialogue is z-index 5, so the
	-- modal sits on top; once the player dismisses it the dialogue is
	-- visible). The second line nudges toward the stall.
	first_catch = {
		"That's dinner! Or, if you're smart, that's coin.",
		"Bring it to my stall.",
	},

	first_sale = {
		"See that big board over there? That's every other dockmaster on the coast. You can sell to them too, when you're ready. For now, save your coin.",
	},

	first_repair = {
		"Forty coins gets the dock seaworthy again. Try it.",
	},
	first_repair_waiting = {
		"Catch a few more — you're almost there.",
	},
	first_repair_ready = {
		"You've got enough now. Tap the dock and pick Repair.",
	},

	daily_quest_hook = {
		"Tide's going out. Deep-water fish only show up at high tide — every 20 minutes.",
		"And the rarest ones come at midnight tide.",
		"I've got something for you. Catch 5 fish, any kind. Come back tomorrow.",
	},

	-- Spoken on completion right before despawn (no Continue press —
	-- shows for ~3s then closes itself).
	farewell = {
		"Good winds. I'll be around when you need me.",
	},

	-- Triggered if the player wanders >80 studs from the plot mid-tutorial.
	wander_recall = {
		"Wandering, are you? Let's get back to work.",
	},
}

-- Per-beat metadata. Drives TutorialService's state machine.
--
-- Fields:
--   dialogueKey:    key into TutorialConfig.Lines for the primary dialogue
--   advanceOn:
--     "dialogue_end" -> beat completes when player presses Continue past
--                       the last line (no gameplay trigger)
--     "gameplay"     -> beat waits for an external success condition,
--                       dialogue plays once then sits idle
--   highlight:      hint about what TutorialController should highlight
--                   ("cast_button", "market_stall", "dock_building",
--                   "quest_tracker", or nil)
--   showFollowupAfter: optional dialogueKey to show *after* a gameplay
--                      success but before transitioning to the next beat
--                      (used for first_catch's "Bring it to my stall.")
TutorialConfig.Beats = {
	greet = {
		dialogueKey = "greet",
		advanceOn   = "dialogue_end",
		highlight   = nil,
	},
	cast_intro = {
		dialogueKey = "cast_intro",
		advanceOn   = "gameplay",
		highlight   = "cast_button",
	},
	first_catch = {
		dialogueKey = "first_catch",
		advanceOn   = "gameplay",
		highlight   = "market_stall",
	},
	first_sale = {
		dialogueKey = "first_sale",
		advanceOn   = "gameplay",
		highlight   = "global_market_flash",
	},
	first_repair = {
		dialogueKey = "first_repair",
		advanceOn   = "gameplay",
		highlight   = "dock_building",
	},
	daily_quest_hook = {
		dialogueKey = "daily_quest_hook",
		advanceOn   = "gameplay",
		highlight   = "quest_tracker",
	},
}

-- Speaker label shown at the top of the dialogue box. Parameterized so
-- DialogueUI is reusable for other NPCs.
TutorialConfig.SpeakerName = "Captain Mira"

-- Portrait config. TODO: drop in the real asset id once art is supplied.
-- Until then, DialogueUI renders an 80x80 placeholder Frame with the
-- letter "M" centered.
TutorialConfig.MiraPortraitAssetId = nil

return TutorialConfig
