--!strict
local C = require("../src/shared/Config/Concussion")
local R = require("../src/shared/Rules/Concussion")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["a helmet knocked off concusses harder the nearer the hit came to killing"] = function()
		assert(near(R.helmet(100, 100, C.Helmet), C.Helmet.least), "full health: least")
		assert(near(R.helmet(0, 100, C.Helmet), C.Helmet.most), "left at nothing: most")
		assert(R.helmet(30, 100, C.Helmet) > R.helmet(70, 100, C.Helmet), "nearer a kill, harder")
	end,
	["a blast concusses by how hard it threw, from least to 1"] = function()
		assert(near(R.blast(0, C.Blast), C.Blast.least), "the faintest throw")
		assert(near(R.blast(1, C.Blast), 1), "the hardest")
		assert(near(R.blast(5, C.Blast), 1), "clamped")
	end,
	["the shape runs from Light at Light.at to Heavy at 1"] = function()
		local light = R.shape(C.Light.at, C)
		local heavy = R.shape(1, C)
		for k, v in C.Heavy do
			assert(near(heavy[k], v), `heavy {k}`)
			assert(near(light[k], C.Light[k]), `light {k}`)
		end
		local mid = R.shape((C.Light.at + 1) / 2, C)
		assert(mid.duration > light.duration and mid.duration < heavy.duration, "in between")
	end,
	["weaker than Light.at, everything shrinks towards no effect"] = function()
		local none = R.shape(0, C)
		assert(none.duration == 0 and none.blur == 0 and none.ring == 0 and none.getUp == 0, "nothing")
		assert(none.duck == 1 and none.reaction == 1 and none.aim == 1, "multipliers at 1")
		assert(R.shape(C.Light.at / 2, C).blur < C.Light.blur, "half way")
	end,
	["a helmet hit and a heavy blast give the picked feel"] = function()
		local helmet = R.shape(R.helmet(100, 100, C.Helmet), C)
		assert(near(helmet.duration, C.Light.duration), "helmet off at full health: the light end")
		local blast = R.shape(R.blast(1, C.Blast), C)
		assert(near(blast.duration, C.Heavy.duration) and near(blast.getUp, C.Heavy.getUp), "the heavy end")
	end,
	["it fades out over the duration"] = function()
		assert(near(R.fade(0, 8, C.Fade), 1), "full at the start")
		assert(R.fade(4, 8, C.Fade) < 0.5, "most of it gone by half way")
		assert(R.fade(8, 8, C.Fade) == 0 and R.fade(20, 8, C.Fade) == 0, "gone at the end")
		assert(R.fade(0, 0, C.Fade) == 0, "no duration")
	end,
	["a new concussion replaces the old one only when it is at least as strong as what is left"] = function()
		local s = R.add(nil, 0.5, 0, C)
		assert(s and s.strength == 0.5, "the first")
		assert(R.add(s, 0.3, 0.1, C) == nil, "weaker than what is left: kept")
		local later = R.add(s, 0.3, 100, C)
		assert(later and later.at == 100, "the old one over: the new one")
		assert(R.add(s, 0, 0, C) == nil, "nothing")
	end,
	["the other sounds duck, then come back"] = function()
		assert(R.duck(0, 0.3, 2, 1.5) == 0.3, "ducked")
		assert(near(R.duck(2.75, 0.3, 2, 1.5), 0.65), "half way back")
		assert(R.duck(10, 0.3, 2, 1.5) == 1, "back")
	end,
	["a concussion adds to the get-up wait, less as it fades"] = function()
		assert(R.getUp(nil, 0, C) == 0, "none")
		local s = { at = 0, strength = 1 }
		assert(near(R.getUp(s, 0, C), C.Heavy.getUp), "at the start")
		assert(R.getUp(s, 3, C) < C.Heavy.getUp, "less later")
		assert(R.getUp(s, C.Heavy.duration, C) == 0, "gone")
	end,
	["a concussed bot reacts later and aims worse, back to normal when it fades"] = function()
		local d = { reaction = 0.5, aimError = 2, aimFloor = 0.4, settle = 1 }
		assert(R.daze(d, nil, 0, C) == d, "not concussed: the same table")
		local s = { at = 0, strength = 1 }
		local dz = R.daze(d, s, 0, C)
		assert(near(dz.reaction, 0.5 * C.Heavy.reaction), "reaction at peak")
		assert(near(dz.aimError, 2 * C.Heavy.aim) and near(dz.aimFloor, 0.4 * C.Heavy.aim), "aim at peak")
		assert(dz.settle == 1 and d.reaction == 0.5, "the rest kept, the original untouched")
		assert(R.daze(d, s, C.Heavy.duration, C) == d, "over")
	end,
}
