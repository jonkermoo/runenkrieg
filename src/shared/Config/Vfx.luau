--!strict
-- Spell effects (src/client/Vfx; user 2026-10-13: "highly animated and super bright", a Zoltraak-style beam, a
-- library of reusable effects). Every effect is built at run time from engine pieces only (Beams, SurfaceGui lines,
-- Neon parts, particles with Roblox's built-in sparkle texture, lights): no uploaded images, flat colors from
-- Config/Palette.Magic. Brightness above 1 is HDR: the Bloom in Lighting (threshold 2) makes it glow while the
-- world stays as it is. Sizes in studs, times in seconds, angles in degrees. Data only.

local Vfx = {
	-- Keeping it light (user 2026-10-13: "ensure that everything is made so that it doesnt cause lag in the future"):
	-- effects borrow their pieces from pools (src/client/Vfx/Pool) and give them back, one frame loop drives them all
	-- (Vfx/Driver), lightning is redrawn at BoltRate (not every frame), and far or surplus effects drop their extras.
	Quality = {
		MaxFree = 400, -- pooled pieces kept per kind; beyond this they're destroyed
		BoltRate = 30, -- lightning redraws per second
		FarDistance = 160, -- beyond this from the camera a beam skips its lightning and mist
		MaxRays = 8, -- beams at once with all their extras; more than this draw the bare beam
		MaxLights = 12, -- point lights at once (lights are the costly part); more go without
	},

	-- Color schemes (Palette.Magic names), one per look of the magic (user 2026-10-13: "different color magic (circles
	-- and laser and effects) ... be creative"): a beam's layers from the core out, its lightning (arc + arcCore), mist,
	-- flashes (flash), the impact glow (glow); the circle's lines (circle), dots (accent) and filled haze (haze); the
	-- charge (charge), the white-hot centres (core: charge, orbits, laser), the orbiting curves (orbit) and the aiming
	-- laser (pointer). A cast uses one throughout (Vfx/Zoltraak; the staff's: Config/Spells.Staff.Scheme).
	Schemes = {
		Arcane = { -- the blue-white Zoltraak
			layers = { "Core", "Glow", "Deep", "Violet" },
			arc = "Deep", -- saturated lightning with a white core, against the pale beam
			arcCore = "Core",
			mist = "Violet",
			flash = "Core",
			glow = "Glow",
			circle = "Glow",
			accent = "Core",
			haze = "Deep",
			charge = "Glow",
			core = "Core",
			orbit = "Glow",
			pointer = "Glow",
		},
		Hex = { -- a hot pink-violet capsule beam (user reference)
			layers = { "HexCore", "Hex", "HexDeep", "HexEdge" },
			arc = "HexDeep",
			arcCore = "HexCore",
			mist = "HexDeep",
			flash = "HexCore",
			glow = "Hex",
			circle = "Hex",
			accent = "HexCore",
			haze = "HexEdge",
			charge = "Hex",
			core = "HexCore",
			orbit = "Hex",
			pointer = "Hex",
		},
		Ember = { -- fire: an orange beam burning to red at its edge, gold lightning and runes
			layers = { "EmberCore", "Flame", "EmberDeep", "EmberEdge" },
			arc = "EmberGold",
			arcCore = "EmberCore",
			mist = "EmberDeep",
			flash = "EmberCore",
			glow = "Flame",
			circle = "Flame",
			accent = "EmberGold",
			haze = "EmberEdge",
			charge = "Flame",
			core = "EmberCore",
			orbit = "EmberGold",
			pointer = "Flame",
		},
		Verdant = { -- jade: a green beam with lime lightning
			layers = { "VerdantCore", "Verdant", "VerdantDeep", "VerdantEdge" },
			arc = "VerdantLime",
			arcCore = "VerdantCore",
			mist = "VerdantDeep",
			flash = "VerdantCore",
			glow = "Verdant",
			circle = "Verdant",
			accent = "VerdantLime",
			haze = "VerdantEdge",
			charge = "Verdant",
			core = "VerdantCore",
			orbit = "VerdantLime",
			pointer = "Verdant",
		},
		Solar = { -- holy gold: a white-gold beam, amber edges, white lightning
			layers = { "SolarCore", "Solar", "SolarDeep", "SolarEdge" },
			arc = "SolarDeep",
			arcCore = "SolarCore",
			mist = "SolarDeep",
			flash = "SolarCore",
			glow = "Solar",
			circle = "Solar",
			accent = "SolarCore",
			haze = "SolarEdge",
			charge = "Solar",
			core = "SolarCore",
			orbit = "Solar",
			pointer = "Solar",
		},
		Void = { -- dark magic: a deep violet beam fading to near black, toxic green lightning, runes and orbits
			layers = { "VoidCore", "Void", "VoidDeep", "VoidEdge" },
			arc = "VoidToxic",
			arcCore = "VoidCore",
			mist = "VoidDeep",
			flash = "VoidCore",
			glow = "Void",
			circle = "Void",
			accent = "VoidToxic",
			haze = "VoidEdge",
			charge = "Void",
			core = "VoidCore",
			orbit = "VoidToxic",
			pointer = "VoidToxic",
		},
		Brass = { -- the olive team's: a brass gold beam, white-gold core, amber lightning (Config/Spells.Staff.Teams)
			layers = { "BrassCore", "Brass", "BrassDeep", "BrassEdge" },
			arc = "BrassDeep",
			arcCore = "BrassCore",
			mist = "BrassDeep",
			flash = "BrassCore",
			glow = "Brass",
			circle = "Brass",
			accent = "BrassCore",
			haze = "BrassEdge", -- dark enough that the blast's puffs keep a rim (BrassDeep left them flat yellow)
			charge = "Brass",
			core = "BrassCore",
			orbit = "Brass",
			pointer = "Brass",
		},
		Crimson = { -- the white-brown team's: a rose crimson beam, pink-white core, deep red lightning
			layers = { "CrimsonCore", "Crimson", "CrimsonDeep", "CrimsonEdge" },
			arc = "CrimsonDeep",
			arcCore = "CrimsonCore",
			mist = "CrimsonDeep",
			flash = "CrimsonCore",
			glow = "Crimson",
			circle = "Crimson",
			accent = "CrimsonCore",
			haze = "CrimsonDeep",
			charge = "Crimson",
			core = "CrimsonCore",
			orbit = "Crimson",
			pointer = "Crimson",
		},
	},

	-- The magic circle (Frieren style): rings, a band of runes, crossed petals, six orbs and a centre, drawn as glowing
	-- lines on a flat disc. The rune band and the inner pattern spin opposite ways.
	Circle = {
		Diameter = 8,
		PixelsPerStud = 48, -- the drawing's resolution
		Line = 0.07, -- line thickness (studs)
		Brightness = 6,
		Color = "Glow",
		Accent = "Core", -- orb and centre dots
		Haze = { color = "Deep", transparency = 0.82 }, -- the faint filled disc behind the lines
		Runes = 26, -- around the band
		RuneSize = 0.055, -- of the diameter
		OuterSpin = 24, -- degrees/s, the rings and runes
		InnerSpin = -40, -- the petals and orbs
		CenterSpin = 90,
		Appear = 0.45, -- how long it takes to appear (Open below)
		Flash = 1.8, -- x brightness at the glow's height once it is whole
		-- appearing (user 2026-10-21: "looks too bouncy ... make it appear more magically"): it eases in from `from` of
		-- its size with no overshoot, fully drawn by `fadeIn` of the appear; its pieces light up from the centre out to
		-- the rim over `lightUp` of it; `flecks` motes of light gather in from `fleckFrom` x its radius; then a soft glow
		-- swells and settles over `glowTime` s
		Open = {
			from = 0.82,
			fadeIn = 0.5,
			lightUp = 0.85,
			flecks = 26,
			fleckFrom = 1.5,
			fleckLife = 0.35,
			fleckSize = { 0.08, 0.22 },
			glowTime = 0.45,
		},
		-- closing (user 2026-10-13: "make it shrink", "disintegrating as it shrinks away"): a small swell, then it
		-- collapses to a point, spinning faster and flaring brighter; meanwhile it crumbles piece by piece (each line,
		-- rune stroke, ring, petal and orb fades on its own, from the rim inward with some randomness) and sheds
		-- glowing square flecks off the crumbling edge that drift away and fade
		-- assembling (stage 3's circle, user 2026-10-13: "slowly build to come together"): it grows from a little over
		-- half size while its pieces light up from the centre outward and glowing flecks fly in to it from around
		Assemble = { from = 0.55, flecks = 70, fleckSize = { 0.12, 0.3 }, fleckLife = 0.4, fleckFrom = 1.7 },
		-- ready (user: "make it obvious when its ready to fire"): a bright flare and a bump in size, then it spins
		-- faster and keeps pulsing
		Ready = { flash = 3, flashTime = 0.35, bump = 0.03, spin = 2, pulse = 0.3, rate = 3 }, -- (bump was 0.12: bouncy)
		Close = {
			time = 0.55,
			anticipation = 1.2, -- how much it swells before collapsing (back-in easing)
			spin = 4, -- x the spin speed by the end
			flash = 2, -- x the line brightness by the end
			fadeFrom = 0.85, -- of the time: when what's left fades as a whole
			dissolve = 0.9, -- of the time: by then every piece is gone
			sweep = 0.6, -- how much a piece's turn follows its distance from the rim (the rest is random)
			soft = 0.2, -- of the dissolve: how long one piece takes to fade
			flecks = 40,
			fleckSize = { 0.1, 0.28 },
			fleckSpeed = { 2, 6 }, -- studs/s outward
			fleckLife = { 0.35, 0.7 },
		},
		Light = { range = 16, brightness = 3 },
	},

	-- A gathering charge: particles drawn in to a growing white orb, the light rising with it.
	Charge = {
		Duration = 0.7,
		Orb = 1.3, -- the core's final diameter
		Shell = 2.4, -- the soft shell around it
		ShellTransparency = 0.6,
		Color = "Glow",
		Core = "Core",
		Gather = { radius = 5, rate = 120, size = 0.3, life = 0.35 },
		Light = { range = 14, brightness = 6 },
		Pop = 0.12, -- the orb snaps out when released
	},

	-- The beam (Zoltraak; later a hitscan mid-long range weapon, user 2026-10-13): a capsule of stacked camera-facing
	-- layers (colors from the scheme, core out) with round glowing ends, widening away from the caster. The head
	-- shoots out, the layers flicker, anime lightning crawls along it and leaps off it, sparkle mist streams off,
	-- rings burst at the muzzle (user 2026-10-13: no rings racing along it); then it disintegrates (Dissolve).
	Ray = {
		Scheme = "Arcane",
		Extend = 0.08, -- the head travels from the caster to the end
		Hold = 0.45,
		Fade = 1.2, -- dies out slowly: disintegrates (Dissolve) while sputtering (Dying); a higher stage takes longer
		-- dying out (user 2026-10-13): while it crumbles it sputters (random bright flashes, wilder flicker)
		-- and little star glints pop on the pieces still there
		Dying = { sputter = 8, flashBright = 1.8, flashTime = 0.07, flicker = 0.3, glints = 2.5, glintLength = 2.5 },
		-- firing flashes (user 2026-10-13: "make it flash a bit"): the layers flare wide and bright for a moment and a
		-- white flash pops at the muzzle; then the beam pulses a little while it holds
		Flash = { time = 0.12, width = 1.5, bright = 2.2, ball = 2.4 }, -- ball: x layer 2's width
		Pulse = { rate = 12, amount = 0.15 }, -- Hz, x brightness
		-- disintegrating flashily (user 2026-10-13): one last bright flare, then it crumbles into gaps from the caster's
		-- end toward the target (each of `keys` points along it goes on its own turn, with some randomness), every
		-- crumbling bit throwing off glowing flecks (Vfx/Flecks)
		Dissolve = {
			keys = 16, -- points along the beam (a NumberSequence holds at most 20)
			sweep = 0.6, -- how much a point's turn follows its place along the beam (the rest is random)
			soft = 0.3, -- of the fade: how long one point takes to go
			flare = 1.4, -- x width and brightness at the start of the fade
			flareTime = 0.08,
			flecks = 60,
			fleckSize = { 0.12, 0.32 },
			fleckSpeed = { 3, 9 },
			fleckLife = { 0.3, 0.65 },
		},
		Layers = {
			-- brightness: above ~3 the Bloom washes everything to white. emission: 1 adds its light (glows, but stacked
			-- layers sum to white), 0 draws the plain color: only the core adds, so the body stays saturated.
			{ width0 = 0.8, width1 = 1.3, transparency = 0, brightness = 3, emission = 1 },
			{ width0 = 1.7, width1 = 2.8, transparency = 0.1, brightness = 1.6, emission = 0.15 },
			-- soft: fades out at both ends (the wide halo would otherwise end in a hard rectangle past the round caps)
			{ width0 = 2.8, width1 = 4.6, transparency = 0.5, brightness = 1.2, emission = 0, soft = true },
			{ width0 = 4, width1 = 6.6, transparency = 0.8, brightness = 1, emission = 0, soft = true },
		},
		Caps = 2, -- the round ends are balls of layer 2's width (x this at the head, which bulges like a capsule)
		CapBulge = 1.15,
		Flicker = 0.1, -- width jitter, a fraction
		-- anime lightning: `crawl` arcs zigzag along stretches of the beam just outside its core, spiralling round it;
		-- `leap` short arcs jump off its surface; `muzzle` crackle round the start. All redrawn at Quality.BoltRate.
		Bolts = {
			crawl = 3,
			crawlSpan = { 0.3, 0.8 }, -- of the beam's length
			crawlStep = 5, -- studs per zigzag segment (at most 10): long straight runs, sharp turns
			crawlTurns = 1.5, -- turns round the beam over its length
			radius = 0.55, -- x layer 3's width: the arcs crawl just outside the bright body, where they read
			jag = 1,
			width = 0.45,
			leap = 3,
			leapLength = { 1.5, 4 },
			muzzle = 2,
			muzzleLength = 2.5,
			brightness = 3,
			zOffset = 2, -- drawn in front of the beam's layers
		},
		Mist = { perStud = 12, maxRate = 600, size = 0.35, speed = 5, life = 0.5, spread = 1.4 },
		Rings = { radius = 2, width = 0.18, brightness = 2, muzzle = 2, muzzleGrow = 5 },
		Light = { range = 14, brightness = 1.5 }, -- at the muzzle, the middle and the end
	},

	-- Beam profiles: a Ray.play opts.profile overrides these keys of Ray above (the rest stay as Ray's). One per staff
	-- stage (Config/Spells.Stages).
	Beams = {
		-- the tap (user 2026-10-13: "a smaller quick beam instantly", references: a thin white-hot line): thin, out in
		-- a blink, gone fast; one crawling arc, a leap and a crackle at the muzzle; one muzzle ring, no racing rings
		Quick = {
			Extend = 0.04,
			Hold = 0.14,
			Fade = 0.8,
			-- dying out (user 2026-10-13): while it crumbles it sputters (random bright flashes, wilder flicker)
			-- and little star glints pop on the pieces still there
			Dying = {
				sputter = 6,
				flashBright = 1.6,
				flashTime = 0.06,
				flicker = 0.25,
				glints = 1.5,
				glintLength = 1.2,
			},
			Dissolve = {
				keys = 12,
				sweep = 0.6,
				soft = 0.3,
				flare = 1.4,
				flareTime = 0.06,
				flecks = 24,
				fleckSize = { 0.08, 0.2 },
				fleckSpeed = { 2, 6 },
				fleckLife = { 0.25, 0.5 },
			},
			Layers = {
				{ width0 = 0.32, width1 = 0.42, transparency = 0, brightness = 3, emission = 1 },
				{ width0 = 0.6, width1 = 0.8, transparency = 0.1, brightness = 1.6, emission = 0.15 },
				{ width0 = 1.1, width1 = 1.5, transparency = 0.5, brightness = 1.2, emission = 0, soft = true },
				{ width0 = 1.7, width1 = 2.3, transparency = 0.8, brightness = 1, emission = 0, soft = true },
			},
			CapBulge = 1.3,
			Bolts = {
				crawl = 1,
				crawlSpan = { 0.3, 0.7 },
				crawlStep = 5,
				crawlTurns = 1,
				radius = 0.6,
				jag = 0.6,
				width = 0.25,
				leap = 1,
				leapLength = { 1, 2.5 },
				muzzle = 1,
				muzzleLength = 1.5,
				brightness = 3,
				zOffset = 2,
			},
			Mist = { perStud = 4, maxRate = 250, size = 0.25, speed = 4, life = 0.4, spread = 0.7 },
			Rings = { radius = 1.2, width = 0.12, brightness = 2, muzzle = 1, muzzleGrow = 4 },
			Light = { range = 10, brightness = 1.2 },
			Impact = 0.55, -- the impact burst's scale
		},
		-- stage 2 (a slight charge, user 2026-10-13): between the tap and the full Zoltraak, fired through two circles;
		-- thicker and wilder than the tap (user: "a little bit thicker and slightly more exaggerated effects")
		Medium = {
			Extend = 0.06,
			Hold = 0.35,
			Fade = 1.2,
			-- dying out (user 2026-10-13): while it crumbles it sputters (random bright flashes, wilder flicker)
			-- and little star glints pop on the pieces still there
			Dying = { sputter = 8, flashBright = 1.8, flashTime = 0.07, flicker = 0.3, glints = 2.5, glintLength = 2 },
			Layers = {
				{ width0 = 0.75, width1 = 1, transparency = 0, brightness = 3, emission = 1 },
				{ width0 = 1.45, width1 = 2.1, transparency = 0.1, brightness = 1.6, emission = 0.15 },
				{ width0 = 2.5, width1 = 3.6, transparency = 0.5, brightness = 1.2, emission = 0, soft = true },
				{ width0 = 3.6, width1 = 5.2, transparency = 0.8, brightness = 1, emission = 0, soft = true },
			},
			CapBulge = 1.25,
			Flicker = 0.14,
			Flash = { time = 0.14, width = 1.6, bright = 2.4, ball = 2.6 },
			Bolts = {
				crawl = 3,
				crawlSpan = { 0.35, 0.85 },
				crawlStep = 5,
				crawlTurns = 1.8,
				radius = 0.55,
				jag = 0.95,
				width = 0.4,
				leap = 3,
				leapLength = { 1.5, 4 },
				muzzle = 3,
				muzzleLength = 2.5,
				brightness = 3,
				zOffset = 2,
			},
			Mist = { perStud = 10, maxRate = 500, size = 0.32, speed = 6, life = 0.5, spread = 1.3 },
			Rings = {
				radius = 1.9,
				width = 0.17,
				brightness = 2,
				muzzle = 3,
				muzzleGrow = 5,
			},
			Light = { range = 13, brightness = 1.5 },
			Dissolve = {
				keys = 16,
				sweep = 0.6,
				soft = 0.3,
				flare = 1.45,
				flareTime = 0.08,
				flecks = 45,
				fleckSize = { 0.1, 0.28 },
				fleckSpeed = { 3, 8 },
				fleckLife = { 0.3, 0.6 },
			},
			Impact = 0.95,
		},
		-- stage 3, the full charge (user 2026-10-13: "mimics a super strong zoltraak"): huge, long, wild
		Full = {
			-- still one hitscan shot (user 2026-10-13: "dont hold it out for so long"): a short hold, then the crumble
			Extend = 0.08,
			Hold = 0.25,
			Fade = 2.4, -- dies out a little longer (user 2026-10-13; was 1.8)
			-- dying out (user 2026-10-13): while it crumbles it sputters (random bright flashes, wilder flicker)
			-- and little star glints pop on the pieces still there
			Dying = { sputter = 10, flashBright = 2, flashTime = 0.08, flicker = 0.35, glints = 4, glintLength = 4 },
			Layers = {
				-- the solid body (layer 2) much thicker, the halo only a little (user 2026-10-13)
				{ width0 = 1.8, width1 = 2.7, transparency = 0, brightness = 3, emission = 1 },
				{ width0 = 4.2, width1 = 6.4, transparency = 0.1, brightness = 1.6, emission = 0.15 },
				{ width0 = 5.2, width1 = 7.8, transparency = 0.5, brightness = 1.2, emission = 0, soft = true },
				{ width0 = 7.2, width1 = 11.2, transparency = 0.8, brightness = 1, emission = 0, soft = true },
			},
			CapBulge = 1.3,
			Flicker = 0.14,
			Flash = { time = 0.2, width = 1.8, bright = 2.8, ball = 3 },
			Pulse = { rate = 10, amount = 0.2 },
			Bolts = {
				crawl = 5,
				crawlSpan = { 0.35, 0.9 },
				crawlStep = 6,
				crawlTurns = 2,
				radius = 0.55,
				jag = 1.3,
				width = 0.55,
				leap = 5,
				leapLength = { 2, 6 },
				muzzle = 4,
				muzzleLength = 3.5,
				brightness = 3,
				zOffset = 2,
			},
			Mist = { perStud = 16, maxRate = 900, size = 0.45, speed = 8, life = 0.6, spread = 2.4 },
			Rings = { radius = 3, width = 0.25, brightness = 2, muzzle = 4, muzzleGrow = 6 },
			Light = { range = 22, brightness = 2 },
			Dissolve = {
				keys = 18,
				sweep = 0.6,
				soft = 0.3,
				flare = 1.6,
				flareTime = 0.1,
				flecks = 110,
				fleckSize = { 0.15, 0.4 },
				fleckSpeed = { 4, 12 },
				fleckLife = { 0.35, 0.8 },
			},
			Impact = 1.6,
		},
	},

	-- Impact: a white flash ball, a flash of light, sparks thrown out and slowing, glowing shards.
	Burst = {
		Flash = { from = 1, to = 7, time = 0.25, color = "Core" },
		Glow = { from = 2, to = 8, time = 0.4, color = "Glow", transparency = 0.5 },
		Light = { range = 24, brightness = 4, time = 0.5, color = "Glow" },
		Sparks = { color = "Core", count = 60, speed = { 25, 60 }, size = 0.35, life = { 0.3, 0.7 }, drag = 6 },
		Shards = { color = "Glow", count = 10, size = 0.5, speed = { 15, 35 }, life = 0.6 },
		-- chunks of whatever was hit (its color), thrown off the surface under gravity (user reference: red chunks)
		Debris = { count = 9, size = { 0.3, 0.8 }, speed = { 12, 28 }, up = 0.6, gravity = 70, life = 0.9, spin = 12 },
		-- curved white comet streaks flung off the impact (the reference's white arcs)
		Streaks = { count = 6, speed = { 18, 34 }, length = 2.2, width = 0.22, bend = 1.2, life = 0.45, color = "Core" },
	},

	-- Every explosion (src/client/Vfx/Blast): the staff's stages, grenades, the field gun's and the howitzer's shells.
	-- User 2026-10-25 ("i'm starting to dislike the explosive and magical explosion effects"), with a stylised explosion
	-- clip: grenades "a quick explosion, less aggressive and 'fiery' looking", no cloud and no big shockwave; shells and
	-- magic "taller longer lasting clouds the stronger they are"; magic keeps its colours and leaves "rune / electricity
	-- static that stays behind (longer the stronger it is)"; every explosion throws dirt that falls back, "realistic".
	-- Round 2 (the user on the first build): "the cloud is too high and unrealistic, i liked the inital blast orb";
	-- "more variety of gray smoke that appears with the colored smoke"; runes "random and float and fade", the static
	-- "random, but connected with the runes"; grenades "too fast and non visible. exaggerate it a bit more". Then the
	-- design was agreed before building (a big orb at the hit, a low dome, grey smoke mixed in, floating runes).
	-- Two looks:
	-- - the pop (grenades: Blast.play's `pop`): a flash, a small hot orb, sparks, a brown dust puff and a faint dust ring,
	--   thrown clods (Pop);
	-- - the cluster (everything else): flash, spikes, sparks, ground rings, the orb (Orb) inside a low dome of balls
	--   cooling dark with a glowing rim (Cluster), grey smoke balls rolling up and drifting off (Smoke), clods, fine
	--   dirt raining out of the cloud (Rain), settling dust (Dust); magic also leaves runes floating up off the ground
	--   with static crackling between them (Runes, Static).
	-- `fireball` (studs, D) sizes everything; a charge's D is its real fireball (Charge). How strong it reads (how tall,
	-- how long) goes from 0 at D = Scale.small to 1 at D = Scale.big on a log scale: staff stage 1 (D 4) is 0, the field
	-- gun (2.5 kg, D ~14.5) ~0.45, staff stage 3 (D 22) ~0.6, the howitzer (340 kg, D ~70) 1. A pair { a, b } is the value
	-- at 0..1 of that strength.
	Blast = {
		Stages = { -- the staff's: D, ground rings, light spikes and the star glint
			{ fireball = 4, rings = 1, spikes = false },
			{ fireball = 9, rings = 2, spikes = true },
			{ fireball = 22, rings = 3, spikes = true },
		},
		-- Any charge: D = a x W^b metres (W kg of TNT; ~8 m at 10 kg), with `rings` ground rings
		Charge = { a = 3.86, b = 0.32, metresPerStud = 0.357, rings = 3 },
		Scale = { small = 4, big = 70 },
		-- The explosion's colours, as roles in the cast's scheme (Config/Vfx.Schemes): a ball starts `hot` (the white),
		-- burns `fire`, its rim glows in the scheme's `rim`-th layer (Ember: the deep orange-red; Arcane: the deep blue)
		-- and its body cools to that rim colour `dark` of the way to black (magic `darkMagic`: "magic stays their magical
		-- colour"). `spark`: sparks, spikes, star; `rune` / `static` / `staticCore`: what magic leaves behind.
		Colors = {
			hot = "flash",
			fire = "glow",
			rim = 3,
			dark = 0.88,
			darkMagic = 0.62,
			spark = "glow",
			rune = "glow",
			static = "arc",
			staticCore = "arcCore",
		},
		-- the first flash: a ball `size` x D across, gone in `time` s; a light `range` x D (Roblox caps 60) for `light` s
		Flash = { size = 0.75, time = 0.14, range = 3, brightness = 8, light = 1.2, lift = 2, max = 60 },
		-- The orb (user: "i liked the inital blast orb that appears where it blew up"): a ball `size` x D across sitting
		-- on the hit (`sink` of it below the ground), swelling over `grow` s, white-hot (its core `core` of it) in a
		-- burning shell, holding `hold` s, then cooling to the rim colour and fading over `fade` s while it swells
		-- `swell` x more.
		Orb = { size = 1, core = 0.7, sink = 0.15, grow = 0.12, hold = 0.3, fade = 0.45, swell = 0.15 },
		Star = 0.6, -- the star glint's length x D
		Rings = { to = 1.6, gap = 0.12, grow = 0.25, lift = 0.3 }, -- each ring out to `to` x D (+`grow` per ring)
		-- sparks flung out (speed x D / s), slowing, then falling under `gravity`
		Sparks = {
			perStud = 5,
			max = 90,
			speed = { 1.2, 3.2 },
			size = 0.4,
			life = { 0.4, 1.1 },
			drag = 3,
			gravity = 30,
			brightness = 6,
		},
		-- The low dome of balls round the orb: `perStud` balls a stud of D (`min`..`max`), each `size` x D across, in a
		-- dome `tall` x D high (user: "too high and unrealistic": was 0.45-2.2) narrowing to `narrow` of its foot's
		-- `spread` x D radius. Each flies out from the centre to its place over `grow` s, the higher ones `stagger` s
		-- later, drifting up `rise` x D a second. Over its `life` s: white-hot to `fire` until `hot` of it, the body
		-- cooling to dark and the rim from fire to the rim colour by `burn`, the rim dimming `rimFade` toward dark by
		-- `crumble`, then it crumbles away (shrinks and throws flakes, Rain). `jitter`: each ball's timing shifted up to
		-- this share (the blotchy look). The body is `inner` of the ball, moved `toward` (share of the radius) the camera
		-- so the rim shows round it.
		Cluster = {
			perStud = 0.5,
			min = 4,
			max = 18,
			size = { 0.3, 0.45 },
			spread = 0.55,
			tall = { 0.35, 1.2 },
			narrow = 0.6,
			grow = 0.18,
			stagger = { 0.1, 0.35 },
			rise = { 0.03, 0.05 },
			life = { 1.3, 4 },
			hot = 0.12,
			burn = 0.4,
			crumble = 0.72,
			rimFade = 0.6,
			jitter = 0.18,
			inner = 0.9,
			toward = 0.14,
			-- a crumbling ball dissolves into `puffs` puffs of dark smoke (its body colour), `puff` x its size across
			-- growing x `grow2`, rising `rising` x its size a second, living `puffLife` s
			puffs = 4,
			puff = 0.55,
			grow2 = 1.8,
			rising = 0.4,
			puffLife = { 0.8, 1.6 },
		},
		-- Grey smoke mixed in (user: "more variety of gray smoke that appears with the colored smoke"; then "for smoke
		-- and other effects, can we use actual effects and not blocks?"): Roblox's smoke texture, lit by the scene, one
		-- emitter per shade in `shades` (Palette.Magic), `count` puffs between them, from a box over the dome's upper half
		-- (`low`..1 of its height, `spread` x D wide), let out over `appear` s from `from` of the dome's life; each
		-- growing from `size[1]` to `size[2]` x D, rising `rise` x D a second (slowed by `drag`), drifting on the `wind`
		-- (studs/s^2), turning up to `spin` degrees/s, `thick` (transparency) after fading in over `fadeIn`, living
		-- `life` s (x 0.75..1) and thinning over its last `fade` share.
		Smoke = {
			shades = { "Smoke", "Ash", "SmokeDark", "Soot" },
			count = { 8, 40 },
			low = 0.3,
			spread = 0.9,
			from = 0.2,
			appear = 0.6,
			size = { 0.3, 0.75 },
			rise = { 0.08, 0.05 },
			drag = 0.4,
			wind = { 1.2, 0.3, 0.5 },
			spin = 20,
			thick = 0.15,
			fadeIn = 0.1,
			fade = 0.55,
			life = { 2, 8 },
		},
		-- Dirt thrown up (user: "not blocks"): soft clumps of the ground (the hit thing's colour, else what's under the
		-- blast, else `dirt`) in two shades x `shade`, `perStud` a stud of D (`min`..`max`), `size` x D^`sizePow` studs,
		-- thrown at `speed` x D^0.5 studs/s (at most `fastest`) within `spread` degrees of straight up, falling under
		-- `gravity`, living about as long as their flight back down x `airtime`, then fading over their last `fade`.
		Clods = {
			perStud = 1.4,
			min = 8,
			max = 50,
			size = { 0.3, 0.7 },
			sizePow = 0.35,
			speed = { 5, 12 },
			fastest = 70,
			spread = 40,
			gravity = 80,
			airtime = 0.95,
			fade = 0.25,
			spin = 90,
			dirt = "Mud", -- Palette.Terrain
			shade = { 0.7, 1.0 },
		},
		-- Fine dirt raining out of the cloud (the clip's falling flakes, made realistic): dark specks of the clods'
		-- colour x `shade`, from a box over the cloud, `rate` x D a second (at most `max`) from `from` of the dome's
		-- life for `last` of it, falling under `gravity`, each `size` studs, `life` s; a crumbling ball throws `flakes`.
		Rain = {
			rate = 1.6,
			max = 70,
			from = 0.35,
			last = 0.7,
			gravity = 14,
			size = { 0.18, 0.4 },
			life = { 1.5, 3 },
			shade = 0.5,
			flakes = 4,
		},
		-- Dust kicked up and settling round the foot (smoke texture in the clods' colour lightened `light`, lit by the
		-- scene): `count` x D^0.5 puffs (at most `max`) thrown out low at `speed` x D^0.5 studs/s, slowed by `drag`,
		-- growing from `size[1]` to `size[2]` x D, `thick` (transparency) at their thickest, living `life` s (x `longer`
		-- at full strength).
		Dust = {
			count = 3,
			max = 22,
			speed = { 2, 5 },
			drag = 2.5,
			spread = 75,
			size = { 0.18, 0.55 },
			thick = 0.35,
			life = { 0.9, 1.6 },
			longer = 2.5,
			light = 0.25,
			fadeIn = 0.12,
			spin = 30,
		},
		-- The grenade (user: "too fast and non visible. exaggerate it a bit more", then "the grenade needs more blast
		-- and effects": a bigger, longer orb with a few burning balls, a grey smoke puff, more dirt and sparks, a
		-- shockwave ring back): the same explosion as a shell at its own small D, no spikes, `rings` ground rings, x
		-- `sparks` sparks, its light x `light`, the grey smoke living `smokeLife` s; its dust (Dust) x `dust` as many, x
		-- `dustSize` as big, living x `dustLife`; its dirt (Clods) x `clods`, thrown x `throw` as fast; a faint dust
		-- ring: `ring` puffs racing out flat at `ringSpeed` x D^0.5 studs/s.
		Pop = {
			rings = 1,
			sparks = 2.5,
			light = 1.5,
			smokeLife = 3,
			dust = 1.6,
			dustSize = 1.2,
			dustLife = 1.8,
			clods = 2,
			throw = 1.4,
			ring = 14,
			ringSpeed = 5,
		},
		-- Magic's leftover runes (user: "random and float and fade"): `count` Elder Futhark runes (Glyphs), spawning one
		-- after another over `life` s at random spots within `radius` x D of the hit, each `size` x D tall (`least`..`most`
		-- studs), stroked `line` x their size (at least `thinnest`), tilted up to `tilt` degrees off the ground, turning
		-- `turn` degrees/s, floating up `float` x its size a second for `each` s, fading in over `appear` and out over its
		-- last `fade` share, flickering `flicker`. The first spawns `delay` s after the blast.
		Runes = {
			count = { 4, 14 },
			radius = { 0.45, 0.7 },
			size = { 0.18, 0.1 },
			least = 1.2,
			most = 7,
			line = 0.09,
			thinnest = 0.12,
			lift = 0.3,
			tilt = 55,
			turn = 30,
			float = { 0.25, 0.6 },
			each = { 1.2, 2.4 },
			delay = 0.25,
			appear = 0.25,
			fade = 0.4,
			life = { 1.8, 8 },
			flicker = 0.3,
			-- drawn as camera-facing beams (user: "not blocks"): a soft halo `halo` x the stroke wide at `haloSee`
			-- (transparency) round a solid line, `brightness` (Beam: above ~3 washes to white)
			halo = 2.6,
			haloSee = 0.55,
			brightness = 2,
		},
		-- Strokes of each rune, { x0, y0, x1, y1 } in a unit box (y up the rune)
		Glyphs = {
			{ { -0.2, -0.5, -0.2, 0.5 }, { -0.2, 0.1, 0.25, 0.4 }, { -0.2, -0.15, 0.25, 0.15 } }, -- fehu
			{ { -0.25, -0.5, -0.25, 0.5 }, { -0.25, 0.5, 0.25, 0.2 }, { 0.25, 0.2, 0.25, -0.5 } }, -- uruz
			{ { -0.2, -0.5, -0.2, 0.5 }, { -0.2, 0.25, 0.2, 0 }, { 0.2, 0, -0.2, -0.25 } }, -- thurisaz
			{ { -0.2, -0.5, -0.2, 0.5 }, { -0.2, 0.5, 0.2, 0.25 }, { -0.2, 0.2, 0.2, -0.05 } }, -- ansuz
			{ { 0.2, 0.4, -0.2, 0 }, { -0.2, 0, 0.2, -0.4 } }, -- kaunan
			{ { -0.25, -0.5, -0.25, 0.5 }, { 0.25, -0.5, 0.25, 0.5 }, { -0.25, 0.2, 0.25, -0.2 } }, -- hagalaz
			{ { 0, -0.5, 0, 0.5 }, { 0, 0.5, -0.3, 0.2 }, { 0, 0.5, 0.3, 0.2 } }, -- tiwaz
			{ { 0, -0.5, 0, 0.5 }, { 0, 0.1, -0.3, 0.45 }, { 0, 0.1, 0.3, 0.45 } }, -- algiz
			{ { 0.2, 0.5, -0.2, 0.15 }, { -0.2, 0.15, 0.2, -0.15 }, { 0.2, -0.15, -0.2, -0.5 } }, -- sowilo
			{ { 0, 0.4, 0.3, 0 }, { 0.3, 0, 0, -0.4 }, { 0, -0.4, -0.3, 0 }, { -0.3, 0, 0, 0.4 } }, -- ingwaz
		},
		-- Static between the runes (user: "random, but connected with the runes"): `arcs` arcs of `segments`, each
		-- redrawn every `refresh` s between a random showing rune and another within `reach` x D (or down to the ground
		-- under it when none is near), wandering `jag` studs, `width` wide, shown `on` of the time; a light flickering
		-- up to `light` over `range` x the runes' spread
		Static = {
			arcs = { 1, 4 },
			segments = 5,
			reach = 0.5,
			jag = 0.7,
			width = 0.14,
			refresh = 0.07,
			on = 0.6,
			brightness = 6,
			light = 3,
			range = 1.2,
		},
	},

	-- A gun's muzzle blast (src/client/Vfx/Muzzle; the artillery, Config/Artillery `muzzle` scale): `Flash` a ball `size`
	-- studs across in `color` (Palette.Magic) lighting `light` studs at `brightness` for `time` s; `Jet` grey smoke
	-- thrown out along the bore, `Side` a ring of it puffing out round the muzzle, `Dust` off the ground under it (if
	-- within `reach`): `count` puffs at `speed` studs/s, slowed by `drag`, spread `spread` degrees, growing from
	-- `size[1]` to `size[2]` studs, `thick` (transparency) after fading in over `fadeIn` of their `life` (s), drifting
	-- on the `wind`. Studs and speeds x the gun's scale.
	Muzzle = {
		-- (user 2026-10-21: "way way WAY more effect when the cannon is fired": the flash twice what it was; the smoke
		-- only a little more: 80 big puffs a shot in front of the camera dropped Studio to 8 fps, round 12)
		Flash = { size = 6, color = "Gold", light = 70, brightness = 6, time = 0.16 },
		Jet = {
			count = 12,
			speed = { 40, 110 },
			drag = 4,
			spread = 14,
			size = { 2, 8 },
			thick = 0.2,
			life = { 2, 3.5 },
			color = "Ash",
		},
		Side = {
			count = 8,
			speed = { 20, 45 },
			drag = 5,
			spread = 90,
			size = { 1.5, 6 },
			thick = 0.3,
			life = { 1.5, 2.5 },
			color = "Ash",
		},
		Dust = {
			count = 8,
			speed = { 10, 22 },
			drag = 2.5,
			spread = 80,
			size = { 2.5, 7 },
			thick = 0.4,
			life = { 1.5, 2.5 },
			color = "Smoke",
			reach = 8,
			width = 10,
		},
		fadeIn = 0.08,
		wind = { 1.2, 0.6, 0.5 },
		spin = 25,
	},

	-- A ring that races outward and thins (lying flat on the ground, or facing any way).
	Shockwave = { from = 0.5, to = 6, time = 0.4, line = 0.5, color = "Glow", brightness = 2 }, -- radii

	-- A star glint: four thin spikes from a point, facing the camera, popping out and back with a twist.
	Star = { length = 6, width = 0.6, time = 0.3, twist = 25, color = "Core", brightness = 10, flash = 1.2 },

	-- Light spikes: rays shooting out from a point in every direction (the "holy burst").
	Spikes = { count = 18, length = { 4, 11 }, width = 0.6, time = 0.4, color = "Gold", brightness = 8 },

	-- Lightning: a jagged bolt between two points, redrawn every few frames, with branches.
	Lightning = {
		segments = 10,
		jag = 0.9, -- sideways wander, studs
		width = 0.22,
		refresh = 0.05,
		duration = 0.6,
		branches = 2,
		branchLength = 0.35, -- of the bolt
		color = "Bolt",
		core = "Core",
		brightness = 8,
	},
	-- Crackling arcs round a body (the Deku look): short bolts hopping between points on a sphere.
	Aura = { radius = 2.6, arcs = 3, arcLength = { 1.5, 3.5 }, hop = 0.06, color = "Bolt", light = 8 },

	-- The full Zoltraak: a circle opens ahead of the staff, the charge gathers in its centre, a glint, the beam, and the
	-- impact where it ends.
	Zoltraak = {
		CircleAhead = 1.2, -- studs in front of the staff tip
		CircleDiameter = 7,
		Charge = 0.6,
		Range = 60, -- where the beam ends with nothing in the way
		CloseAfter = 0.15, -- the circle fades this long after the beam
	},
	-- The staff cast (Config/Spells stages; src/client/Vfx/Zoltraak.begin). Pressing opens the first circle; charging
	-- to a stage opens that stage's circle further out along the aim, larger (user 2026-10-13, references: circles
	-- stacked down the beam's axis, growing). Release fires the reached stage's beam (Config/Vfx.Beams) from the first
	-- circle's centre through the rest; then they disintegrate, the outermost first.
	Cast = {
		-- per stage: its circle (diameter, studs ahead of the tip, how fast it opens) and its beam profile
		Stages = {
			-- both a little smaller (user 2026-10-13, twice); all three a little farther out and a little farther apart
			-- (user 2026-10-13: in first person they read as a jumble; were 1.2 / 2.6 / 5)
			-- orbits: how many orbiting curves round the circle (Orbits below); linger: they keep going this long after
			-- the shot before thinning out (the big blast longest, user 2026-10-13)
			{ diameter = 3.8, ahead = 1.6, appear = 0.1, beam = "Quick", orbits = 2, linger = 0.15 }, -- a tap
			{ diameter = 5.8, ahead = 3.4, appear = 0.15, beam = "Medium", orbits = 3, linger = 0.3 }, -- a slight charge
			-- the full charge (user 2026-10-13: "super exaggerated, a lot larger, a super strong zoltraak"): it starts
			-- assembling `lead` seconds before its hold time (right after stage 2's circle has opened), so it builds slowly
			-- (user 2026-10-20: stage 2 at 1 s, stage 3 at 3 s; was 2 with stage 2 at 0.45)
			{ diameter = 11, ahead = 6.4, lead = 1.85, assemble = true, beam = "Full", orbits = 4, linger = 1 },
		},
		-- while the last circle assembles: a charge gathers in the first circle and lightning crackles between the first
		-- and last circles' rims, more of it as the charge builds (redrawn `rate` times a second)
		Build = { arcs = 5, segments = 7, rate = 20, width = 0.28, jag = 0.9, brightness = 3 },
		-- the moment it's ready: a big star glint in the first circle, light spikes, a shockwave round the last circle
		Ready = { star = 9, shockwave = 11 },
		-- firing the full charge: a bigger glint at the muzzle
		FireStar = 12,
		-- (how far a beam reaches: per stage, Config/Damage.Staff.Range, the same as the server's cast)
		CloseAfter = 0.05, -- the circles start closing this long after the beam starts fading
		CloseStagger = 0.07, -- each circle closes this much before the one inside it
	},

	-- Curves orbiting the magic circles (Vfx/Orbits; user 2026-10-13: "additional curves that orbit the circles in
	-- various locations and speeds ... flashing and staticky too like the laser"). Each: an arc of `segments` dashes
	-- spanning `span` radians on a ring `radius` times the circle's, its plane tilted `tilt` degrees, set `offset`
	-- studs along the axis, sweeping at `speed` rad/s (either way). Redrawn `rate` times a second: an orbit shows `on`
	-- of the time, each dash `dashOn`, widths times a random `flicker`. Widths and offsets are for a `reference`-stud
	-- circle (scaled with it). `fade`: seconds to thin out once stopped.
	Orbits = {
		segments = 9,
		span = { 0.9, 2.6 },
		radius = { 1.05, 1.4 },
		tilt = { 0, 0 }, -- parallel to the circle (user 2026-10-13; tilted up to 55 before)
		offset = { -0.6, 0.9 },
		speed = { 0.8, 2.8 },
		rate = 18,
		on = 0.88,
		dashOn = 0.72,
		flicker = { 0.5, 1.2 },
		width = 0.05,
		glow = 0.15,
		glowTransparency = 0.5,
		brightness = 3,
		color = "Glow",
		core = "Core",
		reference = 5.8,
		fade = 0.35,
	},

	-- The aiming laser (Vfx/Pointer; user 2026-10-13: "a small flashing staticky laser to where you are pointing", and
	-- reference frames: a straight line of glowing white dashes and gaps, changing all the time, blinking out now and
	-- then; it goes when the beam fires). From the held cast to the crosshair while aiming the staff. Redrawn `rate`
	-- times a second: up to `dashes` dashes, each `dash` of the line's length (share, random) after a `gap`; the whole
	-- line shows `on` of the time. A white core `width` in a `glow` (studs at `1 / perStud` from the camera, in
	-- proportion to the distance so it stays as thick on screen), each dash's width times a random `flicker`.
	Pointer = {
		dashes = 12,
		dash = { 0.03, 0.14 },
		gap = { 0.02, 0.1 },
		on = 0.85,
		rate = 18,
		color = "Glow",
		core = "Core",
		-- thinner, twice (user 2026-10-13; was 0.035 / 0.12, then 0.022 / 0.07)
		width = 0.014,
		glow = 0.045,
		glowTransparency = 0.5,
		brightness = 3,
		perStud = 0.08,
		flicker = { 0.6, 1.2 },
	},

	-- The effects showcase (src/client/VfxShowcase), DEV place only: a pad per effect off the map, each playing on a
	-- loop with a label; the effects play away from the viewer (-z). Teleport "Effects showcase" (Config/DevTools).
	Showcase = {
		PlaceId = 103459731368962,
		Origin = { 300, 0, -2700 }, -- the first pad (the floor top is y 0)
		Spacing = 22, -- studs between pads (x)
		Grenade = "grenade_mills", -- the "Grenade explosion" pad's (Config/Grenades.Types)
		Range = 160, -- pads loop only while the player is this close
		Floor = { 92, 94, 104 },
		Label = { 236, 232, 220 },
		Target = { 150, 62, 52 }, -- the blocks the beams hit (their debris takes this color)
		Entries = {
			{ effect = "Circle", label = "Magic circle", every = 2.5 },
			{ effect = "Charge", label = "Charge", every = 2 },
			{ effect = "Ray", label = "Ray (blue)", every = 1.6 },
			{ effect = "Ray", label = "Ray (violet)", every = 1.6, scheme = "Hex" },
			{ effect = "Burst", label = "Impact burst", every = 2 },
			{ effect = "Blast1", label = "Staff explosion (stage 1)", every = 2 },
			{ effect = "Blast3", label = "Staff explosion (stage 3)", every = 4 },
			{ effect = "Grenade", label = "Grenade explosion", every = 2 },
			{ effect = "Shell", label = "Field gun shell", every = 5, gun = "artillery_qf18" },
			{ effect = "Shell", label = "Howitzer shell (magic)", every = 9, gun = "artillery_howitzer" },
			{ effect = "Shockwave", label = "Shockwave", every = 1.5 },
			{ effect = "Star", label = "Star glint", every = 1.2 },
			{ effect = "Spikes", label = "Light spikes", every = 1.5 },
			{ effect = "Lightning", label = "Lightning bolt", every = 1.2 },
			{ effect = "Aura", label = "Lightning aura", every = 2 },
			{ effect = "Zoltraak", label = "Zoltraak (all together)", every = 4 },
			{ effect = "Cast1", label = "Staff tap (stage 1)", every = 1.2 },
			{ effect = "Cast2", label = "Staff charged (stage 2)", every = 1.8 },
			{ effect = "Cast3", label = "Staff full charge (stage 3)", every = 5 },
			-- the other looks of the magic (Schemes; user 2026-10-13: "different color magic ... be creative")
			{ effect = "Cast3", label = "Hex (pink-violet)", every = 5, scheme = "Hex" },
			{ effect = "Cast3", label = "Ember (fire)", every = 5, scheme = "Ember" },
			{ effect = "Cast3", label = "Verdant (jade)", every = 5, scheme = "Verdant" },
			{ effect = "Cast3", label = "Solar (holy gold)", every = 5, scheme = "Solar" },
			{ effect = "Cast3", label = "Void (dark, toxic green)", every = 5, scheme = "Void" },
		},
	},

	-- The staff's sounds (user 2026-10-14: "arcane hum + crackle", like Frieren's Zoltraak; src/client/SoundFx plays
	-- them). Placeholders from the Creator Store, all Pro Sound Effects (licensed for Roblox), each envelope measured
	-- (AudioAnalyzer) and trimmed to the part wanted: `start` / `stop` (seconds in the file), `fade` before the stop,
	-- `pitch` (playback speed), `loop`, and the falloff profile (Config/Audio). Per-stage lists are { stage 1, 2, 3 }.
	-- Heard by the caster only for now, like the casts themselves (they aren't replicated yet).
	Sounds = {
		-- every sound new (user 2026-10-14: "can you find me completely new sounds? these are pretty bad"; before that
		-- "terrifying, not cute", "too screechy"): dark, heavy, growling, all Pro Sound Effects (the braam APM), all on
		-- the Creator Store under Roblox's licence. `eq`: an equalizer (dB lows / mids / highs) cutting any sizzle;
		-- `fade`: down to nothing over the last seconds (to `stop` or the file's end).
		-- a circle opens: a growling magic burst, rumbling into a long reverb, a different one per stage
		-- (Magic Transition 3 / 5 / 6)
		Open = {
			{ id = 9116427220, volume = 0.9, pitch = 1, fade = 1.5, profile = "Spell", eq = { 2, 0, -12 } },
			{ id = 9116427328, volume = 1, pitch = 0.9, fade = 1.5, profile = "Spell", eq = { 2, 0, -12 } },
			{ id = 9116427399, volume = 1.2, pitch = 0.8, fade = 2, profile = "Spell", eq = { 3, 0, -12 } },
		},
		-- the charge: a hum per stage reached, scarier each time (crossfading over `fade` s), growing from `low` to full
		-- over the whole charge (Rules/Spells.charge): 1 the force field's growl-like phasing, 2 the evil power drone
		-- (its buzz cut), 3 a creature's nightmare growling
		Charge = {
			fade = 0.5,
			low = 0.4,
			stages = {
				{ id = 9116386364, volume = 0.9, loop = true, profile = "Hum" },
				{ id = 9119412665, volume = 0.6, loop = true, profile = "Hum", eq = { 2, 0, -15 } },
				{ id = 9113126091, volume = 1.4, pitch = 0.85, loop = true, profile = "Hum", eq = { 3, 0, -10 } },
			},
		},
		-- stage 3 ready: a dark low braam (APM "DARK BRAAM 05")
		Ready = { id = 9043342495, volume = 0.7, fade = 2.5, profile = "Spell" },
		-- the shots: stage 1 an energy burst growl; stage 2 the disintegrator blast; stage 3 thunder with a lion's roar
		-- over the disintegrator, dying away slowly
		Fire = {
			{ { id = 9114315023, volume = 0.9, fade = 1, profile = "Spell", eq = { 3, 0, -12 } } },
			{ { id = 9114119082, volume = 0.8, start = 0.55, fade = 1, profile = "Spell", eq = { 3, 0, -12 } } },
			{
				{ id = 9120030350, volume = 1.6, start = 0.4, fade = 2.5, profile = "SpellBig" },
				{ id = 9114118855, volume = 0.7, start = 0.55, fade = 1.2, profile = "SpellBig", eq = { 3, 0, -12 } },
			},
		},
		-- where a beam lands: an explosion, bigger and more violent with the stage, a faint electrical crackle in it for
		-- the magic (user 2026-10-14: "more explosive than electrical and thunder. do it for all 3")
		-- 1 a mortar's low thump and a sharp blast bang
		-- 2 a big heavy searing boom over the bang and the thump
		-- 3 a huge roaring fire explosion over the searing boom, a sub boom and the bang
		Impact = {
			{
				{ id = 9116973607, volume = 1.2, profile = "SpellBig" },
				{ id = 9114086424, volume = 0.6, fade = 1.5, profile = "SpellBig", eq = { 3, 0, -6 } },
				{ id = 9117877271, volume = 0.25, profile = "SpellBig", eq = { 0, 0, -6 } },
			},
			{
				{ id = 9117876706, volume = 1.2, fade = 2, profile = "SpellBig" },
				{ id = 9114086455, volume = 0.8, fade = 1.5, profile = "SpellBig", eq = { 3, 0, -6 } },
				{ id = 9116973348, volume = 1.2, profile = "SpellBig" },
				{ id = 9114235566, volume = 0.4, start = 0.55, fade = 1, profile = "SpellBig", eq = { 0, 0, -6 } },
			},
			{
				{ id = 9114554766, volume = 1.6, fade = 2.5, profile = "SpellBig", eq = { 3, 0, -4 } },
				{ id = 9117876706, volume = 1.6, fade = 2.5, profile = "SpellBig" },
				{ id = 9119661508, volume = 1.6, fade = 2, profile = "SpellBig" },
				{ id = 9114086424, volume = 1, fade = 2, profile = "SpellBig", eq = { 3, 0, -6 } },
				{ id = 9118067764, volume = 0.4, fade = 1.2, profile = "SpellBig", eq = { 0, 0, -6 } },
			},
		},
		-- the aiming laser: a low electrical hum with slow rattly pulses, quiet
		Laser = { id = 9125636146, volume = 0.5, loop = true, profile = "Hum" },
		-- a shot refused for want of mana: a dull thumpy poof
		Denied = { id = 9116406610, volume = 0.8, pitch = 0.8, profile = "Hum", eq = { 4, 0, -15 } },
		-- burnt out (the bar spent to nothing): a synth powering down
		Burnout = { id = 9119813929, volume = 0.6, start = 0.4, fade = 1, profile = "Hum", eq = { 2, 0, -12 } },
		-- floating: an eerie howling swirl, fading in and out
		Float = { id = 9116391746, volume = 0.25, loop = true, profile = "Hum", fadeIn = 0.4, fadeOut = 0.5 },
		-- thrown back by a stage 3 shot: a heavy air whoosh and thump
		Knock = { id = 9113077334, volume = 1, start = 0.5, profile = "Hum" },
	},
}

return table.freeze(Vfx)
