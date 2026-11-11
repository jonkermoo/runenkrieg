--!strict
-- Lantern Meadows: the campaign's opening against Selvara (CAMPAIGN.md, "Opening (Selvara)"): wide, open festival
-- meadows on the Aurel's north bank, where mages of all three nations held the summer lantern festival. Katzmark (West)
-- holds the hills, Selvara (East) the riverside. S1 the Katzmark camp, S2 the brickfield farm, S3 the festival ground,
-- S4 the river town, S5 the Selvaran cascina.
-- Rebuilt on the leg pattern (map rework, user approved 2026-11-06, "Yes, start LM"; docs/maps/MAP_RULES.md): points
-- 520 apart on an arch that bends north to the festival ground and back, every leg between two points built the same
-- way (Rules/MapTerrain.legPieces: a crest on each approach, the attackers' sunken lanes, open dig ground, MG knolls, gun
-- pads; `legs` below), spawns at the front sector's rally and a sector back once it's attacked (Config/Frontline
-- .Fallback). Rationale: docs/maps/LANTERNMEADOWS.md.
-- Built off Map 1, 6,000 studs south of it (user 2026-11-01: "own region, DEV place"), by the same Greybox:
--   require(game.ServerStorage.Dev.Greybox:Clone()).build("LanternMeadows")
-- Pieces are written in local studs (x along the front, West = -x; z north) and moved by CZ.

local CZ = -6000 -- world z of the map's middle line

local function p(x: number, z: number): { number }
	return { x, CZ + z }
end
local function rect(minX: number, maxX: number, minZ: number, maxZ: number): any
	return { minX = minX, maxX = maxX, minZ = CZ + minZ, maxZ = CZ + maxZ }
end
local function points(list: { { number } }): { { number } }
	local out = {}
	for _, q in list do
		table.insert(out, p(q[1], q[2]))
	end
	return out
end

-- The points (local): an arch, each leg turning 8-23Â° (user 2026-11-06: "variety in direction (not too much that the
-- map gets complicated)"), mirrored about S3's x so each side's legs are alike.
local PTS = { { 231, -96 }, { 822, 8 }, { 1420, 60 }, { 2018, 8 }, { 2609, -96 } }
local S3 = PTS[3]

-- The leg pattern (Rules/MapTerrain: legPieces, rally, tactics; the numbers explained there and in MAP_RULES.md)
local LEGS = {
	crest = {
		u = 100,
		half = 110,
		height = 8,
		width = 40,
		taper = 30,
		-- lumpy, not one long bank (user 2026-11-10, as Map 1: Rules/MapTerrain.hillocks)
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
	-- a broad lumpy swell across each leg's middle (user 2026-11-10: "the meadow map is so flat you can see
	-- everything"): dead ground both ways, the point beyond the next out of sight; none by the river
	swell = {
		-- (the middle legs' swells a third of the way from their HQ end: the S3|S4 leg's middle is the Aurel's, and
		-- this one stands before Borgo Aurel, hiding it from the West's crests)
		at = { 0.5, 0.35 },
		half = 200,
		taper = 80,
		width = 110,
		height = 6,
		riverClear = 30,
		riverFade = 40,
		base = 0.85,
		reach = 50,
		lumps = {
			count = 7,
			core = 60,
			radius = { 40, 75 },
			height = { 0.6, 1.2 },
			shift = 30,
			across = 0.6,
			stretch = 1.3,
		},
	},
	fold = { u = 170, half = 120, depth = 4.5, floor = 4, wall = 6, ends = 20 },
	knoll = { u = 90, n = 175, height = 7, top = 6, radius = 30 },
	guns = { u = 140, n = 110, howitzer = 210, pad = 9, fade = 12 },
	rally = 60,
	calm = { width = 230, fade = 80, keep = 0.3 },
	-- the rolling ground calm round each rally, so it never lifts a waiting wave over its own crest
	rallyCalm = { radius = 40, fade = 40 },
	-- (no hill at the HQs: one lifted the HQ's own rally into the next sector's view; the HQ spawn zones sit 420
	-- back, past the fog from the enemy's crest)
	flagClear = 25, -- no marked spot this close to a flag (the point gets shelled)
	-- the bots' marked spots (Rules/MapTerrain.tactics), studs: the zone's 4 at `zone.angle` + 90s, `zone.clear` past
	-- flagClear or `zone.inset` in from its edge; on each crest cover `back` behind its top at `across`, support the
	-- same; an MG `zoneMg` past flagClear behind the point; the knolls' MGs rake `rake` out and `rake` in; trench runs
	-- `back` behind the crest top; gather `out` past the lane's middle at `across`; support at the lane's ends `out`
	-- past it and `past` beyond its end
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

-- each lane's hedge bank on the side of the point it attacks (dead ground to gather in), with a gap in the middle;
-- one per approach of every point (local studs)
local laneHedges = {}
for i, s in PTS do
	for _, j in { i - 1, i + 1 } do
		local o = PTS[j]
		if o then
			local dx, dz = o[1] - s[1], o[2] - s[2]
			local l = math.sqrt(dx * dx + dz * dz)
			dx, dz = dx / l, dz / l
			local u = LEGS.fold.u - LEGS.fold.floor / 2 - LEGS.fold.wall - 3
			for _, run in { { -110, -14 }, { 14, 110 } } do
				table.insert(laneHedges, {
					a = p(s[1] + dx * u - dz * run[1], s[2] + dz * u + dx * run[1]),
					b = p(s[1] + dx * u - dz * run[2], s[2] + dz * u + dx * run[2]),
				})
			end
		end
	end
end

-- The festival ground's lantern poles: a ring round S3's point (open to the north, where the stage stands, and along
-- the two legs, where each side's spawn stands while S3 is its front sector) and a pair flanking the stage.
local features = {}
for deg = 0, 330, 30 do
	local legs = math.abs(deg - 352) < 30 or deg < 22 or math.abs(deg - 188) < 30
	if (deg < 60 or deg > 120) and not legs then
		local a = math.rad(deg)
		table.insert(
			features,
			{ kind = "LanternPole", x = S3[1] + 54 * math.cos(a), z = CZ + S3[2] + 54 * math.sin(a) }
		)
	end
end
for _, q in { { 1400, 134 }, { 1440, 134 } } do
	table.insert(features, { kind = "LanternPole", x = q[1], z = CZ + q[2] })
end

local LanternMeadows = {
	name = "Lantern Meadows",
	seed = 4417,
	-- the two nations that fight here (user 2026-11-04: Rules/Frontline.mapPair)
	pair = { West = "uniform1", East = "uniform2" },
	offMap = true, -- built beside Map 1: Greybox clears only its own terrain and adds no test spawn
	bounds = rect(-160, 3000, -275, 285),
	terrainMargin = 420,
	skirt = {
		width = 1000,
		hills = {
			{ -1376, CZ - 560, 300, 110 },
			{ 379, CZ - 920, 360, 130 },
			{ 1729, CZ - 880, 320, 100 },
			{ 3814, CZ - 480, 340, 120 },
			{ 3919, CZ + 384, 300, 95 },
			{ 1999, CZ + 904, 380, 140 },
			{ 244, CZ + 864, 320, 105 },
			{ -1443, CZ + 304, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,
	-- its look (Config/Moods, as Map 1's)
	mood = "Overcast",
	legs = LEGS,
	-- fair cover mirrored across S3's x, as its points (Rules/MapTerrain.twinOf)
	symmetry = "x",
	-- uneven ground all over, the way between the points lower (as Map 1, user 2026-11-10): a deeper valley under the
	-- Katzmark hills; each landmark's plot on settled ground
	ground = {
		warp = { amp = 45, scale = 220 },
		valley = { lift = 22, near = 200, far = 420, edge = 40, edgeScale = 160, rough = 2.8 },
		settle = { radius = 60, fade = 50, floor = 0.15 },
	},
	-- the farmland up the flanks (Rules/MapTerrain.fieldAt; the grid square to the map: it's mirrored across an x)
	fields = {
		angle = 0,
		size = { 120, 85 },
		jitter = { 0.35, 0.35 },
		near = 170,
		beyond = 60,
		pointClear = 60,
		kinds = { Plough = 0.25, Meadow = 0.4, Pasture = 0.35 },
		edges = { Hedge = 0.3, RailFence = 0.2, StoneWall = 0.25 },
		gate = 14,
		stacks = { max = 3, inset = 15 },
		stripe = 4,
	},

	-- Capture points 600 apart (user 2026-11-11: "maps need to be longer and less wide"), each fair to its two neighbours (tests/sectors.spec.luau). The strongpoint and the town
	-- have bigger zones (user 2026-11-06: "the building should take up a good portion of the sector").
	sectors = {
		{ id = "S1", name = "S1", x = PTS[1][1], z = CZ + PTS[1][2], radius = 45, startOwner = "West", isHQ = true },
		-- (S2's spawns stand a little further out, clear of the farm's sties and sheds)
		-- (S2 and S4 in a shallow hollow, the swell before each hiding it from the crests beyond: Rules/MapTerrain.legsAt)
		{
			id = "S2",
			name = "S2",
			x = PTS[2][1],
			z = CZ + PTS[2][2],
			radius = 55,
			startOwner = "West",
			rally = 72,
			hollow = { depth = 4, radius = 60, fade = 50 },
		},
		{ id = "S3", name = "S3", x = PTS[3][1], z = CZ + PTS[3][2], radius = 45, startOwner = "Neutral" },
		-- (S4 is Borgo Aurel: no earth crests, its outer houses are the line; Studio's audit checks its spawns' cover
		-- with the buildings)
		{
			id = "S4",
			name = "S4",
			x = PTS[4][1],
			z = CZ + PTS[4][2],
			radius = 60,
			startOwner = "East",
			crest = false,
			hollow = { depth = 4, radius = 60, fade = 50 },
		},
		{ id = "S5", name = "S5", x = PTS[5][1], z = CZ + PTS[5][2], radius = 55, startOwner = "East", isHQ = true },
	},
	-- Where the sprint times to the two points are equal (solved over the real ground by tests/solvedividers.luau, on
	-- average within 0.5 s). points: { x, z } from the south edge to the north edge.
	dividers = {
		{
			between = { "S1", "S2" },
			points = points({
				{ 555, -275 },
				{ 552, -205 },
				{ 549, -135 },
				{ 536, -65 },
				{ 509, 5 },
				{ 506, 75 },
				{ 505, 145 },
				{ 487, 215 },
				{ 466, 285 },
			}),
		},
		{
			between = { "S2", "S3" },
			points = points({
				{ 1153, -275 },
				{ 1132, -205 },
				{ 1132, -135 },
				{ 1129, -65 },
				{ 1129, 5 },
				{ 1113, 75 },
				{ 1110, 145 },
				{ 1104, 215 },
				{ 1104, 285 },
			}),
		},
		{
			between = { "S3", "S4" },
			points = points({
				{ 1804, -275 },
				{ 1750, -205 },
				{ 1708, -135 },
				{ 1705, -65 },
				{ 1711, 5 },
				{ 1739, 75 },
				{ 1745, 145 },
				{ 1730, 215 },
				{ 1730, 285 },
			}),
		},
		{
			between = { "S4", "S5" },
			points = points({
				{ 2286, -275 },
				{ 2286, -205 },
				{ 2295, -135 },
				{ 2308, -65 },
				{ 2326, 5 },
				{ 2332, 75 },
				{ 2336, 145 },
				{ 2348, 215 },
				{ 2375, 285 },
			}),
		},
	},
	-- each side's spawn 300 behind its HQ (420 until the 2026-11-11 stretch), straight back along x (MAP_RULES; the HQ's rise hides it)
	spawnZones = {
		West = rect(-104, -34, -156, -36),
		East = rect(2874, 2944, -156, -36),
	},

	-- open meadows: gentle rolling ground (kept calmer still along the chain: legs.calm)
	terrain = {
		minY = -28,
		maxY = 230,
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
		patchThreshold = 0.62,
		surfaceDepth = 1.5,
	},
	-- mountains outside the bounds (user 2026-11-10: "make mountainous terrains mountanous"): the Katzmark mountains
	-- behind the West tower, the north rises high, the valley side behind the river stays low; peaks and spurs
	-- (`octave`), snow over `snowY`, rock on the cliffs (Rules/MapTerrain.wildHeight, materialAt)
	wild = {
		start = 30,
		ramp = 170,
		fall = 70,
		amp = 120,
		scale = 230,
		octave = 0.9,
		roughAmp = 9,
		roughScale = 40,
		sides = { west = 1.3, north = 0.9, east = 0.6, south = 0.3 },
		snowY = 95,
		rockSlope = 30,
	},
	-- The Aurel: from the north edge south through the open ground between S3 and S4, then bending east along the
	-- south edge past the cascina (just outside it since the 2026-11-11 stretch to 560 wide). Fords are points on it.
	river = {
		path = points({
			{ 1703, 1760 },
			{ 1709, 700 },
			{ 1715, 360 },
			{ 1731, 170 },
			{ 1719, 29 },
			{ 1735, -110 },
			{ 1784, -226 },
			{ 1878, -298 },
			{ 2038, -306 },
			{ 2356, -302 },
			{ 2789, -300 },
			{ 3069, -300 },
			{ 4069, -305 },
		}),
		width = 30,
		bankWidth = 14,
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ x = 1719, z = CZ + 24, width = 30, bedY = -3.6 }, -- the festival ford, on the road
			{ x = 1726, z = CZ + 219, width = 9, bedY = -3.8 }, -- a narrow ford upstream, on the north flank
			-- the rock ford on the south lane: shallow water you can see, flat rocks across (src/dev/Greybox/Bridges)
			{ x = 1733, z = CZ - 95, width = 32, bedY = -4.4, rocks = true, sink = 2 },
		},
		-- the footbridge between the festival ford and the narrow one (src/dev/Greybox/Bridges)
		bridges = {
			{ id = "Footbridge", x = 1731, z = CZ + 160, length = 64, width = 14, deck = true, hump = 2 },
		},
	},
	-- tree-free ground: the festival ground's stage and hall; the crossings' banks; the farm and the town to come
	reserved = {
		{ id = "Festival", minX = 1360, maxX = 1480, minZ = CZ + 125, maxZ = CZ + 260 },
		{ id = "Footbridge", minX = 1675, maxX = 1785, minZ = CZ + 122.8, maxZ = CZ + 197 },
		{ id = "RockFord", minX = 1679, maxX = 1785, minZ = CZ - 131.7, maxZ = CZ - 58 },
		{ id = "Farm", minX = 742, maxX = 902, minZ = CZ - 62, maxZ = CZ + 208 }, -- (and the brickworks)
		{ id = "Town", minX = 1848, maxX = 2188, minZ = CZ - 172, maxZ = CZ + 188 },
	},

	-- The festival road along the arch and over the ford, the landmarks, and the lanes' hedge banks (Rules/Village).
	-- The brickfield farm (S2) and the river town (S4) wait for their design sheet (MAP_RULES Â§3: design first).
	village = {
		-- (houses only in the town round S4: Borgo Aurel, user approved 2026-11-06)
		-- (inside the two sunken lanes' hedges, which stand ~157 out from the point)
		area = rect(1878, 2173, -187, 183),
		kit = "Borgo", -- (the Selvaran kit with Borgo Aurel's three-storey arcaded houses)
		roads = {
			{
				id = "Main",
				width = 10,
				maxLots = 22,
				rows = true, -- the main street's houses in order, a terrace
				points = points({
					{ -159, -96 },
					{ 231, -96 },
					{ 526, -34 },
					{ 822, 8 },
					{ 1121, 44 },
					{ 1420, 60 },
					{ 1600, 45 }, -- (on the leg, through the lane hedges' gap)
					{ 1719, 24 },
					{ 2018, 8 },
					{ 2314, -34 },
					{ 2609, -96 },
					{ 2999, -96 },
				}),
			},
			-- the two back streets, ~70 either side of the main one, two outer ones past them, and the two cross lanes ~90
			-- either side of the piazza
			{ id = "Nord", width = 8, maxLots = 18, points = points({ { 1893, 93 }, { 2018, 78 }, { 2163, 24 } }) },
			{ id = "Sud", width = 8, maxLots = 16, points = points({ { 1893, -47 }, { 2018, -62 }, { 2108, -96 } }) },
			{ id = "Alto", width = 7, maxLots = 14, points = points({ { 1898, 150 }, { 2018, 138 }, { 2138, 90 } }) },
			{
				id = "Basso",
				width = 7,
				maxLots = 8,
				points = points({ { 1908, -110 }, { 2018, -126 }, { 2078, -150 } }),
			},
			{ id = "VicoOvest", width = 7, maxLots = 6, points = points({ { 1935, -84 }, { 1921, 106 } }) },
			{ id = "VicoEst", width = 7, maxLots = 6, points = points({ { 2078, -100 }, { 2128, 48 } }) },
		},
		lotSpacing = 16,
		setback = 3,
		buildingGap = 4,
		keepClear = {
			{ x = PTS[1][1], z = CZ + PTS[1][2], r = 50 },
			{ x = PTS[3][1], z = CZ + PTS[3][2], r = 50 },
			{ x = PTS[4][1], z = CZ + PTS[4][2], r = 38 }, -- Borgo Aurel's piazza
			-- the two little squares where each side's wave stands while S4 is its front sector (MapTerrain.rally)
			{ x = 2064, z = CZ - 11, r = 30 },
			{ x = 1969, z = CZ + 15, r = 30 },
			{ x = PTS[5][1], z = CZ + PTS[5][2], r = 20 },
			{ x = 2909, z = CZ - 96, r = 80 }, -- the East spawn
		},
		specials = {
			-- the festival stage and the lantern-makers' hall on S3's north flank, on its x, facing the point: a support
			-- position looking down both legs
			{ id = "Stage", style = "FestivalStage", x = S3[1], z = CZ + 160, front = { 0, -1 } },
			{ id = "LanternHall", style = "LanternHall", x = S3[1], z = CZ + 245, front = { 0, -1 } },
			-- the Lantern Tower between them (S3's hero, user approved 2026-11-11), its strings, carousel and stalls
			{ id = "LanternTower", style = "LanternTower", x = S3[1], z = CZ + 200, front = { 0, -1 } },
			-- Katzmark Burg behind S1's point on its north side (S1's hero, user approved 2026-11-11), its keep where the
			-- old watchtower stood (340, -84), Katzmark's camp in its bailey
			{ id = "Burg", style = "KatzmarkBurg", x = 159, z = CZ + 6, front = { 1, 0 } },
			-- the brickfield farm on S2's point, the flag in its yard (user approved 2026-11-06)
			{ id = "BrickfieldFarm", style = "BrickfieldFarm", x = PTS[2][1], z = CZ + PTS[2][2], front = { 0, -1 } },
			-- Fornace Aurelia behind it, north of the point on its x (S2's hero, user approved 2026-11-11): the ring kiln and
			-- its 78-stud chimney, seen across the valley; the workers' row behind the clay pit
			{ id = "Fornace", style = "Fornace", x = PTS[2][1], z = CZ + PTS[2][2] + 100, front = { 0, -1 } },
			{ id = "WorkersRow", style = "WorkersRow", x = PTS[2][1], z = CZ + PTS[2][2] + 180, front = { 0, -1 } },
			-- the cascina on S5's point, its south side, facing the flag; Selvara's camp
			-- (Cascina Selvara, S5's hero, user approved 2026-11-11: the house where it stood, its wide walled yard
			-- behind it toward the river, the stable across the back and the chapel on its east side facing into it)
			{ id = "Cascina", style = "Cascina", x = PTS[5][1], z = CZ - 154, front = { 0, 1 } },
			{ id = "CascinaStable", style = "CascinaStable", x = PTS[5][1] - 2, z = CZ - 222, front = { 0, 1 } },
			{ id = "CascinaChapel", style = "CascinaChapel", x = PTS[5][1] + 58, z = CZ - 188, front = { -1, 0 } },
			-- Borgo Aurel's campanile and loggia on the piazza, north and south of the flag
			{ id = "Campanile", style = "Campanile", x = 2022, z = CZ + 56, front = { 0, -1 } },
			{ id = "Loggia", style = "Loggia", x = 2012, z = CZ - 42, front = { 0, 1 } },
			-- S4's hero's compound (user approved 2026-11-11): the church beside the campanile, its front on the piazza;
			-- the town gate over the Main road where it comes in from the festival ford; a broken stretch of the old wall
			-- on the Aurel's east bank above the ferry
			{ id = "Church", style = "BorgoChurch", x = 1982, z = CZ + 60, front = { 0, -1 } },
			{ id = "Porta", style = "PortaAurel", x = 1868, z = CZ + 22.4, front = { -1, 0 } },
			{ id = "OldWall", style = "BorgoWall", x = 1761, z = CZ + 117.9, front = { -1, 0 } },
			-- the ferry house on the east bank above the festival ford, facing the river
			{ id = "Ferry", style = "FerryHouse", x = 1759, z = CZ + 73.6, front = { -1, 0 } },
		},
		hedgerows = laneHedges,
		-- garden trees only in the town (the village area)
		trees = { cell = 18, density = 0.05, roadClear = 5, buildingClear = 6 },
		cars = 0,
		features = features,
	},

	-- woods that are woods (user 2026-11-10: "make foresty areas foresty"): dense groves and a thick forest round
	-- the bounds; clumps instead of lone trees in the meadows
	trees = {
		cell = 14,
		forestScale = 220,
		groveThreshold = 0.42,
		groveDensity = 0.7,
		scatterDensity = 0.01,
		edgeBand = 120,
		edgeDensity = 0.75,
		outerDensity = 0.3,
		maxSlope = 34,
		footprint = 2,
		sink = 0.8,
		sectorClearFrac = 0.4,
		riverClear = 6,
		maxCount = 5000,
		clumps = { cell = 90, chance = 0.16, radius = { 24, 48 }, tail = 2.2, density = 0.85, pull = 0.25 },
	},
}

return table.freeze(LanternMeadows)
