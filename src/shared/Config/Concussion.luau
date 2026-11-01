--!strict
-- Concussion (src/server/Concussion decides, src/client/Concussion shows it; Rules/Concussion; user 2026-11-01: "make
-- getting shot in the head (helmet knocked) concuss you (blur, high pitch ring, slow to get up). add this to ragdolling
-- from explosions as well", bots too; feel picked: "Medium").
-- A concussion has a strength 0..1. Every effect runs from its `Light` value at strength `Light.at` to its `Heavy` value
-- at strength 1, in a straight line, and fades out over the concussion's duration. Data only.

local Concussion = {
	-- what concusses, and how hard:
	-- a helmet shot or struck off that doesn't kill: `least` at full health after the hit, `most` when it left the
	-- soldier at nothing (a near kill), in a straight line
	Helmet = { least = 0.3, most = 0.6 },
	-- a blast that throws a soldier who lives: by how hard it threw them (its damage over
	-- Config/Damage.Blast.Soldier.max, 0..1), from `least` for the faintest throw to 1 for the hardest
	Blast = { least = 0.45 },

	-- the effects at the light end (strength `at`) and the heavy end (strength 1); below `at` they shrink in step with
	-- the strength
	Light = {
		at = 0.3,
		duration = 3, -- seconds, fading out to nothing
		blur = 8, -- BlurEffect.Size at the start
		saturation = 0, -- ColorCorrection.Saturation added (negative: greyer)
		brightness = 0, -- ColorCorrection.Brightness added
		ring = 0.4, -- the ring's volume at the start
		duck = 0.7, -- every other sound's volume share while ducked
		duckFor = 1, -- seconds the other sounds stay ducked, then they come back over `Recover`
		getUp = 0.5, -- seconds added to a ragdoll's get-up wait (players and bots)
		reaction = 1.5, -- x a bot's reaction time
		aim = 1.75, -- x a bot's aim error
	},
	Heavy = {
		duration = 8,
		blur = 18,
		saturation = -0.35,
		brightness = -0.08,
		ring = 0.8,
		duck = 0.3,
		duckFor = 2,
		getUp = 1.5,
		reaction = 2,
		aim = 2.5,
	},
	-- how the effects fade over the duration: (1 - t / duration) ^ `Fade` (above 1: most of it goes early)
	Fade = 1.5,
	-- the ring fades a little slower than the rest (its own exponent), so it lingers
	RingFade = 1,
	-- seconds the other sounds take to come back up after `duckFor`
	Recover = 1.5,
	-- a new concussion over one still going takes the stronger of the two (what is left of the old one, or the new one)

	-- the ring: "Ear Ring Tone", our own 10 s, 3.5 kHz tone (ASSETS_LICENSES.md), heard flat (not from a point),
	-- unducked, at the player's Master x Effects volume; `speed` its playback speed (1 = as recorded)
	Ring = { id = 120218650833901, speed = 1 },
}

return table.freeze(Concussion)
