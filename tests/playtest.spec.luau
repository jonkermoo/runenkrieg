--!strict
-- The playtest map (Config/Maps/Playtest): fair to both sides, everything inside its bounds, walkable, and each
-- spawn in howitzer range of the other side's brick cottage.
local Art = require("../src/shared/Config/Artillery")
local Assets = require("../src/shared/Config/Assets")
local B = require("../src/shared/Config/Buildings")
local CheckCfg = require("../src/shared/Config/MapCheck")
local DevCfg = require("../src/shared/Config/DevTools")
local M = require("../src/shared/Config/Metrics")
local Map = require("../src/shared/Config/Maps/Playtest")
local Map1 = require("../src/shared/Config/Maps/Map1")
local U = require("../src/shared/Config/Uniforms")
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
	["the spawns are inside the bounds, tree-free and sit far apart"] = function()
		local W, E = Map.spawnZones.West, Map.spawnZones.East
		for _, z in { W, E } do
			assert(inside(b, z.minX, z.minZ) and inside(b, z.maxX, z.maxZ), "spawn zone out of bounds")
		end
		for _, t in layout.trees do
			assert(not inside(W, t.x, t.z) and not inside(E, t.x, t.z), `a tree on a spawn at {t.x}, {t.z}`)
		end
		local d = math.abs((W.minX + W.maxX) / 2 - (E.minX + E.maxX) / 2)
		assert(d >= 250 and d <= 400, `spawns {d} apart`)
	end,
	["clear of Map 1 and its skirt, the dev areas and the other side's spawn"] = function()
		local reach = Map1.terrainMargin + Map1.skirt.width
		local own = Map.terrainMargin + Map.skirt.width
		assert(b.minZ - own > Map1.bounds.maxZ + reach, "the playtest ground runs into Map 1's skirt")
	end,
	["a howitzer by either spawn reaches the other side's brick cottage"] = function()
		local h = Art.Guns.artillery_howitzer
		local g = h.gravity
		local reachAt = function(e: number): number
			return h.speed ^ 2 * math.sin(math.rad(2 * e)) / g
		end
		local short = math.min(reachAt(h.elevation[1]), reachAt(h.elevation[2]))
		local long = reachAt(45)
		for team, z in Map.spawnZones do
			local sx, sz = (z.minX + z.maxX) / 2, (z.minZ + z.maxZ) / 2
			local target = if team == "West" then "EastBrickCottage" else "WestBrickCottage"
			for _, l in layout.lots do
				if l.id == target then
					local d = math.sqrt((l.x - sx) ^ 2 + (l.z - sz) ^ 2)
					assert(d > short + 10 and d < long, `{team} spawn to {target}: {d} (range {short}-{long})`)
				end
			end
		end
	end,
	["each side's kit is a real team uniform, and they differ"] = function()
		local W, E = Map.sides.West.kit, Map.sides.East.kit
		assert(W ~= E, "both sides wear the same uniform")
		assert(table.find(U.Teams, W) and table.find(U.Teams, E), "a side's kit is not a team uniform")
	end,
	["each side's dev teleport stands in its spawn zone"] = function()
		for team, z in Map.spawnZones do
			local found = false
			for _, e in DevCfg.Extra do
				if e.id == "Playtest" .. team then
					found = inside(z, e.x, e.z)
				end
			end
			assert(found, `the teleport Playtest{team} is missing or off its spawn`)
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
	["walkable: both spawns open, every open cell reached, no pits, the runs across alike"] = function()
		local g = grid()
		local spawns, walks = {}, {}
		for team, r in Map.spawnZones do
			spawns[team] = Check.cellsIn(g, r)
			assert(#spawns[team] > 4, `{team} spawn has {#spawns[team]} open cells`)
			walks[team] = Check.walk(g, spawns[team])
			local pits = Check.pits(g, spawns[team])
			assert(#pits == 0, `{team}: {#pits} cells you can't climb out of`)
		end
		for _, p in Check.pockets(g, walks.West) do
			assert(#p <= CheckCfg.PocketCells, `a cut-off area of {#p} cells`)
		end
		local runs = {}
		for team, other in { West = "East", East = "West" } do
			local z = Map.spawnZones[other]
			local _, d = Check.nearest(g, walks[team], (z.minX + z.maxX) / 2, (z.minZ + z.maxZ) / 2, 12)
			assert(d, `{team} can't walk to the {other} spawn`)
			runs[team] = d
		end
		assert(math.abs(runs.West - runs.East) <= 0.05 * runs.West, `runs across {runs.West} vs {runs.East}`)
	end,
}
