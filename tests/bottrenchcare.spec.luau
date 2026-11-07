--!strict
local Cfg = require("../src/shared/Config/Bots")
local Build = require("../src/shared/Config/Build")
local C = require("../src/shared/Rules/BotTrenchCare")

local K = Cfg.Trenches.Care
local TH = Build.Trench.hp

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end

local function square(over: { [string]: any }): C.SquareCare
	local s: any = { used = 0, safe = 0, dugout = false, base = false, link = false, heat = 0, hot = false }
	for k, v in over do
		s[k] = v
	end
	return s
end

return {
	["shell map: a shell counts in its cell, half in the next, fading by half every `half` s"] = function()
		local map: C.ShellMap = {}
		C.note(map, 5, 5, K.Map.shell, 0, K.Map)
		assert(near(C.heatAt(map, 5, 5, 0, K.Map), K.Map.shell))
		assert(near(C.heatAt(map, 5 + K.Map.cell, 5, 0, K.Map), K.Map.shell / 2), "the next cell: half")
		assert(C.heatAt(map, 5 + 3 * K.Map.cell, 5, 0, K.Map) == 0, "far off: none")
		assert(near(C.heatAt(map, 5, 5, K.Map.half, K.Map), K.Map.shell / 2), "half after `half` s")
		C.note(map, 6, 6, K.Map.shell, K.Map.half, K.Map)
		assert(near(C.heatAt(map, 5, 5, K.Map.half, K.Map), 1.5 * K.Map.shell), "the faded one and the new one")
	end,
	["shelledNear: a shell close by and lately, not a death, not an old one"] = function()
		local H = K.Hot
		local ev = { { x = 0, z = 0, at = 100, kind = "shell" }, { x = 200, z = 0, at = 100, kind = "death" } }
		assert(C.shelledNear(ev, H.radius - 1, 0, 100 + H.seconds, H.radius, H.seconds))
		assert(not C.shelledNear(ev, H.radius + 1, 0, 100, H.radius, H.seconds), "too far")
		assert(not C.shelledNear(ev, 0, 0, 100 + H.seconds + 1, H.radius, H.seconds), "too old")
		assert(not C.shelledNear(ev, 200, 0, 100, H.radius, H.seconds), "a death is not a shell")
	end,
	["decide (always): every square reinforced but one out ahead nobody uses, hot ones wait"] = function()
		local S = K.Score
		assert(S.always, "the default since 2026-11-06")
		assert(C.decide(square({ base = true }), S) == "reinforce", "the base")
		assert(C.decide(square({}), S) == "ignore", "unused, out ahead: left")
		assert(C.decide(square({ link = true }), S) == "reinforce", "the only way up, unused")
		assert(C.decide(square({ used = 0.1 }), S) == "reinforce", "used a little, ahead")
		assert(C.decide(square({ safe = 0.2 }), S) == "reinforce", "unused, behind the front")
		assert(C.decide(square({ used = 1, safe = 1, hot = true }), S) == "wait", "hot: later")
		local h, x = C.target("reinforce", 0, square({ safe = 0.2 }), TH.max, Cfg.Trenches.standHp, TH.extra, S)
		assert(h == TH.max and x == TH.extra, "to the full extra")
	end,
	["decide: critical squares reinforced, the rest by how used and safe, hot ones wait"] = function()
		local S = table.clone(K.Score)
		S.always = false
		assert(C.decide(square({ dugout = true, hot = true }), S) == "reinforce", "a dugout's square, even hot")
		assert(C.decide(square({ base = true }), S) == "reinforce", "the base")
		assert(C.decide(square({}), S) == "ignore", "unused, far forward: left")
		assert(C.decide(square({ used = 1, safe = 1, hot = true }), S) == "wait", "hot: later")
		assert(C.decide(square({ used = 0.5 }), S) == "patch", "a little used, forward: usable again")
		assert(C.decide(square({ used = 1 }), S) == "fix", "busy, forward: whole")
		assert(C.decide(square({ used = 1, safe = 1 }), S) == "reinforce", "busy, near safe ground")
		assert(C.decide(square({ heat = 10 }), S) == "ignore", "unused in shelled ground")
		local _, cool = C.decide(square({ used = 1 }), S)
		local _, hot = C.decide(square({ used = 1, heat = 10 }), S)
		assert(hot < cool, "the shell map's heat counts against")
	end,
	["target: the HP and extra each decision wants"] = function()
		local S = table.clone(K.Score)
		S.always = false
		local stand, max, extra = Cfg.Trenches.standHp, TH.max, TH.extra
		assert(select(1, C.target("patch", 1, square({}), max, stand, extra, S)) == stand)
		local h, x = C.target("fix", 2, square({}), max, stand, extra, S)
		assert(h == max and x == 0)
		h, x = C.target("reinforce", 0, square({ dugout = true }), max, stand, extra, S)
		assert(h == max and x == extra, "a dugout's square: all of it")
		h, x = C.target("reinforce", 99, square({ base = true }), max, stand, extra, S)
		assert(x == extra / #S.steps, "a base square nobody uses yet: the first sheet")
		h, x = C.target("reinforce", S.steps[#S.steps], square({ used = 1, base = true }), max, stand, extra, S)
		assert(x == extra, "a busy base square: all of it")
		assert(K.Gate.extra <= extra / #S.steps, "the gate's extra within a base square's first step")
	end,
	["gate: the next forward line once dug, a dugout in, its base reinforced; or after waiting"] = function()
		local G = K.Gate
		local g: C.GateState =
			{ fireLaid = true, squares = 10, dug = 10, base = 4, reinforced = 4, dugout = true, since = 0 }
		assert(C.gate(g, G))
		local function with(k: string, v: any): C.GateState
			local c: any = table.clone(g)
			c[k] = v
			return c
		end
		assert(not C.gate(with("fireLaid", false), G))
		assert(not C.gate(with("dug", 5), G))
		assert(not C.gate(with("dugout", false), G))
		assert(not C.gate(with("reinforced", 1), G))
		assert(C.gate(with("base", 0), G), "no base (a forward line's): nothing to reinforce")
		local late = with("dugout", false)
		late.since = G.wait
		assert(C.gate(late, G), "goes on after waiting")
	end,
	["networks and linkRun: a separate network near the main one gets a way across"] = function()
		local J = K.Join
		local segs = {
			{ ax = 0, az = 0, bx = 8, bz = 0 },
			{ ax = 8, az = 0, bx = 16, bz = 0 }, -- (joined to the first)
			{ ax = 16, az = 40, bx = 24, bz = 40 },
			{ ax = 24, az = 40, bx = 32, bz = 40 },
			{ ax = 32, az = 40, bx = 40, bz = 40 }, -- (three apart, 40 off: a second network)
			{ ax = 200, az = 0, bx = 208, bz = 0 }, -- (one alone far off)
		}
		local net = C.networks(segs, J.touch)
		assert(net[1] == net[2] and net[3] == net[4] and net[4] == net[5] and net[1] ~= net[3] and net[6] ~= net[1])
		local run = C.linkRun(segs, net, net[1], {}, J) :: C.Seg
		assert(run and near(run.ax, 16) and near(run.az, 40), "from the other's nearest end")
		assert(near(run.bx, 16) and near(run.bz, J.short), "to the main one's side, stopping short")
		local next = C.linkRun(segs, net, net[1], { [C.endKey(16, 40)] = true }, J) :: C.Seg
		assert(next and not (near(next.ax, 16) and near(next.az, 40)), "an end tried before: the next nearest")
		local small = C.networks({ segs[1], segs[2], segs[6] }, J.touch)
		assert(C.linkRun({ segs[1], segs[2], segs[6] }, small, small[1], {}, J) == nil, "too small and too far")
	end,
}
