--!strict
-- Lantern Meadows: the campaign's opening against Selvara (CAMPAIGN.md, "Opening (Selvara)"): wide, open festival
-- meadows on the Aurel's north bank, where mages of all three nations held the summer lantern festival. Katzmark (West)
-- holds the hills, Selvara (East) the riverside. S1 the Katzmark camp, S2 the hedgerow fields, S3 the festival ground,
-- S4 the ford, S5 the Selvaran riverside camp. Laid out by the map rules (docs/maps/MAP_RULES.md): points ~420 apart
-- on a long, narrow map, each on a same-height rise with its wave line behind it. Rationale: docs/maps/LANTERNMEADOWS.md.
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

-- The festival ground's lantern poles: a ring round S3's point (open to the north, where the stage stands), a pair
-- flanking the stage, and a row down the road to the ford.
local S3 = { 1240, 20 }
local lanterns = {}
for deg = 0, 330, 30 do
	if deg < 60 or deg > 120 then
		local a = math.rad(deg)
		table.insert(
			lanterns,
			{ kind = "LanternPole", x = S3[1] + 54 * math.cos(a), z = CZ + S3[2] + 54 * math.sin(a) }
		)
	end
end
for _, q in { { 1220, 74 }, { 1260, 74 }, { 1307, -45 }, { 1335, -34 }, { 1362, -23 }, { 1390, -11 } } do
	table.insert(lanterns, { kind = "LanternPole", x = q[1], z = CZ + q[2] })
end
-- and the field barn's haystacks, one either side (S2's cover stays the same both ways)
for _, x in { 794, 846 } do
	table.insert(lanterns, { kind = "Haystack", x = x, z = CZ - 136, yaw = 15 })
end

local LanternMeadows = {
	name = "Lantern Meadows",
	seed = 4417,
	-- the two nations that fight here (user 2026-11-04: Rules/Frontline.mapPair)
	pair = { West = "uniform1", East = "uniform2" },
	offMap = true, -- built beside Map 1: Greybox clears only its own terrain and adds no test spawn
	bounds = rect(-150, 2550, -280, 280),
	terrainMargin = 420,
	skirt = {
		width = 1000,
		hills = {
			{ -1243, CZ - 680, 300, 110 },
			{ 429, CZ - 1130, 360, 130 },
			{ 1714, CZ - 1080, 320, 100 },
			{ 3579, CZ - 580, 340, 120 },
			{ 3707, CZ + 480, 300, 95 },
			{ 1971, CZ + 1130, 380, 140 },
			{ 300, CZ + 1080, 320, 105 },
			{ -1307, CZ + 380, 340, 125 },
		}, -- {x, z, radius, peak height}
	},
	fogEnd = 600,

	-- Capture points, 420 apart, each fair to its two neighbours (tests/sectors.spec.luau) and on its own rise.
	sectors = {
		{ id = "S1", name = "S1", x = 400, z = CZ + 0, radius = 45, startOwner = "West", isHQ = true },
		{ id = "S2", name = "S2", x = 820, z = CZ - 20, radius = 45, startOwner = "West" },
		{ id = "S3", name = "S3", x = S3[1], z = CZ + S3[2], radius = 45, startOwner = "Neutral" },
		{ id = "S4", name = "S4", x = 1660, z = CZ - 30, radius = 45, startOwner = "East" },
		{ id = "S5", name = "S5", x = 2080, z = CZ - 60, radius = 45, startOwner = "East", isHQ = true },
	},
	-- Where the sprint times to the two points are equal (solved over the real ground, on average within 0.5 s).
	-- points: { x, z } from the south edge to the north edge.
	dividers = {
		{
			between = { "S1", "S2" },
			points = points({
				{ 579, -280 },
				{ 603, -210 },
				{ 603, -70 },
				{ 615, 0 },
				{ 615, 140 },
				{ 627, 210 },
				{ 639, 280 },
			}),
		},
		{
			between = { "S2", "S3" },
			points = points({
				{ 1077, -280 },
				{ 1047, -210 },
				{ 1035, -140 },
				{ 1035, -70 },
				{ 1029, 0 },
				{ 1023, 70 },
				{ 1023, 140 },
				{ 1005, 210 },
				{ 981, 280 },
			}),
		},
		{
			between = { "S3", "S4" },
			points = points({
				{ 1446, -280 },
				{ 1446, -140 },
				{ 1428, -70 },
				{ 1452, 0 },
				{ 1464, 70 },
				{ 1470, 140 },
				{ 1476, 210 },
				{ 1482, 280 },
			}),
		},
		{
			between = { "S4", "S5" },
			points = points({
				{ 1824, -280 },
				{ 1872, -210 },
				{ 1872, -70 },
				{ 1884, 0 },
				{ 1884, 140 },
				{ 1908, 210 },
				{ 1914, 280 },
			}),
		},
	},
	-- each side's spawn ~400 behind its HQ, as far back as its sector goes (MAP_RULES, user 2026-11-02; was ~225)
	spawnZones = {
		West = rect(-40, 30, -60, 60),
		East = rect(2420, 2490, -120, 0),
	},

	-- open meadows: gentler rolling ground than Map 1's valley
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
	rise = { radius = 110, height = 20, flat = 25 },
	-- The Aurel: from the north edge south between S3 and S4, through the festival ford, then bending east along the
	-- south edge past the Selvaran camp (user 2026-11-01: "approve, bent river"). Fords are points on it.
	river = {
		path = points({
			{ 1420, 1760 },
			{ 1432, 700 },
			{ 1440, 280 },
			{ 1452, 150 },
			{ 1444, 40 },
			{ 1446, -60 },
			{ 1462, -130 },
			{ 1500, -192 },
			{ 1570, -232 },
			{ 1680, -248 },
			{ 1900, -252 },
			{ 2200, -246 },
			{ 2550, -250 },
			{ 3000, -246 },
			{ 4000, -250 },
		}),
		width = 30,
		bankWidth = 14,
		bedY = -7,
		waterY = -2.5,
		fords = {
			{ x = 1444, z = CZ + 0, width = 30, bedY = -3.6 }, -- the festival ford: wide and shallow, by the landing
			{ x = 1447, z = CZ + 200, width = 9, bedY = -3.8 }, -- a narrow ford upstream
			{ x = 1470, z = CZ - 145, width = 8, bedY = -3.8 }, -- stepping stones at the bend
		},
	},
	-- tree-free ground: the festival ground behind S3 (its stage, later its lantern-makers' hall)
	reserved = {
		{ id = "Festival", minX = 1180, maxX = 1300, minZ = CZ + 60, maxZ = CZ + 170 },
	},

	-- The festival road through the meadows and over the ford, its landmarks and the fields' hedgerows
	-- (Rules/Village), and the Selvaran hamlet (Config/Buildings.Kits.Selvara) along the road east of S4 and up a lane.
	village = {
		area = rect(1700, 2550, -200, 250),
		kit = "Selvara",
		roads = {
			{
				id = "Main",
				width = 10,
				maxLots = 6,
				lotsFrom = 0.74, -- houses only past S4
				points = points({
					{ -150, 60 },
					{ 160, 72 },
					{ 400, 68 },
					{ 620, 48 },
					{ 820, 50 },
					{ 1040, 30 },
					{ 1160, -50 },
					{ 1300, -55 },
					{ 1400, -15 },
					{ 1445, 0 },
					{ 1560, 10 },
					{ 1760, 30 },
					{ 1900, 40 },
					{ 2080, 30 },
					{ 2240, 40 },
					{ 2550, 40 },
				}),
			},
			{
				id = "Borgo",
				width = 8,
				maxLots = 5,
				lotsFrom = 0.25,
				points = points({ { 1960, 35 }, { 1985, 110 }, { 2030, 170 }, { 2100, 215 } }),
			},
		},
		lotSpacing = 26,
		setback = 5,
		buildingGap = 6,
		keepClear = {
			{ x = 400, z = CZ + 0, r = 50 },
			{ x = 820, z = CZ - 20, r = 50 },
			{ x = 1240, z = CZ + 20, r = 50 },
			{ x = 1660, z = CZ - 30, r = 50 },
			{ x = 2080, z = CZ - 60, r = 50 },
			{ x = 2455, z = CZ - 60, r = 80 }, -- the East spawn
			{ x = 1880, z = CZ + 40, r = 30 }, -- clear of the S4|S5 divider
		},
		-- the map's own landmarks (Config/Buildings, one at a time; user 2026-11-01). The festival stage north of S3, on
		-- its x, facing the point.
		specials = {
			{ id = "Stage", style = "FestivalStage", x = S3[1], z = CZ + 86, front = { 0, -1 } },
			-- the lantern-makers' hall behind it, on the same x, its arcade facing the festival ground
			{ id = "LanternHall", style = "LanternHall", x = S3[1], z = CZ + 146, front = { 0, -1 } },
			-- the old watchtower on S1's hill, north of the point on its x, Katzmark's camp round it
			{ id = "Watchtower", style = "Watchtower", x = 400, z = CZ + 100, front = { 0, -1 } },
			-- the field barn among the hedgerows, south of S2 on its x, facing it
			{ id = "FieldBarn", style = "FieldBarn", x = 820, z = CZ - 110, front = { 0, 1 } },
			-- the cascina south of S5 on its x, between the point and the river, facing the point; Selvara's camp
			{ id = "Cascina", style = "Cascina", x = 2080, z = CZ - 170, front = { 0, 1 } },
			-- the ferry house on the east bank just north of the festival ford, its landing and boat on the river (west)
			{ id = "Ferry", style = "FerryHouse", x = 1483, z = CZ + 55, front = { -1, 0 } },
		},
		-- the hedgerow fields round S2, the same either side of its x (the point stays fair), with gaps to pass
		hedgerows = (function()
			local out = {}
			for _, x in { 640, 1000 } do
				for _, run in { { -262, -130 }, { -90, 25 }, { 65, 190 } } do
					table.insert(out, { a = p(x, run[1]), b = p(x, run[2]) })
				end
			end
			for _, z in { -175, 150 } do
				for _, run in { { 660, 780 }, { 860, 980 } } do
					table.insert(out, { a = p(run[1], z), b = p(run[2], z) })
				end
			end
			return out
		end)(),
		trees = { cell = 18, density = 0.05, roadClear = 5, buildingClear = 6 },
		cars = 0,
		features = lanterns,
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
