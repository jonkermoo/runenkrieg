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
	["the gun pulls back from just before it touches, up to all the way"] = function()
		assert(T.pull(nil, 4, 0.6, 2) == 0, "nothing in the way")
		assert(T.pull(4.6, 4, 0.6, 2) == 0, "not yet")
		assert(math.abs(T.pull(3.6, 4, 0.6, 2) - 0.5) < 1e-9, "half way")
		assert(T.pull(1, 4, 0.6, 2) == 1, "never past all the way")
		assert(T.pull(3, 4, 0.6, 0) == 0, "no give: no pull")
	end,
	["it folds only head on, and only when even pulled back it would hit"] = function()
		local f = function(hit: number?, facing: number, was: boolean)
			return T.folds(hit, facing, 4, C.Ahead, C.Give, C.Clear, C.Facing, C.FacingClear, was)
		end
		assert(not f(nil, 1, false))
		assert(not f(4 - C.Give + C.Ahead + 0.01, 1, false), "pulled back it fits")
		assert(f(4 - C.Give + C.Ahead - 0.01, 1, false), "even pulled back it hits")
		assert(not f(1, C.Facing - 0.01, false), "a wall glanced along doesn't fold it")
		assert(f(1, C.Facing - C.FacingClear * 0.5, true), "folded: stays while still nearly head on")
		assert(not f(1, C.Facing - C.FacingClear - 0.01, true))
		assert(f(4 - C.Give + C.Ahead + C.Clear * 0.5, 1, true), "folded: stays until clear")
	end,
	["a pull received is clamped and quantized"] = function()
		assert(
			T.sanitizePull("1", 0.1) == nil and T.sanitizePull(0 / 0, 0.1) == nil and T.sanitizePull(nil, 0.1) == nil
		)
		assert(T.sanitizePull(5, 0.1) == 1 and T.sanitizePull(-3, 0.1) == 0)
		assert(math.abs((T.sanitizePull(0.44, 0.1) :: number) - 0.4) < 1e-9)
	end,
	["tuck settings are sane"] = function()
		assert(C.Radius > 0 and C.Radius < 1)
		assert(C.Ahead >= 0 and C.Ahead < 2 and C.Clear > 0 and C.Clear < 2)
		assert(#C.Shoulder == 3 and C.GripAhead > 0)
		assert(C.Give > 0 and C.Facing > 0 and C.Facing <= 1 and C.FacingClear >= 0 and C.Ease > 0)
		assert(C.Body >= 0 and C.First >= 0 and C.FirstAim >= 0 and C.FirstAim <= C.First)
		assert(C.Send.Rate > 0 and C.Send.Step > 0 and C.Send.Step <= 1)
	end,
}
