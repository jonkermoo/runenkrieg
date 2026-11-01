--!strict
local C = require("../src/shared/Config/Suppression")
local G = require("../src/shared/Config/Grenades")
local S = require("../src/shared/Rules/Suppression")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

return {
	["a passing bullet suppresses most on its path, nothing at the radius"] = function()
		local P = C.Pass
		assert(near(S.pass(0, P), P.add))
		assert(S.pass(P.radius / 2, P) < P.add and S.pass(P.radius / 2, P) > 0)
		assert(S.pass(P.radius, P) == 0 and S.pass(P.radius * 3, P) == 0)
	end,
	["a bullet landing close suppresses less than one passing by the head"] = function()
		assert(S.impact(0, C.Impact) < S.pass(0, C.Pass))
		assert(S.impact(C.Impact.radius, C.Impact) == 0)
	end,
	["about three very close cracks reach full suppression"] = function()
		local level = 0
		for _ = 1, 3 do
			level = S.add(level, S.pass(0.5, C.Pass), C.Cap)
		end
		assert(level > 0.8, `3 cracks: {level}`)
		level = S.add(level, S.pass(0, C.Pass), C.Cap)
		assert(level == C.Cap, "never past the cap")
	end,
	["a Mills grenade rattles hard at 5 studs, a little at 20, not at all past 40"] = function()
		local kg = G.Types.grenade_mills.kg
		assert(near(S.blast(kg, 5, C.Blast), 0.8, 0.05))
		assert(near(S.blast(kg, 20, C.Blast), 0.2, 0.05))
		assert(S.blast(kg, 40, C.Blast) == 0)
	end,
	["bigger blasts reach farther, never past maxReach"] = function()
		local B = C.Blast
		assert(S.blast(2.5, 60, B) > S.blast(0.071, 60, B))
		assert(S.blast(400, B.maxReach, B) == 0)
		assert(S.blast(0, 0, B) == 0, "no charge, no rattle")
	end,
	["the level holds, then falls 1 every Fall seconds"] = function()
		assert(S.decay(1, 0, C.Hold * 0.9, C.Hold, C.Fall) == 1, "held")
		assert(near(S.decay(1, 0, C.Hold + C.Fall / 2, C.Hold, C.Fall), 0.5))
		assert(near(S.decay(1, C.Hold + 1, 0.1, C.Hold, C.Fall), 1 - 0.1 / C.Fall))
		assert(S.decay(1, 0, C.Hold + C.Fall + 1, C.Hold, C.Fall) == 0, "gone")
		-- frame by frame comes out the same as in one go
		local level, since = 1, 0
		for _ = 1, 60 do
			level = S.decay(level, since, 1 / 60, C.Hold, C.Fall)
			since += 1 / 60
		end
		assert(near(level, S.decay(1, 0, 1, C.Hold, C.Fall), 1e-9))
	end,
	["the shake grows with the level, 0 to 1"] = function()
		assert(S.size(0, C.grow) == 0 and S.size(1, C.grow) == 1)
		assert(S.size(0.5, C.grow) <= 0.5)
		assert(S.size(2, C.grow) == 1)
	end,
	["a startle jolt is full at the hit, shudders, and is gone after its time"] = function()
		local J = C.Jolt
		assert(S.jolt(0, J.time, J.freq) == 1)
		assert(S.jolt(J.time, J.time, J.freq) == 0 and S.jolt(-0.1, J.time, J.freq) == 0)
		local flips, last = 0, 1
		for i = 1, 99 do
			local u = i / 100 * J.time
			local v = S.jolt(u, J.time, J.freq)
			assert(math.abs(v) <= (1 - u / J.time) ^ 2 + 1e-9, "dies away")
			if v * last < 0 then
				flips += 1
			end
			if v ~= 0 then
				last = v
			end
		end
		assert(flips >= 2, `shudders ({flips} swings)`)
	end,
	["full suppression makes far shots miss: the gun wanders past 4 degrees, first person shakes harder"] = function()
		assert(C.viewmodel.pitch >= 4 and C.viewmodel.yaw >= 4)
		assert(C.cameraFirst.pitch > C.camera.pitch)
	end,
}
