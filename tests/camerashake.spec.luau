--!strict
local C = require("../src/shared/Config/CameraShake")
local A = require("../src/shared/Config/Artillery")
local G = require("../src/shared/Config/Grenades")
local S = require("../src/shared/Rules/CameraShake")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

return {
	["a kick is full at its source and dies away squared to nothing at its reach"] = function()
		assert(near(S.falloff(2, 100, 0), 2))
		assert(near(S.falloff(2, 100, 50), 0.5))
		assert(S.falloff(2, 100, 100) == 0 and S.falloff(2, 100, 400) == 0)
		assert(S.falloff(2, 0, 0) == 0, "no reach, no kick")
	end,
	["a blast shakes harder and farther by its charge's cube root"] = function()
		local B = C.Blast
		assert(near(S.blast(1, 0, B), B.size))
		assert(near(S.blast(8, 0, B), B.size * 2), "8 x the charge: twice the kick")
		assert(near(S.blast(8, B.reach * 1.5, B), S.blast(1, B.reach * 0.75, B) * 2), "and twice as far")
		assert(S.blast(0, 0, B) == 0, "no charge, no kick")
		assert(S.blast(1, B.reach, B) == 0)
	end,
	["artillery shells shake as before (1.2 degrees within 90 studs x the cube root)"] = function()
		for _, gun in A.Guns do
			local k = math.max(gun.kg, 1) ^ (1 / 3)
			for _, d in { 0, 20, 80, 200 } do
				local before = if d < 90 * k then 1.2 * k * (1 - d / (90 * k)) ^ 2 else 0
				assert(near(S.blast(gun.kg, d, C.Blast), before), `{gun.kg} kg at {d}`)
			end
		end
	end,
	["bigger blasts shake more: grenades < staff stages < the howitzer"] = function()
		local B = C.Blast
		local grenade = 0
		for _, g in G.Types do
			grenade = math.max(grenade, S.blast(g.kg, 10, B))
		end
		local stage3 = S.blast(S.stageKg(3, C.Stages), 10, B)
		assert(grenade > 0 and grenade < stage3)
		assert(S.blast(S.stageKg(1, C.Stages), 10, B) < S.blast(S.stageKg(2, C.Stages), 10, B))
		local biggest = 0
		for _, gun in A.Guns do
			biggest = math.max(biggest, gun.kg)
		end
		assert(stage3 < S.blast(biggest, 10, B))
	end,
	["a kick dies away over its time"] = function()
		assert(near(S.decay(2, 0, C.time) :: number, 2))
		assert(near(S.decay(2, C.time / 2, C.time) :: number, 0.5))
		assert(S.decay(2, C.time + 0.01, C.time) == nil)
	end,
	["staff stages map to their charges, clamped"] = function()
		assert(S.stageKg(0, C.Stages) == C.Stages[1] and S.stageKg(9, C.Stages) == C.Stages[#C.Stages])
		assert(C.Stages[1] > 0, "stage 1's blast shakes too")
	end,
}
