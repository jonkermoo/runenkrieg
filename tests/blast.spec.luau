--!strict
local D = require("../src/shared/Config/Damage")
local Destruction = require("../src/shared/Config/Destruction")
local Blast = require("../src/shared/Rules/Blast")

local B = D.Blast
local KG = D.Staff.Charge[3]

local function kpa(studs: number, kg: number?): number
	return Blast.kpa(studs, kg or KG, B)
end

return {
	["Kinney-Graham overpressure matches published values"] = function()
		-- Kinney & Graham (ambient 1 atm): Z = 3 -> ~0.8 bar, Z = 5 -> ~0.29 bar, Z = 10 -> ~0.1 bar
		local function near(z: number, want: number, tol: number)
			local got = Blast.overpressure(z, B.AmbientKPa)
			assert(math.abs(got - want) <= tol, `Z={z}: {got} kPa, want ~{want}`)
		end
		near(3, 82, 4)
		near(5, 29, 2)
		near(10, 10, 1)
		assert(Blast.overpressure(math.huge, B.AmbientKPa) == 0)
	end,
	["pressure falls with distance and grows with the charge by its cube root"] = function()
		assert(kpa(5) > kpa(18) and kpa(18) > kpa(30) and kpa(30) > kpa(60))
		-- 8 x the charge: the same pressure twice as far
		assert(math.abs(kpa(20, 1) - kpa(40, 8)) < 1e-6, "cube-root scaling")
		assert(Blast.scaled(10, 0, B.MetresPerStud) == math.huge, "no charge, no blast")
		assert(Blast.kpa(10, 0, B) == 0)
	end,
	["the full beam at 10 kg: lethal ~18, heavy ~30, knocked down ~60 studs"] = function()
		local S = B.Soldier
		assert(Blast.soldierDamage(kpa(17), S) >= S.max, "inside ~18 studs: lethal")
		local mid = Blast.soldierDamage(kpa(30), S)
		assert(mid > 20 and mid < S.max, `30 studs: heavy, not lethal ({mid})`)
		assert(Blast.knock(kpa(30), B.Knocks) == "BlastThrow" or Blast.knock(kpa(30), B.Knocks) == "Torso")
		assert(Blast.knock(kpa(25), B.Knocks) == "BlastThrow", "25 studs: thrown")
		assert(Blast.knock(kpa(55), B.Knocks) ~= nil, "55 studs: still knocked")
		assert(Blast.soldierDamage(kpa(80), S) == 0 and Blast.knock(kpa(80), B.Knocks) == nil, "80 studs: nothing")
		assert(Blast.studsAt(B.Reach, KG, B.MetresPerStud) > 60, "the search reaches past the knock range")
	end,
	["map sections fail by material: glass far, wood mid, brick and stone close"] = function()
		local F = B.Fail
		for class in Destruction.Materials do
			assert(F[class], "a fail pressure for " .. class)
		end
		local function breaks(class: string, studs: number): boolean
			local hp = Destruction.Materials[class].hp
			return Blast.sectionDamage(kpa(studs), F[class], hp, B.Weaken) >= hp
		end
		assert(breaks("Brick", 17) and breaks("Stone", 16) and not breaks("Brick", 25), "brick / stone ~18")
		assert(breaks("Wood", 30) and breaks("Plaster", 28) and not breaks("Wood", 40), "wood / plaster ~30")
		assert(breaks("Glass", 55) and not breaks("Glass", 75), "glass ~60")
		local worn = Blast.sectionDamage(kpa(25), F.Brick, 700, B.Weaken)
		assert(worn > 0 and worn < 700, "a brick wall at 25 studs is worn down, not broken")
		assert(Blast.sectionDamage(0, F.Brick, 700, B.Weaken) == 0)
	end,
	["a crater about 5 studs across the radius at 10 kg; none without a charge"] = function()
		local r = Blast.crater(KG, B.Crater.perCubeRoot)
		assert(r > 4.5 and r < 5.5, `crater {r}`)
		assert(Blast.crater(0, B.Crater.perCubeRoot) == 0)
		assert(B.Tree.fail < kpa(18) and B.Tree.fail > kpa(30), "trees snap inside ~20 studs")
	end,
}
