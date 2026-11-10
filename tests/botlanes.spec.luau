--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotLanes")

local LN = Cfg.Lanes
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["reach: to the bounds less the margin, at most the cap, nothing outside"] = function()
		local b = { minX = 0, maxX = 1000, minZ = -300, maxZ = 500 }
		assert(near(R.reach(500, 0, 0, 1, b, 40, 1000), 460), "north to 500 less 40")
		assert(near(R.reach(500, 0, 0, -1, b, 40, 1000), 260), "south to -300 less 40")
		assert(near(R.reach(500, 0, 0, 1, b, 40, 350), 350), "capped")
		assert(R.reach(500, 490, 0, 1, b, 40, 350) == 0, "past the margin already")
	end,
	["frame: lanes of one width over the width there, across the enemy's way"] = function()
		local b = { minX = 0, maxX = 1000, minZ = -300, maxZ = 500 }
		local cfg = { count = 5, reach = 350, margin = 40 }
		-- enemy's way +x: across is +z; 260 south, 350 north (capped) = 610 wide, 122 a lane
		local f = R.frame(500, 0, 1, 0, 0, b, cfg)
		assert(near(f.ax, 0) and near(f.az, 1), "across the way")
		assert(#f.centres == 5 and near(f.half, 61), "five lanes 122 wide")
		assert(near(f.centres[1], -260 + 61) and near(f.centres[5], 350 - 61), "edge to edge")
		local s = R.frame(500, 0, 1, 0, -110, b, cfg)
		assert(near(s.ox, 390) and near(s.oz, 0), "the line moved back")
	end,
	["offset, laneOf, inLane: the outer lanes run on past the edge"] = function()
		local b = { minX = -1000, maxX = 1000, minZ = -250, maxZ = 250 }
		local f = R.frame(0, 0, 1, 0, 0, b, { count = 5, reach = 1000, margin = 0 })
		assert(near(R.offset(f, 30, 120), 120), "across only")
		assert(R.laneOf(f, 0) == 3 and R.laneOf(f, 240) == 5 and R.laneOf(f, -240) == 1, "nearest middles")
		assert(R.inLane(f, 3, 49) and not R.inLane(f, 3, 51), "the middle lane is 100 wide")
		assert(R.inLane(f, 5, 900) and R.inLane(f, 1, -900), "past the edge")
		local x, z = R.point(f, 5, 1, 0, 30)
		assert(near(x, 30) and near(z, 200), "lane 5's middle, 30 on")
	end,
	["fromLine: the distance to the nearest leg between flags"] = function()
		local s = { { x = 0, z = 0 }, { x = 100, z = 0 }, { x = 200, z = 100 } }
		assert(near(R.fromLine(s, 50, 30), 30), "off the first leg")
		assert(near(R.fromLine(s, -40, 30), 50), "past the end")
		assert(near(R.fromLine({ { x = 0, z = 0 } }, 3, 4), 5), "one flag")
	end,
	["weights: 1 with nobody, up to `most` outnumbered `odds` to 1"] = function()
		local w = R.weights({ [2] = 4, [3] = 2 }, { [2] = 1, [3] = 1 }, 5, LN)
		assert(near(w[1], 1), "no enemies there")
		assert(near(w[2], LN.most), "4 against 1: all of it")
		assert(w[3] > 1 and w[3] < LN.most, "2 against 1: some")
	end,
	["targets: `least` each while there are enough, the rest by weight"] = function()
		local t = R.targets({ 1, 1, 3, 1, 1 }, 7, 1)
		assert(near(t[1], 1 + 2 / 7) and near(t[3], 1 + 6 / 7), "one each, two more by weight")
		local few = R.targets({ 1, 1, 1, 1, 1 }, 3, 1)
		assert(near(few[1], 0.6), "fewer squads than lanes: by weight only")
	end,
	["pick: the lane furthest under its share, spread out on a tie"] = function()
		local even = { 0.6, 0.6, 0.6, 0.6, 0.6 }
		local a = R.pick(even, {})
		assert(a == 3, "the middle first")
		local h = { [3] = 1 }
		local b = R.pick(even, h)
		assert(b == 1 or b == 5, "then the furthest from it")
		h[b] = 1
		local c = R.pick(even, h)
		assert(c == (if b == 1 then 5 else 1), "then the other edge")
		assert(R.pick({ 1, 1, 3, 1, 1 }, { 1, 1, 1, 1, 1 }) == 3, "the needy lane")
	end,
	["rebalance: one squad from the lane over to the lane under, once worth it"] = function()
		local from, to = R.rebalance({ 1, 1, 3, 1, 1 }, { 2, 1, 1, 1, 1 }, LN.moveAt)
		assert(from == 1 and to == 3, "over to the needy lane")
		local f2 = R.rebalance({ 1.2, 1.2, 1.2, 1.2, 1.2 }, { 2, 1, 1, 1, 1 }, LN.moveAt)
		assert(f2 == nil, "close enough: stays")
	end,
}
