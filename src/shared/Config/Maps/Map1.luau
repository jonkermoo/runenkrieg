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
local PTS = { { 230, 73 }, { 810, -31 }, { 1420, 0 }, { 2030, 31 }, { 2610, -73 } }

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
	knoll = { u = 90, n = 175, height = 7, top = 6, radius = 30 },
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
	bounds = rect(-160, 3000, -280, 280),
	terrainMargin = 420, -- detailed terrain + forest past the bounds; relief fades to flat at its edge
	-- Low-detail flat skirt beyond the margin plus distant hills, so the world edge never shows.
	skirt = {
		width = 1000,
		hills = {
			{ -1376, -656, 300, 110 },
			{ 379, -1016, 360, 130 },
			{ 1729, -976, 320, 100 },
			{ 3814, -576, 340, 120 },
			{ 3919, 496, 300, 95 },
			{ 1999, 1016, 380, 140 },
			{ 244, 976, 320, 105 },
			{ -1443, 416, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,
	-- its look (Config/Moods; user 2026-11-11: "remove this highly saturated look... more dark and foggy"): its haze,
	-- grade, light and sky; the admin panel's Look row tries the others
	mood = "Overcast",
	legs = LEGS,
	-- uneven ground all over, the way between the points lower (user 2026-11-10: "make it just a overall uneven terrain,
	-- with this area more unelevated (does not have to be a perfect line, make it natural)"): the rolling ground bent by
	-- noise, the flanks lifted and rougher past a wandering edge (Rules/MapTerrain.valleyAt, warped)
	ground = {
		warp = { amp = 45, scale = 220 },
		valley = { lift = 16, near = 215, far = 310, edge = 40, edgeScale = 160, rough = 2.5 },
		-- each landmark's plot on settled ground (Rules/MapTerrain.landRaw)
		settle = { radius = 60, fade = 50, floor = 0.15 },
	},
	-- the farmland up the flanks (user 2026-11-10: "it can be open, it just cant look empty"; Rules/MapTerrain.fieldAt,
	-- fieldLayout; Historic England: hedged closes round the farms): ploughland, hay meadows with ricks, pasture,
	-- each edged by a hedge, a rail fence or a stone wall with a gate's gap, or open
	fields = {
		angle = 6,
		size = { 130, 90 },
		jitter = { 0.35, 0.35 },
		near = 170,
		beyond = 60, -- (past the bounds no further than this: the forest frames the map)
		pointClear = 60,
		kinds = { Plough = 0.3, Meadow = 0.3, Pasture = 0.4 },
		edges = { Hedge = 0.35, RailFence = 0.25, StoneWall = 0.15 },
		gate = 14,
		stacks = { max = 3, inset = 15 },
		stripe = 4,
	},

	-- Capture points ~600 apart (user 2026-11-11: "maps need to be longer and less wide"), each fair to its two neighbours (tests/sectors.spec.luau: S2 and S4 stand 11 toward
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
				{ 464, -280 },
				{ 480, -210 },
				{ 492, -140 },
				{ 502, -70 },
				{ 511, 0 },
				{ 539, 70 },
				{ 539, 140 },
				{ 543, 210 },
				{ 555, 280 },
			},
		},
		{
			between = { "S2", "S3" },
			points = {
				{ 1127, -280 },
				{ 1124, -210 },
				{ 1123, -140 },
				{ 1123, -70 },
				{ 1113, 0 },
				{ 1110, 70 },
				{ 1106, 140 },
				{ 1112, 210 },
				{ 1111, 280 },
			},
		},
		{ between = { "S3", "S4" }, river = true }, -- the river's middle line
		{
			between = { "S4", "S5" },
			points = {
				{ 2283, -280 },
				{ 2298, -210 },
				{ 2299, -140 },
				{ 2302, -70 },
				{ 2330, 0 },
				{ 2336, 70 },
				{ 2349, 140 },
				{ 2361, 210 },
				{ 2377, 280 },
			},
		},
	} :: { Divider },
	-- each side's spawn 300 behind its HQ, straight back along x (MAP_RULES; 420 until the 2026-11-11 stretch)
	spawnZones = {
		West = rect(-105, -35, 13, 133),
		East = rect(2875, 2945, -133, -13),
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
		x = 1732, -- its middle line, meandering `meanderAmp` either side every `meanderLen` (MapTerrain.riverCenterX)
		meanderAmp = 12,
		meanderLen = 300,
		width = 26,
		bankWidth = 14,
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ x = 1720, z = 237, width = 9, bedY = -3.8 }, -- a narrow ford upstream, on the north flank
			-- the rock ford by the old lock on the south lane: shallow water you can see, flat rocks across
			{ x = 1724, z = -113, width = 32, bedY = -4.4, rocks = true, sink = 2 },
		},
		-- the road's stone bridge and the footbridge on the north lane (src/dev/Greybox/Bridges)
		bridges = {
			{ id = "Bridge", x = 1736, z = 18, length = 70, width = 16, deck = true, hump = 3 },
			{ id = "Footbridge", x = 1733, z = 148, length = 64, width = 12, deck = true, hump = 2 },
		},
	},
	-- tree-free ground: the farms, the inn, the crossings' banks, the town and the church close
	reserved = {
		{ id = "BeaconFarm", minX = 150, maxX = 260, minZ = 178, maxZ = 238 },
		{ id = "OastFarm", minX = 751, maxX = 891, minZ = -105, maxZ = 45 },
		{ id = "Inn", minX = 1346, maxX = 1504, minZ = 120, maxZ = 204 },
		{ id = "Bridge", minX = 1662, maxX = 1782, minZ = -15, maxZ = 49 },
		{ id = "Footbridge", minX = 1664, maxX = 1774, minZ = 120, maxZ = 174 },
		{ id = "RockFord", minX = 1672, maxX = 1792, minZ = -174, maxZ = -80 },
		{ id = "Town", minX = 1849, maxX = 2189, minZ = -145, maxZ = 205 },
		{ id = "Church", minX = 2560, maxX = 2715, minZ = -123, maxZ = -3 },
		{ id = "Halt", minX = 2940, maxX = 3000, minZ = 42, maxZ = 112 },
	},

	-- The road along the step and over the bridge, the crossroads lane, Ashby round S4, and the landmarks
	-- (Rules/Village). Map 1's English cottages (Config/Buildings.RoadTemplates).
	village = {
		-- (houses only in Ashby round S4, inside its two approaches' lines ~157 out from its point)
		area = rect(1879, 2174, -160, 204),
		roads = {
			{
				id = "Main",
				width = 10,
				maxLots = 22,
				rows = true, -- the High Street's houses in order, a terrace
				points = {
					{ -160, 73 },
					{ 230, 73 },
					{ 664, 27 }, -- (then through the oast farm's two cart gates)
					{ 721, -31 },
					{ 899, -31 },
					{ 1123, -17 },
					{ 1420, 0 },
					{ 1717, 17 },
					{ 2030, 31 },
					{ 2264, -62 }, -- (the High Street out of the green as before the stretch)
					{ 2464, -15 },
					{ 2530, -53 },
					{ 2568, -63 }, -- (to the church close's lychgate)
				},
			},
			-- on from the church close's east gate past the East spawn
			{ id = "Spawn", width = 10, maxLots = 0, points = { { 2676, -63 }, { 2843, -71 }, { 3000, -73 } } },
			-- the crossroads lane through S3, north to the inn's yard
			{ id = "Crossroads", width = 8, maxLots = 0, points = { { 1420, -280 }, { 1420, 140 } } },
			-- Ashby's two back lanes, ~70 either side of the High Street, two outer ones past them, and the two cross
			-- lanes ~90 either side of the green
			{ id = "BackNorth", width = 8, maxLots = 18, points = { { 1894, 120 }, { 2019, 105 }, { 2164, 51 } } },
			{ id = "BackSouth", width = 8, maxLots = 16, points = { { 1894, -20 }, { 2019, -35 }, { 2074, -55 } } },
			{ id = "Upper", width = 7, maxLots = 14, points = { { 1899, 177 }, { 2019, 165 }, { 2139, 117 } } },
			{ id = "Mill", width = 7, maxLots = 8, points = { { 1872, -83 }, { 1982, -99 }, { 2042, -123 } } },
			{ id = "WestLane", width = 7, maxLots = 6, points = { { 1936, -57 }, { 1922, 133 } } },
			{ id = "EastLane", width = 7, maxLots = 6, points = { { 2079, -73 }, { 2129, 75 } } },
		},
		lotSpacing = 22,
		setback = 3,
		buildingGap = 4,
		keepClear = {
			{ x = PTS[1][1], z = PTS[1][2], r = 50 },
			{ x = PTS[3][1], z = PTS[3][2], r = 50 },
			{ x = PTS[4][1], z = PTS[4][2], r = 38 }, -- Ashby's green
			-- the two little squares where each side's wave stands while S4 is its front sector (MapTerrain.rally)
			{ x = 2086, z = 9, r = 30 },
			{ x = 1970, z = 28, r = 30 },
			{ x = PTS[5][1], z = PTS[5][2], r = 20 },
			{ x = 2910, z = -73, r = 80 }, -- the East spawn
		},
		specials = {
			-- the beacon farm on S1's rear north flank, out of S2's sight
			{ id = "BeaconFarm", style = "BeaconFarm", x = 203, z = 208, front = { 0, -1 } },
			-- the oast farm on S2's point, the flag in its yard
			{ id = "OastFarm", style = "OastFarm", x = PTS[2][1], z = PTS[2][2], front = { 0, -1 } },
			-- the coaching inn on S3's north flank, its yard open to the crossroads lane
			{ id = "Inn", style = "CoachingInn", x = PTS[3][1], z = 165, front = { 0, -1 } },
			-- Crossways Brewery east of the inn and the smithy west of it (user approved 2026-11-11)
			{ id = "Brewery", style = "Brewery", x = PTS[3][1] + 70, z = 182, front = { -1, 0 } },
			{ id = "Smithy", style = "Smithy", x = PTS[3][1] - 62, z = 180, front = { 1, 0 } },
			-- the watermill on the S3 bank by the rock ford, its door to the west, its wheel in the river
			{ id = "Mill", style = "Watermill", x = 1708, z = -156, front = { -1, 0 } },
			-- Ashby's market hall and pub on the green, north and south of the flag
			{ id = "MarketHall", style = "MarketHall", x = 2034, z = 78, front = { 0, -1 } },
			{ id = "Plough", style = "Plough", x = 2024, z = -19, front = { 0, 1 } },
			-- Ashby's allotments on the town's north edges (user approved 2026-11-11)
			{ id = "AllotmentsWest", style = "Allotments", x = 1907, z = 207, front = { 0, -1 } },
			{ id = "AllotmentsEast", style = "Allotments", x = 2159, z = 173, front = { 0, -1 } },
			-- the church close on S5's point (the flag in its churchyard at local -12, -10, clear of East's wave line
			-- while S5 is its front sector) and the vicarage outside its east wall, on the spawn side
			{ id = "ChurchClose", style = "ChurchClose", x = PTS[5][1] + 12, z = PTS[5][2] + 10, front = { 0, -1 } },
			{ id = "Vicarage", style = "TwoStoryHouse", x = 2698, z = -31, front = { 1, 0 } },
			-- round St Aldhelm's close (user approved 2026-11-11): the school and the almshouses north of the churchyard,
			-- facing it, the tithe barn south-east
			{ id = "School", style = "VillageSchool", x = 2632, z = 9, front = { 0, -1 } },
			{ id = "Almshouses", style = "Almshouses", x = 2582, z = 9, front = { 0, -1 } },
			{ id = "TitheBarn", style = "TitheBarn", x = 2716, z = -127, front = { 0, 1 } },
			-- the railway halt behind the East spawn, on the line along the east edge (railX)
			{ id = "Halt", style = "RailwayHalt", x = 2972, z = 77, front = { 1, 0 } },
		},
		railX = 2985,
		-- garden trees only in the town (the village area)
		trees = { cell = 18, density = 0.05, roadClear = 5, buildingClear = 6 },
		cars = 0,
		features = {
			-- haystacks outside the oast farm's north corners, a trough and a fingerpost at the crossroads, the well on
			-- Ashby's green
			{ kind = "Haystack", x = 746, z = 33, yaw = 15 },
			{ kind = "Haystack", x = 874, z = 33, yaw = -15 },
			{ kind = "Trough", x = 1434, z = 14, yaw = 0 },
			{ kind = "Signpost", x = 1408, z = 14, yaw = 45 },
			{ kind = "Well", x = 2052, z = 51 },
		},
	},

	-- few trees on the valley floor: lone trees, rare small groves, the forest past the bounds
	trees = {
		cell = 14,
		forestScale = 220,
		groveThreshold = 0.42,
		groveDensity = 0.35,
		scatterDensity = 0.01,
		edgeBand = 80,
		edgeDensity = 0.45,
		outerDensity = 0.1,
		maxSlope = 34,
		footprint = 2,
		sink = 0.8,
		sectorClearFrac = 0.4,
		riverClear = 6,
		maxCount = 5000,
		-- clumps instead of lone trees (user 2026-11-10: "the minimum tree cluster has too little trees, some are just
		-- alone"; Rules/MapTerrain.clumpAt): most of 4-7 trees, a few of 15-20, drawn `pull` in toward the middle
		clumps = { cell = 90, chance = 0.16, radius = { -59, -39 }, tail = 2.2, density = 0.85, pull = 0.25 },
	},
}

return table.freeze(Map1)
