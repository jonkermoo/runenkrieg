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
			Eject = { 0.03, 0.075, -0.397 }, -- the open receiver, right side: casings fly out +X/+Y
		},
		grip = { 0, -0.06, 0.15 },
		-- user references 2026-10-11: ready low in front of the stomach, sprint carried across the body, aim shouldered;
		-- ready and aim breathe like Roblox's R6 idle (user: match the default sway)
		holds = {
			ready = 107914359416034,
			walk = 81116116222571,
			carry = 124372088520129, -- swings with the sprint
			aim = 133970960181165,
			equip = 101917236691086,
			crouchReady = 80456739032631,
			crouchWalk = 90228887606612,
			crouchAim = 137476015651826,
		},
		-- carry: port arms (user reference video); equip: over the right shoulder from behind the camera; aimIn: from
		-- the ready hold up into the sights in 0.2 s
		firstPerson = {
			ready = 122238707400436,
			carry = 114387700921278,
			aim = 109878538050440,
			equip = 120043329130240,
			aimIn = 127708234257716,
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
	},
}

return Weapons
