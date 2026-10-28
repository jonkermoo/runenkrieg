--!strict
-- Weapons. Every position is in gun space, in studs, relative to the
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
	-- Crouched (crouchReady / crouchWalk / crouchAim): the same holds for the crouched torso (hunched 28 deg).
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
		-- folded in against the chest with the barrel blocked (src/client/Tuck, Config/Locomotion.Tuck), and crouched
		tuck: number?,
		crouchTuck: number?,
		-- the staff (src/client/StaffAttack): aimTwo, the two-handed aim once the left hand has joined ("TwoHands");
		-- charge, a one shot played with its time set to how long the cast has been held ("CastHeld")
		aimTwo: number?,
		charge: number?,
		airCharge: number?, -- the charge while floating in the air (leaning back)
		-- the same two started with both hands already on the staff ("ChargeTwo": after a stage 2 shot)
		chargeTwo: number?,
		airChargeTwo: number?,
		-- a grenade (src/client/Grenades): pin, a one shot on left click ("PinAt": the pin pulled, into the wind-up);
		-- windup, held while the throw's line shows ("Winding"); throw, a one shot from it played on release
		-- ("ThrownAt"; the grenade leaves the hand Config/Grenades.Throw.release into it)
		pin: number?,
		windup: number?,
		throw: number?,
		-- the shovel (src/client/Shovel): looped while the fire key is held ("Digging") by its mode: dig in Build,
		-- chip in Destroy
		dig: number?,
		chip: number?,
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
		tuck: number?, -- folded in with the barrel blocked (src/client/Tuck)
		aimTwo: number?,
		charge: number?,
		chargeTwo: number?,
		pin: number?,
		windup: number?,
		throw: number?,
		dig: number?,
		chip: number?,
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
	-- an item posed by holds made for another.
	firstShift: { number }?,
	-- Where the item's origin sits from the hold's "Gun" point (game studs, gun space): the "Hold" motor's C1
	-- (src/server/Armory, src/client/Viewmodel). (The grenades used it until their own holds put them between the
	-- fists, 2026-10-20.)
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
	-- beside: strapped to the side of the pack, so not pushed back by the pack's `sling` (src/server/Armory).
	stow: { part: string, at: { number }, muzzle: { number }, side: { number }, beside: boolean? }?,
	-- Shooting (Config/Firing, Rules/Firing): rounds per clip and how the clip loads ("Enbloc": the whole clip goes
	-- into the magazine and drops out the bottom when empty, only reloaded empty; "Stripper": the rounds are pushed
	-- down out of a clip held in the guides, topping the magazine up). Guns only: an item without `ammo` doesn't fire
	-- (src/client/Firing, src/server/Firing) and has no action, reload or bolt either.
	-- A semi-automatic (W2, `action.auto`) always fills the magazine on R: "Stripper" presses in clips of `clipSize`
	-- rounds (else capacity) from the guides, as many as the room needs; "Box" swaps the detachable box whole.
	ammo: { capacity: number, clip: string, clipSize: number? }?,
	-- The action, worked by hand (seconds; turn in degrees, travel in modelled studs): the bolt turns its handle up
	-- by `turn` about its axis (gun Z), then slides back `travel` (+Z) and returns.
	-- auto: a semi-automatic (W2, user 2026-10-18): the action cycles itself on a shot over `boltTime` seconds
	-- (Config/Firing.AutoCycle; no hand on it), every click fires (at most one shot per fireTime); clipTime: seconds
	-- each clip after the first adds to a reload.
	-- fireTime: after a shot nothing else can start for this long (else Config/Firing.FireTime); cycle: this weapon's
	-- own bolt timeline (else Config/Firing.BoltCycle; `hold`: the bolt / pump rests back until then before it goes
	-- forward).
	action: {
		boltTime: number,
		reloadTime: number,
		turn: number,
		travel: number,
		fireTime: number?,
		auto: boolean?,
		clipTime: number?,
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
		depth: number?, -- how far a stripper clip's rounds go down out of it (modelled studs; else 0.17)
		-- two chargers (W2: the Remington 8 with room for more than 5): their own animations (Config/Firing.ReloadCycleTwo)
		bodyTwo: number?,
		firstPersonTwo: number?,
		-- a box swapped whole (Config/Firing.BoxCycle): where the hand holds it (first person: the bottom of the box;
		-- third person `boxSide`: its right side, the hand beside it; seated) and the cocking plunger's tip that the left
		-- hand pulls (modelled gun space)
		boxGrip: { number }?,
		boxSide: { number }?,
		plunger: { number }?,
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
	-- Sway weight over the class's (Config/Sway.Classes): a heavier gun sways more and aims in slower (W2).
	weight: number?,
	-- a pistol's full-damage range (studs; Config/Damage.Falloff for its class)
	fullRange: number?,
	-- a revolver (ammo.clip "Gate"): its chambers' rounds, the parts that turn with the cylinder, the gate and its
	-- chamber, the hammer, trigger and rod throws (src/client/GunFx)
	revolver: {
		rounds: { string },
		turns: { string },
		gateChamber: number,
		gateOpen: number,
		hammer: number,
		trigger: number,
		rod: { out: number, side: { number }, through: number },
	}?,
	-- Extra sway on the move, x the stride sway (src/client/Sway; on top of `weight`): the semi-automatics' price for
	-- their firepower (user 2026-10-20: "sway more when moving ... the big mag one the worst").
	stride: number?,
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
		-- charge: drawn back more and more, the left hand on by stage 2 (src/client/StaffAttack); no crouch
		-- holds yet (the ready plays)
		holds = {
			ready = 119234625003629,
			walk = 138414232252986,
			carry = 112870868696570,
			aim = 88831510650616,
			aimTwo = 86681465612273, -- at the right side (user 2026-10-19: "make sure the staff is on our right side")
			charge = 73620756613940, -- the arms shake more and more, and keep shaking once ready (user 2026-10-13)
			airCharge = 103729690954572, -- in the air (floating): leaning back as it charges
			-- charging with both hands already on (user 2026-10-13: it went back to one hand first)
			chargeTwo = 102656778029004,
			airChargeTwo = 94943550305563,
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
			charge = 133069843329053,
			chargeTwo = 125821148482130, -- with both hands already on
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
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 101367707858516, -- at the hip (2026-10-21)
			walk = 133744444432961, -- at the hip (2026-10-21)
			carry = 99351977507616,
			aim = 136227496577518,
			equip = 82659479717552,
			unequip = 102627201784629, -- put away onto the back (Config/Locomotion.Stow)
			crouchReady = 97174734111193,
			crouchWalk = 84800064969228,
			crouchAim = 76914903412671,
			tuck = 74538057644512, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 131431173277700,
			strike = 124895658997873, -- the butt stroke (Config/Melee, 2026-10-22)
		},
		firstPerson = {
			ready = 119185102113053,
			carry = 124660991401505,
			aim = 85472517302410,
			equip = 86411519760958,
			unequip = 92360338634937,
			aimIn = 108346522950809,
			aimOut = 118548838358261,
			tuck = 133185583190241, -- folded in (2026-10-21)
			strike = 131249563039741, -- the butt stroke (2026-10-22)
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
	-- The Nagant M1895 revolver (model tools/blender/weapons/nagant.py, its shape from tools/blender/weapons/trace/
	-- nagant.py): the olive team's Engineer pistol (uniform2), 7 rounds loaded one at a time through the gate on the
	-- right. Each chamber's round is its own part (Round1, on the bore, then clockwise from behind), shown while loaded
	-- so the cylinder shows how many are left (user 2026-10-27); the one in the gate's chamber (Round3) is the one to
	-- clone for a round going in or a case coming out. The shotgun's holds are borrowed until the pistols' own.
	pistol_nagant = {
		asset = "pistol_nagant",
		display = "Nagant M1895",
		slot = "Primary",
		class = "Pistol",
		parts = {
			Metal = { 52, 54, 58 },
			Cylinder = { 60, 62, 66 },
			Hammer = { 52, 54, 58 },
			Trigger = { 52, 54, 58 },
			Gate = { 60, 62, 66 },
			Rod = { 60, 62, 66 },
			Wood = { 120, 78, 52 }, -- the Olive team's warm brown (as its shotgun kit)
			Bore = { 3, 3, 3 },
			Chambers = { 3, 3, 3 }, -- the chambers' mouths on the cylinder's front face
			Round1 = { 196, 160, 84 },
			Round2 = { 196, 160, 84 },
			Round3 = { 196, 160, 84 },
			Round4 = { 196, 160, 84 },
			Round5 = { 196, 160, 84 },
			Round6 = { 196, 160, 84 },
			Round7 = { 196, 160, 84 },
		},
		moving = {
			Cylinder = { 0, 0.0311, 0.0419 }, -- its axis at the rear face: 1/7 turn (51.43 deg) clockwise from behind a shot
			Chambers = { 0, 0.0311, 0.0419 }, -- turn with the cylinder
			Round1 = { 0, 0.0311, 0.0419 }, -- the rounds turn with the cylinder too
			Round2 = { 0, 0.0311, 0.0419 },
			Round3 = { 0, 0.0311, 0.0419 },
			Round4 = { 0, 0.0311, 0.0419 },
			Round5 = { 0, 0.0311, 0.0419 },
			Round6 = { 0, 0.0311, 0.0419 },
			Round7 = { 0, 0.0311, 0.0419 },
			Hammer = { 0, 0.0241, 0.1027 }, -- its pin: back 40 deg on every pull, then falls
			Trigger = { 0, -0.0501, 0.0095 }, -- the trigger pin
			Gate = { 0.0476, 0.0051, 0.0557 }, -- hinged at its bottom outer edge: top out to +X 90 deg to load
			Rod = { 0, 0.0311, -0.2058 }, -- the ejector rod: forward 0.107, swung to the gate's chamber, pushed back through
		},
		hidden = {},
		attachments = {
			Muzzle = { 0, 0.065, -0.3824 },
			Aim = { 0, 0.104, 0.6 }, -- the eye, on the sight line through the rear notch to the blade (held out)
			Eject = { 0.0588, 0.0236, 0.0557 }, -- outside the open gate: the cases come out to the right
		},
		grip = { 0, -0.06, 0.17 }, -- the top of the grip, under the hammer's spur
		-- (the shotgun's whole set until the pistols' own: tools/animation/pistol.luau)
		holdsOf = "shotgun_m1897",
		holds = {
			ready = 101367707858516,
			walk = 133744444432961,
			carry = 99351977507616,
			aim = 136227496577518,
			equip = 82659479717552,
			unequip = 102627201784629,
			crouchReady = 97174734111193,
			crouchWalk = 84800064969228,
			crouchAim = 76914903412671,
			tuck = 74538057644512,
			crouchTuck = 131431173277700,
			strike = 124895658997873,
		},
		firstPerson = {
			ready = 119185102113053,
			carry = 124660991401505,
			aim = 85472517302410,
			equip = 86411519760958,
			unequip = 92360338634937,
			aimIn = 108346522950809,
			aimOut = 118548838358261,
			tuck = 133185583190241,
			strike = 131249563039741,
		},
		shouldered = { 0.4, 1.45, -0.6 }, -- (the shotgun's eye, its holds borrowed)
		scale = { 3, 3, 2.5 }, -- 0.66 -> 1.65 studs long, chunky in the 1-stud hand
		-- put away: the pistols' shared hip holster (HOLSTER, below)
		-- the Engineer pistols' roles (the design 2026-10-27): the steady all-rounder, rarely empty. 7 rounds, double
		-- action (every click fires, the shared Config/Firing.PistolFireTime apart), loaded one at a time through the
		-- gate (the slowest reload of the three, topping up from any count), full damage to 40 m (Config/Damage.Pistol,
		-- .Falloff), the middle recoil
		fullRange = 112, -- 40 m at 0.357 m per stud
		ammo = { capacity = 7, clip = "Gate" },
		-- no bolt: the cylinder turns on the trigger pull (src/client/GunFx.revolve); reloadTime unused (single rounds)
		action = { boltTime = 0, reloadTime = 0, turn = 0, travel = 0 },
		-- the gate opens (the cylinder turned to the first empty chamber), then per round: the rod punches the fired case
		-- out, a round goes in, the cylinder turns on; at the end the gate shuts (src/client/GunFx.load)
		single = {
			seat = { 0.033, 0.0236, 0.07 }, -- just behind the gate's chamber: the round pushed in from there
			body = 0,
			firstPerson = 0,
			open = 0.5,
			round = 0.85,
			close = 0.45,
		},
		-- the cylinder's turn and the loading (src/client/GunFx): rounds by chamber, clockwise from behind from the one on
		-- the bore; the gate's chamber; the rod's stroke (modelled studs: forward out of the cylinder, over to the gate's
		-- chamber, back through it)
		revolver = {
			rounds = { "Round1", "Round2", "Round3", "Round4", "Round5", "Round6", "Round7" },
			turns = { "Cylinder", "Chambers", "Round1", "Round2", "Round3", "Round4", "Round5", "Round6", "Round7" },
			gateChamber = 2,
			gateOpen = 80, -- degrees, its top out to the right
			hammer = 40, -- degrees back at full cock
			trigger = 25, -- degrees back on the pull
			rod = { out = 0.1065, side = { 0.033, -0.0022 }, through = 0.019 },
		},
		eject = { "Round3" }, -- a fired case punched out of the gate (the gate's chamber's round as the template)
		bolt = { aim = 0, ready = 0 }, -- (no bolt: nothing to work by hand)
		reload = { knob = { 0, 0, 0 }, clipTop = { 0.033, 0.0236, 0.07 }, entry = 0, body = 0, firstPerson = 0 },
		recoil = { scale = 0.9, build = 0.35, max = 2.2, cool = 1.4 },
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
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 139534313231629, -- at the hip (2026-10-21)
			walk = 132893491172513, -- at the hip (2026-10-21)
			carry = 95787766149259, -- swings with the sprint
			aim = 110368315287864,
			equip = 127686053924548, -- side strap 2026-10-20 (was 116500778543360)
			unequip = 74478538423124, -- side strap 2026-10-20 (was 109180311222647)
			crouchReady = 104496542496105,
			crouchWalk = 95673122474038,
			crouchAim = 81566215869278,
			tuck = 95491655827392, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 132650677327308,
			strike = 82596373229157, -- the butt stroke (Config/Melee, 2026-10-22)
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
			tuck = 101761294890610, -- folded in (2026-10-21)
			strike = 133956793514323, -- the butt stroke (2026-10-22)
		},
		-- the comb at the right cheek, the eye 4.45 above the feet: muzzle ~4.33 (Metrics AimMuzzleHeight ~4.3)
		shouldered = { 0.4, 1.45, -0.6 },
		-- 2.5x thicker, 1.5x longer (user 2026-10-11: way too small next to the arm): 3.51 -> 5.27 studs long, stock
		-- 0.36 wide, forend ~0.3 thick, butt ~1 stud (the arm's width)
		scale = { 2.5, 2.5, 1.5 },
		-- slung on the back (user references 2026-10-11): flat against the back with the bolt handle out, leaning
		-- 18 degrees so the thick stock stays inside the torso's width (butt at the upper thigh) while the rifle
		-- passes clear of the head and rises ~1.3 studs above it over the right shoulder
		-- strapped upright on the right side of the pack (user 2026-10-20: "strap all the rifles to the right
		-- of the bag (the side)", then "point straight up"; it may touch the bag a little), leaning 3 degrees out
		stow = {
			part = "Torso",
			at = { 0.95, 0.1, 1.35 }, -- up and back off the right thigh, against the bag (2026-10-20)
			muzzle = { 0.0523, 0.9986, 0 }, -- sin 3, cos 3
			side = { -0.9986, 0.0523, 0 }, -- the bolt toward the bag, the stock and magazine toward the back
			beside = true,
		},
		-- its 6-round en-bloc clip: one round more than the other rifles (6 + 1), balanced by reloading only with the
		-- magazine empty (1 or 0 rounds left; user 2026-10-12)
		ammo = { capacity = 6, clip = "Enbloc" },
		-- handle mid-bolt, straight out to the right: turns up a quarter turn, the bolt slides back along the open
		-- receiver
		-- slowed (user 2026-10-13: "do the same to all the rifles"): a beat after the shot, the bolt resting back
		action = {
			boltTime = 1.25,
			reloadTime = 3.0, -- v2: +25% (user 2026-10-19)
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
			body = 88369726870929,
			firstPerson = 75492413402370,
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
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 113470181734031, -- at the hip (2026-10-21)
			walk = 138667634904829, -- at the hip (2026-10-21)
			carry = 119428875830732,
			aim = 84854636666833,
			equip = 97908657316745, -- side strap 2026-10-20 (was 72036096088316)
			unequip = 80825573280564, -- side strap 2026-10-20 (was 93267993854514)
			crouchReady = 78521608205736,
			crouchWalk = 127233053921696,
			crouchAim = 85481972800522,
			tuck = 121330838750280, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 75184218736588,
			strike = 72253688383944, -- the butt stroke (Config/Melee, 2026-10-22)
		},
		firstPerson = {
			ready = 102402737080974,
			carry = 106294181602498,
			aim = 70722778630134,
			equip = 123066272399119,
			unequip = 126607551609403,
			aimIn = 77762769530436,
			aimOut = 109549978918090,
			tuck = 119014287250925, -- folded in (2026-10-21)
			strike = 73567308916252, -- the butt stroke (2026-10-22)
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the Carcano: 3.5 -> 5.25 studs long
		-- strapped upright on the right side of the pack (user 2026-10-20: "strap all the rifles to the right
		-- of the bag (the side)", then "point straight up"; it may touch the bag a little), leaning 3 degrees out
		stow = {
			part = "Torso",
			at = { 0.95, 0.1, 1.35 }, -- up and back off the right thigh, against the bag (2026-10-20)
			muzzle = { 0.0523, 0.9986, 0 }, -- sin 3, cos 3
			side = { -0.9986, 0.0523, 0 }, -- the bolt toward the bag, the stock and magazine toward the back
			beside = true,
		},
		ammo = { capacity = 5, clip = "Stripper" }, -- 5 rounds pushed down out of a stripper clip in the guides (5 + 1)
		-- straight handle at the rear of the bolt: turns up a quarter turn, the bolt slides back through the bridge
		action = {
			boltTime = 1.25,
			reloadTime = 3.5, -- v2: +25% (user 2026-10-19)
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
		single = { seat = { 0, 0.035, -0.238 }, body = 81962838082410, firstPerson = 125633536245582 },
		reload = {
			knob = { 0.136, 0.065, -0.0695 },
			clipTop = { 0, 0.255, -0.1863 },
			entry = 0,
			body = 115167609079331,
			firstPerson = 117602140790926,
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
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 126960587568297, -- at the hip (2026-10-21)
			walk = 129468543347196, -- at the hip (2026-10-21)
			carry = 99038350375470,
			aim = 126169298976361,
			equip = 139013019358334, -- side strap 2026-10-20 (was 125483711137564)
			unequip = 81806140074423, -- side strap 2026-10-20 (was 83535543803771)
			crouchReady = 90709952340150,
			crouchWalk = 80571218794707,
			crouchAim = 74306635264463,
			tuck = 140359800426699, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 127147207467670,
			strike = 128522894827196, -- the butt stroke (Config/Melee, 2026-10-22)
		},
		firstPerson = {
			ready = 71589430224575,
			carry = 108888005264242,
			aim = 96309248783570,
			equip = 88893121669824,
			unequip = 128704204598975,
			aimIn = 117817401540584,
			aimOut = 90955676384745,
			tuck = 115039438376162, -- folded in (2026-10-21)
			strike = 77290819806919, -- the butt stroke (2026-10-22)
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the other rifles: 3.17 -> 4.76 studs long
		-- strapped upright on the right side of the pack (user 2026-10-20: "strap all the rifles to the right
		-- of the bag (the side)", then "point straight up"; it may touch the bag a little), leaning 3 degrees out
		stow = {
			part = "Torso",
			at = { 0.95, 0.1, 1.35 }, -- up and back off the right thigh, against the bag (2026-10-20)
			muzzle = { 0.0523, 0.9986, 0 }, -- sin 3, cos 3
			side = { -0.9986, 0.0523, 0 }, -- the bolt toward the bag, the stock and magazine toward the back
			beside = true,
		},
		ammo = { capacity = 5, clip = "Stripper" }, -- 5 rounds pushed down out of a charger in the guides (5 + 1); tops up
		-- the Lee's short lift (60 deg) and cock-on-closing make the fastest bolt; the bolt slides back clear of the
		-- magazine's top round
		action = {
			boltTime = 1.0, -- still the fastest bolt
			reloadTime = 3.5, -- v2: +25% (user 2026-10-19)
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
		single = { seat = { 0, 0.035, -0.204 }, body = 76009049286188, firstPerson = 78678430549776 },
		reload = {
			knob = { 0.11, -0.0276, 0.0376 },
			clipTop = { 0, 0.2833, -0.1618 },
			entry = 0,
			body = 125218307958063,
			firstPerson = 139832163545234,
		},
	},
	-- The semi-automatic rifles, one per team (docs/MILESTONES.md W2, user 2026-10-18): one shot per click, at most one
	-- every 0.35 s; the action cycles itself (no bolt to work); torso 55 / limbs 45 (Config/Damage SemiRifle); R always
	-- fills the magazine. Gentle recoil (scale 0.8, build 0.3).
	-- The grey team's Mondragón (FSK 15): 8 + 1 from 5-round clips (a second tops up the rest), the lightest.
	rifle_mondragon = {
		asset = "rifle_mondragon",
		display = "Mondragón",
		slot = "Primary",
		class = "SemiRifle",
		parts = {
			Wood = { 142, 74, 42 },
			Metal = { 52, 54, 58 },
			Bolt = { 70, 70, 74 },
			Trigger = { 52, 54, 58 },
			Clip = { 90, 88, 84 },
			Rounds = { 196, 160, 84 },
			Bullets = { 184, 115, 72 },
			Casing = { 196, 160, 84 },
			Bore = { 3, 3, 3 },
		},
		moving = {
			Bolt = { 0, 0.065, -0.3492 }, -- on the bolt's axis, at the knob (out to the right through the port)
			Trigger = { 0, -0.0718, 0 }, -- the trigger pin
			Clip = { 0, 0.0995, -0.2151 }, -- the stripper clip over the open top
		},
		hidden = { "Casing", "Clip" }, -- the clip shows only while reloading
		attachments = {
			Muzzle = { 0, 0.065, -2.1709 },
			Aim = { 0, 0.134, 0.45 }, -- on the sight line, 0.069 over the bore
			Eject = { 0.02, 0.09, -0.2762 }, -- out of the open top
		},
		grip = { 0, -0.0072, 0.2151 }, -- the wrist
		-- its own holds (tools/animation/rifle.luau; user-approved from previews 2026-10-19)
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 87362563927334, -- at the hip (2026-10-21)
			walk = 72591791075002, -- at the hip (2026-10-21)
			carry = 98671117994210,
			aim = 91487073174337,
			equip = 114426601068983, -- side strap 2026-10-20 (was 85502951685731)
			unequip = 91495686258766, -- side strap 2026-10-20 (was 91443560254621)
			crouchReady = 130402887594771,
			crouchWalk = 83429616166340,
			crouchAim = 113687704218134,
			tuck = 81056645958987, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 126878471955941,
			strike = 125034366666020, -- the butt stroke (Config/Melee, 2026-10-22)
		},
		firstPerson = {
			ready = 99899869193706,
			carry = 72486322491355,
			aim = 94272139670262,
			equip = 104707910768402,
			unequip = 98957967109125,
			aimIn = 119968660948192,
			aimOut = 70887731010016,
			tuck = 87625337746536, -- folded in (2026-10-21)
			strike = 135600793931016, -- the butt stroke (2026-10-22)
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the bolt rifles: 3.1 -> 4.64 studs long
		-- strapped upright on the right side of the pack (user 2026-10-20: "strap all the rifles to the right
		-- of the bag (the side)", then "point straight up"; it may touch the bag a little), leaning 3 degrees out
		stow = {
			part = "Torso",
			at = { 0.95, 0.1, 1.35 }, -- up and back off the right thigh, against the bag (2026-10-20)
			muzzle = { 0.0523, 0.9986, 0 }, -- sin 3, cos 3
			side = { -0.9986, 0.0523, 0 }, -- the bolt toward the bag, the stock and magazine toward the back
			beside = true,
		},
		-- 5-round clips, the rest topped up from a second (user 2026-10-19: "reload in mags of 5, top off the rest")
		ammo = { capacity = 8, clip = "Stripper", clipSize = 5 },
		-- the bolt slides straight back (no turn) and returns by itself
		action = {
			auto = true,
			boltTime = 0.12,
			reloadTime = 2.8, -- one 5-round clip; two (from empty) 3.7 s
			clipTime = 0.9,
			turn = 0,
			travel = 0.219,
			fireTime = 0.35,
		},
		recoil = { scale = 0.8, build = 0.3, max = 2, cool = 1.6 },
		weight = 1.0,
		stride = 1.3, -- more sway on the move than a bolt rifle (user 2026-10-20)
		bolt = { aim = 0, ready = 0 }, -- (no bolt to work)
		reload = {
			knob = { 0.092, 0.065, -0.3492 }, -- the operating knob, bolt closed
			clipTop = { 0, 0.3695, -0.2151 }, -- the clip's top over the open top
			entry = 0,
			body = 126928019033807, -- the knob pulled straight back, the clip thumbed down, the bolt let go (tools/animation/reload.luau)
			firstPerson = 124547282113754,
			firstPersonTwo = 111314271818130,
			bodyTwo = 101134687311879,
			depth = 0.27, -- 8 rounds in one row
		},
	},
	-- The olive team's Remington Model 8: 10 + 1 from 5-round chargers (one or two pressed in), reload ~3 s, weight 1.1.
	rifle_remington8 = {
		asset = "rifle_remington8",
		display = "Remington Model 8",
		slot = "Primary",
		class = "SemiRifle",
		parts = {
			Wood = { 142, 74, 42 },
			Metal = { 52, 54, 58 },
			Bolt = { 70, 70, 74 },
			Trigger = { 52, 54, 58 },
			Clip = { 90, 88, 84 },
			Rounds = { 196, 160, 84 },
			Bullets = { 184, 115, 72 },
			Casing = { 196, 160, 84 },
			Bore = { 3, 3, 3 },
		},
		moving = {
			Bolt = { 0, 0.065, -0.2733 }, -- on the bolt's axis, at the knob (the slide outside the right wall)
			Trigger = { 0, -0.0541, 0 }, -- the trigger pin
			Clip = { 0, 0.1142, -0.1133 }, -- the charger over the open top
		},
		hidden = { "Casing", "Clip" }, -- the charger shows only while reloading
		attachments = {
			Muzzle = { 0, 0.065, -1.8912 },
			Aim = { 0, 0.1308, 0.45 }, -- on the sight line, 0.066 over the bore
			Eject = { 0.02, 0.09, -0.2399 }, -- out of the open top
		},
		grip = { 0, -0.0558, 0.2966 }, -- the wrist
		-- its own holds (tools/animation/rifle.luau; user-approved from previews 2026-10-19)
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 117925445760177, -- at the hip (2026-10-21)
			walk = 112501944799007, -- at the hip (2026-10-21)
			carry = 100807971064233,
			aim = 137523101236015,
			equip = 120151131197951, -- side strap 2026-10-20 (was 105995501607410)
			unequip = 88422824948262, -- side strap 2026-10-20 (was 134210763532593)
			crouchReady = 111038619727593,
			crouchWalk = 121384492532717,
			crouchAim = 84291737502596,
			tuck = 100963784440638, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 115286704577287,
			strike = 72946692028843, -- the butt stroke (Config/Melee, 2026-10-22)
		},
		firstPerson = {
			ready = 80058775294043,
			carry = 83030861438002,
			aim = 101487864226501,
			equip = 86237616911649,
			unequip = 137358913881476,
			aimIn = 118453809265581,
			aimOut = 128498445355922,
			tuck = 94830473554469, -- folded in (2026-10-21)
			strike = 78851384495308, -- the butt stroke (2026-10-22)
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the bolt rifles: 2.94 -> 4.4 studs long
		-- strapped upright on the right side of the pack (user 2026-10-20: "strap all the rifles to the right
		-- of the bag (the side)", then "point straight up"; it may touch the bag a little), leaning 3 degrees out
		stow = {
			part = "Torso",
			at = { 0.95, 0.1, 1.35 }, -- up and back off the right thigh, against the bag (2026-10-20)
			muzzle = { 0.0523, 0.9986, 0 }, -- sin 3, cos 3
			side = { -0.9986, 0.0523, 0 }, -- the bolt toward the bag, the stock and magazine toward the back
			beside = true,
		},
		ammo = { capacity = 10, clip = "Stripper", clipSize = 5 }, -- two 5-round chargers fill it (10 + 1)
		-- the bolt slides straight back (no turn) and returns by itself; a second charger adds clipTime
		action = {
			auto = true,
			boltTime = 0.12,
			reloadTime = 3.1, -- one charger; two 4.0 s (user 2026-10-19: slower)
			clipTime = 0.9,
			turn = 0,
			travel = 0.133,
			fireTime = 0.35,
		},
		recoil = { scale = 0.8, build = 0.3, max = 2, cool = 1.6 },
		weight = 1.1,
		stride = 1.45,
		bolt = { aim = 0, ready = 0 }, -- (no bolt to work)
		reload = {
			knob = { 0.092, 0.065, -0.2733 }, -- the knob on the slide, bolt closed
			clipTop = { 0, 0.2842, -0.1133 }, -- the charger's top over the open top
			entry = 0,
			-- one charger, and two (the second pressed in before the bolt is let go; tools/animation/reload.luau)
			body = 104150957769271,
			firstPerson = 75746036527426,
			bodyTwo = 115221448967769,
			firstPersonTwo = 139715120468537,
		},
	},
	-- The brown team's Winchester 1907: 15 + 1 from a detachable box swapped whole, the slowest reload (5 s), the
	-- heaviest (weight 1.25: more sway). The bolt is cocked by the plunger under the barrel.
	rifle_winchester1907 = {
		asset = "rifle_winchester1907",
		display = "Winchester 1907",
		slot = "Primary",
		class = "SemiRifle",
		parts = {
			Wood = { 142, 74, 42 },
			Metal = { 52, 54, 58 },
			Bolt = { 70, 70, 74 },
			Trigger = { 52, 54, 58 },
			Magazine = { 70, 70, 74 },
			Rounds = { 196, 160, 84 },
			Bullets = { 184, 115, 72 },
			Casing = { 196, 160, 84 },
			Bore = { 3, 3, 3 },
		},
		moving = {
			Bolt = { 0, 0.065, -0.2763 }, -- on the bolt's axis (with the plunger under the barrel)
			Trigger = { 0, -0.0953, 0 }, -- the trigger pin
			Magazine = { 0, -0.0547, -0.2432 }, -- the box's top front, up in the well
		},
		hidden = { "Casing" },
		attachments = {
			Muzzle = { 0, 0.065, -1.7297 },
			Aim = { 0, 0.1092, 0.45 }, -- on the sight line, 0.044 over the bore
			Eject = { 0.035, 0.07, -0.1105 }, -- the port, right side
		},
		grip = { 0, -0.0437, 0.2579 }, -- the wrist
		-- its own holds (tools/animation/rifle.luau; user-approved from previews 2026-10-19)
		-- third person v3 (user 2026-10-19: the hands hold the gun, the right on the grip, the left on the underbarrel)
		holds = {
			ready = 139888254198407, -- at the hip (2026-10-21)
			walk = 80157291932020, -- at the hip (2026-10-21)
			carry = 101240368863563,
			aim = 101485302556328,
			equip = 139777204769501, -- side strap 2026-10-20 (was 131693072645640)
			unequip = 106743016019956, -- side strap 2026-10-20 (was 118191915320097)
			crouchReady = 112467029219277,
			crouchWalk = 72459068643756,
			crouchAim = 95868975570564,
			tuck = 81776192234329, -- folded in, the barrel blocked (2026-10-21)
			crouchTuck = 112800624654038,
			strike = 81868680809975, -- the butt stroke (Config/Melee, 2026-10-22)
		},
		firstPerson = {
			ready = 110794805321931,
			carry = 130251720996066,
			aim = 90503217545668,
			equip = 82561806594910,
			unequip = 83666097539320,
			aimIn = 133832844856773,
			aimOut = 97729127051200,
			tuck = 96595656648580, -- folded in (2026-10-21)
			strike = 123351849811720, -- the butt stroke (2026-10-22)
		},
		shouldered = { 0.4, 1.45, -0.6 },
		scale = { 2.5, 2.5, 1.5 }, -- as the bolt rifles: 2.85 -> 4.27 studs long
		-- strapped upright on the right side of the pack (user 2026-10-20: "strap all the rifles to the right
		-- of the bag (the side)", then "point straight up"; it may touch the bag a little), leaning 3 degrees out
		stow = {
			part = "Torso",
			at = { 0.95, 0.1, 1.35 }, -- up and back off the right thigh, against the bag (2026-10-20)
			muzzle = { 0.0523, 0.9986, 0 }, -- sin 3, cos 3
			side = { -0.9986, 0.0523, 0 }, -- the bolt toward the bag, the stock and magazine toward the back
			beside = true,
		},
		ammo = { capacity = 15, clip = "Box" }, -- a fresh 15-round box (15 + 1)
		action = {
			auto = true,
			boltTime = 0.12,
			reloadTime = 6.5, -- user 2026-10-19: "significantly slower" (was 5)
			turn = 0,
			travel = 0.169,
			fireTime = 0.35,
		},
		recoil = { scale = 0.8, build = 0.3, max = 2, cool = 1.6 },
		weight = 1.25,
		stride = 1.7, -- the 15-round box: the worst on the move
		bolt = { aim = 0, ready = 0 }, -- (no bolt to work)
		reload = {
			knob = { 0, -0.0124, -1.2931 }, -- (the plunger's tip)
			clipTop = { 0, -0.0547, -0.2432 }, -- the box seated
			entry = -0.25, -- set this far under the well, then pushed up in
			-- the box dropped, a fresh one pushed up in, the plunger pulled (tools/animation/reload.luau)
			body = 93383100141861,
			firstPerson = 132310341907955,
			boxGrip = { 0, -0.29, -0.164 }, -- the box's bottom, seated
			boxSide = { 0.03, -0.2, -0.164 }, -- its right side, halfway down
			plunger = { 0, -0.0124, -1.2931 },
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
	staff_brown = staff("Staff (Brown)", {
		Wood = { 178, 154, 118 }, -- pale ash
		Iron = { 128, 134, 140 }, -- light steel
		Accent = { 196, 198, 204 }, -- silver
		Wrap = { 214, 214, 210 }, -- the off-white of the Brodie helmet
		Ribbon = { 150, 54, 44 }, -- red, against the white
	}),
}

-- The thrown grenades, one per team (docs/MILESTONES.md G1, user 2026-10-18; Config/Grenades for the throw and the
-- blast; models tools/blender/weapons/grenades.py): the Mills bomb No. 5 (brown), the Stielhandgranate M1917 (grey),
-- the SIPE (olive), each tinted in its team's colours (user: "Team-tinted"). Their own "Grenade" slot, carried by
-- Config/Grenades.Carried and nothing on the body while put away. Gun space: the origin is the middle of the body (the
-- stick's: on the handle, where the hand holds), its top (the fuse end) up +Y.
-- Holds: their own (tools/animation/grenade.luau, user 2026-10-19): both hands on it in the middle; on left click the
-- pin pulled and drawn back in the right hand while the throw's line shows, the throw on release; no aim (right click
-- does nothing).
local function grenade(display: string, asset: string, parts: { [string]: { number } }, scale: { number }): Weapon
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
		-- one set for all three (tools/animation/grenade.luau v5, user 2026-10-19/20): held in both hands in the middle, the
		-- pin pulled on left click, one hand while drawn back, drawn from the pack. No unequip: the last one thrown leaves
		-- the hand empty, and one put away goes straight back in the pack
		holds = {
			ready = 101674499118051,
			walk = 138117477771357,
			carry = 107064923054732,
			pin = 113068527158456,
			windup = 73841654682321,
			throw = 93952628639934,
			equip = 121174700853919,
		},
		firstPerson = {
			ready = 129260927316629,
			carry = 100984430779823,
			pin = 79429013550463,
			windup = 134353781610964,
			throw = 118069982261298,
			equip = 75621335657766,
		},
		hipConverge = 0,
		-- modelled at real size (0.0028 studs per mm); thick enough for the 1-stud hand, the stick shorter than thick
		scale = scale,
	}
end
Weapons.grenade_mills = grenade("Mills Bomb", "grenade_mills", {
	Body = { 128, 134, 140 }, -- light steel (the white staff's iron; user's pick)
	Iron = { 60, 62, 66 }, -- base and filler plugs
	Lever = { 90, 92, 96 },
	Pin = { 150, 152, 156 }, -- pin and ring
}, { 2.8, 2.8, 2.8 })
Weapons.grenade_stick = grenade("Stielhandgranate", "grenade_stick", {
	Head = { 80, 82, 86 }, -- the slate tunic cloth (the grey staff's wrap)
	Collar = { 60, 62, 66 },
	Handle = { 84, 60, 44 }, -- the grey staff's dark stained wood
	Cap = { 60, 62, 66 },
}, { 2.8, 1.8, 2.8 })
Weapons.grenade_sipe = grenade("SIPE", "grenade_sipe", {
	Body = { 116, 114, 72 }, -- the olive cloth (the olive staff's ribbon)
	Fuse = { 70, 68, 58 }, -- the olive staff's iron
}, { 2.8, 2.6, 2.8 })

-- The shovel (docs/MILESTONES.md SV1; model tools/blender/weapons/shovel.py, asset "shovel"): carried by every soldier
-- in its own "Shovel" slot (user 2026-10-20: "a mandatory item on every soldier"), the same for every team, colored as
-- Config/Palette.Shovel. Gun space: the origin is the D-grip's bar (the right hand), the blade toward -Z. Holds
-- (tools/animation/shovel.luau): two-handed at port across the chest; left click digs (src/client/Shovel), by the
-- shovel's mode (src/client/Build): in Build a dig tossed over the shoulder, in Destroy a charged strike; no aim.
-- Strapped upright to the pack when put away.
Weapons.shovel = {
	asset = "shovel",
	display = "Shovel",
	slot = "Shovel",
	class = "Shovel",
	parts = {
		Wood = { 139, 94, 60 }, -- as Config/Palette.Shovel
		Iron = { 90, 92, 96 },
		Blade = { 122, 124, 128 },
		Brass = { 184, 149, 90 },
	},
	moving = {},
	hidden = {},
	attachments = { Muzzle = { 0, 0, -3.42 } }, -- the blade's tip (the hip turn's line: hipConverge 0, unused)
	grip = { 0, 0, 0 },
	-- both hands on it throughout (user 2026-10-20). v2: the hold steeper, the blade by the left shoulder (Studio round
	-- 1: it lay out low). dig (Build mode) and chip (Destroy mode): looped while the fire key is held (user 2026-10-24)
	holds = {
		ready = 93066917970284, -- v2 (v1 106958788763761)
		walk = 124545410126279, -- v2 (v1 92108104753052)
		carry = 82178644834924, -- v2 (v1 125775429184790)
		-- round 3 (user 2026-10-24), loops played while the fire key is held (src/client/Shovel): dig, driven steeply
		-- into the ground, levered up and tossed over the right shoulder; chip, a charged strike into the ground. Both
		-- feet planted. (Round 2: dig 126075345861171, chip 99240838965732; round 1: dig 121891930009756, chip
		-- 70819512791404; the overhead chop: v2 125010045442091, v1 89824822382684)
		dig = 130779516436249,
		chip = 137676342121657,
		equip = 73623873207874, -- v3: from the left side of the pack (v2 116916726450237)
		unequip = 98424397379589, -- v3: from the left side of the pack (v2 126643995839062)
	},
	firstPerson = {
		ready = 98520178322418,
		carry = 76288857841410,
		dig = 81270772145607, -- the scoop (the overhead chop 126655171534139)
		chip = 116261444651083,
		equip = 135132717039649,
		unequip = 107708468866719,
	},
	hipConverge = 0,
	scale = { 1, 1, 1 }, -- modelled at game size (3.5 long)
	-- strapped upright on the left side of the pack, the D-grip at the bottom, the blade up, its hollow against the bag
	-- (user 2026-10-20: "strap it on the left of the bag", then "point straight up"), leaning 3 degrees out
	stow = {
		part = "Torso",
		at = { -0.9, -0.9, 1.15 }, -- up and back off the left thigh, against the bag (2026-10-20)
		muzzle = { -0.0523, 0.9986, 0 }, -- sin 3, cos 3
		side = { 0, 0, -1 },
		beside = true,
	},
}

-- Every pistol (class "Pistol") put away rides at the right hip as if holstered, unless its entry has its own `stow`
-- (user 2026-10-28: "make it sit at the hip for now, as if it was holstered"; a holster accessory comes later): the
-- barrel down along the thigh a touch forward (sin 5, cos 5), the butt back, the right side outward, on the belt so
-- the pack's `sling` doesn't push it back.
local HOLSTER = {
	part = "Torso",
	at = { 1.2, -1.1, -0.15 }, -- outside the right hip, a revolver's cylinder clear of the leg
	muzzle = { 0, -0.9962, -0.0872 },
	side = { 1, 0, 0 },
	beside = true,
}
for _, w in Weapons do
	if w.class == "Pistol" and not w.stow then
		w.stow = HOLSTER
	end
end

return Weapons
