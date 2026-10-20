--!strict
-- Healing (H1; user 2026-10-18, docs/MILESTONES.md H1). Rules/Healing decides, src/server/Healing applies,
-- src/client/Healing picks the patient and plays the animations. Data only.
-- You never heal yourself (user: "you cannot heal yourself, you can only heal others"): look at a hurt soldier in
-- reach and press the Heal key (Config/Settings Key_Heal). At MedPackFrom health or more the med pack is used, below it
-- the bandage (user); both heal to full, a share at a time, unlimited supplies. Everyone can heal anyone until teams
-- (M13), then only teammates.

local Healing = {
	MedPackFrom = 70, -- the patient's health from which the med pack is used; below it, the bandage
	SecondsPerHp = 0.05, -- heal time grows with the health healed (user: "should not take more than 5 seconds")
	MaxSeconds = 5,
	Range = 6, -- studs between the two soldiers' roots to start a heal (and the prompt shows)
	Break = 8, -- studs apart at which a heal stops (the health healed so far stays)
	-- the client's pick: the hurt soldier in Range nearest the camera's look, within this many degrees of it
	PickCone = 25,
	StartSlack = 1.5, -- studs the server allows past Range when a start arrives (lag)
	AskGap = 0.25, -- seconds between a player's heal requests the server takes (rate limit)

	-- Slow recovery on your own (user: "you slowly recover health to up to 70 hp"): from `delay` seconds after the last
	-- drop in health (a hit, a fall, a dev tool), `rate` health a second up to `cap`. Any drop starts the wait again.
	-- `dummies`: DEV target dummies recover too (off: they keep their damage for tests).
	Recovery = { cap = 70, delay = 8, rate = 2, dummies = false },

	-- Each finished bandage heal puts the next wrap on the patient (user: left arm, right leg, head; after the third no
	-- new wraps). Config/Assets entries and the R6 part each sits on (its Origin at the part's centre). With the head
	-- wrap on, the soldier wears the helmet-on version of their hair (src/server/Helmets); a helmet stays on over it.
	Wraps = {
		{ entry = "wrap_arm", part = "Left Arm" },
		{ entry = "wrap_leg", part = "Right Leg" },
		{ entry = "wrap_head", part = "Head" },
	},

	-- What the healer holds: a Config/Assets entry welded to the right hand (its Origin `grip` below the arm's centre,
	-- in the arm's axes), `scale` times its modelled size (user 2026-10-19: "the models are way too small": chunky like
	-- the R6 hand), coloured from Config/Palette.Medical by part name.
	-- The bandage is the unrolling one (its strip pays out toward the left hand: Unroll); the med pack moves to the left
	-- hand (`leftGrip`) to be opened and its pad (`Pad`) comes out into the right hand (Open).
	Held = {
		Bandage = { entry = "bandage_unroll", grip = { 0, -1.35, 0 }, scale = 2.2 },
		MedPack = { entry = "dressing_packet", grip = { 0, -1.3, 0 }, leftGrip = { 0, -1.3, 0 }, scale = 2 },
		Pad = { entry = "dressing_pad", grip = { 0, -1.25, 0 }, scale = 2 },
	},
	-- The strip out of the unrolling bandage (user 2026-10-19: "unrolling bandage partially and applying"): `start`
	-- studs at the start of the wrap, growing `rate` a second, at most `max` (src/shared/HealItems.strip).
	Unroll = { start = 0.5, rate = 0.8, max = 3.5 },

	-- Before either item the healer reaches back to the pack for it (user 2026-10-18: "pretend to grab the
	-- bandage/medkit from behind us"): HealGrab plays for `time` seconds, the item shows in the hand at `take`. The
	-- patient's health only starts to rise once the healing itself starts (user: "once start performing the actual
	-- animation where we physically heal them"): after the grab for the bandage, after the grab and the opening
	-- (`Open.time`) for the med pack. A hit, moving apart or the Heal key still stop it before then.
	Grab = { time = 0.7, take = 0.3 },
	-- Opening the med pack (user 2026-10-19: "opening pack"), seconds into HealOpen: the red thread pulled off (it
	-- drops), the white pad drawn out into the right hand, the empty pack let fall; dropped pieces go after `fall`.
	Open = { time = 1.2, thread = 0.45, pad = 0.7, drop = 0.85, fall = 2 },

	-- The healer's animations (tools/animation/healing.luau): upper-body layers over the crouch (the healer crouches
	-- while healing, at crouch speed, no sprint or aim). The grab from the pack first; then the bandage wraps in
	-- circles, looping, or the med pack is opened (`open`, once) and its pad pressed on (`press`, looping).
	Animations = {
		grab = { id = 134857195633344 }, -- HealGrab
		wrap = { id = 114430068813850 }, -- HealWrap
		open = { id = 101138649879193 }, -- HealOpen
		press = { id = 77497388101770 }, -- HealPress
	},
	-- First person (user 2026-10-19), only when the player is already zoomed into first person (the free camera within
	-- `Zoom` studs of the head; user: "only if already in first person"): src/client/HealView's eye-fixed arms play
	-- these, the hands low in the view at the patient. Elsewhere the third-person animations show as usual.
	First = {
		Zoom = 1,
		Animations = {
			grab = { id = 128633229513483 }, -- FirstHealGrab
			wrap = { id = 136543324516095 }, -- FirstHealWrap
			open = { id = 99079308953762 }, -- FirstHealOpen
			press = { id = 110065612841817 }, -- FirstHealPress
		},
	},
	Fade = 0.15,

	-- The prompt over the patient's head (src/client/Healing): what it says per item, and its size.
	Prompt = {
		Bandage = "Bandage",
		MedPack = "Med pack",
		Size = { 150, 30 },
		Above = 2.2, -- studs over the head
		TextSize = 16,
		Transparency = 0.15, -- the panel behind the text
	},
}

return table.freeze(Healing)
