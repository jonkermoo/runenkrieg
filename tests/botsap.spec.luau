--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotSap")

local S = Cfg.Sap

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["failed: refused until it gave up, through water, or nothing dug for long enough"] = function()
		assert(not R.failed(0, false, false, S), "fresh")
		assert(not R.failed(S.dig - 1, false, false, S), "still digging")
		assert(R.failed(S.dig, false, false, S), "nothing dug in time")
		assert(R.failed(0, true, false, S), "gave up")
		assert(R.failed(0, false, true, S), "water")
	end,
	["stalled: stuck under fire, or losing men, for long enough"] = function()
		assert(R.stalled(S.stall, 0, true, 0, S), "pinned the whole time")
		assert(R.stalled(S.stall + 5, S.progress - 1, false, S.losses, S), "losing men")
		assert(not R.stalled(S.stall - 1, 0, true, 0, S), "not long enough yet")
		assert(not R.stalled(S.stall, S.progress, true, 0, S), "it got forward")
		assert(not R.stalled(S.stall, 0, false, 0, S), "nobody shooting, nobody lost")
	end,
	["run: toward the objective, turning one way then the other"] = function()
		local x1, z1 = R.run(0, 0, 100, 0, 1, S)
		local x2, z2 = R.run(0, 0, 100, 0, 2, S)
		assert(near(math.sqrt(x1 * x1 + z1 * z1), S.run), "its length")
		assert(x1 > 0 and z1 > 0 and x2 > 0 and z2 < 0, "a zig-zag")
		assert(near(z1, -z2), "the same turn each way")
		local x3, z3 = R.run(0, 0, 5, 0, 1, S)
		assert(math.sqrt(x3 * x3 + z3 * z3) <= 5 + 1e-6, "never past the objective")
	end,
	["over: at the objective's edge, or no fire for a while"] = function()
		assert(R.over(10, 20, 0, S.quiet))
		assert(R.over(100, 20, S.quiet, S.quiet))
		assert(not R.over(100, 20, S.quiet - 1, S.quiet))
	end,
}
