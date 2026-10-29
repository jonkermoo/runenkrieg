--!strict
-- Spent cases and belt links thrown off a gun as it fires (src/client/CaseDrop; user 2026-10-29: "can you add shell
-- case droppings and sounds? ... accordingly to what kind of shell they use"). Each piece falls with real gravity,
-- tumbling, and clinks once where it first lands, a sound for its kind. Studs, seconds. Data only.

local Cases = {
	-- the flight: real gravity (studs/s², Roblox's own is 196.2), a tumble of up to `spin` rad/s on each axis, held on
	-- real gravity for `flight` s (then left to the world's), gone after `life` s
	gravity = 27.5,
	spin = 25,
	flight = 1.2,
	life = 4,
	-- a clink at most every `gap` s (a machine gun drops 15 pieces a second; one clink each would be a hiss)
	gap = 0.05,
	-- what each kind sounds like when it lands: one variant picked a drop, its pitch spread by +/- `spread`. Pro Sound
	-- Effects "Bullet Drops 5 / 7 / 8 / 9" (a .45 case dropped on concrete, its clink and a bounce or two)
	Sounds = {
		-- a big rifle case (.50 BMG, 99 mm long): the .45's clink pitched down
		Heavy = {
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
