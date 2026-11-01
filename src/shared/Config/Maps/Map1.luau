--!strict
-- Map 1: natural terrain + trees. Trenches, fortifications and equipment are built by players;
-- natural buildings (village, farm, church) come later into the reserved areas.
-- X runs along the front (west = West team), Z is lateral. Units: studs. Rationale: docs/maps/MAP1.md.

export type Sector = {
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	startOwner: "West" | "East" | "Neutral",
	isHQ: boolean?,
}

export type Divider = { between: { string }, points: { { number } }?, river: boolean? }

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local Map1 = {
	name = "Map 1",
	seed = 1337,
	-- playable area: long and narrow (user 2026-11-01: "we need more distance between sectors ... we can make the map less
	-- wide and longer instead"; was 2,100 x 800)
	bounds = { minX = -150, maxX = 2550, minZ = -280, maxZ = 280 } :: Rect,
	terrainMargin = 420, -- detailed terrain + forest past the bounds; relief fades to flat at its edge
	-- Low-detail flat skirt beyond the margin plus distant hills, so the world edge never shows.
	skirt = {
		width = 1000,
		hills = {
			{ -1243, -680, 300, 110 },
			{ 429, -1130, 360, 130 },
			{ 1714, -1080, 320, 100 },
			{ 3579, -580, 340, 120 },
			{ 3707, 480, 300, 95 },
			{ 1971, 1130, 380, 140 },
			{ 300, 1080, 320, 105 },
			{ -1307, 380, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,

	-- Capture points (frontline mode, user 2026-10-27: "somewhere that doesnt provide any tactical advantage to either
	-- sides"). Each sector's point has the same sprint time from the neighbouring point on each side (within 1.5 s,
	-- over the real ground: Rules/MapCheck). Points ~420 apart (user 2026-11-01: more distance between sectors), each on
	-- its own rise (`rise` below) with the wave line behind it on the back slope. S3 off the farm, S4 past the middle
	-- ford before the village, S5 north of the church square. Five points (user 2026-10-27, Normal mode): S1 is the West
	-- HQ and S5 the East HQ, S2-S4 are fought over. Reasoning: docs/maps/MAP1.md.
	sectors = {
		{ id = "S1", name = "S1", x = 400, z = 0, radius = 45, startOwner = "West", isHQ = true },
		{ id = "S2", name = "S2", x = 820, z = 30, radius = 45, startOwner = "West" },
		{ id = "S3", name = "S3", x = 1240, z = -30, radius = 45, startOwner = "Neutral" },
		{ id = "S4", name = "S4", x = 1660, z = -40, radius = 45, startOwner = "East" },
		{ id = "S5", name = "S5", x = 2080, z = 40, radius = 45, startOwner = "East", isHQ = true },
	} :: { Sector },
	-- The invisible blocks between sectors, west to east, one between each pair of neighbours (Rules/Sectors,
	-- Config/Sectors, built by src/dev/Greybox). Each runs where the sprint times to the two points are equal (on
	-- average within 0.5 s along it), bent where needed so it never cuts a house; S3|S4 is the river's middle line.
	-- points: { x, z } from the south edge (bounds.minZ) to the north edge (bounds.maxZ).
	dividers = {
		{ between = { "S1", "S2" }, points = { { 647, -280 }, { 617, -160 }, { 617, 0 }, { 605, 200 }, { 581, 280 } } },
		{
			between = { "S2", "S3" },
			points = { { 971, -280 }, { 1019, -160 }, { 1019, -40 }, { 1043, 40 }, { 1043, 160 }, { 1085, 280 } },
		},
		{ between = { "S3", "S4" }, river = true },
		{
			between = { "S4", "S5" },
			points = { { 1937, -280 }, { 1889, -120 }, { 1883, -40 }, { 1853, 80 }, { 1853, 160 }, { 1805, 280 } },
		},
	} :: { Divider },
	-- each side's spawn, behind its HQ (S1 / S5) as far out as the old HQ points were from theirs (~225 studs, ~12 s
	-- sprint; user 2026-10-27: an HQ point too near its spawn is too hard to take)
	spawnZones = {
		West = { minX = 140, maxX = 210, minZ = -60, maxZ = 60 } :: Rect,
		East = { minX = 2240, maxX = 2310, minZ = 40, maxZ = 130 } :: Rect, -- (clear of the village houses)
	},

	-- Terrain shape
	terrain = {
		minY = -28, -- bottom of the voxel slab
		maxY = 96, -- top of the voxel slab (room for the hills outside the bounds)
		baseAmp = 8, -- broad rolling hills
		baseScale = 260,
		midAmp = 5, -- swells
		midScale = 110,
		detailAmp = 3.2, -- uneven ground
		detailScale = 45,
		bumpAmp = 1.0, -- small bumps underfoot
		bumpScale = 16,
		moundAmp = 7, -- occasional knolls (cover on open ground)
		moundScale = 70,
		moundThreshold = 0.25,
		patchThreshold = 0.45, -- dirt patches where patch noise exceeds this
		-- the surface material (grass) only in voxels whose top is within this of the ground (was a whole voxel, 4):
		-- under it is dirt, so a crater shows earth (user 2026-10-17: "dont make the green layer ... so thick")
		surfaceDepth = 1.5,
	},
	-- More extreme ridged hills outside the bounds, for the view. Unwalkable is fine out there.
	wild = {
		start = 30, -- studs outside the bounds before hills begin
		ramp = 150,
		fall = 80, -- falls back to flat over the last stretch of the margin
		amp = 46,
		scale = 170,
		roughAmp = 6,
		roughScale = 40,
	},
	-- Every point on a rise, its spawn behind it (user 2026-11-01: "most points should be on an elevated position and the
	-- spawn behind that elevated position (as natural cover)"): a round hill `height` high at the point, falling smoothly
	-- to the rolling ground `radius` out. The wave line (Config/Frontline.Line.edge) stands on the back slope, low
	-- enough that a soldier on the next point's rise sees over its heads (tests/map1.spec.luau).
	rise = { radius = 110, height = 20, flat = 25 },
	-- Natural river between S3 and S4, with shallow fords where crossings will be built later.
	river = {
		x = 1450,
		meanderAmp = 18,
		meanderLen = 280,
		width = 22, -- water surface width
		bankWidth = 14, -- slope from bed edge to ground
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ z = 0, width = 18, bedY = -3.8 }, -- future stone bridge
			{ z = 188, width = 8, bedY = -3.8 }, -- future footbridge
			{ z = -210, width = 10, bedY = -3.8 }, -- future collapsed lock
		},
	},
	-- Flat, tree-free areas held for buildings designed later.
	reserved = {
		-- Natural (not flattened): buildings will sit on foundations. Kept clear of natural trees.
		{ id = "Village", minX = 1710, maxX = 2550, minZ = -248, maxZ = 248 },
		{ id = "Farm", minX = 1180, maxX = 1290, minZ = 30, maxZ = 150, falloff = 30 },
	},

	-- Village (references/village): organic core along winding lanes, a planned street of row houses,
	-- hamlets at lane ends and a farm by S3. Rules/Village turns this into lots, props and trees.
	village = {
		area = { minX = 1710, maxX = 2550, minZ = -248, maxZ = 248 }, -- matches the reserved Village area

		roads = {
			{
				id = "Main",
				width = 14,
				maxLots = 14,
				points = {
					{ 1450, 0 },
					{ 1660, 0 },
					{ 1780, -8 },
					{ 1890, 10 },
					{ 2000, 3 },
					{ 2100, -14 },
					{ 2220, -6 },
					{ 2360, 0 },
					{ 2550, 0 },
				},
			},
			{
				id = "NorthLane",
				width = 9,
				maxLots = 4,
				lotsFrom = 0.45, -- hamlet: lots only on the far part of the lane
				points = { { 2000, 3 }, { 2028, 60 }, { 2070, 112 }, { 2140, 154 }, { 2210, 188 } },
			},
			{
				id = "SouthLane",
				width = 9,
				maxLots = 4,
				lotsFrom = 0.4,
				points = { { 2000, 3 }, { 1985, -60 }, { 2020, -128 }, { 2085, -176 } },
			},
			{
				id = "RowStreet",
				width = 14,
				maxLots = 8,
				rows = true, -- planned street: uniform row houses, evenly spaced, both sides
				points = { { 2280, -6 }, { 2280, -172 } },
			},
			{
				id = "FarmTrack",
				width = 7,
				maxLots = 0,
				points = { { 1450, 0 }, { 1390, 14 }, { 1340, 26 }, { 1290, 36 } },
			},
		},

		lotSpacing = 26, -- candidate spacing along roads
		setback = 5, -- front wall distance from the road edge
		buildingGap = 6, -- minimum clear gap between buildings (players pass between)

		-- Open ground kept clear of buildings: the bridge-head and church squares, the S4 and S5 zones, the East HQ spawn
		-- and its approach.
		keepClear = {
			{ x = 1800, z = 0, r = 30 },
			{ x = 2100, z = -30, r = 34 },
			{ x = 1660, z = -40, r = 60 },
			{ x = 2080, z = 40, r = 60 },
			{ x = 2275, z = 85, r = 70 },
			{ x = 2400, z = 0, r = 70 },
			{ x = 2505, z = 0, r = 55 },
		},

		-- Hand-placed landmark buildings (Config/Buildings `blocks` templates, this map's own; user 2026-11-01), one at a
		-- time. front = direction the door faces. The church south of the church square, facing it.
		specials = {
			{ id = "Church", style = "Church", x = 2100, z = -90, front = { 0, 1 } },
			-- the coaching inn north of the bridge-head square, facing it across the main road
			{ id = "Inn", style = "CoachingInn", x = 1800, z = 42, front = { 0, -1 } },
			-- the farm north of S3, on the point's x: the oast house facing the point, its yard behind
			{ id = "Oast", style = "OastHouse", x = 1240, z = 72, front = { 0, -1 } },
			{ id = "FarmYard", style = "HayBarn", x = 1240, z = 118, front = { 0, -1 } },
			-- the watermill on the S3 bank just south of the lock ford, its door to the west, its wheel in the river
			{ id = "Mill", style = "Watermill", x = 1450, z = -234, front = { -1, 0 } },
		},

		railX = 2530,

		trees = { cell = 18, density = 0.14, roadClear = 5, buildingClear = 6 },
		poles = { road = "Main", spacing = 48, side = 1 },
		cars = 3,
		-- Fixed village features: a well on the church square, a trough at the bridge-head square.
		features = {
			{ kind = "Well", x = 2100, z = -30 },
			{ kind = "Trough", x = 1812, z = 16, yaw = 90 },
		},
	},

	-- Trees: jittered grid, density from a forest-noise field. Outer = beyond the bounds.
	trees = {
		cell = 14,
		forestScale = 220,
		groveThreshold = 0.12, -- forest noise above this = grove
		groveDensity = 0.5,
		scatterDensity = 0.03,
		edgeBand = 120, -- dense forest band just outside the bounds
		edgeDensity = 0.5,
		outerDensity = 0.1,
		maxSlope = 34, -- no trees on steeper ground (rock faces)
		footprint = 2, -- trunk radius sampled for the lowest ground
		sink = 0.8, -- extra depth below the lowest ground
		sectorClearFrac = 0.4, -- no trees inside this fraction of a sector radius
		riverClear = 6, -- extra clearance past the river banks
		maxCount = 5000,
	},
}

return table.freeze(Map1)
