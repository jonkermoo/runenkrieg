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

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local Map1 = {
	name = "Map 1",
	seed = 1337,
	bounds = { minX = -150, maxX = 1950, minZ = -400, maxZ = 400 } :: Rect, -- playable area
	terrainMargin = 420, -- detailed terrain + forest past the bounds; relief fades to flat at its edge
	-- Low-detail flat skirt beyond the margin plus distant hills, so the world edge never shows.
	skirt = {
		width = 1000,
		hills = {
			{ -1000, -800, 300, 110 },
			{ 300, -1250, 360, 130 },
			{ 1300, -1200, 320, 100 },
			{ 2750, -700, 340, 120 },
			{ 2850, 600, 300, 95 },
			{ 1500, 1250, 380, 140 },
			{ 200, 1200, 320, 105 },
			{ -1050, 500, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,

	sectors = {
		{ id = "HQW", name = "West HQ", x = 0, z = 0, radius = 60, startOwner = "West", isHQ = true },
		{ id = "S1", name = "S1", x = 300, z = 20, radius = 45, startOwner = "West" },
		{ id = "S2", name = "S2", x = 600, z = -60, radius = 45, startOwner = "West" },
		{ id = "S3", name = "S3", x = 900, z = 40, radius = 45, startOwner = "Neutral" },
		{ id = "S4", name = "S4", x = 1200, z = 0, radius = 45, startOwner = "East" },
		{ id = "S5", name = "S5", x = 1500, z = -40, radius = 45, startOwner = "East" },
		{ id = "HQE", name = "East HQ", x = 1800, z = 0, radius = 60, startOwner = "East", isHQ = true },
	} :: { Sector },
	spawnZones = {
		West = { minX = -140, maxX = -70, minZ = -60, maxZ = 60 } :: Rect,
		East = { minX = 1870, maxX = 1940, minZ = -60, maxZ = 60 } :: Rect,
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
	-- High ground along the West side, full map width.
	ridge = { upStart = 500, topStart = 570, topEnd = 690, downEnd = 770, height = 10 },
	-- Natural river between S3 and S4, with shallow fords where crossings will be built later.
	river = {
		x = 1060,
		meanderAmp = 18,
		meanderLen = 280,
		width = 22, -- water surface width
		bankWidth = 14, -- slope from bed edge to ground
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ z = 0, width = 18, bedY = -3.8 }, -- future stone bridge
			{ z = 250, width = 8, bedY = -3.8 }, -- future footbridge
			{ z = -280, width = 10, bedY = -3.8 }, -- future collapsed lock
		},
	},
	-- Flat, tree-free areas held for buildings designed later.
	reserved = {
		-- Natural (not flattened): buildings will sit on foundations. Kept clear of natural trees.
		{ id = "Village", minX = 1110, maxX = 1950, minZ = -330, maxZ = 330 },
		{ id = "Farm", minX = 850, maxX = 960, minZ = -30, maxZ = 130, falloff = 30 },
	},

	-- Village (references/village): organic core along winding lanes, a planned street of row houses,
	-- hamlets at lane ends and a farm by S3. Rules/Village turns this into lots, props and trees.
	village = {
		area = { minX = 1110, maxX = 1950, minZ = -330, maxZ = 330 }, -- matches the reserved Village area

		roads = {
			{
				id = "Main",
				width = 14,
				maxLots = 10,
				points = {
					{ 1060, 0 },
					{ 1180, -10 },
					{ 1290, 14 },
					{ 1400, 4 },
					{ 1500, -18 },
					{ 1620, -8 },
					{ 1760, 0 },
					{ 1950, 0 },
				},
			},
			{
				id = "NorthLane",
				width = 9,
				maxLots = 4,
				lotsFrom = 0.45, -- hamlet: lots only on the far part of the lane
				points = { { 1400, 4 }, { 1428, 80 }, { 1470, 150 }, { 1540, 205 }, { 1610, 250 } },
			},
			{
				id = "SouthLane",
				width = 9,
				maxLots = 4,
				lotsFrom = 0.4,
				points = { { 1290, 14 }, { 1268, -80 }, { 1300, -170 }, { 1365, -235 } },
			},
			{
				id = "RowStreet",
				width = 14,
				maxLots = 8,
				rows = true, -- planned street: uniform row houses, evenly spaced, both sides
				points = { { 1680, -8 }, { 1680, -230 } },
			},
			{
				id = "FarmTrack",
				width = 7,
				maxLots = 0,
				points = { { 1060, 0 }, { 1000, 18 }, { 950, 40 }, { 905, 55 } },
			},
		},

		lotSpacing = 26, -- candidate spacing along roads
		setback = 5, -- front wall distance from the road edge
		buildingGap = 6, -- minimum clear gap between buildings (players pass between)

		-- Open ground kept clear of buildings: sector squares and the East HQ spawn approach.
		keepClear = {
			{ x = 1200, z = 0, r = 30 },
			{ x = 1500, z = -40, r = 34 },
			{ x = 1800, z = 0, r = 70 },
			{ x = 1905, z = 0, r = 55 },
		},

		-- Hand-placed landmark buildings. front = direction the door faces.
		-- Hand-placed landmark buildings (church, station, farm...) return one at a time.
		specials = {},

		railX = 1930,

		trees = { cell = 18, density = 0.14, roadClear = 5, buildingClear = 6 },
		poles = { road = "Main", spacing = 48, side = 1 },
		cars = 3,
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
