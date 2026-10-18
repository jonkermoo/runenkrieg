--!strict
-- Thrown grenades (docs/MILESTONES.md G1; user 2026-10-18). One per team, each a Config/Weapons entry of class
-- "Grenade" in the "Grenade" slot; Rules/Grenade works the numbers, src/server/Grenades throws and sets them off,
-- src/client/Grenades shows the arc and sends the throw. Data only.
-- - Pull the pin and throw: the fuse starts as it leaves the hand, the same for all three, no cooking (user).
-- - Hold the throw button to see a faint dotted arc to where it lands (user: "Arc preview line"); release throws.
-- - It can't be picked up or thrown back (user).
-- - The blast is the real charge through Damage.blast (TNT equivalent), plus its fragments (user: "Real + fragments").
--   It only strips leaves and shakes trees, never fells them (user 2026-10-18).

local Grenades = {
	Fuse = 3, -- seconds from leaving the hand (user: "3s, no throwing back")
	Carried = 2, -- per life, refilled at respawn (user: "2 per life, own slot")
	Cooldown = 1, -- seconds before the next one can be thrown (the next grenade into the hand)

	-- The throw: along the camera's look, lifted `loft` degrees (so a level look still lobs it), at the grenade's own
	-- `speed` (studs/s, below). From the head, `from` studs out in the camera's space (+X right, +Y up, -Z forward): the
	-- throwing hand over the right shoulder. No drag (Roblox has none); gravity is workspace.Gravity.
	Throw = {
		loft = 10,
		from = { 0.8, 0.6, -0.8 },
		-- the server takes the throw only from near the soldier's head (studs) and looking where it can (a unit vector)
		reach = 4,
		-- a wall between the head and the hand: the throw starts this far short of it (never through it)
		gap = 0.3,
		spin = 8, -- tumbling in flight, radians/s
	},

	-- The thrown grenade: a small hitbox (studs) that bounces and rolls a little (user: "bounces and rolls a little").
	Body = {
		size = 0.6,
		density = 2,
		friction = 0.6,
		elasticity = 0.3,
		-- Where it lands it thuds: the first touch keeps `land` of its speed along the ground, then rolling loses it at
		-- `roll` per second (a ball in Roblox never stops rolling by itself; Studio round 1 rolled 275 studs). Swept
		-- each frame from where it was (`probe` studs past its radius), so a fast throw can't pass through thin ground.
		land = 0.15,
		roll = 3,
		probe = 0.15,
		-- the blast goes off this far above where the body lies (out of the ground it rests on)
		lift = 0.3,
		-- the Mills's lever flying off: the throw's velocity times `carry`, plus `pop` studs/s up, tumbling `spin`
		-- radians/s; gone after `life` seconds
		lever = { carry = 0.5, pop = 15, spin = 20, life = 1.5 },
	},

	-- The arc preview (src/client/Grenades): dots along the path every `step` seconds of flight, out to the first thing
	-- it hits or `time` seconds; each dot `size` studs, see-through (Palette.Grenades.Arc), the landing spot bigger.
	Arc = {
		step = 0.05,
		time = 4,
		size = 0.3, -- (Studio round 1: 0.18 at 0.45 see-through was near invisible)
		landSize = 0.8,
		transparency = 0.15,
	},

	-- Per grenade (Config/Weapons name):
	-- speed: studs/s at the throw. At 45 degrees it lands v^2 / g away: 128 -> ~84 studs (about 30 m, a Mills bomb
	-- thrown well; 0.357 m per stud), the stick's handle throws further (35 m).
	-- kg: the filling as TNT (Damage.blast, Config/Damage.Blast): Mills ~71 g, SIPE ~100 g, the M1917 stick ~170 g.
	-- fragments: the casing's splinters on soldiers the blast can see (the same cover lines, Config/Damage.Blast.Cover):
	-- `max` damage within `lethal` studs, then `near` falling to `far` at `wound`, none beyond (user: "lethal within
	-- about 8 studs, wounding to about 28"). The cast-iron Mills and SIPE throw fragments; the stick's thin can is mostly
	-- blast, so its fragments reach less.
	Types = {
		grenade_mills = {
			speed = 128,
			kg = 0.071,
			fragments = { lethal = 8, wound = 28, max = 100, near = 60, far = 10 },
		},
		grenade_sipe = {
			speed = 128,
			kg = 0.1,
			fragments = { lethal = 7, wound = 25, max = 100, near = 60, far = 10 },
		},
		grenade_stick = {
			speed = 139,
			kg = 0.17,
			fragments = { lethal = 4, wound = 14, max = 100, near = 50, far = 10 },
		},
	},

	-- The explosion (src/client/Vfx/Blast, shared with the staff and later cannons): a plain one sized by the charge, in
	-- the fire scheme (Config/Vfx.Schemes).
	Vfx = { scheme = "Ember" },
	-- Its bang (src/client/SoundFx entries): the staff's stage 1 impact without its magic crackle, a mortar's low thump
	-- and a sharp blast bang (Pro Sound Effects, already in the game: Config/Vfx staff sounds, ASSETS_LICENSES.md).
	Sound = {
		{ id = 9116973607, volume = 1.2, profile = "SpellBig" },
		{ id = 9114086424, volume = 0.6, fade = 1.5, profile = "SpellBig", eq = { 3, 0, -6 } },
	},
}

return Grenades
