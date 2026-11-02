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
	["plan: bags at open holds, wire, a nest, the open guns behind (no trench: Rules/BotTrenches)"] = function()
		local zone = { x = 0, z = 0, radius = 50 }
		local holds = {
			{ x = 10, z = 0, hidden = false },
			{ x = 30, z = 5, hidden = true },
			{ x = -5, z = 10, hidden = false },
		}
		local jobs = R.plan(zone, 1, 0, holds, { "FieldGun" }, B)
		assert(count(jobs, "Trench") == 0 and count(jobs, "SandbagPile") == 2, "bags only at the open holds")
		assert(count(jobs, "Wire") == #B.Wire.lanes and count(jobs, "MGNest") == 1 and count(jobs, "FieldGun") == 1)
		assert(count(jobs, "Howitzer") == 0, "only the guns the level opens")
		for _, j in jobs do
			if j.key == "MGNest" then
				assert(near(j.x, 30 + B.Nest.ahead), "at the hold nearest the enemy")
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
	["mayRepair: only after the wait"] = function()
		assert(not R.mayRepair(B.repairWait - 1, B.repairWait) and R.mayRepair(B.repairWait, B.repairWait))
	end,
	["strikes: sometimes, likelier empty"] = function()
		local Me = Cfg.Melee
		assert(R.strikes(false, Me.chance - 0.01, Me) and not R.strikes(false, Me.chance + 0.01, Me))
		assert(R.strikes(true, Me.empty - 0.01, Me) and not R.strikes(true, Me.empty + 0.01, Me))
	end,
}
