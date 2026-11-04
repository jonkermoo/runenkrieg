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
	["a stump clears in fewer shovel swings than its tree falls in"] = function()
		local C = T.Chop
		assert(C.stumpSwings >= 1 and C.stumpSwings < C.swings)
		local n, cleared = 0, false
		local swings = 0
		while not cleared do
			n, cleared = Trees.stumpChop(n, C.stumpSwings)
			swings += 1
		end
		assert(swings == C.stumpSwings and n == C.stumpSwings)
		local _, one = Trees.stumpChop(0, 0)
		assert(one, "at least one swing")
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
	["the imprint is even and shallow, and root balls show in 4-stud voxels"] = function()
		local I = T.Fall.Imprint
		assert(I.depth > 0 and I.depth <= 1.5, "pressed in about a stud, not buried")
		assert(I.step < I.churnRadius, "its mud runs on along the trunk")
		local R = T.Fall.Roots
		assert(R.min >= 2.2 and R.max >= R.min, "a root ball the voxels keep")
		local Palette = require("../src/shared/Config/Palette")
		local roots, mud = Palette.Terrain[R.material], Palette.Terrain.Mud
		assert(roots, "the root material has a palette colour (flat, from Greybox applyPalette)")
		assert(roots[1] + roots[2] + roots[3] < mud[1] + mud[2] + mud[3], "roots darker than mud")
		local Foliage = require("../src/shared/Config/Foliage")
		assert(Foliage.UnderTrunk.radius >= 2, "no grass along the trunk")
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
	["leaves: a shot through a canopy's box corner misses the leaves, one through the middle hits them"] = function()
		local ball = { { shape = "Ellipsoid", x = 0, y = 0, z = 0, rx = 1, ry = 1, rz = 1 } }
		-- a box of half size 4: through the middle enters at 6
		local t = Trees.enterLeaves(-10, 0, 0, 1, 0, 0, 50, 4, 4, 4, ball, 1)
		assert(t and math.abs(t - 6) < 1e-6, `middle: {t}`)
		-- 3.5 up and 3.5 across: inside the box, outside the ball
		local c = 1 / math.sqrt(2)
		assert(Trees.enterBox(-10, 3.5, 0, 1, 0, 0, 50, 4, 4, 4) ~= nil, "the box takes the corner")
		assert(Trees.enterLeaves(-10, 3.5, 3.5, c, 0, -c, 50, 4, 4, 4, ball, 1) == nil, "the ball doesn't")
		assert(Trees.enterLeaves(0, 0, 0, 0, 1, 0, 50, 4, 4, 4, ball, 1) == 0, "starts inside")
		assert(Trees.enterLeaves(-10, 0, 0, 1, 0, 0, 5, 4, 4, 4, ball, 1) == nil, "too short")
		assert(Trees.enterLeaves(10, 0, 0, 1, 0, 0, 50, 4, 4, 4, ball, 1) == nil, "behind the start")
		assert(Trees.enterLeaves(-10, 4.2, 0, 1, 0, 0, 50, 4, 4, 4, ball, 1.1) ~= nil, "grown pieces reach further")
	end,
	["leaves: a cone is hit below its apex and missed beside it"] = function()
		-- base at the bottom (y = -1), base radius 1, apex at the top (height 2): half size 4 -> base radius 4 studs
		local cone = { { shape = "Cone", x = 0, y = -1, z = 0, rx = 1, ry = 0, rz = 1, height = 2 } }
		local low = Trees.enterLeaves(-10, -3, 0, 1, 0, 0, 50, 4, 4, 4, cone, 1)
		-- 1 stud above the base the radius is 4 x (1 - 1/8) = 3.5
		assert(low and math.abs(low - 6.5) < 1e-6, `low: {low}`)
		local high = Trees.enterLeaves(-10, 3, 0, 1, 0, 0, 50, 4, 4, 4, cone, 1)
		assert(high and math.abs(high - 9.5) < 1e-6, `high: {high}`)
		assert(Trees.enterLeaves(-10, 3, 2, 1, 0, 0, 50, 4, 4, 4, cone, 1) == nil, "beside the narrow top")
		assert(Trees.enterLeaves(-10, -5, 0, 1, 0, 0, 50, 4, 4, 4, cone, 1) == nil, "under the base")
		local down = Trees.enterLeaves(0, 10, 0, 0, -1, 0, 50, 4, 4, 4, cone, 1)
		assert(down and math.abs(down - 6) < 1e-6, `from above, at the apex: {down}`)
		local up = Trees.enterLeaves(1, -10, 0, 0, 1, 0, 50, 4, 4, 4, cone, 1)
		assert(up and math.abs(up - 6) < 1e-6, `from below, through the base: {up}`)
		assert(Trees.enterLeaves(1, 0, 0, 0, 1, 0, 50, 4, 4, 4, cone, 1) == 0, "starts inside")
	end,
	["leaves: every tree kit canopy finds its own shapes; an odd one gets the fallback"] = function()
		local S = require("../src/shared/Config/TreeShapes")
		for name, v in S.Variants do
			local s = v.size
			for _, k in { 1, 37.5 } do
				assert(Trees.canopyShapes(s[1] * k, s[2] * k, s[3] * k, S) == v.shapes, name .. " matches itself")
			end
			assert(#v.shapes >= 3, name)
			for _, p in v.shapes do
				assert(p.shape == "Cone" or p.shape == "Ellipsoid", name)
			end
		end
		assert(Trees.canopyShapes(10, 10, 10, S) == S.Fallback, "a cube is no kit canopy")
		-- the leaves fill much less than the box: of lines through random points of the box, many miss
		for name, v in S.Variants do
			local miss, n = 0, 400
			for i = 1, n do
				local a, b = (i * 0.618034) % 1 * 2 - 1, (i * 0.414214) % 1 * 2 - 1
				if not Trees.enterLeaves(-5, a, b, 1, 0, 0, 10, 1, 1, 1, v.shapes, S.grow) then
					miss += 1
				end
			end
			assert(miss > n * 0.1 and miss < n * 0.8, `{name}: {miss} of {n} side-on lines miss the leaves`)
		end
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
	["every Config key src/server/Trees reads exists (the checks don't type-check)"] = function()
		local F = T.Fall
		local need = {
			[F] = {
				"Crush",
				"Imprint",
				"Roots",
				"lifetime",
				"maxFallen",
				"maxTilt",
				"minTilt",
				"samples",
				"time",
				"tipClear",
				"tipShare",
				"sinkDepth",
				"sinkTime",
				"bounce",
				"bounceTime",
			},
			[T] = { "Direct", "Fall", "Fallen", "Leaves", "Stump", "HP", "Weapons" },
			[T.Leaves] = {
				"HP",
				"blastFail",
				"blastWeaken",
				"nearDistance",
				"nearReact",
				"react",
				"shedTime",
				"through",
				"near",
			},
			[F.Roots] = { "material", "max", "min", "pit", "pitBack", "pitSink", "radius", "rise" },
			[F.Imprint] = { "churnRadius", "churnDepth", "depth", "step", "touch", "churnFrom", "churnTo" },
			[F.Crush] = { "ghost", "ghostMax", "radius", "damage", "knock" },
			[T.Stump] = { "height", "widthShare", "floatTolerance" },
		}
		for t, keys in need do
			for _, k in keys do
				assert((t :: any)[k] ~= nil, "missing Config/Damage.Trees key " .. k)
			end
		end
	end,
}
