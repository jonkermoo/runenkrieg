--!strict
-- Playtest map (user 2026-10-27: "extremely small, fit for 2 people, but have enough stuff to demonstrate features like
-- the howitzer and building and destruction"): untouched countryside where soldiers build their own trenches,
-- sandbags and guns with the shovel (user: "no guns should spawn on the map ... the map should look untouched and let
-- war ruin it"), played as a zone-capture free-for-all (user: "let's make this a zone capture FFA map"; Config/ZoneMatch).
-- Built off Map 1, 2,800 studs north of it, by the same Greybox (Rules/MapTerrain):
--   require(game.ServerStorage.Dev.Greybox:Clone()).build("Playtest")
-- Rebuilding Map 1 clears all terrain, so rebuild this after it. The match on it: src/server/ZoneMatch.
-- Fair by construction: point-symmetric about `mirror` (the ground, its trees, every piece below and its mirror image).
-- Its length is set by the howitzer's shortest range (~201 studs at 80 degrees, Config/Artillery): a howitzer built
-- by an end spawn reaches the brick cottage at the other end.
-- Pieces are written for the West half in local studs from the centre (x along the front, West = -x) and mirrored.

local CX, CZ = 0, 2800 -- world position of the centre

local function rect(minX: number, maxX: number, minZ: number, maxZ: number): any
	return { minX = CX + minX, maxX = CX + maxX, minZ = CZ + minZ, maxZ = CZ + maxZ }
end
local function flip(r: any): any
	return { minX = 2 * CX - r.maxX, maxX = 2 * CX - r.minX, minZ = 2 * CZ - r.maxZ, maxZ = 2 * CZ - r.minZ }
end

-- West-half pieces (local). Buildings: Config/Buildings.Templates, `front` the way the door faces; `centre` = on the
-- centre point (not mirrored). Fences: Config/Props kinds from a to b. Yard: Config/Props.YardKinds.
local west = {
	buildings = {
		{ id = "BrickCottage", style = "TileCottage", x = -95, z = -40, front = { 0, 1 }, colorSeed = 4 },
		{ id = "Shed", style = "Shed", x = -60, z = 46, front = { 0, -1 }, colorSeed = 11 },
		{ id = "Cottage", style = "ThatchCottage", x = 0, z = 0, front = { 0, 1 }, colorSeed = 7, centre = true },
	},
	fences = {
		{ kind = "StoneWall", a = { -35, -32 }, b = { -35, -12 } },
		{ kind = "StoneWall", a = { -35, 20 }, b = { -35, 40 } },
		{ kind = "StoneWall", a = { -82, 6 }, b = { -68, 6 } },
		{ kind = "Hedge", a = { -174, -30 }, b = { -174, 30 } }, -- behind the spawn
		{ kind = "Hedge", a = { -22, -62 }, b = { 22, -62 } },
		{ kind = "RailFence", a = { -110, -54 }, b = { -80, -54 } }, -- the cottage's back garden
	},
	yard = {
		{ kind = "Haystack", x = -48, z = 52, yaw = 20 },
		{ kind = "Woodpile", x = -110, z = -30, yaw = 90 },
	},
	-- kept clear of trees: the open ground in front of each spawn, for digging in
	clear = {
		{ id = "SpawnField", minX = -150, maxX = -112, minZ = -24, maxZ = 24 },
	},
	-- the zone's spots, with their mirrors 6 (user 2026-10-27: "mix yards and open ground"): the centre cottage's front
	-- yard, the brick cottage's, and open field between the stone walls and the spawn's ground, held from trenches you
	-- dig; and the spawn points (Config/ZoneMatch). Both kept clear of trees
	spots = { { 0, 24 }, { -95, -15 }, { -52, -2 } },
	spawns = { { -165, 0 }, { -130, 62 }, { -128, -62 }, { -40, -70 } },
}

local function mirrored(): any
	local out = { lots = {}, fences = {}, yard = {}, reserved = {}, spots = {}, spawns = {}, spawnZones = {} }
	local function both(x: number, z: number, f: (number, number, number) -> ())
		f(CX + x, CZ + z, 1)
		if x ~= 0 or z ~= 0 then
			f(CX - x, CZ - z, -1)
		end
	end
	for _, b in west.buildings do
		local pieces = if b.centre then { 1 } else { 1, -1 }
		for _, s in pieces do
			table.insert(out.lots, {
				id = if s == 1 then (if b.centre then b.id else "West" .. b.id) else "East" .. b.id,
				style = b.style,
				x = CX + s * b.x,
				z = CZ + s * b.z,
				fx = s * b.front[1],
				fz = s * b.front[2],
				colorSeed = b.colorSeed,
			})
		end
	end
	for _, f in west.fences do
		table.insert(out.fences, { kind = f.kind, a = { CX + f.a[1], CZ + f.a[2] }, b = { CX + f.b[1], CZ + f.b[2] } })
		table.insert(out.fences, { kind = f.kind, a = { CX - f.a[1], CZ - f.a[2] }, b = { CX - f.b[1], CZ - f.b[2] } })
	end
	for _, y in west.yard do
		both(y.x, y.z, function(x, z, s)
			table.insert(out.yard, { kind = y.kind, x = x, z = z, yaw = y.yaw + (if s == 1 then 0 else 180) })
		end)
	end
	for _, c in west.clear do
		local r = rect(c.minX, c.maxX, c.minZ, c.maxZ)
		r.id = "West" .. c.id
		local m = flip(r)
		m.id = "East" .. c.id
		table.insert(out.reserved, r)
		table.insert(out.reserved, m)
	end
	for _, p in west.spots do
		for _, sgn in { 1, -1 } do
			local x, z = CX + sgn * p[1], CZ + sgn * p[2]
			table.insert(out.spots, { x, z })
			local r = 18 -- (Config/ZoneMatch.Radius, plus a little)
			table.insert(
				out.reserved,
				{ id = `Zone{#out.spots}`, minX = x - r, maxX = x + r, minZ = z - r, maxZ = z + r }
			)
		end
	end
	-- every West spawn point, then each one's mirror: S1-S4 West half, S5-S8 East
	for _, sgn in { 1, -1 } do
		for _, p in west.spawns do
			table.insert(out.spawns, { CX + sgn * p[1], CZ + sgn * p[2] })
		end
	end
	for i, p in out.spawns do
		out.spawnZones[`S{i}`] = { minX = p[1] - 5, maxX = p[1] + 5, minZ = p[2] - 5, maxZ = p[2] + 5 }
	end
	return out
end

local pieces = mirrored()

local Playtest = {
	name = "Playtest",
	seed = 2027,
	offMap = true, -- built beside Map 1: Greybox clears only its own terrain and adds no spawn of its own
	mirror = { x = CX, z = CZ }, -- point symmetry: (x, z) and (2 cx - x, 2 cz - z) are alike
	bounds = rect(-180, 180, -80, 80),
	terrainMargin = 140, -- forest round the clearing; relief fades to flat at its edge
	skirt = {
		width = 420,
		hills = {
			{ CX - 420, CZ - 380, 240, 70 },
			{ CX + 380, CZ + 420, 260, 80 },
			{ CX + 520, CZ - 300, 220, 60 },
			{ CX - 540, CZ + 330, 230, 65 },
		},
	},
	fogEnd = 600,

	sectors = {},
	-- a little square round each spawn point (kept clear of trees, Rules/MapTerrain)
	spawnZones = pieces.spawnZones,
	-- the zone-capture match (Config/ZoneMatch, src/server/ZoneMatch): the spots the zone moves between and the spawn
	-- points ({ x, z } world studs)
	zoneMatch = { spots = pieces.spots, spawns = pieces.spawns },

	terrain = {
		minY = -24,
		maxY = 80,
		baseAmp = 7, -- a gentle swell across the field
		baseScale = 220,
		midAmp = 3.5,
		midScale = 90,
		detailAmp = 1.6,
		detailScale = 40,
		bumpAmp = 0.7,
		bumpScale = 14,
		moundAmp = 3, -- the odd low knoll (cover in the open)
		moundScale = 60,
		moundThreshold = 0.3,
		patchThreshold = 0.5,
		surfaceDepth = 1.5,
	},
	wild = {
		start = 40,
		ramp = 60,
		fall = 30,
		amp = 18,
		scale = 120,
		roughAmp = 3,
		roughScale = 30,
	},

	reserved = pieces.reserved,
	layout = { lots = pieces.lots, fences = pieces.fences, yard = pieces.yard },

	-- Trees (user 2026-10-27: "i would add way more trees"): groves in the field, thick forest round it.
	trees = {
		cell = 11,
		forestScale = 110,
		groveThreshold = 0.02,
		groveDensity = 0.5,
		scatterDensity = 0.1,
		edgeBand = 90,
		edgeDensity = 0.65,
		outerDensity = 0.25,
		maxSlope = 34,
		footprint = 2,
		sink = 0.8,
		sectorClearFrac = 0.4,
		buildingClear = 8, -- no trees this close to a building or yard piece, nor half this to a fence (Rules/Village.fixed)
		maxCount = 3000,
	},
}

return table.freeze(Playtest)
