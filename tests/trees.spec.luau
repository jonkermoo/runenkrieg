--!strict
local D = require("../src/shared/Config/Damage")
local Blast = require("../src/shared/Rules/Blast")
local Trees = require("../src/shared/Rules/Trees")
local Rules = Trees

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
	["a felled tree lies clear of the ground: flat on the level, less up a slope, more down one"] = function()
		local F = T.Fall
		local function level(rise: number)
			local samples = {}
			for k = 1, 10 do
				table.insert(samples, { k * 3, rise * k / 10 })
			end
			return Rules.clearTilt(samples, F.minTilt, F.maxTilt)
		end
		assert(level(0) == 90, "flat")
		assert(level(6) < 90 and level(-3) > 90, "up / down a slope")
		assert(level(100) == F.minTilt and level(-100) == F.maxTilt, "clamped")
		-- a bump half way up wins over level ground at the top
		local bump = Rules.clearTilt({ { 10, 3 }, { 30, 0 } }, F.minTilt, F.maxTilt)
		assert(math.abs(bump - (90 - math.deg(math.atan(3 / 10)))) < 1e-9, `bump {bump}`)
		assert(Rules.clearTilt({}, F.minTilt, F.maxTilt) == F.maxTilt, "no ground found: lies flat or a bit down")
		assert(F.maxFallen > 0 and F.lifetime > 0 and F.time > 0, "fallen trees stay a while, capped")
	end,
	["a falling tree pushes soldiers to the side they stand on"] = function()
		local d, side = Rules.offSegment(5, 2, 0, 0, 10, 0)
		assert(math.abs(d - 2) < 1e-9 and side == 1)
		d, side = Rules.offSegment(5, -2, 0, 0, 10, 0)
		assert(math.abs(d - 2) < 1e-9 and side == -1)
		d = Rules.offSegment(13, 0, 0, 0, 10, 0)
		assert(math.abs(d - 3) < 1e-9, "past the top")
		local C = T.Fall.Crush
		assert(C.damage > 0 and C.damage < 100, "hurt, not killed outright")
		assert(C.ghost > 0 and C.ghostMax >= C.ghost)
		local Ragdoll = require("../src/shared/Config/Ragdoll")
		assert(Ragdoll.Knocks[C.knock], "a knock Config/Ragdoll knows")
	end,
	["a direct full beam shatters a trunk; weaker beams wear it down"] = function()
		local Dr = T.Direct
		local amount, blown = Rules.directHit(Dr.shatterFrom, Dr)
		assert(blown and amount == math.huge)
		amount, blown = Rules.directHit(2, Dr)
		assert(not blown and amount > Trees.shotDamage("BoltRifle", T) * 5, "stage 2 hits a trunk hard")
		amount, blown = Rules.directHit(1, Dr)
		assert(not blown and amount > 0 and amount < Dr.damage[2])
		for kind, hp in T.HP do
			local hits = math.ceil(hp * 1.3 / Dr.damage[2])
			assert(hits >= 2 and hits <= 5, `{kind}: {hits} stage 2 hits fell it`)
		end
	end,
	["the imprint and root balls are big enough to show in 4-stud voxels, and even"] = function()
		local I = T.Fall.Imprint
		assert(I.radius >= 2.5, "an imprint the voxels keep")
		assert(I.depth > 0 and I.depth < I.radius, "pressed in, not a hole")
		local open = math.sqrt(I.radius ^ 2 - (I.radius - I.depth) ^ 2)
		assert(I.step <= open, "its balls overlap into one even trough")
		local R = T.Fall.Roots
		assert(R.min >= 2.2 and R.max >= R.min, "a root ball the voxels keep")
		local Palette = require("../src/shared/Config/Palette")
		local roots, mud = Palette.Terrain[R.material], Palette.Terrain.Mud
		assert(roots, "the root material has a palette colour (flat, from Greybox applyPalette)")
		assert(roots[1] + roots[2] + roots[3] < mud[1] + mud[2] + mud[3], "roots darker than mud")
		local Foliage = require("../src/shared/Config/Foliage")
		assert(Foliage.UnderTrunk.radius >= open, "no grass in the imprint")
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
	["leaves: a few stage 2 beams strip a tree, a full beam does at once, bullets never"] = function()
		local L = T.Leaves
		for kind, hp in L.HP do
			local through = Trees.beamLeafDamage(2, true, L)
			local near = Trees.beamLeafDamage(2, false, L)
			local hits = math.ceil(hp * 1.3 / through) -- the biggest trees (scale ~1.3)
			assert(hits >= 2 and hits <= 4, `{kind}: {hits} stage 2 beams through`)
			assert(near > 0 and near <= through, "near takes some, less than through")
			assert(Trees.beamLeafDamage(3, true, L) >= hp * 1.4, `{kind}: a full beam strips it`)
			assert(Trees.beamLeafDamage(1, true, L) < through, "stage 1 takes less")
		end
		assert(Trees.beamLeafDamage(9, true, L) == 0, "no such stage")
		assert(Trees.shotDamage("BoltRifle", { Weapons = {} }) == 0)
		-- a full blast strips leaves further out than it fells trees
		assert(L.blastFail < D.Blast.Tree.fail)
		assert(T.Fallen.share > 0 and T.Fallen.share <= 1, "a fallen tree lies with HP again")
		assert(L.shedTime > 0, "the canopy sheds over time, not at once")
		for stage = 1, 3 do
			assert(L.react[stage] and L.nearDistance[stage], `react / near for stage {stage}`)
		end
	end,
}
