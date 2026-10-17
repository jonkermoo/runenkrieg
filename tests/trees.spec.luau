--!strict
local D = require("../src/shared/Config/Damage")
local Blast = require("../src/shared/Rules/Blast")
local Trees = require("../src/shared/Rules/Trees")

local T = D.Trees
local B = D.Blast

return {
	["a tree's HP grows with its scale; an unknown kind gets the smallest"] = function()
		assert(Trees.maxHP("Pine", 2, T) == 2 * T.HP.Pine)
		assert(Trees.maxHP("Nope", 1, T) == math.min(T.HP.Pine, T.HP.Broadleaf, T.HP.Birch))
		assert(Trees.maxHP("Birch", -1, T) == 0)
	end,
	["about 30 rifle bullets fell a tree, a shotgun pellet only chips it"] = function()
		local rifle = Trees.shotDamage("BoltRifle", T)
		for kind, hp in T.HP do
			local hits = math.ceil(hp / rifle)
			assert(hits >= 20 and hits <= 40, `{kind}: {hits} rifle hits`)
		end
		assert(Trees.shotDamage("Shotgun", T) < rifle / 2)
		assert(Trees.shotDamage(nil, T) == 0 and Trees.shotDamage("Staff", T) == 0)
		for class in T.Weapons do
			assert(D.Weapons[class], "a weapon class Config/Damage knows: " .. class)
		end
	end,
	["HP runs down to 0 and only a real hit fells"] = function()
		local left, felled = Trees.after(15, 10)
		assert(left == 5 and not felled)
		left, felled = Trees.after(5, 10)
		assert(left == 0 and felled)
		left, felled = Trees.after(0, 0)
		assert(left == 0 and not felled, "no damage fells nothing")
		left = Trees.after(10, -5)
		assert(left == 10, "negative damage heals nothing")
	end,
	["a big blast at the roots fells it whole; further off it wears it down"] = function()
		local kg = D.Staff.Charge[3]
		local near = Blast.kpa(10, kg, B)
		local amount, whole = Trees.blastDamage(near, B.Tree.fail, 300, B.Weaken)
		assert(whole and amount == 300)
		amount, whole = Trees.blastDamage(Blast.kpa(30, kg, B), B.Tree.fail, 300, B.Weaken)
		assert(not whole and amount > 0 and amount < 300)
		assert(Trees.blastDamage(0, B.Tree.fail, 300, B.Weaken) == 0)
	end,
	["a felled tree lies on the ground: flat on the level, less up a slope, more down one"] = function()
		local F = T.Fall
		assert(Trees.fallTilt(30, 0, F.minTilt, F.maxTilt) == 90)
		assert(Trees.fallTilt(30, 6, F.minTilt, F.maxTilt) < 90)
		assert(Trees.fallTilt(30, -3, F.minTilt, F.maxTilt) > 90)
		assert(Trees.fallTilt(30, 100, F.minTilt, F.maxTilt) == F.minTilt, "clamped")
		assert(Trees.fallTilt(30, -100, F.minTilt, F.maxTilt) == F.maxTilt, "clamped")
		assert(Trees.fallTilt(0, 0, F.minTilt, F.maxTilt) == F.minTilt)
		assert(F.maxFallen > 0 and F.lifetime > 0 and F.time > 0, "fallen trees stay a while, capped")
	end,
	["a bullet's line enters a canopy box where it should"] = function()
		-- along +X from x = -10, a box of half size 2: enters at 8
		local t = Trees.enterBox(-10, 0, 0, 1, 0, 0, 50, 2, 2, 2)
		assert(t and math.abs(t - 8) < 1e-9)
		assert(Trees.enterBox(-10, 0, 0, 1, 0, 0, 5, 2, 2, 2) == nil, "too short")
		assert(Trees.enterBox(-10, 3, 0, 1, 0, 0, 50, 2, 2, 2) == nil, "passes over")
		assert(Trees.enterBox(-10, 1.9, 0, 1, 0, 0, 50, 2, 2, 2) ~= nil, "low in the box still counts")
		assert(Trees.enterBox(10, 0, 0, 1, 0, 0, 50, 2, 2, 2) == nil, "behind the start")
		assert(Trees.enterBox(0, 0, 0, 0, 1, 0, 50, 2, 2, 2) == 0, "starts inside")
	end,
}
