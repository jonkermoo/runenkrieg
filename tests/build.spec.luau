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
	["a cave-in covers only the chord inside the segment"] = function()
		assert(near(B.caveSpan(6, 0, 3, 12), 6))
		assert(near(B.caveSpan(0, 0, 3, 12), 3), "at an end (a joint): only its own half")
		assert(near(B.caveSpan(6, 6.2, 9.1, 12), 12) and B.caveSpan(6, 9.1, 9.1, 12) == 0)
		assert(near(B.caveSpan(12, 6.2, 9.1, 12), math.sqrt(9.1 ^ 2 - 6.2 ^ 2)), "the joint case, Studio round 1")
		assert(near(B.caveSpan(-20, 0, 3, 12), 0))
	end,
	["trenches v2: blocks of a plan, all the same length, none too short"] = function()
		local T = C.Trench
		local b = B.planBlocks(60, T.block, T.minBlock) :: any
		assert(#b == 5 and near(b[5].to, 60) and near(b[1].to - b[1].from, 12))
		b = B.planBlocks(30, T.block, T.minBlock) :: any
		assert(#b == 3 and near(b[1].to, 10))
		b = B.planBlocks(8, T.block, T.minBlock) :: any
		assert(#b == 1 and near(b[1].to, 8))
		assert(B.planBlocks(5, T.block, T.minBlock) == nil)
		assert(T.maxPlan / T.block == 5)
	end,
	["trenches v2: the shape: floor, walls too steep to walk, banks"] = function()
		local T = C.Trench
		local top = B.trenchTop(T)
		assert(near(top, T.floor + T.depth / math.tan(math.rad(T.wallAngle))))
		assert(T.wallAngle > M.Movement.MaxSlopeAngle, "the walls can't be walked up")
		assert(T.depth >= M.Cover.FullCoverMin, "full cover on the floor")
		assert(B.trenchProfile(0, 1, T) == -T.depth and B.trenchProfile(T.floor, 1, T) == -T.depth)
		assert(near(B.trenchProfile((T.floor + top) / 2, 1, T) :: number, -T.depth / 2))
		local bank = B.trenchProfile(top + T.bank.width / 2, 1, T) :: number
		assert(near(bank, T.bank.height))
		assert(B.trenchProfile(top + T.bank.width + 0.1, 1, T) == nil and B.trenchProfile(1, 0, T) == nil)
		assert(near(B.trenchProfile(0, 1 / 3, T) :: number, -T.depth / 3), "a third dug")
	end,
	["trenches v2: reach along a block, past a joined end, round a dead end"] = function()
		local shape = { length = 12, extA = 4, extB = 0, deadA = false, deadB = true }
		assert(B.trenchReach(6, -2, shape, 3) == 2)
		assert(B.trenchReach(-3, 1, shape, 3) == 1 and B.trenchReach(-5, 1, shape, 3) == nil, "joined: on by its reach")
		assert(B.trenchReach(14, 1, shape, 3) == 5, "dead end: the floor's edge plus the distance past it")
		assert(near(B.trenchReach(15, 7, shape, 3) :: number, 3 + 5), "round the corner")
	end,
	["trenches v2: stages by work"] = function()
		local st = C.Trench.stages
		assert(B.trenchStage(0, st) == 0 and B.trenchStage(3, st) == 1 and B.trenchStage(7, st) == 2)
		assert(B.trenchStage(C.Trench.work, st) == #st and st[#st] == C.Trench.work)
		assert(#C.Trench.depthByStage == #st and C.Trench.depthByStage[#st] == 1)
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
	["trenches v2: a blast never takes more than half a block"] = function()
		assert(B.caveLoss(8, 12, 12, 0.5) == 4 and B.caveLoss(8, 3, 12, 0.5) == 2 and B.caveLoss(8, 0, 12, 0.5) == 0)
		assert(C.Trench.cave.maxShare <= 0.5)
	end,
}
