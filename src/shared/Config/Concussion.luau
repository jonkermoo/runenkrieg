--!strict
-- Concussion and shell shock (src/server/Concussion decides the hits that hurt, src/client/Concussion shows it all;
-- Rules/Concussion; user 2026-11-01: "make getting shot in the head (helmet knocked) concuss you (blur, high pitch
-- ring, slow to get up). add this to ragdolling from explosions as well", bots too; user 2026-11-03: "i want it to be
-- realistic", "a headshot should be a lot longer. and aggressive. we should make players stay down longer on a headshot
-- survival", "be sure the blur strength and duration lasts accurately too").
-- A concussion has a kind (Blast or Helmet) and a strength 0..1. Every effect runs from its kind's `Light` value at
-- strength `Light.at` to its `Heavy` value at strength 1, in a straight line; weaker than `Light.at` it shrinks in step.
-- Real blast hearing (blast-injury criteria): ~7 kPa muffles hearing for a while, ~14 kPa shifts it, ~35 kPa bursts the
-- first eardrums, ~100 kPa half of them; the highs go first. Data only.

local Concussion = {
	-- what concusses, and how hard:
	-- a helmet shot or struck off that doesn't kill: `least` at full health after the hit, `most` when it left the
	-- soldier at nothing (a near kill), in a straight line
	Helmet = { least = 0.3, most = 1 },
	-- a blast that throws a soldier who lives: by how hard it threw them (its damage over
	-- Config/Damage.Blast.Soldier.max, 0..1), from `least` for the faintest throw to 1 for the hardest
	Blast = { least = 0.45 },
	-- a blast near the own soldier, hurt or not (src/client/Concussion.near, every blast shown): by its overpressure at
	-- the head (Rules/Blast.kpa, Config/Damage.Blast), nothing under `from` kPa, `most` at `full` kPa and over, on a log
	-- scale between. Starts when the blast's sound gets there (Config/Audio.Heard.speed). Bands, studs from the blast:
	--   faint 2-9 kPa (~160-173 dB: a short quiet ring): a grenade 12-35, a field shell 42-130, the howitzer 135-260
	--   close 9-31 kPa: a grenade 6-12, a field shell 18-42, the howitzer 63-135
	--   very close 31-110 kPa: a field shell 10-18, the howitzer 34-63
	-- (inside a casing's splinter reach, Config/Grenades and Config/Artillery fragments, the soldier is usually wounded
	-- and thrown too: the heavier thrown concussion, Blast above, takes over; Studio 2026-11-03: from 5 kPa a field shell
	-- 60 studs off left almost nothing, too quiet for ~170 dB at the ear)
	Near = { from = 2, full = 110, most = 0.8 },

	-- the effects by kind, Light (strength `at`) to Heavy (strength 1). Seconds unless noted:
	--   duration: the picture's effects, held at full for `hold`, then fading out (`Fade`)
	--   blur: BlurEffect.Size at the start; it follows the ring (held and fading with it, user 2026-11-03: "make the
	--   blur be to scale with the ringing volume and fade"); saturation, brightness: ColorCorrection added; vignette:
	--   the screen's edges darkened
	--   (0..1); tilt: the view rolled to one side (degrees), fading; sway: a slow dizzy wobble (degrees)
	--   snap: the head thrown away from the shot (degrees, over `Snap.time`); flash: a white flash (brightness)
	--   ring: the ring's volume, lasting `ringFor` (held for `hold`, fading `RingFade`); pitch: its playback speed
	--   (user 2026-11-03: "make overall ringing shorter by a little ... and also lower how loud it can actually get":
	--   ringFor x0.75, the loudest 0.85 -> 0.6)
	--   muffle: how deep the world's sound is muffled (0..1, the highs cut first: `Muffle`), held `muffleFor`, back to
	--   clear over `muffleBack`; duck: every other sound's volume share at full muffle
	--   getUp: seconds added to a ragdoll's get-up wait (players and bots; only hits that knock: src/server/Ragdoll)
	--   reaction, aim: x a bot's reaction time and aim error
	Kinds = {
		Blast = {
			Light = {
				at = 0.15, -- (a near miss at ~4 kPa)
				duration = 0.6,
				hold = 0,
				blur = 1,
				saturation = 0,
				brightness = 0,
				vignette = 0,
				tilt = 0,
				sway = 0,
				snap = 0,
				flash = 0,
				ring = 0.08,
				ringFor = 1.1,
				pitch = 1,
				muffle = 0.25,
				muffleFor = 0.2,
				muffleBack = 1,
				duck = 0.9,
				getUp = 0,
				reaction = 1.2,
				aim = 1.3,
			},
			Heavy = {
				duration = 8,
				hold = 1,
				blur = 18,
				saturation = -0.4,
				brightness = -0.08,
				vignette = 0.6,
				tilt = 4,
				sway = 1.5,
				snap = 0,
				flash = 0.25,
				ring = 0.55,
				ringFor = 9,
				pitch = 1,
				muffle = 1,
				muffleFor = 2.5,
				muffleBack = 6,
				duck = 0.35,
				getUp = 1.5,
				reaction = 2,
				aim = 2.5,
			},
		},
		-- a round ringing off the helmet and knocking it away: sharper and higher than a shell, and long (user 2026-11-03)
		Helmet = {
			Light = {
				at = 0.3,
				duration = 10,
				hold = 1.5,
				blur = 14,
				saturation = -0.3,
				brightness = -0.05,
				vignette = 0.5,
				tilt = 2,
				sway = 1.5,
				snap = 6,
				flash = 0.4,
				ring = 0.5,
				ringFor = 7.5,
				pitch = 1.3,
				muffle = 0.85,
				muffleFor = 2,
				muffleBack = 4,
				duck = 0.5,
				getUp = 2.5,
				reaction = 2,
				aim = 2.5,
			},
			Heavy = {
				duration = 14,
				hold = 2.5,
				blur = 20,
				saturation = -0.45,
				brightness = -0.1,
				vignette = 0.7,
				tilt = 4,
				sway = 2.5,
				snap = 9,
				flash = 0.5,
				ring = 0.6,
				ringFor = 10.5,
				pitch = 1.3,
				muffle = 1,
				muffleFor = 3,
				muffleBack = 6,
				duck = 0.35,
				getUp = 4,
				reaction = 2.5,
				aim = 3,
			},
		},
	},
	-- how the picture's effects fade after `hold`: (1 - t / rest) ^ `Fade` (above 1: most of it goes early)
	Fade = 1.5,
	-- the ring's own fade exponent (1: even), so it lingers
	RingFade = 1,
	-- a new concussion over one still going takes the stronger of the two (what is left of the old one, or the new one)

	-- the muffle at full depth on every game sound (the "Effects" group, an EqualizerSoundEffect): dB off the highs and
	-- mids, dB onto the lows (the pressure in the ears); it comes in over `attack` s, so the bang itself is heard first
	Muffle = { high = 45, mid = 20, low = 3, attack = 0.12 },
	-- the head thrown by a helmet hit: dies away squared over `time` s
	-- (a hit this little across the view, straight down on the crown, nods the head back all the same)
	Snap = { time = 0.4, crown = 0.3 },
	-- the white flash: dies away squared over `time` s
	Flash = { time = 0.2 },
	-- the dark edges: each a gradient this share of the screen deep
	Vignette = { size = 0.3 },
	-- the dizzy wobble: the roll at `rate` cycles a second, the pitch and yaw as shares of its size, at their own rates
	-- (x `rate`) and phases (radians), so it never repeats in step
	Sway = {
		rate = 0.35,
		pitch = { size = 0.5, rate = 0.7, phase = 1 },
		yaw = { size = 0.4, rate = 0.55, phase = 2 },
	},
	-- under these the blur and the dark edges are switched off, not drawn faintly
	Shown = { blur = 0.05, vignette = 0.01 },

	-- the ring: "Ear Ring Tone Long", our own `length` s, 3.5 kHz tone (ASSETS_LICENSES.md), heard flat (not from a point),
	-- unmuffled, at the player's Master x Effects volume; the kind's `pitch` its playback speed. One take, never looped
	-- (user 2026-11-03: "it should be 1 continuous ringing"): every kind's `ringFor` x `pitch` fits in it
	Ring = { id = 77120881063360, length = 20 },
	-- a near blast's pressure on the ears: "Blast Thump", our own 1.4 s low fall (ASSETS_LICENSES.md), flat, at
	-- `volume` x its near strength over `full` (at most 1), not under `from`
	Thump = { id = 127738397510840, volume = 1.4, full = 0.6, from = 0.1 },
	-- the helmet knocked off: one of these Pro Sound Effects ricochets at random (ASSETS_LICENSES.md; user 2026-11-03:
	-- "use 3 helmet knock sounds"), flat, at `volume`
	Clang = { ids = { 9118168612, 9118168610, 9118168949 }, volume = 1.2 },
}

return table.freeze(Concussion)
