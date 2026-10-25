--!strict
-- The shovel (docs/MILESTONES.md SV1; Config/Weapons.shovel, src/client/Shovel). Data only.
-- Left click with the shovel in the hands digs, swung by the shovel's mode (src/client/Build; user 2026-10-23,
-- tools/animation/shovel.luau): in Build a dig tossed over the shoulder, in Destroy a charged strike. Holding the
-- fire key keeps swinging.

local Shovel = {
	-- one swing, a looping animation (Config/Weapons.shovel holds dig / chip), Dig in Build mode, Chip in Destroy mode
	-- (user 2026-10-24: "hold left click to continuously do the animation ... once left click is let go, after tossing
	-- over shoulder, it will go back to its idle animation"): `length` one swing (seconds); `strike` when the blade
	-- meets the ground (its "Strike" marker: the hit lands, src/client/Build); `rest` where a swing let go of settles
	-- back to the ready (its "Rest" marker: after the toss, or the chip wrenched loose)
	Dig = { length = 2.6, strike = 0.45, rest = 1.82 },
	Chip = { length = 1.5, strike = 0.5, rest = 1.0 },
	-- the swings' sounds (user 2026-10-24: "give me a digging and chipping sound"), Pro Sound Effects, each trimmed so
	-- its hit lands on the marker it plays at (src/client/Locomotion; others hear them through Net "Dug"):
	-- Dig at the dig's "Strike": "Shovel Dirt 1", the blade into the dirt through the push and the lever;
	-- Toss at the dig's "Rest" (the toss): "Dirt Shoveling Tossing Cu 7", its first burst at 0.55 s into the file;
	-- Chip at the chip's "Strike": "Dirt Digging With Pick 14", its thud at 0.35 s
	Sounds = {
		Dig = { id = 9119120449, volume = 0.9, stop = 1.5, fade = 0.3, profile = "Dig" },
		Toss = { id = 9114116650, volume = 0.9, start = 0.5, stop = 1.4, fade = 0.3, profile = "Dig" },
		Chip = { id = 9114084422, volume = 0.8, start = 0.33, stop = 1.3, fade = 0.4, profile = "Dig" },
	},
	SoundGap = 0.4, -- the server passes on one swinger's sounds no closer together than this (seconds)
	Enter = 0.35, -- the blend up from the ready into the first swing (seconds)
	Leave = 0.5, -- the blend from a swing's rest back to the ready
}

return table.freeze(Shovel)
