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
	["the trench profile: Metrics depth, floor, firestep room, banks and ramps"] = function()
		local seg = { length = 12, depth = M.Trench.Depth, share = 1, openA = false, openB = false, exit = false }
		local fw = M.Trench.FirestepWidth
		assert(T.front - T.back == M.Trench.FloorWidth, "the floor is Metrics wide")
		assert(B.trenchAt(6, 0, seg, T, fw) == -M.Trench.Depth)
		assert(B.trenchAt(6, T.front + fw, seg, T, fw) == -M.Trench.Depth, "the firestep's room is cut")
		local m = T.cutMargin
		assert(B.trenchAt(6, T.back - m + 0.1, seg, T, fw) == -M.Trench.Depth, "cut a little wider than the planks")
		local bank = B.trenchAt(6, T.front + fw + m + T.parapet.width / 2, seg, T, fw) :: number
		assert(near(bank, T.parapet.height), "the parapet peaks in its middle")
		assert((B.trenchAt(6, T.back - m - T.parados.width / 2, seg, T, fw) :: number) > 0, "a parados behind")
		assert(B.trenchAt(6, 40, seg, T, fw) == nil)
		-- joined ends: the floor runs on past them
		assert(B.trenchAt(-T.overlap + 0.1, 0, seg, T, fw) == -M.Trench.Depth)
		assert(B.trenchAt(12 + T.overlap - 0.1, 0, seg, T, fw) == -M.Trench.Depth)
		assert(B.trenchAt(-T.overlap - 0.5, 0, seg, T, fw) == nil)
		-- an open end ramps up out of it, only cutting
		seg.openA = true
		local mid = (T.back + T.front + fw) / 2
		local h, cutOnly = B.trenchAt(-T.ramp.length / 2, mid, seg, T, fw)
		assert(h and near(h, -M.Trench.Depth / 2) and cutOnly)
		assert(B.trenchAt(-T.ramp.length - 0.5, mid, seg, T, fw) == nil)
		-- the exit piece: a ramp out of the back in its middle
		seg.exit = true
		h, cutOnly = B.trenchAt(6, T.back - m - T.ramp.length / 2, seg, T, fw)
		assert(h and near(h, -M.Trench.Depth / 2) and cutOnly)
		-- a third dug: a third deep, banks a third high
		local part =
			{ length = 12, depth = M.Trench.Depth / 3, share = 1 / 3, openA = false, openB = false, exit = false }
		assert(near(B.trenchAt(6, 0, part, T, fw) :: number, -M.Trench.Depth / 3))
		local low = B.trenchAt(6, T.front + fw + T.cutMargin + T.parapet.width / 2, part, T, fw) :: number
		assert(near(low, T.parapet.height / 3))
		assert(
			B.trenchAt(6, 0, { length = 12, depth = 0, share = 0, openA = false, openB = false, exit = false }, T, fw)
				== nil
		)
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
	["trench lines: every point within the exit spacing of a way out"] = function()
		local L = C.Trench.length
		-- one segment: both ends open
		assert(near(B.farthestFromExit({ { a = 1, b = 2, length = L } }), L / 2))
		-- five in a line (60): the middle is 30 from either end
		local line = {}
		for i = 1, 5 do
			table.insert(line, { a = i, b = i + 1, length = L })
		end
		assert(near(B.farthestFromExit(line), 30) and B.farthestFromExit(line) <= M.Trench.MaxExitSpacing)
		-- six: 36, too far, unless one is an exit piece
		table.insert(line, { a = 6, b = 7, length = L })
		assert(near(B.farthestFromExit(line), 36))
		line[3].exit = true
		assert(B.farthestFromExit(line) <= M.Trench.MaxExitSpacing)
		-- a closed loop of four with no exit piece has no way out
		local loop = {
			{ a = 1, b = 2, length = L },
			{ a = 2, b = 3, length = L },
			{ a = 3, b = 4, length = L },
			{ a = 4, b = 1, length = L },
		}
		assert(B.farthestFromExit(loop) == math.huge)
		loop[1].exit = true
		assert(near(B.farthestFromExit(loop), 24))
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
	["a cave-in costs work by the share of the trench caved"] = function()
		assert(B.caveWork(8, 8, 6, 12) == 4 and B.caveWork(8, 8, 0, 12) == 8 and B.caveWork(2, 8, 12, 12) == 0)
	end,
}
