--!strict
-- A frontline map's walk grid for the map checker (Rules/MapCheck), built once per map and shared by
-- tests/mapcheck.spec.luau, tests/sectors.spec.luau and the report (tests/mapreport.luau): grid(map).
local Assets = require("../src/shared/Config/Assets")
local B = require("../src/shared/Config/Buildings")
local Cfg = require("../src/shared/Config/MapCheck")
local M = require("../src/shared/Config/Metrics")
local P = require("../src/shared/Config/Props")
local Check = require("../src/shared/Rules/MapCheck")
local MT = require("../src/shared/Rules/MapTerrain")
local V = require("../src/shared/Rules/Village")

local Line = require("../src/shared/Config/Frontline").Line
local Frontline = require("../src/shared/Rules/Frontline")

local cache: { [any]: any } = {}

return function(map: any): any
	if cache[map] then
		return cache[map]
	end
	local layout = V.layout(map, B, M, MT, P)
	local lines = Frontline.lineQuads(map.sectors, Line, Line.treeClear)
	local trees = V.naturalTrees(map, MT, layout.lots, map.village.trees.buildingClear, lines)
	for _, t in layout.trees do
		table.insert(trees, t)
	end
	local lots = {}
	for _, l in layout.lots do
		for _, f in V.footprints(l, B, 0) do
			table.insert(lots, f)
		end
	end
	local g = Check.grid(map, MT, Cfg, trees, lots, Assets.TreeTargetHeight, M.Movement.MaxSlopeAngle)

	local spawns = {}
	local walks = {}
	for team, r in map.spawnZones do
		spawns[team] = Check.cellsIn(g, r)
		walks[team] = Check.walk(g, spawns[team])
	end
	cache[map] = { grid = g, spawns = spawns, walks = walks, map = map, cfg = Cfg, metrics = M, layout = layout }
	return cache[map]
end
