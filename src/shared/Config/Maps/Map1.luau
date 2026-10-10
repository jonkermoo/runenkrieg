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
	terrainMargin = 300, -- detailed terrain + forest past the bounds; noise fades to flat at its edge
	-- Low-detail flat skirt beyond the margin plus distant hills, so the world edge never shows.
	skirt = {
		width = 1000,
		hills = {
			{ -900, -700, 260, 60 },
			{ 300, -1100, 320, 80 },
			{ 1300, -1050, 280, 55 },
			{ 2600, -600, 300, 70 },
			{ 2700, 500, 260, 50 },
			{ 1500, 1100, 330, 85 },
			{ 200, 1050, 280, 60 },
			{ -950, 450, 300, 75 },
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
		maxY = 32, -- top of the voxel slab
		baseAmp = 8, -- rolling hills
		baseScale = 260,
		patchThreshold = 0.45, -- dirt patches where patch noise exceeds this
		detailAmp = 1.2,
		detailScale = 70,
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
		{ id = "Village", minX = 1110, maxX = 1950, minZ = -330, maxZ = 330, falloff = 60, baseY = 0 },
		{ id = "Farm", minX = 850, maxX = 960, minZ = -30, maxZ = 130, falloff = 30 },
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
		outerDensity = 0.12,
		sectorClearFrac = 0.4, -- no trees inside this fraction of a sector radius
		riverClear = 6, -- extra clearance past the river banks
		maxCount = 4500,
	},
}

return table.freeze(Map1)
