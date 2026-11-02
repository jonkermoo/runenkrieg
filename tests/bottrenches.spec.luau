--!strict
local Cfg = require("../src/shared/Config/Bots")
local Build = require("../src/shared/Config/Build")
local R = require("../src/shared/Rules/BotTrenches")

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
		local x, z = R.fireStep(10, 5, -1, 0, step)
		assert(near(x, 10 - step) and near(z, 5))
		-- (on the wall, short of its top edge, high enough to see over the parapet)
		assert(step > TB.floor and step < TB.floor + TB.depth / math.tan(math.rad(TB.wallAngle)))
		assert(T.rise + 4.5 > TB.depth + 2.3, "eyes over the parapet")
		assert(math.abs(R.stepOut(4.25, 59, T.rise) - 6.29) < 0.05, "the wider trench: 6.3 as before")
		assert(math.abs(R.stepOut(3, 59, T.rise) - 5.04) < 0.05, "the slimmer trench: about 5.05")
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
}
