--!strict
-- The shovel (docs/MILESTONES.md SV1; Config/Weapons.shovel, src/client/Shovel). Data only.
-- Left click with the shovel in the hands digs, swung by the shovel's mode (src/client/Build; user 2026-10-23,
-- tools/animation/shovel.luau): in Build a scoop, in Destroy a stab. Holding the fire key keeps swinging.

local Shovel = {
	-- one swing, Dig in Build mode (the scoop), Chip in Destroy mode: `length` its animation's (seconds); held down
	-- (user 2026-10-24: "hold left click to continuously do the animation"), the next swing starts `cycle` into this one,
	-- `skip` into its own animation (past the ready pose: no return to it between swings), blended over ChainFade; a
	-- click before `cycle` is ignored
	Dig = { length = 1.1, cycle = 0.78, skip = 0.1 },
	Chip = { length = 0.55, cycle = 0.42, skip = 0.08 },
	ChainFade = 0.15,
}

return table.freeze(Shovel)
