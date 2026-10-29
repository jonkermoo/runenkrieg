--!strict
local A = require("../src/shared/Config/Audio")
local C = require("../src/shared/Config/Cases")
local R = require("../src/shared/Rules/Casing")
local W = require("../src/shared/Config/Weapons")

return {
	["every gun's case has its own clink"] = function()
		for name, w in W do
			if w.ammo then
				local c = w.casing
				assert(c, `{name}: no casing`)
				assert(c.pitch >= 0.4 and c.pitch <= 1.6 and c.volume > 0 and c.volume <= 1.5, name)
				assert(#c.eq == 3, `{name}: low, mid, high`)
			end
		end
	end,
	["a long rifle case rings lower than a pistol's, a paper shotgun hull lowest"] = function()
		assert(W.rifle_g98.casing.pitch < W.rifle_winchester1907.casing.pitch, "57 mm under 35 mm")
		assert(W.rifle_winchester1907.casing.pitch < W.pistol_c96.casing.pitch, "rifle under pistol")
		assert(W.shotgun_m1897.casing.pitch < W.rifle_g98.casing.pitch, "the hull lowest")
	end,
	["the ground decides: dirt dull, stone rings"] = function()
		assert(R.surface("Grass", C) == "Soft" and R.surface("Mud", C) == "Soft")
		assert(R.surface("WoodPlanks", C) == "Wood" and R.surface("Metal", C) == "Metal")
		assert(R.surface("Cobblestone", C) == C.default and C.default == "Hard")
		local case = W.rifle_g98.casing :: any
		local soft, _, softEq = R.sound(case, "Soft", C)
		local hard, pitch, hardEq = R.sound(case, "Hard", C)
		assert(soft < hard and softEq[3] < hardEq[3], "dirt is quieter and duller")
		assert(pitch == case.pitch, "the case's own pitch")
		for name, s in C.surfaces do
			assert(s.volume > 0 and #s.eq == 3, name)
		end
		for m, s in C.materials do
			assert(C.surfaces[s], `{m}: {s}`)
		end
	end,
	["an MG case or link takes the ground's sound at its own pitch"] = function()
		local v, pitch, eq = R.sound(nil, "Hard", C)
		assert(v == 1 and pitch == 1 and eq[1] == 0 and eq[3] == 0)
		local soft = R.sound(nil, "Soft", C)
		assert(soft < v)
	end,
	["a gun's cases lie about a while, the MG's go soon, and not without end"] = function()
		assert(C.rest > C.life and C.rest >= 10, "a gun's case lies longer")
		assert(C.max >= 10 and C.max <= 200)
		assert(R.excess(C.max, C.max) == 0 and R.excess(C.max + 1, C.max) == 1 and R.excess(3, C.max) == 0)
		assert(A.Profiles.Casing.ref <= 3 and A.Profiles.Casing.max <= 60, "a small clink, close by only")
	end,
	["each cartridge clink plays its single hit"] = function()
		local s = C.Sounds.Cartridge
		assert(s.roll and s.roll > 0 and s.rollSlow > 0, "a round case rolls on a little, then stops")
		assert(#s.variants >= 2, "variants")
		for _, e in s.variants do
			assert(e.stop > e.start and e.fade < e.stop - e.start)
			assert(A.Profiles[e.profile], e.profile)
		end
	end,
}
