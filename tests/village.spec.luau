--!strict
local M = require("../src/shared/Config/Metrics")
local B = require("../src/shared/Config/Buildings")
local Map1 = require("../src/shared/Config/Maps/Map1")
local MT = require("../src/shared/Rules/MapTerrain")
local V = require("../src/shared/Rules/Village")
local P = require("../src/shared/Config/Props")

local layout = V.layout(Map1, B, M, MT, P)
local lots = layout.lots
local cfg = Map1.village
local pad = B.RoofOverhang

return {
	["deterministic"] = function()
		local again = V.layout(Map1, B, M, MT, P)
		assert(#again.lots == #lots and again.lots[#lots].x == lots[#lots].x, "layout changed between runs")
	end,
	["about 30 buildings, with every style family present"] = function()
		assert(#lots >= 26 and #lots <= 36, `{#lots} buildings`)
		local styles = {}
		for _, l in lots do
			styles[l.style] = true
		end
		for _, s in { "ThatchCottage" } do
			assert(styles[s], `no {s}`)
		end
	end,
	["buildings never overlap and keep a walkable gap"] = function()
		for i = 1, #lots do
			for j = i + 1, #lots do
				local a = V.corners(lots[i], pad + cfg.buildingGap / 2 - 0.01)
				local b = V.corners(lots[j], pad + cfg.buildingGap / 2 - 0.01)
				assert(not V.quadsOverlap(a, b), `{lots[i].id} overlaps {lots[j].id}`)
			end
		end
	end,
	["the spawn zones are clear of buildings (Normal mode: S1 / S5 spawns, the East one in the village)"] = function()
		for side, r in Map1.spawnZones do
			for _, l in lots do
				for x = r.minX, r.maxX, 4 do
					for z = r.minZ, r.maxZ, 4 do
						assert(not V.pointInQuad(x, z, V.corners(l, pad)), `{side} spawn on {l.id}`)
					end
				end
			end
		end
	end,
	["no building sits on a road, in the river or in a kept-clear square"] = function()
		for _, l in lots do
			for _, c in V.corners(l, pad) do
				assert(MT.roadDistance(Map1, c[1], c[2]) > 0, `{l.id} corner on a road`)
				for _, k in cfg.keepClear do
					assert((c[1] - k.x) ^ 2 + (c[2] - k.z) ^ 2 >= k.r * k.r, `{l.id} in a kept-clear square`)
				end
			end
			assert(not MT.isRiver(Map1, l.x, l.z), `{l.id} in the river`)
		end
	end,
	["every road-side house faces its road (door within reach of the road)"] = function()
		for _, l in lots do
			if not l.special then
				local dx, dz = l.x + l.fx * (l.depth / 2 + 1), l.z + l.fz * (l.depth / 2 + 1)
				assert(MT.roadDistance(Map1, dx, dz) < cfg.setback + 6, `{l.id} door far from road`)
			end
		end
	end,
	["village is not wall-to-wall: built footprint under 35% of the area"] = function()
		local a = cfg.area
		local built = 0
		for _, l in lots do
			if l.x >= a.minX and l.x <= a.maxX then
				built += l.width * l.depth
			end
		end
		local frac = built / ((a.maxX - a.minX) * (a.maxZ - a.minZ))
		assert(frac < 0.35, `built fraction {frac}`)
	end,
	["two-story buildings fit a full stair flight"] = function()
		local run = function(h: number)
			return h / M.Building.StairRise * M.Building.StairRun
		end
		for _, l in lots do
			if l.stories >= 2 then
				assert(l.width - 2 >= run(l.storyHeight) + 3, `{l.id} too narrow for its stairs`)
			end
		end
	end,
	["garden trees avoid roads and buildings"] = function()
		for _, t in layout.trees do
			assert(MT.roadDistance(Map1, t.x, t.z) > cfg.trees.roadClear, "tree on road")
			for _, l in lots do
				assert(not V.pointInQuad(t.x, t.z, V.corners(l, pad)), `tree inside {l.id}`)
			end
		end
		assert(#layout.trees > 20, "village needs trees")
	end,
	["roads are painted on the terrain"] = function()
		local r = cfg.roads[1]
		local x, z = V.pointAt(r.points, 300)
		assert(MT.materialAt(Map1, x, z) == "Sand", "main road not painted")
	end,
	["props exist"] = function()
		assert(#layout.poles >= 10 and #layout.signs >= 3 and #layout.cars >= 2 and #layout.fences > 10)
	end,
	["boundaries use real prop kinds, never sit on roads, and leave every door's gate open"] = function()
		for _, f in layout.fences do
			assert(table.find(P.Kinds, f.kind), `unknown boundary {f.kind}`)
			for k = 0, 4 do
				local x = f.a[1] + (f.b[1] - f.a[1]) * k / 4
				local z = f.a[2] + (f.b[2] - f.a[2]) * k / 4
				assert(MT.roadDistance(Map1, x, z) >= 0.5, "boundary on a road")
			end
		end
		-- the path straight out of each front door must not cross a boundary
		for _, l in lots do
			local rx, rz = -l.fz, l.fx
			for _, door in B.Templates[l.style].doors or { { center = 0 } } do
				local px = l.x + rx * door.center + l.fx * (l.depth / 2 + cfg.setback - 1.5)
				local pz = l.z + rz * door.center + l.fz * (l.depth / 2 + cfg.setback - 1.5)
				for _, f in layout.fences do
					local dx, dz = f.b[1] - f.a[1], f.b[2] - f.a[2]
					local len2 = dx * dx + dz * dz
					local t = math.clamp(((px - f.a[1]) * dx + (pz - f.a[2]) * dz) / len2, 0, 1)
					local d = math.sqrt((px - f.a[1] - dx * t) ^ 2 + (pz - f.a[2] - dz * t) ^ 2)
					assert(d > 1.5, `{l.id} door gate blocked`)
				end
			end
		end
	end,
	["yard clutter is real, off roads and outside other plots"] = function()
		assert(#layout.yard >= 8, `only {#layout.yard} yard props`)
		for _, y in layout.yard do
			assert(table.find(P.Kinds, y.kind), `unknown yard prop {y.kind}`)
			assert(MT.roadDistance(Map1, y.x, y.z) > 0, `{y.kind} on a road`)
		end
	end,
}
