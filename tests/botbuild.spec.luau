--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotBuild")

local B = Cfg.Build

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local function count(jobs: { R.Job }, key: string): number
	local n = 0
	for _, j in jobs do
		if j.key == key then
			n += 1
		end
	end
	return n
end

return {
	["front: West's easternmost sector, East's westernmost"] = function()
		local sectors = { { x = 0 }, { x = 100 }, { x = 200 }, { x = 300 } }
		local owner = { "West", "West", "East", "East" }
		assert(R.front(sectors, owner, "West") == 2)
		assert(R.front(sectors, owner, "East") == 3)
		assert(R.front(sectors, { "East", "East", "East", "East" }, "West") == nil, "none held")
	end,
	["front: by the sector chain, not by x (a map running east to west, or north)"] = function()
		local sectors = { { x = 300 }, { x = 200 }, { x = 100 }, { x = 0 } }
		local owner = { "West", "West", "East", "East" }
		assert(R.front(sectors, owner, "West") == 2)
		assert(R.front(sectors, owner, "East") == 3)
	end,
	["toward: the enemy's way from the chain, on any heading"] = function()
		local line = { { x = 0, z = 0 }, { x = 100, z = 0 }, { x = 200, z = 0 } }
		local tx, tz = R.toward(line, 2, "West")
		assert(near(tx, 1) and near(tz, 0), "West up the chain")
		tx, tz = R.toward(line, 2, "East")
		assert(near(tx, -1) and near(tz, 0), "East down it")
		tx, tz = R.toward(line, 3, "West")
		assert(near(tx, 1) and near(tz, 0), "at the chain's end: on from the one before")
		local north = { { x = 0, z = 0 }, { x = 0, z = -300 }, { x = 40, z = -600 } }
		tx, tz = R.toward(north, 1, "West")
		assert(near(tx, 0) and near(tz, -1), "a chain running north")
		tx, tz = R.toward(north, 3, "East")
		assert(near(tx, -40 / math.sqrt(40 * 40 + 300 * 300)) and near(tz, 300 / math.sqrt(40 * 40 + 300 * 300)))
		tx, tz = R.toward({ { x = 5, z = 5 } }, 1, "East")
		assert(tx == -1 and tz == 0, "no heading: the old default")
	end,
	["plan: bags at open holds, wire, a nest, the open guns behind (no trench: Rules/BotTrenches)"] = function()
		local zone = { x = 0, z = 0, radius = 50 }
		local holds = {
			{ x = 10, z = 0, hidden = false },
			{ x = 30, z = 5, hidden = true },
			{ x = -5, z = 10, hidden = false },
		}
		local jobs = R.plan(zone, 1, 0, holds, { "FieldGun" }, B)
		assert(count(jobs, "Trench") == 0 and count(jobs, "SandbagPile") == 2, "bags only at the open holds")
		assert(count(jobs, "Wire") == #B.Wire.lanes and count(jobs, "FieldGun") == 1)
		assert(count(jobs, "MGNest") == math.min(B.Nest.count, #holds), "a nest at each of the nearest holds")
		assert(count(R.plan(zone, 1, 0, holds, {}, B, 0), "MGNest") == 0, "none missing: none")
		assert(count(R.plan(zone, 1, 0, holds, {}, B, 1), "MGNest") == 1, "one missing: one")
		assert(count(jobs, "Howitzer") == 0, "only the guns the level opens")
		local first = nil
		for _, j in R.plan(zone, 1, 0, holds, {}, B, 1) do
			if j.key == "MGNest" then
				first = j
			end
		end
		assert(first and near(first.x, 30 + B.Nest.ahead), "the first at the hold nearest the enemy")
		for _, j in jobs do
			if j.key == "MGNest" then
				assert(j.x >= -5 + B.Nest.ahead - 0.01, "ahead of a hold")
			elseif j.key == "FieldGun" then
				assert(near(j.x, -B.Guns.back), "behind the zone")
			elseif j.key == "Wire" then
				assert(near(j.x, zone.radius + B.Wire.out), "out past the edge")
			end
			assert(j.fx == 1 and j.fz == 0, "all facing the enemy")
		end
	end,
	["plan: bags capped, both guns side by side"] = function()
		local holds = {}
		for k = 1, 10 do
			holds[k] = { x = k, z = 0, hidden = false }
		end
		local jobs = R.plan({ x = 0, z = 0, radius = 50 }, -1, 0, holds, { "FieldGun", "Howitzer" }, B)
		assert(count(jobs, "SandbagPile") == B.Bags.max)
		local a, b
		for _, j in jobs do
			if j.key == "FieldGun" then
				a = j
			elseif j.key == "Howitzer" then
				b = j
			end
		end
		assert(
			a and b and near(a.x, B.Guns.back) and near(math.abs(a.z - b.z), B.Guns.side),
			"behind (west faces east)"
		)
	end,
	["allowed: a third of the team's pieces, half the guns"] = function()
		local caps = B.caps
		assert(R.allowed("Wire", 0, 0, caps))
		assert(not R.allowed("Wire", caps.pieces, 0, caps), "the bots' share used")
		assert(R.allowed("FieldGun", 10, caps.FieldGun - 1, caps))
		assert(not R.allowed("FieldGun", 10, caps.FieldGun, caps), "half the field guns")
		assert(not R.allowed("Howitzer", 10, caps.Howitzer, caps), "half the howitzers")
	end,
	["match: a laid piece of the job's key near its spot"] = function()
		local jobs: { R.Job } = {
			{ key = "Wire", x = 0, z = 0, fx = 1, fz = 0 },
			{ key = "Wire", x = 2, z = 0, fx = 1, fz = 0 },
			{ key = "Trench", x = 0, z = -20, ex = 0, ez = 20, fx = 1, fz = 0 },
		}
		local pieces = {
			{ key = "Wire", x = 1, z = 0, left = 3 },
			{ key = "SandbagPile", x = 2, z = 0, left = 0 },
			{ key = "Trench", x = 0, z = 15, left = 5 },
		}
		local got = R.match(jobs, pieces, 6)
		assert(got[1] == 1 and got[2] == nil, "one wire for one job")
		assert(got[3] == 3, "a square along the line")
	end,
	["repairs: wanting swings, near the zone, nearest first"] = function()
		local pieces = {
			{ key = "Wire", x = 70, z = 0, left = 2 },
			{ key = "Wire", x = 10, z = 0, left = 2 },
			{ key = "Wire", x = 5, z = 0, left = 0 },
			{ key = "Wire", x = 500, z = 0, left = 2 },
		}
		local got = R.repairs(pieces, { x = 0, z = 0, radius = 50 }, 30, 6)
		assert(#got == 2 and got[1] == 2 and got[2] == 1)
	end,
	["pick: the nearest free job; helpers only work trenches and wire"] = function()
		local jobs: { R.Job } = {
			{ key = "SandbagPile", x = 5, z = 0, fx = 1, fz = 0 },
			{ key = "Wire", x = 10, z = 0, fx = 1, fz = 0 },
			{ key = "Wire", x = 12, z = 0, fx = 1, fz = 0, work = true },
			{ key = "Trench", x = 200, z = 0, fx = 1, fz = 0, work = true },
		}
		assert(R.pick(jobs, 0, 0, 90, {}, {}) == 1)
		assert(R.pick(jobs, 0, 0, 90, { [1] = true }, {}) == 2)
		assert(R.pick(jobs, 0, 0, 90, { [1] = true }, { [2] = true }) == 3)
		local helps = { Trench = true, Wire = true }
		assert(R.pick(jobs, 0, 0, 90, {}, {}, helps) == 3, "a work job only")
		assert(R.pick(jobs, 0, 0, 90, { [3] = true }, {}, helps) == nil, "the trench too far")
	end,
	["line: a breastwork's piles and barriers along the refused run"] = function()
		local jobs = R.line(0, 0, 0, 32, 1, 0, B.Breast.step, B.Breast.keys)
		assert(#jobs == 4, "one every step")
		assert(jobs[1].key == "SandbagPile" and jobs[2].key == "Hesco" and jobs[3].key == "SandbagPile")
		assert(jobs[1].x == 0 and jobs[1].z == 4 and jobs[4].z == 28 and jobs[1].fx == 1, "along it, facing out")
	end,
	["wall: piles on the enemy side of a nest or gun"] = function()
		local W = B.Walls
		local jobs = R.wall(10, 0, 1, 0, W.ahead, W.spread, W.count)
		assert(#jobs == W.count)
		for _, j in jobs do
			assert(j.key == "SandbagPile" and j.x == 10 + W.ahead, "ahead of it")
		end
		assert(math.abs(jobs[1].z - jobs[2].z) == W.spread, "side by side")
	end,
	["exposedDig: seen from the open a while, no cover, not in a trench, not pressing on (user 2026-11-06)"] = function()
		local E = { after = B.Exposed.after, every = B.Pinned.every }
		assert(R.exposedDig(E.after, false, false, false, E.every, E))
		assert(not R.exposedDig(E.after - 0.1, false, false, false, E.every, E), "only just seen")
		assert(not R.exposedDig(E.after, true, false, false, E.every, E), "cover near")
		assert(not R.exposedDig(E.after, false, true, false, E.every, E), "in a trench")
		assert(not R.exposedDig(E.after, false, false, true, E.every, E), "pressing on")
		assert(not R.exposedDig(E.after, false, false, false, E.every - 1, E), "dug one just now")
		assert(Cfg.Brain.SeenSpots, "an enemy in sight counts as having spotted it")
	end,
	["pinned: shot at, shaken, no cover and not in a trench"] = function()
		local P = B.Pinned
		assert(R.pinned(0, P.shaken, false, false, P.every, P))
		assert(not R.pinned(P.threat + 1, P.shaken, false, false, P.every, P), "nobody shooting now")
		assert(not R.pinned(0, P.shaken - 0.1, false, false, P.every, P), "not pinned down")
		assert(not R.pinned(0, P.shaken, true, false, P.every, P), "it has cover")
		assert(not R.pinned(0, P.shaken, false, true, P.every, P), "in a trench")
		assert(not R.pinned(0, P.shaken, false, false, P.every - 1, P), "laid one lately")
	end,
	["nudge: across the way in, one side then the other"] = function()
		local job: R.Job = { key = "Wire", x = 0, z = 0, fx = 1, fz = 0 }
		local x1, z1 = R.nudge(job, 1, 6)
		local x2, z2 = R.nudge(job, 2, 6)
		local x3, z3 = R.nudge(job, 3, 6)
		assert(near(x1, 0) and near(z1, 6) and near(x2, 0) and near(z2, -6) and near(z3, 12) and near(x3, 0))
		local line: R.Job = { key = "Trench", x = 0, z = -10, ex = 0, ez = 10, fx = 1, fz = 0 }
		local tx1, tz1 = R.nudge(line, 1, 6)
		local tx2 = R.nudge(line, 2, 6)
		assert(near(tx1, -6) and near(tz1, -10) and near(tx2, 6), "a trench steps back, then forward")
	end,
	["crews: up to max bots go Engineer while too few guns stand"] = function()
		local C = B.Crews
		assert(R.crewWanted(0, 0, C) and R.crewWanted(C.enough - 1, C.max - 1, C))
		assert(not R.crewWanted(C.enough, 0, C), "enough guns: nobody")
		assert(not R.crewWanted(0, C.max, C), "a small, capped number")
	end,
	["gun spots: behind the zone, farthest back first, spaced, only where they fit"] = function()
		local zone = { x = 0, z = 0, radius = 50 }
		local C = { back = { 90, 60, 30 }, across = { 0, -60, 60, -120, 120, -180, 180 } }
		local spacing = { FieldGun = 60, Howitzer = 120 }
		local function any(_: string, _x: number, _z: number): boolean
			return true
		end
		local want = { { key = "Howitzer", count = 1 }, { key = "FieldGun", count = 3 } }
		local jobs = R.gunSpots(zone, 1, 0, want, C, spacing, any)
		assert(#jobs == 4 and jobs[1].key == "Howitzer" and near(jobs[1].x, -140) and near(jobs[1].z, 0))
		for i, a in jobs do
			assert(a.x < -zone.radius and a.fx == 1, "behind the zone's edge, facing the enemy")
			for k, b in jobs do
				if i ~= k then
					local gap = math.max(spacing[a.key], spacing[b.key])
					assert((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 >= gap * gap - 1e-6, "spaced")
				end
			end
		end
		-- East faces west: behind is +x
		assert(R.gunSpots(zone, -1, 0, want, C, spacing, any)[1].x > zone.radius)
		-- a spot that doesn't fit (out of reach, a spawn) is skipped for the next
		local function notFar(_: string, x: number, _z: number): boolean
			return x > -120
		end
		local near1 = R.gunSpots(zone, 1, 0, { { key = "FieldGun", count = 1 } }, C, spacing, notFar)
		assert(#near1 == 1 and near(near1[1].x, -110), "the next row in")
		local none = R.gunSpots(zone, 1, 0, want, C, spacing, function()
			return false
		end)
		assert(#none == 0)
		-- the flanks (Config/Bots.Front.Flank): every `every`-th spot at least `gunFrom` across
		local Fl = Cfg.Front.Flank
		local FC = { back = C.back, across = C.across, flank = Fl }
		local flanked = R.gunSpots(zone, 1, 0, want, FC, spacing, any)
		assert(#flanked == 4, "as many")
		for i, j in flanked do
			if i % Fl.every == 0 then
				assert(math.abs(j.z) >= Fl.gunFrom - 1e-6, "a flank spot")
			end
		end
	end,
	["plan: every third MG nest at the hold spot farthest across (Config/Bots.Front.Flank)"] = function()
		local zone = { x = 0, z = 0, radius = 50 }
		local holds = {
			{ x = 30, z = 0, hidden = true },
			{ x = 25, z = 5, hidden = true },
			{ x = 20, z = -2, hidden = true },
			{ x = 0, z = 45, hidden = true },
		}
		local cfg = table.clone(B)
		cfg.Flank = Cfg.Front.Flank
		local nests = {}
		for _, j in R.plan(zone, 1, 0, holds, {}, cfg, 3) do
			if j.key == "MGNest" then
				table.insert(nests, j)
			end
		end
		assert(#nests == 3 and near(nests[1].x, 30 + B.Nest.ahead) and near(nests[2].x, 25 + B.Nest.ahead))
		assert(near(nests[3].z, 45), "the third off to the side")
	end,
	["wireSpot: off its own side's ways and spawn, moved across, or nowhere"] = function()
		local Wr = B.Wire
		local lines = { { ax = 0, az = 0, bx = 100, bz = 0 } }
		local x, z = R.wireSpot(50, 0, 0, 1, lines, nil, Wr)
		assert(x == 50 and z and math.abs(z) >= Wr.gap, "moved off the way")
		local cx, cz = R.wireSpot(50, 40, 0, 1, lines, nil, Wr)
		assert(cx == 50 and cz == 40, "clear where planned")
		local wide = { gap = 100, spawn = Wr.spawn, step = Wr.step, shift = Wr.shift }
		assert(R.wireSpot(50, 0, 0, 1, lines, nil, wide) == nil, "nowhere clear")
		local spawn = { minX = 0, maxX = 10, minZ = 0, maxZ = 10 }
		assert(R.wireSpot(20, 5, 0, 1, {}, spawn, { gap = 0, spawn = 30, step = 6, shift = 12 }) == nil, "by the spawn")
	end,
	["treesInWay: within clear of a way, nearest first, never in a building"] = function()
		local T = B.Trees
		local ways = { { ax = 0, az = 0, bx = 100, bz = 0 }, { ax = 200, az = 50, bx = 200, bz = 50 } }
		local trees = {
			{ x = 50, z = T.clear - 1 }, -- 1: near the run
			{ x = 50, z = T.clear + 1 }, -- 2: just out
			{ x = 50, z = 1 }, -- 3: nearest
			{ x = 201, z = 50, building = true }, -- 4: by the point, in a building
			{ x = 202, z = 52 }, -- 5: by the point
			{ x = 150, z = 0 }, -- 6: past the run's end
		}
		local got = R.treesInWay(trees, ways, T.clear)
		assert(#got == 3, `{#got} trees`)
		assert(got[1] == 3 and got[2] == 5 and got[3] == 1, "nearest its way first")
		assert(#R.treesInWay(trees, {}, T.clear) == 0, "no ways, no trees")
	end,
	["fireLine: out along the gun's facing"] = function()
		local T = B.Trees
		local l = R.fireLine(10, 20, 0, 1, T.fireLine)
		assert(l.ax == 10 and l.az == 20 and near(l.bx, 10) and near(l.bz, 20 + T.fireLine))
		local trees = { { x = 12, z = 20 + T.fireLine - 5 }, { x = 12, z = 20 + T.fireLine + T.clear + 1 } }
		local got = R.treesInWay(trees, { l }, T.clear)
		assert(#got == 1 and got[1] == 1, "only within the line's reach")
	end,
	["mayFell: one per Engineer every so often, a side's cap"] = function()
		local T = B.Trees
		assert(R.mayFell(0, nil, T), "the first")
		assert(not R.mayFell(0, T.every - 1, T) and R.mayFell(0, T.every, T), "every")
		assert(not R.mayFell(T.perSide, nil, T), "the side's cap")
	end,
	["mayRepair: only after the wait"] = function()
		assert(not R.mayRepair(B.repairWait - 1, B.repairWait) and R.mayRepair(B.repairWait, B.repairWait))
	end,
	["safeToWork: pinned always; never with an enemy in sight; else calm or hidden from the threat"] = function()
		local c = B.calm
		assert(R.safeToWork(true, true, 0, 0, false, c), "its own foxhole under fire")
		assert(not R.safeToWork(false, true, math.huge, math.huge, true, c), "an enemy in sight")
		assert(R.safeToWork(false, false, c, c, false, c), "calm")
		assert(not R.safeToWork(false, false, c - 0.1, math.huge, false, c), "shot at lately")
		assert(not R.safeToWork(false, false, math.huge, c - 0.1, false, c), "hurt lately")
		assert(R.safeToWork(false, false, 0, 0, true, c), "the spot hidden from the threat")
	end,
	["stalled: nearer by `gain` starts the clock again; fighting too; else gives up after `stall`"] = function()
		local W = B.Work
		local best, at, gave = R.stalled(50, nil, 0, 0, false, W)
		assert(best == 50 and at == 0 and not gave, "first look")
		best, at, gave = R.stalled(50 - W.gain + 0.5, best, at, W.stall - 1, false, W)
		assert(best == 50 and at == 0 and not gave, "a little nearer: no")
		best, at, gave = R.stalled(49, best, at, W.stall, false, W)
		assert(gave, "no nearer for `stall`")
		best, at, gave = R.stalled(50 - W.gain - 1, 50, 0, W.stall, false, W)
		assert(best == 50 - W.gain - 1 and at == W.stall and not gave, "nearer")
		best, at, gave = R.stalled(60, 50, 0, W.stall + 5, true, W)
		assert(best == 50 and at == W.stall + 5 and not gave, "fighting on the way")
	end,
	["strikes: sometimes, likelier empty"] = function()
		local Me = Cfg.Melee
		assert(R.strikes(false, Me.chance - 0.01, Me) and not R.strikes(false, Me.chance + 0.01, Me))
		assert(R.strikes(true, Me.empty - 0.01, Me) and not R.strikes(true, Me.empty + 0.01, Me))
	end,
}
