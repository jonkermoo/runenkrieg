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
	["a near blast concusses by its overpressure, on a log scale up to most"] = function()
		local N = C.Near
		assert(R.near(N.from, N) == 0 and R.near(1, N) == 0, "under from: nothing")
		assert(near(R.near(N.full, N), N.most) and near(R.near(N.full * 10, N), N.most), "from full: most")
		local mid = R.near(math.sqrt(N.from * N.full), N)
		assert(near(mid, N.most / 2), "half way on the log scale")
	end,
	["the shape runs from Light at Light.at to Heavy at 1, per kind"] = function()
		for kind, K in C.Kinds do
			local light = R.shape(K.Light.at, kind, C)
			local heavy = R.shape(1, kind, C)
			for k, v in K.Heavy do
				assert(near(heavy[k], v), `{kind} heavy {k}`)
				assert(near(light[k], K.Light[k]), `{kind} light {k}`)
			end
			local mid = R.shape((K.Light.at + 1) / 2, kind, C)
			assert(mid.duration > light.duration and mid.duration < heavy.duration, `{kind} in between`)
		end
	end,
	["weaker than Light.at, everything shrinks towards no effect"] = function()
		local none = R.shape(0, "Blast", C)
		assert(none.duration == 0 and none.blur == 0 and none.ring == 0 and none.getUp == 0, "nothing")
		assert(none.muffle == 0 and none.ringFor == 0 and none.hold == 0, "nothing heard")
		assert(none.duck == 1 and none.reaction == 1 and none.aim == 1 and none.pitch == 1, "multipliers at 1")
		local L = C.Kinds.Blast.Light
		assert(R.shape(L.at / 2, "Blast", C).ring < L.ring, "half way")
	end,
	["a helmet hit is longer and harsher than a near miss, and keeps you down longer"] = function()
		local helmet = R.shape(R.helmet(100, 100, C.Helmet), "Helmet", C)
		local nearMiss = R.shape(R.near(40, C.Near), "Blast", C)
		assert(helmet.duration > nearMiss.duration and helmet.ringFor > nearMiss.ringFor, "longer")
		assert(helmet.blur > nearMiss.blur and helmet.snap > 0 and helmet.pitch > 1, "harsher, higher")
		assert(helmet.getUp >= C.Kinds.Helmet.Light.getUp, "down longer")
		local nearKill = R.shape(R.helmet(1, 100, C.Helmet), "Helmet", C)
		assert(nearKill.getUp > helmet.getUp and nearKill.duration > helmet.duration, "a near kill: worse")
	end,
	["it fades out over the duration, after the hold"] = function()
		assert(near(R.fade(0, 8, C.Fade), 1), "full at the start")
		assert(R.fade(4, 8, C.Fade) < 0.5, "most of it gone by half way")
		assert(R.fade(8, 8, C.Fade) == 0 and R.fade(20, 8, C.Fade) == 0, "gone at the end")
		assert(R.fade(0, 0, C.Fade) == 0, "no duration")
		assert(R.held(1.5, 2, 8, C.Fade) == 1, "held")
		assert(near(R.held(2, 2, 8, C.Fade), 1) and R.held(5, 2, 8, C.Fade) < 1, "then fading")
		assert(R.held(8, 2, 8, C.Fade) == 0 and R.held(0, 0, 0, C.Fade) == 0, "gone")
	end,
	["the muffle comes in after the bang, holds, then clears"] = function()
		local s = R.shape(1, "Blast", C)
		local A = C.Muffle.attack
		assert(R.muffle(0, s, A) == 0, "the bang heard first")
		assert(near(R.muffle(A, s, A), s.muffle), "in")
		assert(near(R.muffle(s.muffleFor - 0.01, s, A), s.muffle), "held")
		local half = R.muffle(s.muffleFor + s.muffleBack / 2, s, A)
		assert(half > 0 and half < s.muffle, "clearing")
		assert(R.muffle(s.muffleFor + s.muffleBack, s, A) == 0, "clear")
	end,
	["a kick dies away to nothing"] = function()
		assert(R.kick(0, 0.4) == 1 and R.kick(0.4, 0.4) == 0 and R.kick(0.2, 0.4) < 0.5, "squared")
	end,
	["a new concussion replaces the old one only when it is at least as strong as what is left"] = function()
		local s = R.add(nil, 0.5, "Blast", 0, C)
		assert(s and s.strength == 0.5 and s.kind == "Blast", "the first")
		assert(R.add(s, 0.3, "Helmet", 0.1, C) == nil, "weaker than what is left: kept")
		local later = R.add(s, 0.3, "Helmet", 100, C)
		assert(later and later.at == 100 and later.kind == "Helmet", "the old one over: the new one")
		local again = R.add(s, 0.5, "Blast", 0.2, C)
		assert(again and again.strength == 0.5 and again.at == 0.2, "a second blast restarts it, never adds up")
		assert(R.add(s, 0, "Blast", 0, C) == nil, "nothing")
	end,
	["a concussion adds to the get-up wait, less as it fades"] = function()
		assert(R.getUp(nil, 0, C) == 0, "none")
		local H = C.Kinds.Helmet.Heavy
		local s = { at = 0, strength = 1, kind = "Helmet" :: "Helmet" }
		assert(near(R.getUp(s, 0, C), H.getUp), "at the start")
		assert(R.getUp(s, H.hold + 3, C) < H.getUp, "less later")
		assert(R.getUp(s, H.duration, C) == 0, "gone")
	end,
	["a concussed bot reacts later and aims worse, back to normal when it fades"] = function()
		local H = C.Kinds.Blast.Heavy
		local d = { reaction = 0.5, aimError = 2, aimFloor = 0.4, settle = 1 }
		assert(R.daze(d, nil, 0, C) == d, "not concussed: the same table")
		local s = { at = 0, strength = 1, kind = "Blast" :: "Blast" }
		local dz = R.daze(d, s, 0, C)
		assert(near(dz.reaction, 0.5 * H.reaction), "reaction at peak")
		assert(near(dz.aimError, 2 * H.aim) and near(dz.aimFloor, 0.4 * H.aim), "aim at peak")
		assert(dz.settle == 1 and d.reaction == 0.5, "the rest kept, the original untouched")
		assert(R.daze(d, s, H.duration, C) == d, "over")
	end,
}
