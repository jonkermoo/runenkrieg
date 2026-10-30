--!strict
local Cfg = require("../src/shared/Config/Firing")
local F = require("../src/shared/Rules/Firing")
local W = require("../src/shared/Config/Weapons")

local OPEN = { openAt = Cfg.BoltCycle.back, reloadOpenAt = Cfg.ReloadCycle.back }
local S = Cfg.Single
local CARCANO: F.Gun = {
	capacity = 6,
	clip = "Enbloc",
	boltTime = 0.9,
	reloadTime = 2.5,
	fireTime = 0.15,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
	singleOpen = S.open,
	singleRound = S.round,
	singleClose = S.close,
}
local GEWEHR: F.Gun = {
	capacity = 5,
	clip = "Stripper",
	boltTime = 0.9,
	reloadTime = 2.8,
	fireTime = 0.15,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
	singleOpen = S.open,
	singleRound = S.round,
	singleClose = S.close,
}
-- the M1897 (loose shells, its own load times)
local PUMP: F.Gun = {
	capacity = 5,
	clip = "Loose",
	boltTime = 0.6,
	reloadTime = 0,
	fireTime = 0.15,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
	singleOpen = 0.25,
	singleRound = 0.45,
	singleClose = 0.25,
}
-- the Nagant's gate (a revolver: 7 chambers, its own load times)
local NAGANT: F.Gun = {
	capacity = 7,
	clip = "Gate",
	boltTime = 0,
	reloadTime = 0,
	fireTime = Cfg.PistolFireTime,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
	singleOpen = 0.5,
	singleRound = 0.85,
	singleClose = 0.45,
}
-- the Webley's top break (a revolver: 6 chambers, all reloaded at once)
local WEBLEY: F.Gun = {
	capacity = 6,
	clip = "BreakOpen",
	boltTime = 0,
	reloadTime = 2.0,
	fireTime = Cfg.PistolFireTime,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
	singleOpen = S.open,
	singleRound = S.round,
	singleClose = S.close,
}
-- the semi-automatics (W2): a stripper-clip one, a charger one (two 5-round chargers), a box one
local function semi(capacity: number, clip: string, clipSize: number?): F.Gun
	return {
		capacity = capacity,
		clip = clip,
		auto = true,
		clipSize = clipSize,
		clipTime = if clipSize then 0.8 else nil,
		boltTime = 0.12,
		reloadTime = 2.5,
		fireTime = 0.35,
		openAt = OPEN.openAt,
		reloadOpenAt = OPEN.reloadOpenAt,
		singleOpen = S.open,
		singleRound = S.round,
		singleClose = S.close,
	}
end
local MONDRAGON, REMINGTON, WINCHESTER = semi(8, "Stripper"), semi(10, "Stripper", 5), semi(15, "Box")
-- when a single load started at `t0` with every round going in ends
local function loadDone(t0: number, rounds: number): number
	return t0 + S.open + rounds * S.round + S.close
end

return {
	["a full rifle has one round chambered and a full clip in the magazine: Gewehr 5 + 1, Carcano 6 + 1"] = function()
		local s = F.new(CARCANO)
		assert(s.chambered and not s.spent and s.magazine == 6, "Carcano: 6 + 1")
		assert(F.rounds(s) == 7, "seven rounds in all")
		assert(F.rounds(F.new(GEWEHR)) == 6, "Gewehr: six")
	end,
	["a shot leaves the case in the chamber: the next click works the bolt"] = function()
		local s = F.new(GEWEHR)
		assert(F.next(s, 0) == "Fire")
		assert(F.fire(s, GEWEHR, 0))
		assert(s.spent and not s.chambered, "case in the chamber")
		assert(F.next(s, 1) == "Bolt", "click = work the bolt")
		local ok, _, out = F.bolt(s, GEWEHR, 1)
		assert(ok and out == "Casing" and s.chambered and s.magazine == 4, "case out, next round in")
	end,
	["a shot faster than the bolt allows is rejected"] = function()
		local s = F.new(GEWEHR)
		assert(F.fire(s, GEWEHR, 0))
		local ok, why = F.fire(s, GEWEHR, 0.5)
		assert(not ok and why == "bolt", "no second shot before working the bolt")
		assert(F.bolt(s, GEWEHR, 0.5))
		ok, why = F.fire(s, GEWEHR, 0.5 + GEWEHR.boltTime / 2)
		assert(not ok and why == "busy", "nor while the bolt is still moving")
		assert(F.fire(s, GEWEHR, 0.5 + GEWEHR.boltTime), "once it's closed")
	end,
	["spammed shots are counted once"] = function()
		local s = F.new(CARCANO)
		local hits = 0
		for i = 0, 20 do
			if F.fire(s, CARCANO, i * 0.01) then
				hits += 1
			end
		end
		assert(hits == 1, `{hits} shots from one chambered round`)
	end,
	["the server's slack lets a bolt land a little early, never a whole cycle early"] = function()
		local s = F.new(GEWEHR)
		assert(F.fire(s, GEWEHR, 0))
		assert(F.bolt(s, GEWEHR, 0.2))
		assert(F.fire(s, GEWEHR, 0.2 + GEWEHR.boltTime - 0.15, Cfg.Slack), "within slack")
		local t = F.new(GEWEHR)
		assert(F.fire(t, GEWEHR, 0))
		assert(F.bolt(t, GEWEHR, 0.2))
		assert(not F.fire(t, GEWEHR, 0.3, Cfg.Slack), "not a cycle early")
	end,
	["shooting the rifle dry, then an empty click"] = function()
		local s = F.new(GEWEHR)
		local t = 0
		for _ = 1, 6 do
			assert(F.fire(s, GEWEHR, t))
			t += 1
			F.bolt(s, GEWEHR, t)
			t += 1
		end
		assert(F.rounds(s) == 0 and not s.spent, "six shots, the last case thrown out")
		assert(s.open, "the bolt stays open on the empty rifle")
		assert(F.next(s, t) == "Open", "the trigger does nothing with the bolt open")
		assert(not F.bolt(s, GEWEHR, t), "nothing for the bolt to do")
	end,
	["the bolt opening on an empty rifle takes only until it is back; the reload starts from it"] = function()
		local s = F.new(GEWEHR)
		s.magazine, s.chambered, s.spent = 0, false, true
		assert(F.bolt(s, GEWEHR, 0) and s.open)
		assert(math.abs(s.busyUntil - GEWEHR.boltTime * GEWEHR.openAt) < 1e-9, "stops at the open point")
		assert(F.reload(s, GEWEHR, 10) and not s.open and s.chambered and s.magazine == 4, "clip in, bolt closed")
		assert(math.abs(s.busyUntil - (10 + GEWEHR.reloadTime * (1 - GEWEHR.reloadOpenAt))) < 1e-9, "no opening")
	end,
	["putting the rifle away mid-action keeps its time left; drawn again it plays out after the draw"] = function()
		local s = F.new(GEWEHR)
		assert(F.fire(s, GEWEHR, 0))
		assert(F.bolt(s, GEWEHR, 1))
		F.pause(s, 1.3) -- 0.6 s of the 0.9 s bolt left
		assert(math.abs(s.paused - 0.6) < 1e-9, "time left kept")
		local left = F.resume(s, 20, Cfg.Resume.delay)
		assert(math.abs(left - 0.6) < 1e-9, "the rest of the bolt plays")
		assert(not F.fire(s, GEWEHR, 20 + Cfg.Resume.delay + 0.3), "still working the bolt after the draw")
		assert(F.fire(s, GEWEHR, 20 + Cfg.Resume.delay + 0.6), "then it can fire")
		local idle = F.new(GEWEHR)
		F.pause(idle, 5)
		assert(F.resume(idle, 9, Cfg.Resume.delay) == 0 and F.fire(idle, GEWEHR, 9), "nothing interrupted: no wait")
	end,
	["en-bloc clips go in only when the magazine is empty; a stripper clip only into an empty magazine"] = function()
		local c = F.new(CARCANO)
		assert(not F.reload(c, CARCANO, 0), "Carcano: not with rounds left")
		c.magazine, c.chambered, c.spent = 0, false, true
		local ok, _, out, kind = F.reload(c, CARCANO, 0)
		assert(ok and out == "Casing" and kind == "Reload" and c.chambered and c.magazine == 5, "Carcano: clip in")
		local g = F.new(GEWEHR)
		assert(not F.reload(g, GEWEHR, 0), "Gewehr: not when full")
		g.magazine, g.chambered, g.spent = 0, false, true
		ok, _, out, kind = F.reload(g, GEWEHR, 0)
		assert(ok and kind == "Reload" and g.magazine == 4 and g.chambered, "Gewehr: empty -> a whole clip, 4 + 1")
	end,
	["the Carcano reloads only with 1 or 0 rounds left"] = function()
		local c = F.new(CARCANO)
		c.magazine = 1
		assert(not F.reload(c, CARCANO, 0), "Carcano: 2 rounds left (1 + 1)")
		c.magazine = 0
		assert(F.reload(c, CARCANO, 0) and F.rounds(c) == 7, "Carcano: 1 left (chambered) -> 6 + 1")
		local e = F.new(CARCANO)
		e.magazine, e.chambered = 0, false
		assert(F.reload(e, CARCANO, 0) and F.rounds(e) == 6, "Carcano: 0 left -> 5 + 1 (the clip feeds the chamber)")
	end,
	["with rounds left a stripper-clip rifle loads single rounds until full, then closes on one"] = function()
		local g = F.new(GEWEHR)
		assert(F.fire(g, GEWEHR, 0))
		assert(F.bolt(g, GEWEHR, 1)) -- 4 + 1
		assert(F.fire(g, GEWEHR, 2)) -- 4 + a spent case
		assert(F.bolt(g, GEWEHR, 3)) -- 3 + 1
		assert(F.fire(g, GEWEHR, 4)) -- 3 + a spent case: room for 2
		local ok, _, out, kind = F.reload(g, GEWEHR, 5)
		assert(ok and kind == "Load" and out == "Casing", "single rounds; the case comes out")
		assert(F.next(g, 5.2) == "Load", "a click now stops the loading")
		assert(F.magazineAt(g, 5 + S.open + S.round + 0.01) == 4, "the first round is in after one round's time")
		local done = loadDone(5, 2)
		assert(not F.fire(g, GEWEHR, done - 0.05), "busy until the bolt has closed")
		assert(F.fire(g, GEWEHR, done) and g.magazine == 4 and not g.load, "full (5) and closed on one: 4 + 1, fired")
	end,
	["a click stops single loading after the round in the hand"] = function()
		local g = F.new(GEWEHR)
		g.magazine = 1 -- 1 + 1: room for 4
		assert(F.reload(g, GEWEHR, 0))
		assert(not g.chambered, "opening the bolt throws the live round out")
		local k = F.stopLoad(g, S.open + S.round * 1.4) -- the second round is in the hand
		assert(k == 2, `the round in the hand still goes in ({k})`)
		assert(F.next(g, loadDone(0, 2) - 0.05) == "Busy", "the bolt is closing")
		assert(
			F.next(g, loadDone(0, 2)) == "Fire" and g.magazine == 2 and g.chambered,
			"1 + 2 in, one chambered: 2 + 1"
		)
	end,
	["a live round in the chamber is lost when the bolt opens to load"] = function()
		local g = F.new(GEWEHR)
		g.magazine = 3 -- 3 + 1 live
		local ok, _, out = F.reload(g, GEWEHR, 0)
		assert(ok and out == "Round", "the live round is thrown out")
		F.settle(g, loadDone(0, 2))
		assert(F.rounds(g) == 5, `full magazine, one of it chambered: 4 + 1 (got {F.rounds(g)})`)
	end,
	["single loading put away keeps going after the draw"] = function()
		local g = F.new(GEWEHR)
		g.magazine = 2 -- room for 3
		assert(F.reload(g, GEWEHR, 0))
		F.pause(g, S.open + S.round * 0.5) -- the first round in the hand
		assert(g.load and g.load.rounds == 1, "the round in the hand will still go in")
		local left = F.resume(g, 10, Cfg.Resume.delay)
		assert(left > 0, "the rest plays after the draw")
		assert(F.next(g, 10 + Cfg.Resume.delay + left - 0.05) == "Busy", "still loading / closing")
		assert(F.next(g, 10 + Cfg.Resume.delay + left) == "Fire" and g.magazine == 2, "2 + 1 in, closed: 2 + 1")
	end,
	["a semi-automatic fires every click, at most one shot per fireTime"] = function()
		local s = F.new(MONDRAGON)
		local ok, _, out = F.fire(s, MONDRAGON, 0)
		assert(ok and out == "Casing", "the action throws the case out itself")
		assert(s.chambered and not s.spent and s.magazine == 7, "the next round is in: 7 + 1")
		assert(F.next(s, 0.2) == "Busy", "too soon")
		assert(not F.fire(s, MONDRAGON, 0.2), "no second shot within fireTime")
		assert(F.next(s, 0.35) == "Fire", "no bolt to work: the next click fires")
	end,
	["a semi-automatic's bolt stays open after the last round"] = function()
		local s = F.new(MONDRAGON)
		for i = 0, 8 do
			assert(F.fire(s, MONDRAGON, i), `shot {i + 1}`)
		end
		assert(s.open and not s.chambered and s.magazine == 0, "held open on the empty magazine")
		assert(F.next(s, 10) == "Open", "the trigger does nothing")
		local ok = F.reload(s, MONDRAGON, 10)
		assert(ok and s.chambered and s.magazine == 7 and not s.open, "a clip in, the bolt closes on a round: 7 + 1")
		assert(s.busyUntil == 10 + 2.5 * (1 - OPEN.reloadOpenAt), "from the open bolt: the clip goes straight in")
	end,
	["a semi-automatic's reload tops up: the chambered round stays"] = function()
		local s = F.new(MONDRAGON)
		assert(not F.reload(s, MONDRAGON, 0), "full: nothing to load")
		F.fire(s, MONDRAGON, 0)
		F.fire(s, MONDRAGON, 1) -- 6 + 1
		local ok, _, out, kind = F.reload(s, MONDRAGON, 2)
		assert(ok and kind == "Reload" and out == nil, "a clip, nothing thrown out")
		assert(s.magazine == 8 and s.chambered and F.rounds(s) == 9, "full again: 8 + 1")
		assert(s.busyUntil == 2 + 2.5, "one clip")
	end,
	["a charger rifle presses in as many chargers as the room needs"] = function()
		local s = F.new(REMINGTON)
		assert(F.rounds(s) == 11, "10 + 1")
		for i = 0, 3 do
			F.fire(s, REMINGTON, i) -- 4 shots: 6 + 1
		end
		assert(F.clipsFor(s, REMINGTON) == 1, "room for 4: one charger")
		for i = 4, 7 do
			F.fire(s, REMINGTON, i) -- 2 + 1
		end
		assert(F.clipsFor(s, REMINGTON) == 2, "room for 8: two chargers")
		local _, _, _, kind = F.reload(s, REMINGTON, 10)
		assert(kind == "Reload2", "two chargers: their own reload")
		assert(s.magazine == 10 and s.chambered and s.busyUntil == 10 + 2.5 + 0.8, "two chargers take clipTime more")
	end,
	["a box rifle swaps the box whole"] = function()
		local s = F.new(WINCHESTER)
		F.fire(s, WINCHESTER, 0)
		assert(F.clipsFor(s, WINCHESTER) == 1, "one box")
		assert(F.reload(s, WINCHESTER, 1) and s.magazine == 15 and F.rounds(s) == 16, "a fresh box: 15 + 1")
	end,
	["a box swap from an open bolt takes the whole reload and reports the open bolt"] = function()
		local s = F.new(WINCHESTER)
		for i = 0, 15 do
			F.fire(s, WINCHESTER, i)
		end
		assert(s.open, "held open")
		local ok, _, out = F.reload(s, WINCHESTER, 20)
		assert(ok and out == "Open", "the bolt stays back until the plunger lets it go")
		assert(s.busyUntil == 20 + 2.5 and s.magazine == 14 and s.chambered, "the whole swap; 14 + 1")
	end,
	["shots must come from the shooter's own rifle, as a unit direction"] = function()
		assert(F.validShot(5, 1, Cfg.MaxOrigin))
		assert(not F.validShot(30, 1, Cfg.MaxOrigin), "far from the shooter")
		assert(not F.validShot(5, 3, Cfg.MaxOrigin), "not a unit vector")
		assert(not F.validShot(0 / 0, 1, Cfg.MaxOrigin), "NaN")
	end,
	["every gun has its ammunition and action"] = function()
		for name, w in W do
			if not w.ammo and w.class ~= "BoltRifle" and w.class ~= "SemiRifle" then
				continue -- not a gun (the staff)
			end
			local a, act = w.ammo, w.action
			local clips = { Enbloc = true, Stripper = true, Loose = true, Box = true, Gate = true, BreakOpen = true }
			assert(a and a.capacity >= 1 and clips[a.clip], `{name}: ammo`)
			if act and act.auto then
				-- a semi-automatic (W2): the bolt slides straight back by itself, one shot per fireTime
				-- (a semi-automatic pistol, the C96: the pistols' shared rate, Config/Firing.PistolFireTime)
				local pistol = w.class == "Pistol"
				assert(
					(w.class == "SemiRifle" or pistol) and act.turn == 0 and act.travel > 0,
					`{name}: self-cycling bolt`
				)
				local least = if pistol then Cfg.PistolFireTime else 0.35
				local fire = act.fireTime or (if pistol then Cfg.PistolFireTime else nil)
				assert(fire and fire >= least, `{name}: at most one shot every {least} s`)
				assert(act.reloadTime > act.boltTime, `{name}: action times`)
				assert((a.clipSize or a.capacity) <= a.capacity, `{name}: clip size`)
			elseif a.clip == "Gate" then
				-- a revolver: double action, rounds one at a time (`single`) through the gate, its cylinder turning
				local rv = w.revolver
				assert(w.class == "Pistol" and w.single and rv, `{name}: a revolver needs single and revolver`)
				assert(
					#rv.rounds == a.capacity and rv.gateChamber >= 0 and rv.gateChamber < a.capacity,
					`{name}: chambers`
				)
				for _, part in rv.turns do
					assert(w.moving[part], `{name}: {part} turns with the cylinder, so must move`)
				end
				for _, part in { "Hammer", "Trigger", "Gate", "Rod" } do
					assert(w.moving[part], `{name}: the {part} must move`)
				end
				-- a round in two parts: each bullet beside its round, coloured, turning with the cylinder
				for k, part in rv.bullets or {} do
					assert(#rv.bullets == #rv.rounds and w.parts[part], `{name}: bullet {k}`)
					assert(table.find(rv.turns, part) and table.find(rv.turns, rv.rounds[k]), `{name}: {part} turns`)
				end
				continue
			elseif a.clip == "BreakOpen" then
				-- a top-break revolver: double action, broken open on the hinge and all six replaced at once
				local rv = w.revolver
				local b = rv and rv.breakOpen
				assert(
					w.class == "Pistol" and rv and b and act.reloadTime > 0,
					`{name}: a top break needs revolver.breakOpen`
				)
				assert(#rv.rounds == a.capacity, `{name}: chambers`)
				for _, part in { "Hammer", "Trigger", "Latch", table.unpack(rv.turns), table.unpack(b.swings) } do
					assert(w.moving[part], `{name}: the {part} must move`)
				end
				-- a round in two parts: each bullet beside its round, coloured, turning with the cylinder and swinging down
				for k, part in rv.bullets or {} do
					assert(#rv.bullets == #rv.rounds and w.parts[part], `{name}: bullet {k}`)
					assert(table.find(rv.turns, part) and table.find(rv.turns, rv.rounds[k]), `{name}: {part} turns`)
					assert(table.find(b.swings, part), `{name}: {part} swings with its round`)
				end
				local c = b.cycle
				assert(
					c.up < c.back and c.back < c.kick and c.kick < c.home and c.home <= c.grab,
					`{name}: opening order`
				)
				assert(
					c.grab < c.clip and c.clip <= c.knob and c.knob < c.forward and c.forward < c.down,
					`{name}: closing`
				)
				assert(c.down <= 1, `{name}: the timeline fits the reload`)
				continue
			elseif a.clip == "Loose" then
				-- a pump gun: shells one at a time (`single`), the pump slides straight back (no turn) with its shell feed
				assert(act and act.boltTime > 0 and act.turn == 0, `{name}: pump action`)
				assert(act.travel > 0 and act.travel < 0.5, `{name}: pump stroke`)
				assert(w.single and w.moving.Pump and w.feed, `{name}: loose shells need single, a Pump and a feed`)
				for _, part in w.feed.parts do
					assert(w.moving[part], `{name}: feed part {part} must move`)
				end
			else
				assert(act and act.boltTime > 0 and act.reloadTime > act.boltTime, `{name}: action times`)
				assert(act.turn > 0 and act.turn <= 120 and act.travel > 0 and act.travel < 0.5, `{name}: bolt throw`)
			end
			assert(w.moving.Bolt, `{name}: the bolt must move`)
			for _, part in w.eject or {} do
				assert(w.parts[part], `{name}: eject part {part} has no color`)
			end
			if w.pellets then
				local p = w.pellets
				assert(p.count >= 2 and p.spread > 0 and p.spread < 10 and p.full < p.none, `{name}: pellets`)
			end
			if w.class == "BoltRifle" then
				-- 5 + 1; an en-bloc rifle one more, since it reloads only when empty (user 2026-10-12)
				local want = Cfg.RifleClip + (if a.clip == "Enbloc" then 1 else 0)
				assert(a.capacity == want, `{name}: {a.clip} clips hold {want} rounds`)
			end
		end
	end,
	["loose shells: R loads one at a time, the chamber left alone"] = function()
		local s = F.new(PUMP)
		assert(not F.reload(s, PUMP, 0), "full: nothing to load")
		F.fire(s, PUMP, 0)
		F.bolt(s, PUMP, 0.5) -- 4 + 1
		F.fire(s, PUMP, 2)
		local ok, _, out, kind = F.reload(s, PUMP, 3)
		assert(ok and kind == "Load" and out == nil, "a fired hull stays in the chamber while loading")
		assert(s.spent and not s.chambered, "still the hull")
		F.settle(s, 3 + 0.25 + 0.45 + 0.25)
		assert(s.magazine == 5 and s.spent, "one shell in; the hull waits for the pump")
		assert(F.next(s, 4) == "Bolt", "then the next click pumps")
	end,
	["loose shells into an empty gun: the open action closes on a shell"] = function()
		local s = F.new(PUMP)
		for i = 0, 5 do
			local t = i * 2
			F.fire(s, PUMP, t)
			F.bolt(s, PUMP, t + 0.5)
		end
		assert(s.open and s.magazine == 0 and not s.chambered, "empty: the action held open")
		local ok, _, out = F.reload(s, PUMP, 14)
		assert(ok and out == "Open", "the load reports the open action")
		F.settle(s, 14 + 0.25 + 5 * 0.45 + 0.25)
		assert(s.chambered and s.magazine == 4 and not s.open, "5 shells in, one chambered: 4 + 1")
	end,
	["a shotgun pattern: the same from the same seed, inside the cone"] = function()
		local random = { count = 9, spread = 3 }
		local a, b = F.pellets(12345, random), F.pellets(12345, random)
		assert(#a == 9, "nine pellets")
		local differs = false
		for i, o in a do
			assert(o[1] == b[i][1] and o[2] == b[i][2], "the same seed, the same pattern")
			assert(math.sqrt(o[1] ^ 2 + o[2] ^ 2) <= 3 + 1e-9, "inside the cone")
		end
		for i, o in F.pellets(54321, random) do
			differs = differs or o[1] ~= a[i][1]
		end
		assert(differs, "another seed, another pattern")
	end,
	["a fixed shotgun pattern: one pellet on the line, the core ring tight, the rest on the outer ring"] = function()
		local p = W.shotgun_m1897.pellets :: any
		assert(p.core, "the M1897 fires a fixed pattern")
		local jitter = p.jitter or 0
		for seed = 1, 500 do
			local o = F.pellets(seed * 7919, p)
			assert(#o == p.count, "every pellet")
			assert(o[1][1] == 0 and o[1][2] == 0, "the first on the barrel's line")
			for i = 2, p.count do
				local r = math.sqrt(o[i][1] ^ 2 + o[i][2] ^ 2)
				local ring = if i <= 1 + p.core.count then p.core.spread else p.spread
				assert(math.abs(r - ring) <= ring * jitter + 1e-9, `pellet {i} on its ring`)
			end
		end
		local a, b = F.pellets(1, p), F.pellets(2, p)
		assert(a[2][1] ~= b[2][1], "turned per shot")
	end,
	["a bullet shatters window glass and goes on, a few panes at most; nothing else"] = function()
		local D = require("../src/shared/Config/Destruction")
		local S = Cfg.Shatter
		assert(S.panes >= 1, "at least one pane")
		assert(F.shatters("Glass", 0, S), "glass breaks")
		assert(F.shatters("Glass", S.panes - 1, S), "up to the last pane")
		assert(not F.shatters("Glass", S.panes, S), "stops after the last pane")
		assert(not F.shatters(nil, 0, S), "not a building")
		for class in D.Materials do
			if class ~= "Glass" then
				assert(not F.shatters(class, 0, S), `{class} stops the bullet`)
			end
		end
		for class in S.classes do
			assert(D.Materials[class], `unknown class {class}`)
		end
	end,
	["the admin's unlimited ammo keeps the magazine full, shot after shot"] = function()
		local s = F.new(CARCANO)
		for i = 1, CARCANO.capacity + 3 do
			local now = i * 10
			assert(F.fire(s, CARCANO, now), `shot {i}`)
			F.topUp(s, CARCANO)
			assert(s.magazine == CARCANO.capacity)
			assert(F.bolt(s, CARCANO, now + 2), `bolt {i}`)
		end
		local m = F.new(MONDRAGON)
		for i = 1, MONDRAGON.capacity + 3 do
			assert(F.fire(m, MONDRAGON, i * 10), `semi shot {i}`)
			F.topUp(m, MONDRAGON)
		end
		assert(m.chambered and not m.open, "a semi never runs dry")
	end,
	["a revolver fires every click, 7 rounds, then clicks empty"] = function()
		local s = F.new(NAGANT)
		assert(F.rounds(s) == 7 and s.chambered, "full: all 7 chambers")
		local now = 0
		for i = 1, 7 do
			assert(F.next(s, now) == "Fire", `pull {i} fires`)
			local ok, _, out = F.fire(s, NAGANT, now)
			assert(ok and out == nil, "nothing flies out: the case stays in its chamber")
			assert(not s.spent, "the cylinder turns the next chamber on: no case to clear")
			assert(F.next(s, now + 0.1) == "Busy", "at most one shot per fireTime")
			now += NAGANT.fireTime
		end
		assert(F.rounds(s) == 0 and F.next(s, now) == "Dry", "empty: it just clicks")
		assert(not s.open, "nothing held open")
	end,
	["a revolver loads one at a time through the gate, topping up from any count"] = function()
		local s = F.new(NAGANT)
		assert(not F.reload(s, NAGANT, 0), "full: nothing to load")
		F.fire(s, NAGANT, 0)
		F.fire(s, NAGANT, 1)
		F.fire(s, NAGANT, 2) -- 4 left
		local ok, _, out, kind = F.reload(s, NAGANT, 3)
		assert(ok and kind == "Load" and out == nil, "single rounds, nothing out of the chamber")
		assert(s.load and s.load.room == 3, "room for the 3 fired")
		assert(F.next(s, 3.1) == "Load", "a click stops it")
		F.settle(s, 3 + 0.5 + 3 * 0.85 + 0.45)
		assert(F.rounds(s) == 7 and s.chambered, "full again")
		-- stopped after the round in the hand
		local e = F.new(NAGANT)
		for i = 0, 6 do
			F.fire(e, NAGANT, i)
		end
		assert(F.reload(e, NAGANT, 10))
		assert(e.load and e.load.room == 7, "empty: room for 7")
		assert(F.stopLoad(e, 10 + 0.5 + 0.85 + 0.1) == 2, "the second round, in the hand, still goes in")
		F.settle(e, 20)
		assert(F.rounds(e) == 2 and e.chambered, "two in, one on the bore")
		assert(F.next(e, 20) == "Fire", "and it fires")
		F.topUp(e, NAGANT)
		assert(F.rounds(e) == 7, "the admin's unlimited ammo fills every chamber")
	end,
	["a top break fires 6 a click apart, then R puts six in at once"] = function()
		local s = F.new(WEBLEY)
		assert(F.rounds(s) == 6 and s.chambered, "full: all 6 chambers")
		assert(not F.reload(s, WEBLEY, 0), "full: nothing to reload")
		local now = 0
		for i = 1, 6 do
			local ok, _, out = F.fire(s, WEBLEY, now)
			assert(ok and out == nil and not s.spent, `pull {i} fires, the cylinder turning on`)
			now += WEBLEY.fireTime
		end
		assert(F.rounds(s) == 0 and F.next(s, now) == "Dry", "empty: it just clicks")
		local ok, _, out, kind = F.reload(s, WEBLEY, now)
		assert(ok and kind == "Reload" and out == nil and not s.load, "one reload, not single rounds")
		assert(F.rounds(s) == 6 and s.chambered, "six in at once")
		assert(F.next(s, now + WEBLEY.reloadTime - 0.1) == "Busy", "busy for the whole reload")
		assert(F.next(s, now + WEBLEY.reloadTime) == "Fire", "then it fires")
		-- from a part-fired cylinder too (the live rounds come out with the cases)
		local p = F.new(WEBLEY)
		F.fire(p, WEBLEY, 0)
		assert(F.reload(p, WEBLEY, 1) and F.rounds(p) == 6, "topped up")
		F.fire(p, WEBLEY, 5)
		F.topUp(p, WEBLEY)
		assert(F.rounds(p) == 6, "the admin's unlimited ammo fills every chamber")
	end,
}
