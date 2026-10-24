--!strict
-- The shovel (docs/MILESTONES.md SV1; Config/Weapons.shovel, src/client/Shovel). Data only.
-- Left click with the shovel in the hands digs, swung by the shovel's mode (src/client/Build; user 2026-10-23,
-- tools/animation/shovel.luau): in Build a dig tossed over the shoulder, in Destroy a charged strike. Holding the
-- fire key keeps swinging.

local Shovel = {
	-- one swing, a looping animation (Config/Weapons.shovel holds dig / chip), Dig in Build mode, Chip in Destroy mode
	-- (user 2026-10-24: "hold left click to continuously do the animation ... once left click is let go, after tossing
	-- over shoulder, it will go back to its idle animation"): `length` one swing (seconds); `strike` when the blade
	-- meets the ground (its "Strike" marker: the hit lands, src/client/Build); `rest` where a swing let go of settles
	-- back to the ready (its "Rest" marker: after the toss, or the chip wrenched loose)
	Dig = { length = 2.6, strike = 0.45, rest = 1.82 },
	Chip = { length = 1.5, strike = 0.5, rest = 1.0 },
	Enter = 0.35, -- the blend up from the ready into the first swing (seconds)
	Leave = 0.5, -- the blend from a swing's rest back to the ready
}

return table.freeze(Shovel)
