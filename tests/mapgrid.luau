--!strict
-- Map 1's walk grid for the map checker (Rules/MapCheck), built once and shared by tests/mapcheck.spec.luau and the
-- report (tests/mapreport.luau).
local Assets = require("../src/shared/Config/Assets")
local B = require("../src/shared/Config/Buildings")
local Cfg = require("../src/shared/Config/MapCheck")
local M = require("../src/shared/Config/Metrics")
local Map1 = require("../src/shared/Config/Maps/Map1")
local P = require("../src/shared/Config/Props")
local Check = require("../src/shared/Rules/MapCheck")
local MT = require("../src/shared/Rules/MapTerrain")
local V = require("../src/shared/Rules/Village")

local layout = V.layout(Map1, B, M, MT, P)
local trees = table.clone(MT.trees(Map1))
for _, t in layout.trees do
	table.insert(trees, t)
end
local lots = {}
for _, l in layout.lots do
	table.insert(lots, { corners = V.corners(l, 0), stories = l.stories, storyHeight = l.storyHeight })
end
local g = Check.grid(Map1, MT, Cfg, trees, lots, Assets.TreeTargetHeight, M.Movement.MaxSlopeAngle)

local spawns = {}
local walks = {}
for team, r in Map1.spawnZones do
	spawns[team] = Check.cellsIn(g, r)
	walks[team] = Check.walk(g, spawns[team])
end

return { grid = g, spawns = spawns, walks = walks, map = Map1, cfg = Cfg, metrics = M }
