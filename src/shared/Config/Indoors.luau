--!strict
-- Going into buildings as a soldier who isn't a player (user 2026-11-01: bots can enter buildings too): doors and
-- stairs pathfinding routes through (src/server/Doors, src/server/Indoors), and the spots inside a building a soldier
-- could use (src/server/Indoors, worked out by Rules/Indoors from the walls). Data only.

local Indoors = {
	-- every part of a door gets a PathfindingModifier with this label, passing through, so a path isn't stopped by a
	-- door open or shut
	Door = { label = "Door" },
	-- A doorway (4.6 wide) is too narrow for the navmesh with the bots' agent (radius 1.6, Config/Bots.Move), and some
	-- flights of stairs too, so each gets a PathfindingLink (both ways): a doorway's from `approach` studs out of its
	-- outer face to as far in from its inner face, each end dropped onto whatever is under it within `drop` studs (no
	-- link if the ground is farther: a door up a bank), the outside end moved out up to `further` studs (one at a time)
	-- until a soldier has room there (a pole or a fence in front of the door); a flight's from the floor `out` studs
	-- beside it, `up` studs along from its foot, to `past` studs beyond its top step (or the top step itself when there's
	-- no room there)
	Links = {
		door = "Door",
		stairs = "Stairs",
		approach = 4,
		drop = 4,
		further = 4,
		up = 2.4,
		out = 2.5,
		past = 1,
	},
	-- Costs for CreatePath: through a doorway costs a bit more (a way round through an open gap wins when it is about as
	-- short)
	PathCosts = { Door = 2, Stairs = 1 },

	Spots = {
		stand = 2, -- studs from a wall's inner face to where a soldier stands (a firing spot at a window, cover behind)
		side = 1.6, -- studs past a doorway's edge to the spots either side of it, inside
		coverWidth = 3, -- the narrowest stretch of solid wall that counts as cover
		spacing = 3.5, -- no cover spot within this of another spot
		-- standing room: a box this wide (studs, each way from the spot) and tall over the floor must be clear of the
		-- building, and the floor found within `floorProbe` under the spot
		clearance = 1.4,
		height = 4.6,
		lift = 0.3, -- the box starts this far over the floor (a doorstep or a rug doesn't count)
		floorProbe = 3,
	},
}

return table.freeze(Indoors)
