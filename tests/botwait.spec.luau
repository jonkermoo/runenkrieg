--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotWait")

local W = Cfg.Move.Wait

return {
	["free: nobody within the gap, the bot's own spot not counted"] = function()
		local me = { x = 0, z = 0 }
		assert(R.free(0, 0, { me }, W.gap, me), "its own spot")
		assert(not R.free(0, 0, { me, { x = W.gap - 1, z = 0 } }, W.gap, me), "a mate too close")
		assert(R.free(0, 0, { { x = W.gap, z = 0 } }, W.gap), "exactly the gap away")
		assert(R.free(0, 0, {}, W.gap), "nobody")
	end,
	["pick: a fire step facing the enemy over a square or cover, a free one, within reach"] = function()
		local spots = {
			{ x = 10, z = 0, kind = "cover" },
			{ x = 20, z = 0, kind = "square" },
			{ x = 30, z = 0, kind = "step", fx = 1, fz = 0 },
			{ x = 40, z = 0, kind = "step", fx = -1, fz = 0 },
		}
		assert(R.pick(spots, 0, 0, 50, 0, 0, 1, 0, {}, W) == 3, "the step facing the enemy")
		assert(R.pick(spots, 0, 0, 50, 0, 0, -1, 0, {}, W) == 4, "the other way round")
		local next = R.pick(spots, 0, 0, 50, 0, 0, 1, 0, { { x = 30, z = 1 } }, W)
		assert(next ~= nil and next ~= 3, "the best taken: another")
		assert(R.pick(spots, 0, 0, 11, 0, 0, 1, 0, {}, W) == 1, "only the cover within reach")
		assert(R.pick(spots, 0, 0, 5, 0, 0, 1, 0, {}, W) == nil, "nothing within reach")
		local taken = { { x = 10, z = 0 }, { x = 20, z = 0 }, { x = 30, z = 0 }, { x = 40, z = 0 } }
		assert(R.pick(spots, 0, 0, 50, 0, 0, 1, 0, taken, W) == nil, "all taken")
	end,
	["pick: nearer is better among the same kind"] = function()
		local spots = { { x = 20, z = 0, kind = "square" }, { x = 5, z = 0, kind = "square" } }
		assert(R.pick(spots, 0, 0, 30, 0, 0, nil, nil, {}, W) == 2)
	end,
	["spread: away from the crowd, kept within reach, nil with nobody near"] = function()
		local x, z = R.spread(0, 0, 0, 0, 30, { { x = 1, z = 0 } }, W.gap, W.step, 0)
		assert(x and z and x < 0 and math.abs(z) < 1e-6, "pushed away from the mate")
		assert(math.abs((x :: number) + W.step) < 1e-6, "a step's length")
		local nx = R.spread(0, 0, 0, 0, 30, { { x = W.gap + 1, z = 0 } }, W.gap, W.step, 0)
		assert(nx == nil, "nobody crowding")
		local fx, fz = R.spread(0, 0, 0, 0, 3, { { x = 1, z = 0 } }, W.gap, W.step, 0)
		assert(fx and fz and math.abs(math.sqrt(fx * fx + fz * fz) - 3) < 1e-6, "held within reach")
		local rx, rz = R.spread(0, 0, 0, 0, 30, { { x = 0, z = 0 } }, W.gap, W.step, 0.25)
		assert(rx and rz and math.abs(math.sqrt(rx * rx + rz * rz) - W.step) < 1e-6, "standing on it: a random way")
	end,
	["stalled: no nearer for long enough; a new goal starts afresh"] = function()
		local p = { key = nil, best = 0, at = 0 }
		local g = { x = 100, z = 0 }
		assert(not R.stalled(p, g, 50, 0, W), "first look")
		assert(not R.stalled(p, g, 50 - W.gain - 1, W.stall - 1, W), "getting nearer")
		assert(not R.stalled(p, g, 50 - W.gain - 1, W.stall * 2 - 2, W), "not long enough since")
		assert(R.stalled(p, g, 50 - W.gain - 1, W.stall * 2, W), "no nearer for stall s")
		assert(not R.stalled(p, { x = -100, z = 0 }, 50, W.stall * 3, W), "a new goal")
		assert(not R.stalled(p, { x = -100, z = W.gain - 1 }, 50, W.stall * 3 + 1, W), "the same goal, a little moved")
	end,
	["clumped: each with enough others close"] = function()
		local pts = { { x = 0, z = 0 }, { x = 1, z = 0 }, { x = 0, z = 1 }, { x = 1, z = 1 }, { x = 50, z = 50 } }
		assert(R.clumped(pts, W.clump.within, 3) == 4)
		assert(R.clumped(pts, W.clump.within, 4) == 0)
		assert(R.clumped({}, W.clump.within, 3) == 0)
	end,
}
