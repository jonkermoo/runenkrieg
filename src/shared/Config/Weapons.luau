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
	holdsOf: string?,
	holds: {
		ready: number,
		walk: number,
		carry: number,
		aim: number,
		equip: number,
		crouchReady: number,
		crouchWalk: number,
		crouchAim: number,
	},
	-- The first-person holds (user 2026-10-11): played only on the player's own client, on a viewmodel (a copy of the
	-- arms and the weapon fixed to the camera, src/client/Viewmodel); others see `holds` on the body. Walking and
	-- running motion comes from the sway layer (Config/Sway), not from extra animations. aimIn: a brief one shot each
	-- time aiming starts, the gun coming up into the sights over the aim hold (user 2026-10-11).
	firstPerson: { ready: number, carry: number, aim: number, equip: number, aimIn: number },
	-- Where the eye (the Aim attachment) sits in the third-person aim hold, in the soldier's upright frame (studs from
	-- the torso centre: +X right, +Y up, -Z forward; the torso centre is 3 above the feet). tests/weapons.spec checks
	-- the muzzle against Metrics.
	shouldered: { number },
	-- Size in game relative to the model, per gun axis { x width, y height, z length }: the blocky R6 soldier carries
	-- chunky, Pordier-style weapons, thick next to the 1-stud arm (the hand closes round a stock about half its size)
	-- but only about as long as the soldier is tall, so the cross-section scales more than the length. Every
	-- gun-space number in this entry is the modelled one; Armory scales them.
	scale: { number },
	-- Where the weapon rides on the body when it isn't equipped (src/server/Armory, everyone sees it). In `part`'s
	-- space (R6 Torso: +X right, +Y up, front -Z, back face at z +0.5): `at` is the gun origin, `muzzle` the way the
	-- muzzle points, `side` the way the gun's right side (+X, the bolt handle) faces.
	stow: { part: string, at: { number }, muzzle: { number }, side: { number } },
	-- Shooting (Config/Firing, Rules/Firing): rounds per clip and how the clip loads ("Enbloc": the whole clip goes
	-- into the magazine and drops out the bottom when empty, only reloaded empty; "Stripper": the rounds are pushed
	-- down out of a clip held in the guides, topping the magazine up).
	ammo: { capacity: number, clip: string },
	-- The action, worked by hand (seconds; turn in degrees, travel in modelled studs): the bolt turns its handle up
	-- by `turn` about its axis (gun Z), then slides back `travel` (+Z) and returns.
	action: { boltTime: number, reloadTime: number, turn: number, travel: number },
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
	},
	-- Working the bolt after a shot, third person (user 2026-10-13; tools/animation/bolt.luau): the right hand goes from
	-- the grip to the knob (reload.knob) and works it; `aim` with the rifle shouldered, `ready` at the hip (any other
	-- hold). 0 until uploaded.
	bolt: { aim: number, ready: number },
	-- Loading single rounds (stripper-clip rifles with rounds left; Config/Firing.Single, tools/animation/single.luau):
	-- seat, where a round goes in (its centre pushed onto the top round, modelled gun space); the animation ids.
	single: { seat: { number }, body: number, firstPerson: number }?,
}

local Weapons: { [string]: Weapon } = {
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
			crouchReady = 92303129713125,
			crouchWalk = 87132266042623,
			crouchAim = 104754199810093,
		},
		-- carry: port arms (user reference video); equip: over the right shoulder from behind the camera; aimIn: from
		-- the ready hold up into the sights in 0.3 s
		firstPerson = {
			ready = 112444183702109,
			carry = 107781105123018,
			aim = 116060344003850,
			equip = 118921104577688,
			aimIn = 88933522621364,
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
		action = { boltTime = 0.9, reloadTime = 2.4, turn = 90, travel = 0.3 },
		-- the knob at the end of the straight handle, mid-bolt; the clip pushed down from just over the magazine
		bolt = { aim = 112665941285389, ready = 88846316947766 },
		reload = {
			knob = { 0.12, 0.065, -0.1511 },
			clipTop = { 0, 0.0614, -0.267 },
			entry = 0.2,
			body = 85665510995906,
			firstPerson = 114783665355868,
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
			crouchReady = 81033918313470,
			crouchWalk = 79212217140130,
			crouchAim = 96381247209498,
		},
		firstPerson = {
			ready = 80927013820298,
			carry = 106294181602498,
			aim = 115730728635887,
			equip = 111730436809929,
			aimIn = 91813569699030,
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
		action = { boltTime = 0.9, reloadTime = 2.8, turn = 90, travel = 0.27 },
		-- the knob at the end of the straight handle at the bolt's rear; the stripper clip in the guides on the bridge
		bolt = { aim = 104911133082414, ready = 95799602076532 },
		-- a round goes in through the open action onto the top round (the magazine's middle round, measured)
		single = { seat = { 0, 0.035, -0.238 }, body = 81962838082410, firstPerson = 95730483657941 },
		reload = {
			knob = { 0.136, 0.065, -0.0695 },
			clipTop = { 0, 0.255, -0.1863 },
			entry = 0,
			body = 122499300440488,
			firstPerson = 98144219253549,
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
			crouchReady = 134261827381957,
			crouchWalk = 130726353830006,
			crouchAim = 115330156920688,
		},
		firstPerson = {
			ready = 89200022670278,
			carry = 108888005264242,
			aim = 116062577227252,
			equip = 74611252629732,
			aimIn = 90801944558884,
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
		action = { boltTime = 0.7, reloadTime = 2.8, turn = 60, travel = 0.28 },
		-- the knob of the bent handle at the bolt's rear, down by the wrist; the charger in the guides on the bridge
		bolt = { aim = 111244016757012, ready = 89479225195668 },
		-- a round goes in through the open action onto the top round (the magazine's middle round, measured)
		single = { seat = { 0, 0.035, -0.204 }, body = 76009049286188, firstPerson = 133640753043197 },
		reload = {
			knob = { 0.11, -0.0276, 0.0376 },
			clipTop = { 0, 0.2833, -0.1618 },
			entry = 0,
			body = 101808128954188,
			firstPerson = 122069545639246,
		},
	},
}

return Weapons
