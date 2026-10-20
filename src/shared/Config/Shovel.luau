--!strict
-- The shovel (docs/MILESTONES.md SV1; Config/Weapons.shovel, src/client/Shovel, src/server/Shovel). Data only.
-- Left click with the shovel in the hands digs (user 2026-10-20: a downward chop into the ground in front,
-- tools/animation/shovel.luau), and the dig goes down into the ground ("make the digging actually dig downwards into
-- the ground"): where the blade lands the ground is lowered a little more each dig, and dirt chips fly
-- ("make the destroy chipping into the ground"). Building trenches as pieces comes with the build system
-- (docs/ROADMAP.md 4.4).

local Shovel = {
	Dig = {
		length = 0.85, -- the animation's length (seconds); a click during a dig is ignored
		strike = 0.45, -- when the blade hits the ground, into the animation (its "struck" key)
		forward = 2.0, -- where the blade lands: this far ahead of the soldier's centre (studs, level; the dig's struck key)
		-- the ground there must be within this far above or below the feet (studs), or nothing is dug
		above = 1.5,
		below = 7,
		-- each dig lowers the ground by `depth` at the middle, less out to `radius` (a bowl, src/server/Ground.bowl;
		-- terrain voxels are 4 studs, so the radius reaches at least one voxel column's middle)
		depth = 0.75,
		radius = 4,
		-- never deeper than this below the ground as it first was (Config/Metrics.Trench.Depth)
		maxDepth = 5.5,
		cell = 4, -- the ground's first height is remembered per cell this wide (studs; the voxel size)
		feet = 3, -- the feet below the HumanoidRootPart's centre (R6: 2-stud legs, half the 2-stud torso)
		slack = 0.9, -- the server takes a dig this share of `length` after the last (the network's jitter)
	},
	-- the dirt thrown up where the blade bites (src/client/Impacts burst; the ground's own colour)
	Chips = { count = 12, size = 0.32, speed = 8, up = 14, gravity = 55, drag = 1.5, life = 1.0 },
}

return table.freeze(Shovel)
