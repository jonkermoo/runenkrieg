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
	end,
	["join loading: the foci cover the whole map and its margin, each cell inside one focus's radius"] = function()
		local b = { minX = -150, maxX = 2550, minZ = -280, maxZ = 280 } -- (Map 1)
		local f = R.foci(b, Cfg.FocusMargin, Cfg.MinRadius)
		local cell = Cfg.MinRadius * math.sqrt(2)
		local w, d = 2700 + 2 * Cfg.FocusMargin, 560 + 2 * Cfg.FocusMargin
		assert(#f == math.ceil(w / cell) * math.ceil(d / cell), `a grid of foci ({#f})`)
		-- every corner of the grown bounds within MinRadius of some focus
		for _, c in
			{
				{ b.minX - Cfg.FocusMargin, b.minZ - Cfg.FocusMargin },
				{ b.maxX + Cfg.FocusMargin, b.maxZ + Cfg.FocusMargin },
				{ 1200, 0 },
			}
		do
			local best = math.huge
			for _, p in f do
				best = math.min(best, math.sqrt((p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2))
			end
			assert(best <= Cfg.MinRadius + 1e-6, `({c[1]}, {c[2]}) covered ({best})`)
		end
		assert(#f <= 12, "a handful of foci per map")
	end,
	["join loading: the parts held against the server's count"] = function()
		assert(R.held(0, nil, Cfg.HeldShare), "no count: held")
		assert(R.held(97, 100, 0.97) and not R.held(96, 100, 0.97), "the share")
		assert(R.held(5, 0, Cfg.HeldShare), "an empty map: held")
		assert(Cfg.HeldShare > 0.9 and Cfg.HeldShare <= 1, "nearly every part")
	end,
	["loading: the victory screen and the armory wait on players, capped"] = function()
		local Front = require("../src/shared/Config/Frontline")
		local Cut = require("../src/shared/Rules/Cutscenes")
		assert(Front.Victory.least >= 6, "the victory screen holds 6 s at the least (user 2026-11-04)")
		assert(
			Front.Victory.max > Front.Victory.least and Front.Loading.max > Front.Loading.least,
			"caps past the least"
		)
		assert(
			not Cut.loadOver(Front.Victory.least + 1, Front.Victory.least, Front.Victory.max, 1),
			"waits for a player"
		)
		assert(Cut.loadOver(Front.Victory.least, Front.Victory.least, Front.Victory.max, 0), "everyone ready: on")
		assert(Cut.loadOver(Front.Victory.max, Front.Victory.least, Front.Victory.max, 3), "the cap")
	end,
}
