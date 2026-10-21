--!strict
-- Artillery (docs/MILESTONES.md A2; user 2026-10-20: "we need to start working on making the artillery work"): the
-- QF 18-pounder field gun and the magic howitzer (models: A1, Config/Assets artillery_qf18 / artillery_howitzer).
-- src/server/Artillery places the guns, mans them and flies the shells; src/client/Artillery lays and shows them;
-- Rules/Artillery works the numbers. Data only.
-- Agreed with the user (2026-10-20):
-- - E mans a gun (one player does it all); a third-person cinematic camera behind it; the mouse lays it. An arc line
--   and a landing marker show where it would land, but the shot scatters ("it will be innacurate").
-- - Past the mount's traverse the whole gun swings round slowly (both guns).
-- - Dev-placed for now (the dev blast menu); real building waits for the build system.
-- - Reloads 10 s and 30 s ("they are very strong weapons"); a reload bar while manning.
-- - The howitzer is magic: an Arcane blast, its crystal shows the gun's state.
--
-- Gun space (studs, from the A1 generators tools/blender/artillery): right +X, up +Y, back +Z (the muzzle points -Z),
-- origin on the ground under the traverse axis. Angles in degrees: traverse + turns left (Roblox's yaw), elevation +
-- raises the muzzle.

export type Gun = {
	asset: string, -- Config/Assets entry (ReplicatedStorage.Assets.Weapons.Shared.Artillery)
	name: string, -- shown on the prompt
	base: string, -- the static part the model hangs on (its PrimaryPart)
	-- moving parts by what moves them (each also takes everything before it): the mount traverses, the cradle
	-- elevates, the barrel recoils, the breech opens
	mount: { string },
	cradle: { string },
	barrel: { string },
	breech: { string },
	trunnion: { number }, -- the elevation axis (gun X) passes through here
	hinge: { number }, -- the breech's vertical hinge
	muzzle: { number }, -- the bore's centre at the muzzle face
	boreCentre: number, -- the Bore disc's centre lies this far behind the muzzle face (finds gun space on the model)
	traverse: number, -- +- degrees on the mount
	elevation: { number }, -- min, max degrees
	swing: number, -- degrees/s the whole gun turns past the traverse
	traverseRate: number, -- degrees/s on the hand wheels
	elevationRate: number,
	speed: number, -- muzzle speed, studs/s (game-scaled: real ones overshoot the map; 1 stud = 0.357 m)
	kg: number, -- the shell's filling as TNT (Damage.blast)
	fragments: { lethal: number, wound: number, max: number, near: number, far: number }?, -- Rules/Grenade.fragments
	scatter: { yaw: number, elevation: number, speed: number }, -- the most a shot strays: degrees, degrees, share
	reload: number, -- seconds from a shot to the next
	breechOpen: number, -- degrees the breech swings open
	breechTimes: { number }, -- seconds after the shot it opens, and before ready it closes
	recoil: number, -- studs back along the bore
	recoilTimes: { number }, -- seconds back, seconds running out again
	-- the barrel's recoil is cut short so the breech's lowest point stays over `floor` (y): that point lies `along`
	-- studs behind the trunnion along the bore and `below` under its axis (Rules/Artillery.recoilAt); nil: always full
	recoilClear: { floor: number, along: number, below: number }?,
	crew: { number }, -- where the gunner stands (x, z; y from the ground there)
	prompt: number, -- reach of the E prompt, studs
	vfx: { scheme: string, magic: boolean },
	muzzleScale: number, -- the muzzle blast's scale (Config/Vfx.Muzzle)
	loads: boolean?, -- the gunner plays the loading (Load above)
	sound: { fire: any, far: any, blast: any, whistle: any, whistleLead: number },
	-- the gunner's camera (user 2026-10-20: "a cinematic lower left angle camera pov"): low at the gun's left rear,
	-- `side` (- left), `up` over the ground and `back` behind it along the aim, looking at a point `ahead` studs out
	-- along the aim, `rise` up, lifted further by the elevation x `follow` (so a high lob stays in view)
	zone: number, -- the impact zone's radius, studs (Zone above)
	camera: { side: number, up: number, back: number, ahead: number, rise: number, follow: number, fov: number },
}

local Artillery = {
	Folder = "Artillery", -- the Workspace folder the guns stand in
	-- the paint until teams exist (Config/Palette.Artillery.Paint)
	Paint = "Grey",

	-- What the gunner sends (Net "Artillery" "Aim"): at most `rate` a second; the mouse lays the gun by `sensitivity`
	-- degrees per pixel (yaw, elevation)
	Aim = { rate = 10, sensitivity = { 0.12, 0.06 } },
	-- the lay the server writes out to the gun (its attributes, the whole gun's swing) at most this often a second
	Send = 20,
	-- clients ease the posed lay toward those (per second), and swing the breech open or shut over `breechSwing` s
	Smooth = 12,
	BreechSwing = 0.4,
	-- the camera's ease toward its place (per second; higher = stiffer)
	CameraEase = 6,
	-- a flight longer than this is given up (seconds)
	MaxFlight = 20,
	-- the server steps a shell's path this often (seconds)
	Step = 1 / 30,
	-- E again (or the leave key) gets off the gun, not before this long after getting on (the same press)
	LeaveAfter = 0.4,

	-- The arc line and landing marker while manning (src/client/Artillery): the line is one Beam bent to the path
	-- (as the grenade's, Palette.Artillery.Arc), the marker a ring and the range on top of everything (seen past the fog)
	Arc = {
		step = 0.1, -- seconds of flight between the casts that find where it lands
		refresh = 0.1, -- seconds between redraws
		floor = -60, -- below this height (studs) the path is given up (under the map)
		-- the ground where it comes down unloaded on this client (streaming): asked for again once the landing has moved
		-- this many studs
		restream = 100,
		width = 0.5,
		segments = 60,
		transparency = 0.35,
		marker = 46, -- the ring's size in pixels, its line `ring` thick, the range's text `text` high
		ring = 3,
		text = 18,
	},

	-- Firing (user 2026-10-20: "have the character play a brace animation or prepare for loud explosion animation when
	-- firing (play that first then fire, a slight delay in the shots makes it feel real)"): the gunner plays `animation`
	-- (tools/animation/artillery.luau ArtilleryBrace: reach for the lever, lean away, pull) and the shot goes `delay` s
	-- after the click, at its "Fire". Turning (user: "add an animation for turning the weapon too"): while the gun is
	-- being laid (the aim more than `moving` degrees off its lay) the gunner winds the hand wheel (`crank`, a loop),
	-- easing in and out over `fade` s. nil: not uploaded yet.
	Brace = { animation = 110111507484119 :: number?, delay = 0.45 },
	Turn = { crank = 80321147839061 :: number?, moving = 0.3, fade = 0.2 },

	-- The impact zone (src/client/Artillery; user 2026-10-20: "the impact zone should be showed like a highlight on the
	-- surface the cannon is going to hit"): a glowing disc (Palette.Artillery.Marker) lying on the ground where it would
	-- land, the gun's `zone` studs in radius (about where its blast still hurts), `fill` transparent, `thickness` thick,
	-- `lift` off the surface; a core `coreShare` of it across pulsing between the `core` transparencies at `pulse` rad/s.
	-- Past `ringFrom` studs from the camera the ring over it shows too (the haze, Map 1's Atmosphere, hides parts far
	-- off; Lighting.FogEnd isn't it: Studio round 5).
	Zone = {
		fill = 0.72,
		core = { 0.45, 0.8 },
		coreShare = 0.35,
		thickness = 0.15,
		lift = 0.1,
		pulse = 5,
		ringFrom = 450,
	},

	-- The reload bar (bottom centre while manning; Palette.UI)
	Bar = { width = 220, height = 12, margin = 90, text = 16 },

	-- The howitzer's crystal (src/client/ArtilleryCrystal, Rules/Artillery.crystal; user 2026-10-20: "make the howitzer
	-- loading just a empty colored crystal and the color slowly returns (make it look nice, like its coming back to
	-- life)", "give the crystal more design and effects. some runes on it works too"). RGB colours: `empty` drained,
	-- `ready` full, `fired` white-hot. The flare: `flareGlow` draining over `flare` s. Charging: the glow rises as the
	-- share ^ `curve`, sputters below `sputter`, heartbeats at `beat` (a second, start to end) adding `beatGlow`; full,
	-- it blooms `awakeGlow` over `awake` s, then breathes by `breath` at `pulse` rad/s. The barrel's and bed's runes
	-- (`alsoRunes`) dim and come back with it, never below `runesFloor`. `light`: a point light in it, `range` /
	-- `brightness` at full glow.
	-- Round it: `runes` Elder Futhark runes (Config/Runes strokes) circling level round the crystal, `orbit` studs out,
	-- `size` studs tall, `spin` deg/s, `bob` studs up and down; each wakes in turn as it charges (over `runeFade` of the
	-- charge), flickering on; all scatter `scatter` studs and fade on the shot. Motes of light drawn into it while it
	-- charges: up to `motes` a second, from `moteFrom` studs, `moteSize` studs.
	Crystal = {
		empty = { 20, 26, 40 },
		ready = { 70, 150, 255 },
		fired = { 225, 245, 255 },
		flare = 0.6,
		flareGlow = 1.6,
		curve = 1.6,
		sputter = 0.3,
		beat = { 0.5, 1.6 },
		beatGlow = 0.35,
		awake = 0.5,
		awakeGlow = 0.6,
		breath = 0.2,
		pulse = 1.6,
		alsoRunes = { "BarrelRunes", "BedRunes" },
		runesFloor = 0.15,
		light = { range = 14, brightness = 2.5 },
		runes = 8,
		orbit = 2.1,
		size = 0.75,
		spin = 25,
		bob = 0.15,
		runeFade = 0.1,
		scatter = 2.5,
		stroke = 0.12, -- a stroke's width, of the rune's height
		motes = 14,
		moteFrom = 3,
		moteSize = 0.18,
	},

	-- Sounds (Pro Sound Effects, licensed through Roblox; ASSETS_LICENSES.md), per gun below: `fire` its report up
	-- close, `far` heard past `FarFrom` studs instead, `blast` the shell going off; the incoming shell's `whistle` is
	-- heard within `Whistle.reach` studs of where it lands, starting the gun's `whistleLead` s before it lands (only on a
	-- flight at least that long: a short one comes in under the report; Studio round 2). All late and
	-- duller far off (Rules/Grenade.heard).
	Whistle = { reach = 300 },
	Heard = { dullFrom = 80, dullFull = 900, highCut = -14, lowBoost = 5 },
	FarFrom = 400,

	-- The field gun's loading (tools/animation/artillery.luau; user 2026-10-20: "make the player load the shell as an
	-- animation. the howitzer can be just the crystal"): the gunner's client plays `animation` from `lead` s before
	-- ready (its "Close" as the breech shuts); every client shows the round (Config/Assets `round`) at the gunner's
	-- right hand from `take` to `loaded` s into it, its base in the hand, level along the gun. nil animation: none yet.
	-- The reload runs on with nobody on the gun (user 2026-10-20: "reloading should happen when players are off the
	-- cannons too"); a gunner getting on during the loading picks it up where it is (`length` s long).
	Load = {
		animation = 77988505499096 :: number?,
		lead = 3.45,
		take = 0.5,
		loaded = 2.1,
		length = 3,
		round = "round_qf18",
	},

	Guns = {
		-- QF 18-pounder (A1): traverse 4.5, elevation -5..16 about the trunnion, recoil 46 in, the breech 100 degrees.
		-- 745 studs/s: ~1,500 studs at 16 degrees (Map 1 HQ to HQ 1,800), ~2 s in the air.
		artillery_qf18 = {
			asset = "artillery_qf18",
			name = "QF 18-pounder",
			base = "Carriage",
			mount = { "Mount" },
			cradle = { "Cradle" },
			barrel = { "Barrel", "Bore" },
			breech = { "Breech" },
			trunnion = { 0, 2.544, -0.266 },
			hinge = { 0.457, 2.855, 2.398 },
			muzzle = { 0, 2.855, -4.808 },
			boreCentre = 0.123,
			traverse = 4.5,
			elevation = { -5, 16 },
			swing = 10,
			traverseRate = 6,
			elevationRate = 4,
			speed = 745,
			kg = 0.6,
			fragments = { lethal = 6, wound = 30, max = 100, near = 60, far = 10 },
			scatter = { yaw = 0.8, elevation = 0.25, speed = 0.012 },
			reload = 10,
			breechOpen = 100,
			breechTimes = { 1.2, 1 },
			recoil = 3.34,
			recoilTimes = { 0.08, 1.2 },
			recoilClear = nil,
			crew = { -1.6, 3.4 }, -- left of the breech, behind it (the loading reaches it), clear of the trail
			prompt = 8,
			vfx = { scheme = "Ember", magic = false },
			muzzleScale = 1,
			loads = true,
			sound = {
				fire = {
					{ id = 9116973611, volume = 1.4, profile = "Explosion" }, -- Mortar Explosion 3: big, low thump
					{ id = 9114362266, volume = 0.8, profile = "Explosion" }, -- Explosions 4: the crack and its debris
				},
				far = { { id = 9113169432, volume = 1.2, profile = "Explosion" } }, -- Artillery Distant 2
				blast = {
					{ id = 9114362266, volume = 1.4, profile = "Explosion" }, -- Explosions 4
					{ id = 9114086964, volume = 1, profile = "Explosion" }, -- Dirt Explosion 2
					{ id = 9114363833, volume = 1, profile = "Explosion", eq = { 3, 0, -3 } }, -- Explosive Boom 2
				},
				-- Bullet Whiz By 1 (lengthened), slowed into a shell's rushing whine
				whistle = {
					{ id = 9113634642, volume = 0.9, profile = "Explosion", pitch = 0.6, stop = 0.75, fade = 0.2 },
				},
				whistleLead = 1.2, -- (its flights are ~0.5-2 s)
			},
			zone = 10, -- 0.6 kg: hurt to ~8 by the blast, lethal fragments to 6
			-- (Studio rounds 5-6: at 2.2 up the grass filled the view; at 9 left the gunner stood in the middle of it)
			camera = { side = -14, up = 5, back = 8, ahead = 60, rise = 3, follow = 0.5, fov = 60 },
		} :: Gun,
		-- The magic howitzer (A1, BL 9.2-inch at 1.3x): traverse 30 about the racer, recoil 40 in (1.3x), cut short at
		-- high elevation (the breech would reach the platform: top 3.36, the breech block's low back corner 4.05 behind
		-- the trunnion and 1.54 under it; 0.46 at 80). A short-arc mortar (user 2026-10-20: "make the howitzer more of a
		-- short arc mortar weapon"): it only lobs, 45..80 degrees (the real gun stopped at 55), at 340 studs/s: ~590 studs
		-- at 45 down to ~200 at 80, 2.5-3.4 s in the air.
		artillery_howitzer = {
			asset = "artillery_howitzer",
			name = "Magic howitzer",
			base = "Bed",
			mount = { "Mount" },
			cradle = { "Cradle" },
			barrel = { "Barrel", "BarrelRunes", "Bore" },
			breech = { "Breech", "Crystal" },
			trunnion = { 0, 8.37, 0.616 },
			hinge = { 1.12, 7.782, 3.723 },
			muzzle = { 0, 7.782, -7.054 },
			boreCentre = 0.148,
			traverse = 30,
			elevation = { 45, 80 },
			swing = 3,
			traverseRate = 5,
			elevationRate = 5,
			speed = 340,
			kg = 15,
			fragments = nil,
			scatter = { yaw = 0.9, elevation = 0.35, speed = 0.015 },
			reload = 30,
			breechOpen = 100,
			breechTimes = { 2, 2 },
			recoil = 3.77,
			recoilTimes = { 0.12, 2 },
			recoilClear = { floor = 3.66, along = 4.05, below = 1.54 },
			crew = { -2.6, 4.6 },
			prompt = 12,
			vfx = { scheme = "Arcane", magic = true },
			muzzleScale = 2.2,
			sound = {
				fire = {
					{ id = 9119382515, volume = 1.5, profile = "Explosion" }, -- Sonic Boom 2: a huge single boom
					{ id = 9116973607, volume = 1.2, profile = "Explosion" }, -- Mortar Explosion 5
				},
				far = { { id = 9113169264, volume = 1.4, profile = "Explosion" } }, -- Artillery Distant 1
				blast = {
					{ id = 9114362135, volume = 1.5, profile = "Explosion" }, -- Explosions 1: rumbling, punchy
					{ id = 9114086964, volume = 1.2, profile = "Explosion" }, -- Dirt Explosion 2
					{ id = 9114363996, volume = 1.2, profile = "Explosion", eq = { 4, 0, -3 } }, -- Explosive Boom 5: the long tail
				},
				whistle = {
					{ id = 9113634642, volume = 1, profile = "Explosion", pitch = 0.45, stop = 1.15, fade = 0.3 },
				},
				whistleLead = 2.5,
			},
			zone = 17, -- 15 kg: lethal to ~9, hurt to ~17
			camera = { side = -15, up = 3, back = 13, ahead = 60, rise = 8, follow = 0.75, fov = 65 },
		} :: Gun,
	},
}

return table.freeze(Artillery)
