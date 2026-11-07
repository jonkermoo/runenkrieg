--!strict
-- Suppression (src/client/Suppression, Rules/Suppression; user 2026-11-01: "camera shake and arm wobble when shot near
-- or explosions go off (to make cover fire more useful)"). Enemy bullets passing close or landing close, and any
-- explosion nearby (your own and teammates' too), build a level from 0 to 1 on your own client. It holds `Hold` s after
-- the last hit, then falls by 1 every `Fall` s. While it is up, the first-person gun and arms wander (src/client/Sway)
-- and the camera shakes. Shots leave the visible gun's barrel, so the wander moves the aim: no extra spread. Third
-- person keeps its animations; only the view shakes. Client only, nothing sent. Data only.

return table.freeze({
	-- an enemy bullet passing within `radius` studs of your head: `add` on its path, nothing at the radius, `curve` the
	-- falloff's steepness (1 = straight); not within `clear` studs of the muzzle. A shotgun counts its nearest pellet.
	Pass = { radius = 6, add = 0.35, curve = 1.5, clear = 2 },
	-- an enemy bullet ending within `radius` studs of your body, feet to head (each bullet counts the stronger of its pass
	-- and this; a machine gun stitching the dirt round your feet pins you too)
	Impact = { radius = 6, add = 0.3, curve = 1.5 },
	-- an explosion of `kg` of TNT: `add` at the blast, nothing `reach` x the charge's cube root studs away (at most
	-- `maxReach`), `curve` the falloff. A Mills (71 g) reaches ~35 studs: ~0.8 at 5, ~0.2 at 20; a 2.5 kg shell ~115.
	Blast = { add = 1.1, reach = 85, maxReach = 250, curve = 2 },

	Cap = 1,
	Hold = 0.4,
	Fall = 1.5,
	-- the shake's size is level^grow, eased in at `ease` per second; the jolt below gives each hit its snap
	grow = 1,
	ease = 10,

	-- at full suppression (degrees): a slow wander `rate` times a second plus a tremor `tremorRate` times a second at
	-- `tremor` of the size. Aiming keeps `aim` of the gun's wander (the sights wander with it). The camera shakes by
	-- `cameraFirst` in first person, `camera` out of it (user 2026-11-01: "increase the shake in first person. make it
	-- practically unusable at medium+ range"; at 6 degrees a shot at 100 studs strays up to ~10 studs).
	viewmodel = { pitch = 6, yaw = 6, roll = 7 },
	cameraFirst = { pitch = 2, yaw = 2, roll = 2.5 },
	camera = { pitch = 0.5, yaw = 0.5, roll = 0.6 },
	rate = 0.9,
	tremor = 0.5,
	tremorRate = 11,
	aim = 1,
	-- the startle (user: "as if we got startled and shook"): every hit jerks the gun and, in first person, the view
	-- `viewmodel` / `camera` degrees x the hit's size (mostly up, a random side and roll), dying away squared over
	-- `time` s while it shudders `freq` radians per second
	Jolt = { viewmodel = 9, camera = 3, time = 0.35, freq = 32, up = 0.6 },
	-- first person: the camera within this many studs of the head
	FirstWithin = 1.5,

	-- The machine gun (user 2026-11-06: "machine guns should be a terrifying threat as a soldier", "someone getting
	-- shot at by an MG would know it's an mg and to be worried"). A machine gun's bullet (Config/Artillery `mg`) adds
	-- `weight` x a rifle's, and only machine-gun fire takes the level past `Cap` up to `cap`: "pinned", 0 at `Cap`, 1 at
	-- `cap`. At 450 rounds a minute and ~1 stud of stray at 100 studs, a burst on you is full in ~3 rounds and pinned in
	-- ~5 (under a second); rifle fire never pins. Pinned holds `hold` s after the last hit (not `Hold`), then falls as
	-- ever: gone ~3.5 s after the burst stops.
	MG = { weight = 1.4, cap = 1.6, hold = 1 },
	-- pinned, the gun's wander grows to `wander` x (the sights with it: no hidden spread, shots still leave the barrel)
	Pinned = { wander = 1.4 },

	-- the screen (src/client/SuppressionScreen): dark edges and drained colour. At level 1 the edges reach `depth` of the
	-- screen in from each side, `dark` black at the very edge; pinned they close in to `pinnedDepth`, `pinnedDark`, and
	-- pulse `pulse` darker and lighter at `beat` times a second (a racing heart). `ease`: how fast it follows (per s).
	Screen = {
		depth = 0.16,
		dark = 0.35,
		pinnedDepth = 0.3,
		pinnedDark = 0.6,
		pulse = 0.1,
		beat = 1.6,
		color = { 12, 8, 6 },
		ease = 8,
		-- colour: saturation (Lighting's ColorCorrection, -1 grey) and contrast at level 1 and pinned
		saturation = -0.2,
		pinnedSaturation = -0.35,
		contrast = 0.05,
	},
	-- hearing: every game sound's highs (and some mids) pulled down, dB, at level 1 and pinned (with a concussion's
	-- muffle the stronger one wins, src/client/Audio)
	Muffle = { high = -4, mid = -1, pinnedHigh = -10, pinnedMid = -3 },

	-- dirt (src/client/Impacts): a bullet landing within `near` studs of your body (feet to head) throws `count` x the dirt, `size` x
	-- bigger, and a dust puff (`Dust`); within `face` studs a few specks hit the screen (`Specks`). Not a bullet fired
	-- from within `own` studs of the head (your own).
	Dirt = {
		near = 8,
		own = 4,
		face = 4,
		count = 2,
		size = 1.5,
		-- the puff: `count` soft lumps `size` studs, rising slowly, gone in `life` s, `see` opaque at first
		Dust = { count = 3, size = 1.4, speed = 2, up = 3, gravity = 2, drag = 3, life = 0.9, see = 0.45 },
		-- on the screen: `count` specks `size` (share of the screen's height), gone in `life` s
		Specks = { count = 7, size = { 0.006, 0.02 }, life = 0.6, spread = 0.35 },
	},
})
