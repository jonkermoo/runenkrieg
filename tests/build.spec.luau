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
			assert(p.kind == "Trench" or p.kind == "Sandbags" or p.kind == "Wire" or p.kind == "Gun", p.key)
			-- (a sandbag pile is built on HP, Config/Build.Sandbags.hp, not a count of swings)
			assert(type(p.name) == "string" and (p.kind == "Sandbags" or p.work >= 1), p.key)
		end
		assert(
			B.piece("SandbagPile", C.Pieces) ~= nil and B.piece("Nope", C.Pieces) == nil and B.piece(5, C.Pieces) == nil
		)
		assert(B.piece("LowWall", C.Pieces) == nil and B.piece("HighWall", C.Pieces) == nil, "the old walls are gone")
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
		assert(field.spacing == 60 and how.spacing == 120 and field.work == 20 and how.work == 40)
		assert(not B.gunsClear(59, true, 60, 9, 9) and B.gunsClear(60, true, 60, 9, 9))
		assert(B.gunsClear(50, false, 60, 9, 36) and not B.gunsClear(44, false, 60, 9, 36))
		for _, kit in { "uniform1", "uniform2", "uniform3" } do
			assert(C.Guns.paint[kit] ~= nil, kit)
		end
	end,
	["guns: stand at full work, stay until under standsFrom, the pit deepens by stage"] = function()
		local s = C.Guns.standsFrom
		assert(not B.gunStands(false, 39, 40, s) and B.gunStands(false, 40, 40, s))
		assert(
			B.gunStands(true, 31, 40, s) and not B.gunStands(true, 30, 40, s),
			"10 Destroy swings of 40 take it down"
		)
		assert(B.gunStands(true, 16, 20, s) and not B.gunStands(true, 15, 20, s), "5 of 20")
		assert(not B.gunStands(false, 35, 40, s), "a gun taken apart stands again only at full work")
		assert(B.pitShare(true, 30, 40, 8) == 1 and B.pitShare(false, 0, 40, 8) == 0)
		assert(near(B.pitShare(false, 20, 40, 8), 0.5) and near(B.pitShare(false, 39, 40, 8), 7 / 8))
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
	["the wire: 8 x 4, 3/5 of a soldier high, too high to hop, 2 swings"] = function()
		local w = B.piece("Wire", C.Pieces) :: any
		assert(w.width == 8 and w.depth == 4 and w.work == 2)
		assert(near(w.height, M.Character.Height * 3 / 5, 0.05), "3/5 of a soldier")
		assert(w.height > M.Movement.JumpHeight, "can't be hopped")
	end,
	["the wire: looks by work and HP"] = function()
		local W, hp = C.Wire, C.Structures.wireHP
		assert(B.wireLook(false, 0, 2, hp, hp, W) == "Bundle", "laid, it is on the ground at once, before any swing")
		assert(B.wireLook(false, 1, 2, hp, hp, W) == "Bundle")
		assert(B.wireLook(false, 2, 2, hp, hp, W) == "Standing")
		assert(B.wireLook(true, 2, 2, hp * W.broken, hp, W) == "Standing", "at half HP it still stands")
		assert(B.wireLook(true, 2, 2, hp * W.broken - 1, hp, W) == "Broken", "under half it is broken")
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
	["the wire: 2 Destroy swings, broken then gone; 1 Build swing stands it back up"] = function()
		local W, hp = C.Wire, C.Structures.wireHP
		local left, gone = B.wireSwing(hp, hp, false, W)
		assert(not gone and B.wireLook(true, 2, 2, left, hp, W) == "Broken", "one swing breaks it")
		local up = B.wireSwing(left, hp, true, W)
		assert(up == hp, "a Build swing stands it back up")
		left, gone = B.wireSwing(left, hp, false, W)
		assert(gone and left == 0, "the second swing takes it away")
		assert(B.wireSwing(hp, hp, true, W) == hp, "a Build swing on a standing wire does nothing")
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

	["the sandbag pile: on HP, a bag down when laid, a bag a Build swing, ties with their bags, aimed fire clears it"] = function()
		local pile = assert(B.piece("SandbagPile", C.Pieces))
		local h = C.Sandbags.hp
		local n = #pile.bags
		assert(pile.kind == "Sandbags", "everyone builds it (Config/Classes small pieces)")
		assert(B.pileBag("Bag1", pile.bags) == 1 and B.pileBag("Bag3Cord", pile.bags) == 3)
		assert(B.pileBag("Origin", pile.bags) == nil and B.pileBag("Cord", pile.bags) == nil)
		assert(B.isPileCord("Bag2Cord") and not B.isPileCord("Bag2"))
		-- laid: the first bag down at once; each Build swing the next; full HP all of them
		assert(B.pileBags(h.place, h.max, n) == 1, "laid with a bag down")
		local hp, gone = B.pileSwing(h.place, true, h)
		assert(B.pileBags(hp, h.max, n) == 2 and not gone)
		hp = B.pileSwing(hp, true, h)
		assert(hp == h.max and B.pileBags(hp, h.max, n) == n, "two swings after laying finish it")
		assert(B.pileSwing(hp, true, h) == h.max, "never over its max")
		-- worn: bags come off as HP goes, one stands while any is left, gone at 0
		assert(B.pileBags(1, h.max, n) == 1 and B.pileBags(0, h.max, n) == 0 and B.pileBags(-5, h.max, n) == 0)
		local left
		left, gone = B.pileSwing(h.destroy, false, h)
		assert(left == 0 and gone)
		left, gone = B.pileSwing(h.max, false, h)
		assert(left == h.max - h.destroy and not gone)
		assert(B.pileSwing(h.max, false, h, 50) == 50, "an admin dig step in place of a swing")
		assert(pile.height < M.Character.AimMuzzleHeight and pile.height >= M.Cover.LowCoverMin)
	end,
}
