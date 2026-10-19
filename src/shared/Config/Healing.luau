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
	-- in the arm's axes), coloured from Config/Palette.Medical by part name.
	Held = {
		Bandage = { entry = "bandage_roll", grip = { 0, -1.25, 0 } },
		MedPack = { entry = "dressing_packet", grip = { 0, -1.25, 0 } },
	},

	-- The healer's animations (tools/animation/healing.luau): upper-body layers over the crouch (the healer crouches
	-- while healing, at crouch speed, no sprint or aim). The bandage wraps in circles, looping; the med pack is torn
	-- open (`tear`, once) and pressed on (`press`, looping).
	Animations = {
		wrap = { id = 114430068813850 }, -- HealWrap
		tear = { id = 91459275077815 }, -- HealTear
		press = { id = 77497388101770 }, -- HealPress
	},
	Fade = 0.15,
	Turn = 10, -- the healer turns to face the patient: share of the way per second (exponential)

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
