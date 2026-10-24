--!strict
local D = require("../src/shared/Config/Damage")
local Refill = require("../src/shared/Rules/Refill")

local R = D.Blast.Crater.Refill

return {
	["the agreed timings: 2 min wait, 5 min fill, 2 min of mud, at most 40 waiting"] = function()
		assert(R.delay == 120 and R.time == 300 and R.mud == 120, "2 + 5 + 2 minutes")
		assert(R.maxCraters == 40)
		assert(R.steps >= 1 and R.tick > 0 and R.budget > 0)
		assert(R.rimFill > 0 and R.rimFill < 1, "thrown earth fills part of an older crater, not all")
	end,
	["nothing fills during the wait, then it fills in whole steps to all of it"] = function()
		assert(Refill.share(0, R) == 0)
		assert(Refill.share(R.delay, R) == 0)
		local step = R.time / R.steps
		assert(Refill.share(R.delay + step * 0.99, R) == 0, "no part steps")
		assert(math.abs(Refill.share(R.delay + step, R) - 1 / R.steps) < 1e-9)
		assert(math.abs(Refill.share(R.delay + R.time / 2, R) - 0.5) < 1e-9)
		assert(Refill.share(R.delay + R.time, R) == 1)
		assert(Refill.share(R.delay + R.time * 5, R) == 1)
		local last = 0
		for t = 0, R.delay + R.time + 10, 7 do
			local s = Refill.share(t, R)
			assert(s >= last, "never goes back")
			last = s
		end
	end,
	["the mud outlasts the shape"] = function()
		assert(not Refill.done(R.delay + R.time, R), "filled, still mud")
		assert(not Refill.done(R.delay + R.time + R.mud - 1, R))
		assert(Refill.done(R.delay + R.time + R.mud, R))
	end,
	["a voxel eases back to the ground before: bowls fill, rims settle"] = function()
		assert(Refill.occupancy(0.2, 1, 0) == 0.2)
		assert(math.abs(Refill.occupancy(0.2, 1, 0.5) - 0.6) < 1e-9)
		assert(Refill.occupancy(0.2, 1, 1) == 1)
		-- rim earth where there was air goes again
		assert(Refill.occupancy(0.8, 0, 1) == 0)
		assert(math.abs(Refill.occupancy(0.8, 0, 0.25) - 0.6) < 1e-9)
	end,
	["materials: earth put back is mud until done, then the old ground"] = function()
		local air, mud, grass = "Air", "Mud", "Grass"
		assert(Refill.material(0, grass, mud, false, air, mud) == air, "empty is air")
		assert(Refill.material(0.5, grass, air, false, air, mud) == mud, "refilled earth is mud")
		assert(Refill.material(0.5, grass, mud, false, air, mud) == mud, "churned ground stays mud")
		assert(Refill.material(1, grass, mud, true, air, mud) == grass, "grass back once the mud is gone")
		-- a rim where there was air, not yet settled: what the blast made it, even when done
		assert(Refill.material(0.3, air, mud, true, air, mud) == mud)
	end,
	["past the cap the oldest craters start filling now"] = function()
		assert(Refill.overCap(40, 40) == 0)
		assert(Refill.overCap(43, 40) == 3)
		assert(Refill.overCap(500, 0) == 0, "0: no cap")
		assert(Refill.startNow(10, R) == R.delay, "its wait cut short")
		assert(Refill.share(Refill.startNow(10, R), R) == 0, "nothing filled at once")
		assert(Refill.startNow(R.delay + 50, R) == R.delay + 50, "already filling: unchanged")
	end,
	["a blast's thrown earth partly fills an older crater under its rim"] = function()
		assert(not Refill.underRim(5, 10, 15), "inside the new bowl")
		assert(Refill.underRim(12, 10, 15))
		assert(not Refill.underRim(16, 10, 15), "past the rim")
		assert(math.abs(Refill.rimFilled(0.2, 1, 0.5) - 0.6) < 1e-9)
		assert(Refill.rimFilled(1, 0.5, 0.5) == 1, "never takes away")
	end,
}
