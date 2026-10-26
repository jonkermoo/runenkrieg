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
	-- the shell's own gravity, studs/s^2 (user 2026-10-21: "make the projectiles go slower (slow for cannon, way slower for
	-- howitzer)"): slower shells keep their ranges under a lighter pull (range = speed^2 sin 2e / gravity), so they hang
	-- in the air longer
	gravity: number,
	charge: number, -- seconds from the click to the shot (the brace; the howitzer's magic charge-up)
	breechOpens: boolean, -- the breech swings open through the reload (not the howitzer's: user 2026-10-21)
	kg: number, -- the shell's filling as TNT (Damage.blast)
	craterScale: number?, -- its crater's size against a charge's own (Rules/Blast.craterPlan; nil: 1)
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
	-- where the gunner stands (x, z): on the ground there, or `crewY` up on the gun itself (the server never poses the
	-- moving parts, so it can't cast onto them); `crewTurns`: on the mount, turning with its traverse (the howitzer's step)
	crew: { number },
	crewY: number?,
	crewTurns: boolean,
	prompt: number, -- reach of the E prompt, studs
	vfx: { scheme: string, magic: boolean },
	muzzleScale: number, -- the muzzle blast's scale (Config/Vfx.Muzzle)
	loads: boolean?, -- the gunner plays the loading (Load above)
	sound: { fire: any, far: any, blast: any, echo: any, whistle: any, whistleLead: number },
	zone: number, -- the impact zone's radius, studs (Zone above)
	-- the shell in flight (user 2026-10-21: "a very visual projectile"): a glowing ball `size` studs across in `color`
	-- (RGB), a trail `trail` s long fading to `tail`, a light `light` studs round; `magic`: static crackling round it in
	-- `static` (Palette.Magic)
	shell: {
		size: number,
		color: { number },
		tail: { number },
		trail: number,
		light: number,
		magic: boolean,
		static: string?,
		star: any?,
	},
	-- the gunner's camera (user 2026-10-20: "a cinematic lower left angle camera pov"): out at the gun's left, `side` (-
	-- left), `up` over the ground and `back` behind it along the aim, turned `yaw` degrees right of the aim (the gun and
	-- the gunner right of centre, the target left of it) and `pitch` up, plus the
	-- elevation x `follow` (a high lob stays in view)
	-- dug in when placed (src/server/Artillery); `ramp`: a way down into the pit behind the gun (Ground.pit); `wall`: the
	-- pit's walls lean back at this many degrees (nil: cut straight down); `slabs`: trench dirt slabs laid on them (Slabs)
	dig: {
		depth: number,
		radius: number,
		rim: number,
		rimHeight: number,
		ramp: { width: number, length: number }?,
		wall: number?,
		slabs: boolean?,
	}?,
	hp: number, -- what it takes to wreck it (Hits, Wreck)
	-- the shell leaves this many degrees over the bore, unseen (Rules/Artillery.muzzle); nil: along it
	aimTilt: number?,
	-- a flat pad round its base that counts as the gun for hits (Hits): `pad` studs out past its footprint, `thick` studs
	-- up from its foot; nil: the gun alone
	platform: { pad: number, thick: number }?,
	camera: { side: number, up: number, back: number, yaw: number, pitch: number, follow: number, fov: number },
}

local Artillery = {
	Folder = "Artillery", -- the Workspace folder the guns stand in
	PitFolder = "ArtilleryPits", -- and their pits' trench slabs
	-- the paint until teams exist (Config/Palette.Artillery.Paint)
	Paint = "Grey",

	-- Laying (user 2026-10-21: "can you make the cannon turn was wasd?"): A / D turn it, W / S raise and lower it, at the
	-- gun's own rates (traverse, swing, elevation): held, the aim leads the gun by `lead` degrees; let go, it stops where
	-- it is. What the gunner sends (Net "Artillery" "Aim"): at most `rate` a second.
	Aim = { rate = 10, lead = 2 },
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
	-- (the delay is each gun's `charge`; the brace starts so its pull, `pull` s into it, lands on the shot)
	Brace = { animation = 110111507484119 :: number?, pull = 0.45 },
	Turn = { crank = 80321147839061 :: number?, moving = 0.3, fade = 0.2 },

	-- The effects (src/client/ArtilleryFx; user 2026-10-21, see there). Colours are Config/Palette.Magic names, RGB lists
	-- where said. Shot: pressure waves along the bore (`wave` studs out, starting `ahead` past the muzzle) and a ring blown
	-- across the ground (`ground` studs, when the ground is within `groundReach`); Air: a see-through bubble swelling
	-- `size` studs over `time` s; Shake: the shot kicks the camera `shot` degrees within `reach` studs (x the gun's
	-- muzzleScale; its blast shakes as every explosion, Config/CameraShake); Static: the magic shell's bolts every
	-- `every` s, `reach` x its size long, living `life` s; Charge: the howitzer's charge-up (layered circles, below;
	-- bolts crystal -> muzzle every `boltEvery` s from start to end; the hum rising in volume and pitch); Blast: the magic blast's `bolts` leaping out over `spread` s, an aura for
	-- `aura` s.
	Fx = {
		Shot = { color = "Core", wave = 26, ahead = 2, ground = 30, groundReach = 9 },
		Air = { size = 14, time = 0.35, transparency = { 0.75, 1 }, color = { 235, 235, 230 } },
		Shake = { shot = 1.6, reach = 60 },
		Static = { every = 0.07, reach = 2.2, life = 0.09 },
		Charge = {
			color = "Glow",
			-- the layered circles, stacked out from the muzzle (user 2026-10-21: "multi layer ... way way WAY bigger"): each
			-- opens at `at` of the charge over `appear` s (the last one assembling), `ahead` studs out, `diameter` across,
			-- `orbits` curves round it; on the shot they crumble outermost first, `closeEach` s apart
			layers = {
				{ at = 0, ahead = 3, diameter = 16, appear = 0.3, orbits = 2 },
				{ at = 0.3, ahead = 11, diameter = 30, appear = 0.35, orbits = 3 },
				{ at = 0.55, ahead = 22, diameter = 48, appear = 0.6, orbits = 4, assemble = true },
			},
			closeEach = 0.08,
			rimEvery = { 0.3, 0.06 }, -- lightning between the first and last rims, every this many s (start, end)
			boltEvery = { 0.35, 0.08 },
			boltLife = 0.12,
			hum = { id = 9113126091, volume = 1, loop = true, profile = "Hum", eq = { 3, 0, -10 } },
			humVolume = 1.4,
			humPitch = { 0.55, 1.1 },
			open = { { id = 9116427399, volume = 1.2, pitch = 0.7, fade = 2, profile = "Spell", eq = { 3, 0, -12 } } },
		},
		Blast = { color = "Glow", bolts = 10, spread = 0.5, life = 0.18, aura = 1.4 },
		-- smoke curling up out of the barrel after the shot (user 2026-10-21: "make smoke come out of the cannons
		-- (both)"): `rate` puffs a second thinning to none over `time` s, out of the muzzle at `speed` (x the gun's
		-- muzzleScale), rising `rise` studs/s^2, growing `size` (x the scale), `thick` at its thickest (Palette.Magic)
		-- (Studio round 15: at rate 9, thick 0.45 it read faint against the sky)
		Smoke = {
			time = 8,
			rate = 16,
			speed = { 1.5, 4 },
			life = { 3, 5 },
			spread = 18,
			drag = 0.6,
			rise = 2.5,
			wind = { 0.8, 0, 0.4 },
			size = { 0.9, 4.5 },
			thick = 0.2,
			color = "Ash",
		},
	},

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

	-- The howitzer's crystal (src/client/ArtilleryCrystal, Rules/Artillery.crystal; user 2026-10-20: "make the howitzer
	-- loading just a empty colored crystal and the color slowly returns (make it look nice, like its coming back to
	-- life)", "give the crystal more design and effects. some runes on it works too"). RGB colours: `empty` drained,
	-- `ready` full, `fired` white-hot. The flare: `flareGlow` draining over `flare` s. Charging: the glow rises as the
	-- share ^ `curve`, sputters below `sputter`, heartbeats at `beat` (a second, start to end) adding `beatGlow`; full,
	-- it blooms `awakeGlow` over `awake` s, then breathes by `breath` at `pulse` rad/s. The barrel's and bed's runes
	-- (`alsoRunes`) dim and come back with it, never below `runesFloor`. `light`: a point light in it, `range` /
	-- `brightness` at full glow.
	-- Round it: `runes` Elder Futhark runes (Config/Runes strokes) circling level round the crystal, `orbit` studs out,
	-- `size` studs tall, `spin` deg/s, `bob` studs up and down; they scatter `scatter` studs and fade on the shot, stay
	-- dark through the reload (user 2026-10-21: "die when it's reloading") and come back when it's full, whirling faster as
	-- it charges to fire (`surge.spin`: "spin ... faster when its about to fire"). Motes of light drawn into it while it
	-- charges: up to `motes` a second, from `moteFrom` studs, `moteSize` studs.
	Crystal = {
		empty = { 20, 26, 40 },
		ready = { 70, 150, 255 },
		fired = { 225, 245, 255 },
		flare = 0.6,
		flareGlow = 1.6,
		curve = 1.6,
		sputter = 0, -- (the sputter is random now: `flicker`)
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
		orbit = 2.9, -- (round the bigger gem)
		size = 0.9,
		spin = 25,
		bob = 0.15,
		scatter = 2.5,
		stroke = 0.12, -- a stroke's width, of the rune's height
		motes = 14,
		moteFrom = 3,
		moteSize = 0.18,
		-- charging up for the shot: up to `glow` brighter, the runes `spin` x faster, drawn in by `tighten`
		surge = { glow = 0.7, spin = 12, tighten = 0.35 },
		-- a random flicker (user 2026-10-21: "make the flicker random"), like a failing light: drop-outs at `rate` a
		-- second (charging: from the first to the second as it fills; ready: the third), each `length` s long and
		-- `depth` deep, and a slow uneven wobble of `wobble`
		flicker = { rate = { 5, 0.8, 0.3 }, length = { 0.04, 0.2 }, depth = { 0.35, 0.9 }, wobble = 0.1 },
		-- the cracks (its "CrystalCracks" part) burn brighter than the gem by `cracks` of a glow, never darker than empty
		cracks = 0.45,
	},

	-- Sounds (Pro Sound Effects, licensed through Roblox; ASSETS_LICENSES.md), per gun below (the blasts each fade over
	-- their last `fade` seconds, so their tails die away; user 2026-10-21: "the explosion audio cuts out"): `fire` its report up
	-- close, `far` heard past `FarFrom` studs instead, `blast` the shell going off; the incoming shell's `whistle` is
	-- heard within `Whistle.reach` studs of where it lands, starting the gun's `whistleLead` s before it lands (only on a
	-- flight at least that long: a short one comes in under the report; Studio round 2). All late and
	-- duller far off (Rules/Grenade.heard).
	Whistle = { reach = 300 },
	-- a blast's echo (each gun's `sound.echo`): silent within `from` studs, rising to full at `full`, a little after the
	-- blast itself (`lag` s)
	Echo = { from = 120, full = 450, lag = 0.25 },
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

	-- What hits do to the guns themselves (src/server/Artillery, Rules/Artillery.gunHit; user 2026-10-25: "the hotbox
	-- should be similar, direct hits more, surround areas (the mound / nearby terrain) should do less"; "a direct cannon
	-- hit or two should destroy a field gun. it should take 4+ DIRECT cannon shots to destroy the howitzer"): HP off a
	-- gun's `hp` by what went off. A blast within `direct` studs of the gun's box is a direct hit and takes `direct`; past
	-- that (its pit, its mound, the ground round it) it takes `near` at most, fading to nothing at `reach`. Bullets do
	-- nothing. A blast nobody named (DEV tools) by its charge: the first of `byCharge` it is no bigger than (as
	-- Config/Build.Structures).
	Hits = {
		direct = 1.5,
		grenade = { direct = 8, near = 1, reach = 6 },
		staff1 = { direct = 1, near = 0, reach = 3 },
		staff2 = { direct = 3, near = 0.5, reach = 5 },
		staff3 = { direct = 10, near = 2, reach = 10 },
		field = { direct = 60, near = 8, reach = 12 }, -- (a field gun: two; the howitzer: four)
		howitzer = { direct = 150, near = 25, reach = 30 }, -- (a field gun at once; the howitzer: two)
		byCharge = {
			{ kg = 0.5, source = "grenade" },
			{ kg = 5, source = "field" },
			{ kg = math.huge, source = "howitzer" },
		},
	},
	-- A damaged gun (user 2026-10-25: "once it gets to a critical percentage (let's say 50%) it becomes unusable, but not
	-- completely wrecked. make it 4 stages, each at 25%, each more damaged"): stage i once its HP is down to `at[i]`% of
	-- full; from stage `unusable` nobody can man it (its gunner is thrown off), its barrel knocked down to its lowest lay
	-- and up to `knock` degrees round, the howitzer's crystal dead. Each stage scorches it `scorch[i]` of the way to
	-- Palette.Artillery.Scorched, leans it `tilt[i]` degrees and sinks it `sink[i]` studs.
	Wreck = {
		at = { 75, 50, 25, 0 },
		unusable = 2,
		knock = 12,
		scorch = { 0.25, 0.45, 0.65, 0.85 },
		tilt = { 0, 1.5, 4, 9 },
		sink = { 0, 0, 0.3, 0.7 },
	},
	-- The trench dirt slabs on a dug-in gun's pit (`dig.slabs`; Config/Assets trench_pieces, as a trench's walls; user
	-- 2026-10-25: "add the described trench style on it", "still pretty messy and disorganized"): rough slabs round the
	-- pit's wall in `rows` uneven rows, each slab `turn` of the way round (radians, a range), `height` studs up its slope
	-- (a range), its rows `rowStep` apart, leaning off true by up to `jitter` (radians: yaw, roll), shifted by up to
	-- `shift` studs, `extra` studs longer than its share (a range); `gap` of them left out; `parapet` of the top row with
	-- a heap of dirt behind it. The ramp's sides get slabs where they stand `rampMin` high or more (`rampLength` long, a
	-- range, at most `rampHeight` high); the floor a few loose floor pieces, `floorGap` of a grid left out. The slabs'
	-- variants (Wall1..8, some with planks) are rolled from `walls`.
	Slabs = {
		rows = 2,
		turn = { 0.3, 0.45 },
		height = { 5.2, 6.5 },
		rowStep = 5,
		jitter = { 0.12, 0.08 },
		shift = 0.8,
		extra = { 1, 3 },
		gap = 0.2,
		parapet = 0.55,
		mouth = 0.42, -- radians either side of the ramp left open
		walls = { 1, 2, 3, 4, 1, 2, 3, 4, 5, 7 },
		rampMin = 2,
		rampLength = { 6, 9 },
		rampHeight = 7,
		rampGap = 0.25,
		floorGrid = 4,
		floorStep = 7.4,
		floorGap = 0.35,
		floorTurn = 0.25,
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
			speed = 450,
			gravity = 71.6, -- (745 studs/s under 196.2 before: the same ranges, ~1.7x the flight: up to ~3.5 s)
			charge = 0.45,
			breechOpens = true,
			-- (user 2026-10-21: "the explosives to be a lot more damaging and destructive ... realistic"; was 0.6 kg,
			-- fragments lethal 6 / wound 30): a shell's lethality is mostly its fragments: a real 18-pdr HE burst kills
			-- out to ~10 m and wounds to ~25-30 m, and its charge as TNT here is raised to 2.5 kg so it breaks walls
			kg = 2.5,
			fragments = { lethal = 12, wound = 40, max = 100, near = 70, far = 15 },
			scatter = { yaw = 0.8, elevation = 0.25, speed = 0.012 },
			reload = 10,
			breechOpen = 100,
			breechTimes = { 1.2, 1 },
			recoil = 3.34,
			recoilTimes = { 0.08, 1.2 },
			recoilClear = nil,
			hp = 100,
			-- (user 2026-10-26: "angles it slightly (not visibly at all) up, since it will be a mid range weapon (only can
			-- hit enemy sectors)"; picked: the shortest shot ~300 studs, one sector): +8 on every shot, so -5..16 on the
			-- dial throws 3..24: ~300 to ~2,100 studs
			aimTilt = 8,
			-- (user 2026-10-26: "add a platform hitbox for the cannon"; picked: the ground it stands on counts as the gun)
			platform = { pad = 3, thick = 1.5 },
			crew = { -1.6, 3.4 }, -- left of the breech, behind it (the loading reaches it), clear of the trail
			crewTurns = false,
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
				-- dry, heard at every distance (user 2026-10-21: the echo "sounds distorted at the end and it echoes even
				-- when you're close ... it should echo only when you're far": the flanged Explosive Boom tail is gone)
				blast = {
					{ id = 9114362266, volume = 1.4, profile = "Explosion", fade = 1.5 }, -- Explosions 4
					{ id = 9114086964, volume = 1, profile = "Explosion", fade = 1.5 }, -- Dirt Explosion 2
					{ id = 9116973611, volume = 1, profile = "Explosion" }, -- Mortar Explosion 3: a short low thump
				},
				-- the echo rolling back off the land, only far off (Echo below)
				echo = { { id = 9113169432, volume = 1.3, profile = "Explosion", fade = 2.5 } }, -- Artillery Distant 2
				-- Bullet Whiz By 1 (lengthened), slowed into a shell's rushing whine
				whistle = {
					{ id = 9113634642, volume = 0.9, profile = "Explosion", pitch = 0.6, stop = 0.75, fade = 0.2 },
				},
				whistleLead = 1.2, -- (its flights are ~0.5-2 s)
			},
			zone = 16, -- lethal fragments to 12, the blast hurting to ~10
			-- a hot slug trailing grey smoke
			shell = {
				size = 0.7,
				color = { 255, 196, 120 },
				tail = { 120, 118, 112 },
				trail = 0.6,
				light = 10,
				magic = false,
			},
			-- (Studio rounds 5-8: low in the grass, or from behind with the gunner in the middle; worked out from the angles:
			-- the gun ~25-40 deg right of centre, the gunner ~50, the target ~-30)
			-- (user 2026-10-21: "closer but from a similar angle we want to be able to see our avatar")
			-- (user 2026-10-21: "a little closer to the player"; was side -8, up 4.5, back 9)
			-- (user 2026-10-22: "have the cannon further back and up more"; was up 4, back 7)
			camera = { side = -6.5, up = 5.5, back = 10, yaw = 25, pitch = 2, follow = 0.4, fov = 60 },
		} :: Gun,
		-- The magic howitzer v6 (user 2026-10-21: "look like the big bertha", "no tires ... the turning being controlled by
		-- giant gears"; tools/blender/artillery/bertha.py, approved v10): a 42 cm siege mortar, its riveted box carriage
		-- turning all the way round on a giant ring gear, the barrel trunnioned high between its walls. A short-arc mortar
		-- (user: "make the howitzer more of a short arc mortar weapon"): it only lobs, 45..80 degrees, 160 studs/s under
		-- its own lighter gravity: ~590 studs at 45 down to ~200 at 80, 5-7 s in the air. Its recoil is cut short at
		-- high elevation so the gem under the breech clears the turntable (~1 at 80). Dug in when placed (`dig`).
		artillery_howitzer = {
			asset = "artillery_howitzer",
			name = "Magic howitzer",
			base = "Bed",
			mount = { "Mount" },
			cradle = { "Cradle" },
			barrel = { "Barrel", "BarrelRunes", "Bore" },
			breech = { "Breech", "Crystal", "CrystalCracks" },
			trunnion = { 0, 7.4, 0.5 },
			hinge = { 0, 7.4, 3.1 }, -- (the breech never opens)
			muzzle = { 0, 7.4, -10.6 },
			boreCentre = 0.123,
			traverse = 180, -- right round on its ring gear
			elevation = { 45, 80 },
			swing = 3,
			traverseRate = 5,
			elevationRate = 5,
			speed = 160,
			gravity = 43.5, -- (340 under 196.2 before: the same ranges, ~2.1x the flight: 5.2 s at 45, 7.2 at 80)
			charge = 1.8, -- its magic charge-up (user 2026-10-21: "make the howitzer have a cinematic magic charge up")
			breechOpens = false, -- (user 2026-10-21: "remove the close and opening on the howitzer, leave it closed")
			-- (user 2026-10-21: "significantly more damage (close to the 50kg bomb)"; was 15 kg, no fragments): 50 kg,
			-- like the dev blast menu's 50 kg bomb (lethal by blast to ~14 studs, a crater ~34 across), and a 42 cm
			-- shell's fragments flying far
			-- (user 2026-10-22: "a direct hit from the howitzer should destroy an entire house and some of its
			-- surroundings"): every wall, roof and door class fails at 1,000 kPa (Damage.Blast.Fail, stone 1,200), which a
			-- charge reaches out to ~0.95 x kg^(1/3) studs. A shell on the ridge of a village cottage (up to 24 x 21, one
			-- 12-stud story, the ridge ~16 up) has its farthest ground-floor wall sections ~19 studs off: 400 kg breaks walls
			-- to ~20.7 (stone ~19), so the whole house comes down; round it trees fall to ~72, glass breaks to ~128, a
			-- crater ~68 across, soldiers die to ~27 by blast and are hurt to ~51 (was 50 kg: walls to ~10, a hole in one
			-- side; Studio round 1 at 250 kg: walls to ~17.7 took 19 of a cottage's 38 sections, a wall stood)
			-- (user 2026-10-22: "lower how big the explosion is a tiny bit"; was 400 kg): 340 kg, every reach x0.95 (the
			-- cube root): walls to ~19.6 (stone ~18), trees to ~68, glass to ~121, a crater ~64 across, soldiers die to
			-- ~26 by blast and are hurt to ~48
			kg = 340,
			-- (user 2026-10-23: "lower the crater of the howitzer cannon even more? a few shots from multiple people could
			-- clear out an entire section"; was ~65 across, ~9.7 deep): half the hole, ~32 across and ~5 deep; its damage,
			-- reach, mud and broken buildings stay the 340 kg blast's
			craterScale = 0.5,
			fragments = { lethal = 18, wound = 60, max = 100, near = 80, far = 20 },
			scatter = { yaw = 0.9, elevation = 0.35, speed = 0.015 },
			reload = 30,
			breechOpen = 100,
			breechTimes = { 2, 2 },
			recoil = 2.5,
			recoilTimes = { 0.12, 2 },
			recoilClear = { floor = 1.9, along = 4.58, below = 0 }, -- the gem's point over the turntable (1.6)
			-- on the step on the carriage's left wall by the hand wheels (user 2026-10-21: "a small platform you stand on the
			-- side of the cannon to arm it and control it"; bertha.py STEP)
			crew = { -4.45, 1.4 },
			crewY = 3.2, -- the step's top
			crewTurns = true,
			prompt = 12,
			-- dug in when placed (user 2026-10-21: "slightly underground to give it cover ... naturally destroy the terrain";
			-- "Pit to the axle"): a pit `radius` round it `depth` deep, an earth rim `rim` wide and `rimHeight` high round that
			-- (Studio round 13c: the level floor must reach past the bed's corners, ~10.2 out, so the pit reaches a voxel
			-- further; a rim narrower than two voxels never formed)
			-- (13d-e: the voxel columns along an axis sit 10.2 and 14.14 out, so a pit under 14.2 stops at the first and the
			-- bed's corners ~10.2 out end up in its wall; at 2.8 the rim stands ~1.6)
			-- (user 2026-10-22: "have the howitzer really dug down. only the barrel should really be exposed"; was 1.5): the
			-- carriage walls' crowns stand 9.3 over the bed's underside (bertha.py) and the cradle round the barrel rose to
			-- 15.3 at 45 degrees (Studio round 1 at 9.5 deep: 3.3 over the ground), so at 12 only the barrel rises out of the
			-- ground, and the rim covers the rest; a ramp `width` wide climbs out behind the gun over `length` studs (~20
			-- degrees; at least two voxels wide, as the rim)
			-- (user 2026-10-22: "lift the mortal ... formed on a hill (mortal should not be as deep but have same cover)"; was
			-- depth 12, rim 9, rimHeight 2.8): half as deep, on a mound of earth thrown up round it, so the cover stands as
			-- high over the bed as before (14.8)
			-- (user 2026-10-25: "push the howitzer down so there isnt as big of a mound. the mound should be player height or
			-- less. then add the described trench style on it"; "a ramp that slowly goes to floor level"; was depth 6,
			-- rimHeight 8.8, ramp 33 long, walls cut straight down): 10.5 deep under a 4.5 mound, the same cover over the
			-- bed (15); the walls leaning back at a trench's 59 degrees with rough trench slabs on them (Slabs), the floor
			-- still 15 round; the ramp 40 long (~15 degrees)
			dig = {
				depth = 10.5,
				radius = 15,
				rim = 14,
				rimHeight = 4.5,
				ramp = { width = 10, length = 40 },
				wall = 59,
				slabs = true,
			},
			hp = 240,
			vfx = { scheme = "Arcane", magic = true },
			muzzleScale = 2.2,
			sound = {
				fire = {
					{ id = 9119382515, volume = 1.5, profile = "Explosion" }, -- Sonic Boom 2: a huge single boom
					{ id = 9116973607, volume = 1.2, profile = "Explosion" }, -- Mortar Explosion 5
				},
				far = { { id = 9113169264, volume = 1.4, profile = "Explosion" } }, -- Artillery Distant 1
				blast = {
					{ id = 9114362135, volume = 1.5, profile = "Explosion", fade = 1.5 }, -- Explosions 1: rumbling, punchy
					{ id = 9114086964, volume = 1.2, profile = "Explosion", fade = 1.5 }, -- Dirt Explosion 2
					{ id = 9116973607, volume = 1.3, profile = "Explosion" }, -- Mortar Explosion 5: a deep low thump
				},
				echo = { { id = 9113169264, volume = 1.5, profile = "Explosion", fade = 3 } }, -- Artillery Distant 1
				whistle = {
					{ id = 9113634642, volume = 1, profile = "Explosion", pitch = 0.45, stop = 1.15, fade = 0.3 },
				},
				whistleLead = 2.5,
			},
			zone = 48, -- 340 kg: lethal by blast to ~26, the blast hurting to ~48 (400 kg: 27 and 51)
			-- a bright four-point star (user 2026-10-21: "a bright 4 point star"): a white-hot core, the spikes (below), a
			-- strong light; a blue trail of light and static crackling round it
			shell = {
				size = 2.4,
				color = { 235, 250, 255 },
				tail = { 90, 170, 255 },
				trail = 1.4,
				light = 40,
				magic = true,
				static = "Glow",
				-- the anime four-point sparkle: four long tapered spikes `long` studs out, `width` wide at the core; four short
				-- faint ones `diag` out between them; a soft `halo` ball; `twinkle` the flutter, `spin` deg/s
				star = {
					long = 11,
					width = 1.3,
					diag = 3.5,
					diagWidth = 0.5,
					diagFade = 0.45,
					halo = 4.5,
					haloFade = 0.75,
					twinkle = 0.18,
					spin = 15,
					beamBrightness = 8,
					brightness = 6,
					color = { 225, 245, 255 },
				},
			},
			-- (Studio round 10: at pitch 8 + 0.3 x elevation the landing fell out of the bottom of the frame at 80)
			-- (dug 12 down; was side -16, up 8, back 18, pitch 6: that put it inside the ground round the pit, and from up
			-- over the ground, Studio round 2, the rim hid the gunner, who stands >30 degrees under any line over it): down
			-- in the pit behind the gunner's left, 2 under the ground, the gunner ~22 degrees under it; the landing marker is
			-- drawn over the pit's wall (AlwaysOnTop)
			-- (user 2026-10-22: "angle the camera way up more? our avatar should look pretty small. we also cant see where
			-- we are aiming"; was side -10, up 10, back 9, pitch -6, fov 65): high up behind it, over the mound, looking
			-- down into the pit: the gunner ~42 degrees under the camera, the landing 0-6 under the horizon at every lay, so
			-- a steady pitch between them keeps both in view (Studio round 1 at pitch -8 + 0.12 x elevation: the mound's
			-- near side filled the bottom of the frame and the gunner was under it)
			-- (dug 10.5 down, was 6: `up` 4.5 higher, so it stands as high over the ground as before; was 24)
			camera = { side = -12, up = 28.5, back = 20, yaw = 25, pitch = -21, follow = 0, fov = 70 },
		} :: Gun,
	},
}

return table.freeze(Artillery)
