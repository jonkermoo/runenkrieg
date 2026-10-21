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
	camera: { back: number, up: number, pitch: number, follow: number, fov: number },
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
		width = 0.5,
		segments = 60,
		transparency = 0.35,
		marker = 46, -- the ring's size in pixels, its line `ring` thick, the range's text `text` high
		ring = 3,
		text = 18,
	},

	-- The reload bar (bottom centre while manning; Palette.UI)
	Bar = { width = 220, height = 12, margin = 90, text = 16 },

	-- The howitzer's crystal by state (Rules/Artillery.crystal): just fired it flares, then dims and fills back up while
	-- charging, ready it pulses. RGB.
	Crystal = {
		fired = { 235, 250, 255 },
		empty = { 30, 50, 80 },
		ready = { 90, 170, 255 },
		flare = 0.6, -- seconds of the flare
		pulse = 2, -- the ready pulse's speed (radians/s)
		pulseShare = 0.25,
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
	Load = { animation = 77988505499096 :: number?, lead = 3.45, take = 0.5, loaded = 2.1, round = "round_qf18" },

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
			camera = { back = 16, up = 7, pitch = -6, follow = 0.4, fov = 60 },
		} :: Gun,
		-- The magic howitzer (A1, BL 9.2-inch at 1.3x): traverse 30 about the racer, elevation 0..55, recoil 40 in (1.3x),
		-- cut short at high elevation (the breech would reach the platform: top 3.36, the breech block's low back corner
		-- 4.05 behind the trunnion and 1.54 under it). 657 studs/s: ~2,200 at 45 degrees, ~5 s in the air.
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
			elevation = { 0, 55 },
			swing = 3,
			traverseRate = 5,
			elevationRate = 5,
			speed = 657,
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
			camera = { back = 30, up = 14, pitch = -8, follow = 0.4, fov = 60 },
		} :: Gun,
	},
}

return table.freeze(Artillery)
