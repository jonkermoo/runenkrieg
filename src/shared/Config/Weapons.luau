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
	parts: { [string]: { number } }, -- flat color per mesh part
	moving: { [string]: { number } }, -- Motor6D pivot per moving part (the rest is welded)
	hidden: { string }, -- template parts, invisible on the weapon (cloned at runtime)
	attachments: { [string]: { number } },
	grip: { number }, -- where the right hand holds (the wrist behind the trigger guard)
	-- Size in game relative to the model: the blocky R6 soldier carries chunky, Pordier-style weapons (a rifle about
	-- as long as the soldier is tall). Every gun-space number in this entry is the modelled one; Armory scales them.
	scale: number,
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
		scale = 1.5, -- 3.51 -> 5.27 studs long (user 2026-10-11: bigger, like the references)
		-- slung on the back (user references 2026-10-11): flat against the right half of the back with the bolt
		-- handle out, nearly upright (8 degrees), butt at the hip, passing beside the head (x 0.85 at head height,
		-- clear of it) and rising ~1.3 studs above it
		stow = {
			part = "Torso",
			at = { 0.63, -0.08, 0.66 },
			muzzle = { 0.1392, 0.9903, 0 }, -- sin 8, cos 8
			side = { 0, 0, 1 },
		},
	},
}

return Weapons
