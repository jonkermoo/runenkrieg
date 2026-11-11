--!strict
-- Map 1: the English valley. Rebuilt on the leg pattern (map rework, user approved 2026-11-10, "Yes, build it";
-- docs/maps/MAP_RULES.md), as Lantern Meadows: points ~520 apart on a step (the chain drops south from S1, runs level
-- through the valley, drops again to the church), every leg between two points built the same way
-- (Rules/MapTerrain.legPieces: a crest on each approach, the attackers' sunken lanes, open dig ground, MG knolls, gun
-- pads; `legs` below), spawns at the front sector's rally and a sector back once it's attacked (Config/Frontline
-- .Fallback). S1 the beacon farm (West HQ), S2 the oast farm, S3 the coaching crossroads, S4 Ashby, S5 the church
-- close (East HQ). X runs along the front (west = West team), Z is lateral. Units: studs. Rationale: docs/maps/MAP1.md.

export type Sector = {
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	startOwner: "West" | "East" | "Neutral",
	isHQ: boolean?,
	rally: number?,
	crest: boolean?,
}

export type Divider = { between: { string }, points: { { number } }?, river: boolean? }

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

-- The points: a step, the two end legs turning 22° south, the middle two 3° north (user 2026-11-06: "variety in
-- direction (not too much that the map gets complicated)"), point-symmetric about S3 so each side's legs are alike.
local PTS = { { 420, 160 }, { 889, -26 }, { 1420, 0 }, { 1951, 26 }, { 2420, -160 } }

-- The leg pattern (Rules/MapTerrain: legPieces, rally, tactics; the numbers explained there and in MAP_RULES.md), as
-- Lantern Meadows
local LEGS = {
	-- a natural rise, not a straight bank (user 2026-11-10: "just make it natural looking rises"): wider, its line
	-- wandering up to `bend` studs toward or away from the point, its height and its ends varying (Rules/MapTerrain.legsAt)
	crest = {
		u = 100,
		half = 110,
		height = 8,
		width = 52,
		taper = 45,
		bend = 18,
		bendScale = 70,
		vary = 0.8,
		reach = 0.4,
		-- lumpy, not one long bank (user 2026-11-10: "still too obviously placed (the hills)"): the bank whole only round
		-- its middle, a row of hillocks of their own sizes over it (Rules/MapTerrain.hillocks)
		lumps = {
			count = 5,
			base = 0.65,
			core = 70,
			fade = 40,
			radius = { 24, 40 },
			height = { 0.55, 1.0 },
			shift = 12,
			forward = true,
			across = 0.65,
			stretch = 1.4,
		},
	},
	-- a broad lumpy swell across each leg's middle: dead ground both ways, and the point beyond the next one out of
	-- sight (user 2026-11-10: "not every sector visible"); none by the river
	swell = {
		at = 0.5,
		half = 200,
		taper = 80,
		width = 110,
		height = 6,
		riverClear = 30,
		riverFade = 40,
		lumps = { count = 7, core = 60, radius = { 40, 75 }, height = { 0.6, 1.2 }, shift = 30, stretch = 1.3 },
	},
	-- no sunken lane cut here (user 2026-11-10: "remove the old trenches"): `depth` 0; the line still marks where the
	-- enemy's attack forms up (the bots' gather spots)
	fold = { u = 170, half = 120, depth = 0, floor = 4, wall = 6, ends = 20 },
	knoll = { u = 90, n = 175, height = 9, top = 6, radius = 30 },
	guns = { u = 140, n = 110, howitzer = 210, pad = 9, fade = 12 },
	rally = 60,
	calm = { width = 230, fade = 80, keep = 0.55 },
	-- the rolling ground calm round each rally, so it never lifts a waiting wave over its own crest
	rallyCalm = { radius = 40, fade = 40 },
	-- copses and lone trees on the open ground (user 2026-11-10: "add more trees and such in the really open field. it
	-- looks really empty"), none within `lane` of the way between the points, round a knoll, a gun pad or a rally
	open = {
		scale = 55,
		threshold = 0.42,
		copse = 0.42,
		lone = 0.012,
		lane = 30,
		knollClear = 34,
		padClear = 22,
		rallyClear = 45,
	},
	flagClear = 25, -- no marked spot this close to a flag (the point gets shelled)
	-- the bots' marked spots (Rules/MapTerrain.tactics), as Lantern Meadows (its comment explains each)
	spots = {
		zone = { angle = 45, clear = 10, inset = 8 },
		crestCover = { back = 4, across = { -80, 0, 80 } },
		crestSupport = { back = 6, across = { -55, 55 } },
		zoneMg = 25,
		rake = 0.7,
		trench = { back = 3, runs = { { -100, -40 }, { 40, 100 } } },
		gather = { out = 2, across = { -80, 0, 80 } },
		laneEnds = { out = 10, past = 40 },
	},
}

local Map1 = {
	name = "Map 1",
	seed = 1337,
	-- the two nations that fight here (user 2026-11-04, "fixed pair per map": Rules/Frontline.mapPair), Katzmark always
	-- one of them; the Allies (Selvara, Sowilo) wear the map's own
	pair = { West = "uniform1", East = "uniform3" },
	bounds = rect(-90, 2930, -420, 420),
	terrainMargin = 420, -- detailed terrain + forest past the bounds; relief fades to flat at its edge
	-- Low-detail flat skirt beyond the margin plus distant hills, so the world edge never shows.
	skirt = {
		width = 1000,
		hills = {
			{ -1243, -820, 300, 110 },
			{ 429, -1270, 360, 130 },
			{ 1714, -1220, 320, 100 },
			{ 3700, -720, 340, 120 },
			{ 3800, 620, 300, 95 },
			{ 1971, 1270, 380, 140 },
			{ 300, 1220, 320, 105 },
			{ -1307, 520, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,
	legs = LEGS,
	-- uneven ground all over, the way between the points lower (user 2026-11-10: "make it just a overall uneven terrain,
	-- with this area more unelevated (does not have to be a perfect line, make it natural)"): the rolling ground bent by
	-- noise, the flanks lifted and rougher past a wandering edge (Rules/MapTerrain.valleyAt, warped)
	ground = {
		warp = { amp = 45, scale = 220 },
		valley = { lift = 12, near = 120, far = 330, edge = 55, edgeScale = 160, rough = 1.8 },
	},
	-- the farmland up the flanks (user 2026-11-10: "it can be open, it just cant look empty"; Rules/MapTerrain.fieldAt,
	-- fieldLayout; Historic England: hedged closes round the farms): ploughland, hay meadows with ricks, pasture,
	-- each edged by a hedge, a rail fence or a stone wall with a gate's gap, or open
	fields = {
		angle = 6,
		size = { 130, 90 },
		near = 170,
		pointClear = 60,
		kinds = { Plough = 0.3, Meadow = 0.3, Pasture = 0.4 },
		edges = { Hedge = 0.35, RailFence = 0.25, StoneWall = 0.15 },
		gate = 14,
		stacks = { max = 3, inset = 15 },
		stripe = 4,
	},

	-- Capture points ~520 apart, each fair to its two neighbours (tests/sectors.spec.luau: S2 and S4 stand 11 toward
	-- their HQs, where the farm's walls and the town's houses would slow the attacker from the HQ). The strongpoints and
	-- the town have bigger zones (user 2026-11-06: "the building should take up a good portion of the sector").
	sectors = {
		{ id = "S1", name = "S1", x = PTS[1][1], z = PTS[1][2], radius = 45, startOwner = "West", isHQ = true },
		-- (S2's spawns stand out past the oast farm's gate walls, 48 out)
		{ id = "S2", name = "S2", x = PTS[2][1], z = PTS[2][2], radius = 55, startOwner = "West", rally = 79 },
		{ id = "S3", name = "S3", x = PTS[3][1], z = PTS[3][2], radius = 45, startOwner = "Neutral" },
		-- (S4 is Ashby: no earth crests, its outer houses are the line; Studio's audit checks its spawns' cover)
		{ id = "S4", name = "S4", x = PTS[4][1], z = PTS[4][2], radius = 60, startOwner = "East", crest = false },
		-- (S5's spawns stand out past the churchyard's west wall)
		{
			id = "S5",
			name = "S5",
			x = PTS[5][1],
			z = PTS[5][2],
			radius = 55,
			startOwner = "East",
			isHQ = true,
			rally = 78,
		},
	} :: { Sector },
	-- Where the sprint times to the two points are equal (solved over the real ground by tests/solvedividers.luau, on
	-- average within 0.5 s). points: { x, z } from the south edge to the north edge.
	dividers = {
		{
			between = { "S1", "S2" },
			points = {
				{ 457, -420 },
				{ 488, -350 },
				{ 513, -280 },
				{ 541, -210 },
				{ 571, -140 },
				{ 599, -70 },
				{ 627, 0 },
				{ 655, 70 },
				{ 682, 140 },
				{ 710, 210 },
				{ 738, 280 },
				{ 766, 350 },
				{ 796, 420 },
			},
		},
		{
			between = { "S2", "S3" },
			points = {
				{ 1179, -420 },
				{ 1179, -350 },
				{ 1170, -280 },
				{ 1160, -210 },
				{ 1160, -140 },
				{ 1156, -70 },
				{ 1153, 0 },
				{ 1149, 70 },
				{ 1149, 140 },
				{ 1152, 210 },
				{ 1136, 280 },
				{ 1130, 350 },
				{ 1129, 420 },
			},
		},
		{ between = { "S3", "S4" }, river = true }, -- the river's middle line
		{
			between = { "S4", "S5" },
			points = {
				{ 2042, -420 },
				{ 2072, -350 },
				{ 2100, -280 },
				{ 2128, -210 },
				{ 2159, -140 },
				{ 2183, -70 },
				{ 2211, 0 },
				{ 2239, 70 },
				{ 2267, 140 },
				{ 2297, 210 },
				{ 2325, 280 },
				{ 2350, 350 },
				{ 2381, 420 },
			},
		},
	} :: { Divider },
	-- each side's spawn 420 behind its HQ, straight back along x (MAP_RULES)
	spawnZones = {
		West = rect(-35, 35, 100, 220),
		East = rect(2805, 2875, -220, -100),
	},

	-- the valley floor: gentle rolling ground (kept calmer still along the chain: legs.calm)
	terrain = {
		minY = -28,
		maxY = 96,
		baseAmp = 6,
		baseScale = 300,
		midAmp = 4,
		midScale = 120,
		detailAmp = 2.6,
		detailScale = 45,
		bumpAmp = 0.9,
		bumpScale = 16,
		moundAmp = 5,
		moundScale = 80,
		moundThreshold = 0.3,
		-- fewer, smaller bare patches, and grass up a natural rise's face (user 2026-11-10: "make it look more naturally
		-- generated"; Rules/MapTerrain.materialAt: earth from `dirtSlope` degrees)
		patchThreshold = 0.62,
		dirtSlope = 33,
		-- the surface material (grass) only in voxels whose top is within this of the ground: under it is dirt, so a
		-- crater shows earth (user 2026-10-17: "dont make the green layer ... so thick")
		surfaceDepth = 1.5,
	},
	-- More extreme ridged hills outside the bounds, for the view. Unwalkable is fine out there.
	wild = { start = 30, ramp = 150, fall = 80, amp = 46, scale = 170, roughAmp = 6, roughScale = 40 },
	-- The river: from the north edge south through the open ground between S3 and Ashby, with the road's stone bridge,
	-- a footbridge to the north, the rock ford by the old lock and the mill to the south, and a narrow ford upstream.
	river = {
		x = 1690, -- its middle line, meandering `meanderAmp` either side every `meanderLen` (MapTerrain.riverCenterX)
		meanderAmp = 12,
		meanderLen = 300,
		width = 26,
		bankWidth = 14,
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ x = 1690, z = 300, width = 9, bedY = -3.8 }, -- a narrow ford upstream, on the north flank
			-- the rock ford by the old lock on the south lane: shallow water you can see, flat rocks across
			{ x = 1682, z = -115, width = 32, bedY = -4.4, rocks = true, sink = 2 },
		},
		-- the road's stone bridge and the footbridge on the north lane (src/dev/Greybox/Bridges)
		bridges = {
			{ id = "Bridge", x = 1694, z = 15, length = 70, width = 16, deck = true, hump = 3 },
			{ id = "Footbridge", x = 1691, z = 145, length = 64, width = 12, deck = true, hump = 2 },
		},
	},
	-- tree-free ground: the farms, the inn, the crossings' banks, the town and the church close
	reserved = {
		{ id = "BeaconFarm", minX = 340, maxX = 450, minZ = 280, maxZ = 340 },
		{ id = "OastFarm", minX = 830, maxX = 970, minZ = -100, maxZ = 50 },
		{ id = "Inn", minX = 1370, maxX = 1470, minZ = 120, maxZ = 210 },
		{ id = "Bridge", minX = 1620, maxX = 1740, minZ = -15, maxZ = 45 },
		{ id = "Footbridge", minX = 1622, maxX = 1732, minZ = 120, maxZ = 170 },
		{ id = "RockFord", minX = 1630, maxX = 1750, minZ = -175, maxZ = -85 },
		{ id = "Town", minX = 1770, maxX = 2110, minZ = -150, maxZ = 210 },
		{ id = "Church", minX = 2370, maxX = 2525, minZ = -210, maxZ = -90 },
		{ id = "Halt", minX = 2870, maxX = 2930, minZ = -45, maxZ = 25 },
	},

	-- The road along the step and over the bridge, the crossroads lane, Ashby round S4, and the landmarks
	-- (Rules/Village). Map 1's English cottages (Config/Buildings.RoadTemplates).
	village = {
		-- (houses only in Ashby round S4, inside its two approaches' lines ~157 out from its point)
		area = rect(1800, 2095, -165, 205),
		roads = {
			{
				id = "Main",
				width = 10,
				maxLots = 22,
				rows = true, -- the High Street's houses in order, a terrace
				points = {
					{ -90, 160 },
					{ 420, 160 },
					{ 743, 32 }, -- (then through the oast farm's two cart gates)
					{ 800, -26 },
					{ 978, -26 },
					{ 1160, -15 },
					{ 1420, 0 },
					{ 1680, 15 },
					{ 1951, 26 },
					{ 2185, -67 },
					{ 2274, -102 },
					{ 2340, -140 },
					{ 2378, -150 }, -- (to the church close's lychgate)
				},
			},
			-- on from the church close's east gate past the East spawn
			{ id = "Spawn", width = 10, maxLots = 0, points = { { 2486, -150 }, { 2700, -158 }, { 2930, -160 } } },
			-- the crossroads lane through S3, north to the inn's yard
			{ id = "Crossroads", width = 8, maxLots = 0, points = { { 1420, -420 }, { 1420, 140 } } },
			-- Ashby's two back lanes, ~70 either side of the High Street, two outer ones past them, and the two cross
			-- lanes ~90 either side of the green
			{ id = "BackNorth", width = 8, maxLots = 18, points = { { 1815, 115 }, { 1940, 100 }, { 2085, 46 } } },
			{ id = "BackSouth", width = 8, maxLots = 16, points = { { 1815, -25 }, { 1940, -40 }, { 1995, -60 } } },
			{ id = "Upper", width = 7, maxLots = 14, points = { { 1820, 172 }, { 1940, 160 }, { 2060, 112 } } },
			{ id = "Mill", width = 7, maxLots = 8, points = { { 1830, -88 }, { 1940, -104 }, { 2000, -128 } } },
			{ id = "WestLane", width = 7, maxLots = 6, points = { { 1857, -62 }, { 1843, 128 } } },
			{ id = "EastLane", width = 7, maxLots = 6, points = { { 2000, -78 }, { 2050, 70 } } },
		},
		lotSpacing = 22,
		setback = 3,
		buildingGap = 4,
		keepClear = {
			{ x = PTS[1][1], z = PTS[1][2], r = 50 },
			{ x = PTS[3][1], z = PTS[3][2], r = 50 },
			{ x = PTS[4][1], z = PTS[4][2], r = 38 }, -- Ashby's green
			-- the two little squares where each side's wave stands while S4 is its front sector (MapTerrain.rally)
			{ x = 2007, z = 4, r = 30 },
			{ x = 1891, z = 23, r = 30 },
			{ x = PTS[5][1], z = PTS[5][2], r = 20 },
			{ x = 2840, z = -160, r = 80 }, -- the East spawn
		},
		specials = {
			-- the beacon farm on S1's rear north flank, out of S2's sight
			{ id = "BeaconFarm", style = "BeaconFarm", x = 393, z = 310, front = { 0, -1 } },
			-- the oast farm on S2's point, the flag in its yard
			{ id = "OastFarm", style = "OastFarm", x = PTS[2][1], z = PTS[2][2], front = { 0, -1 } },
			-- the coaching inn on S3's north flank, its yard open to the crossroads lane
			{ id = "Inn", style = "CoachingInn", x = PTS[3][1], z = 165, front = { 0, -1 } },
			-- the watermill on the S3 bank by the rock ford, its door to the west, its wheel in the river
			{ id = "Mill", style = "Watermill", x = 1666, z = -158, front = { -1, 0 } },
			-- Ashby's market hall and pub on the green, north and south of the flag
			{ id = "MarketHall", style = "MarketHall", x = 1955, z = 74, front = { 0, -1 } },
			{ id = "Plough", style = "Plough", x = 1945, z = -24, front = { 0, 1 } },
			-- the church close on S5's point (the flag in its churchyard at local -12, -10, clear of East's wave line
			-- while S5 is its front sector) and the vicarage outside its east wall, on the spawn side
			{ id = "ChurchClose", style = "ChurchClose", x = PTS[5][1] + 12, z = PTS[5][2] + 10, front = { 0, -1 } },
			{ id = "Vicarage", style = "TwoStoryHouse", x = 2508, z = -118, front = { 1, 0 } },
			-- the railway halt behind the East spawn, on the line along the east edge (railX)
			{ id = "Halt", style = "RailwayHalt", x = 2902, z = -10, front = { 1, 0 } },
		},
		railX = 2915,
		-- garden trees only in the town (the village area)
		trees = { cell = 18, density = 0.05, roadClear = 5, buildingClear = 6 },
		cars = 0,
		features = {
			-- haystacks outside the oast farm's north corners, a trough and a fingerpost at the crossroads, the well on
			-- Ashby's green
			{ kind = "Haystack", x = 825, z = 38, yaw = 15 },
			{ kind = "Haystack", x = 953, z = 38, yaw = -15 },
			{ kind = "Trough", x = 1434, z = 14, yaw = 0 },
			{ kind = "Signpost", x = 1408, z = 14, yaw = 45 },
			{ kind = "Well", x = 1973, z = 46 },
		},
	},

	-- few trees on the valley floor: lone trees, rare small groves, the forest past the bounds
	trees = {
		cell = 14,
		forestScale = 220,
		groveThreshold = 0.42,
		groveDensity = 0.35,
		scatterDensity = 0.01,
		edgeBand = 120,
		edgeDensity = 0.45,
		outerDensity = 0.1,
		maxSlope = 34,
		footprint = 2,
		sink = 0.8,
		sectorClearFrac = 0.4,
		riverClear = 6,
		maxCount = 5000,
		-- clumps instead of lone trees (user 2026-11-10: "the minimum tree cluster has too little trees, some are just
		-- alone"; Rules/MapTerrain.clumpAt): most of 4-7 trees, a few of 15-20
		clumps = { cell = 80, chance = 0.22, radius = { 18, 40 }, tail = 2.2, density = 0.8 },
	},
}

return table.freeze(Map1)
