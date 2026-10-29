--!strict
-- Spent cases and belt links thrown off a gun as it fires (src/client/CaseDrop; user 2026-10-29: "can you add shell
-- case droppings and sounds? ... accordingly to what kind of shell they use"). Each piece falls with real gravity,
-- tumbling, and clinks once where it first lands, a sound for its kind. Studs, seconds. Data only.

local Cases = {
	-- the flight: real gravity (studs/s², 9.81 m/s² at 0.357 m a stud; Roblox's own is 196.2), a tumble of up to
	-- `spin` rad/s on each axis; on landing it keeps `bounce` of its speed (and tumble) for up to `bounces` bounces,
	-- lying down for good once slower than `settle` studs/s; gone `life` s after it was thrown
	gravity = 27.5,
	spin = 25,
	bounce = 0.3,
	bounces = 2,
	settle = 3,
	life = 4,
	-- a gun's spent case (dropped with its cartridge's `case`, Config/Weapons `casing`: pitch, volume, eq) lies where it
	-- fell longer, `rest` s, the oldest going once more than `max` lie about (the MG's cases and links don't count)
	rest = 30,
	max = 60,
	-- a round case rolls off at `rollLeast` to all of its kind's `roll`; kept on the ground by looking for it from
	-- `rollReach` studs above (off an edge, it falls again)
	rollLeast = 0.4,
	rollReach = 0.5,
	-- what it lands on (Rules/Casing): brass on dirt or grass is a dull tick (the highs soaked up), on wood a knock, on
	-- stone a ring, on metal a brighter one: a share of the clink's volume and an eq (dB, low / mid / high) on top of its
	-- own; a material not listed is `default`. (Into water it sinks without a sound.)
	surfaces = {
		Soft = { volume = 0.35, eq = { 0, -6, -18 } },
		Wood = { volume = 0.7, eq = { 2, -2, -8 } },
		Hard = { volume = 1, eq = { 0, 0, 0 } },
		Metal = { volume = 1.1, eq = { 0, 0, 3 } },
	},
	materials = {
		Grass = "Soft",
		LeafyGrass = "Soft",
		Ground = "Soft",
		Mud = "Soft",
		Sand = "Soft",
		Snow = "Soft",
		Salt = "Soft",
		Fabric = "Soft",
		Carpet = "Soft",
		Wood = "Wood",
		WoodPlanks = "Wood",
		Cardboard = "Wood",
		Metal = "Metal",
		CorrodedMetal = "Metal",
		DiamondPlate = "Metal",
		Foil = "Metal",
	},
	default = "Hard", -- (stone, brick, concrete, cobbles, rock, ice, glass, plastic)
	-- a clink at most every `gap` s (a machine gun drops 15 pieces a second; one clink each would be a hiss)
	gap = 0.05,
	-- each kind of piece: what it sounds like when it lands (one variant picked a drop, its pitch spread by +/-
	-- `spread`; Pro Sound Effects "Bullet Drops 5 / 7 / 8 / 9", a .45 case dropped on concrete, its clink and a bounce
	-- or two), `life` s it lasts if not `life` above, `roll` studs/s at most it rolls on across the ground once down
	-- (a round case; slowing by `rollSlow` studs/s²)
	Sounds = {
		-- a big rifle case (.50 BMG, 99 mm long): the .45's clink pitched down. A machine gun's: gone sooner, 15 pieces
		-- a second (user 2026-10-29: "you can make it despawn faster than usual since it's a mg with a lot of ammo, but
		-- make sure it still exists long enough to hit the ground and roll")
		Heavy = {
			life = 2.5,
			roll = 2,
			rollSlow = 4,
			pitch = 0.75,
			spread = 0.08,
			variants = {
				{ id = 9113631202, volume = 0.45, profile = "Mechanism" },
				{ id = 9113631210, volume = 0.45, profile = "Mechanism" },
				{ id = 9113631432, volume = 0.45, profile = "Mechanism" },
				{ id = 9113631437, volume = 0.45, profile = "Mechanism" },
			},
		},
		-- a rifle's or pistol's case (and the shotgun's hull): Pro Sound Effects "Bullet Drops 1 / 9 / 12 / 14 / 6"
		-- (single clinks, 6 with a bounce), from `start` just before the first hit to `stop` once rung out (measured
		-- 2026-10-29), at its gun's `case` pitch (a long rifle case rings lower than a pistol's), on falloff profile
		-- Casing. Lasts `rest` (above), rolling on a little once down.
		Cartridge = {
			roll = 2.5,
			rollSlow = 5,
			pitch = 1,
			spread = 0.05,
			variants = {
				{ id = 9113630936, volume = 1.4, start = 0.17, stop = 0.8, fade = 0.3, profile = "Casing" },
				{ id = 9113631437, volume = 1.4, start = 0.14, stop = 0.45, fade = 0.15, profile = "Casing" },
				{ id = 9113631610, volume = 1.4, start = 0.12, stop = 0.95, fade = 0.3, profile = "Casing" },
				{ id = 9113631717, volume = 1.4, start = 0.13, stop = 0.95, fade = 0.3, profile = "Casing" },
				{ id = 9113631209, volume = 1.4, start = 0.2, stop = 0.9, fade = 0.3, profile = "Casing" },
			},
		},
		-- a steel belt link: small, thin and light, a quick high tink
		Link = {
			life = 2,
			pitch = 1.45,
			spread = 0.1,
			variants = {
				{ id = 9113631210, volume = 0.25, stop = 0.4, fade = 0.15, profile = "Mechanism" },
				{ id = 9113631432, volume = 0.25, stop = 0.4, fade = 0.15, profile = "Mechanism" },
			},
		},
	},
}

return Cases
