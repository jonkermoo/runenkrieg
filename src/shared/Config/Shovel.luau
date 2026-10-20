--!strict
-- The shovel (docs/MILESTONES.md SV1; Config/Weapons.shovel, src/client/Shovel). Data only.
-- Left click with the shovel in the hands digs (user 2026-10-20: a chop swung over the right shoulder and down into the
-- ground in front, tools/animation/shovel.luau). The animation only (user 2026-10-20: "no digging the earth. just
-- focus on the animation"); digging trenches and destroying player-built structures come with the build system
-- (docs/ROADMAP.md 4.4).

local Shovel = {
	-- one dig: the animation's length (seconds); a click during a dig is ignored
	Dig = { length = 0.85 },
}

return table.freeze(Shovel)
