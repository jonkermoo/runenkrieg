--!strict
local Cfg = require("../src/shared/Config/Flagpole")
local R = require("../src/shared/Rules/Flagpole")

local function near(a: number, b: number, e: number?): boolean
	return math.abs(a - b) < (e or 1e-9)
end

return {
	["flag: the side the control leans to, as high as it goes; a bare pole at neutral"] = function()
		local side, share = R.flag(1)
		assert(side == "West" and share == 1)
		side, share = R.flag(-0.4)
		assert(side == "East" and near(share, 0.4))
		side, share = R.flag(0)
		assert(side == nil and share == 0)
		side, share = R.flag(-3)
		assert(side == "East" and share == 1, "clamped")
	end,
	["top: from just over the ground to just under the pole's top"] = function()
		local F = Cfg.Flag
		local h = F.size[2]
		assert(near(R.top(0, 20, h, F), F.bottomGap + h))
		assert(near(R.top(1, 20, h, F), 20 - F.topGap))
		assert(R.top(0.5, 20, h, F) > R.top(0.2, 20, h, F), "rises with control")
		assert(R.top(1, 20, h, F) - h > F.bottomGap, "the flag never reaches the ground")
	end,
	["ring: evenly spread, about `spacing` apart, never fewer than three"] = function()
		local a = R.ring(45, Cfg.Stakes.spacing)
		local arc = 2 * math.pi * 45 / #a
		assert(math.abs(arc - Cfg.Stakes.spacing) < Cfg.Stakes.spacing * 0.15, `{arc}`)
		assert(a[1] == 0 and near(a[2] - a[1], 2 * math.pi / #a))
		assert(#R.ring(1, 8) == 3)
	end,
	["wind: GlobalWind's strength and direction, the default when calm"] = function()
		local F = Cfg.Flap
		local s, dx, dz = R.wind(F.WindReference, 0, F)
		assert(near(s, 1) and near(dx, 1) and near(dz, 0))
		s, dx, dz = R.wind(0, 0, F)
		assert(s > 0 and near(dx * dx + dz * dz, 1))
		assert(R.wind(1000, 0, F) == 1.5, "capped")
	end,
	["flap: bigger toward the free edge, harder in wind and while contested"] = function()
		local F = Cfg.Flap
		local function peak(i: number, strength: number, contested: boolean): number
			local m = 0
			for k = 0, 400 do
				m = math.max(m, math.abs(R.flap(i, 4, k * 0.01, strength, contested, F)))
			end
			return m
		end
		assert(peak(4, 1, false) > peak(1, 1, false))
		assert(peak(4, 1, false) > peak(4, 0.2, false))
		assert(peak(4, 1, true) > peak(4, 1, false))
		assert(peak(4, 1, false) <= F.amplitude + 1e-6)
	end,
	["droop: hangs in calm air, flies straight out in a full wind"] = function()
		local F = Cfg.Flap
		assert(near(R.droop(0, F), 90 * F.droop))
		assert(R.droop(1, F) == 0 and R.droop(1.5, F) == 0)
	end,
	["toSegment: the shortest way to a line between two points"] = function()
		assert(near(R.toSegment(0, 0, 0, 10, 0, 0, 5, 3, 0), 3))
		assert(near(R.toSegment(0, 0, 0, 10, 0, 0, -4, 3, 0), 5), "past the start: to the start")
		assert(near(R.toSegment(1, 1, 1, 1, 1, 1, 1, 1, 2), 1), "a point segment")
	end,
	["whip and step: nearby blasts whip harder, far flags move less often"] = function()
		local W = Cfg.Whip
		assert(R.whip(1, W.radius, W) == 0)
		assert(R.whip(1, 5, W) > R.whip(1, 20, W))
		assert(R.whip(100, 0, W) == W.maxDegrees)
		local L = Cfg.Lod
		assert(R.step(10, L) == 0 and R.step(L.far, L) == L.farStep and R.step(L.far + 1, L) == nil)
	end,
	["ease: moves toward the target, never past it"] = function()
		local v = R.ease(0, 1, 3, 0.1)
		assert(v > 0 and v < 1)
		assert(near(R.ease(0.5, 0.5, 3, 1), 0.5))
		assert(R.ease(0, 1, 3, 100) <= 1)
	end,
}
