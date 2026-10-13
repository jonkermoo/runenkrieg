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
	["shots must come from the shooter's own rifle, as a unit direction"] = function()
		assert(F.validShot(5, 1, Cfg.MaxOrigin))
		assert(not F.validShot(30, 1, Cfg.MaxOrigin), "far from the shooter")
		assert(not F.validShot(5, 3, Cfg.MaxOrigin), "not a unit vector")
		assert(not F.validShot(0 / 0, 1, Cfg.MaxOrigin), "NaN")
	end,
	["every weapon has its ammunition and action"] = function()
		for name, w in W do
			local a, act = w.ammo, w.action
			assert(a and a.capacity >= 1 and (a.clip == "Enbloc" or a.clip == "Stripper"), `{name}: ammo`)
			assert(act and act.boltTime > 0 and act.reloadTime > act.boltTime, `{name}: action times`)
			assert(act.turn > 0 and act.turn <= 120 and act.travel > 0 and act.travel < 0.5, `{name}: bolt throw`)
			assert(w.moving.Bolt, `{name}: the bolt must move`)
			if w.class == "BoltRifle" then
				-- 5 + 1; an en-bloc rifle one more, since it reloads only when empty (user 2026-10-12)
				local want = Cfg.RifleClip + (if a.clip == "Enbloc" then 1 else 0)
				assert(a.capacity == want, `{name}: {a.clip} clips hold {want} rounds`)
			end
		end
	end,
}
