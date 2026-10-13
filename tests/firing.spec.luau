--!strict
local Cfg = require("../src/shared/Config/Firing")
local F = require("../src/shared/Rules/Firing")
local W = require("../src/shared/Config/Weapons")

local OPEN = { openAt = Cfg.BoltCycle.back, reloadOpenAt = Cfg.ReloadCycle.back }
local CARCANO: F.Gun = {
	capacity = 6,
	clip = "Enbloc",
	boltTime = 0.9,
	reloadTime = 2.5,
	fireTime = 0.15,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
}
local GEWEHR: F.Gun = {
	capacity = 5,
	clip = "Stripper",
	boltTime = 0.9,
	reloadTime = 2.8,
	fireTime = 0.15,
	openAt = OPEN.openAt,
	reloadOpenAt = OPEN.reloadOpenAt,
}

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
	["en-bloc clips go in only when the magazine is empty; stripper clips top it up"] = function()
		local c = F.new(CARCANO)
		assert(not F.reload(c, CARCANO, 0), "Carcano: not with rounds left")
		c.magazine, c.chambered, c.spent = 0, false, true
		local ok, _, out = F.reload(c, CARCANO, 0)
		assert(ok and out == "Casing" and c.chambered and c.magazine == 5, "Carcano: clip in, case out, round in")
		local g = F.new(GEWEHR)
		assert(not F.reload(g, GEWEHR, 0), "Gewehr: not when full")
		g.magazine = 2
		assert(F.reload(g, GEWEHR, 0) and g.magazine == 5, "Gewehr: tops up a part-empty magazine")
		local g2 = F.new(GEWEHR)
		g2.magazine = GEWEHR.capacity
		assert(not F.reload(g2, GEWEHR, 0), "Gewehr: not when full")
		local g3 = F.new(GEWEHR)
		g3.magazine = 1
		assert(F.reload(g3, GEWEHR, 0) and g3.magazine == 5 and g3.chambered, "Gewehr: 5 + the chambered round")
	end,
	["the Carcano reloads only with 1 or 0 rounds left; the Gewehr whenever it isn't full"] = function()
		local c = F.new(CARCANO)
		c.magazine = 1
		assert(not F.reload(c, CARCANO, 0), "Carcano: 2 rounds left (1 + 1)")
		c.magazine = 0
		assert(F.reload(c, CARCANO, 0) and F.rounds(c) == 7, "Carcano: 1 left (chambered) -> 6 + 1")
		local e = F.new(CARCANO)
		e.magazine, e.chambered = 0, false
		assert(F.reload(e, CARCANO, 0) and F.rounds(e) == 6, "Carcano: 0 left -> 5 + 1 (the clip feeds the chamber)")
		local g = F.new(GEWEHR)
		g.magazine = 4
		assert(F.reload(g, GEWEHR, 0) and F.rounds(g) == 6, "Gewehr: one shot down, topped up")
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
