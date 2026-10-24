--!strict
local C = require("../src/shared/Config/Build")
local M = require("../src/shared/Config/Metrics")
local B = require("../src/shared/Rules/Build")

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local function placing(over: { [string]: any }): B.Placing
	local p: any = {
		piece = C.Pieces[1],
		distance = 5,
		reach = C.Reach,
		slope = 5,
		maxSlope = 20,
		ground = true,
		water = false,
		overlap = false,
		mine = 0,
		team = 0,
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
	}
	for k, v in over do
		p[k] = v
	end
	return p
end

local T = table.clone(C.Trench) :: any

return {
	["every piece has a key, a kind, a name and work; keys are unique"] = function()
		local seen = {}
		for _, p in C.Pieces do
			assert(type(p.key) == "string" and not seen[p.key], p.key)
			seen[p.key] = true
			assert(p.kind == "Trench" or p.kind == "Sandbags" or p.kind == "Wire", p.key)
			assert(type(p.name) == "string" and p.work >= 1, p.key)
		end
		assert(B.piece("LowWall", C.Pieces) ~= nil and B.piece("Nope", C.Pieces) == nil and B.piece(5, C.Pieces) == nil)
	end,
	["sandbag walls: the low one is low cover, the high one full cover with a loophole at the aimed muzzle"] = function()
		local low = B.piece("LowWall", C.Pieces) :: any
		local high = B.piece("HighWall", C.Pieces) :: any
		assert(low.rows * low.row >= M.Cover.LowCoverMin, "the low wall can't be hopped")
		assert(high.rows * high.row >= M.Cover.FullCoverMin, "the high wall hides a standing soldier")
		local bottom, top = (high.loophole - 1) * high.row, high.loophole * high.row
		assert(bottom < 4.3 and top > 4.3, "the standing aimed muzzle (4.3) looks out of the loophole")
	end,
	["laying a piece: each reason in turn"] = function()
		assert(B.canPlace(placing({})))
		local function why(over): string?
			local ok, reason = B.canPlace(placing(over))
			assert(not ok)
			return reason
		end
		assert(why({ distance = C.Reach + 1 }) == "Too far")
		assert(why({ ground = false }) == "Needs open ground")
		assert(why({ water = true }) == "Not in water")
		assert(why({ slope = 21 }) == "Too steep")
		assert(why({ overlap = true }) == "In the way")
		assert(why({ mine = C.PerPlayer }) == "You have too many pieces")
		assert(why({ team = C.PerTeam }) == "Your team has too many pieces")
	end,
	["slopes: level is 0, a rise equal to the span is 45, the steepest pair wins"] = function()
		assert(near(B.slope(3, 3, 4), 0) and near(B.slope(0, 4, 4), 45) and B.slope(0, 1, 0) == 90)
		-- 2 rows x 3 columns, 4 apart; one step of 4 between columns 2 and 3 in row 2
		assert(near(B.steepest({ 0, 0, 0, 0, 0, 4 }, 2, 4, 4), 45))
		assert(near(B.steepest({ 1, 1, 1, 1 }, 2, 4, 4), 0))
	end,
	["work: stages show as it rises, the last swing finishes it, never past"] = function()
		assert(B.stageOf(0, 8, 3) == 0 and B.stageOf(3, 8, 3) == 1 and B.stageOf(8, 8, 3) == 3)
		assert(B.stageOf(100, 8, 3) == 3 and B.stageOf(-1, 8, 3) == 0 and B.stageOf(0, 0, 3) == 3)
		local w, gone = B.swing(7, 8, true)
		assert(w == 8 and not gone)
		w, gone = B.swing(8, 8, true)
		assert(w == 8 and not gone)
	end,
	["an enemy's swings take it down, the last one removes it"] = function()
		local w, gone = B.swing(2, 8, false)
		assert(w == 1 and not gone)
		w, gone = B.swing(1, 8, false)
		assert(w == 0 and gone)
		w, gone = B.swing(0, 8, false) -- a blueprint with no work yet
		assert(w == 0 and gone)
	end,
	["swings faster than the dig are ignored"] = function()
		assert(not B.tooSoon(10, nil, 0.85, 0.8))
		assert(B.tooSoon(10.5, 10, 0.85, 0.8) and not B.tooSoon(10.7, 10, 0.85, 0.8))
	end,
	["a voxel column shaped to a height: cut and filled, or only cut"] = function()
		-- 4 voxels of 4 from y = 0
		local col = { 1, 1, 1, 0.5 }
		local out = B.shapeColumn(col, 0, 4, 6, false) -- the first voxel full: its centre 2 + 4 = 6
		assert(out[1] == 1 and out[2] == 0 and out[3] == 0 and out[4] == 0)
		local filled = B.shapeColumn({ 0, 0, 0, 0 }, 0, 4, 8, false)
		assert(filled[1] == 1 and near(filled[2], 0.5) and filled[3] == 0)
		local cut = B.shapeColumn({ 0, 0, 0, 0 }, 0, 4, 8, true)
		assert(cut[2] == 0, "only cutting never fills")
		assert(near(B.columnTop({ 1, 1, 0.5, 0 }, 0, 4) :: number, 12) and B.columnTop({ 0, 0 }, 0, 4) == nil)
	end,
	["sandbag courses: bonded rows, the loophole left out, all inside the wall"] = function()
		local high = B.piece("HighWall", C.Pieces) :: any
		local bags = B.sandbags(high)
		local middle = (high.columns + 1) // 2
		local rows = {}
		for _, b in bags do
			assert(not (b.column == middle and b.row == high.loophole), "the loophole is open")
			assert(b.x - b.width / 2 >= -high.width / 2 - 1e-6 and b.x + b.width / 2 <= high.width / 2 + 1e-6)
			rows[b.row] = (rows[b.row] or 0) + 1
		end
		assert(rows[1] == high.columns and rows[2] == high.columns * 2, "odd rows whole bags, even rows halves")
		assert(rows[high.loophole] == high.columns * 2 - 2)
	end,
	["the wire: inside its box, harm only while moving"] = function()
		assert(B.inBox(0, 0, 0, 12, 2.5, 3) and not B.inBox(0, 0, 1.6, 12, 2.5, 3))
		assert(B.wireHarm(0.5, 1, C.Wire) == 0 and near(B.wireHarm(5, 0.25, C.Wire), C.Wire.damage / 4))
		assert(C.Wire.speed < M.Movement.CrouchSpeed)
	end,
	["trenches v2: fixed segments, the leftover blended or a partial segment"] = function()
		local T = C.Trench
		assert(T.block == 8)
		local b = B.planBlocks(56, 8, T.minBlock) :: any
		assert(#b == 7 and near(b[7].to, 56) and near(b[1].to - b[1].from, 8), "whole segments")
		b = B.planBlocks(59, 8, T.minBlock) :: any
		assert(#b == 7 and near(b[7].to - b[7].from, 11), "3 left over (under half) blends into the last")
		b = B.planBlocks(60, 8, T.minBlock) :: any
		assert(#b == 8 and near(b[8].to - b[8].from, 4) and near(b[7].to, 56), "4 left over is a partial segment")
		b = B.planBlocks(5, 8, T.minBlock) :: any
		assert(#b == 1 and near(b[1].to, 5), "shorter than a segment: one partial")
		assert(B.planBlocks(1, 8, T.minBlock) == nil)
	end,
	["trenches v2: the shape: floor, walls walkable but steep, banks"] = function()
		local T = C.Trench
		local top = B.trenchTop(T)
		assert(near(top, T.floor + T.depth / math.tan(math.rad(T.wallAngle))))
		assert(T.wallAngle > 48 and T.wallAngle < 70, "between the first walls (70) and the walkable 48")
		assert(T.spacing >= 2 * (top + T.bank.width), "two trenches' parapets and banks don't overlap")
		assert(T.depth >= M.Cover.FullCoverMin, "full cover on the floor")
		assert(B.trenchProfile(0, 1, T) == -T.depth and B.trenchProfile(T.floor, 1, T) == -T.depth)
		assert(near(B.trenchProfile((T.floor + top) / 2, 1, T) :: number, -T.depth / 2))
		local bank = B.trenchProfile(top + T.bank.width / 2, 1, T) :: number
		assert(near(bank, T.bank.height))
		assert(B.trenchProfile(top + T.bank.width + 0.1, 1, T) == nil and B.trenchProfile(1, 0, T) == nil)
		assert(near(B.trenchProfile(0, 1 / 3, T) :: number, -T.depth / 3), "a third dug")
	end,
	["trenches v2: a bullet meeting the ground in a square's hole, walls or banks hits it"] = function()
		local T = C.Trench
		local s = T.shotSlack
		local edge = B.trenchTop(T) + T.bank.width
		assert(B.inTrenchGround(0, -T.depth, T, s), "the floor")
		assert(B.inTrenchGround(T.floor + 0.5, -T.depth + 1, T, s), "the foot of a wall")
		assert(B.inTrenchGround(edge, T.bank.height, T, s), "the bank's far edge")
		assert(B.inTrenchGround(edge + s - 0.01, 0, T, s), "within the slack")
		assert(not B.inTrenchGround(edge + s + 0.01, 0, T, s), "the meadow past it")
		assert(not B.inTrenchGround(2, -T.depth - s - 0.01, T, s), "deep under it")
		assert(not B.inTrenchGround(2, T.bank.height + s + 0.01, T, s), "a hill over it")
		assert(s > 0 and s <= 4)
	end,
	["trenches v2: reach along a block, past a joined end, round a dead end"] = function()
		local shape = { length = 12, extA = 4, extB = 0, deadA = false, deadB = true }
		assert(B.trenchReach(6, -2, shape, 3) == 2)
		assert(B.trenchReach(-3, 1, shape, 3) == 1 and B.trenchReach(-5, 1, shape, 3) == nil, "joined: on by its reach")
		assert(B.trenchReach(14, 1, shape, 3) == 5, "dead end: the floor's edge plus the distance past it")
		assert(near(B.trenchReach(15, 7, shape, 3) :: number, 3 + 5), "round the corner")
	end,
	["trenches v2: a square's HP: five Build swings dig it, Destroy swings fill it, blasts by pressure"] = function()
		local H = C.Trench.hp
		local hp = 0
		for _ = 1, 4 do
			hp = B.trenchSwing(hp, H.max, H.swing, true)
		end
		assert(hp < H.max, "four swings aren't enough")
		hp = B.trenchSwing(hp, H.max, H.swing, true)
		assert(hp == H.max, "five swings dig a square")
		local gone
		hp, gone = B.trenchSwing(hp, H.max, H.swing, false)
		assert(hp == H.max - H.swing and not gone)
		hp, gone = B.trenchSwing(10, H.max, H.swing, false)
		assert(hp == 0 and gone)
	end,
	["trenches v2: a built square is buried by what it loses: a little at 80%, nearly level at 5-10%"] = function()
		local H = C.Trench.hp
		assert(near(B.trenchDepth(H.max / 2, false, H), 0.5), "digging: depth is the HP's share")
		assert(B.trenchDepth(H.max - H.destroy, true, H) == 1, "a swing's damage doesn't show")
		local at80 = B.trenchDepth(80, true, H)
		assert(at80 > 0.75 and at80 < 0.9, `80%: a little filled ({at80})`)
		assert(B.trenchDepth(10, true, H) < 0.12 and B.trenchDepth(0, true, H) == 0, "10%: nearly level")
		assert(H.destroy < H.swing, "much harder to break than to dig")
	end,
	["trenches v2: a new trench keeps its distance from others unless it joins one"] = function()
		local S = C.Trench.spacing
		local other = { { 0, 0, 24, 0 } }
		assert(B.tooClose(0, S - 1, 24, S - 1, false, false, other, S), "alongside, too near")
		assert(not B.tooClose(0, S + 1, 24, S + 1, false, false, other, S), "far enough")
		-- a branch off its side: starts at the wall and runs out; only its first `spacing` studs may be near
		local w = C.Trench.floor
		assert(not B.tooClose(12, w, 12, w + 30, true, false, other, S), "a branch off the side")
		assert(B.tooClose(12, w, 12, w + 30, false, false, other, S), "the same, not joined")
		-- leaving an end but bending back alongside
		assert(B.tooClose(24, 0, 4, S - 4, true, false, other, S), "doubling back alongside")
	end,
	["trenches v2: a side wall keeps to the longest stretch clear of other trenches"] = function()
		local a, b = B.longestFree({ true, false, false, true, false, false, false, true })
		assert(a == 5 and b == 7, "the longest run")
		a, b = B.longestFree({ false, false, false })
		assert(a == 1 and b == 3, "all clear")
		assert(B.longestFree({ true, true }) == nil, "all blocked")
	end,
	["trenches v2: each square rolls its walls and floor, wood walls now and then but never twice in a row"] = function()
		local P = C.Trench.pieces
		local wood, total, prev = 0, 0, nil
		local seen = {}
		for seed = 1, 400 do
			local r = B.trenchPieces(seed * 7919, prev, P)
			local again = B.trenchPieces(seed * 7919, prev, P)
			assert(
				r.walls[1] == again.walls[1] and r.floor == again.floor and r.flip == again.flip,
				"same seed, same roll"
			)
			assert(r.floor >= 1 and r.floor <= P.floors)
			assert(not table.find(P.wood, r.ends[1]) and not table.find(P.wood, r.ends[2]), "dead ends are plain")
			for side = 1, 2 do
				local w = r.walls[side]
				assert(w >= 1 and w <= P.walls)
				seen[w] = true
				total += 1
				if table.find(P.wood, w) then
					wood += 1
					local before = prev and B.trenchPieces(prev, nil, P)
					assert(not (before and table.find(P.wood, before.walls[side])), "no wood twice in a row on a side")
				end
			end
			prev = seed * 7919
		end
		for i = 1, P.walls do
			assert(seen[i], `wall {i} comes up`)
		end
		assert(wood / total > 0.1 and wood / total < P.woodChance + 0.05, `wood walls now and then ({wood} of {total})`)
	end,
	["built things: each weapon takes its share, grenades and staffs least, the howitzer most"] = function()
		local S = C.Structures
		local function at(key: string?, kg: number, d: number): number
			return B.structureHit(d, B.structureSource(key, kg, S), S.edge)
		end
		assert(
			at("grenade", 0.1, 0) < 5 and at("grenade", 0.1, 0) > 0,
			"a grenade, even inside the trench, only wears it"
		)
		assert(at("staff3", 10, 0) < 5, "a full staff beam is no bigger than a grenade or so, for all its 10 kg")
		local field = at(nil, 2.5, 1)
		assert(field > 25 and field < 40, `a few field gun shells bury it ({field})`)
		local howitzer = at(nil, 340, 3)
		assert(howitzer >= 90 and howitzer < 100, `the howitzer buries it but leaves some ({howitzer})`)
		assert(
			at("bullet", 0, 0) > 0 and at("bullet", 0, 0) < 0.5 and at("bullet", 0, 1) == 0,
			"a bullet: on it, a little"
		)
		assert(at("grenade", 0.1, S.grenade.reach) == 0, "nothing past its reach")
		assert(near(at("grenade", 0.1, (S.edge + S.grenade.reach) / 2), S.grenade.hit / 2), "fading out")
		assert(B.structureHit(0, S.field, S.edge, S.field.wire) >= 100, "a shell cuts wire")
	end,
	["trenches v2: a segment through a rectangle"] = function()
		-- a rectangle at the origin along x, 6 long each way, 2 across each way; a segment along x through it
		local t0, t1 = B.clipRect(-10, 0, 10, 0, 0, 0, 1, 0, 6, 2)
		assert(t0 and t1 and near(t0, 0.2) and near(t1, 0.8))
		assert(B.clipRect(-10, 5, 10, 5, 0, 0, 1, 0, 6, 2) == nil, "passes beside it")
		-- turned 90 degrees: the rectangle along z
		t0, t1 = B.clipRect(-10, 0, 10, 0, 0, 0, 0, 1, 6, 2)
		assert(t0 and t1 and near(t0, 0.4) and near(t1, 0.6))
		t0 = B.clipRect(0, 0, 1, 0, 0, 0, 1, 0, 6, 2)
		assert(t0 == 0, "starting inside")
	end,
}
