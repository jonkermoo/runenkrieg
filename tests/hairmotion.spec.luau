--!strict
local A = require("../src/shared/Config/Assets")
local Cfg = require("../src/shared/Config/HairMotion")
local H = require("../src/shared/Rules/HairMotion")

local STILL = { forward = 0, sideways = 0, up = 0, turn = 0, speed = 0 }

local function most(bone: any, n: number, m: any): (number, number)
	local b, r = 0, 0
	for i = 0, 400 do
		local x, y = H.target(bone, n, i * 0.05, m, 0.3, 1, false, Cfg)
		b, r = math.max(b, math.abs(x)), math.max(r, math.abs(y))
	end
	return b, r
end

return {
	["bone names: the back chain and the sides move, Root never"] = function()
		local b = H.bone("Back3")
		assert(b and b.kind == "back" and b.index == 3, "Back3")
		local r, l = H.bone("SideR"), H.bone("SideL")
		assert(r and r.kind == "side" and r.side == 1, "SideR on the right")
		assert(l and l.kind == "side" and l.side == -1, "SideL on the left")
		assert(H.bone("Root") == nil and H.bone("Hair") == nil and H.bone("Backpack") == nil, "nothing else moves")
	end,
	["standing still it only sways a little, side to side"] = function()
		local b, r = most(H.bone("Back1"), 1, STILL)
		assert(b < 1e-9, `standing: no swing back ({b})`)
		assert(r > 1 and r <= Cfg.Back.swayDeg + 1e-9, `standing: a slight sway ({r})`)
	end,
	["a chain shares its angles out, so a long ponytail bends no more in all than a short back"] = function()
		local run = { forward = 16, sideways = 0, up = 0, turn = 0, speed = 16 }
		local one = select(1, H.target(H.bone("Back1") :: any, 1, 0, run, 0, 1, false, Cfg))
		local all = 0
		for i = 1, 4 do
			all += select(1, H.target(H.bone(`Back{i}`) :: any, 4, 0, run, 0, 1, false, Cfg))
		end
		assert(math.abs(all - one) < 1e-9, `4 bones {all} vs 1 bone {one}`)
	end,
	["running it trails back, never forward, and never past its limits"] = function()
		local run = { forward = 16, sideways = 0, up = 0, turn = 0, speed = 16 }
		local fast = { forward = 200, sideways = 0, up = -200, turn = 0, speed = 200 }
		local b = select(1, most(H.bone("Back1"), 1, fast))
		assert(b <= Cfg.Back.liftMax + Cfg.Back.bobDeg + Cfg.Back.fallMax + 1e-9, `capped ({b})`)
		for i = 0, 100 do
			local x = H.target(H.bone("Back1") :: any, 1, i * 0.03, run, 0.1, 1, false, Cfg)
			assert(x > 0, "running: the hair trails behind")
		end
	end,
	["it swings against a sidestep and a turn"] = function()
		local right = { forward = 0, sideways = 10, up = 0, turn = 0, speed = 10 }
		local _, r = H.target(H.bone("Back1") :: any, 1, 0, right, 0, 1, false, Cfg)
		assert(r < 0, "stepping right, the hair swings left")
		local left = { forward = 0, sideways = 0, up = 0, turn = 3, speed = 0 }
		local _, r2 = H.target(H.bone("Back1") :: any, 1, 0, left, 0, 1, false, Cfg)
		assert(r2 < 0, "turning left, the back hair lags right of the turn")
	end,
	["falling, the side locks lift out to their own side"] = function()
		local fall = { forward = 0, sideways = 0, up = -30, turn = 0, speed = 0 }
		local _, r = H.target(H.bone("SideR") :: any, 1, 0.25 / Cfg.Side.swayHz, fall, 0, 1, false, Cfg)
		local _, l = H.target(H.bone("SideL") :: any, 1, 0.25 / Cfg.Side.swayHz, fall, 0, 1, false, Cfg)
		assert(r > l, `right lock out right ({r}), left lock out left ({l})`)
	end,
	["under a helmet it moves less, and dead it holds still"] = function()
		local run = { forward = 16, sideways = 5, up = 0, turn = 1, speed = 16 }
		local b1, r1 = H.target(H.bone("Back1") :: any, 1, 0.4, run, 0, 1, false, Cfg)
		local b2, r2 = H.target(H.bone("Back1") :: any, 1, 0.4, run, 0, Cfg.HelmetOn, false, Cfg)
		assert(math.abs(b2) < math.abs(b1) and math.abs(r2) < math.abs(r1), "helmet on: less")
		local b3, r3 = H.target(H.bone("Back1") :: any, 1, 0.4, run, 0, 1, true, Cfg)
		assert(b3 == 0 and r3 == 0, "dead: still")
	end,
	["the spring settles on its target, held within its limit, even over a long frame"] = function()
		local x, v = 0, 0
		for _ = 1, 240 do
			x, v = H.spring(x, v, 5, 1 / 60, Cfg.MaxDeg, Cfg.Spring)
		end
		assert(math.abs(x - 5) < 0.01 and math.abs(v) < 0.1, `settled at {x}`)
		local y, w = H.spring(0, 0, 1000, 2, Cfg.MaxDeg, Cfg.Spring)
		assert(y <= Cfg.MaxDeg and y == y and w == w, `a 2 s frame stays sane ({y}, {w})`)
	end,
	["every hair is placed somehow: rigged by its bones, the rest by their center"] = function()
		for name, e in A.Entries do
			if e.hair then
				local rigged = e.hair.bones ~= nil
				assert(rigged or (e.hair.center and #e.hair.center == 3), `{name}: needs bones or a center`)
				assert(not rigged or (e.hair.bones :: number) >= 1, `{name}: a rigged hair sways with 1 bone or more`)
			end
		end
	end,
	["the numbers are sane"] = function()
		assert(Cfg.Range > 0 and Cfg.PerFrame >= 1, "range and per-frame budget")
		assert(Cfg.HelmetOn >= 0 and Cfg.HelmetOn <= 1, "HelmetOn is a share")
		assert(Cfg.MaxDeg > 0 and Cfg.MaxDeg <= 30, "slight: at most 30 degrees a bone")
		assert(Cfg.Spring.damping > 0 and Cfg.Spring.stiffness > 0, "a damped spring")
	end,
}
