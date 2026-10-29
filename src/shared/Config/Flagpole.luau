--!strict
-- The capture-point flagpoles in Territory Push (FLAGPOLE.md, user 2026-10-27; built 2026-10-29): src/server/Flagpoles
-- stands a pole on each sector point while the frontline match runs (Workspace's Frontline folder), with the zone's ring of
-- stakes and, at the HQs, a knee-high ring of sandbags; src/client/Flagpoles raises the holder's flag as far as the
-- sector's control goes (bare pole at neutral), flaps it downwind, ties the holder's rags on the stakes and plays the
-- sounds. Rules/Flagpole is the maths. Colours Config/Palette.Flagpole; the flag image Config/Uniforms.Kits[kit].flag.pole.
local Flagpole = {
	FolderName = "Flagpoles", -- the poles' Workspace folder (one Model per sector, named by its id)
	Asset = "flagpole", -- Config/Assets: Pole, Knob, Cleat, Stake
	HQScale = 1.4, -- the HQ pole: the field pole's pieces this much bigger (20 -> 28 studs)
	Pole = { height = 20, topRadius = 0.27, footRadius = 0.42 }, -- the field pole's mesh (tools/blender/flagpole)
	Sink = 0.4, -- the pole and stakes stand this deep in the ground
	GroundRay = { top = 300, depth = 600 }, -- the ground found by a ray this high, this long, down on terrain only
	-- the flag: width x height (studs; the HQ's bigger), 4 hinged strips from the hoist; its top this far under the pole's
	-- top at full control, its bottom this far over the ground at the least control shown
	Flag = {
		size = { 7, 4.5 },
		hqSize = { 9, 6 },
		strips = 4,
		thickness = 0.06,
		topGap = 0.8,
		bottomGap = 2.2,
		gap = 0.08, -- off the pole's surface
		image = { strip = { 128, 328 } }, -- each strip's share of the `pole` flag image (512 x 328)
		ease = 3, -- per second: how fast the shown height follows the control
		pixelsPerStud = 32, -- the flag image's SurfaceGui resolution
	},
	-- the flap (Rules/Flagpole.flap): each strip turns from the one before by a wave travelling out to the free edge,
	-- bigger toward it; stronger wind flaps harder and faster (strength 1 at WindReference); contested flaps harder still
	Flap = {
		amplitude = 18, -- degrees between neighbouring strips at strength 1 (the free edge's)
		droop = 0.35, -- in no wind the flag hangs: this share of 90 degrees down the pole at strength 0
		speed = 5.5, -- radians per second at strength 1
		minSpeed = 2.2,
		wave = 1.1, -- radians the wave lags per strip
		contested = 1.6, -- amplitude and speed this much more while contested
		WindReference = 12, -- GlobalWind speed for strength 1 (Config/TreeSway's)
		DefaultWind = { x = 10, z = 4 }, -- used when GlobalWind is zero
	},
	-- a bullet through the cloth or near it (src/client/Impacts.shot) jolts it; a blast nearby whips it
	Jolt = { radius = 2.5, degrees = 28, decay = 6 },
	Whip = { radius = 40, perKg = 14, maxDegrees = 50, decay = 2.5 },
	-- full rate within `near`, every `farStep` seconds out to `far`, frozen beyond (studs)
	Lod = { near = 90, far = 400, farStep = 0.12 },
	-- the zone's edge: a knee-high stake every `spacing` studs round the circle, each with a rag in the holder's colour
	-- (bare at neutral); a stake whose ground has been dug away (trench, blast) more than `dug` under its foot is hidden
	Stakes = {
		spacing = 8,
		rag = { 0.55, 0.32, 0.04 },
		ragAt = 1.55,
		lean = 6,
		dug = 0.6,
		recheck = 2,
		ray = { up = 20, depth = 60 },
	},
	-- the HQ pole's knee-high sandbag ring (the sandbag pile's bags, Config/Assets sandbag_pile Bag1)
	Sandbags = { radius = 4, bag = "Bag1", length = 3.6, rise = 0 },
	Rope = { thickness = 0.06, out = 0.32, slackLean = 4 }, -- the halyard: its off-set from the pole, its lean when slack
	-- sounds, all 3D at the pole (nil id: silent); cloth flap loop louder in stronger wind, the halyard while the flag
	-- moves, the trench whistle when the point is taken (Pro Sound Effects, Creator Store terms: ASSETS_LICENSES.md;
	-- the whistle an Acme Thunderer, the WW1 trench whistle)
	Sounds = {
		Flap = { id = 9114461215 :: number?, volume = 0.5, min = 6, max = 40 }, -- Flag Flapping 1
		-- Pulley Rotating Movement With Squeaking 2; `moving`: control per second that counts as the flag moving
		Halyard = { id = 9117951813 :: number?, volume = 0.45, min = 4, max = 30, moving = 0.02 },
		Whistle = { id = 9125967307 :: number?, volume = 1, min = 20, max = 200 }, -- Soccer Whistle Acme Thunderer
	},
}

return table.freeze(Flagpole)
