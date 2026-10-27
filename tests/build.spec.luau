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
	["an admin dig step works its share of the whole, rounded up, never less than a normal swing"] = function()
		assert(B.digAmount(20, 100, nil) == 20 and B.digAmount(20, 100, 0) == 20)
		assert(B.digAmount(1, 20, 0.25) == 5 and B.digAmount(1, 40, 0.1) == 4 and B.digAmount(1, 3, 0.1) == 1)
		assert(B.digAmount(4, 100, 0.5) == 50 and B.digAmount(20, 100, 0.1) == 20)
		local w, gone = B.swing(0, 20, true, B.digAmount(1, 20, 1))
		assert(w == 20 and not gone)
		w, gone = B.swing(20, 20, false, B.digAmount(1, 20, 0.5))
		assert(w == 10 and not gone)
		w, gone = B.swing(10, 20, false, 10)
		assert(w == 0 and gone)
	end,
	["every piece has a key, a kind, a name and work; keys are unique"] = function()
		local seen = {}
		for _, p in C.Pieces do
			assert(type(p.key) == "string" and not seen[p.key], p.key)
			seen[p.key] = true
			assert(
				p.kind == "Trench"
					or p.kind == "Sandbags"
					or p.kind == "Wire"
					or p.kind == "Gun"
					or p.kind == "Hesco"
					or p.kind == "Bridge",
				p.key
			)
			-- (every piece but a trench square and the old sandbag walls is on HP out of 100, Rules.hpOf)
			local h = B.hpOf(p, C)
			assert(type(p.name) == "string" and (h ~= nil or p.work >= 1), p.key)
			assert(h == nil or (h.max == 100 and h.place >= 0 and h.swing > 0 and h.destroy > 0), p.key)
		end
		assert(
			B.piece("SandbagPile", C.Pieces) ~= nil and B.piece("Nope", C.Pieces) == nil and B.piece(5, C.Pieces) == nil
		)
		assert(B.piece("LowWall", C.Pieces) == nil and B.piece("HighWall", C.Pieces) == nil, "the old walls are gone")
	end,
	["hesco: 6 x 6, just over a soldier, only the dirt is cover; four stages on HP: laid standing, gone at 0"] = function()
		local A = require("../src/shared/Config/Assets")
		local h = B.piece("Hesco", C.Pieces) :: any
		assert(h and h.kind == "Hesco" and h.width == 6 and h.depth == 6 and A.Entries[h.asset] ~= nil)
		-- (user 2026-10-27: "just barely the players height")
		assert(h.height > M.Character.Height and h.height < M.Character.Height + 0.25, "just over a standing soldier")
		-- (user 2026-10-27: "stage 1 and 2 barriers will provide little to no protection"): the dirt at each stage
		local function dirt(stage: number): number
			return h.height * math.max(stage - 1, 0) / (h.stages - 1)
		end
		assert(
			dirt(1) == 0
				and dirt(2) <= M.Cover.HopableLedgeMax
				and dirt(3) >= M.Cover.LowCoverMin
				and dirt(h.stages) == h.height
		)
		-- on HP (user 2026-10-27: "all strucuttres use HP rule", "stage 1 should always be when its placed")
		local hp = C.Hesco.hp
		-- (user round 5: "hesco barriers should still start at 0 HP. make another flat model for when it has just been placed")
		assert(h.stages == 4 and hp.place == 0 and B.hescoStage(hp.place, hp.max, 4) == 0, "laid: lying flat at 0 HP")
		assert(B.hescoStage(hp.swing, hp.max, 4) == 1, "a swing in: the empty perimeter stands")
		assert(B.hescoStage(hp.max, hp.max, 4) == 4, "full")
		assert(B.hescoStage(hp.max * 0.6, hp.max, 4) == 3, "worn: the dirt slumps a stage")
		assert(B.hescoStage(0.01, hp.max, 4) == 1, "the perimeter stands while it has any HP")
		local v, gone, swings = hp.place, false, 0
		while v < hp.max do
			v, gone = B.hpSwing(v, true, hp)
			swings += 1
		end
		assert(v == hp.max and not gone and swings >= 4 and swings <= 8, `built up in a few swings ({swings})`)
		v, gone = B.hpSwing(hp.destroy, false, hp)
		assert(v == 0 and gone, "a Destroy swing takes the last of it")
		v = B.hpSwing(hp.max, false, hp, 40)
		assert(v == hp.max - 40, "an admin step")
		v, gone = B.hpSwing(0, false, hp)
		assert(v == 0 and gone, "a Destroy swing at a barrier just laid takes it away")
		-- the ground it keeps from craters (user round 5: "the ground below the barrier and the surround (the hitbox)")
		local m = C.Hesco.ground
		assert(B.onFootprint(0, 0, 6, 6, m) and B.onFootprint(3 + m, -3 - m, 6, 6, m))
		assert(not B.onFootprint(3 + m + 0.01, 0, 6, 6, m) and not B.onFootprint(0, -3 - m - 0.01, 6, 6, m))
		assert(C.Hesco.soak > 0 and C.Hesco.soak < 1, "tougher than sandbags")
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
		assert(why({ gunGap = true }) == "Too close to another gun")
		assert(why({ nearTrench = true }) == "Too close to a trench")
		assert(why({ mine = C.PerPlayer }) == "You have too many pieces")
		assert(why({ team = C.PerTeam }) == "Your team has too many pieces")
	end,
	["guns: one per kind within its spacing, any two their clears apart; both teams build both"] = function()
		local field = B.piece("FieldGun", C.Pieces) :: any
		local how = B.piece("Howitzer", C.Pieces) :: any
		assert(field.spacing == 60 and how.spacing == 120)
		assert(not B.gunsClear(59, true, 60, 9, 9) and B.gunsClear(60, true, 60, 9, 9))
		assert(B.gunsClear(50, false, 60, 9, 36) and not B.gunsClear(44, false, 60, 9, 36))
		for _, kit in { "uniform1", "uniform2", "uniform3" } do
			assert(C.Guns.paint[kit] ~= nil, kit)
		end
	end,
	["guns: on HP, laid at 0, the same swings as before to stand, the pit deepens by stage"] = function()
		for key, swings in { FieldGun = 20, Howitzer = 40 } do
			local p = B.piece(key, C.Pieces) :: any
			local h = B.hpOf(p, C) :: B.Hp
			assert(h.max == 100 and h.place == 0, key)
			local hp, gone, n = h.place, false, 0
			while hp < h.max do
				hp, gone = B.hpSwing(hp, true, h)
				n += 1
			end
			assert(n == swings and not gone, `{key}: {swings} Build swings ({n})`)
			n = 0
			while not gone do
				hp, gone = B.hpSwing(hp, false, h)
				n += 1
			end
			assert(n == swings, `{key}: as many Destroy swings take it apart while it is built ({n})`)
			assert(B.pitShare(false, h.place, h.max, p.stages) == 0, "laid: the pit not dug yet")
		end
		assert(B.pitShare(true, 0, 100, 8) == 1, "a gun that has stood keeps its pit, a wreck at 0 too")
		assert(near(B.pitShare(false, 50, 100, 8), 0.5) and near(B.pitShare(false, 99, 100, 8), 7 / 8))
		-- a standing gun at 0 (a wreck weapons left): the next Destroy swing takes it away
		local _, gone = B.hpSwing(0, false, { max = 100 }, 10)
		assert(gone)
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
	["the shovel's strikes: the shortest gap is a chip let go of and a dig started at once"] = function()
		local dig = { length = 2.6, strike = 0.45, rest = 1.82 }
		local chip = { length = 1.5, strike = 0.5, rest = 1.0 }
		assert(near(B.strikeGap({ dig }), 1.82), "a dig let go of and another started")
		assert(near(B.strikeGap({ chip }), 1.0))
		assert(near(B.strikeGap({ dig, chip }), 0.95), "chip rest 1.0 - strike 0.5 + dig strike 0.45")
		assert(near(B.strikeGap({ { length = 0.5, strike = 0.1, rest = 0.9 } }), 0.5), "never longer than a swing")
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
	["the wire: inside its box, harm only while moving"] = function()
		assert(B.inBox(0, 0, 0, 12, 2.5, 3) and not B.inBox(0, 0, 1.6, 12, 2.5, 3))
		assert(B.wireHarm(0.5, 1, C.Wire) == 0 and near(B.wireHarm(5, 0.25, C.Wire), C.Wire.damage / 4))
		assert(C.Wire.speed < M.Movement.CrouchSpeed)
	end,
	["the wire: only the enemy is hurt, its own team only slowed"] = function()
		assert(B.wireHarm(5, 0.25, C.Wire, true) == 0, "a teammate moving through it")
		assert(B.wireHarm(5, 0.25, C.Wire, false) > 0, "an enemy moving through it")
	end,
	["footprints: overlapping pieces are refused, side by side and apart are fine"] = function()
		local function box(x: number, z: number, deg: number, w: number, d: number): B.Footprint
			local r = math.rad(deg)
			return { x = x, z = z, rx = math.cos(r), rz = math.sin(r), width = w, depth = d }
		end
		local wire = box(0, 0, 0, 8, 4)
		assert(B.footprintsOverlap(wire, box(0, 0, 0, 8, 4)), "one wire on another")
		assert(B.footprintsOverlap(wire, box(3, 1, 90, 8, 4)), "crossed over it")
		assert(B.footprintsOverlap(wire, box(6, 0, 0, 6, 2.2)), "a sandbag wall reaching into its end")
		assert(not B.footprintsOverlap(wire, box(8, 0, 0, 8, 4)), "end to end, touching")
		assert(not B.footprintsOverlap(wire, box(0, 4.5, 0, 8, 4)), "side by side, apart")
		assert(not B.footprintsOverlap(wire, box(9, 5, 45, 8, 4)), "turned, clear of its corner")
	end,
	["the wire: anyone moving through rattles it, standing still doesn't"] = function()
		assert(B.wireRattles(C.Wire.speed, C.Wire), "a teammate or enemy wading through")
		assert(not B.wireRattles(0, C.Wire) and not B.wireRattles(C.Wire.moving, C.Wire), "standing in it")
		assert(#C.Wire.sounds >= 1)
		for _, s in C.Wire.sounds do
			assert(s.stop > s.start and s.fade < s.stop - s.start, "trimmed with room to fade")
		end
	end,
	["the wire: 8 x 4, 3/5 of a soldier high, too high to hop, 2 swings stand it"] = function()
		local w = B.piece("Wire", C.Pieces) :: any
		local h = C.Wire.hp
		assert(w.width == 8 and w.depth == 4 and h.place == 0)
		local hp, n = h.place, 0
		while B.wireLook(hp, h.max, C.Wire) ~= "Standing" do
			hp = B.hpSwing(hp, true, h)
			n += 1
		end
		assert(n == 2, `2 Build swings stand it ({n})`)
		assert(near(w.height, M.Character.Height * 3 / 5, 0.05), "3/5 of a soldier")
		assert(w.height > M.Movement.JumpHeight, "can't be hopped")
	end,
	["the wire: looks by HP alone"] = function()
		local W, hp = C.Wire, C.Wire.hp.max
		assert(B.wireLook(0, hp, W) == "Bundle", "laid at 0, it is on the ground at once, before any swing")
		assert(B.wireLook(hp * W.stand - 1, hp, W) == "Bundle", "low: on the ground, doing nothing")
		assert(B.wireLook(hp * W.stand, hp, W) == "Standing" and B.wireLook(hp, hp, W) == "Standing")
	end,
	["the wire: a shake wobbles within its size and comes to rest"] = function()
		local W = C.Wire
		local most = 0
		for i = 0, 100 do
			most = math.max(most, math.abs(B.wireShake(W.shake * i / 100, W)))
		end
		assert(most > W.wobble * 0.3 and most <= W.wobble + 1e-9, "it moves, no more than its wobble")
		assert(B.wireShake(W.shake, W) == 0 and B.wireShake(-0.1, W) == 0, "still outside the shake")
		assert(math.abs(B.wireShake(W.shake * 0.99, W)) < W.wobble * 0.01, "it dies away")
	end,
	["the wire: 2 Destroy swings, knocked down then gone; its team's Build swings stand it back up"] = function()
		local W, h = C.Wire, C.Wire.hp
		local left, gone = B.hpSwing(h.max, false, h)
		assert(not gone and B.wireLook(left, h.max, W) == "Bundle", "one swing knocks it down")
		local up = B.hpSwing(left, true, h)
		assert(B.wireLook(up, h.max, W) == "Standing", "a Build swing stands it back up")
		left, gone = B.hpSwing(left, false, h)
		assert(gone and left == 0, "the second swing takes it away")
		assert(B.hpSwing(h.max, true, h) == h.max, "never over its max")
		_, gone = B.hpSwing(h.place, false, h)
		assert(gone, "a Destroy swing at a wire just laid takes it away")
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
		assert(T.wallAngle > 48 and T.wallAngle < 70, "between the first walls (70) and 48")
		assert(
			T.wallAngle < M.Movement.MaxSlopeAngle,
			"the walls can be walked up, hard (the dirt heap stops you at the top)"
		)
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
	["trenches v2: a heap's thin skirt is laid only where the ground holds it, never hanging in the air"] = function()
		local hang = C.Trench.apronHang
		-- flat ground: the skirt's underside sunk below it
		assert(B.thinPieceSits(9.2, { 10, 10, 10, 10 }, hang), "sunk in flat ground")
		-- the ground just under it, within the slack
		assert(B.thinPieceSits(9.2, { 9.2 - hang * 0.5, 10 }, hang), "a hair over the ground")
		-- the trench pokes out: the ground falls away under its far edge
		assert(not B.thinPieceSits(9.2, { 10, 10, 7.5, 6 }, hang), "over ground falling away")
		-- no ground under one point at all
		assert(not B.thinPieceSits(9.2, { 10, -math.huge }, hang), "over nothing")
		assert(not B.thinPieceSits(9.2, {}, hang), "no samples, no skirt")
	end,
	["trenches v2: a side wall keeps to the stretches clear of other trenches, either side of a branch"] = function()
		local runs = B.freeRuns({ true, false, false, true, false, false, false, true })
		assert(#runs == 2 and runs[1][1] == 2 and runs[1][2] == 3 and runs[2][1] == 5 and runs[2][2] == 7, "both runs")
		runs = B.freeRuns({ false, false, false })
		assert(#runs == 1 and runs[1][1] == 1 and runs[1][2] == 3, "all clear")
		assert(#B.freeRuns({ true, true }) == 0, "all blocked")
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
		-- (user 2026-10-27: "about 5-6 should be able to sink/destroy a trench")
		local beams = math.ceil(C.Trench.hp.max / (C.Trench.hp.max * at("staff3", 10, 0) / 100))
		assert(beams >= 5 and beams <= 6, `5-6 full staff beams bury a trench ({beams})`)
		assert(at("staff1", 1, 0) < at("staff2", 1, 0) and at("staff2", 1, 0) < at("staff3", 1, 0), "stage by stage")
		assert(at("staff3", 10, 0) < at(nil, 2.5, 0), "a full beam is still less than a field gun shell")
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
	["bridges: on HP, stage 1 when laid, two swings to whole, crossable until 0"] = function()
		local p = B.piece("Bridge", C.Pieces) :: any
		assert(p and p.kind == "Bridge")
		local h = C.Bridge.hp
		local need = h.max
		local w = h.place
		assert(w == 0 and B.bridgeStage(w, need) == 1, "laid at 0 HP: stage 1 down at once, crossable")
		w = B.trenchSwing(w, need, h.swing, true)
		assert(B.bridgeStage(w, need) == 2 and w < need, "a swing: stage 2")
		w = B.trenchSwing(w, need, h.swing, true)
		assert(w == need, "two: whole")
		local S = C.Structures
		local gone
		w, gone = B.bridgeHit(w, need, B.structureHit(0, S.grenade, S.edge, S.grenade.bridge))
		assert(not gone and B.bridgeStage(w, need) == 2, "a grenade: still every board (75%)")
		w, gone = B.bridgeHit(w, need, B.structureHit(0, S.grenade, S.edge, S.grenade.bridge))
		assert(not gone and B.bridgeStage(w, need) == 1, "two: down to stage 1 (50%), still crossable")
		w, gone = B.bridgeHit(w, need, B.structureHit(0, S.grenade, S.edge, S.grenade.bridge))
		assert(not gone and B.bridgeStage(w, need) == 1)
		w, gone = B.bridgeHit(w, need, B.structureHit(0, S.grenade, S.edge, S.grenade.bridge))
		assert(gone and w == 0, "four take it away")
		w, gone = B.bridgeHit(need, need, B.structureHit(1, S.field, S.edge, S.field.bridge))
		assert(gone, "one shell drops it")
		assert(B.structureHit(0, S.bullet, S.edge, S.bullet.bridge) == 0, "bullets pass the planks")
		-- Destroy swings take its HP: down to stage 1 at half, gone at 0
		w, gone = need, false
		local swings = 0
		while not gone do
			w, gone = B.trenchSwing(w, need, h.destroy, false)
			swings += 1
			if w > 0 then
				assert(B.bridgeStage(w, need) == (if w > need / 2 then 2 else 1))
			end
		end
		assert(swings == math.ceil(need / h.destroy), `{swings} Destroy swings take a whole bridge away`)
		w = B.trenchSwing(30, need, h.swing, true)
		assert(w == math.min(30 + h.swing, need), "its team's Build swings repair it")
		local _, gone0 = B.trenchSwing(h.place, need, h.destroy, false)
		assert(gone0, "a Destroy swing at a bridge just laid takes it away")
	end,
	["bridges: only across a dug square joined straight on, a square apart"] = function()
		local b = C.Bridge
		local function spot(over: { [string]: any }): string?
			local s: any =
				{ found = true, dug = 100, ends = { "end", "end" }, bends = { 0, 0 }, teed = false, nearest = 99 }
			for k, v in over do
				s[k] = v
			end
			return B.bridgeSpot(s, b)
		end
		assert(spot({}) == nil, "a straight run, dug")
		assert(spot({ bends = { b.maxBend - 1, 0 } }) == nil, "a gentle bend")
		assert(spot({ found = false }) == "Needs a dug trench")
		assert(spot({ dug = b.dug - 1 }) == "Needs a dug trench", "not dug full")
		assert(spot({ ends = { "", "end" } }) == "Not at a dead end")
		assert(spot({ ends = { "end", "tee" } }) == "Not on a joint", "where it tees into another")
		assert(spot({ bends = { 0, b.maxBend + 5 } }) == "Not on a joint", "a sharp bend")
		assert(spot({ teed = true }) == "Not on a joint", "a trench joins its side")
		assert(spot({ nearest = 0 }) == "A bridge is already here")
		assert(spot({ nearest = C.Trench.block }) == "Too close to another bridge", "the next square")
		assert(spot({ nearest = 2 * C.Trench.block }) == nil, "one free square between")
		local ok = B.canPlace(placing({ piece = B.piece("Bridge", C.Pieces), spot = "Not on a joint" }))
		assert(not ok, "the spot's reason refuses it")
	end,
	["bridges: every layout and both ways round come up"] = function()
		local seen = {}
		for seed = 1, 60 do
			local v, turned = B.bridgeVariant(seed * 7919, C.Bridge.variants)
			assert(v >= 1 and v <= C.Bridge.variants)
			seen[`{v}{turned}`] = true
			assert(B.bridgeVariant(seed * 7919, C.Bridge.variants) == v, "same seed, same layout")
		end
		for v = 1, C.Bridge.variants do
			assert(seen[`{v}true`] and seen[`{v}false`], `layout {v} both ways`)
		end
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

	["the sandbag pile: on HP, stage 1 when laid, a bag a Build swing, ties with their bags, aimed fire clears it"] = function()
		local pile = assert(B.piece("SandbagPile", C.Pieces))
		local h = C.Sandbags.hp
		local n = #pile.bags
		assert(pile.kind == "Sandbags", "everyone builds it (Config/Classes small pieces)")
		assert(B.pileBag("Bag1", pile.bags) == 1 and B.pileBag("Bag3Cord", pile.bags) == 3)
		assert(B.pileBag("Origin", pile.bags) == nil and B.pileBag("Cord", pile.bags) == nil)
		assert(B.pileBag(pile.stage1.ground, pile.bags) == nil and B.pileBag(pile.stage1.sacks, pile.bags) == nil)
		assert(B.isPileCord("Bag2Cord") and not B.isPileCord("Bag2"))
		-- laid: stage 1, no bag yet (scraped ground, empty sacks); each Build swing fills the next; full HP all of them
		assert(h.place == 0 and B.pileBags(h.place, h.swing, n) == 0, "laid at 0 HP, stage 1")
		local hp, gone = h.place, false
		for bags = 1, n do
			hp, gone = B.hpSwing(hp, true, h)
			assert(B.pileBags(hp, h.swing, n) == bags and not gone, "a bag a swing")
		end
		assert(hp == h.max, "the last bag at full HP")
		assert(B.hpSwing(hp, true, h) == h.max, "never over its max")
		-- worn: bags come off as HP goes, a bag while any of its share is left, stage 1 at 0
		assert(B.pileBags(h.max - 1, h.swing, n) == n, "a scratch takes no bag")
		assert(B.pileBags(1, h.swing, n) == 1 and B.pileBags(0, h.swing, n) == 0 and B.pileBags(-5, h.swing, n) == 0)
		local left
		left, gone = B.hpSwing(h.destroy, false, h)
		assert(left == 0 and gone)
		left, gone = B.hpSwing(h.max, false, h)
		assert(left == h.max - h.destroy and not gone)
		assert(B.hpSwing(h.max, false, h, 50) == 50, "an admin dig step in place of a swing")
		assert(pile.height < M.Character.AimMuzzleHeight and pile.height >= M.Cover.LowCoverMin)
	end,
	["laid on the ground: the plane through the ground under it, its height and slope each way"] = function()
		-- a flat field: level at its height
		local flat = table.create(15, 4)
		local h, gx, gz = B.groundPlane(flat, 3, 5, 8, 4)
		assert(near(h, 4) and near(gx, 0) and near(gz, 0))
		-- rising 0.5 a stud along its width, 0.25 along its depth
		local tilted = {}
		for r = 1, 3 do
			for c = 1, 5 do
				local x, z = ((c - 1) / 4 - 0.5) * 8, ((r - 1) / 2 - 0.5) * 4
				tilted[(r - 1) * 5 + c] = 10 + 0.5 * x + 0.25 * z
			end
		end
		h, gx, gz = B.groundPlane(tilted, 3, 5, 8, 4)
		assert(near(h, 10) and near(gx, 0.5) and near(gz, 0.25))
	end,
	["every Hesco piece has its colour (a missing one hid the whole barrier, round 7)"] = function()
		local A = require("../src/shared/Config/Assets")
		local P = require("../src/shared/Config/Palette")
		local seen = 0
		for kind in string.gmatch(A.Entries.hesco.description, "(%u%a*)[%d<]") do
			assert(P.Build.Hesco[kind] ~= nil, `Palette.Build.Hesco.{kind}`)
			seen += 1
		end
		assert(seen >= 10, "the stage pieces are listed")
	end,
}
