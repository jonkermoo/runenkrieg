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

-- The points (local): an arch, each leg turning 8-23° (user 2026-11-06: "variety in direction (not too much that the
-- map gets complicated)"), mirrored about S3's x so each side's legs are alike.
local PTS = { { 420, -170 }, { 900, 30 }, { 1420, 100 }, { 1940, 30 }, { 2420, -170 } }
local S3 = PTS[3]

-- The leg pattern (Rules/MapTerrain: legPieces, rally, tactics; the numbers explained there and in MAP_RULES.md)
local LEGS = {
	crest = { u = 100, half = 110, height = 8, width = 40, taper = 30 },
	fold = { u = 170, half = 120, depth = 4.5, floor = 4, wall = 6, ends = 20 },
	knoll = { u = 90, n = 175, height = 7, top = 6, radius = 30 },
	guns = { u = 140, n = 110, howitzer = 210, pad = 9, fade = 12 },
	rally = 60,
	calm = { width = 230, fade = 80, keep = 0.3 },
	-- (no hill at the HQs: one lifted the HQ's own rally into the next sector's view; the HQ spawn zones sit 420
	-- back, past the fog from the enemy's crest)
	flagClear = 25, -- no marked spot this close to a flag (the point gets shelled)
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

-- The festival ground's lantern poles: a ring round S3's point (open to the north, where the stage stands) and a pair
-- flanking the stage.
local features = {}
for deg = 0, 330, 30 do
	if deg < 60 or deg > 120 then
		local a = math.rad(deg)
		table.insert(
			features,
			{ kind = "LanternPole", x = S3[1] + 54 * math.cos(a), z = CZ + S3[2] + 54 * math.sin(a) }
		)
	end
end
for _, q in { { 1400, 174 }, { 1440, 174 } } do
	table.insert(features, { kind = "LanternPole", x = q[1], z = CZ + q[2] })
end
-- the field barn's haystacks at S2, one either side of it
for _, x in { 868, 932 } do
	table.insert(features, { kind = "Haystack", x = x, z = CZ + 118, yaw = 15 })
end

local LanternMeadows = {
	name = "Lantern Meadows",
	seed = 4417,
	-- the two nations that fight here (user 2026-11-04: Rules/Frontline.mapPair)
	pair = { West = "uniform1", East = "uniform2" },
	offMap = true, -- built beside Map 1: Greybox clears only its own terrain and adds no test spawn
	bounds = rect(-90, 2930, -430, 360),
	terrainMargin = 420,
	skirt = {
		width = 1000,
		hills = {
			{ -1243, CZ - 700, 300, 110 },
			{ 429, CZ - 1150, 360, 130 },
			{ 1714, CZ - 1100, 320, 100 },
			{ 3700, CZ - 600, 340, 120 },
			{ 3800, CZ + 480, 300, 95 },
			{ 1971, CZ + 1130, 380, 140 },
			{ 300, CZ + 1080, 320, 105 },
			{ -1307, CZ + 380, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,
	legs = LEGS,

	-- Capture points 520 apart, each fair to its two neighbours (tests/sectors.spec.luau). The strongpoint and the town
	-- have bigger zones (user 2026-11-06: "the building should take up a good portion of the sector").
	sectors = {
		{ id = "S1", name = "S1", x = PTS[1][1], z = CZ + PTS[1][2], radius = 45, startOwner = "West", isHQ = true },
		{ id = "S2", name = "S2", x = PTS[2][1], z = CZ + PTS[2][2], radius = 55, startOwner = "West" },
		{ id = "S3", name = "S3", x = PTS[3][1], z = CZ + PTS[3][2], radius = 45, startOwner = "Neutral" },
		{ id = "S4", name = "S4", x = PTS[4][1], z = CZ + PTS[4][2], radius = 60, startOwner = "East" },
		{ id = "S5", name = "S5", x = PTS[5][1], z = CZ + PTS[5][2], radius = 55, startOwner = "East", isHQ = true },
	},
	-- Where the sprint times to the two points are equal (solved over the real ground by tests/solvedividers.luau, on
	-- average within 0.5 s). points: { x, z } from the south edge to the north edge.
	dividers = {
		{
			between = { "S1", "S2" },
			points = points({
				{ 809, -430 },
				{ 780, -360 },
				{ 754, -290 },
				{ 725, -220 },
				{ 692, -150 },
				{ 663, -80 },
				{ 634, -10 },
				{ 605, 60 },
				{ 576, 130 },
				{ 547, 200 },
				{ 517, 270 },
				{ 488, 340 },
				{ 481, 360 },
			}),
		},
		{
			between = { "S2", "S3" },
			points = points({
				{ 1241, -430 },
				{ 1240, -360 },
				{ 1234, -290 },
				{ 1203, -220 },
				{ 1179, -150 },
				{ 1179, -80 },
				{ 1175, -10 },
				{ 1163, 60 },
				{ 1147, 130 },
				{ 1144, 200 },
				{ 1143, 270 },
				{ 1122, 340 },
				{ 1120, 360 },
			}),
		},
		{
			between = { "S3", "S4" },
			points = points({
				{ 1768, -430 },
				{ 1781, -360 },
				{ 1769, -290 },
				{ 1710, -220 },
				{ 1683, -150 },
				{ 1665, -80 },
				{ 1663, -10 },
				{ 1678, 60 },
				{ 1703, 130 },
				{ 1709, 200 },
				{ 1707, 270 },
				{ 1704, 340 },
				{ 1720, 360 },
			}),
		},
		{
			between = { "S4", "S5" },
			points = points({
				{ 2122, -430 },
				{ 2070, -360 },
				{ 2096, -290 },
				{ 2126, -220 },
				{ 2158, -150 },
				{ 2187, -80 },
				{ 2216, -10 },
				{ 2245, 60 },
				{ 2274, 130 },
				{ 2310, 200 },
				{ 2333, 270 },
				{ 2362, 340 },
				{ 2371, 360 },
			}),
		},
	},
	-- each side's spawn 420 behind its HQ, straight back along x (MAP_RULES; the HQ's rise hides it)
	spawnZones = {
		West = rect(-35, 35, -230, -110),
		East = rect(2805, 2875, -230, -110),
	},

	-- open meadows: gentle rolling ground (kept calmer still along the chain: legs.calm)
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
		patchThreshold = 0.5,
		surfaceDepth = 1.5,
	},
	-- rougher hills outside the bounds (the Katzmark hills behind the West, the valley side behind the river)
	wild = { start = 30, ramp = 150, fall = 80, amp = 46, scale = 170, roughAmp = 6, roughScale = 40 },
	-- The Aurel: from the north edge south through the open ground between S3 and S4, then bending east along the
	-- south edge past the cascina. Fords are points on it.
	river = {
		path = points({
			{ 1660, 1760 },
			{ 1666, 700 },
			{ 1672, 360 },
			{ 1688, 200 },
			{ 1680, 60 },
			{ 1690, -80 },
			{ 1722, -200 },
			{ 1800, -300 },
			{ 1960, -372 },
			{ 2200, -398 },
			{ 2600, -402 },
			{ 3000, -402 },
			{ 4000, -405 },
		}),
		width = 30,
		bankWidth = 14,
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ x = 1680, z = CZ + 55, width = 30, bedY = -3.6 }, -- the festival ford, on the road
			{ x = 1683, z = CZ + 250, width = 9, bedY = -3.8 }, -- a narrow ford upstream, on the north flank
			-- the rock ford on the south lane: shallow water you can see, flat rocks across (src/dev/Greybox/Bridges)
			{ x = 1689, z = CZ - 65, width = 32, bedY = -4.4, rocks = true, sink = 2 },
		},
		-- the footbridge between the festival ford and the narrow one (src/dev/Greybox/Bridges)
		bridges = {
			{ id = "Footbridge", x = 1687, z = CZ + 190, length = 64, width = 14, deck = true, hump = 2 },
		},
	},
	-- tree-free ground: the festival ground's stage and hall; the crossings' banks; the farm and the town to come
	reserved = {
		{ id = "Festival", minX = 1360, maxX = 1480, minZ = CZ + 165, maxZ = CZ + 300 },
		{ id = "Footbridge", minX = 1632, maxX = 1742, minZ = CZ + 160, maxZ = CZ + 220 },
		{ id = "RockFord", minX = 1636, maxX = 1742, minZ = CZ - 95, maxZ = CZ - 35 },
		{ id = "Farm", minX = 830, maxX = 970, minZ = CZ - 40, maxZ = CZ + 140 },
		{ id = "Town", minX = 1770, maxX = 2110, minZ = CZ - 150, maxZ = CZ + 210 },
	},

	-- The festival road along the arch and over the ford, the landmarks, and the lanes' hedge banks (Rules/Village).
	-- The brickfield farm (S2) and the river town (S4) wait for their design sheet (MAP_RULES §3: design first).
	village = {
		area = rect(1700, 2930, -300, 300),
		kit = "Selvara",
		roads = {
			{
				id = "Main",
				width = 10,
				maxLots = 0,
				points = points({
					{ -90, -170 },
					{ 420, -170 },
					{ 660, -60 },
					{ 900, 30 },
					{ 1160, 75 },
					{ 1420, 100 },
					{ 1600, 70 },
					{ 1680, 55 },
					{ 1940, 30 },
					{ 2180, -60 },
					{ 2420, -170 },
					{ 2930, -170 },
				}),
			},
		},
		lotSpacing = 26,
		setback = 5,
		buildingGap = 6,
		keepClear = {
			{ x = PTS[1][1], z = CZ + PTS[1][2], r = 50 },
			{ x = PTS[2][1], z = CZ + PTS[2][2], r = 20 },
			{ x = PTS[3][1], z = CZ + PTS[3][2], r = 50 },
			{ x = PTS[4][1], z = CZ + PTS[4][2], r = 20 },
			{ x = PTS[5][1], z = CZ + PTS[5][2], r = 20 },
			{ x = 2840, z = CZ - 170, r = 80 }, -- the East spawn
		},
		-- the map's own landmarks (Config/Buildings), moved onto the new points (user 2026-11-06 plan)
		specials = {
			-- the festival stage and the lantern-makers' hall on S3's north flank, on its x, facing the point: a support
			-- position looking down both legs
			{ id = "Stage", style = "FestivalStage", x = S3[1], z = CZ + 200, front = { 0, -1 } },
			{ id = "LanternHall", style = "LanternHall", x = S3[1], z = CZ + 262, front = { 0, -1 } },
			-- the old watchtower behind S1's point on its north side, Katzmark's camp round it
			{ id = "Watchtower", style = "Watchtower", x = 340, z = CZ - 84, front = { 1, 0 } },
			-- the field barn on S2's point, its north side, facing the flag (until the brickfield farm replaces it)
			{ id = "FieldBarn", style = "FieldBarn", x = PTS[2][1], z = CZ + 82, front = { 0, -1 } },
			-- the cascina on S5's point, its south side, facing the flag; Selvara's camp
			{ id = "Cascina", style = "Cascina", x = PTS[5][1], z = CZ - 228, front = { 0, 1 } },
			-- the ferry house on the east bank above the festival ford, facing the river
			{ id = "Ferry", style = "FerryHouse", x = 1716, z = CZ + 100, front = { -1, 0 } },
		},
		hedgerows = laneHedges,
		trees = { cell = 18, density = 0.05, roadClear = 5, buildingClear = 6 },
		cars = 0,
		features = features,
	},

	-- few trees: lone trees in the meadows, rare small groves, the forest past the bounds
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
	},
}

return table.freeze(LanternMeadows)
