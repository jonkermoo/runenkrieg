--!strict
-- The shovel (docs/MILESTONES.md SV1; Config/Weapons.shovel, src/client/Shovel). Data only.
-- Left click with the shovel in the hands digs, swung by the shovel's mode (src/client/Build; user 2026-10-23,
-- tools/animation/shovel.luau): in Build a scoop, in Destroy a stab and chip. The animation only (user 2026-10-20: "no
-- digging the earth. just focus on the animation"); digging trenches and destroying player-built structures come with
-- the build system (docs/ROADMAP.md 4.4).

local Shovel = {
	-- one swing: its animation's length (seconds); a click during a swing is ignored. Dig in Build mode (the scoop),
	-- Chip in Destroy mode
	Dig = { length = 1.0 },
	Chip = { length = 0.7 },
}

return table.freeze(Shovel)
