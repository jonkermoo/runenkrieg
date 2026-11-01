--!strict
local C = require("../src/shared/Config/Ragdoll")
local R = require("../src/shared/Rules/Ragdoll")

local B = C.ByDamage

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["a body settles at maxDown, or once still after minDown; a dragged one counts as still"] = function()
		assert(not R.settled(0, 0, false, C), "not before minDown")
		assert(not R.settled(C.minDown, C.still + 1, false, C), "still moving")
		assert(R.settled(C.minDown, C.still - 0.1, false, C), "still")
		assert(R.settled(C.minDown, C.still + 10, true, C), "dragged: the pull's speed")
		assert(not R.settled(0, 0, true, C), "dragged, before minDown")
		assert(R.settled(C.maxDown, C.still + 10, false, C), "maxDown")
	end,
	["a dragged soldier breaks free only once the knock's stand-up time has passed"] = function()
		assert(not R.served(nil, 2, 100), "not settled yet")
		assert(not R.served(10, 2, 11.9), "the get-up wait not over")
		assert(R.served(10, 2, 12), "over")
		assert(R.served(10, 0, 10), "no wait")
	end,
	["a knock that does no damage keeps its own get-up time"] = function()
		assert(R.getUp(C.Knocks.StaffRecoil.getUp, nil, B) == C.Knocks.StaffRecoil.getUp, "the staff's recoil")
		assert(R.getUp(C.Knocks.FloatFall.getUp, 0, B) == C.Knocks.FloatFall.getUp, "the float fall")
		assert(R.getUp(C.Knocks.BlastThrow.getUp, 0, B) == C.Knocks.BlastThrow.getUp, "your own blast's throw")
	end,
	["more damage keeps you down longer, from the floor up to the ceiling"] = function()
		assert(near(R.getUp(0, 1e-6, B), B.floor), "the slightest hurt: the floor")
		assert(near(R.getUp(0, B.full / 2, B), (B.floor + B.ceiling) / 2))
		assert(near(R.getUp(0, B.full, B), B.ceiling))
		assert(near(R.getUp(0, B.full * 3, B), B.ceiling), "never past the ceiling")
		local last = 0
		for d = 1, 120 do
			local t = R.getUp(0, d, B)
			assert(t >= last, "never shorter for more damage")
			last = t
		end
	end,
	["never shorter than the knock's own get-up time"] = function()
		assert(R.getUp(1, 1, B) == 1, "a light blast still waits the blast's own time")
		assert(R.getUp(1, B.full, B) == B.ceiling, "a heavy one: the ceiling")
	end,
	["a light hit gets up quickly, a heavy one stays down"] = function()
		local light = R.getUp(C.Knocks.Limb.getUp, 12, B) -- a shotgun pellet
		local heavy = R.getUp(C.Knocks.Torso.getUp, 70, B) -- a bolt rifle in the torso
		assert(light < 1 and heavy > 1.8, "light " .. light .. " heavy " .. heavy)
	end,
	["a knocked-down soldier breathes while alive, a dead body is still"] = function()
		assert(R.animates(100) and R.animates(1), "alive")
		assert(not R.animates(0) and not R.animates(-5), "dead")
	end,
	["holding the stay-down key keeps you down past the wait, letting go gets you up"] = function()
		local S = C.StayDown
		assert(not R.rises(nil, false, 100, S), "the wait not over")
		assert(not R.rises(10, false, 9.9, S), "not yet")
		assert(R.rises(10, false, 10, S), "not held: up at the usual time")
		assert(not R.rises(10, true, 10, S), "held: stays down")
		assert(not R.rises(10, true, 10 + S.max - 0.1, S), "still held")
		assert(R.rises(10, false, 25, S), "let go: up")
		assert(R.rises(10, true, 10 + S.max, S), "held too long: up anyway")
	end,
	["stay-down settings are sane"] = function()
		local S = C.StayDown
		assert(S.key == "Space" and S.max > 5 and S.rate >= 2, "key, cap, rate")
	end,
	["by-damage settings are sane"] = function()
		assert(B.floor > 0 and B.ceiling > B.floor and B.ceiling < C.maxDown + 2, "floor and ceiling")
		assert(B.full > 0 and B.full <= 100, "full damage")
	end,
}
