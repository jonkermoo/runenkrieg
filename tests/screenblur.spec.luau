--!strict
local A = require("../src/shared/Config/Audio")
local Cfg = require("../src/shared/Config/ScreenBlur")
local R = require("../src/shared/Rules/ScreenBlur")

local radius = A.Heard.pass.radius
local P, B = Cfg.Pass, Cfg.Blast

local function fireball(kg: number): number -- Config/Vfx.Blast.Charge
	return 3.86 * kg ^ 0.32 / 0.357
end

return {
	["a passing bullet blurs most on its path, less farther off, not at all past the radius"] = function()
		assert(math.abs(R.pass(0, radius, P.peak, P.curve) - P.peak) < 1e-9)
		local last = math.huge
		for off = 0, radius, 1 do
			local s = R.pass(off, radius, P.peak, P.curve)
			assert(s <= last and s >= 0, `falls off at {off}`)
			last = s
		end
		assert(R.pass(radius, radius, P.peak, P.curve) == 0 and R.pass(radius * 3, radius, P.peak, P.curve) == 0)
	end,
	["a blast blurs less with distance and more with size, nothing out of reach"] = function()
		local grenade, shell, bomb = fireball(0.071), fireball(2.5), fireball(50)
		assert(R.blast(5, grenade, B) > R.blast(20, grenade, B), "closer is stronger")
		assert(R.blast(20, shell, B) > R.blast(20, grenade, B), "bigger is stronger")
		assert(R.blast(20, bomb, B) >= R.blast(20, shell, B))
		assert(R.blast(B.reach * grenade, grenade, B) == 0, "nothing at the grenade's reach")
		assert(R.blast(B.maxReach + 1, bomb, B) == 0, "the biggest blast stops at maxReach")
		assert(R.blast(0, bomb, B) <= 1 and R.blast(0, grenade, B) >= B.least, "a grenade at your feet still blurs")
	end,
	["hits build up but never past the cap"] = function()
		local s = 0
		for _ = 1, 50 do
			s = R.add(s, 1, Cfg.Stack, Cfg.Cap)
			assert(s <= Cfg.Cap)
		end
		assert(math.abs(R.add(0.4, 0.2, 0.5, 1) - 0.5) < 1e-9, "the stronger plus a share of the weaker")
		assert(R.add(0.2, 0, Cfg.Stack, Cfg.Cap) == 0.2, "nothing added by nothing")
	end,
	["eases in, holds, eases out to nothing"] = function()
		local dt = 1 / 60
		local level, shown = 1, 0
		level, shown = R.step(level, shown, dt, true, Cfg.Rise, Cfg.Fall, Cfg.Floor)
		assert(shown > 0 and shown < 1, "not all at once")
		for _ = 1, 30 do
			level, shown = R.step(level, shown, dt, true, Cfg.Rise, Cfg.Fall, Cfg.Floor)
		end
		assert(level == 1 and shown > 0.95, "up while held")
		local t, last = 0, shown
		while shown > 0 and t < 10 do
			level, shown = R.step(level, shown, dt, false, Cfg.Rise, Cfg.Fall, Cfg.Floor)
			assert(shown <= last, "only down once the hold is over")
			last = shown
			t += dt
		end
		assert(shown == 0 and level == 0, "gone")
		assert(t < Cfg.Fall * 6, `gone soon ({t} s)`)
	end,
	["sizes stay within Roblox's blur"] = function()
		assert(Cfg.MaxSize * Cfg.Cap <= 56 and Cfg.MaxSize > 0)
		assert(P.peak <= Cfg.Cap and B.least <= 1)
	end,
}
