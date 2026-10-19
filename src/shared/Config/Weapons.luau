--!strict
-- Weapons (.claude/skills/roblox-weapons/SKILL.md). Every position is in gun space, in studs, relative to the
-- export's Origin marker (the gun origin, at the trigger): +X right, +Y up, -Z toward the muzzle.
-- Aiming contract: the Aim camera and the bullet both travel along gun -Z, so the line of sight is parallel to the
-- line of fire and the shot lands one sight height (Aim.y - Muzzle.y) below the point of aim at every range.

export type Weapon = {
	asset: string, -- Config/Assets entry (the uploaded model)
	display: string,
	-- Loadout slot: a soldier carries one weapon per slot, given at spawn and kept for the life (src/server/Armory).
	-- "Primary" = the main long gun (one primary at a time, user 2026-10-11).
	slot: string,
	-- Item class (docs/HOLD_AND_CAMERA_RULES.md §1; weights in Config/Sway.Classes): the motion and, later, the holds
	-- every item of the class shares.
	class: string,
	parts: { [string]: { number } }, -- flat color per mesh part
	moving: { [string]: { number } }, -- Motor6D pivot per moving part (the rest is welded)
	hidden: { string }, -- template parts, invisible on the weapon (cloned at runtime)
	attachments: { [string]: { number } },
	grip: { number }, -- where the right hand holds (the wrist behind the trigger guard)
	-- Hold animations while the weapon is in the hands (tools/animation/rifle.luau; src/client/Locomotion picks one):
	-- ready (standing), walk (walking: keeps step with the legs), carry (sprinting: keeps step too), aim (aiming down
	-- the sights), equip (one shot: drawn from the sling on the back). Both arms reach for the gun.
	-- Crouched (crouchReady / crouchWalk / crouchAim): the same holds for the crouched torso.
	-- holdsOf: the weapon these holds were built for, when borrowed (aimed, src/client/Viewmodel moves the rig by the
	-- difference between the two weapons' Aim, so this one's own sights sit on the eye)
	-- Only ready and equip are required: a hold an item doesn't have plays its ready instead (src/client/Locomotion,
	-- src/client/Viewmodel), and an item without `aim` (no sights: the staff) can't be aimed (src/client/Stance).
	holdsOf: string?,
	holds: {
		ready: number,
		walk: number?,
		carry: number?,
		aim: number?,
		equip: number,
		unequip: number?, -- put away (Config/Locomotion.Stow)
		crouchReady: number?,
		crouchWalk: number?,
		crouchAim: number?,
		-- the staff (src/client/StaffAttack): aimTwo, the two-handed aim once the left hand has joined ("TwoHands");
		-- charge, a one shot played with its time set to how long the cast has been held ("CastHeld")
		aimTwo: number?,
		charge: number?,
		airCharge: number?, -- the charge while floating in the air (leaning back)
		-- the same two started with both hands already on the staff ("ChargeTwo": after a stage 2 shot)
		chargeTwo: number?,
		airChargeTwo: number?,
		-- a grenade (src/client/Grenades): windup, held while the throw's line shows ("Winding"); throw, a one shot from
		-- it played on release ("ThrownAt"; the grenade leaves the hand Config/Grenades.Throw.release into it)
		windup: number?,
		throw: number?,
	},
	-- The first-person holds (user 2026-10-11): played only on the player's own client, on a viewmodel (a copy of the
	-- arms and the weapon fixed to the camera, src/client/Viewmodel); others see `holds` on the body. Walking and
	-- running motion comes from the sway layer (Config/Sway), not from extra animations. aimIn: a brief one shot each
	-- time aiming starts, the gun coming up into the sights over the aim hold (user 2026-10-11).
	firstPerson: {
		ready: number,
		carry: number?,
		aim: number?,
		equip: number,
		unequip: number?,
		aimIn: number?,
		aimOut: number?, -- the aim-in backwards, letting go of aim (A1 2026-10-18)
		aimTwo: number?,
		charge: number?,
		chargeTwo: number?,
		windup: number?,
		throw: number?,
	},
	-- The staff's third-person recoils (one shots over the hold fired from; src/client/StaffAttack): quick from the hip,
	-- quickAim / quickTwo aimed with one or two hands, medium / mediumTwo the stage 2 shot; on the first-person
	-- viewmodel: firstQuick the hip quick fire, firstQuickAim / firstQuickTwo the aimed one (one hand / two).
	fire: { [string]: number }?,
	-- First person (src/client/Viewmodel): at the hip the weapon turns about the eye until its line meets the screen
	-- centre this far out (default Config/Camera.HipConverge; 0 = no turn); aimed, aimConverge does the same (none
	-- by default: a gun's sights are on the eye).
	hipConverge: number?,
	aimConverge: number?,
	-- First person: the whole viewmodel (arms and item) moved this far in camera space (+X right, +Y up, -Z forward), for
	-- an item posed by holds made for another (the grenades on the staff's holds: Studio round 2 had the hand and
	-- grenade below and behind the camera).
	firstShift: { number }?,
	-- Where the item's origin sits from the hold's "Gun" point (game studs, gun space): the "Hold" motor's C1
	-- (src/server/Armory, src/client/Viewmodel). The Mills and SIPE sat inside the fist (Studio round 3): pushed out in
	-- front of it.
	held: { number }?,
	-- Where the eye (the Aim attachment) sits in the third-person aim hold, in the soldier's upright frame (studs from
	-- the torso centre: +X right, +Y up, -Z forward; the torso centre is 3 above the feet). tests/weapons.spec checks
	-- the muzzle against Metrics. Sighted weapons only.
	shouldered: { number }?,
	-- Size in game relative to the model, per gun axis { x width, y height, z length }: the blocky R6 soldier carries
	-- chunky, Pordier-style weapons, thick next to the 1-stud arm (the hand closes round a stock about half its size)
	-- but only about as long as the soldier is tall, so the cross-section scales more than the length. Every
	-- gun-space number in this entry is the modelled one; Armory scales them.
	scale: { number },
	-- Where the weapon rides on the body when it isn't equipped (src/server/Armory, everyone sees it). In `part`'s
	-- space (R6 Torso: +X right, +Y up, front -Z, back face at z +0.5): `at` is the gun origin, `muzzle` the way the
	-- muzzle points, `side` the way the gun's right side (+X, the bolt handle) faces.
	-- None: nothing shows on the body while it's put away (the grenades).
	stow: { part: string, at: { number }, muzzle: { number }, side: { number } }?,
	-- Shooting (Config/Firing, Rules/Firing): rounds per clip and how the clip loads ("Enbloc": the whole clip goes
	-- into the magazine and drops out the bottom when empty, only reloaded empty; "Stripper": the rounds are pushed
	-- down out of a clip held in the guides, topping the magazine up). Guns only: an item without `ammo` doesn't fire
	-- (src/client/Firing, src/server/Firing) and has no action, reload or bolt either.
	ammo: { capacity: number, clip: string }?,
	-- The action, worked by hand (seconds; turn in degrees, travel in modelled studs): the bolt turns its handle up
	-- by `turn` about its axis (gun Z), then slides back `travel` (+Z) and returns.
	-- fireTime: after a shot nothing else can start for this long (else Config/Firing.FireTime); cycle: this weapon's
	-- own bolt timeline (else Config/Firing.BoltCycle; `hold`: the bolt / pump rests back until then before it goes
	-- forward).
	action: {
		boltTime: number,
		reloadTime: number,
		turn: number,
		travel: number,
		fireTime: number?,
		cycle: { reach: number, up: number, back: number, hold: number?, forward: number, down: number }?,
	}?,
	-- The reload (Config/Firing.ReloadCycle; user 2026-10-13): where the right hand works, in modelled gun space, and
	-- the weapon's own reload animations (tools/animation/reload.luau). knob: the bolt handle's knob, bolt closed;
	-- clipTop: the top of the clip when seated (a stripper clip in the guides, an en-bloc clip in the magazine), where
	-- the thumb pushes; entry: an en-bloc clip is set this far above its seat and pushed down into the magazine (0: a
	-- stripper clip sits in the guides and only its rounds go down). body / firstPerson: the animation ids (0 until
	-- uploaded).
	reload: {
		knob: { number },
		clipTop: { number },
		entry: number,
		body: number,
		firstPerson: number,
	}?,
	-- Working the bolt after a shot, third person (user 2026-10-13; tools/animation/bolt.luau): the right hand goes from
	-- the grip to the knob (reload.knob) and works it; `aim` with the rifle shouldered, `ready` at the hip (any other
	-- hold). 0 until uploaded. First person (the rifles: tools/animation/bolt.luau; a pump gun's pump:
	-- tools/animation/pump.luau), played on the viewmodel: `firstAim` aimed, `firstReady` otherwise.
	bolt: { aim: number, ready: number, firstAim: number?, firstReady: number? }?,
	-- Loading single rounds (stripper-clip rifles with rounds left; Config/Firing.Single, tools/animation/single.luau):
	-- seat, where a round goes in (its centre pushed onto the top round, modelled gun space); the animation ids.
	-- open / round / close: this weapon's own times (else Config/Firing.Single's).
	single: { seat: { number }, body: number, firstPerson: number, open: number?, round: number?, close: number? }?,
	-- A shotgun's shot (user 2026-10-13): `count` pellets in a cone `spread` degrees wide (half angle), each its own
	-- hitscan ray; full damage to `full` studs, none past `none` (stored for damage, M11: not applied yet).
	pellets: { count: number, spread: number, full: number, none: number }?,
	-- An exposed hammer (the "Hammer" part, src/client/GunFx): rests cocked, falls `cock` degrees forward on a shot;
	-- the bolt going back pushes it down again, `push` giving how far cocked (0..1) at evenly spaced shares of the
	-- stroke, so the bolt never goes through it (computed by the model's builder, which prints it).
	hammer: { cock: number, push: { number } }?,
	-- A pump gun's feed (src/client/GunFx): the shell lying on the carrier (parts `parts`, at rest under the bolt)
	-- lifts `lift` to the bore line and goes `push` forward into the chamber as the pump comes forward; shown while the
	-- magazine has shells. The "Pump" part slides with the bolt (action.travel back).
	feed: { parts: { string }, lift: number, push: number }?,
	-- The parts thrown out of the port after a shot, as one piece (else { "Casing" }).
	eject: { string }?,
	-- Part colors per kit (Config/Uniforms.Kits; user 2026-10-13: "slight coloring differences per team"), over `parts`.
	kits: { [string]: { [string]: { number } } }?,
	-- This weapon's own sounds, over Config/Firing.Sounds (same fields: id, volume, start, stop, fade); Equip / Unequip
	-- (src/client/SoundFx entries, with a falloff `profile`) play on drawing and putting it away.
	sounds: { [string]: { [string]: any } }?,
	-- Recoil (src/client/Sway): `scale` times Config/Firing.Recoil; each shot within `cool` seconds of the last kicks
	-- `build` times harder per shot still "hot", up to `max` times (user 2026-10-13: the view sways worse each shot).
	recoil: { scale: number, build: number, max: number, cool: number }?,
}

-- The mage staff (docs/VFX.md; model tools/blender/weapons/staff.py, exported by export_staff.py): carried like the
-- rifles (user 2026-10-13: "carry the staff the same way weapons are being carried ... they should share code"),
-- one Primary at a time, slung on the back when put away. Gun space: the origin is the iron sleeve's centre, where
-- the right hand holds; the head points down -Z. No ammo, sights or moving parts.
-- A variant per team (user 2026-10-13: "coloring different variants per team ... make accents on the staff and color
-- the staff how you see fit"): one model (asset "staff"), its parts colored from the team's own gear: Wood, Iron
-- (sleeve + foot cap), Accent (the grip's band + the ring under the head), Wrap (the cloth binding under the head),
-- Ribbon (knotted at the binding's foot).
local function staff(display: string, colors: { [string]: { number } }): Weapon
	return {
		asset = "staff",
		display = display,
		slot = "Primary",
		class = "Staff",
		parts = colors,
		moving = {},
		hidden = {},
		attachments = {
			-- the head's top, along the shaft: the first-person hip turn points this line at the screen centre (user
			-- 2026-10-13: the staff points where the crosshair would be); later where the spells leave
			Muzzle = { 0, 0, -2.25 },
		},
		grip = { 0, 0, 0 }, -- the middle of the iron sleeve
		-- user reference 2026-10-13 (Fern, Frieren): idle and walking, low in the right hand at the hip, the shaft
		-- running front to back with the head forward; the left arm free (tools/animation/staff.luau)
		-- equip: off the back over the right shoulder (like the rifles'); carry: low at the side while sprinting (no
		-- firing); aim: the right arm out, the staff level at chest height; aimTwo: both hands, in front of the chest;
		-- charge: drawn back more and more, the left hand joining halfway to stage 3 (src/client/StaffAttack); no crouch
		-- holds yet (the ready plays)
		holds = {
			ready = 119234625003629,
			walk = 138414232252986,
			carry = 112870868696570,
			aim = 88831510650616,
			aimTwo = 86681465612273, -- at the right side (user 2026-10-19: "make sure the staff is on our right side")
			charge = 103451564817751, -- the arms shake more and more, and keep shaking once ready (user 2026-10-13)
			airCharge = 128965516186736, -- in the air (floating): leaning back as it charges
			-- charging with both hands already on (user 2026-10-13: it went back to one hand first)
			chargeTwo = 111875640876355,
			airChargeTwo = 120791575488143,
			equip = 105902337487636,
			unequip = 130701792854486, -- put away onto the back (Config/Locomotion.Stow)
		},
		-- first person: low on the right, the right forearm rising from the corner, the head turned onto the centre;
		-- aimed (cinematic, user 2026-10-13): thrust out low on the right; the recoil is the sway layer's kick
		firstPerson = {
			ready = 126446372546704,
			carry = 86383295329379,
			aim = 96292870185836,
			aimIn = 117766595310610,
			aimTwo = 139107991867244,
			charge = 108466726703676,
			chargeTwo = 121381197496636, -- with both hands already on
			equip = 80156061468327,
			unequip = 79165303145977,
		},
		-- first person: standing angled up at the hip (no turn: user 2026-10-13 "upright more ... arms down hands on
		-- the side"); aimed, its line turned onto the crosshair so the cast's circles sit on it (user: "the staff in line
		-- with the center of the circle")
		hipConverge = 0,
		aimConverge = 60,
		fire = {
			quick = 75953489387448,
			quickAim = 101856301139598,
			quickTwo = 71779282009224,
			medium = 73692498139809,
			mediumTwo = 139254316829053,
			-- first person, the hip quick fire: a jab of the head toward the crosshair, settling through the cooldown
			firstQuick = 80861609176406,
			-- first person, aimed quick fire: a slight recoil, one hand or both (user 2026-10-13: "when ADS it should just
			-- be a slight recoil")
			firstQuickAim = 85129262859161,
			firstQuickTwo = 80242360718588,
		},
		scale = { 1, 1, 1 }, -- modelled in studs at game size (5.3 long, the sleeve 0.43 across)
		-- drawn and put away (src/client/Locomotion, user 2026-10-14): a wooden swish ("Wood Swish Ruler Whoosh Fast
		-- Movement In Air", Pro Sound Effects; src/client/SoundFx entries)
		sounds = {
			Equip = { id = 9126283592, volume = 0.6, start = 0.05, profile = "Hum" },
			Unequip = { id = 9126283272, volume = 0.6, profile = "Hum" },
		},
		-- slung on the back like the rifles (the same lean), higher up: the foot clears the ground and the head rises
		-- over the right shoulder
		stow = {
			part = "Torso",
			at = { 0.3, 0.6, 0.75 },
			muzzle = { 0.309, 0.9511, 0 }, -- sin 18, cos 18
			side = { 0, 0, 1 },
		},
	}
end

local Weapons: { [string]: Weapon } = {
	-- The shotgun of all three teams (docs/MILESTONES.md W1, user 2026-10-13): one model, the wood tinted per team
	-- (`kits`). The pump is worked by the next click like a bolt (the "Bolt" action: no turn, the pump and bolt slide
	-- back `travel` and forward, the shell on the carrier lifts into the chamber); shells go in one at a time through
	-- the loading port under the receiver, 5 + 1, topping up any time without opening the action (ammo.clip "Loose").
	shotgun_m1897 = {
		asset = "shotgun_m1897",
		display = "Winchester M1897",
		slot = "Primary",
		class = "Shotgun",
		-- the photo's colors (user: "the colors of the top shotgun"), the shell like the helmet bands' shells
		parts = {
			Wood = { 112, 64, 60 },
			Pump = { 78, 46, 44 },
			Metal = { 104, 92, 96 },
			Receiver = { 116, 117, 126 },
			Bore = { 3, 3, 3 },
			Bolt = { 132, 132, 138 },
			Hammer = { 96, 95, 93 },
			Trigger = { 96, 95, 93 },
			Shell = { 150, 54, 44 },
			ShellHead = { 176, 146, 80 },
		},
		kits = {
			uniform1 = { Wood = { 88, 56, 48 }, Pump = { 62, 40, 36 } }, -- grey: dark walnut
			uniform2 = { Wood = { 120, 78, 52 }, Pump = { 86, 56, 38 } }, -- olive: warm brown
		},
		moving = {
			Pump = { 0, -0.0245, -0.9398 }, -- slides back the stroke and forward
			Bolt = { 0, 0.0755, -0.3501 }, -- the slide in the receiver's top: back with the pump, out over the wrist
			Hammer = { 0, 0.0281, -0.0395 }, -- its pin: rests cocked, falls 90 deg forward on a shot
			Trigger = { 0, -0.0877, -0.029 }, -- the trigger pin
			Shell = { 0, 0.0229, -0.1448 }, -- the shell on the carrier (its head)
			ShellHead = { 0, 0.0229, -0.1448 }, -- moves with it
		},
		hidden = {},
		attachments = {
			Muzzle = { 0, 0.065, -1.7735 }, -- the bore on the mount's front face: pellets' origin, flash
			Aim = { 0, 0.1071, 0.45 }, -- the eye, on the sight line: the bead in the rear sight's notch
			Eject = { 0.052, 0.0597, -0.2369 }, -- the ejection port, right side
		},
		grip = { 0, -0.09, 0.17 }, -- the wrist of the straight stock, behind the guard
		-- its own holds (tools/animation/rifle.luau, user 2026-10-13): the rifles' poses, the left hand on the pump
		holds = {
			ready = 123307446642086,
			walk = 74378124906474,
			carry = 122181109482392,
			aim = 114865521572329,
			equip = 96966780660102,
			unequip = 106479819126650, -- put away onto the back (Config/Locomotion.Stow)
			crouchReady = 125201661584426,
			crouchWalk = 88611640240958,
			crouchAim = 81699754378349,
		},
		firstPerson = {
			ready = 119185102113053,
			carry = 124660991401505,
			aim = 85472517302410,
			equip = 86411519760958,
			unequip = 92360338634937,
			aimIn = 108346522950809,
			aimOut = 118548838358261,
		},
		-- the hammer lies back in its slot (user 2026-10-13: "the hammer is clipping into the shotgun"); push from
		-- tools/blender/weapons/m1897.py (its ends set to 0 and 1: the bolt's face only touches the fallen hammer)
		hammer = {
			cock = 115,
			push = {
				0,
				0.16,
				0.25,
				0.395,
				0.57,
				0.745,
				0.825,
				0.895,
				0.955,
				0.97,
				0.975,
				0.975,
				0.975,
				0.975,
				0.975,
				0.975,
				0.975,
				0.975,
				0.975,
				0.975,
				1,
			},
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the rifles: 2.79 -> 4.19 studs long
		stow = {
			part = "Torso",
			at = { 0.5, -0.04, 0.71 },
			muzzle = { 0.309, 0.9511, 0 },
			side = { 0, 0, 1 },
		},
		ammo = { capacity = 5, clip = "Loose" }, -- 5 in the tube + 1 (user 2026-10-13)
		-- the pump: no turn, the stroke 3 1/4 in (the trace's 88 px); reloadTime unused (loose shells only). Slowed
		-- (user 2026-10-13: "slow down the fire rate ... put delays between stuff"): a beat after the shot before the pump
		-- can start (fireTime), the hand settles on the pump before it pulls (up), the pump rests back a moment
		-- (back .. hold), then forward.
		action = {
			boltTime = 1.0,
			reloadTime = 0,
			turn = 0,
			travel = 0.232,
			fireTime = 0.4,
			cycle = { reach = 0.15, up = 0.3, back = 0.5, hold = 0.62, forward = 0.84, down = 0.92 },
		},
		-- Creator Store placeholders like the rifles' (user 2026-10-13: "something more fitting"): "Shotgun Close Shot"
		-- (ChipTheTrainer2, the rifle shot's creator; no lead-in silence), "shotgun pump back" / "shotgun_pump_forward",
		-- "Shotgun Shell Insert 3 (SFX)" (YuvoNet)
		sounds = {
			Shot = { id = 94645072637721, volume = 2.5 },
			BoltOpen = { id = 126161725690062, volume = 0.9 },
			BoltClose = { id = 112863196810371, volume = 0.9 },
			ClipIn = { id = 128059899217728, volume = 0.8 },
			-- heard far off (src/client/ShotAudio): "Gun Live Ammunition 1" (Pro Sound Effects, a Mossberg 12 gauge
			-- "Distant and Low Angle"), cut before the pump's cocking; pellets whiz by: "Bullet Whiz 1 / 2"
			Far = {
				{ id = 9114710159, volume = 1.6, stop = 1.4, fade = 0.6 },
				{ id = 9114712952, volume = 1.6, stop = 1.25, fade = 0.5 },
			},
			Pass = {
				{ id = 9113634361, volume = 1, lead = 0.04 },
				{ id = 9113634444, volume = 1, start = 0.1, lead = 0.18 },
			},
		},
		-- a heavier kick than a rifle's, worse with every quick shot (user 2026-10-13)
		recoil = { scale = 1.6, build = 0.45, max = 2.8, cool = 1.8 },
		pellets = { count = 9, spread = 3, full = 42, none = 140 }, -- 15 m / 50 m at 0.357 m per stud
		feed = { parts = { "Shell", "ShellHead" }, lift = 0.042, push = 0.211 },
		eject = { "Shell", "ShellHead" },
		-- the pump worked (tools/animation/pump.luau): the left hand rides it back and forward
		bolt = {
			aim = 79121681696081,
			ready = 103141305409594,
			firstAim = 123068697692331,
			firstReady = 126610154264357,
		},
		-- shells go in through the loading port under the receiver (seat: a shell there, pushed up into the tube); the
		-- action stays shut, so no time to open it
		single = {
			seat = { 0, -0.05, -0.2 },
			body = 84714499624328,
			firstPerson = 83892112156051,
			open = 0.35, -- slower (user 2026-10-13)
			round = 0.6,
			close = 0.4,
		},
		reload = { knob = { 0, -0.0245, -0.9398 }, clipTop = { 0, -0.05, -0.2 }, entry = 0, body = 0, firstPerson = 0 },
	},
	rifle_m91 = {
		asset = "rifle_m91",
		display = "Carcano M91",
		slot = "Primary",
		class = "BoltRifle",
		parts = {
			Wood = { 142, 74, 42 },
			Handguard = { 142, 74, 42 },
			Metal = { 52, 54, 58 },
			Bolt = { 70, 70, 74 },
			Trigger = { 52, 54, 58 },
			Clip = { 90, 88, 84 },
			Rounds = { 196, 160, 84 },
			Casing = { 196, 160, 84 },
			Bore = { 3, 3, 3 },
		},
		moving = {
			Bolt = { 0, 0.065, -0.1511 }, -- on the bolt's axis, at the handle
			Trigger = { 0, -0.086, -0.006 }, -- the trigger pin
			Clip = { 0, -0.027, -0.267 }, -- the en-bloc clip in the magazine
			Rounds = { 0, -0.027, -0.267 }, -- moves with the clip
		},
		hidden = { "Casing" },
		attachments = {
			Muzzle = { 0, 0.0717, -2.483 }, -- bore axis at the muzzle face: bullet origin, flash
			Aim = { 0, 0.1186, 0.45 }, -- the eye (cheek on the comb), on the sight line: post tip + notch
			-- where the case leaves: in the open receiver at the bolt face pulled back (rest z -0.46 + travel 0.3), the case
			-- just in front of it (user 2026-10-12: it came out too far forward, at the receiver ring); right side, +X/+Y
			Eject = { 0.03, 0.075, -0.21 },
		},
		grip = { 0, -0.06, 0.15 },
		-- user references 2026-10-11: ready low in front of the stomach, sprint carried across the body, aim shouldered;
		-- ready and aim breathe like Roblox's R6 idle (user: match the default sway)
		holds = {
			ready = 78002721137460,
			walk = 124889771920224,
			carry = 105709189619828, -- swings with the sprint
			aim = 136351549623920,
			equip = 116169498023535,
			unequip = 114673290829081, -- put away onto the back (Config/Locomotion.Stow)
			crouchReady = 92303129713125,
			crouchWalk = 87132266042623,
			crouchAim = 104754199810093,
		},
		-- carry: port arms (user reference video); equip: over the right shoulder from behind the camera; aimIn: from
		-- the ready hold up into the sights in 0.3 s
		firstPerson = {
			ready = 120415429367250,
			carry = 107781105123018,
			aim = 94444327606653,
			equip = 105963460001801,
			unequip = 102151639999018,
			aimIn = 111730503877557,
			aimOut = 81283833297555,
		},
		-- the comb at the right cheek, the eye 4.45 above the feet: muzzle ~4.33 (Metrics AimMuzzleHeight ~4.3)
		shouldered = { 0.4, 1.45, -0.6 },
		-- 2.5x thicker, 1.5x longer (user 2026-10-11: way too small next to the arm): 3.51 -> 5.27 studs long, stock
		-- 0.36 wide, forend ~0.3 thick, butt ~1 stud (the arm's width)
		scale = { 2.5, 2.5, 1.5 },
		-- slung on the back (user references 2026-10-11): flat against the back with the bolt handle out, leaning
		-- 18 degrees so the thick stock stays inside the torso's width (butt at the upper thigh) while the rifle
		-- passes clear of the head and rises ~1.3 studs above it over the right shoulder
		stow = {
			part = "Torso",
			at = { 0.5, -0.04, 0.71 },
			muzzle = { 0.309, 0.9511, 0 }, -- sin 18, cos 18
			side = { 0, 0, 1 },
		},
		-- its 6-round en-bloc clip: one round more than the other rifles (6 + 1), balanced by reloading only with the
		-- magazine empty (1 or 0 rounds left; user 2026-10-12)
		ammo = { capacity = 6, clip = "Enbloc" },
		-- handle mid-bolt, straight out to the right: turns up a quarter turn, the bolt slides back along the open
		-- receiver
		-- slowed (user 2026-10-13: "do the same to all the rifles"): a beat after the shot, the bolt resting back
		action = {
			boltTime = 1.25,
			reloadTime = 2.4,
			turn = 90,
			travel = 0.3,
			fireTime = 0.35,
			cycle = { reach = 0.14, up = 0.27, back = 0.45, hold = 0.55, forward = 0.76, down = 0.88 },
		},
		-- every quick shot kicks harder (user 2026-10-13: as the shotgun, gentler)
		recoil = { scale = 1, build = 0.3, max = 2, cool = 1.6 },
		-- the knob at the end of the straight handle, mid-bolt; the clip pushed down from just over the magazine
		-- v2: slower, the bolt resting back (2026-10-13); first person: the viewmodel's hand works it too (v3: the rifle lower, further out and muzzle left while it works; aimed it comes down off the eye to that)
		bolt = {
			aim = 98946190531261,
			ready = 91424552679806,
			firstAim = 71600393030717,
			firstReady = 92603270436446,
		},
		reload = {
			knob = { 0.12, 0.065, -0.1511 },
			clipTop = { 0, 0.0614, -0.267 },
			entry = 0.2,
			body = 85665510995906,
			firstPerson = 75633779262187,
		},
	},
	rifle_g98 = {
		asset = "rifle_g98",
		display = "Gewehr 98",
		slot = "Primary",
		class = "BoltRifle",
		parts = {
			Wood = { 142, 74, 42 },
			Handguard = { 142, 74, 42 },
			Metal = { 52, 54, 58 },
			Bolt = { 70, 70, 74 },
			Trigger = { 52, 54, 58 },
			Clip = { 90, 88, 84 },
			Rounds = { 196, 160, 84 }, -- the shared rifle round's brass case (tools/blender/weapons/ammo.py)
			Bullets = { 184, 115, 72 }, -- its copper-jacketed bullet
			Casing = { 196, 160, 84 },
			Bore = { 3, 3, 3 },
		},
		moving = {
			Bolt = { 0, 0.065, -0.0695 }, -- on the bolt's axis, at the handle (straight, out to the right when closed)
			Trigger = { 0, -0.0897, 0 }, -- the trigger pin
			Clip = { 0, 0.095, -0.1863 }, -- the stripper clip, in the charger guides on the rear bridge
		},
		hidden = { "Casing", "Clip" }, -- the clip shows only while reloading
		attachments = {
			Muzzle = { 0, 0.065, -2.5323 },
			Aim = { 0, 0.1218, 0.45 }, -- on the sight line: barleycorn tip + rear notch, 0.057 over the bore
			Eject = { 0.035, 0.075, -0.3031 }, -- the ejection port, right side
		},
		grip = { 0, -0.07, 0.17 }, -- the wrist of the semi-pistol grip, behind the guard
		-- its own holds (user 2026-10-13: hold each gun where appropriate), built from its grip, forend and sights
		-- (tools/animation/rifle.luau)
		holds = {
			ready = 122397590747708,
			walk = 132355293924259,
			carry = 111492198362235,
			aim = 122070726635734,
			equip = 71450535994230,
			unequip = 116812363774678, -- put away onto the back (Config/Locomotion.Stow)
			crouchReady = 81033918313470,
			crouchWalk = 79212217140130,
			crouchAim = 96381247209498,
		},
		firstPerson = {
			ready = 102402737080974,
			carry = 106294181602498,
			aim = 70722778630134,
			equip = 123066272399119,
			unequip = 126607551609403,
			aimIn = 77762769530436,
			aimOut = 109549978918090,
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the Carcano: 3.5 -> 5.25 studs long
		stow = {
			part = "Torso",
			at = { 0.5, -0.04, 0.71 },
			muzzle = { 0.309, 0.9511, 0 },
			side = { 0, 0, 1 },
		},
		ammo = { capacity = 5, clip = "Stripper" }, -- 5 rounds pushed down out of a stripper clip in the guides (5 + 1)
		-- straight handle at the rear of the bolt: turns up a quarter turn, the bolt slides back through the bridge
		action = {
			boltTime = 1.25,
			reloadTime = 2.8,
			turn = 90,
			travel = 0.27,
			fireTime = 0.35,
			cycle = { reach = 0.14, up = 0.27, back = 0.45, hold = 0.55, forward = 0.76, down = 0.88 },
		},
		-- every quick shot kicks harder (user 2026-10-13: as the shotgun, gentler)
		recoil = { scale = 1, build = 0.3, max = 2, cool = 1.6 },
		-- the knob at the end of the straight handle at the bolt's rear; the stripper clip in the guides on the bridge
		-- v2: slower (2026-10-13); first person: the viewmodel's hand works it too (v3: the rifle lower, further out and muzzle left while it works; aimed it comes down off the eye to that)
		bolt = {
			aim = 128295823529662,
			ready = 136571491377027,
			firstAim = 83372159652701,
			firstReady = 117007270529310,
		},
		-- a round goes in through the open action onto the top round (the magazine's middle round, measured)
		single = { seat = { 0, 0.035, -0.238 }, body = 81962838082410, firstPerson = 95518071079042 },
		reload = {
			knob = { 0.136, 0.065, -0.0695 },
			clipTop = { 0, 0.255, -0.1863 },
			entry = 0,
			body = 122499300440488,
			firstPerson = 131003405036443,
		},
	},
	rifle_smle = {
		asset = "rifle_smle",
		display = "Lee-Enfield SMLE",
		slot = "Primary",
		class = "BoltRifle",
		parts = {
			Wood = { 142, 74, 42 },
			Handguard = { 142, 74, 42 },
			Metal = { 52, 54, 58 },
			Bolt = { 70, 70, 74 },
			Trigger = { 52, 54, 58 },
			Clip = { 90, 88, 84 },
			Rounds = { 196, 160, 84 }, -- the shared rifle round's brass case (tools/blender/weapons/ammo.py)
			Bullets = { 184, 115, 72 }, -- its copper-jacketed bullet
			Casing = { 196, 160, 84 },
			Bore = { 3, 3, 3 },
		},
		moving = {
			Bolt = { 0, 0.065, 0.0376 }, -- on the bolt's axis, at the handle (at the bolt's rear, down to the right when closed)
			Trigger = { 0, -0.0748, 0 }, -- the trigger pin
			Clip = { 0, 0.1233, -0.1618 }, -- the charger, in the guides on the bridge
		},
		hidden = { "Casing", "Clip" }, -- the charger shows only while reloading
		attachments = {
			Muzzle = { 0, 0.065, -2.1899 }, -- flush in the nose cap, over the bayonet boss
			Aim = { 0, 0.1393, 0.45 }, -- on the sight line: blade tip + rear notch, 0.074 over the bore (the SMLE's high sights)
			Eject = { 0.035, 0.075, -0.2533 }, -- the ejection port, right side
		},
		grip = { 0, -0.05, 0.15 }, -- the wrist behind the butt socket
		-- its own holds (user 2026-10-13: hold each gun where appropriate), built from its grip, forend and sights
		-- (tools/animation/rifle.luau)
		holds = {
			ready = 80525771640790,
			walk = 114188040637314,
			carry = 119893426125614,
			aim = 112261684163473,
			equip = 99227268595174,
			unequip = 81198522446397, -- put away onto the back (Config/Locomotion.Stow)
			crouchReady = 134261827381957,
			crouchWalk = 130726353830006,
			crouchAim = 115330156920688,
		},
		firstPerson = {
			ready = 71589430224575,
			carry = 108888005264242,
			aim = 96309248783570,
			equip = 88893121669824,
			unequip = 128704204598975,
			aimIn = 117817401540584,
			aimOut = 90955676384745,
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the other rifles: 3.17 -> 4.76 studs long
		stow = {
			part = "Torso",
			at = { 0.5, -0.04, 0.71 },
			muzzle = { 0.309, 0.9511, 0 },
			side = { 0, 0, 1 },
		},
		ammo = { capacity = 5, clip = "Stripper" }, -- 5 rounds pushed down out of a charger in the guides (5 + 1); tops up
		-- the Lee's short lift (60 deg) and cock-on-closing make the fastest bolt; the bolt slides back clear of the
		-- magazine's top round
		action = {
			boltTime = 1.0, -- still the fastest bolt
			reloadTime = 2.8,
			turn = 60,
			travel = 0.28,
			fireTime = 0.35,
			cycle = { reach = 0.14, up = 0.27, back = 0.45, hold = 0.55, forward = 0.76, down = 0.88 },
		},
		-- every quick shot kicks harder (user 2026-10-13: as the shotgun, gentler)
		recoil = { scale = 1, build = 0.3, max = 2, cool = 1.6 },
		-- the knob of the bent handle at the bolt's rear, down by the wrist; the charger in the guides on the bridge
		-- v2: slower (2026-10-13); first person: the viewmodel's hand works it too (v3: the rifle lower, further out and muzzle left while it works; aimed it comes down off the eye to that)
		bolt = {
			aim = 111789507011434,
			ready = 138431199459053,
			firstAim = 133941155423925,
			firstReady = 108177354367826,
		},
		-- a round goes in through the open action onto the top round (the magazine's middle round, measured)
		single = { seat = { 0, 0.035, -0.204 }, body = 76009049286188, firstPerson = 125069294394284 },
		reload = {
			knob = { 0.11, -0.0276, 0.0376 },
			clipTop = { 0, 0.2833, -0.1618 },
			entry = 0,
			body = 101808128954188,
			firstPerson = 136400362363287,
		},
	},
	-- The mage staff, a variant per team (team colors: the staff() function above)
	staff_grey = staff("Staff (Grey)", {
		Wood = { 84, 60, 44 }, -- dark stained
		Iron = { 60, 62, 66 },
		Accent = { 204, 172, 92 }, -- the gold of the tunic's pips
		Wrap = { 80, 82, 86 }, -- the slate tunic cloth
		Ribbon = { 40, 76, 60 }, -- the green collar tab
	}),
	staff_olive = staff("Staff (Olive)", {
		Wood = { 128, 86, 52 }, -- warm natural
		Iron = { 70, 68, 58 },
		Accent = { 176, 146, 80 }, -- the uniform's brass
		Wrap = { 150, 104, 80 }, -- leather, as the helmet straps
		Ribbon = { 116, 114, 72 }, -- the olive cloth
	}),
	staff_white = staff("Staff (White)", {
		Wood = { 178, 154, 118 }, -- pale ash
		Iron = { 128, 134, 140 }, -- light steel
		Accent = { 196, 198, 204 }, -- silver
		Wrap = { 214, 214, 210 }, -- the off-white of the Brodie helmet
		Ribbon = { 150, 54, 44 }, -- red, against the white
	}),
}

-- The thrown grenades, one per team (docs/MILESTONES.md G1, user 2026-10-18; Config/Grenades for the throw and the
-- blast; models tools/blender/weapons/grenades.py): the Mills bomb No. 5 (white), the Stielhandgranate M1917 (grey),
-- the SIPE (olive), each tinted in its team's colours (user: "Team-tinted"). Their own "Grenade" slot, carried by
-- Config/Grenades.Carried and nothing on the body while put away. Gun space: the origin is the middle of the body (the
-- stick's: on the handle, where the hand holds), its top (the fuse end) up +Y.
-- Holds: the staff's one-handed ones (holdsOf) until the throw animations are made (the animation session, after the
-- user's go): the grenade low in the right hand, the left free; no aim (right click does nothing).
local function grenade(
	display: string,
	asset: string,
	parts: { [string]: { number } },
	scale: { number },
	held: { number }?
): Weapon
	return {
		asset = asset,
		display = display,
		slot = "Grenade",
		class = "Grenade",
		parts = parts,
		moving = {},
		hidden = {},
		attachments = { Muzzle = { 0, 0, -0.1 } }, -- the hip turn's line (hipConverge 0: unused)
		grip = { 0, 0, 0 },
		-- one set for all three (tools/animation/grenade.luau; user 2026-10-19). No unequip: the last one thrown leaves
		-- the hand empty, and one put away goes straight back on the belt
		holds = {
			ready = 87513731672117,
			walk = 72019961101383,
			carry = 140492027408748,
			windup = 86952381429241,
			throw = 80303138028176,
			equip = 97380658835952,
		},
		firstPerson = {
			ready = 124932391377053,
			carry = 128945277614351,
			windup = 81227309666236,
			throw = 88674791679623,
			equip = 130111227451167,
		},
		hipConverge = 0,
		held = held,
		-- modelled at real size (0.0028 studs per mm); thick enough for the 1-stud hand, the stick shorter than thick
		scale = scale,
	}
end
Weapons.grenade_mills = grenade("Mills Bomb", "grenade_mills", {
	Body = { 128, 134, 140 }, -- light steel (the white staff's iron; user's pick)
	Iron = { 60, 62, 66 }, -- base and filler plugs
	Lever = { 90, 92, 96 },
	Pin = { 150, 152, 156 }, -- pin and ring
}, { 2.8, 2.8, 2.8 }, { 0, 0.15, -0.5 })
Weapons.grenade_stick = grenade("Stielhandgranate", "grenade_stick", {
	Head = { 80, 82, 86 }, -- the slate tunic cloth (the grey staff's wrap)
	Collar = { 60, 62, 66 },
	Handle = { 84, 60, 44 }, -- the grey staff's dark stained wood
	Cap = { 60, 62, 66 },
}, { 2.8, 1.8, 2.8 })
Weapons.grenade_sipe = grenade("SIPE", "grenade_sipe", {
	Body = { 116, 114, 72 }, -- the olive cloth (the olive staff's ribbon)
	Fuse = { 70, 68, 58 }, -- the olive staff's iron
}, { 2.8, 2.6, 2.8 }, { 0, 0.15, -0.5 })

return Weapons
