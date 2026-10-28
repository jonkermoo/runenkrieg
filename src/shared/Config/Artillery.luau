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
	hp: number, -- what it takes to wreck it (Hits, Wreck): 100, like every structure (Config/Build.Guns)
	-- what blasts take off it is divided by this (Hits; nil: 1): the howitzer's 240 HP on the 100 scale (user
	-- 2026-10-27: "change all building to be HP out of 100 ... use the appropriate math"), as many hits as before
	armour: number?,
	-- shovel swings (Build mode, any team's) that fix it from a wreck to whole (Repair)
	repair: number,
	-- the shell leaves this many degrees over the bore, unseen (Rules/Artillery.muzzle); nil: along it
	aimTilt: number?,
	-- a flat pad round its base that counts as the gun for hits (Hits): `pad` studs out past its footprint, `thick` studs
	-- up from its foot; nil: the gun alone
	platform: { pad: number, thick: number }?,
	-- stands on the terrain itself, no earth block (Ground below): the ground under its footprint, `pad` studs out past
	-- it, levelled to its foot and turned to `material` (no grass), easing back to the ground as it was over the next
	-- `blend` studs; an unseen box over its `platform` from `Ground.depth` under its foot is its hitbox
	level: { pad: number, blend: number, material: string }?,
	-- the parts shell holes are punched into as it is damaged (Wreck), and the holes' size range (studs)
	wreckParts: { string },
	holeSize: { number },
	camera: { side: number, up: number, back: number, yaw: number, pitch: number, follow: number, fov: number },
	-- set up in an MG nest (Config/Build.Nest) instead of on its own (its building site in the nest's ring), and it fires
	-- bullets, not shells; nil: an artillery piece
	nest: boolean?,
	-- a nest gun's own ground kept from craters (Artillery.onGround): x, z from its pivot, lo and hi (it stands on its
	-- nest's mount bag, no earth under it)
	nestGround: { lo: { number }, hi: { number } }?,
	-- a machine gun's own firing (the MG nest's; src/server/Artillery, src/client/Artillery, Rules/Artillery mg*): held
	-- fire at `rate` rounds a minute from a box of `box` (the gun's `reload` swaps it, on the reload key or once it is
	-- empty), each a bullet out to `range` studs hurting as Config/Damage.Weapons[`class`]; it strays `spread.min`
	-- degrees, growing `spread.per` of the way to `spread.max` a shot and settling back at `spread.recover` of it a
	-- second; aimed, the gunner looks from `eye` (gun space, through the rear sight, turning and lifting with the
	-- gun; else the rifle's camera, Config/Camera.Gun), the mouse laying it `look` degrees a pixel; `shot` its report
	-- (Config/Audio profile Gunshot)
	mg: {
		rate: number,
		box: number,
		range: number,
		class: string,
		spread: { min: number, max: number, per: number, recover: number },
		stand: number,
		eye: { number },
		over: { number },
		shield: { top: number, z: number },
		shoulder: { number },
		look: number,
		shot: any,
	}?,
	-- part names coloured so instead of by Palette.Artillery (the MG's gunmetal body and its belt); nil: none
	colors: { [string]: { number } }?,
	-- built with the shovel (Assembly below): the model's parts in groups (`names`: every mesh whose name starts with
	-- one), each appearing in place once quarter `at` of the work is done (0: from the start; 4: with the gun standing)
	assembly: { { names: { string }, at: number } },
	-- gears turning as it is laid (src/client/Artillery; user 2026-10-26: "animate the gears turning as well when we
	-- rotate the gun left and right. make sure its accurate and biting each teeth accurately"): `part` (one of its
	-- `mount`) spins about gun-space `axis` ("X", "Y" or "Z") through `centre`, `ratio` degrees per degree of its
	-- `by` ("traverse" or "elevation"): the tooth ratio of the pair it meshes (tools/blender/artillery/bertha.py
	-- prints them); nil: none
	gears: { { part: string, centre: { number }, axis: string, by: string, ratio: number } }?,
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
		marker = 46, -- the range label's box (pixels), its text `text` high (no ring: user 2026-10-26)
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
		Shake = { shot = 2.2, reach = 70 },
		-- The shot in beats (user 2026-10-26: "improve the cannon firing animations. give it more effect, make it super
		-- 'visual' and appealing"; approved as a design preview, with the FOV punch and only sounds already in the
		-- game). The muzzle's own beats are Config/Vfx.Muzzle (its look: Magic for a magic gun, else Field). Past `far`
		-- studs from the camera a shot draws only its flash, fireball, glint and jet.
		-- Punch: the gunner's view widens `fov` degrees (x the square root of the gun's muzzleScale) and eases back
		-- over `time` s.
		-- Jolt: the whole gun kicks `back` studs and its nose `lift` degrees, `rise` s in, then settles in a wobble at
		-- `wobble` rad/s dying away at `damp` a second, done after `time` s (client only, the models untouched).
		-- Bank: the smoke hanging in front after the shot: from `at` s for `time` s, `rate` puffs a second out of a box
		-- `width` studs wide `ahead` studs in front at the ground (x the scale), `speed` studs/s, rising `rise`, drifting
		-- on the `wind`, growing `size`, `thick` at its thickest; the magic gun's has `sparkle` (motes of its colour
		-- twinkling in it, `rate` a second).
		-- Corkscrew: the field shell's smoke spiralling off it for its first `time` s, `radius` studs round the path at
		-- `turns` a second, `rate` puffs a second; `sparks` sparks shed off it a second.
		-- Sound: layers after the report, each `at` s after the shot (the recoil's clank on its buffer, the dirt
		-- pattering down; `runout` as the barrel runs home, at the end of the gun's recoil).
		far = 300,
		Punch = { fov = 4, time = 0.2 },
		Jolt = {
			Field = { back = 0.35, lift = 1.5, rise = 0.04, wobble = 28, damp = 9, time = 0.6 },
			Magic = { back = 0.15, lift = 0.35, rise = 0.06, wobble = 22, damp = 7, time = 0.8 },
			-- a machine gun's (user 2026-10-27: "realistic recoil and spread, with no fight between full auto and the
			-- camera shake"; was the field gun's, 0.35 back and 1.5 up restarting 7 times a second): a heavy gun on its
			-- sled barely moves, a short buzz settled before the next shot (Guns `mg.rate`)
			MG = { back = 0.03, lift = 0.25, rise = 0.015, wobble = 45, damp = 30, time = 0.12 },
		},
		Bank = {
			at = 0.25,
			time = 1.5,
			rate = 6,
			width = 14,
			ahead = 10,
			speed = { 0.5, 2 },
			life = { 4, 6 },
			rise = 0.4,
			wind = { 1.2, 0, 0.6 },
			size = { 5, 13 },
			thick = 0.55,
			color = "Ash",
			sparkle = { rate = 14, life = { 0.8, 1.6 }, size = 0.3, color = "Glow" },
		},
		Corkscrew = {
			time = 0.6,
			radius = 0.5,
			turns = 6,
			rate = 50,
			life = { 0.6, 1 },
			size = { 0.5, 2 },
			thick = 0.4,
			color = "Ash",
			sparks = 40,
		},
		Sound = {
			Field = {
				-- Locking Wrench 7, slowed: the recoil hitting its buffer, then the barrel running home
				{ at = 0.03, sound = { id = 9116321026, volume = 1.3, pitch = 0.45, profile = "Mechanism" } },
				-- Rock Impact Dirt Hard Muted Thuds 2: the dirt thrown up pattering down
				{ at = 0.3, sound = { id = 9118616398, volume = 0.7, profile = "Thunk" } },
			},
			Magic = {
				{ at = 0.04, sound = { id = 9116321026, volume = 1.5, pitch = 0.3, profile = "Mechanism" } },
				{ at = 0.3, sound = { id = 9118616398, volume = 0.8, profile = "Thunk" } },
				-- the staff's spell swell, slowed: the magic ringing on after the shot
				{
					at = 0,
					sound = {
						id = 9116427220,
						volume = 1,
						pitch = 0.6,
						fade = 1.5,
						profile = "Spell",
						eq = { 2, 0, -12 },
					},
				},
			},
			runout = {
				Field = { id = 9116321026, volume = 0.8, pitch = 0.6, profile = "Mechanism" },
				Magic = { id = 9116321026, volume = 1, pitch = 0.4, profile = "Mechanism" },
			},
		},
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
	-- `lift` off the surface (always level: user 2026-10-26, "make it flat at all times"); a core `coreShare` of it
	-- across pulsing between the `core` transparencies at `pulse` rad/s.
	Zone = {
		fill = 0.72,
		core = { 0.45, 0.8 },
		coreShare = 0.35,
		thickness = 0.15,
		lift = 0.1,
		pulse = 5,
	},

	-- Building a gun with the shovel (src/server/Build, src/server/Artillery.assemble; user 2026-10-26: "the artillery
	-- will look broken down when first placed and assembled slowly in quarters phases", "you can just make parts start
	-- appearing out of no where throughout phases"): only some of its parts stand when it is laid out, the rest appear
	-- a group at a time as the work passes each quarter (each gun's `assembly`), the gun standing whole at full work.
	-- The parts can't be touched, stood on or shot; the barrel sits at the gun's lowest lay.
	Assembly = { quarters = 4 },

	-- The earth a gun stands on, part of the gun (user 2026-10-26: "the ground below the howitzer can be destroyed ...
	-- make sure its part of the model so it has a hitbox. same applies for the field cannon"): a block of earth under
	-- its footprint, `pad` studs out past it, from the ground it stands on down `depth` studs, in Palette.Terrain
	-- `color`; when blasts carve the terrain away round and under it, the gun still stands on it, and it counts as the
	-- gun for hits (its box). A gun with `level` (the field gun) stands on the terrain instead, its hitbox unseen.
	Ground = { pad = 0.5, depth = 5, color = "Mud" },

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
		alsoRunes = { "BarrelRunes" }, -- (the bed's runes are gone: user 2026-10-26)
		-- the orbiting runes' strokes (user 2026-10-26: "more ... curve. it looks too blocky"; their halos taken off
		-- again: "it makes the runes indecipherable"): each bows `bow` of its length off true (alternate strokes the
		-- other way) in `pieces` rounded pieces, swelling to `swell` x the stroke in its middle, `tip` x at its ends
		strokes = { bow = 0.1, pieces = 3, swell = 1.2, tip = 0.55 },
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
		-- dying (user 2026-10-26: "make the lights flicker more deathly when its low HP"): hurt past `from` of its HP,
		-- the drop-outs come up to `rate` more a second, `depth` deep (from the second up to the first); knocked out
		-- (Wreck.unusable) it no longer charges or fires but sputters on, holding at `glow` and black for `blackout` of
		-- the time, now and then a weak flare of `flare` lasting `flareLength` s (`flareEvery` s apart on average), the
		-- light toward `tint` (RGB); at Wreck.dark it dies
		dying = {
			from = 0.2,
			rate = 7,
			depth = { 1, 0.5 },
			glow = 0.35,
			blackout = 0.55,
			flare = 0.9,
			flareLength = 0.1,
			flareEvery = 1.6,
			tint = { 150, 70, 110 },
		},
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
		-- (staffs since 2026-10-27, as Config/Build.Structures: user "staff beams should do a lot more damage to built
		-- structures overall": 6 direct full beams wreck a field gun, 14 the howitzer)
		staff1 = { direct = 2, near = 0, reach = 3 },
		staff2 = { direct = 6, near = 1, reach = 5 },
		staff3 = { direct = 18, near = 4, reach = 10 },
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
	-- Physically damaged too (user 2026-10-26: "make the physical model look damaged throughout each phase too? along
	-- with the darkening. make the lights flicker more deathly when its low HP"): by stage i it has `holes[i]` shell
	-- holes punched into its `wreckParts` (each gun's: torn holes of its `holeSize`, `petals` metal flaps bent out round
	-- each), and the accent pieces of the roles in `lose[i]` (Palette.Artillery.Roles) are blown off, tumbling away as
	-- debris for `debris.life` s; its glow sputters on (src/client/ArtilleryCrystal, Crystal.dying) until stage `dark`,
	-- when it dies.
	-- Fixing a gun with the shovel (src/server/Build, Artillery.repair; user 2026-10-27: "make it so you can fix a
	-- artillery by digging too", "enemie teams should be able to repair and fix enemie trenches and artillery, as they
	-- should be able to use it if they earn the sector"): a Build swing by any team's soldier gives back the gun's `hp` /
	-- `repair` (an admin dig step: that share of its full HP). An unusable gun is usable again from `usable`% ("the
	-- artillery should be in a damaged but usable status at 75%"): a fresh gun stands in its place, damaged to the HP it
	-- has; whole, a fresh gun again. Each time its ground is flattened out again (the howitzer's pit dug out again).
	Repair = { usable = 75 },
	Wreck = {
		at = { 75, 50, 25, 0 },
		unusable = 2,
		dark = 4,
		holes = { 2, 5, 9, 14 },
		lose = { {}, { "Kit" }, { "Kit", "Marking" }, { "Kit", "Marking", "Trim" } },
		petals = 3,
		holeDepth = 0.06,
		debris = { life = 8, speed = { 8, 16 }, spin = 8 },
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
			-- (each part's accent pieces, Palette.Artillery.Roles, ride with it)
			mount = { "Mount", "MountTrim", "MountFittings", "MountMarking" },
			cradle = { "Cradle", "CradleFittings" },
			barrel = { "Barrel", "Bore", "BarrelTrim", "BarrelFittings" },
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
			repair = 10, -- (half the swings it takes to build)
			-- (user 2026-10-26: "angles it slightly (not visibly at all) up, since it will be a mid range weapon (only can
			-- hit enemy sectors)"; picked: the shortest shot ~300 studs, one sector): +8 on every shot, so -5..16 on the
			-- dial throws 3..24: ~300 to ~2,100 studs
			aimTilt = 8,
			-- (user 2026-10-26: "add a platform hitbox for the cannon"; picked: the ground it stands on counts as the gun)
			platform = { pad = 3, thick = 1.5 },
			-- (user 2026-10-27: "the field cannon shouldnt have a platform, it should just make the ground its on lose its
			-- grass and straight out. just give it a hitbox on the terrain around it")
			level = { pad = 2, blend = 8, material = "Ground" },
			wreckParts = { "Carriage", "Wheels", "Mount" }, -- (the mount turns at most 4.5 degrees)
			holeSize = { 0.3, 0.6 },
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
			-- the trail on its wheels first, then the shield and mount, the cradle, the barrel, the breech last
			assembly = {
				{ names = { "Carriage", "Wheels", "Tyres" }, at = 0 },
				{ names = { "Mount" }, at = 1 },
				{ names = { "Cradle" }, at = 2 },
				{ names = { "Barrel", "Bore" }, at = 3 },
				{ names = { "Breech" }, at = 4 },
			},
		} :: Gun,
		-- The magic howitzer v6 (user 2026-10-21: "look like the big bertha", "no tires ... the turning being controlled by
		-- giant gears"; tools/blender/artillery/bertha.py, approved v10): a 42 cm siege mortar, its riveted box carriage
		-- turning all the way round on a giant ring gear, the barrel trunnioned high between its walls. A short-arc mortar
		-- (user: "make the howitzer more of a short arc mortar weapon"): it only lobs, 45..80 degrees, 160 studs/s under
		-- its own lighter gravity: ~590 studs at 45 down to ~200 at 80, 5-7 s in the air. Its recoil is cut short at
		-- high elevation so the gem under the breech clears the turntable (~1 at 80). Dug in when placed (`dig`).
		artillery_howitzer = {
			asset = "artillery_howitzer",
			name = "42 cm Rune mortar",
			base = "Bed",
			mount = {
				"Mount",
				"MountTrim",
				"MountFittings",
				"MountKit",
				"MountMarking",
				"TraversePinion",
				"TraverseWheel",
				"ElevationPinion",
				"ElevationWheel",
			},
			-- the traverse pinion rolls round the 60-tooth ring gear (10 teeth: 6 turns to the gun's one), its hand wheel
			-- on its shaft; the elevating pinion (8 teeth) meshes the cradle's 50-tooth sector, against it (bertha.py)
			gears = {
				{ part = "TraversePinion", centre = { -5.576, 1.09, -4.515 }, axis = "Y", by = "traverse", ratio = 6 },
				{ part = "TraverseWheel", centre = { -5.576, 4.4, -1.2 }, axis = "Z", by = "traverse", ratio = 6 },
				{
					part = "ElevationPinion",
					centre = { -3.81, 3.973, -0.104 },
					axis = "X",
					by = "elevation",
					ratio = -6.25,
				},
				{
					part = "ElevationWheel",
					centre = { -4.15, 3.973, -0.104 },
					axis = "X",
					by = "elevation",
					ratio = -6.25,
				},
			},
			cradle = { "Cradle", "CradleTrim" },
			barrel = { "Barrel", "BarrelRunes", "Bore", "BarrelTrim" },
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
			hp = 100,
			armour = 2.4,
			repair = 30, -- (half the swings it takes to build)
			wreckParts = { "Bed", "Mount", "Cradle" }, -- (the moving ones carried by src/client/Artillery)
			holeSize = { 0.7, 1.4 },
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
			-- the bed and its ring gear first, then the carriage, the cradle, the barrel, the breech and gem last
			assembly = {
				{ names = { "Bed", "RingGear" }, at = 0 },
				{ names = { "Mount", "Traverse", "Elevation" }, at = 1 },
				{ names = { "Cradle" }, at = 2 },
				{ names = { "Barrel", "Bore" }, at = 3 },
				{ names = { "Breech", "Crystal" }, at = 4 },
			},
		} :: Gun,
		-- The MG nest's machine gun (user 2026-10-27, design approved by the user): an MG 08
		-- (tools/blender/mgnest/mg08.py) built by the shovel in an MG nest (Config/Build.Nest), set up in quarters
		-- (`assembly`). Gun space: the origin on the mount bag's top under the pivot. Its firing (bullets, its belt box,
		-- the box reload) comes with manning it (next step); the shell fields below are kept only so it is a Gun.
		mg08 = {
			asset = "mg08",
			name = "MG 08",
			nest = true,
			nestGround = { lo = { -0.5, -0.5 }, hi = { 0.5, 0.5 } },
			base = "Carriage",
			mount = {
				"Mount",
				"MountFittings",
				"Shield",
				"ShieldTrim",
				"ShieldFittings",
				"BoxKit",
				"BoxTrim",
				"BoxFittings",
				"Belt",
				"Rounds",
				"Bullets",
			},
			cradle = { "Cradle", "CradleTrim", "CradleFittings" },
			barrel = { "Barrel", "Bore" },
			breech = {},
			trunnion = { 0, 1.035, 0 },
			hinge = { 0, 1.035, 0 },
			muzzle = { 0, 1.25, -2.187 },
			boreCentre = 0.009,
			traverse = 20, -- (the design: +-20 before the shield meets the top bags round the notch)
			elevation = { -8, 10 },
			swing = 0.001, -- (it never swings past its stops: the nest holds it)
			traverseRate = 60,
			elevationRate = 40,
			speed = 900,
			gravity = 196.2,
			charge = 0,
			breechOpens = false,
			kg = 0.01,
			scatter = { yaw = 0.6, elevation = 0.6, speed = 0 },
			reload = 12, -- (the box reload, the design's long wait)
			breechOpen = 0,
			breechTimes = { 0, 0 },
			recoil = 0.06, -- (recoil-operated: the barrel and lock kick back a little each shot)
			recoilTimes = { 0.01, 0.05 },
			crew = { 0, 4 }, -- (standing behind the grips, arms out to them: MGStand)
			crewTurns = true,
			prompt = 7,
			vfx = { scheme = "Ember", magic = false },
			muzzleScale = 0.3,
			sound = { fire = {}, far = {}, blast = {}, echo = {}, whistle = {}, whistleLead = 0 },
			zone = 0,
			shell = {
				size = 0.1,
				color = { 255, 220, 150 },
				tail = { 200, 200, 200 },
				trail = 0.1,
				light = 0,
				magic = false,
			},
			hp = 100,
			repair = 7,
			wreckParts = { "Mount", "Cradle" },
			holeSize = { 0.08, 0.16 },
			-- (the design: 450 a minute, a box of 100, a 12 s box reload, 0.6 degrees growing to 1.5 over a long burst;
			-- the eye half a stud behind the rear peep ring, the ring sight's line at y 1.78; the report a placeholder,
			-- the rifles' shot cut short)
			mg = {
				rate = 450,
				box = 100,
				range = 600, -- (as far as a rifle shot: Config/Firing.Range, the fog)
				class = "MachineGun",
				spread = { min = 0.6, max = 1.5, per = 0.06, recover = 0.3 }, -- (hot after ~50 rounds held, cool ~3 s after)
				-- the gunner's pose while manning it (tools/animation/mg.luau MGStand, a loop; user 2026-10-28: "make it
				-- standing and ready"): standing behind it, hands on the spade grips
				stand = 90383747593412,
				eye = { 0, 1.78, 2.44 },
				-- the eye at the hip, in first person (user 2026-10-28: "can you move the camera up more since the
				-- shield in the way of the camera"): over the shield's top (`shield`: its arch's top with the rim, its
				-- face's z) at the gun's lowest, turning with the mount as the shield does, not lifting with the gun
				over = { 0, 2.95, 2.44 },
				shield = { top = 2.65, z = 0.36 },
				-- over the shoulder: the camera's offset right and up from the gunner's head (as Config/Camera.Gun
				-- Shoulder; user 2026-10-28: "fix the MG's third-person camera so the gun shows past the standing
				-- gunner"): wide and high enough that the line down to the gun passes over the right shoulder
				shoulder = { 2.5, 1 },
				look = 0.12,
				shot = { id = 134529004435835, volume = 1.8, start = 0.34, stop = 0.9, fade = 0.4, profile = "Gunshot" },
			},
			camera = { side = 0, up = 1.8, back = 4.5, yaw = 0, pitch = 0, follow = 0.5, fov = 70 },
			-- (the gunmetal body and the belt, not the team's paint: the shield, mount and foot take it)
			colors = {
				Cradle = { 46, 48, 51 },
				Barrel = { 46, 48, 51 },
				Belt = { 140, 120, 84 },
				Rounds = { 196, 160, 84 },
				Bullets = { 184, 115, 72 },
			},
			-- (user 2026-10-27, the stage design: "sled-gun-shield-box order"): the foot and mount, the gun, the shield,
			-- the ammo box and its belt last, each appearing in place in its quarter (user 2026-10-28: "not all the parts have to
			-- be present before its built (all the other structures work this way too). they can just appear as its being
			-- built")
			assembly = {
				{ names = { "Carriage", "Mount" }, at = 1 },
				{ names = { "Cradle", "Barrel", "Bore" }, at = 2 },
				{ names = { "Shield" }, at = 3 },
				{ names = { "Box", "Belt", "Rounds", "Bullets" }, at = 4 },
			},
		} :: Gun,
	},
}

return table.freeze(Artillery)
