--!strict
-- Player building (phase 4.4, stage 1; user 2026-10-22: everyone builds with the shovel, the cost is shovel swings
-- plus caps, trenches carved in the terrain, the pieces flat-coloured code-built shapes until meshes are approved).
-- Rules/Build decides, src/server/Build builds, src/client/Build shows build mode. Data only.
--
-- Build mode: the shovel in the hands, Key_Build toggles it; the mouse wheel picks a piece, Key_BuildTurn turns it,
-- a click lays its blueprint. Each dig swing at a blueprint of your team adds one unit of work; at `work` it stands.
-- A swing at another team's piece takes one off; at 0 it is torn down (a trench filled in).

local Build = {
	-- how far from the builder's root a piece can be laid, and a swing reach its piece (studs, to the piece's footprint)
	Reach = 14,
	SwingReach = 8,
	-- swings faster than this share of the dig's length (Config/Shovel.Dig.length) are ignored
	SwingSlack = 0.8,
	-- a blueprint nobody has worked on goes after this (seconds)
	BlueprintLife = 60,
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

	-- Trenches (Config/Metrics.Trench sizes): a segment is `length` long, carved into the terrain in `stages` cuts as
	-- it is worked; the floor 6 wide, a firestep in front, earth thrown up as a parapet in front, plank revetments.
	-- Ends within `snap` of a free end of your team's trench join it (the cut runs on past a joined end by `overlap`
	-- so corners meet). Every point of a trench line must be within Metrics MaxExitSpacing of a way out: an open end
	-- (a ramp up out of the trench) or an exit piece (a ramp out of the back).
	Trench = {
		length = 12,
		snap = 4,
		overlap = 3.5,
		stages = 3,
		-- the profile across the trench, from the back (negative) to the front (positive), studs from the centre line
		back = -3, -- the back wall (the floor runs from here ...)
		front = 3, -- (... to here, then the firestep)
		parapet = { width = 6, height = 1.6 }, -- earth thrown up past the front wall, peaked in its middle
		parados = { width = 4, height = 0.6 }, -- a lower bank behind
		ramp = { length = 10, width = 5 }, -- an open end's ramp up (along the trench), and the exit piece's (out the back)
		maxSlope = 22, -- degrees of ground slope along the segment
		-- the revetment planks and the firestep: wood sections (Config/Damage.Blast.Fail Wood), so blasts break them
		plankThickness = 0.4,
		plankHP = 300,
		-- a blast that reaches the trench line at this overpressure caves it in there: the ground put back within
		-- the class's reach (Rules/Blast.reachOf), and the trench loses work by the share of its length caved
		caveKPa = 400,
	},

	-- Every piece you can lay, in the order the build menu lists them.
	Pieces = {
		{
			key = "Trench",
			name = "Trench",
			kind = "Trench",
			work = 8,
		},
		{
			key = "TrenchExit",
			name = "Trench exit",
			kind = "Trench",
			exit = true, -- a ramp out of the back wall in its middle
			work = 10,
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
