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
	-- a round case rolls off at `rollLeast` to all of its kind's `roll`; kept on the ground by looking for it from
	-- `rollReach` studs above (off an edge, it falls again)
	rollLeast = 0.4,
	rollReach = 0.5,
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
