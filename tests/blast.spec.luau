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
	["the full beam at 10 kg: lethal ~18, hurts to ~70, ragdolls the living only within ~10 studs"] = function()
		local S = B.Soldier
		assert(Blast.soldierDamage(kpa(17), S) >= S.max, "inside ~18 studs: lethal")
		local mid = Blast.soldierDamage(kpa(30), S)
		assert(mid > 20 and mid < S.max, `30 studs: heavy, not lethal ({mid})`)
		assert(Blast.soldierDamage(kpa(60), S) > 0, "60 studs: still hurt")
		-- user 2026-10-17: only the one aimed at and those really close to them are ragdolled
		assert(Blast.knock(kpa(5.5), B.Knocks) == "BlastThrow", "5.5 studs: thrown")
		assert(Blast.knock(kpa(8), B.Knocks) == "Torso", "8 studs: knocked down")
		assert(Blast.knock(kpa(11), B.Knocks) == nil, "11 studs: hurt, stays up")
		assert(Blast.knock(kpa(30), B.Knocks) == nil, "30 studs: stays up")
		assert(Blast.soldierDamage(kpa(80), S) == 0 and Blast.knock(kpa(80), B.Knocks) == nil, "80 studs: nothing")
		assert(Blast.studsAt(B.Reach, KG, B.MetresPerStud) > 60, "the search reaches past the damage range")
	end,
	["the full beam leaves a hole where it hits, not a ruin"] = function()
		local F = B.Fail
		for class in Destruction.Materials do
			assert(F[class], "a fail pressure for " .. class)
		end
		local function hit(class: string, studs: number, kg: number?, opts: any?): number
			local hp = Destruction.Materials[class].hp
			local o = opts or {}
			return Blast.sectionHit(kpa(studs, kg), {
				fail = F[class],
				maxHP = hp,
				hp = o.hp or hp,
				weaken = B.Weaken,
				wear = o.wear,
				keep = o.keep,
			})
		end
		local function breaks(class: string, studs: number, kg: number?, opts: any?): boolean
			return hit(class, studs, kg, opts) >= Destruction.Materials[class].hp
		end
		-- user 2026-10-17: walls, roofs and doors of every material break only within ~6 studs (a 1-2 section hole)
		for class in Destruction.Materials do
			if class ~= "Glass" then
				assert(breaks(class, 5), `{class}: breaks at 5 studs`)
				assert(not breaks(class, 7), `{class}: holds at 7 studs`)
				local worn = hit(class, 12, nil)
				assert(worn > 0 and worn < Destruction.Materials[class].hp / 3, `{class}: worn a little at 12 studs`)
			end
		end
		assert(breaks("Glass", 35) and not breaks("Glass", 40), "glass ~37")
		-- floors only wear (each is one slab): even at the blast they keep 1 HP
		local floor = Destruction.Materials.Wood.hp
		assert(hit("Wood", 0, nil, { keep = true }) == floor - 1, "a floor at the blast: down to 1 HP")
		assert(hit("Wood", 0, nil, { keep = true, hp = 1 }) == 0, "a floor at 1 HP takes nothing more")
		assert(Blast.sectionDamage(0, F.Brick, 700, B.Weaken) == 0)
	end,
	["stage 2: a light blast for the map only (glass, a shake for trees, sections worn not broken)"] = function()
		local St = D.Staff
		local kg, o = St.Charge[2], St.Blasts[2]
		assert(kg > 0 and kg < St.Charge[3], "a small charge")
		assert(o.soldiers == false and o.trees == false and o.crater == false, "nothing but the map")
		assert(o.breaks and o.breaks.Glass, "glass still shatters")
		local glass = Blast.sectionHit(kpa(13, kg), { fail = B.Fail.Glass, maxHP = 1, hp = 1, weaken = B.Weaken })
		assert(glass >= 1, "glass ~14 studs off breaks")
		assert(
			Blast.sectionHit(kpa(17, kg), { fail = B.Fail.Glass, maxHP = 1, hp = 1, weaken = B.Weaken }) < 1,
			"glass 17 studs off holds"
		)
		-- a direct hit on a wall: at most `wear` of it (user: 3 shots at one spot break it)
		local hp = Destruction.Materials.Brick.hp
		local function shot(left: number): number
			return Blast.sectionHit(
				kpa(0, kg),
				{ fail = B.Fail.Brick, maxHP = hp, hp = left, weaken = B.Weaken, wear = o.wear }
			)
		end
		local left = hp
		for i = 1, 2 do
			left -= shot(left)
			assert(left > 0, `still standing after {i} shots`)
		end
		left -= shot(left)
		assert(left <= 0, "the third shot breaks it")
		-- stage 1 and the full beam: everything
		for _, s in { 1, 3 } do
			local b = St.Blasts[s]
			assert(b.soldiers and b.trees and b.crater and b.wear == nil)
		end
		assert(#St.Blasts == #St.Charge)
	end,
	["a crater about 5 studs across the radius at 10 kg; none without a charge"] = function()
		local r = Blast.crater(KG, B.Crater.perCubeRoot)
		assert(r > 4.5 and r < 5.5, `crater {r}`)
		assert(Blast.crater(0, B.Crater.perCubeRoot) == 0)
		assert(B.Tree.fail < kpa(18) and B.Tree.fail > kpa(30), "trees felled whole inside ~20 studs")
	end,
	["the crater has a low rim round it and churns the ground about twice as far"] = function()
		local C = B.Crater
		local plan = Blast.craterPlan(KG, C) :: Blast.CraterPlan
		assert(plan and #plan.rim == C.rim.count)
		for _, b in plan.rim do
			local out = math.sqrt(b.dx * b.dx + b.dz * b.dz)
			assert(out > plan.radius, "the rim is outside the hole")
			local rise = b.radius - b.sink
			assert(rise > 0 and rise < 0.5 * plan.radius, `a low rim: {rise}`)
		end
		assert(plan.churn > plan.radius * 1.5 and plan.churn < plan.radius * 3, "churned out to ~2x the hole")
		assert(Blast.craterPlan(0, C) == nil, "no charge, no crater")
		-- clients work the churn out from the reach alone, for any charge
		for _, kg in { 1, 10, 50 } do
			local reach = Blast.studsAt(B.Reach, kg, B.MetresPerStud)
			local want = (Blast.craterPlan(kg, C) :: Blast.CraterPlan).churn
			assert(math.abs(Blast.churnFromReach(reach, B) - want) < 1e-6, `churn at {kg} kg`)
		end
		-- churned earth grows no grass
		local Foliage = require("../src/shared/Config/Foliage")
		for _, m in Foliage.Materials do
			assert(m ~= C.churnTo, "churned ground must not grow tufts")
		end
		for _, m in Foliage.Blades.Materials do
			assert(m ~= C.churnTo, "churned ground must not grow blades")
		end
	end,
}
