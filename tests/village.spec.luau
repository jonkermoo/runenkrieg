--!strict
local M = require("../src/shared/Config/Metrics")
local B = require("../src/shared/Config/Buildings")
local Map1 = require("../src/shared/Config/Maps/Map1")
local MT = require("../src/shared/Rules/MapTerrain")
local V = require("../src/shared/Rules/Village")

local layout = V.layout(Map1, B, M, MT)
local lots = layout.lots
local cfg = Map1.village
local pad = B.RoofOverhang

return {
	["deterministic"] = function()
		local again = V.layout(Map1, B, M, MT)
		assert(#again.lots == #lots and again.lots[#lots].x == lots[#lots].x, "layout changed between runs")
	end,
	["about 30 buildings, with every style family present"] = function()
		assert(#lots >= 26 and #lots <= 36, `{#lots} buildings`)
		local styles = {}
		for _, l in lots do
			styles[l.style] = true
		end
		for _, s in { "Cottage", "Weatherboard", "Row", "Church", "Station", "Barn" } do
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
}
