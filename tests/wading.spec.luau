--!strict
local L = require("../src/shared/Config/Locomotion")
local M = require("../src/shared/Config/Metrics")
local R = require("../src/shared/Rules/Wading")

local C = L.Wading

return {
	["the surface runs up from the water at the feet and ends at the last voxel's occupancy"] = function()
		-- voxels at 0, 4, 8, 12: ground, water, water (half full), air
		local water, occ = { false, true, true, false }, { 1, 1, 0.5, 0 }
		assert(R.surface(water, occ, 0, 4, 3.5) == 10, "feet in the bed's voxel: the water above counts")
		assert(R.surface(water, occ, 0, 4, 5) == 10, "feet in the water")
		assert(R.surface(water, occ, 0, 4, 13) == nil, "above the water: dry")
		assert(R.surface({ false, false, true }, { 1, 1, 1 }, 0, 4, 1) == nil, "water two voxels up is not wading")
		assert(R.surface({}, {}, 0, 4, 1) == nil)
		assert(R.surface({ true }, { 2 }, 0, 4, 1) == 4, "occupancy clamped")
	end,
	["depth is the surface over the feet, never negative"] = function()
		assert(R.depth(10, 7) == 3)
		assert(R.depth(10, 12) == 0)
		assert(R.depth(nil, 0) == 0)
	end,
	["shallow water keeps full speed, hip-deep slows, chest-deep is the slowest"] = function()
		assert(R.scale(0, C.From, C.Full, C.Slow) == 1)
		assert(R.scale(C.From, C.From, C.Full, C.Slow) == 1, "at the hip: not yet")
		local mid = R.scale((C.From + C.Full) / 2, C.From, C.Full, C.Slow)
		assert(math.abs(mid - (1 + C.Slow) / 2) < 1e-9, "halfway down at halfway (smoothstep)")
		assert(R.scale(C.Full, C.From, C.Full, C.Slow) == C.Slow)
		assert(R.scale(50, C.From, C.Full, C.Slow) == C.Slow, "deeper stays at the slow")
		local last = 1
		for d = 0, 5, 0.1 do
			local s = R.scale(d, C.From, C.Full, C.Slow)
			assert(s <= last + 1e-12, "never faster deeper")
			last = s
		end
		assert(R.scale(3, 2, 2, 0.5) == 0.5, "no ramp: straight to the slow")
	end,
	["the slow eases toward its target without passing it"] = function()
		local x = 1
		for _ = 1, 10 do
			x = R.ease(x, C.Slow, C.Rate, 1 / 60)
			assert(x > C.Slow and x < 1)
		end
		assert(math.abs(R.ease(1, C.Slow, C.Rate, 10) - C.Slow) < 1e-6, "settles")
		assert(R.ease(0.7, 0.7, C.Rate, 1) == 0.7)
		assert(R.ease(0.8, 1, C.Rate, -1) == 0.8, "a negative step does nothing")
	end,
	["submerged share of a part"] = function()
		assert(R.submerged(4, 1, 2, 10) == 4, "all under")
		assert(R.submerged(4, 1, 2, 0) == 0, "all above")
		assert(R.submerged(4, 1, 2, 1) == 2, "half")
		assert(R.submerged(1, 1, 0, 2) == 1 and R.submerged(1, 1, 0, 0) == 0, "flat part")
	end,
	["wading settings are sane"] = function()
		assert(math.abs(C.From - M.Character.LegLength) < 0.5, "starts at the hip")
		assert(C.Full > C.From and C.Full < M.Character.Height)
		assert(C.Slow > 0.3 and C.Slow < 1)
		assert(C.Rate > 0 and C.Sink >= 1 and C.Sink < 1.5)
		assert(
			M.Movement.WalkSpeed * C.Slow >= M.Movement.WalkSpeed * L.PlaybackMin - 1e-9,
			"the walk cycle can keep up"
		)
	end,
}
