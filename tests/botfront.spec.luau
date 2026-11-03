--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotFront")

local F = Cfg.Front

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["plan: open until contact, then trench; the admin panel's wins"] = function()
		assert(R.plan(nil, nil) == "open")
		assert(R.plan(12, nil) == "trench")
		assert(R.plan(nil, "assault") == "assault" and R.plan(12, "open") == "open")
		for _, p in R.Plans do
			assert(R.plan(nil, p) == p, p)
		end
	end,
	["captured: only a change between two looks"] = function()
		assert(not R.captured(nil, { "West", "East" }), "the first look")
		assert(not R.captured({ "West", "East" }, { "West", "East" }))
		assert(R.captured({ "West", "East" }, { "West", "West" }))
	end,
	["sapNow: stuck in any plan; in trench also near the objective; never assaulting"] = function()
		assert(not R.sapNow("open", false, 0, F) and R.sapNow("open", true, 999, F))
		assert(R.sapNow("trench", false, F.sapFrom, F) and not R.sapNow("trench", false, F.sapFrom + 1, F))
		assert(R.sapNow("flank", false, F.sapFrom - 1, F))
		assert(not R.sapNow("assault", true, 0, F))
	end,
	["parallel: across the way, centred on the head, its width"] = function()
		assert(R.parallelNow(F.parallel.at, F) and not R.parallelNow(F.parallel.at + 1, F))
		local ax, az, bx, bz = R.parallel(10, 0, 100, 0, F.parallel.width)
		assert(near(ax, 10) and near(bx, 10), "across an x-ward way")
		assert(near(math.abs(bz - az), F.parallel.width) and near((az + bz) / 2, 0), "centred, its width")
	end,
	["flank: 1 in 3 attacking squads, alternating sides"] = function()
		local s = F.Flank.share
		assert(R.flank(1, 0, 0, s) == nil and R.flank(2, 0, 0, s) == nil, "too few squads")
		assert(R.flank(3, 0, 0, s) == -1, "the third")
		assert(R.flank(3, 1, 0, s) == nil, "one is enough for three")
		assert(R.flank(6, 1, 0, s) == 1, "the other side next")
	end,
}
