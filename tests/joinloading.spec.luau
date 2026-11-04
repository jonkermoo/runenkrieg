--!strict
local R = require("../src/shared/Rules/JoinLoading")
local Cfg = require("../src/shared/Config/JoinLoading")

return {
	["join loading: a grid over the map no cell wider than the spacing, points off the grid added"] = function()
		local b = { minX = -150, maxX = 2550, minZ = -280, maxZ = 280 } -- (Map 1)
		local s = R.spots(b, { { 0, 0 }, { 5000, 0 } }, Cfg.Spacing)
		local grid = math.ceil(2700 / Cfg.Spacing) * math.ceil(560 / Cfg.Spacing)
		assert(#s == grid + 1, "the grid and the one far point")
		for _, p in s do
			assert(p[1] >= b.minX and p[2] >= b.minZ and p[2] <= b.maxZ or p[1] == 5000, "inside the bounds")
		end
		assert(s[#s][1] == 5000, "the far point last")
		local one = R.spots({ minX = 0, maxX = 10, minZ = 0, maxZ = 10 }, {}, Cfg.Spacing)
		assert(#one == 1 and one[1][1] == 5 and one[1][2] == 5, "a small map: its middle")
	end,
	["join loading: progress and its words"] = function()
		assert(R.progress(0, 0) == 1, "nothing to load: done")
		assert(R.progress(3, 4) == 0.75 and R.progress(9, 4) == 1 and R.progress(-1, 4) == 0, "clamped")
		assert(R.status(0.426) == "Loading the front · 42%", R.status(0.426))
		assert(R.status(1) == "Loading the front · 100%")
		assert(Cfg.Max > Cfg.BuiltWait, "the map's model is waited for inside the whole wait")
	end,
}
