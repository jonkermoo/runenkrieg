--!strict
local L = require("../src/shared/Config/Locomotion")
local W = require("../src/shared/Config/Weapons")
local T = require("../src/shared/Rules/Tuck")

local C = L.Tuck

return {
	["the barrel's reach: grip ahead of the shoulder plus the muzzle's length"] = function()
		assert(T.reach(-2.483, 0.15, 1.5, 0.7) - (0.7 + 2.633 * 1.5) < 1e-9)
		assert(T.reach(1, 0, 1, 0.7) == 0.7, "a muzzle behind the grip adds nothing")
		local w = W.rifle_m91 :: any
		local r = T.reach(w.attachments.Muzzle[3], w.grip[3], w.scale[3], C.GripAhead)
		assert(r > 3 and r < 5.5, "a rifle reaches about its length ahead")
	end,
	["something within the reach folds the gun, and it stays folded until clear"] = function()
		assert(not T.blocked(nil, 4, C.Ahead, C.Clear, false))
		assert(not T.blocked(nil, 4, C.Ahead, C.Clear, true), "nothing in the way: out")
		assert(T.blocked(3, 4, C.Ahead, C.Clear, false))
		assert(T.blocked(4 + C.Ahead - 0.01, 4, C.Ahead, C.Clear, false), "about to hit")
		assert(not T.blocked(4 + C.Ahead + 0.01, 4, C.Ahead, C.Clear, false))
		assert(T.blocked(4 + C.Ahead + C.Clear * 0.5, 4, C.Ahead, C.Clear, true), "folded: stays until clear")
		assert(not T.blocked(4 + C.Ahead + C.Clear + 0.01, 4, C.Ahead, C.Clear, true))
	end,
	["trench dirt folds the gun only head on and at the barrel's reach"] = function()
		local f = C.TrenchFacing
		assert(not T.trenchBlocked(nil, 1, 4, f, C.Clear, false))
		assert(T.trenchBlocked(3, 0.95, 4, f, C.Clear, false), "straight into a wall at point blank")
		assert(not T.trenchBlocked(3, 0.3, 4, f, C.Clear, false), "a sloped wall glanced along the trench")
		assert(not T.trenchBlocked(2, -0.5, 4, f, C.Clear, false), "the floor or the parapet, aiming out")
		assert(not T.trenchBlocked(4 + 0.1, 0.95, 4, f, C.Clear, false), "no about-to-hit margin in a trench")
		assert(T.trenchBlocked(4 + C.Clear * 0.5, 0.95, 4, f, C.Clear, true), "folded: stays until clear")
		assert(f > 0.5 and f < 1)
	end,
	["tuck settings are sane"] = function()
		assert(C.Radius > 0 and C.Radius < 1)
		assert(C.Ahead >= 0 and C.Ahead < 2 and C.Clear > 0 and C.Clear < 2)
		assert(#C.Shoulder == 3 and C.GripAhead > 0)
	end,
}
