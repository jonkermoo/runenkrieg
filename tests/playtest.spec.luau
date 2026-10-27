--!strict
-- The playtest map (Config/Maps/Playtest): fair to both halves, everything inside its bounds, walkable, the zone's
-- spots and the spawn points clear, and the end spawns in howitzer range of the far brick cottage.
local Art = require("../src/shared/Config/Artillery")
local Assets = require("../src/shared/Config/Assets")
local B = require("../src/shared/Config/Buildings")
local CheckCfg = require("../src/shared/Config/MapCheck")
local DevCfg = require("../src/shared/Config/DevTools")
local M = require("../src/shared/Config/Metrics")
local Map = require("../src/shared/Config/Maps/Playtest")
local Map1 = require("../src/shared/Config/Maps/Map1")
local ZoneCfg = require("../src/shared/Config/ZoneMatch")
local Check = require("../src/shared/Rules/MapCheck")
local MT = require("../src/shared/Rules/MapTerrain")
local V = require("../src/shared/Rules/Village")

local layout = V.fixed(Map, B, M, MT)
local mid = Map.mirror
local b = Map.bounds

local function mirror(x: number, z: number): (number, number)
	return 2 * mid.x - x, 2 * mid.z - z
end

local function near(a: number, c: number, tol: number?): boolean
	return math.abs(a - c) <= (tol or 1e-6)
end

local function inside(r: any, x: number, z: number): boolean
	return x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ
end

local function grid()
	local lots = {}
	for _, l in layout.lots do
		table.insert(lots, { corners = V.corners(l, 0), stories = l.stories, storyHeight = l.storyHeight })
	end
	return Check.grid(Map, MT, CheckCfg, layout.trees, lots, Assets.TreeTargetHeight, M.Movement.MaxSlopeAngle)
end

return {
	["the ground and its surface are the same on both sides"] = function()
		for x = b.minX - 100, b.maxX + 100, 37 do
			for z = b.minZ - 100, b.maxZ + 100, 23 do
				local mx, mz = mirror(x, z)
				assert(near(MT.heightAt(Map, x, z), MT.heightAt(Map, mx, mz), 1e-4), `height differs at {x}, {z}`)
				assert(MT.materialAt(Map, x, z) == MT.materialAt(Map, mx, mz), `material differs at {x}, {z}`)
			end
		end
	end,
	["every tree has its mirror image, and there are plenty"] = function()
		local inBounds = 0
		for _, t in layout.trees do
			local mx, mz = mirror(t.x, t.z)
			local found = false
			for _, o in layout.trees do
				if near(o.x, mx, 1e-3) and near(o.z, mz, 1e-3) and o.kind == t.kind and o.scale == t.scale then
					found = true
					break
				end
			end
			assert(found, `the tree at {t.x}, {t.z} has no mirror`)
			if inside(b, t.x, t.z) then
				inBounds += 1
			end
		end
		assert(inBounds >= 40, `only {inBounds} trees in the field (user: "way more trees")`)
	end,
	["every building, fence and yard piece has its mirror image (but the centre one)"] = function()
		for _, l in layout.lots do
			local mx, mz = mirror(l.x, l.z)
			local found = false
			for _, o in layout.lots do
				found = found
					or (
						o.style == l.style
						and near(o.x, mx)
						and near(o.z, mz)
						and near(o.fx, -l.fx)
						and near(o.fz, -l.fz)
					)
			end
			assert(found or (near(l.x, mid.x) and near(l.z, mid.z)), `{l.id} has no mirror`)
		end
		for _, f in layout.fences do
			local ax, az = mirror(f.a[1], f.a[2])
			local found = false
			for _, o in layout.fences do
				found = found or (o.kind == f.kind and near(o.a[1], ax) and near(o.a[2], az))
			end
			assert(found, `a {f.kind} at {f.a[1]}, {f.a[2]} has no mirror`)
		end
		for _, y in layout.yard do
			local mx, mz = mirror(y.x, y.z)
			local found = false
			for _, o in layout.yard do
				found = found or (o.kind == y.kind and near(o.x, mx) and near(o.z, mz))
			end
			assert(found, `the {y.kind} at {y.x}, {y.z} has no mirror`)
		end
	end,
	["no guns on the map (user: players build them)"] = function()
		assert((Map :: any).guns == nil, "the map places no guns")
	end,
	["buildings stand inside the bounds, apart from each other, the spawns and the trees"] = function()
		for i, l in layout.lots do
			local q = V.corners(l, 0)
			for _, c in q do
				assert(inside(b, c[1], c[2]), `{l.id} pokes out of the bounds`)
			end
			for j, o in layout.lots do
				assert(i == j or not V.quadsOverlap(V.corners(l, 3), V.corners(o, 3)), `{l.id} and {o.id} overlap`)
			end
			for team, z in Map.spawnZones do
				local zq = { { z.minX, z.minZ }, { z.maxX, z.minZ }, { z.maxX, z.maxZ }, { z.minX, z.maxZ } }
				assert(not V.quadsOverlap(V.corners(l, 6), zq), `{l.id} is on the {team} spawn`)
			end
			for _, t in layout.trees do
				assert(not V.pointInQuad(t.x, t.z, q), `a tree grows inside {l.id}`)
			end
		end
	end,
	["the spawn points: inside the bounds, tree-free, each with its mirror"] = function()
		local pts = Map.zoneMatch.spawns
		assert(#pts == 8, `{#pts} spawn points`)
		for i, p in pts do
			assert(inside(b, p[1], p[2]), `S{i} out of bounds`)
			for _, t in layout.trees do
				assert((t.x - p[1]) ^ 2 + (t.z - p[2]) ^ 2 > 16, `a tree on S{i}`)
			end
			local mx, mz = mirror(p[1], p[2])
			local m = pts[(i + 3) % 8 + 1]
			assert(near(m[1], mx) and near(m[2], mz), `S{i}'s mirror is not S{(i + 3) % 8 + 1}`)
		end
	end,
	["the zone's spots: inside the bounds, off the buildings and trees, mirrored, each with spawns clear of it"] = function()
		local spots = Map.zoneMatch.spots
		assert(#spots >= 3, "the zone needs spots to move between")
		local r = ZoneCfg.Radius
		for i, p in spots do
			assert(inside(b, p[1] - r, p[2] - r) and inside(b, p[1] + r, p[2] + r), `spot {i} out of bounds`)
			for _, t in layout.trees do
				assert((t.x - p[1]) ^ 2 + (t.z - p[2]) ^ 2 > (r + 1) ^ 2, `a tree in spot {i}`)
			end
			for k = 0, 15 do
				local a = k / 16 * 2 * math.pi
				local x, z = p[1] + r * math.cos(a), p[2] + r * math.sin(a)
				for _, l in layout.lots do
					assert(not V.pointInQuad(x, z, V.corners(l, 0.5)), `spot {i}'s ring runs into {l.id}`)
				end
			end
			local mx, mz = mirror(p[1], p[2])
			local found = false
			for _, o in spots do
				found = found or (near(o[1], mx) and near(o[2], mz))
			end
			assert(found, `spot {i} has no mirror`)
			local clear = 0
			for _, sp in Map.zoneMatch.spawns do
				if math.sqrt((sp[1] - p[1]) ^ 2 + (sp[2] - p[2]) ^ 2) >= ZoneCfg.SpawnZoneClear then
					clear += 1
				end
			end
			assert(clear >= 4, `only {clear} spawn points clear of spot {i}`)
		end
	end,
	["clear of Map 1 and its skirt"] = function()
		local reach = Map1.terrainMargin + Map1.skirt.width
		local own = Map.terrainMargin + Map.skirt.width
		assert(b.minZ - own > Map1.bounds.maxZ + reach, "the playtest ground runs into Map 1's skirt")
	end,
	["a howitzer by an end spawn reaches the brick cottage at the other end"] = function()
		local h = Art.Guns.artillery_howitzer
		local reachAt = function(e: number): number
			return h.speed ^ 2 * math.sin(math.rad(2 * e)) / h.gravity
		end
		local short = math.min(reachAt(h.elevation[1]), reachAt(h.elevation[2]))
		local long = reachAt(45)
		local pts = Map.zoneMatch.spawns
		for _, pair in { { pts[1], "EastBrickCottage" }, { pts[5], "WestBrickCottage" } } do
			local sp, target = pair[1], pair[2]
			for _, l in layout.lots do
				if l.id == target then
					local d = math.sqrt((l.x - sp[1]) ^ 2 + (l.z - sp[2]) ^ 2)
					assert(d > short + 10 and d < long, `spawn to {target}: {d} (range {short}-{long})`)
				end
			end
		end
	end,
	["the dev teleports stand on the end spawns"] = function()
		local pts = Map.zoneMatch.spawns
		for id, p in { PlaytestWest = pts[1], PlaytestEast = pts[5] } do
			local found = false
			for _, e in DevCfg.Extra do
				if e.id == id then
					found = math.abs(e.x - p[1]) <= 5 and math.abs(e.z - p[2]) <= 5
				end
			end
			assert(found, `the teleport {id} is missing or off its spawn`)
		end
	end,
	["undo destruction covers the playtest ground"] = function()
		local covered = false
		for _, box in DevCfg.World.Terrain do
			covered = covered
				or (box.min[1] <= b.minX and box.max[1] >= b.maxX and box.min[3] <= b.minZ and box.max[3] >= b.maxZ)
		end
		assert(covered, "no Config/DevTools.World.Terrain box holds the playtest bounds")
	end,
	["walkable: every spawn reaches every spot, no pits, no cut-off ground, mirrored spawns alike"] = function()
		local g = grid()
		local runs = {}
		for name, r in Map.spawnZones do
			local cells = Check.cellsIn(g, r)
			assert(#cells > 0, `{name} has no open cell`)
			local walk = Check.walk(g, cells)
			local pits = Check.pits(g, cells)
			assert(#pits == 0, `{name}: {#pits} cells you can't climb out of`)
			for _, p in Check.pockets(g, walk) do
				assert(#p <= CheckCfg.PocketCells, `from {name}, a cut-off area of {#p} cells`)
			end
			runs[name] = {}
			for i, p in Map.zoneMatch.spots do
				local _, d = Check.nearest(g, walk, p[1], p[2], ZoneCfg.Radius)
				assert(d, `{name} can't walk to spot {i}`)
				runs[name][i] = d
			end
		end
		-- S1 to the centre cottage's front yard (spot 1) as far as its mirror S5 to the back yard (spot 2; the grid isn't
		-- exactly symmetric: 10%)
		local a, c = runs.S1[1], runs.S5[2]
		assert(math.abs(a - c) <= 0.1 * a, `S1 {a} vs S5 {c} to the centre`)
	end,
}
