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
	-- a field gun's or howitzer's shell comes down up to `miss` studs from where it was laid (Rules.miss; user
	-- 2026-11-02: "the artillery (mg nest excluded) should be way less accurate. it should miss a lot of its shots by a
	-- little (not exactly where ur aiming)"): mostly about half that, rarely on the aim; nil for the machine gun
	miss: number?,
	reload: number, -- seconds from a shot to the next
	-- its reload runs on when its gunner gets off (nil: broken off and started over once it is manned again, the field
	-- gun's and the MG's; src/server/Artillery cancelReload)
	keepsReload: boolean?,
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
	-- the traverse turns about the vertical line through this gun-space (x, z) (nil: the origin): the MG's tripod
	-- pintle, so it spins on its mount (user 2026-11-03: "make it spin from the mount")
	pintle: { number }?,
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
	-- elevation x `follow` (a high lob stays in view); with `lob` (the field gun, laid up to lob over cover: user
	-- 2026-11-03, "notice how i cant see over the hill im trying to shoot over") it rises `lob.up` and backs off
	-- `lob.back` studs a degree of elevation and looks down at where the shell comes down instead of following it up
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
	camera: {
		side: number,
		up: number,
		back: number,
		yaw: number,
		pitch: number,
		follow: number,
		fov: number,
		lob: { up: number, back: number }?,
	},
	-- the elevation it is placed at (nil: level, or its lowest when that is above level)
	rest: number?,
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
		tap: number, -- a fresh pull's one shot: the next comes no sooner than this many seconds after it (Rules.mgShot)
		box: number,
		range: number,
		class: string,
		spread: { min: number, max: number, per: number, recover: number },
		stand: { level: number, low: number, high: number },
		reload: {
			animation: number,
			lift: number,
			drop: number,
			take: number,
			set: number,
			fed: number,
			box: string,
			grip: { number },
			-- each step's sound, `at` s into the reload, at the gun (src/client/Artillery reloadBox): played once a
			-- reload, by everyone near, skipped if joined over a second after it
			sounds: { { at: number, sound: any } },
		},
		eye: { number },
		over: { number },
		shield: { top: number, z: number },
		shoulder: { number },
		look: number,
		shot: any,
		-- a low boom under the shot (`shot` is the crack, alone heard far off as a rifle's), its pitch varied by
		-- +/- `vary`; `jingle`: the belt and can rattling as each round is pulled in
		boom: any,
		vary: number,
		jingle: any,
		-- the report's pitch and tone, as a rifle's (Config/Weapons `report`), heard as a rifle's (src/client/ShotAudio)
		report: { pitch: number, eq: { number } },
		-- each of the gunner's own shots kicks their camera `shake` degrees, nothing past `shakeReach` studs from the
		-- muzzle (src/client/CameraShake)
		shake: number,
		shakeReach: number,
		-- what each shot throws off (src/client/CaseDrop, Config/Cases): `case` the spent case (a copy of Rounds01), `link`
		-- its belt link (Links01), each from `at` (gun space, riding the cradle) at `push` studs/s (gun space: +X right,
		-- +Y up, +Z back) give or take up to `scatter` on each axis, clinking as `sound`
		spent: { [string]: { part: string, at: { number }, push: { number }, scatter: number, sound: string } },
	}?,
	-- its barrel warming as it fires (src/client/BarrelHeat, Heat below; user 2026-10-29: "make the barrel get warmer
	-- from the tip as you hold it (steam a little too)"): each shot adds `per` to its heat (0 cold .. 1), losing `cool`
	-- a second; `segments` glowing bands over the `length` studs behind the muzzle, `radius` x the bore's radius round
	-- (a little over the barrel), lighting from the tip back as it warms; steam off it past `steam`, up to `steamRate`
	-- puffs a second hot; nil: none (the howitzer)
	heat: {
		per: number,
		cool: number,
		length: number,
		radius: number,
		segments: number,
		steam: number,
		steamRate: number,
	}?,
	-- each shot jolts its gunner (src/client/GunnerKick; user 2026-10-29: "add some recoil animation to both the gun
	-- and the player"): the arms back `arms` degrees and the body `torso`, settling over `time` s; nil: none
	kick: { arms: number, torso: number, time: number }?,
	-- part names coloured so instead of by Palette.Artillery (the MG's gunmetal body and its belt); nil: none
	colors: { [string]: { number } }?,
	-- parts that stand still as it is laid but are looked up by name all the same (the MG's ammo can and the belt in it,
	-- hidden while its box is changed); nil: none
	fixed: { string }?,
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

-- The M2's belt (tools/blender/mgnest/m2.py): a link belt from the feedway down to its can on the mount bag, every
-- round on it outside the can its own case, bullet and link (`Rounds01` / `Bullets01` / `Links01` next into the feed;
-- user 2026-10-29: "make it go empty as we go empty", "make it attached to where its fed": src/client/Artillery bends
-- them with the gun); its mount names and colours (the links dark steel)
local BELT = 12 -- (the last dipping into the can's mouth: user 2026-10-29, "the last bullet loop isnt feeding")
local function beltOf(names: { string }, colors: { [string]: { number } }): ({ string }, { [string]: { number } })
	for i = 1, BELT do
		local case, tip, link =
			string.format("Rounds%02d", i), string.format("Bullets%02d", i), string.format("Links%02d", i)
		table.insert(names, case)
		table.insert(names, tip)
		table.insert(names, link)
		colors[case], colors[tip], colors[link] = { 196, 160, 84 }, { 184, 115, 72 }, { 40, 40, 38 }
	end
	return names, colors
end
-- (its ammo can and the belt in it too: they turn with the gun right round the 360 nest, user 2026-11-03)
local mgMount, mgColors = beltOf({
	"Mount",
	"MountFittings",
	"BoxKit",
	"BoxTrim",
	"BoxFittings",
	"Belt",
}, { Cradle = { 46, 48, 51 }, Barrel = { 46, 48, 51 }, Belt = { 40, 40, 38 } })

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

	-- Bot soldiers on the guns (src/server/Artillery's manAs ... API; user 2026-11-01: "make bots be able to use
	-- artillery too (but players can kick them off)"; any free gun, only the bot's teammates take it over): a bot mans a
	-- gun from within `reach` times its prompt's reach of the crew spot; a gun counts as laid on its aim within `laid`
	-- degrees; a bot put off for a player is set down `aside` studs to the gun's side of the crew spot. While a bot mans
	-- it, the prompt reads `takeOver` for its teammates.
	Bot = { reach = 1.5, laid = 0.5, aside = 4, takeOver = "Take over the gun" },
	-- a bot gunner's tracks on every client (src/client/Artillery), each an AnimationPriority a step over its own (brace
	-- Action3, loading and box reload Action2, hand wheel and stance Action): over the bot's weapon hold (Action, played
	-- from the server: src/server/Bots/Animate), in a player gunner's order
	BotPose = { brace = "Action4", load = "Action3", reload = "Action3", crank = "Action2", stand = "Action2" },

	-- No shells on the spawns (user 2026-11-02: "it shouldnt be able to reach the exact spawn no matter where its placed?
	-- make it consistent throughout all maps"; Rules.nearSpawn): a field gun or howitzer won't fire where its shell
	-- would come down (its path cast on the terrain) within its `zone` plus `gap` studs of a spawn: either side's spawn
	-- zone (the map's spawnZones) or, in a Normal match, either side's wave line now, a circle `line` studs round its
	-- centre (Config/Frontline.LineAttribute). It still lays there (user 2026-11-02: "still allow aiming over it, just put
	-- the warning more center bottom/top of the screen so players know"): while it is laid on one the gun has
	-- `attribute` true and its gunner reads `why` in the bottom centre (src/client/ArtilleryHud). Bots don't aim there.
	SpawnGuard = {
		gap = 20,
		line = 24,
		why = "Can't fire on a spawn",
		attribute = "OnSpawn",
	},
	-- A field gun's or howitzer's miss (its `miss`; src/server/Artillery missOf): rolled again, up to `tries` times,
	-- while its path traced on the terrain comes down on a spawn or more than `stray` times the radius off (rough
	-- ground: a longer shot clearing a crest); none after that.
	Miss = { tries = 8, stray = 1.25 },

	-- The arc line and landing marker while manning (src/client/Artillery): the line is one Beam bent to the path
	-- (as the grenade's, Palette.Artillery.Arc), the marker a ring and the range on top of everything (seen past the fog)
	-- Out of the gunner's way (user 2026-11-02: "make surrounding / blocking trees/houses more transparent to prevent
	-- them from blocking the artys view"; src/client/ArtilleryFade, this client only): while I'm on a field gun or
	-- howitzer, every `every` seconds rays go from the camera through `cols` x `rows` points of the screen box `box`
	-- (left, top, right, bottom, Rules.sightPoints), out to `far` studs or the ground, past at most `depth` things each; a tree or building (a Model tagged one of `tags`) they cross fades to `see` see-through, at
	-- `rate` a second, and back once no ray has crossed it for `hold` seconds.
	ViewFade = {
		every = 0.15,
		cols = 7,
		rows = 5,
		box = { 0.1, 0.25, 0.9, 0.9 },
		far = 400,
		depth = 6,
		tags = { "SwayTree", "FallenTree", "NaturalBuilding" },
		see = 0.8,
		rate = 4,
		hold = 0.6,
	},

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
	-- easing in and out over `fade` s; a bot gunner (whose aim no client knows) winds it while its gun's lay has moved
	-- in the last `held` s. nil: not uploaded yet.
	-- (the delay is each gun's `charge`; the brace starts so its pull, `pull` s into it, lands on the shot)
	Brace = { animation = 110111507484119 :: number?, pull = 0.45 },
	Turn = { crank = 80321147839061 :: number?, moving = 0.3, fade = 0.2, held = 0.25 },

	-- A warm barrel (src/client/BarrelHeat, each gun's `heat`; user 2026-10-29: "make the barrel get warmer from the tip
	-- as you hold it (steam a little too)", then "make the barrel start gradual and heat up way more (50% of the
	-- barrel)"): its bands glow from `cold` to `hot` (RGB), at most `glow` opaque; band i of n (1 the tip) starts at heat
	-- (i - 1) / n x `lead` (Rules/Artillery.heatGlow), each easing in along its glow ^ `curve` (no band pops on); a
	-- `light` at the tip `range` studs out, up to `brightness`, as hot. The steam: `color` puffs `size`
	-- studs growing to `grow`, rising `rise` studs/s against `drag`, living `life` s, `transparency` at birth, leaving at
	-- `speed` studs/s every which way, turning up to `spin` degrees a second.
	Heat = {
		cold = { 120, 24, 12 },
		hot = { 255, 150, 50 },
		glow = 0.95,
		lead = 0.75,
		curve = 1.8,
		light = { range = 7, brightness = 2.5 },
		steam = {
			color = { 235, 235, 235 },
			size = 0.25,
			grow = 1.1,
			rise = 1.6,
			drag = 1,
			life = { 1.2, 2 },
			transparency = 0.55,
			speed = { 0.2, 0.6 },
			spin = 30,
		},
	},

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
			-- sled barely moves, a short buzz settled before the next shot (Guns `mg.rate`); the M2 kicks harder
			-- (user 2026-10-29: "add some recoil animation to both the gun and the player"; under a quarter of the field's)
			MG = { back = 0.07, lift = 0.35, rise = 0.015, wobble = 45, damp = 30, time = 0.12 },
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
		alsoRunes = { "BarrelRunes", "CradleRunes" }, -- (the bed's runes are gone: user 2026-10-26; the collar's, 2026-11-02)
		-- the rune engravings round the barrel (user 2026-11-02: "make rune engravings appear on the barrel when the gun
		-- is charging up to be fired"; Rules/Artillery.engravingShown): unseen till the charge-up, fading in through it
		-- toward `glow` (Crystal colours: past 1 toward white-hot), full on the shot, gone again over `fade` s after it
		engraving = { part = "BarrelEngraving", glow = 1.4, fade = 1 },
		-- the orbiting runes' strokes (user 2026-10-26: "more ... curve. it looks too blocky"; their halos taken off
		-- again: "it makes the runes indecipherable"): each bows `bow` of its length off true (alternate strokes the
		-- other way) in `pieces` rounded pieces, swelling to `swell` x the stroke in its middle, `tip` x at its ends
		strokes = { bow = 0.1, pieces = 3, swell = 1.2, tip = 0.55 },
		runesFloor = 0.15,
		light = { range = 14, brightness = 2.5 },
		runes = 8,
		orbit = 1.9, -- (round the Rune howitzer's caged crystal, 2026-11-02; was 2.9 round the 42 cm's gem)
		size = 0.6,
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
		-- (Broken: below Man.keep) it no longer charges or fires but sputters on, holding at `glow` and black for `blackout` of
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
	-- close, crossfading (equal power, Rules/ShotAudio.mix) into `far` from `Report.near` to `Report.far` studs (user
	-- 2026-10-28: the echo and far report grow with distance; was a hard switch at 400), `blast` the shell going off; the incoming shell's `whistle` is
	-- heard within `Whistle.reach` studs of where it lands, starting the gun's `whistleLead` s before it lands (only on a
	-- flight at least that long: a short one comes in under the report; Studio round 2). All late and
	-- duller far off (Rules/Grenade.heard).
	Whistle = { reach = 300 },
	-- a blast's echo (each gun's `sound.echo`): silent within `from` studs, rising to full at `full`, a little after the
	-- blast itself (`lag` s)
	Echo = { from = 120, full = 450, lag = 0.25 },
	Heard = { dullFrom = 80, dullFull = 900, highCut = -14, lowBoost = 5 },
	Report = { near = 150, far = 500 },

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
		-- (user 2026-11-02, the damage rework: its 100 kg shell reaches less far; was near 25, reach 30)
		howitzer = { direct = 150, near = 30, reach = 14 }, -- (a field gun at once; the howitzer: two)
		byCharge = {
			{ kg = 0.5, source = "grenade" },
			{ kg = 5, source = "field" },
			{ kg = math.huge, source = "howitzer" },
		},
	},
	-- A damaged gun (user 2026-10-25: "once it gets to a critical percentage (let's say 50%) it becomes unusable, but not
	-- completely wrecked. make it 4 stages, each at 25%, each more damaged"): stage i once its HP is down to `at[i]`% of
	-- full; below Man `keep` nobody can man it (its gunner is thrown off), its barrel knocked down to its lowest lay
	-- and up to `knock` degrees round, the howitzer's crystal dying. Each stage scorches it `scorch[i]` of the way to
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
	-- `repair` (an admin dig step: that share of its full HP). An unusable gun is usable again from Man `keep`%: a fresh
	-- gun stands in its place, damaged to the HP it has; whole, a fresh gun again. Each time its ground is flattened out
	-- again (the howitzer's pit dug out again).
	-- Manning a gun (Rules/Artillery.mannable; user 2026-11-03: "manning the gun for any arty should be be available
	-- until CONTRUCTION to 100 HP. after constructed, it can still be operated until low HP (50%)"): any gun (field gun,
	-- howitzer, MG) being built can't be manned until its HP first reaches `built`% (src/server/Build places the real gun
	-- only then); once built it can be manned at or above `keep`% of its HP, and below that its gunner is put off until
	-- repairs bring it back to `keep`%. For players and bots alike.
	Man = { built = 100, keep = 50 },
	-- How far a field gun or howitzer reaches (Rules/Artillery.capped; user 2026-11-03: "adjust cannons so that they
	-- cannot be shot over a sector away. same thing with the howitzer"): `sectors` of the live map's sector spacing
	-- (Rules/Artillery.sectorSpan: ~423 studs on Map 1) plus `margin` studs (two zone radii: a gun anywhere in its
	-- sector reaches anywhere in the next), on flat ground: the lay stops there (the field gun raises no higher, the
	-- howitzer lowers no further). Bots aim within it too. Machine guns keep their own range. `guns`: a gun's own (the
	-- field gun, user 2026-11-03: "i think you nerfed the range a little too hard": 1.5 sectors, 725 studs on Map 1, 722
	-- on Lantern Meadows; its own longest shot, 720 at 45 degrees, is what stops it).
	Reach = { sectors = 1, margin = 90, guns = { artillery_qf18 = { sectors = 1.5, margin = 90 } } },
	Wreck = {
		at = { 75, 50, 25, 0 },
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
		-- The field gun (A1), the Italian 75/27 mod. 1911 Deport since v6 (user 2026-11-03: "find field cannon designs that
		-- look like this and rebuild the field cannon", so its barrel lays up to 70 without passing through it; was the QF
		-- 18-pounder, still its key): traverse 4.5, recoil 46 in, the breech 100 degrees.
		artillery_qf18 = {
			asset = "artillery_qf18",
			name = "75/27 Déport",
			base = "Carriage",
			-- (each part's accent pieces, Palette.Artillery.Roles, ride with it)
			mount = { "Mount", "MountTrim", "MountFittings", "MountMarking" },
			cradle = { "Cradle", "CradleFittings" },
			barrel = { "Barrel", "Bore", "BarrelTrim", "BarrelFittings" },
			breech = { "Breech" },
			-- (v6) the trunnions 1.0 behind the axle, near the breech, so laid high it drops between the trail legs
			trunnion = { 0, 2.55, 1.0 },
			hinge = { 0.28, 2.95, 2.35 },
			muzzle = { 0, 2.95, -3.75 },
			boreCentre = 0.18,
			traverse = 4.5,
			-- (user 2026-11-03: "alter the field gun so its more 'arc'. it should fire similarily to a mortar, maybe with
			-- less arc", "allowing cannons to be angled upwards ... its too flat"): laid from 5 up to 70 degrees (was -5
			-- to 16, with a hidden +8.5): low shots to 45, then lobbed over cover from 45 to 70 (its lobs reach 463 to 720
			-- studs), short of the howitzer's 80; placed at `rest` 20
			elevation = { 5, 70 },
			rest = 20,
			swing = 10,
			traverseRate = 6,
			elevationRate = 4,
			-- 227 studs/s (was 420): 125 studs at 5 degrees, 460 at 20, 625 at 30, 720 at 45 (its longest), 463 lobbed at
			-- 70 (topping out ~320 up, ~6 s in the air); 2.2 s at 20, 4.5 s at 45 (was 420 with a hidden +8.5: 300 to
			-- 2,100 studs, nearly flat)
			speed = 227,
			gravity = 71.6,
			charge = 0.45,
			breechOpens = true,
			-- (user 2026-10-21: "the explosives to be a lot more damaging and destructive ... realistic"; was 0.6 kg,
			-- fragments lethal 6 / wound 30): a shell's lethality is mostly its fragments: a real 18-pdr HE burst kills
			-- out to ~10 m and wounds to ~25-30 m, and its charge as TNT here is raised to 2.5 kg so it breaks walls
			kg = 2.5,
			fragments = { lethal = 12, wound = 40, max = 100, near = 70, far = 15 },
			miss = 36, -- (mostly ~18 studs off: past its lethal 12, inside its wounding 40)
			reload = 10,
			breechOpen = 100,
			breechTimes = { 1.2, 1 },
			recoil = 3.34,
			recoilTimes = { 0.08, 1.2 },
			-- (v6) laid high the recoil is cut short, as a high-angle gun's: the breech block's low edge (1.57 behind the
			-- trunnion, 0.23 over its axis) stays 0.35 over the ground; full up to ~30 degrees, ~0.9 at 70
			recoilClear = { floor = 0.35, along = 1.57, below = -0.23 },
			hp = 100,
			repair = 10, -- (half the swings it takes to build)
			-- (user 2026-10-26: "add a platform hitbox for the cannon"; picked: the ground it stands on counts as the gun)
			platform = { pad = 3, thick = 1.5 },
			-- (user 2026-10-27: "the field cannon shouldnt have a platform, it should just make the ground its on lose its
			-- grass and straight out. just give it a hitbox on the terrain around it")
			level = { pad = 2, blend = 8, material = "Ground" },
			wreckParts = { "Carriage", "Wheels", "Mount" }, -- (the mount turns at most 4.5 degrees)
			holeSize = { 0.3, 0.6 },
			crew = { -2.4, 2.8 }, -- left of the breech, behind it (the loading reaches it), outside the left trail leg
			crewTurns = false,
			prompt = 8,
			vfx = { scheme = "Ember", magic = false },
			muzzleScale = 1,
			loads = true,
			sound = {
				-- dry beside the gun (user 2026-10-28: "the shot keeps ringing a distant echo when we are right next to the
				-- gun", and "not the natural gun sounds after firing"): Explosions 4's first 0.5 s is its crack and boom, the
				-- rest debris falling and a ~4 s rumble (measured 2026-10-28), so it dies away from 0.6 s (an exponential
				-- fade: Config/Firing.Sounds.Shot); the 18-pounder's ~0.6 kg of cordite and its supersonic shell (~490 m/s)
				-- make a sharp crack-bang, as recorded
				fire = {
					{ id = 9116973611, volume = 1.4, profile = "Explosion" }, -- Mortar Explosion 3: big, low thump
					{
						id = 9114362266,
						volume = 0.8,
						profile = "Explosion",
						stop = 3,
						fade = 2.4,
						curve = "Exponential",
					}, -- Explosions 4
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
			camera = {
				side = -6.5,
				up = 5.5,
				back = 10,
				yaw = 25,
				pitch = 2,
				follow = 0.4,
				fov = 60,
				lob = { up = 0.45, back = 0.25 },
			},
			-- (user 2026-10-29: the MG's warm barrel, steam and the gunner's recoil "apply to the field cannons too (not
			-- the howitzer)"): a third of the way warm a shot, cooling over ~40 s, half its barrel glowing; the gunner thrown
			-- back by each shot
			-- (v6: radius 1.7, was 2.9 round the 18-pounder's smaller Bore disc: a little over the 75's barrel)
			heat = { per = 0.3, cool = 0.025, length = 2.5, radius = 1.7, segments = 8, steam = 0.25, steamRate = 8 },
			kick = { arms = 12, torso = 5, time = 0.4 },
			-- the trail on its wheels first, then the shield and mount, the cradle, the barrel, the breech last
			assembly = {
				{ names = { "Carriage", "Wheels", "Tyres" }, at = 0 },
				{ names = { "Mount" }, at = 1 },
				{ names = { "Cradle" }, at = 2 },
				{ names = { "Barrel", "Bore" }, at = 3 },
				{ names = { "Breech" }, at = 4 },
			},
		} :: Gun,
		-- The Rune howitzer v7 (user 2026-11-02: "completely remake a new howitzer model ... make it stronger than the field
		-- cannon, but less AOE but keep direct damage strong"; "lets take inspiration from these styles": the US 240 mm
		-- and 8-inch M1 heavy howitzers in their sandbagged pits; "keep the howizer semi dugged, but have sandbags around
		-- it that behave similarily to how the mg nest sandbags behave"; "make it even bigger. it should still be a deadly
		-- weapon"; "this is still a magic howitzer. no shells or anything and include a rune crystal somehow";
		-- tools/blender/artillery/rune_howitzer.py; was the 42 cm Bertha mortar v6, bertha.py): a long barrel under twin
		-- recuperators in a sleigh cradle, trunnioned between the riveted walls of a top carriage turning right round on a
		-- toothed ring gear, the big cracked rune crystal caged on the cradle over the breech. It still only lobs, 45..80
		-- degrees at 160 studs/s under its own lighter gravity: ~590 studs at 45 down to ~200 at 80, 5-7 s in the air.
		-- Its recoil is cut short at high elevation so the breech's carrier handle clears the turntable. Built 3 down in a
		-- shallow pit (`dig`) in a ring of sandbags (Config/Build.GunRing).
		artillery_howitzer = {
			asset = "artillery_howitzer",
			name = "Rune howitzer",
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
			-- the traverse pinion rolls round the 54-tooth ring gear (10 teeth: 5.4 turns to the gun's one), its hand wheel
			-- on its shaft; the elevating pinion (8 teeth) meshes the cradle's 40-tooth sector (rune_howitzer.py)
			gears = {
				{
					part = "TraversePinion",
					centre = { -3.546, 0.73, -4.539 },
					axis = "Y",
					by = "traverse",
					ratio = 5.4,
				},
				{ part = "TraverseWheel", centre = { -3.546, 2.75, -0.3 }, axis = "Z", by = "traverse", ratio = 5.4 },
				{
					part = "ElevationPinion",
					centre = { -2.15, 2.236, 0.583 },
					axis = "X",
					by = "elevation",
					ratio = -5,
				},
				{
					part = "ElevationWheel",
					centre = { -2.62, 2.236, 0.583 },
					axis = "X",
					by = "elevation",
					ratio = -5,
				},
			},
			-- (the crystal rides the cradle: it elevates with the gun but never recoils)
			cradle = { "Cradle", "CradleTrim", "CradleFittings", "CradleRunes", "Crystal", "CrystalCracks" },
			barrel = { "Barrel", "BarrelRunes", "BarrelEngraving", "Bore", "BarrelTrim" },
			breech = { "Breech" },
			trunnion = { 0, 4.6, 1.0 },
			hinge = { 0, 4.6, 3.1 }, -- (the breech never opens)
			muzzle = { 0, 4.6, -10.6 },
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
			-- (user 2026-11-02, the damage rework, table approved: "make it stronger than the field cannon, but less AOE but
			-- keep direct damage strong, just scale it with the lowered AOE radius", "it should still be a deadly weapon";
			-- was 340 kg, crater x0.5, fragments lethal 18 / wound 60): 100 kg, every reach x0.67 (the cube root): soldiers
			-- die to ~19.6 by blast (the field gun's fragments kill to 12) and are hurt to ~32 (the field gun wounds to 40),
			-- walls break to ~13 (most of a cottage, no longer the whole house), trees fall to ~45; its crater kept at
			-- half its charge's own (user 2026-10-23: "lower the crater of the howitzer cannon even more"), ~22 across
			kg = 100,
			craterScale = 0.5,
			fragments = { lethal = 16, wound = 30, max = 100, near = 70, far = 15 },
			miss = 60,
			reload = 30,
			-- (user 2026-11-03: "recharing the howitzer should happen even if you're not on the gun"): its crystal fills
			-- whether anyone is on it or not, and everyone sees how far it has come (src/client/ArtilleryCrystal)
			keepsReload = true,
			breechOpen = 100,
			breechTimes = { 2, 2 },
			recoil = 1.2,
			recoilTimes = { 0.12, 2 },
			recoilClear = { floor = 1.35, along = 2.12, below = 0.6 }, -- the carrier handle over the turntable (1.15)
			-- the gunner on the turntable behind the hand wheels, left of the carriage (turning with it)
			crew = { -3.65, 1.6 },
			crewY = 1.15, -- the turntable's top
			crewTurns = true,
			prompt = 9,
			-- (user 2026-11-02: "we can keep the howizer semi dugged"; was 10.5 deep in a 15-stud pit under a 4.5 earth
			-- rim, its walls lined with trench slabs): 3 down, the floor 8.5 round (past the bed's corners, ~8.1 out), the
			-- walls leaning back at a trench's 59 degrees to ~10.3, no rim or slabs (the sandbag ring stands round it from
			-- ~11.9, Config/Build.GunRing); a ramp out behind (~43 degrees, walkable under 50) that is up at the ground
			-- before the ring, so the bags by its doorway stand on whole ground; at least two voxels wide
			dig = {
				depth = 3,
				radius = 8.5,
				rim = 0,
				rimHeight = 0,
				ramp = { width = 8, length = 3.2 },
				wall = 59,
			},
			hp = 100,
			armour = 2.4,
			repair = 30, -- (half the swings it takes to build)
			wreckParts = { "Bed", "Mount", "Cradle" }, -- (the moving ones carried by src/client/Artillery)
			holeSize = { 0.4, 0.9 },
			vfx = { scheme = "Arcane", magic = true },
			muzzleScale = 1.6,
			sound = {
				-- a heavy howitzer's deep, slow boom, dry beside it: Sonic Boom 2 rolls on at -1..-10 dB for ~3 s after
				-- its 0.3 s of lead-in silence and dies out over 6.5 s (measured 2026-10-28), so it plays from 0.25 s and dies
				-- away from 1.2 s (an exponential fade); Mortar Explosion 5 a fifth lower (0.85)
				fire = {
					-- Sonic Boom 2: a huge single boom
					{
						id = 9119382515,
						volume = 1.5,
						profile = "Explosion",
						start = 0.25,
						stop = 4,
						fade = 2.8,
						curve = "Exponential",
					},
					{ id = 9116973607, volume = 1.2, profile = "Explosion", pitch = 0.85 }, -- Mortar Explosion 5
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
			zone = 32, -- 100 kg: lethal by blast to ~19.6, the blast hurting to ~32 (was 340 kg: 48)
			-- a bright four-point star (user 2026-10-21: "a bright 4 point star"): a white-hot core, the spikes (below), a
			-- strong light; a blue trail of light and static crackling round it
			shell = {
				size = 2,
				color = { 235, 250, 255 },
				tail = { 90, 170, 255 },
				trail = 1.2,
				light = 34,
				magic = true,
				static = "Glow",
				-- the anime four-point sparkle: four long tapered spikes `long` studs out, `width` wide at the core; four short
				-- faint ones `diag` out between them; a soft `halo` ball; `twinkle` the flutter, `spin` deg/s
				star = {
					long = 9,
					width = 1.1,
					diag = 3,
					diagWidth = 0.45,
					diagFade = 0.45,
					halo = 3.8,
					haloFade = 0.75,
					twinkle = 0.18,
					spin = 15,
					beamBrightness = 8,
					brightness = 6,
					color = { 225, 245, 255 },
				},
			},
			-- (the 42 cm's was side -12, up 28.5, back 20, pitch -21, fov 70, from high over its 10.5-deep pit; this one
			-- stands 3 down, so the camera comes down and in with it: high behind the gunner's left over the sandbags,
			-- looking down past the crystal at the landing)
			camera = { side = -9, up = 16, back = 15, yaw = 25, pitch = -16, follow = 0, fov = 70 },
			-- the bed and its ring gear first, then the carriage, the cradle, the barrel, the breech and the crystal last
			assembly = {
				{ names = { "Bed", "RingGear" }, at = 0 },
				{ names = { "Mount", "Traverse", "Elevation" }, at = 1 },
				{ names = { "Cradle" }, at = 2 },
				{ names = { "Barrel", "Bore" }, at = 3 },
				{ names = { "Breech", "Crystal" }, at = 4 },
			},
		} :: Gun,
		-- The MG nest's machine gun (user 2026-10-27, design approved by the user; user 2026-10-28: "can we use this
		-- machine gun instead?"): an M2 Browning on its M3 tripod (tools/blender/mgnest/m2.py, a 3D trace of Ajay
		-- Kumar's Sketchfab model in our style; was the MG 08, tools/blender/mgnest/mg08.py), no shield, its ammo can
		-- standing on the mount bags; built by the shovel in an MG nest (Config/Build.Nest), set up in quarters
		-- (`assembly`). Gun space: the origin 1.9 over the ground (Build.Nest.bagTop) under the pivot. (Its key is still
		-- mg08: Config/Build and Damage name it.) The shell fields below are kept only so it is a Gun.
		mg08 = {
			asset = "mg08",
			name = "M2 Browning",
			nest = true,
			nestGround = { lo = { -0.5, -0.5 }, hi = { 0.5, 0.5 } },
			base = "Carriage",
			mount = mgMount, -- (and each round on the belt: beltOf above)
			-- the ammo can and the belt in it turn with the gun now (in `mount`; user 2026-11-03: "make the mgnest a 360
			-- nest": was standing still on the mount bag so it wouldn't clip the old nest's high front bags); the belt's
			-- rounds bend from it to the feed (src/client/Artillery)
			fixed = {},
			cradle = { "Cradle", "CradleTrim", "CradleFittings" },
			barrel = { "Barrel", "Bore" },
			breech = {},
			trunnion = { 0, 1.035, 0 },
			hinge = { 0, 1.035, 0 },
			muzzle = { 0, 1.25, -4.226 },
			boreCentre = 0.009,
			-- (user 2026-11-03: "make the mgnest a 360 nest, so the sandbags would just be a 1 layer circle"; was 70 each
			-- way, 140 in all): right round, its gunner walking round with it (`crewTurns`), the gun and its shots over the
			-- one-bag ring all the way (Config/Build.Nest `ring`, `fit`; Rules/Build.nestFit)
			traverse = 180,
			-- (user 2026-11-03, the 360 nest: "make it spin from the mount", "be sure the center of the nest is the point
			-- where it spins"): on the tripod head's pintle, gun space's origin (the head's top measured on the model at
			-- x 0, z 0; the Mount's box middle, 0.43 back, swung it off centre), which stands at the ring's middle
			-- (Config/Build.Nest `gunBack`)
			pintle = { 0, 0 },
			elevation = { -8, 10 },
			swing = 0.001, -- (it never swings past its stops: the nest holds it)
			-- (user 2026-11-03, the 360 nest: "the gun turning controls are weird"; was 60): swung by hand on its pintle, it
			-- keeps up with the mouse
			traverseRate = 240,
			elevationRate = 40,
			speed = 900,
			gravity = 196.2,
			charge = 0,
			breechOpens = false,
			kg = 0.01,
			reload = 12, -- (the box reload, the design's long wait)
			breechOpen = 0,
			breechTimes = { 0, 0 },
			-- (recoil-operated: the barrel and lock kick back each shot; user 2026-11-01: "make sure the recoil for the
			-- barrel of the mg nest it visible ... make it look visual and match the firerate"; was 0.12 over 0.07 s,
			-- too small and quick to see): back in 0.015 s, home again just before the next round (0.133 s at 450)
			recoil = 0.3,
			recoilTimes = { 0.015, 0.105 },
			-- (user 2026-10-29: "make the barrel get warmer from the tip as you hold it (steam a little too)"): glowing
			-- at the tip from the first rounds, creeping back half the barrel (2 of its ~4.1 studs out of the receiver),
			-- all of it hot after ~50 rounds held, cool again ~20 s after; steam past 0.4
			heat = { per = 0.02, cool = 0.05, length = 2.0, radius = 2.75, segments = 8, steam = 0.4, steamRate = 16 },
			-- (user 2026-10-29: "add some recoil animation to both the gun and the player"): a short shove each round
			kick = { arms = 5, torso = 1.5, time = 0.1 },
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
			-- the sight line at y 1.71)
			mg = {
				rate = 450,
				-- (user 2026-11-01: "one click is one shot. two shouldnt come out at once, two shouldnt be fired
				-- sequenttially either"): a click let go within this gives that one shot; held longer, full auto
				tap = 0.25,
				box = 100,
				range = 600, -- (as far as a rifle shot: Config/Firing.Range, the fog)
				class = "MachineGun",
				spread = { min = 0.6, max = 1.5, per = 0.06, recover = 0.3 }, -- (hot after ~50 rounds held, cool ~3 s after)
				-- the gunner's pose while manning it (tools/animation/mg.luau MGStand, a loop; user 2026-10-28: "make it
				-- standing and ready"): standing behind it, hands on the spade grips; `low` and `high` with the hands
				-- where the grips are at its lowest and highest lay, blended in by the lay (Rules/Artillery.mgStand)
				stand = { level = 90383747593412, low = 75408750546932, high = 82573864374660 },
				-- the box reload (the gun's `reload` s; user 2026-10-27: "the ammo bag as part of the reload animation";
				-- tools/animation/mg.luau MGReload, Rules/Artillery.mgReloadShows): seconds into it the empty box comes
				-- off its tray (`lift`, in the hands) and is put down (`drop`), the full one is taken up (`take`, Config/
				-- Assets `box`, held by its handle's `grip`) and set on the tray (`set`), its belt fed in (`fed`); the
				-- belt's rattle into the feed block (Pro Sound Effects "Machine Gun 20") as it is fed
				reload = {
					animation = 108385355006568,
					lift = 1.2,
					drop = 2.6,
					take = 3.7,
					set = 5.3,
					fed = 7,
					box = "m2_box",
					grip = { 0.087, 1.34, 0 },
					-- (Pro Sound Effects; user 2026-11-01, the sounds picked by the user from a listening page, in this order):
					-- each on its move in the animation (tools/animation/mg.luau MGReload), a list layering its sounds
					-- (src/client/SoundFx): the cover unlatched with the slam's latch, the empty can's rattle whole from just
					-- before the lift (it was cut to its last 0.04 s), the full can set down, the belt's tab lifted, fed through
					-- jingling (was "Machine Gun 20", a gunshot heard 2400 studs off) and seated, the cover slammed, the
					-- charging handle racked on both pulls, and a last rack as the hands are back on the grips: the gun is ready
					sounds = {
						-- Top cover unlatched ("Metal Latches 12")
						{
							at = 0.5,
							sound = { id = 9116729170, volume = 0.9, stop = 0.4, fade = 0.1, profile = "Mechanism" },
						},
						-- Empty can lifted off ("Ammo Box Movement 1")
						{ at = 1, sound = { id = 9113102913, volume = 1.6, profile = "Mechanism" } },
						-- Full can set on the tray ("Shield Impacts 17")
						{
							at = 5.3,
							sound = { id = 9119075617, volume = 0.9, pitch = 0.8, stop = 0.4, profile = "Mechanism" },
						},
						-- Belt tab lifted ("Chain Rattle Glassy Metal Rattle 4")
						{
							at = 5.5,
							sound = { id = 9113763639, volume = 0.35, stop = 0.9, fade = 0.2, profile = "Mechanism" },
						},
						-- Belt fed through ("Dog Tags Rattles Metal Jingle")
						{
							at = 6.1,
							sound = {
								id = 9125490846,
								volume = 0.55,
								start = 0.1,
								stop = 1.5,
								fade = 0.3,
								profile = "Mechanism",
							},
						},
						-- Belt seated in the feed ("Machine Gun Movement 1")
						{ at = 7, sound = { id = 9116362330, volume = 1.5, profile = "Mechanism" } },
						-- Top cover slammed shut ("Metal Latches 12" + "Metal Clunks Heavy Latch Mechanism 1")
						{
							at = 7.5,
							sound = {
								{ id = 9116729170, volume = 1.2, pitch = 0.85, stop = 0.5, profile = "Mechanism" },
								{
									id = 9116545245,
									volume = 0.6,
									start = 2.2,
									stop = 2.9,
									fade = 0.2,
									profile = "Mechanism",
								},
							},
						},
						-- Charging handle racked ("Machine Gun Bolt 1")
						{ at = 8.3, sound = { id = 9116357348, volume = 3, profile = "Mechanism" } },
						-- Racked again ("Machine Gun Bolt 2")
						{ at = 9.05, sound = { id = 9116357355, volume = 1, profile = "Mechanism" } },
						-- Hands on the grips: the gun is ready ("Machine Gun Bolt 2")
						{ at = 10.7, sound = { id = 9116357355, volume = 1.2, profile = "Mechanism" } },
					},
				},
				-- (the M2's sights: 0.77 behind the rear sight's peep ring, on the line through the ring's middle and the
				-- hooded front post's tip, parallel to the bore; the MG 08's was { 0, 1.78, 2.688 })
				eye = { 0, 1.71, 2.707 },
				-- the eye at the hip, in first person (user 2026-10-28: "can you move the camera up more since the
				-- shield in the way of the camera"): over the gun, turning with the mount, not lifting with the gun.
				-- (`shield` was the MG 08 shield's top and face; the M2 has none, and nothing reads it)
				over = { 0, 2.95, 2.44 },
				shield = { top = 2.65, z = 0.36 },
				-- over the shoulder: the camera's offset right and up from the gunner's head (as Config/Camera.Gun
				-- Shoulder; user 2026-10-28: "fix the MG's third-person camera so the gun shows past the standing
				-- gunner"): wide and high enough that the line down to the gun passes over the right shoulder
				shoulder = { 2.5, 1 },
				look = 0.12,
				-- right round (`traverse` 180): the mouse's aim runs at most this many degrees ahead of the gun
				-- (Rules/Artillery.mgLay)
				lead = 45, -- (20 lost mouse motion once the lay it sees comes 0.2 s late)
				-- the report (Pro Sound Effects "Rifle Single Shots 1", a heavy single shot, its crack and first boom: one
				-- a round, 7.5 a second, so the tail is cut short before the take's metal clink at 0.6 s (Studio: loud
				-- to 0.06 s, mostly gone by 0.45); was the rifles' shot as a placeholder)
				shot = { id = 9118173739, volume = 1.6, stop = 0.5, fade = 0.25, profile = "Gunshot" },
				-- (user 2026-10-29: "find better sound effects for the machine gun"): the shot above is a Barrett M82's,
				-- a real .50; under it a huge 12-gauge blast pitched well down for the heavy gun's thump (Pro Sound Effects
				-- "Gun Live Ammunition 5", Remington 870), each round a little different
				boom = { id = 9114724430, volume = 0.8, pitch = 0.6, stop = 0.45, fade = 0.2, profile = "Gunshot" },
				vary = 0.04,
				-- (user 2026-10-29: "make the ammo box have a jingle sound"): a quick rattle of the can as each round
				-- goes in (Pro Sound Effects "Ammo Box Movement 1")
				jingle = {
					id = 9113102913,
					volume = 0.25,
					pitch = 1.1,
					start = 0.5,
					stop = 0.75,
					fade = 0.1,
					profile = "Mechanism",
				},
				-- the G98's round (7.92x57 S, ~890 m/s from a 720 mm barrel): as recorded, the crack a little up; heard far off
				-- and going by as a rifle (src/client/ShotAudio: late, the far report, echoes off what stands round)
				report = { pitch = 1, eq = { 0, 0, 2 } },
				-- (user 2026-10-29: "some camera shake too"; small: 7.5 kicks a second, no fight with aiming)
				shake = 0.35,
				shakeReach = 25,
				-- (user 2026-10-29: "shell case droppings and sounds"): fed from the right, the M2 drops its spent case
				-- out of the bottom of the receiver and throws the empty link out of its left side. The case leaves just
				-- behind the tripod's head, a little back and left (straight down under the receiver it landed hidden
				-- under the head, user 2026-10-29: "its not dropping the shell"), and rolls off the mount bags.
				spent = {
					case = {
						part = "Rounds01",
						at = { 0, 0.8, 1.1 },
						push = { -1.2, -2.5, 2 },
						scatter = 1,
						sound = "Heavy",
					},
					link = {
						part = "Links01",
						at = { -0.34, 1.39, 0.45 },
						push = { -5, 1.5, 0.5 },
						scatter = 0.8,
						sound = "Link",
					},
				},
			},
			camera = { side = 0, up = 1.8, back = 4.5, yaw = 0, pitch = 0, follow = 0.5, fov = 70 },
			-- (the gunmetal body and the belt, not the team's paint: the tripod and its head take it)
			colors = mgColors,
			-- (user 2026-10-27, the stage design: "sled-gun-shield-box order"; the M2 has no shield): the tripod, the
			-- gun, the ammo can, then its belt last, each appearing in place in its quarter (user 2026-10-28: "not all
			-- the parts have to be present before its built (all the other structures work this way too). they can just
			-- appear as its being built")
			assembly = {
				{ names = { "Carriage", "Mount" }, at = 1 },
				{ names = { "Cradle", "Barrel", "Bore" }, at = 2 },
				{ names = { "Box" }, at = 3 },
				{ names = { "Belt", "Rounds", "Bullets" }, at = 4 },
			},
		} :: Gun,
	},
}

return table.freeze(Artillery)
