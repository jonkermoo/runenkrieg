--!strict
-- Weapons (.claude/skills/roblox-weapons/SKILL.md). Every position is in gun space, in studs, relative to the
-- export's Origin marker (the gun origin, at the trigger): +X right, +Y up, -Z toward the muzzle.
-- Aiming contract: the Aim camera and the bullet both travel along gun -Z, so the line of sight is parallel to the
-- line of fire and the shot lands one sight height (Aim.y - Muzzle.y) below the point of aim at every range.

export type Weapon = {
	asset: string, -- Config/Assets entry (the uploaded model)
	display: string,
	parts: { [string]: { number } }, -- flat color per mesh part
	moving: { [string]: { number } }, -- Motor6D pivot per moving part (the rest is welded)
	hidden: { string }, -- template parts, invisible on the weapon (cloned at runtime)
	attachments: { [string]: { number } },
	grip: { number }, -- where the right hand holds (the wrist behind the trigger guard)
	bolt: { lift: number, travel: number, liftTime: number, slideTime: number }?,
	trigger: { pull: number, time: number },
}

local Weapons: { [string]: Weapon } = {
	rifle_m91 = {
		asset = "rifle_m91",
		display = "Carcano M91",
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
		bolt = { lift = 90, travel = 0.28, liftTime = 0.12, slideTime = 0.18 }, -- degrees, studs, seconds
		trigger = { pull = 14, time = 0.05 },
	},
}

return Weapons
