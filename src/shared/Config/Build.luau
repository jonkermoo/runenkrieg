--!strict
-- Player building (phase 4.4, stage 1; user 2026-10-22: everyone builds with the shovel, the cost is shovel swings
-- plus caps, trenches carved in the terrain, the pieces flat-coloured code-built shapes until meshes are approved).
-- Rules/Build decides, src/server/Build builds, src/client/Build shows build mode. Data only.
--
-- Build mode: the shovel in the hands, Key_Build toggles it; the mouse wheel picks a piece, Key_BuildTurn turns it,
-- a click lays its blueprint. The shovel's mode (Key_Reload toggles Build / Destroy, user 2026-10-23): a Build swing at
-- a piece of your team adds one unit of work; at `work` it stands. A Destroy swing at any piece, any team's, takes one
-- off; at 0 it is torn down (a trench falls in). Destroy swings also chop trees (Config/Damage.Trees.Chop).

local Build = {
	-- how far from the builder's root a piece can be laid, and a swing reach its piece (studs, to the piece's footprint)
	Reach = 14,
	SwingReach = 8,
	-- swings faster than this share of the dig's length (Config/Shovel.Dig.length) are ignored
	SwingSlack = 0.8,
	-- a blueprint nobody has worked on goes after this (seconds)
	BlueprintLife = 120,
	-- live pieces (blueprints count) per player and per team
	PerPlayer = 8,
	PerTeam = 150,
	-- where the pieces live (a Folder in Workspace)
	Folder = "Structures",
	-- blueprint look: its parts this transparent until it stands
	GhostTransparency = 0.75,
	-- the ghost in build mode (src/client/Build): fill colours where it can / can't go
	Ghost = { ok = { 120, 200, 120 }, bad = { 220, 80, 70 }, transparency = 0.55 },
	-- the turn step (degrees) for Key_BuildTurn and a mouse wheel notch with Shift
	TurnStep = 15,

	-- Trenches v2 (user 2026-10-23; design page https://claude.ai/artifact/FRZKPxjdaq3nXAzFwWwFb6): carved into the
	-- terrain like the howitzer's pit (user: "I really like how the mortar dug out is like ... make it like that"),
	-- src/server/Trenches. A plan is one straight run, click start, click end (src/client/Build), up to `maxPlan`
	-- studs, split into blocks of up to `block` studs (at least `minBlock`); the plan is pegged out with markers
	-- everyone sees. Each block is dug on its own: `work` swings, deeper at each stage. A plan's end on a free end of a
	-- trench joins it end to end (up to `maxBend` off straight); on a block's side, a T. A plan may not cross a trench
	-- (user: "connect the trench then continue from the other side").
	-- Segments (user 2026-10-23: "make each segment a fixed size", "make each segment distinct", "trenches should be
	-- treated like other structures. they have hp. how dug in they are are determined by hp"): a run is split into
	-- segments of `block` studs, each pegged out with its own string outline until it is dug full, and each with HP:
	-- its depth is HP / MaxHP of the full depth.
	Trench = {
		block = 8, -- (user 2026-10-23: fixed 8-stud segments; Rules.planBlocks for the leftover)
		minBlock = 2,
		maxPlan = 60,
		firstReach = 14, -- the first click this close to you
		joinReach = 4, -- a plan's end this close to a free end joins it
		maxBend = 135,
		maxSlope = 22, -- degrees of ground slope along the run
		planLife = 180, -- seconds an undug plan stays
		swingReach = 8, -- a swing works the square whose line is this close, in front of you
		-- a square's HP: a Build swing adds `swing` (up to `max`), a Destroy swing takes `destroy` off; blasts take HP by
		-- their overpressure at the square (Blast below). Once dug full it keeps its full shape and pieces until its HP
		-- is below `cave`, then caves in with what's left (user 2026-10-24: "the trenches break too easily. make it start
		-- burrowing at a way lower % after it's been built. it also should be way way more durable")
		hp = { max = 100, swing = 34, destroy = 4, cave = 30 },
		-- the shape: floor half width, depth, walls at `wallAngle` (too steep to walk up: Metrics MaxSlopeAngle 50),
		-- earth thrown up as a bank along both edges (the pit's rim)
		-- (carved in 4-stud voxels the floor rounds into a bowl and the walls soften: Studio round t1023-2101 measured a
		-- 6-wide floor as a narrow bowl and 60 degree walls as 45-55, so the carve is wider at the floor and steeper)
		floor = 4.25, -- (user 2026-10-23: 1.5x wider, then "a little more narrow")
		depth = 5.5,
		-- (user 2026-10-23: "just make it a wall with less slope ... no invisible steps": no wall grip)
		wallAngle = 70, -- (user 2026-10-23: steeper, "it could be either deeper or less slopy")
		bank = { width = 5, height = 1.2 },
		-- a filled-in block leaves a scar: a lumpy dip this deep, churned earth, no grass
		scar = { depth = 0.6 },
		-- markers: pegs every `every` studs along both top edges, string between, a flag at each end
		-- (0.9 high pegs were lost in the tall grass, Studio round t1023-2101)
		markers = { peg = { 0.25, 1.6 }, flag = 3, string = 0.08 },
		-- the dirt pieces of a square dug full (Config/Assets trench_pieces, tools/blender/trench/trench_pieces.py; user
		-- 2026-10-23: "make wide variety of random wall and floor segments ... and include wood on the wall ones"): one
		-- wall a side (Wall1..`walls`) and a floor (Floor1..`floors`), rolled from its seed (Rules.trenchPieces); the
		-- `wood` walls carry plank steps, rolled at `woodChance` a side, never on two squares in a row on one side. Made
		-- `segment` long, stretched along a shorter square; a dead end gets a plain wall across.
		pieces = { segment = 8, walls = 8, floors = 4, wood = { 5, 6, 7, 8 }, woodChance = 0.25 },
		-- a blast fills a square in: from `from` kPa it loses HP, all of it at `full`. Inside the trench the pressure is
		-- taken at the blast's distance past the floor's edge; within `zone` trench widths past the top edge (user
		-- 2026-10-23: "the hitbox should extend out about another trench size") as if it went off `edge` studs away
		-- (a grenade takes about a third, a shell fills it); further out, `edge` plus how far past the zone
		-- (a blast at `full` takes `share` of the HP: way more durable, user 2026-10-24)
		blast = { from = 150, full = 900, zone = 1, edge = 2.5, share = 0.15 },
		-- clods knocked off the walls each destroy swing (client debris; not by blasts)
		clods = { perSwing = 6, size = { 0.5, 1.2 } },
	},

	-- Every piece you can lay, in the order the build menu lists them.
	Pieces = {
		{
			key = "Trench",
			name = "Trench",
			kind = "Trench", -- planned by two clicks, dug block by block (Trench above)
			work = 8,
		},
		{
			key = "LowWall",
			name = "Sandbags (low)",
			kind = "Sandbags",
			work = 4,
			-- `columns` of bags, each a section, `rows` high (each row `row` studs), `depth` thick, `width` wide
			width = 6,
			depth = 2.2,
			columns = 3,
			rows = 3,
			row = 1.0,
			maxSlope = 25,
		},
		{
			key = "HighWall",
			name = "Sandbags (high)",
			kind = "Sandbags",
			work = 6,
			width = 6,
			depth = 2.6,
			columns = 3,
			rows = 5,
			row = 1.1,
			-- a loophole: this row of the middle column left open (the standing aimed muzzle, 4.3 high, looks out)
			loophole = 4,
			maxSlope = 25,
		},
		{
			key = "Wire",
			name = "Barbed wire",
			kind = "Wire",
			work = 3,
			width = 12,
			depth = 3,
			height = 2.5,
			pickets = 4,
			maxSlope = 30,
		},
	},

	-- Sandbags: each column a section of class "Sandbag" (Config/Damage.Blast.Fail), shovels tear the whole piece down
	Sandbags = { columnHP = 400, shade = 0.06 },

	-- Barbed wire: anyone inside its box (both teams) is "Wired": walks at `speed`, can't sprint or jump
	-- (src/client/Stance), and loses `damage` health a second while moving faster than `moving` studs/s. Bullets pass
	-- (its parts aren't queried); a blast cuts it at `failKPa` or more at its line.
	Wire = { speed = 3, damage = 4, moving = 1, tick = 0.25, failKPa = 60 },
}

return table.freeze(Build)
