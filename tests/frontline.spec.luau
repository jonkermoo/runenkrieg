--!strict
local Cfg = require("../src/shared/Config/Frontline")
local Map1 = require("../src/shared/Config/Maps/Map1")
local R = require("../src/shared/Rules/Frontline")

local N = #Map1.sectors

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- counts with `w` West and `e` East soldiers in sector `i`'s zone, nobody elsewhere
local function at(i: number, w: number, e: number): { { West: number, East: number } }
	local out = {}
	for k = 1, N do
		out[k] = if k == i then { West = w, East = e } else { West = 0, East = 0 }
	end
	return out
end

-- runs `seconds` of ticks with the same counts (and momentum `rate`); every event in order
local function hold(state: R.State, counts: any, seconds: number, rate: number?): { R.Event }
	local events = {}
	for _ = 1, math.round(seconds / Cfg.Tick) do
		for _, ev in R.step(state, Cfg, counts, Cfg.Tick, rate) do
			table.insert(events, ev)
		end
	end
	return events
end

return {
	["Map 1 starts: West holds S1-S2, S3 neutral, East holds S4-S5; both attack S3"] = function()
		local s = R.new(Map1.sectors)
		assert(N == 5)
		assert(s.owner[1] == "West" and s.owner[2] == "West" and s.owner[3] == "Neutral")
		assert(s.owner[4] == "East" and s.owner[5] == "East")
		assert(s.control[1] == 1 and s.control[3] == 0 and s.control[5] == -1)
		assert(R.target(s, "West") == 3 and R.target(s, "East") == 3)
		assert(R.winner(s) == nil)
	end,
	["one soldier takes the neutral S3 in half the capture time; more go faster, up to the cap"] = function()
		local s = R.new(Map1.sectors)
		local ev = hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 2)
		assert(#ev == 1 and ev[1].kind == "Captured" and ev[1].index == 3 and ev[1].side == "West")
		assert(s.owner[3] == "West" and s.control[3] == 1)
		assert(near(R.push(Cfg, 2, 0, 1) :: number, 2 * R.push(Cfg, 1, 0, 1) :: number), "two soldiers twice as fast")
		assert(R.push(Cfg, 10, 0, 1) == R.push(Cfg, Cfg.MaxAdvantage, 0, 1), "capped")
		assert(near(R.push(Cfg, 3, 1, 1) :: number, R.push(Cfg, 2, 0, 1) :: number), "by the lead")
		assert(R.push(Cfg, 0, 0, 1) == nil and R.push(Cfg, 2, 2, 1) == nil)
	end,
	["an enemy sector goes neutral first, then is taken"] = function()
		local s = R.new(Map1.sectors)
		hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 2) -- West takes S3
		assert(R.target(s, "West") == 4 and R.target(s, "East") == 3, "the front moved: East now attacks S3")
		local ev = hold(s, at(4, 1, 0), Cfg.CaptureSeconds)
		assert(#ev == 2, `{#ev} events`)
		assert(ev[1].kind == "Neutral" and ev[1].index == 4 and ev[1].side == "West")
		assert(ev[2].kind == "Captured" and ev[2].index == 4 and ev[2].side == "West")
	end,
	["even numbers in a zone hold it; an empty one drifts back to its holder"] = function()
		local s = R.new(Map1.sectors)
		hold(s, at(3, 1, 0), 4)
		local c = s.control[3]
		assert(c > 0 and s.owner[3] == "Neutral")
		hold(s, at(3, 2, 2), 4)
		assert(near(s.control[3], c), "contested: held")
		hold(s, at(3, 0, 0), Cfg.DrainSeconds)
		assert(s.control[3] == 0, "drifted back to neutral")
		-- a held sector partly pulled drifts back to its holder's end
		hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 2)
		hold(s, at(4, 1, 0), 4)
		assert(s.control[4] > -1 and s.owner[4] == "East")
		hold(s, at(4, 0, 0), Cfg.DrainSeconds)
		assert(s.control[4] == -1)
	end,
	["defenders in their own attacked sector push it back"] = function()
		local s = R.new(Map1.sectors)
		hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 2)
		hold(s, at(4, 2, 0), 3)
		local c = s.control[4]
		hold(s, at(4, 1, 3), 2)
		assert(s.control[4] < c and s.owner[4] == "East")
	end,
	["only the sectors next to a front move: soldiers deeper in do nothing"] = function()
		local s = R.new(Map1.sectors)
		local ev = hold(s, at(5, 5, 0), Cfg.CaptureSeconds)
		assert(#ev == 0 and s.owner[5] == "East" and s.control[5] == -1)
		ev = hold(s, at(1, 0, 5), Cfg.CaptureSeconds)
		assert(#ev == 0 and s.owner[1] == "West")
	end,
	["pushing all the way takes the enemy HQ (S5 / S1) and wins"] = function()
		local s = R.new(Map1.sectors)
		for i = 3, N do
			assert(R.target(s, "West") == i)
			hold(s, at(i, 3, 0), Cfg.CaptureSeconds)
			assert(s.owner[i] == "West", `took sector {i}`)
		end
		assert(R.target(s, "West") == nil, "nothing left to take")
		assert(R.winner(s) == "West")
		local e = R.new(Map1.sectors)
		for i = 3, 1, -1 do
			hold(e, at(i, 0, 3), Cfg.CaptureSeconds)
		end
		assert(R.winner(e) == "East")
	end,
	["momentum: none until the front has stood still a while, then faster, capped"] = function()
		local M = Cfg.Momentum
		assert(R.momentum(Cfg, 0) == 1 and R.momentum(Cfg, M.after) == 1)
		assert(near(R.momentum(Cfg, M.after + 60), 1 + M.perMinute))
		assert(R.momentum(Cfg, M.after + 60 * 1000) == M.max)
		-- at x2 a capture takes half the time
		local s = R.new(Map1.sectors)
		local ev = hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 4, 2)
		assert(#ev == 1 and ev[1].kind == "Captured")
	end,
	["a match starts once each side has its players"] = function()
		assert(R.ready(1, 1, Cfg.MinPerSide))
		assert(not R.ready(3, 0, 1) and not R.ready(0, 2, 1))
	end,
	["Defend: a kill near your own sector while the enemy attacks it"] = function()
		local s = R.new(Map1.sectors)
		local S2, S3 = Map1.sectors[2], Map1.sectors[3]
		-- at the start both attack the neutral S3: nobody defends
		assert(not R.defends(s, Map1.sectors, "West", { { S3.x, S3.z } }, Cfg.DefendReach))
		hold(s, at(3, 0, 1), Cfg.CaptureSeconds / 2) -- East takes S3, now attacks West's S2
		assert(R.defends(s, Map1.sectors, "West", { { S2.x + S2.radius + 5, S2.z } }, Cfg.DefendReach))
		assert(not R.defends(s, Map1.sectors, "West", { { S2.x + 500, S2.z } }, Cfg.DefendReach), "too far")
		assert(not R.defends(s, Map1.sectors, "East", { { S2.x, S2.z } }, Cfg.DefendReach), "East is attacking")
		-- either the killer or the victim may be the one near it
		assert(R.defends(s, Map1.sectors, "West", { { 0, 0 }, { S2.x, S2.z } }, Cfg.DefendReach))
	end,
	["spawns: HQ until the first capture, then each side's frontmost held sector"] = function()
		local s = R.new(Map1.sectors)
		assert(R.spawn(s, "West", false) == 1 and R.spawn(s, "East", false) == N)
		assert(R.spawn(s, "West", true) == 2 and R.spawn(s, "East", true) == 4)
		hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 2)
		assert(R.spawn(s, "West", true) == 3 and R.spawn(s, "East", true) == 4)
		-- a side whose HQ went neutral spawns there still
		s.owner = { "Neutral", "East", "East", "East", "East" }
		assert(R.spawn(s, "West", true) == 1 and R.spawn(s, "East", true) == 2)
	end,
	["zones: within the radius across the ground and the height"] = function()
		assert(R.inZone(30, 30, 0, 45, Cfg.Height))
		assert(not R.inZone(40, 30, 0, 45, Cfg.Height))
		assert(not R.inZone(0, 0, Cfg.Height + 1, 45, Cfg.Height) and R.inZone(0, 0, -Cfg.Height, 45, Cfg.Height))
	end,
	["two different teams each match, any pair, either side"] = function()
		local teams = { "uniform1", "uniform2", "uniform3" }
		local seen: { [string]: boolean } = {}
		for a = 0, 9 do
			for b = 0, 9 do
				local p = R.pair(teams, a / 10, b / 10)
				assert(p.West ~= p.East and table.find(teams, p.West) and table.find(teams, p.East))
				seen[R.pairText(p)] = true
			end
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		assert(n == 6, `{n} of the 6 ordered pairs`)
		local back = R.parsePair("uniform2,uniform3")
		assert(back and back.West == "uniform2" and back.East == "uniform3")
		assert(R.parsePair("uniform2,uniform2") == nil and R.parsePair("x") == nil and R.parsePair(nil) == nil)
		assert(R.sideOf(back, "uniform3") == "East" and R.sideOf(back, "uniform1") == nil and R.sideOf(nil, "x") == nil)
	end,
}
