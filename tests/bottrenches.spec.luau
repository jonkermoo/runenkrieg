--!strict
local Cfg = require("../src/shared/Config/Bots")
local Build = require("../src/shared/Config/Build")
local R = require("../src/shared/Rules/BotTrenches")
local Rules = require("../src/shared/Rules/Build")

local T = Cfg.Trenches

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end

local function of(runs: { R.Run }, kind: string): { R.Run }
	local out = {}
	for _, r in runs do
		if r.kind == kind then
			table.insert(out, r)
		end
	end
	return out
end

local function len(r: R.Run): number
	return math.sqrt((r.bx - r.ax) ^ 2 + (r.bz - r.az) ^ 2)
end

return {
	["layout: a fire trench of bays and traverses, joined end to end, at the zone's enemy edge"] = function()
		local zone = { x = 0, z = 0, radius = 50 }
		local fire = of(R.layout(zone, 1, 0, T), "Fire")
		assert(#fire == T.Fire.bays)
		local edge = zone.radius * T.Fire.edge
		for k, r in fire do
			assert(r.ax >= edge - 1e-6 and r.ax <= edge + T.Fire.traverse + 1e-6, "at the edge, toward the enemy")
			assert(len(r) <= Build.Trench.maxPlan, "one plan each")
			if k > 1 then
				assert(near(r.ax, fire[k - 1].bx) and near(r.az, fire[k - 1].bz), "joined end to end")
			end
		end
		assert(near(fire[1].ax, edge) and near(fire[1].bx, edge + T.Fire.traverse), "every other joint forward")
		assert(near(math.abs(fire[#fire].bz - fire[1].az), T.Fire.width), "its width across")
	end,
	["layout: the support line behind, the communication trench between, in two jogging runs"] = function()
		local runs = R.layout({ x = 100, z = 0, radius = 50 }, -1, 0, T) -- (East: the enemy to the west)
		local support = of(runs, "Support")
		local comm = of(runs, "Comm")
		assert(#support == 1 and #comm == 2)
		local edge = 100 - 50 * T.Fire.edge
		assert(near(support[1].ax, edge + T.Support.back), "behind the fire trench (east of it)")
		assert(T.Support.back >= Build.Trench.spacing, "far enough from the fire trench for the planner")
		assert(near(comm[1].bx, comm[2].ax) and near(comm[1].bz, comm[2].az), "the two runs joined")
		assert(not near(comm[1].bz, comm[1].az, 1), "it jogs across")
		assert(comm[1].ax < edge + T.Support.back and comm[2].bx > edge - T.Fire.traverse, "between the two lines")
		assert(runs[1].kind == "Fire" and runs[#runs].kind == "Comm", "dug in order")
		assert(#R.layout({ x = 0, z = 0, radius = 50 }, 1, 0, T, true) == T.Fire.bays, "the fire trench alone")
	end,
	["laid: a square on the run's line, in its middle part"] = function()
		local run: R.Run = { kind = "Fire", ax = 0, az = 0, bx = 0, bz = 16 }
		assert(R.laid(run, { { x = 0.5, z = 8 } }, T.on, T.ends) == 1)
		assert(R.laid(run, { { x = 0, z = 0.5 } }, T.on, T.ends) == nil, "at its end: the run it joins")
		assert(R.laid(run, { { x = 4, z = 8 } }, T.on, T.ends) == nil, "off its line")
	end,
	["ready: each run once every run before it is planned"] = function()
		local runs = R.layout({ x = 0, z = 0, radius = 50 }, 1, 0, T)
		assert(R.ready({}, 1) and not R.ready({}, 2), "the first bay first")
		assert(R.ready({ true }, 2) and not R.ready({ true }, 3))
		local all = {}
		for k = 1, #runs - 1 do
			all[k] = true
		end
		assert(R.ready(all, #runs), "the communication trench last")
		all[2] = false
		assert(not R.ready(all, #runs), "a bay missing")
	end,
	["swing: the far end steps aside, one way then the other; the start stays"] = function()
		local x1, z1 = R.swing(0, 0, 0, 16, 1, 6)
		local x2, z2 = R.swing(0, 0, 0, 16, 2, 6)
		local x3 = R.swing(0, 0, 0, 16, 3, 6)
		assert(near(x1, -6) and near(z1, 16) and near(x2, 6) and near(z2, 16) and near(x3, -12))
	end,
	["fireStep: up the forward wall toward the enemy, by the trench's shape"] = function()
		local TB = Build.Trench
		local step = R.stepOut(TB.floor, TB.wallAngle, T.rise)
		local flat = { ax = 10, ay = 2, az = 1, bx = 10, by = 2, bz = 9, tilt = 0 }
		local p = R.firePost(flat, -1, 0, step, T.rise, TB.depth, 0)
		assert(near(p.sx, 10 - step) and near(p.sz, 5) and near(p.sy, 2 + T.rise - TB.depth))
		assert(near(p.fx, 10) and near(p.fz, 5) and near(p.fy, 2 - TB.depth))
		assert(near(p.ox, -1) and near(p.oz, 0))
		-- (on the wall, short of its top edge, high enough to see over the parapet)
		assert(step > TB.floor and step < TB.floor + TB.depth / math.tan(math.rad(TB.wallAngle)))
		assert(T.rise + 4.5 > TB.depth + 2.3, "eyes over the parapet")
		assert(math.abs(R.stepOut(4.25, 59, T.rise) - 6.29) < 0.05, "the wider trench: 6.3 as before")
		assert(math.abs(R.stepOut(3, 59, T.rise) - 5.04) < 0.05, "the slimmer trench: about 5.05")
	end,
	["firePost: on the forward wall across the square's own line, turned with its tilt"] = function()
		local TB = Build.Trench
		local step = R.stepOut(TB.floor, TB.wallAngle, T.rise)
		local top = Rules.trenchTop(TB)
		local function wall(r: number): number
			return Rules.trenchProfile(math.abs(r), 1, TB) or 0
		end
		-- a square slanted 30 degrees off square to the enemy (+X), sloping along it, tilted both ways across
		for _, tilt in { -0.4, -0.15, 0, 0.15, 0.4 } do
			local a, b = math.rad(120), 8
			local sq = { ax = 0, ay = 5, az = 0, bx = math.cos(a) * b, by = 7, bz = math.sin(a) * b, tilt = tilt }
			local p = R.firePost(sq, 1, 0, step, T.rise, TB.depth, 0)
			local mx, my, mz = sq.bx / 2, 6, sq.bz / 2
			local rx, rz = -math.sin(a), math.cos(a) -- (the square's right: away from the enemy here, its left wall)
			local v = (p.sx - mx) * rx + (p.sz - mz) * rz
			assert(v < 0 and (p.sx - mx) > 0, "on the enemy's side")
			assert(near((p.sx - mx) * math.cos(a) + (p.sz - mz) * math.sin(a), 0), "at right angles to the line")
			assert(near(p.ox, -rx) and near(p.oz, -rz), "facing out across its line")
			-- on the wall its pieces lie on: back in the square's own (tilted) frame, the profile's height at that reach
			local c = 1 / math.sqrt(1 + tilt * tilt)
			local function frame(across: number, up: number): (number, number)
				return across * c + up * tilt * c, up * c - across * tilt * c
			end
			local w, d = frame(v, p.sy - my)
			assert(near(d, wall(w), 1e-6) and near(math.abs(w), step), `on the wall at tilt {tilt}`)
			-- under the parapet: its eyes (4.5 up) over the wall top on that side, its feet under it
			local ty = -top * tilt * c
			assert(p.sy - my < ty and p.sy - my + 4.5 > ty + TB.bank.height, "eyes just over the forward wall")
			-- the floor below, in the middle, on the turned floor
			local fv = (p.fx - mx) * rx + (p.fz - mz) * rz
			local fw, fd = frame(fv, p.fy - my)
			assert(near(fw, 0) and near(fd, -TB.depth), "on the floor")
			local q = R.firePost(sq, 1, 0, step, T.rise, TB.depth, 2)
			assert(q.fy > p.fy + 1.5 and near(q.sy, p.sy), "the floor rides up on the fill, the step stays")
		end
		-- the enemy the other way: the other wall
		local sq = { ax = 0, ay = 0, az = 0, bx = 0, by = 0, bz = 8, tilt = 0.3 }
		local e, w = R.firePost(sq, 1, 0, step, T.rise, TB.depth, 0), R.firePost(sq, -1, 0, step, T.rise, TB.depth, 0)
		assert(e.sx > 0 and w.sx < 0 and e.ox > 0 and w.ox < 0)
		assert(e.sy ~= w.sy, "the tilt lifts one wall's step and drops the other's")
	end,
	["digs: half the squad digs, the rest guard"] = function()
		assert(R.digs(1, 4, T.share) and R.digs(2, 4, T.share) and not R.digs(3, 4, T.share))
		assert(R.digs(1, 1, T.share), "a lone bot digs")
		assert(R.digs(1, 3, T.share) and R.digs(2, 3, T.share) and not R.digs(3, 3, T.share))
	end,
	["overrun, standTo, inSquare"] = function()
		assert(R.overrun(1, 1, 4, T.keep) and not R.overrun(1, 3, 4, T.keep) and not R.overrun(0, 0, 4, T.keep))
		assert(R.standTo(T.alarm - 1, T.alarm) and not R.standTo(T.alarm + 1, T.alarm))
		local squares = { { x = 0, z = 0 }, { x = 8, z = 0 } }
		assert(R.inSquare(7, 1, squares, 4) == 2 and R.inSquare(20, 0, squares, 4) == nil)
	end,
	["clearOf: pieces keep off trench lines by the reach and their own size"] = function()
		local lines = { { kind = "Fire", ax = 0, az = 0, bx = 40, bz = 0 } }
		assert(not R.clearOf(20, 0, 2, lines, 8), "on the line")
		assert(not R.clearOf(20, 9, 2, lines, 8), "its corner over the wall top")
		assert(R.clearOf(20, 11, 2, lines, 8), "clear of it")
		assert(not R.clearOf(45, 0, 2, lines, 8), "past the end, still too close")
		assert(R.clearOf(20, 0, 2, {}, 8), "no lines")
	end,
	["blocker: small pieces torn down, the rest routed round"] = function()
		local tear = T.tear
		assert(R.blocker("SandbagPile", false, false, tear) == "tear", "the enemy's pile")
		assert(R.blocker("Hesco", true, true, tear) == "tear", "a bot's own barrier")
		assert(R.blocker("SandbagPile", true, false, tear) == "around", "a player's own pile stays")
		assert(R.blocker("FieldGun", false, true, tear) == "around", "a gun: round it")
		assert(R.blocker("MGNest", true, true, tear) == "around", "a nest: round it")
	end,
	["danger: shot at, enemy near, shelling near or a contested goal"] = function()
		local M = Cfg.TrenchMove
		assert(not R.danger(100, 0, 0, math.huge, {}, {}, false, M), "an empty field")
		assert(R.danger(100, 0, 0, M.shot - 1, {}, {}, false, M), "shot at")
		assert(not R.danger(100, 0, 0, M.shot + 1, {}, {}, false, M), "shot at long ago")
		assert(R.danger(100, 0, 0, math.huge, { { x = M.near - 1, z = 0, at = 100 } }, {}, false, M), "enemy near")
		assert(not R.danger(100, 0, 0, math.huge, { { x = M.near + 1, z = 0, at = 100 } }, {}, false, M), "too far")
		assert(not R.danger(100, 0, 0, math.huge, { { x = 1, z = 0, at = 100 - M.known - 1 } }, {}, false, M), "old")
		assert(R.danger(100, 0, 0, math.huge, {}, { { x = 0, z = M.blastNear - 1, at = 99 } }, false, M), "shelled")
		assert(not R.danger(100, 0, 0, math.huge, {}, { { x = 0, z = M.blastNear + 1, at = 99 } }, false, M))
		assert(R.danger(100, 0, 0, math.huge, {}, {}, true, M), "contested")
	end,
	["jumpOff: the dug square nearest the objective, outside its zone, ahead of the squad"] = function()
		local J = Cfg.TrenchMove.Jump
		local squares = { { x = 100, z = 0 }, { x = 60, z = 0 }, { x = 20, z = 0 }, { x = 300, z = 0 } }
		-- objective at 0, radius 40, squad at 200
		assert(R.jumpOff(squares, 200, 0, 0, 0, 40, J) == 2, "60 out: the nearest outside the zone")
		assert(R.jumpOff(squares, 70, 0, 0, 0, 40, J) == nil, "none far enough ahead of the squad")
		assert(R.jumpOff({ { x = 40 + J.reach + 5, z = 0 } }, 400, 0, 0, 0, 40, J) == nil, "too far from the zone")
	end,
	["overTop: most of the squad there, or waited long enough"] = function()
		local J = Cfg.TrenchMove.Jump
		assert(R.overTop(3, 4, 0, J) and not R.overTop(2, 4, 0, J), "three of four")
		assert(R.overTop(1, 4, J.wait, J), "no waiting for ever")
		assert(not R.overTop(0, 0, J.wait, J), "nobody left")
	end,
	["shelled: a shell near the trench lately, not a grenade"] = function()
		local D = Cfg.Dugouts
		local squares = { { x = 0, z = 0 } }
		local shell = { x = D.near - 1, z = 0, at = 100, kg = D.shell }
		assert(R.shelled(100, { shell }, squares, D), "a shell near")
		assert(not R.shelled(100 + D.recent + 1, { shell }, squares, D), "long ago")
		assert(not R.shelled(100, { { x = 1, z = 0, at = 100, kg = 0.17 } }, squares, D), "a grenade")
		assert(not R.shelled(100, { { x = D.near + 1, z = 0, at = 100, kg = 5 } }, squares, D), "too far")
		assert(not R.shelled(100, { shell }, {}, D), "no trench")
	end,
	["dugoutsWanted: none before shelling, then room for all but the sentries"] = function()
		local D = Cfg.Dugouts
		assert(R.dugoutsWanted(false, 12, 2, D) == 0, "never shelled")
		assert(R.dugoutsWanted(true, 2, 2, D) == 0, "only sentries")
		assert(R.dugoutsWanted(true, 2 + D.room, 2, D) == 1)
		assert(R.dugoutsWanted(true, 3 + D.room, 2, D) == 2, "one more over")
	end,
	["a trench's heat: shells and its own dead close by, fading; enemies known near, capped (user 2026-11-03)"] = function()
		-- user 2026-11-03: "make bots utilize dug outs more often, especially in trenches highly contested or often shelled"
		local H = Cfg.Dugouts.Heat
		local shell = { x = 0, z = 0, at = 100, kind = "shell" }
		assert(near((R.heat(100, 0, 0, "West", { shell }, {}, H)), H.weight.shell), "a shell on the spot, full")
		assert(near((R.heat(100, H.radius, 0, "West", { shell }, {}, H)), H.weight.shell * H.edge), "at the radius")
		assert(R.heat(100, H.radius + 1, 0, "West", { shell }, {}, H) == 0, "past it")
		assert(near((R.heat(100 + H.fade, 0, 0, "West", { shell }, {}, H)), H.weight.shell / math.exp(1)), "fades")
		assert((R.heat(100 + H.fade, 0, 0, "West", { shell }, {}, H, H.memory)) > H.weight.shell * 0.7, "remembered")
		local dead = { x = 0, z = 0, at = 100, kind = "death", side = "West" }
		assert(near((R.heat(100, 0, 0, "West", { dead }, {}, H)), H.weight.death), "its own dead")
		assert(R.heat(100, 0, 0, "East", { dead }, {}, H) == 0, "not the enemy's dead")
		local foes = {}
		for i = 1, 20 do
			table.insert(foes, { x = i, z = 0 })
		end
		local h, s, d, f = R.heat(100, 0, 0, "West", { shell, dead }, foes, H)
		assert(near(f, H.enemyMost) and near(h, s + d + f), "enemies known near, capped")
		assert(H.enemyMost < H.enter, "enemies alone never send them down")
		assert(R.heat(100, 0, 0, "West", {}, { { x = H.enemyNear + 1, z = 0 } }, H) == 0, "a far enemy")
		local why = R.heatWhy(h, s, d, f)
		assert(string.find(why, "shells") and string.find(why, "deaths") and string.find(why, "enemies"), why)
	end,
	["shelter: down when hot, up when it cools or after a stay, then a rest up to fight"] = function()
		local H = Cfg.Dugouts.Heat
		assert(H.leave < H.enter and H.rest > 0 and H.stay > H.rest, "a margin, and longer down than up")
		assert(R.shelter(false, H.enter, 0, false, H), "hot: down")
		assert(not R.shelter(false, H.enter - 0.01, 0, false, H), "not hot enough")
		local down, why = R.shelter(false, 5, 0, true, H)
		assert(not down and why == "resting", "resting: up, fighting")
		assert(R.shelter(true, H.leave, 1, false, H), "still warm: stays")
		down, why = R.shelter(true, H.leave - 0.01, 1, false, H)
		assert(not down and why == "calm", "cooled: up")
		down, why = R.shelter(true, 5, H.stay, false, H)
		assert(not down and why == "stay", "down long enough: up to fight")
		-- one shell near a trench is enough, and they stay down longer than the old 8 s
		local shell = { { x = 0, z = 0, at = 0, kind = "shell" } }
		assert((R.heat(0, 10, 0, "West", shell, {}, H)) >= H.enter, "a shell 10 studs off")
		local t = H.fade * math.log(H.weight.shell / H.leave)
		assert(t > Cfg.Dugouts.recent, "longer than the old shelling")
		-- often shelled (a shell every 10 s): still hot after a stay, so a holder rests up a while and goes back down
		local often = {}
		for i = 0, 5 do
			table.insert(often, { x = 0, z = 0, at = i * 10, kind = "shell" })
		end
		assert((R.heat(H.stay + H.rest, 0, 0, "West", often, {}, H)) >= H.enter, "hot after a stay and a rest")
	end,
	["dugoutSquares: the hottest squares first"] = function()
		local D = Cfg.Dugouts
		local sq = {
			{ x = 0, z = 0, share = 1, len = 20, heat = 0 },
			{ x = 40, z = 0, share = 1, len = 20, heat = 3 },
			{ x = -40, z = 0, share = 1, len = 20, heat = 1 },
		}
		local out = R.dugoutSquares(sq, {}, 2, D, 10)
		assert(out[1] == 2 and out[2] == 3, "hottest, then the next")
		sq[2].heat, sq[3].heat = 0, 0
		assert(R.dugoutSquares(sq, {}, 1, D, 10)[1] == 1, "none hot: the middle")
	end,
	["dugoutSquares: dug squares, spaced, the middle first"] = function()
		local D = Cfg.Dugouts
		local squares = {}
		for k = 0, 6 do
			table.insert(squares, { x = 0, z = k * 8, share = 1, len = 8 })
		end
		squares[4].share = 0.5 -- (the middle one, z 24, not dug yet)
		local got = R.dugoutSquares(squares, {}, 2, D, 8)
		assert(#got == 2, "two")
		for _, i in got do
			assert(i ~= 4, "not on an undug square")
		end
		local a, b = squares[got[1]], squares[got[2]]
		assert(math.abs(a.z - b.z) >= D.spacing, "spaced")
		assert(D.spacing >= Build.Dugout.spacing, "bots plan no nearer than a dugout is refused")
		assert(math.abs(a.z - 24) <= 8, "the middle first")
		assert(#R.dugoutSquares(squares, { { x = 0, z = 24 } }, 1, D, 8) == 1)
		local near = R.dugoutSquares(squares, { { x = 0, z = 24 } }, 1, D, 8)
		assert(math.abs(squares[near[1]].z - 24) >= D.spacing, "off the one it has")
		assert(#R.dugoutSquares(squares, {}, 0, D, 8) == 0, "none wanted")
		assert(#R.dugoutSquares(squares, {}, 2, D, 8.1) == 0, "too short on the flat")
	end,
	["seat: the nearest dugout with a place"] = function()
		local rooms = { { x = 0, z = 0, free = 0 }, { x = 20, z = 0, free = 1 }, { x = 50, z = 0, free = 2 } }
		assert(R.seat(rooms, 1, 0) == 2, "the full one skipped")
		assert(R.seat(rooms, 48, 0) == 3)
		assert(R.seat({ { x = 0, z = 0, free = 0 } }, 0, 0) == nil, "all full")
	end,
	["foxholeWanted: an open post with no trench near and no foxhole there"] = function()
		local F = Cfg.Dugouts.Fox
		assert(R.foxholeWanted(0, 0, {}, {}, F), "open ground")
		assert(not R.foxholeWanted(0, 0, { { x = F.trench - 1, z = 0 } }, {}, F), "a trench near")
		assert(not R.foxholeWanted(0, 0, {}, { { x = F.apart - 1, z = 0 } }, F), "dug already")
		assert(R.foxholeWanted(0, 0, { { x = F.trench + 1, z = 0 } }, { { x = F.apart + 1, z = 0 } }, F))
	end,
	["occupied: a known enemy in the room, under the trench floor"] = function()
		local B = Cfg.Dugouts.Bomb
		local room = { x = 0, z = 0 }
		assert(R.occupied({ { x = 1, y = -3, z = 1 } }, room, -1, B), "in it")
		assert(not R.occupied({ { x = 1, y = 0, z = 1 } }, room, -1, B), "up in the trench")
		assert(not R.occupied({ { x = B.inside + 1, y = -3, z = 0 } }, room, -1, B), "elsewhere")
		assert(not R.occupied({}, room, -1, B), "nobody known")
	end,
	["exposed: a threat in line ahead of the run, or above it; not off to the side or behind"] = function()
		local Z = T.Zigzag
		local run = { kind = "Comm", ax = 0, az = 0, bx = 30, bz = 0 }
		assert(R.exposed(run, 0, { x = 200, y = 0, z = 10 }, Z) == "in line", "straight ahead")
		assert(R.exposed(run, 0, { x = 100, y = 40, z = 60 }, Z) == "from above", "uphill, off the line")
		assert(R.exposed(run, 0, { x = 100, y = 0, z = 80 }, Z) == nil, "off to the side, level")
		assert(R.exposed(run, 0, { x = -100, y = 50, z = 0 }, Z) == nil, "behind")
	end,
	["zigAngle: steeper the higher the threat, within its bounds"] = function()
		local A = T.Zigzag.angle
		assert(near(R.zigAngle(0, A), A.min) and near(R.zigAngle(-5, A), A.min))
		assert(R.zigAngle(10, A) > A.min and near(R.zigAngle(1000, A), A.max))
	end,
	["zigzag: legs of its length, alternating, ending on B, never further than B"] = function()
		local run = { kind = "Sap", ax = 0, az = 0, bx = 60, bz = 0 }
		local legs = R.zigzag(run, 30, 12)
		assert(#legs >= 5, "several legs")
		assert(near(legs[1].ax, 0) and near(legs[#legs].bx, 60) and near(legs[#legs].bz, 0), "from A onto B")
		for i, l in legs do
			assert(l.kind == "Sap", "its kind")
			if i > 1 then
				assert(near(l.ax, legs[i - 1].bx) and near(l.az, legs[i - 1].bz), "joined end to end")
			end
			if i < #legs then
				assert(near(len(l), 12), "its length")
			end
		end
		assert(legs[1].bz > 0 and legs[2].bz < legs[1].bz, "one way, then back")
		assert(#R.zigzag(run, 30, 0) == 1, "no legs: straight")
	end,
}
