--!strict
local C = require("../src/shared/Config/Cinematic")
local R = require("../src/shared/Rules/Cinematic")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["daylight is 1 by day, 0 by night and smooth between"] = function()
		assert(R.daylight(1, 0.15, -0.05) == 1)
		assert(R.daylight(0.15, 0.15, -0.05) == 1)
		assert(R.daylight(-0.05, 0.15, -0.05) == 0)
		assert(R.daylight(-1, 0.15, -0.05) == 0)
		assert(near(R.daylight(0.05, 0.15, -0.05), 0.5))
		assert(R.daylight(0.1, 0.15, -0.05) > R.daylight(0, 0.15, -0.05))
	end,
	["daylight with no band between is a step"] = function()
		assert(R.daylight(0.2, 0.1, 0.1) == 1)
		assert(R.daylight(0, 0.1, 0.1) == 0)
	end,
	["the grade blends night to day"] = function()
		local day = { tint = { 255, 240, 220 }, brightness = 0.1, contrast = 0.2, saturation = 0.1 }
		local night = { tint = { 200, 220, 255 }, brightness = 0, contrast = 0, saturation = -0.3 }
		local g0, g1, gh = R.grade(day, night, 0), R.grade(day, night, 1), R.grade(day, night, 0.5)
		assert(g0.tint[1] == 200 and g0.saturation == -0.3)
		assert(g1.tint[3] == 220 and g1.contrast == 0.2)
		assert(near(gh.tint[1], 227.5) and near(gh.saturation, -0.1))
	end,
	["the focus eases toward the target and never overshoots"] = function()
		assert(R.focus(10, 100, 6, 0) == 10)
		assert(R.focus(10, 10, 6, 1) == 10)
		local f = R.focus(10, 100, 6, 1 / 30)
		assert(f > 10 and f < 100)
		assert(R.focus(10, 100, 6, 100) <= 100)
		assert(R.focus(100, 10, 6, -1) == 100)
	end,
	["the in-focus radius is a share of the focus, with a floor and a cap"] = function()
		assert(R.radius(80, 0.5, 30, 50) == 40)
		assert(R.radius(10, 0.5, 30, 50) == 30)
		assert(R.radius(0, 0.5, 30, 50) == 30)
		assert(R.radius(200, 0.5, 30, 50) == 50)
	end,
	["every look is complete and sane"] = function()
		assert(C.Looks[C.Look] ~= nil, "Look names a look")
		for name, look in C.Looks do
			for _, g in { look.day, look.night } do
				assert(#g.tint == 3, name)
				for _, v in g.tint do
					assert(v >= 0 and v <= 255, name)
				end
				assert(math.abs(g.brightness) <= 0.2 and math.abs(g.contrast) <= 0.5, name)
				assert(g.saturation >= -1 and g.saturation <= 1, name)
			end
			assert(look.dof.far >= 0 and look.dof.far <= 1 and look.dof.minRadius > 0, name)
			assert(look.vignette.size > 0 and look.vignette.size < 0.5, name)
			assert(look.vignette.transparency >= 0 and look.vignette.transparency <= 1, name)
		end
		assert(C.DayAbove > C.NightBelow)
		assert(C.AimFarShare >= 0 and C.AimFarShare <= 1)
	end,
}
