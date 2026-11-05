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

-- runs `seconds` of ticks with the same counts (and one soldier's worth `unit`); every event in order
local function hold(state: R.State, counts: any, seconds: number, unit: number?): { R.Event }
	local events = {}
	for _ = 1, math.round(seconds / Cfg.Tick) do
		for _, ev in R.step(state, Cfg, counts, Cfg.Tick, unit) do
			table.insert(events, ev)
		end
	end
	return events
end

return {
	["feet on the ground: the footprint covers the middle and the corners; a held soldier lifted only when the ground rose"] = function()
		local f = R.footprint(Cfg.Line.foot)
		assert(#f == 9, `{#f} samples`)
		local corners = 0
		for _, o in f do
			if math.abs(o[1]) == Cfg.Line.foot and math.abs(o[2]) == Cfg.Line.foot then
				corners += 1
			end
		end
		assert(corners == 4, "the four corners sampled")
		assert(R.liftNeeded(10.2, 10, 0.2) == 0, "standing right: no lift")
		assert(R.liftNeeded(11, 10, 0.2) == 0, "standing higher: no lift (never pushed down)")
		assert(math.abs(R.liftNeeded(9, 10, 0.2) - 1.2) < 1e-9, "ground 1 over the feet: lifted 1.2")
		assert(Cfg.Line.recheck > 0 and Cfg.Line.recheck <= 1 and Cfg.Line.relift >= 0)
	end,
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
	["a bot counts half a player: two bots push as one player, a bot alone at half speed (user 2026-11-03)"] = function()
		assert(R.weight(Cfg, false) == 1 and R.weight(Cfg, true) == Cfg.BotWeight and Cfg.BotWeight == 0.5)
		local bot = R.weight(Cfg, true)
		assert(near(R.push(Cfg, bot, 0, 1) :: number, R.push(Cfg, 1, 0, 1) :: number / 2), "a bot alone: half speed")
		assert(near(R.push(Cfg, 2 * bot, 0, 1) :: number, R.push(Cfg, 1, 0, 1) :: number), "two bots: one player")
		assert(R.push(Cfg, 1, 2 * bot, 1) == nil, "a player against two bots: contested")
		assert(near(R.push(Cfg, 1 + bot, 1, 1) :: number, R.push(Cfg, bot, 0, 1) :: number), "by the lead in weight")
		-- a bot alone takes the neutral S3 in the whole capture time
		local s = R.new(Map1.sectors)
		local c = at(3, 0, 0)
		c[3].West = bot
		assert(#hold(s, c, Cfg.CaptureSeconds - 0.5) == 0 and s.owner[3] ~= "West", "not yet just before")
		hold(s, c, 1)
		assert(s.owner[3] == "West", "taken at the full capture time")
	end,
	["the admin readout's rates: only the sectors either side may attack move"] = function()
		local s = R.new(Map1.sectors)
		local c = at(3, 2, 0)
		c[1].East = 4 -- deep in West's ground: out of East's reach
		local r = R.rates(s, Cfg, c, 1)
		assert(near(r[3], 2 * 2 / Cfg.CaptureSeconds), "S3: two soldiers' lead, per second")
		assert(r[1] == 0 and r[2] == 0, "out of reach / empty")
		assert(near(R.rates(s, Cfg, c, 2)[3], r[3] / 2), "a soldier's worth twice as big: half as fast")
		c[3].East = 2
		assert(R.rates(s, Cfg, c, 1)[3] == 0, "contested")
		assert(near(R.eta(0, 0.1) :: number, 10) and near(R.eta(0.5, -0.1) :: number, 15) and R.eta(0.3, 0) == nil)
	end,
	["an enemy sector goes neutral first, then is taken"] = function()
		local s = R.new(Map1.sectors)
		hold(s, at(3, 1, 0), Cfg.CaptureSeconds / 2) -- West takes S3
		assert(R.target(s, "West") == 4 and R.target(s, "East") == 3, "the front moved: East now attacks S3")
		local ev = hold(s, at(4, 1, 0), Cfg.CaptureSeconds + Cfg.Tick)
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
		hold(s, at(4, 2, 0), Cfg.CaptureSeconds / 8) -- (partway: still East's)
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
	["no momentum: a capture's speed is the soldiers in the zone only (user 2026-11-04)"] = function()
		assert(Cfg.Momentum == nil and (R :: any).momentum == nil)
	end,
	["a soldier's worth grows with the server, never under the minimum"] = function()
		local U = Cfg.Unit
		assert(R.unit(Cfg, 0, 0) == U.min and R.unit(Cfg, 1, 1) == math.max(U.min, U.perSoldier))
		assert(near(R.unit(Cfg, 40, 40), math.max(U.min, 40 * U.perSoldier)), "the sides' mean strength")
		assert(near(R.unit(Cfg, 30, 10), R.unit(Cfg, 20, 20)), "uneven sides: their mean")
		assert(R.unit(Cfg, 40, 40) >= R.unit(Cfg, 20, 20), "bigger servers: more soldiers to a soldier's worth")
	end,
	["20v20, 30v30, 40v40 bots: a typical lead takes an enemy sector in 8-10 s (user 2026-11-04)"] = function()
		assert(Cfg.CaptureSeconds >= 8 and Cfg.CaptureSeconds <= 10)
		for _, n in { 20, 30, 40 } do
			local side = n * R.weight(Cfg, true) -- (n bots a side)
			local unit = R.unit(Cfg, side, side)
			-- West holds S3 (taken first), East pushes it with a lead of one soldier's worth: neutral, then East's
			local s = R.new(Map1.sectors)
			hold(s, at(3, 1, 0), Cfg.CaptureSeconds)
			assert(s.owner[3] == "West", `{n}v{n}: set up`)
			local c = at(3, 0, unit)
			local took = 0
			while s.owner[3] ~= "East" and took < 60 do
				R.step(s, Cfg, c, Cfg.Tick, unit)
				took += Cfg.Tick
			end
			assert(took >= 8 - Cfg.Tick and took <= 10 + Cfg.Tick, `{n}v{n}: {took} s`)
			-- twice the lead: twice as fast; a lead of one bot alone still moves it
			assert(near(R.push(Cfg, 2 * unit, 0, 1, unit) :: number, 2 * (R.push(Cfg, unit, 0, 1, unit) :: number)))
			assert((R.push(Cfg, R.weight(Cfg, true), 0, 1, unit) :: number) > 0)
		end
		-- the bigger the server, the more soldiers a soldier's worth
		assert(R.unit(Cfg, 10, 10) < R.unit(Cfg, 15, 15) and R.unit(Cfg, 15, 15) < R.unit(Cfg, 20, 20))
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
	["each map is fought by its own pair (user 2026-11-04), a bad or missing one rolled"] = function()
		local teams = { "uniform1", "uniform2", "uniform3" }
		local p = R.mapPair({ West = "uniform1", East = "uniform3" }, teams, "uniform1", 0.9, 0.9)
		assert(p.West == "uniform1" and p.East == "uniform3")
		for _, bad in { nil, {}, { West = "uniform2", East = "uniform3" }, { West = "uniform1", East = "uniform1" } } do
			local r = R.mapPair(bad, teams, "uniform1", 0, 0)
			assert(r.West == "uniform1" or r.East == "uniform1", "rolled, grey in it")
		end
		for _, key in { "Map1", "LanternMeadows" } do
			local map = require(`../src/shared/Config/Maps/{key}`) :: any
			local mp = R.mapPair(map.pair, teams, "uniform1", 0, 0)
			assert(mp.West == map.pair.West and mp.East == map.pair.East, `{key}'s own pair`)
		end
	end,
	["the grey team every match, against green or brown, either side; never green against brown"] = function()
		local teams = { "uniform1", "uniform2", "uniform3" }
		local seen: { [string]: boolean } = {}
		for a = 0, 9 do
			for b = 0, 9 do
				local p = R.pair(teams, "uniform1", a / 10, b / 10)
				assert(p.West ~= p.East and table.find(teams, p.West) and table.find(teams, p.East))
				assert(p.West == "uniform1" or p.East == "uniform1", R.pairText(p))
				seen[R.pairText(p)] = true
			end
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		assert(n == 4, `{n} of the 4 ordered pairs`)
		assert(not seen["uniform2,uniform3"] and not seen["uniform3,uniform2"])
		assert(R.pair(teams, "uniform1", 0.99, 0.99).East == "uniform1")
		local back = R.parsePair("uniform2,uniform3")
		assert(back and back.West == "uniform2" and back.East == "uniform3")
		assert(R.parsePair("uniform2,uniform2") == nil and R.parsePair("x") == nil and R.parsePair(nil) == nil)
		assert(R.sideOf(back, "uniform3") == "East" and R.sideOf(back, "uniform1") == nil and R.sideOf(nil, "x") == nil)
	end,
	["spawns: frontmost held sector, one back while the enemy leads there (user 2026-10-27)"] = function()
		local s = R.new(Map1.sectors)
		assert(R.spawnSector(s, "West", false, at(2, 0, 3)) == 1, "no capture yet: the HQ")
		assert(R.spawnSector(s, "West", true, at(2, 0, 0)) == 2, "frontmost held")
		assert(R.spawnSector(s, "West", true, at(2, 1, 2)) == 1, "the enemy leads at S2: one back")
		assert(R.spawnSector(s, "West", true, at(2, 2, 2)) == 2, "even: stays")
		assert(R.spawnSector(s, "East", true, at(4, 3, 0)) == N, "East steps back toward its own end")
		s.owner[2] = "East"
		assert(R.spawnSector(s, "West", true, at(1, 0, 5)) == 1, "never behind its own HQ")
	end,
	["waves: one clock every 15 s from the countdown's end (user 2026-10-27)"] = function()
		local W = Cfg.Waves
		assert(W.every == 15 and W.dead == 5 and W.shield > 0, "the user's numbers")
		assert(R.nextWave(100, 15, 90) == 100 and R.nextWave(100, 15, 100) == 100)
		assert(
			R.nextWave(100, 15, 100.1) == 115 and R.nextWave(100, 15, 115) == 115 and R.nextWave(100, 15, 129) == 130
		)
		assert(R.nextWave(100, 0, 500) == 100, "no period: no later wave")
	end,
	["the wave line: side by side from the middle out, rows behind (user 2026-10-27, 2026-10-31)"] = function()
		local L = Cfg.Line
		local seen = {}
		for k = 1, L.perRow * 2 do
			local r, b = R.slot(k, L)
			local key = `{r},{b}`
			assert(not seen[key], `slot {k} is free`)
			seen[key] = true
			assert(b == (if k <= L.perRow then 0 else L.rowGap), `slot {k}'s row`)
			assert(math.abs(r) <= L.perRow / 2 * L.gap, `slot {k} within the row`)
		end
		local r1 = R.slot(1, L)
		local r2 = R.slot(2, L)
		local r3 = R.slot(3, L)
		assert(r1 == 0 and r2 == L.gap and r3 == -L.gap, "the middle, then right, then left")
	end,
	["the howitzer only for a side down to its last two sectors; the field gun always (user 2026-11-03)"] = function()
		local A = Cfg.Artillery
		assert(A.unlockAt == 2) -- user 2026-11-03: "unlock at the second to last sector, not the last sector"
		local s = R.new(Map1.sectors)
		assert(R.held(s, "West") == 2 and R.held(s, "East") == 2, "each starts with its HQ and the next")
		assert(R.gunLocked(A, "Howitzer", R.held(s, "West")) == nil, "from the start (user: 'Yes, from the start')")
		assert(R.gunLocked(A, "FieldGun", 3) == nil and R.gunLocked(A, "FieldGun", 1) == nil)
		assert(R.gunLocked(A, "Trench", 3) == nil, "other pieces never wait")
		-- West takes the middle: three from its end, locked; East still two
		s.owner = { "West", "West", "West", "East", "East" }
		assert(R.held(s, "West") == 3 and R.gunLocked(A, "Howitzer", R.held(s, "West")) == A.why, "West pushed out")
		assert(R.gunLocked(A, "Howitzer", R.held(s, "East")) == nil, "East at its last two")
		-- pushed back to its HQ: still unlocked
		s.owner = { "West", "Neutral", "East", "East", "East" }
		assert(R.held(s, "West") == 1 and R.gunLocked(A, "Howitzer", R.held(s, "West")) == nil)
		assert(R.held(s, "East") == 3 and R.gunLocked(A, "Howitzer", R.held(s, "East")) ~= nil)
	end,
	["pushed back to the last two, the howitzer stays for the match (user 2026-11-04)"] = function()
		local A = Cfg.Artillery
		assert(not R.latched(A, false, 2, 2), "holding two from the start: not a push back")
		assert(not R.latched(A, false, 2, 3) and not R.latched(A, false, 4, 3), "out past it, or back to three")
		assert(R.latched(A, false, 3, 2) and R.latched(A, false, 2, 1), "pushed back to two, or one")
		assert(R.latched(A, true, 2, 4), "kept once latched")
		assert(R.gunLocked(A, "Howitzer", 4, true) == nil, "latched: open at any count")
		assert(R.gunLocked(A, "Howitzer", 4, false) == A.why and R.gunLocked(A, "Howitzer", 4) == A.why)
		assert(R.gunLocked(A, "Trench", 4, false) == nil)
	end,
	["the center taken opens the howitzer for both sides (user 2026-11-04)"] = function()
		assert(table.concat(R.center(5), ",") == "3" and table.concat(R.center(3), ",") == "2")
		assert(table.concat(R.center(4), ",") == "2,3" and #R.center(0) == 0 and table.concat(R.center(1), ",") == "1")
		local s = R.new(Map1.sectors)
		local start = table.clone(s.owner)
		assert(start[3] == "Neutral" and not R.centerTaken(start, s.owner), "the start")
		s.owner[2] = "East"
		assert(not R.centerTaken(start, s.owner), "a sector off the center")
		s.owner[3] = "West"
		assert(R.centerTaken(start, s.owner), "West takes the center")
		s.owner[3] = "East"
		assert(R.centerTaken(start, s.owner), "or East")
		-- an even chain: either middle sector lost to the other side
		local st, now = { "West", "West", "East", "East" }, { "West", "West", "West", "East" }
		assert(R.centerTaken(st, now) and not R.centerTaken(st, st))
		assert(not R.centerTaken(st, { "West", "Neutral", "East", "East" }), "neutralised isn't taken")
	end,
	["reinforcements only on a big mismatch (user 2026-10-29)"] = function()
		local C = Cfg.Reinforcements
		assert(C.gap == 3 and C.share == 0.25 and C.times == 1, "no comeback pay since the marks rebalance")
		assert(R.reinforced(C, 10, 10) == nil and R.reinforced(C, 12, 10) == nil, "near enough")
		assert(R.reinforced(C, 13, 10) == "East", "3 more and 30% more")
		assert(R.reinforced(C, 20, 17) == nil, "3 more but under 25%")
		assert(R.reinforced(C, 1, 4) == "West" and R.reinforced(C, 0, 3) == "West")
	end,
}
