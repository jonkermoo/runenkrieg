--!strict
local Cfg = require("../src/shared/Config/Shovel")
local M = require("../src/shared/Config/Metrics")
local Rules = require("../src/shared/Rules/Shovel")

return {
	["the blade lands ahead along the level look"] = function()
		local x, z = Rules.spot(10, 20, 0, -2, 2.6)
		assert(math.abs(x - 10) < 1e-9 and math.abs(z - 17.4) < 1e-9, `spot {x}, {z}`)
		local sx, sz = Rules.spot(1, 2, 0, 0, 2.6)
		assert(sx == 1 and sz == 2, "no look: in place")
	end,
	["each dig goes down a step, never past the deepest"] = function()
		local d = Cfg.Dig
		assert(Rules.lower(10, 10, d.depth, d.maxDepth) == d.depth, "first dig: a full step")
		assert(math.abs(Rules.lower(10 - d.maxDepth + 0.2, 10, d.depth, d.maxDepth) - 0.2) < 1e-9, "near the floor")
		assert(Rules.lower(10 - d.maxDepth, 10, d.depth, d.maxDepth) == 0, "at the floor: nothing")
		assert(Rules.lower(3, 10, d.depth, d.maxDepth) == 0, "below the floor: nothing")
	end,
	["a dug trench is as deep as the trench metric"] = function()
		assert(Cfg.Dig.maxDepth == M.Trench.Depth, "maxDepth follows Metrics.Trench.Depth")
	end,
	["ground in reach of the feet"] = function()
		assert(Rules.inReach(0, 0, 1.5, 7), "level")
		assert(not Rules.inReach(2, 0, 1.5, 7), "too high")
		assert(Rules.inReach(-6, 0, 1.5, 7), "in a hole")
		assert(not Rules.inReach(-8, 0, 1.5, 7), "too deep")
	end,
	["cells"] = function()
		assert(Rules.cell(3.9, -0.1, 4) == "0,-1", Rules.cell(3.9, -0.1, 4))
	end,
}
