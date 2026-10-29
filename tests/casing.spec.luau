--!strict
local A = require("../src/shared/Config/Audio")
local F = require("../src/shared/Config/Firing")
local R = require("../src/shared/Rules/Casing")
local W = require("../src/shared/Config/Weapons")

local C = F.Cases

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
	["the ground decides: dirt dull, stone rings, water silent"] = function()
		assert(R.surface("Grass", C) == "Soft" and R.surface("Mud", C) == "Soft")
		assert(R.surface("WoodPlanks", C) == "Wood" and R.surface("Metal", C) == "Metal")
		assert(R.surface("Cobblestone", C) == C.default and C.default == "Hard")
		local case = W.rifle_g98.casing :: any
		local soft, _, softEq = R.sound(case, "Soft", C)
		local hard, pitch, hardEq = R.sound(case, "Hard", C)
		assert(soft < hard and softEq[3] < hardEq[3], "dirt is quieter and duller")
		assert(pitch == case.pitch, "the case's own pitch")
		assert(R.sound(case, "Water", C) == 0, "nothing in water")
		for name, s in C.surfaces do
			assert(s.volume >= 0 and #s.eq == 3, name)
		end
		for m, s in C.materials do
			assert(C.surfaces[s], `{m}: {s}`)
		end
	end,
	["a rolling case is no landing"] = function()
		assert(not R.lands(C.still * 0.5, C) and R.lands(C.still * 4, C))
	end,
	["cases lie about a while, and not without end"] = function()
		local c = F.Effects.Casing
		assert(c.rest > c.life and c.settle > c.flight and c.settle < c.rest, "lands, settles, then goes")
		assert(c.max >= 10 and c.max <= 200)
		assert(A.Profiles.Casing.ref <= 3 and A.Profiles.Casing.max <= 60, "a small clink, close by only")
	end,
	["each landing sound plays its single clink"] = function()
		assert(#C.sounds >= 2, "variants")
		for _, s in C.sounds do
			assert(s.stop > s.start and s.fade < s.stop - s.start)
		end
	end,
}
