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
	-- the trench square you're working, extending or branching off is lit faintly (a Highlight in Palette.Build.Focus:
	-- its fill and outline transparency; user 2026-10-25: "a slight slight indicator for which segment you are focused on")
	Focus = { fill = 0.93, outline = 0.6 },
	-- swings faster than this share of the shortest time between two strikes (Rules/Build.strikeGap) are ignored
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
	-- the trench planner's ghost (src/client/Build; user 2026-10-24: "make the entire planning thing better and more
	-- stylish"), a preview of the stakes and cord the
	-- server lays: per square a faint fill (Ghost ok / bad, `fill` see-through) with the dug floor's band in it
	-- (`floor`), a chalk cord round it (`cord` wide, `cordSee` see-through; Palette.Build.Chalk, ChalkBad when it can't
	-- go), `gap` between squares, ghost stakes (`peg`: width, height, one at the cursor before the
	-- first click; no flags, user 2026-10-24: "lets just do the stakes"); squares fade in and out at `fade` per second. Reach circles (Trench.firstReach) dashed on the ground: `dashes`
	-- dashes, each `dash` of its step, `ringWidth` wide; the one you stand in `near` see-through, the other `far`. The
	-- length tag floats `tag` studs over the end.
	Plan = {
		fill = 0.82,
		floor = 0.7,
		cord = 0.14,
		cordSee = 0.1,
		gap = 0.3,
		peg = { 0.22, 1.0 },
		fade = 12,
		dashes = 44,
		dash = 0.55,
		ringWidth = 0.18,
		near = 0.2,
		far = 0.6,
		tag = 4.6,
		-- the action icon over each end (user 2026-10-24: "one icon for new trenches, one more extending"): a round badge
		-- `size` studs across on a chalk pin `height` studs tall
		badge = { height = 2.4, size = 1.4 },
	},
	-- the turn step (degrees) for Key_BuildTurn and a mouse wheel notch with Shift
	TurnStep = 15,

	-- Trenches v2 (user 2026-10-23): carved into the
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
		-- the first click this close to you, and when the plan is laid you within this of either end (you may walk along
		-- it while planning; the planner shows it red with the reason as soon as you're too far, user 2026-10-24)
		firstReach = 14,
		-- a plan's end this close to a free end joins it (8 since the wider 59 degree walls: 4 was easy to miss, user
		-- 2026-10-24: "the trenches dont connect")
		joinReach = 8,
		-- a new trench keeps this far (between centre lines) from every other trench, except near the end where it joins
		-- one (user 2026-10-24: "you shouldnt be able to build a new trench within a certain distance of another trench
		-- unless you're extending"; 32 since the parapets: two trenches' parapets just meet)
		spacing = 32,
		maxBend = 135,
		maxSlope = 22, -- degrees of ground slope along the run
		planLife = 180, -- seconds an undug plan stays
		-- a swing works the square whose line is this close, in front of you (19: from anywhere on its dirt, out to the
		-- skirt past its heap, joins.heapReach; user 2026-10-25: "can you extend the trench hitbox")
		swingReach = 19,
		-- a square's HP: a Build swing adds `swing` (up to `max`), a Destroy swing takes `destroy` off; blasts take HP by
		-- their overpressure at the square (Blast below). Once dug full it is buried by what it loses: full depth down to
		-- `hold`% HP, then filled in with the rest (80%: a little earth in it; 5-10%: nearly level, unusable), its pieces
		-- under the fill (user 2026-10-24: "an 80% trench should start visibly filling a little bit, but not an unusable
		-- amount"; "way way more durable")
		-- (5 Build swings dig a square: "make building take a bit longer", user 2026-10-24)
		-- (a square buried under `bare`% HP loses its dirt pieces: it just fills with earth, its neighbours add no walls,
		-- user 2026-10-25: "just make it fill, no need to add additional walls"; dug back up past it, they return)
		hp = { max = 100, swing = 20, destroy = 4, hold = 95, bare = 75 },
		-- the shape: floor half width, depth, walls at `wallAngle` (Metrics MaxSlopeAngle decides whether you can walk
		-- up them), earth thrown up as a bank along both edges (the pit's rim) under each wall's parapet (Config/Assets
		-- trench_pieces Wall<i>Parapet: a thick heap of dirt just behind the wall's top edge, about 2.1 to 2.5 over the
		-- ground, a 74 degree face toward the trench: too steep to walk up, chest high cover to shoot over)
		-- (carved in 4-stud voxels the floor rounds into a bowl and the walls soften: Studio round t1023-2101 measured a
		-- 6-wide floor as a narrow bowl and 60 degree walls as 45-55, so the carve is wider at the floor and steeper)
		floor = 4.25, -- (user 2026-10-23: 1.5x wider, then "a little more narrow")
		depth = 5.5,
		-- (user 2026-10-23: "just make it a wall with less slope ... no invisible steps": no wall grip)
		-- (user 2026-10-23: steeper, 70, "it could be either deeper or less slopy"; 2026-10-24: "make this less steep
		-- (just a bit) so our character can walk out of (not smoothly and easily of course)", 48, then "make the slope
		-- more aggressive. have an inbetween from what we had before and now")
		wallAngle = 59,
		bank = { width = 5, height = 1.2 },
		-- a bullet meeting the ground this close round a square's hole, walls and banks hits the square (studs; the
		-- terrain is carved in 4-stud voxels, so a shot at a wall often meets the ground just in front of its slab)
		shotSlack = 2,
		-- a filled-in block leaves a scar: a lumpy dip this deep, churned earth, no grass
		scar = { depth = 0.6 },
		-- markers (src/server/Trenches; user 2026-10-24): a
		-- stake (width, height) at each corner of a square, its top `top` studs painted (Palette.Build.PegTop), cord
		-- `string` wide between the stake tops sagging by `sag` of its length (a Beam's curve); no flags
		-- (user 2026-10-24: "i dont think we need a flag. lets just do the stakes"). (0.9 high pegs were lost in the tall grass, Studio round t1023-2101)
		markers = { peg = { 0.25, 1.6 }, top = 0.3, string = 0.08, sag = 0.035 },
		-- the dirt pieces of a square dug full (Config/Assets trench_pieces, tools/blender/trench/trench_pieces.py; user
		-- 2026-10-23: "make wide variety of random wall and floor segments ... and include wood on the wall ones"): one
		-- wall a side (Wall1..`walls`) and a floor (Floor1..`floors`), rolled from its seed (Rules.trenchPieces); the
		-- `wood` walls carry plank steps, rolled at `woodChance` a side, never on two squares in a row on one side. Made
		-- `segment` long, stretched along a shorter square; a dead end gets a plain wall across.
		pieces = { segment = 8, walls = 8, floors = 4, wood = { 5, 6, 7, 8 }, woodChance = 0.25 },
		-- where pieces meet (src/server/Trenches; user 2026-10-24: "make sure that the joints connect by the walls"): how far
		-- out past a wall's top edge its dirt heap and the skirt behind it reach (they keep that whole depth out of other
		-- trenches; the skirt since 2026-10-25, trench_pieces v8 Wall<i>Apron), and how much further the side heaps run on
		-- round a dead end and its heap reaches past the side walls' tops
		joins = { heapReach = 11, deadEndHeap = 3 },
	},

	-- What each weapon does to built things (user 2026-10-24: "a revamp on damage to built structures ... rifles and
	-- weapons will do damage to a trench too, but just not a lot. most of it will be explosives. grenades and staffs
	-- should do the least, howitzer the most"): `hit`, the % of a trench square's or a sandbag column's max HP it takes,
	-- in full within `edge` studs of it (the entry's own `edge` if it has one; a trench: its hole, walls and banks, so a blast on the bank counts; user:
	-- "make the ground around each segment to also be part of the trench hit box"), fading to nothing at `reach`;
	-- `wire`, the % of a barbed wire's HP. Bullets only by a direct hit. A blast nobody named (DEV tools) by its
	-- charge: the first of `byCharge` it is no bigger than. (A Destroy swing is Trench.hp.destroy.)
	Structures = {
		edge = 2,
		wireHP = 100,
		bullet = { hit = 0.2, wire = 0 }, -- (about 500 hits bury a trench)
		grenade = { hit = 3, reach = 6, wire = 15 },
		staff1 = { hit = 0.5, reach = 4, wire = 0 },
		staff2 = { hit = 1.5, reach = 6, wire = 5 },
		staff3 = { hit = 4, reach = 10, wire = 15 },
		field = { hit = 33, reach = 10, edge = 3, wire = 100 }, -- (three bury a trench)
		howitzer = { hit = 93, reach = 20, edge = 8, wire = 100 }, -- (buries it at once, 7% left)
		byCharge = {
			{ kg = 0.5, source = "grenade" },
			{ kg = 5, source = "field" },
			{ kg = math.huge, source = "howitzer" },
		},
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
	-- (its parts aren't queried); blasts wear it down and cut it (Structures above).
	Wire = { speed = 3, damage = 4, moving = 1, tick = 0.25 },
}

return table.freeze(Build)
