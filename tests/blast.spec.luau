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
	["the full beam at 10 kg: lethal ~9, and whoever it hurts is ragdolled, all within ~15 studs"] = function()
		local S = B.Soldier
		-- user 2026-10-18: "lethal within ~8"; 2026-10-23: near misses should kill, ~9
		assert(Blast.soldierDamage(kpa(8.8), S) >= S.max, "inside ~9 studs: lethal")
		local ten = Blast.soldierDamage(kpa(10), S)
		assert(ten > 50 and ten < 90, `10 studs: heavy, not lethal ({ten})`)
		-- user 2026-10-18: flung whenever it hurts, as hard as it hurts
		local F = B.Fling
		assert(Blast.fling(0, S.max, F.least) == nil, "no damage, no fling")
		assert(Blast.fling(S.max, S.max, F.least) == 1 and Blast.fling(500, S.max, F.least) == 1, "full force at max")
		local small = Blast.fling(5, S.max, F.least) :: number
		local big = Blast.fling(60, S.max, F.least) :: number
		assert(small >= F.least and small < big and big < 1, "scaled to the damage")
		for _, d in { 2, 5, 9, 11, 13, 14.5 } do
			assert(Blast.fling(Blast.soldierDamage(kpa(d), S), S.max, F.least), `{d} studs: flung`)
		end
		assert(Blast.soldierDamage(kpa(16), S) == 0, "16 studs: nothing")
		assert(Blast.studsAt(B.Reach, KG, B.MetresPerStud) > 15, "the search reaches past the damage range")
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
		-- the wear fades out with distance (Studio round 2): the hit section in full, a neighbour ~3 studs off nothing
		local function wearAt(d: number): number
			return Blast.sectionHit(kpa(d, kg), {
				fail = B.Fail.Brick,
				maxHP = hp,
				hp = hp,
				weaken = B.Weaken,
				wear = o.wear,
				wearFull = o.wearFull,
				wearReach = o.wearReach,
				distance = d,
			})
		end
		assert(wearAt(1) == hp * o.wear, "the hit section, ~1 stud off its centre: in full")
		assert(wearAt(3) == 0, `a neighbour 3 studs off: {wearAt(3)}`)
		local mid = wearAt((o.wearFull + o.wearReach) / 2)
		assert(mid > 0 and mid < hp * o.wear, "fading in between")
		assert(wearAt(o.wearReach + 1) == 0, "nothing past wearReach")
		-- glass is brittle: a weaker blast leaves it whole, however many there are (Studio round 1)
		local function pane(d: number): number
			return Blast.sectionHit(
				kpa(d, kg),
				{ fail = B.Fail.Glass, maxHP = 1, hp = 1, weaken = B.Weaken, brittle = B.Brittle.Glass }
			)
		end
		assert(pane(13) == 1 and pane(20) == 0, "glass breaks near, takes nothing further off")
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
			assert(out > plan.mouth, "the rim is outside the bowl")
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
	["a crater scale sizes the hole and its rim, not the churn; the howitzer's is about half"] = function()
		local C = B.Crater
		local full = Blast.craterPlan(50, C) :: Blast.CraterPlan
		local half = Blast.craterPlan(50, C, 0.5) :: Blast.CraterPlan
		assert(math.abs(half.radius - full.radius / 2) < 1e-9)
		assert(math.abs(half.mouth - full.mouth / 2) < 1e-9 and math.abs(half.depth - full.depth / 2) < 1e-9)
		assert(math.abs(half.rim[1].radius - full.rim[1].radius / 2) < 1e-9, "the rim shrinks with it")
		assert(half.churn == full.churn, "the ground churns as far as the blast's (clients clear grass by reach)")
		local same = Blast.craterPlan(50, C, 1) :: Blast.CraterPlan
		assert(same.mouth == full.mouth and same.depth == full.depth)
		local Artillery = require("../src/shared/Config/Artillery")
		local h = Artillery.Guns.artillery_howitzer
		local plan = Blast.craterPlan(h.kg, C, h.craterScale) :: Blast.CraterPlan
		local across = 2 * plan.mouth
		assert(across > 28 and across < 36, `howitzer crater ~32 across: {across}`)
		assert(plan.depth > 4 and plan.depth < 6, `howitzer crater ~5 deep: {plan.depth}`)
		assert(Artillery.Guns.artillery_qf18.craterScale == nil, "the field gun's crater is its charge's own")
	end,
	["cover: a blast reaches only the share of a soldier it can see"] = function()
		local C = B.Cover
		assert(Blast.exposure(0, 6, C.minShare) == 0, "fully behind cover: nothing")
		assert(Blast.exposure(6, 6, C.minShare) == 1)
		assert(Blast.exposure(3, 6, C.minShare) == 0.5)
		assert(Blast.exposure(1, 0, C.minShare) == 1, "no parts to test: in the open")
		assert(C.minShare > 0 and C.minShare < 1)
		assert(#C.parts >= 4)
	end,
	["a near miss hits in full, cover or not; further out cover counts again"] = function()
		local C = B.Cover
		-- user 2026-10-23: "a grenade or staff explosion that missed a few studs away should kill"
		for _, d in { 0, 2, 3, 4, 5 } do
			assert(not Blast.coverCounts(d, C.near), `{d} studs: no cover`)
		end
		for _, d in { 5.5, 6.5, 20 } do
			assert(Blast.coverCounts(d, C.near), `{d} studs: cover counts`)
		end
		assert(C.near >= 3 and C.near <= 6, "a few studs")
		-- a blast on the ground 4 studs off, torso ~2.7 up
		assert(not Blast.coverCounts(math.sqrt(4 ^ 2 + 2.7 ^ 2), C.near), "4 studs off on the ground: no cover")
		assert(C.near > C.skip, "wider than the skipped wall")
		-- the full beam kills there outright (and the grenades by their fragments, Config/Grenades)
		assert(Blast.soldierDamage(kpa(C.near), B.Soldier) >= B.Soldier.max, "the full beam kills inside `near`")
	end,
	["a grenade's own blast kills out to ~2 studs, the full beam to ~9"] = function()
		local G = require("../src/shared/Config/Grenades")
		local S = B.Soldier
		for name, g in G.Types do
			local r = Blast.reachOf(S.kill, g.kg, B)
			assert(r > 1.6 and r < 2.6, `{name}: own blast lethal to {r}`)
			-- inside `near` (no cover) its fragments kill too
			assert(g.fragments.lethal >= B.Cover.near, `{name}: fragments lethal inside near`)
			-- on the ground 4 studs off (torso ~2.7 up) its fragments kill
			assert(g.fragments.lethal >= math.sqrt(4 ^ 2 + 2.7 ^ 2), `{name}: kills 4 studs off on the ground`)
		end
		local r = Blast.reachOf(S.kill, KG, B)
		assert(r > 8.5 and r < 9.5, `full beam lethal to {r}`)
	end,
	["each class breaks out to where the pressure falls to its fail pressure"] = function()
		for class, fail in B.Fail do
			local r = Blast.reachOf(fail, KG, B)
			assert(r > 0, class)
			assert(math.abs(kpa(r) - fail) / fail < 1e-3, `{class}: {kpa(r)} at {r}`)
		end
		local brick = Blast.reachOf(B.Fail.Brick, KG, B)
		assert(brick > 4 and brick < 9, `brick hole ~6: {brick}`)
		assert(Blast.reachOf(10, 0, B) == 0, "no charge")
		assert(Blast.reachOf(1e9, KG, B) == 0, "never that strong")
	end,
	["a crater is a bowl you can walk out of, at any charge, and follows the ground"] = function()
		local M = require("../src/shared/Config/Metrics")
		local steepest = math.tan(math.rad(M.Movement.MaxSlopeAngle))
		for _, kg in { 0.5, 2, 10, 50, 200 } do
			local plan = Blast.craterPlan(kg, B.Crater) :: Blast.CraterPlan
			-- the steepest the bowl adds to the ground: its slope at the mouth, 2 x depth / mouth
			local wall = 2 * plan.depth / plan.mouth
			local hill = math.tan(math.rad(25)) -- the map's steepest walkable ground is ~23 deg (mapterrain.spec)
			assert(wall + hill < steepest * 0.95, `{kg} kg: a wall of {math.deg(math.atan(wall))} deg on a hillside`)
			assert(plan.mouth > plan.depth * 2, `{kg} kg: wider than deep`)
			assert(Blast.bowlDepth(0, plan.mouth, plan.depth) == plan.depth)
			assert(Blast.bowlDepth(plan.mouth, plan.mouth, plan.depth) == 0)
			assert(Blast.bowlDepth(plan.mouth / 2, plan.mouth, plan.depth) == plan.depth * 0.75)
		end
		local big = Blast.craterPlan(50, B.Crater) :: Blast.CraterPlan
		assert(big.depth < 8, `50 kg: no pit ({big.depth} deep)`)
		-- a column 4 voxels high, ground at 10 (2.5 voxels full), lowered by 3: ground at 7
		local out = Blast.lowerColumn({ 1, 1, 0.5, 0 }, 0, 4, 3)
		local filled = 0
		for _, o in out do
			filled += o
		end
		assert(math.abs(filled * 4 - 7) < 1e-9, `lowered to {filled * 4}`)
		assert(out[1] == 1 and out[4] == 0)
		-- never adds ground, lowering by 0 changes nothing
		local same = Blast.lowerColumn({ 1, 0.3, 0 }, 0, 4, 0)
		assert(same[1] == 1 and math.abs(same[2] - 0.3) < 1e-9 and same[3] == 0)
	end,
}
