--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/Bots")

local brainCfg = Cfg.Brain :: any
local D = Cfg.Difficulty.Medium

local function senses(over: { [string]: any }?): R.Senses
	local s: any = {
		now = 0,
		health = 1,
		magazine = 5,
		chambered = true,
		spent = false,
		busy = false,
		loading = false,
		capacity = 6,
		auto = false,
		target = nil,
		hurtAt = nil,
	}
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

local function enemy(distance: number?, visible: boolean?)
	return { id = "e", distance = distance or 100, visible = if visible == nil then true else visible }
end

return {
	["wanted: tops the players up to the fill, never under 0 or over the budget"] = function()
		assert(R.wanted({ total = 8 }, 0, 20) == 8)
		assert(R.wanted({ total = 8 }, 3, 20) == 5)
		assert(R.wanted({ total = 8 }, 8, 20) == 0)
		assert(R.wanted({ total = 8 }, 12, 20) == 0, "more players than the fill: none")
		assert(R.wanted({ total = 40 }, 0, 20) == 20, "the budget caps it")
		assert(R.wanted(nil, 0, 20) == 0, "a mode without a fill: none")
	end,
	["wanted: a test's pin wins, clamped to the budget"] = function()
		assert(R.wanted({ total = 8 }, 5, 20, 10) == 10)
		assert(R.wanted(nil, 0, 20, 4) == 4)
		assert(R.wanted({ total = 8 }, 0, 20, 50) == 20)
		assert(R.wanted({ total = 8 }, 0, 20, -3) == 0)
		assert(R.wanted({ total = 8 }, 0, 20, 2.7) == 2)
	end,
	["advance with nothing in sight"] = function()
		local b = R.new()
		local i = R.step(b, senses(), brainCfg, D, 0.5)
		assert(b.state == "Advance" and i.move == "Objective" and not i.fire and not i.aim)
	end,
	["engage: aims at once, fires only after the reaction time"] = function()
		local b = R.new()
		local i = R.step(b, senses({ now = 10, target = enemy() }), brainCfg, D, 0.5)
		assert(b.state == "Engage" and i.aim and i.move == "Strafe" and not i.fire, "no shot before reacting")
		i = R.step(b, senses({ now = 10 + D.reaction * 0.9, target = enemy() }), brainCfg, D, 0.5)
		assert(not i.fire)
		i = R.step(b, senses({ now = 10 + D.reaction + 1e-6, target = enemy() }), brainCfg, D, 0.5)
		assert(i.fire, "fires once reacted")
	end,
	["a new target restarts the reaction"] = function()
		local b = R.new()
		R.step(b, senses({ now = 0, target = enemy() }), brainCfg, D, 0.5)
		local other = { id = "f", distance = 50, visible = true }
		local i = R.step(b, senses({ now = 5, target = other }), brainCfg, D, 0.5)
		assert(not i.fire and b.targetId == "f")
	end,
	["in the open it never stands still; a short gun closes in"] = function()
		local b = R.new()
		local i = R.step(b, senses({ target = enemy(200) }), brainCfg, D, 0.5)
		assert(i.move == "Strafe")
		b = R.new()
		i = R.step(b, senses({ target = enemy(40), push = 18 }), brainCfg, D, 0.5)
		assert(i.move == "Push" and i.aim)
		i = R.step(b, senses({ target = enemy(10), push = 18 }), brainCfg, D, 0.5)
		assert(i.move == "Strafe", "close enough: fights where it is")
	end,
	["shot at with cover found: runs to cover, no shots on the way"] = function()
		local b = R.new()
		local i = R.step(b, senses({ now = 5, threatAt = 4.8, cover = "going", target = enemy() }), brainCfg, D, 0)
		assert(b.state == "Cover" and i.move == "Cover" and not i.fire and not i.aim)
	end,
	["shot at with no cover: fights on in the open, moving"] = function()
		local b = R.new()
		local i = R.step(b, senses({ now = 5, threatAt = 4.8, cover = "none", target = enemy() }), brainCfg, D, 0)
		assert(b.state == "Engage" and i.move == "Strafe")
	end,
	["spotted (an enemy looking at it) also sends it to cover"] = function()
		local b = R.new()
		R.step(b, senses({ now = 1, spotted = true, cover = "going", target = enemy() }), brainCfg, D, 0)
		assert(b.state == "Cover")
	end,
	["in cover it waits, then peeks once quiet, and ducks back when hit"] = function()
		local b = R.new()
		local s = senses({ now = 0, threatAt = 0, cover = "going", target = enemy() })
		R.step(b, s, brainCfg, D, 0)
		assert(b.state == "Cover")
		s.now, s.cover, s.target = brainCfg.CoverFor[1] * 0.5, "at", enemy(100, false)
		R.step(b, s, brainCfg, D, 0)
		assert(b.state == "Cover", "not before its time")
		s.now = brainCfg.CoverFor[1] + 0.01
		s.threatAt = s.now - brainCfg.PeekQuiet * 0.5
		R.step(b, s, brainCfg, D, 0)
		assert(b.state == "Cover", "not while shots still fly past")
		s.threatAt = s.now - brainCfg.PeekQuiet - 0.01
		local i = R.step(b, s, brainCfg, D, 0)
		assert(b.state == "Peek" and i.move == "Peek" and i.aim)
		s.now += 0.2
		s.hurtAt = s.now
		i = R.step(b, s, brainCfg, D, 0)
		assert(b.state == "Cover" and i.move == "Cover", "hit on the peek")
	end,
	["a peek ends when its time is up"] = function()
		local b = R.new()
		b.state, b.peekFrom, b.peekUntil, b.targetId, b.lastSeen = "Peek", 0, 2, "e", 0
		R.step(b, senses({ now = 1, cover = "at", target = enemy() }), brainCfg, D, 0)
		assert(b.state == "Peek")
		R.step(b, senses({ now = 2, cover = "at", target = enemy() }), brainCfg, D, 0)
		assert(b.state == "Cover")
	end,
	["no new dash to cover before CoverEvery"] = function()
		local b = R.new()
		b.coverReady = 10
		R.step(b, senses({ now = 5, threatAt = 5, cover = "going", target = enemy() }), brainCfg, D, 0)
		assert(b.state == "Engage")
	end,
	["back in sight after a while: the reaction again"] = function()
		local b = R.new()
		R.step(b, senses({ now = 0, target = enemy() }), brainCfg, D, 0)
		R.step(b, senses({ now = 0.5, target = enemy(100, false) }), brainCfg, D, 0)
		local back = 0.5 + brainCfg.Reacquire + 0.1
		local i = R.step(b, senses({ now = back, target = enemy() }), brainCfg, D, 0)
		assert(not i.fire and b.seenAt == back)
	end,
	["class: the dearest it can pay for when buying, the default when broke"] = function()
		local opts = { { key = "R", cost = 0 }, { key = "A", cost = 100 }, { key = "S", cost = 150 } }
		local w = { { key = "A", weight = 1 }, { key = "B", weight = 0 }, { key = "C", weight = 3 } }
		assert(R.rollClass(w, 0) == "A" and R.rollClass(w, 0.24) == "A", "the first quarter")
		assert(R.rollClass(w, 0.26) == "C" and R.rollClass(w, 1) == "C", "the rest, never a weight of 0")
		assert(R.rollClass({}, 0.5) == nil and R.rollClass({ { key = "A", weight = 0 } }, 0.5) == nil, "none")
		local k, c = R.chooseClass(0, opts, 0.6, 0, 0)
		assert(k == "R" and c == 0)
		k, c = R.chooseClass(120, opts, 0.6, 0, 0)
		assert(k == "A" and c == 100)
		k = R.chooseClass(500, opts, 0.6, 0.1, 0)
		assert(k == "S")
		k = R.chooseClass(500, opts, 0.6, 0.9, 0)
		assert(k == "R", "saving up: a random affordable one (here the first)")
		k = R.chooseClass(500, opts, 0.6, 0.9, 0.99)
		assert(k == "S")
	end,
	["cover: the nearest hidden point, not toward the threat, within reach"] = function()
		local pts = {
			{ distance = 3, hidden = false, threat = 50 },
			{ distance = 8, hidden = true, threat = 40 },
			{ distance = 6, hidden = true, threat = 20 },
			{ distance = 30, hidden = true, threat = 60 },
		}
		assert(R.pickCover(pts, 30, 24) == 2)
		assert(R.pickCover(pts, 10, 24) == 3)
		assert(R.pickCover(pts, 70, 24) == nil)
		assert(R.pickCover({}, 0, 24) == nil)
	end,
	["looking at: an enemy facing back at the bot, within the cone"] = function()
		-- the enemy 10 studs ahead (+z), facing back (-z)
		assert(R.lookingAt(0, 10, 0, -1, 15))
		assert(not R.lookingAt(0, 10, 0, 1, 15), "facing away")
		local a = math.rad(20)
		assert(not R.lookingAt(0, 10, math.sin(a), -math.cos(a), 15), "looking past it")
	end,
	["near miss: within the radius of the line, ahead of the muzzle, not past the hit"] = function()
		assert(R.nearMiss(0, 0, 0, 1, 0, 0, 100, 50, 3, 0, 5))
		assert(not R.nearMiss(0, 0, 0, 1, 0, 0, 100, 50, 6, 0, 5), "too far off the line")
		assert(not R.nearMiss(0, 0, 0, 1, 0, 0, 100, -3, 1, 0, 5), "behind the shooter")
		assert(not R.nearMiss(0, 0, 0, 1, 0, 0, 20, 50, 1, 0, 5), "the shot stopped short of it")
	end,
	["out of sight it hunts the last place for Forget seconds, then advances"] = function()
		local b = R.new()
		R.step(b, senses({ now = 0, target = enemy() }), brainCfg, D, 0.5)
		local i = R.step(b, senses({ now = 1, target = enemy(100, false) }), brainCfg, D, 0.5)
		assert(b.state == "Engage" and i.move == "Hunt" and not i.fire)
		i = R.step(b, senses({ now = 1 + brainCfg.Forget }), brainCfg, D, 0.5)
		assert(b.state == "Advance" and i.move == "Objective")
	end,
	["a bolt rifle works its bolt after the delay, never while busy"] = function()
		local b = R.new()
		R.step(b, senses({ now = 0, target = enemy() }), brainCfg, D, 0)
		local i = R.step(b, senses({ now = 1, target = enemy() }), brainCfg, D, 0)
		assert(i.fire)
		local after = { now = 1.1, chambered = false, spent = true, magazine = 4, target = enemy() }
		i = R.step(b, senses(after), brainCfg, D, 0)
		assert(not i.bolt, "not before BoltDelay")
		after.now = 1 + Cfg.Brain.BoltDelay[1]
		after.busy = true
		i = R.step(b, senses(after), brainCfg, D, 0)
		assert(not i.bolt, "not while the shot's action is under way")
		after.busy = false
		i = R.step(b, senses(after), brainCfg, D, 0)
		assert(i.bolt and not i.fire)
	end,
	["a semi rifle never works a bolt and waits its fire gap"] = function()
		local b = R.new()
		R.step(b, senses({ now = 0, auto = true, target = enemy() }), brainCfg, D, 1)
		local i = R.step(b, senses({ now = 1, auto = true, target = enemy() }), brainCfg, D, 1)
		assert(i.fire and not i.bolt)
		i = R.step(b, senses({ now = 1 + D.fireGap[2] * 0.9, auto = true, target = enemy() }), brainCfg, D, 1)
		assert(not i.fire, "within the gap")
		i = R.step(b, senses({ now = 1 + D.fireGap[2], auto = true, target = enemy() }), brainCfg, D, 1)
		assert(i.fire)
	end,
	["empty: reloads even in a fight, once, until it has played out"] = function()
		local b = R.new()
		local s = senses({ now = 0, magazine = 0, chambered = false, spent = true, target = enemy() })
		local i = R.step(b, s, brainCfg, D, 0.5)
		assert(i.reload and not i.fire and i.move == "Strafe", "reloads on the move in the open")
		s.now, s.busy = 0.5, true
		i = R.step(b, s, brainCfg, D, 0.5)
		assert(not i.reload and b.reloading, "asked once")
		s.now, s.busy, s.magazine, s.chambered, s.spent = 3, false, 5, true, false
		i = R.step(b, s, brainCfg, D, 0.5)
		assert(b.state == "Engage" and not i.reload)
	end,
	["low with nothing in sight: tops up; low in a fight: keeps shooting"] = function()
		local b = R.new()
		local i = R.step(b, senses({ magazine = 1 }), brainCfg, D, 0.5)
		assert(i.reload and i.move == "Objective", "tops up on the way")
		b = R.new()
		R.step(b, senses({ now = 0, magazine = 1, target = enemy() }), brainCfg, D, 0.5)
		i = R.step(b, senses({ now = 1, magazine = 1, target = enemy() }), brainCfg, D, 0.5)
		assert(not i.reload and i.fire)
	end,
	["single rounds going in stop when an enemy shows up"] = function()
		local b = R.new()
		local i = R.step(b, senses({ magazine = 2, loading = true, busy = true, target = enemy() }), brainCfg, D, 0.5)
		assert(i.stopLoad)
	end,
	["hurt under fire it retreats, shooting back, until the time is up or it has healed"] = function()
		local b = R.new()
		local s = senses({ now = 5, health = brainCfg.RetreatBelow - 0.01, hurtAt = 4.9, target = enemy() })
		local i = R.step(b, s, brainCfg, D, 0.5)
		assert(b.state == "Retreat" and i.move == "Away" and i.aim)
		s.now = 5 + D.reaction + 0.1 -- (seen all along: within Reacquire)
		i = R.step(b, s, brainCfg, D, 0.5)
		assert(b.state == "Retreat" and i.fire, "shoots back once reacted")
		s.now = 5 + brainCfg.RetreatFor
		R.step(b, s, brainCfg, D, 0.5)
		assert(b.state ~= "Retreat", "time is up")
		b = R.new()
		s = senses({ now = 0, health = 0.2, hurtAt = 0 })
		R.step(b, s, brainCfg, D, 0.5)
		s.now, s.health = 1, brainCfg.RetreatUntil
		R.step(b, s, brainCfg, D, 0.5)
		assert(b.state == "Advance", "healed enough")
	end,
	["low health without fresh damage doesn't retreat"] = function()
		local b = R.new()
		R.step(b, senses({ now = 10, health = 0.2, hurtAt = 5 }), brainCfg, D, 0.5)
		assert(b.state == "Advance")
	end,
	["sight: range, the view cone, and all round when alert"] = function()
		local fov = 120
		assert(R.inSight(0, 10, 10, 0, 1, 100, fov, false), "dead ahead")
		assert(not R.inSight(0, 200, 200, 0, 1, 100, fov, false), "out of range")
		assert(not R.inSight(0, -10, 10, 0, 1, 100, fov, false), "behind")
		assert(R.inSight(0, -10, 10, 0, 1, 100, fov, true), "behind, but alert")
		local a = math.rad(fov / 2 - 1)
		assert(R.inSight(math.sin(a), math.cos(a), 1, 0, 1, 100, fov, false), "just inside the cone")
		a = math.rad(fov / 2 + 1)
		assert(not R.inSight(math.sin(a), math.cos(a), 1, 0, 1, 100, fov, false), "just outside")
	end,
	["pick: keeps the current target in sight, else the nearest in sight"] = function()
		local list = {
			{ id = "a", distance = 50, visible = true },
			{ id = "b", distance = 20, visible = true },
			{ id = "c", distance = 5, visible = false },
		}
		assert((R.pick(list, "a") :: any).id == "a")
		assert((R.pick(list, nil) :: any).id == "b")
		assert((R.pick(list, "c") :: any).id == "b", "the current one out of sight")
		assert(R.pick({ { id = "c", distance = 5, visible = false } }, nil) == nil)
	end,
	["aim error: settles from the new-target error to the floor, more on a crossing target"] = function()
		assert(math.abs(R.aimError(D, 0, 0) - D.aimError) < 1e-9)
		assert(R.aimError(D, D.settle, 0) < R.aimError(D, 0, 0))
		assert(math.abs(R.aimError(D, 1e6, 0) - D.aimFloor) < 1e-6)
		assert(math.abs(R.aimError(D, 1e6, 10) - (D.aimFloor + D.moving)) < 1e-6)
		assert(R.aimError(D, -5, 0) == R.aimError(D, 0, 0), "no time before the start")
	end,
	["scatter stays within the cone"] = function()
		math.randomseed(7)
		for _ = 1, 500 do
			local x, y = R.scatter(3, math.random(), math.random())
			assert(x * x + y * y <= 9 + 1e-9)
		end
		local x, y = R.scatter(3, 0, 0.3)
		assert(x == 0 and y == 0)
	end,
	["lead: 1 dead on, 0 where it was the lag ago"] = function()
		assert(R.lead(10, 5, 0.4, 1) == 10)
		assert(R.lead(10, 5, 0.4, 0) == 8)
		assert(math.abs(R.lead(10, 5, 0.4, 0.5) - 9) < 1e-9)
	end,
	["stuck: too little progress over the window"] = function()
		assert(R.stuck(0.5, 2, 1.5, 1.5, 4))
		assert(not R.stuck(0.5, 1, 1.5, 1.5, 4), "window not up")
		assert(not R.stuck(3, 2, 1.5, 1.5, 4))
	end,
	["stuck: a stale sample (held in the wave line, down) says nothing"] = function()
		assert(not R.stuck(0, 30, 1.5, 1.5, 4))
		assert(R.stuck(0, 3.9, 1.5, 1.5, 4))
	end,
	["inside: a point beyond the map's edge comes back inside by the margin"] = function()
		local b = { minX = -150, maxX = 2550, minZ = -280, maxZ = 280 }
		local x, z = R.inside(1750, 326, b, 10)
		assert(x == 1750 and z == 270)
		x, z = R.inside(-200, -300, b, 10)
		assert(x == -140 and z == -270)
		x, z = R.inside(100, 0, b, 10)
		assert(x == 100 and z == 0, "inside: unchanged")
	end,
	["every class a bot plays is a real class, the first free"] = function()
		local Classes = require("../src/shared/Config/Classes")
		for _, c in Cfg.Classes do
			assert(Classes.Defs[c.key], c.key)
		end
		assert(Classes.Defs[Cfg.Classes[1].key].cost == 0)
		for mode, max in Cfg.Max do
			assert(#Cfg.Names >= max, `a name for every bot ({mode})`)
		end
	end,
	["killing a bot pays a share of the battle points, never more than a player's"] = function()
		assert(Cfg.KillShare > 0 and Cfg.KillShare <= 1)
	end,
	["the admin panel's bot rows name real difficulties and counts within the budget"] = function()
		local Dev = require("../src/shared/Config/DevTools")
		for _, k in Dev.Admin.BotDifficulties do
			assert(Cfg.Difficulty[k], k)
		end
		for _, n in Dev.Admin.BotCounts do
			assert(n >= 0 and n <= math.max(Cfg.Max.FFA, Cfg.Max.Normal, Cfg.PinMax.Normal), `{n}`)
		end
	end,
	["every difficulty has every knob"] = function()
		for name, d in Cfg.Difficulty do
			for _, k in { "reaction", "aimError", "aimFloor", "settle", "moving", "spotRange", "fov", "lead" } do
				assert(type((d :: any)[k]) == "number", `{name}.{k}`)
			end
			assert(d.aimFloor <= d.aimError, name)
			assert(#d.fireGap == 2 and d.fireGap[1] <= d.fireGap[2], name)
		end
		assert(Cfg.Difficulty[Cfg.Default], "the default is one of them")
	end,
	["wantedSides: each side topped up to its fill with its own players first"] = function()
		local w, e = R.wantedSides(20, 1, 0, 39)
		assert(w == 19 and e == 20, "one player: 20 v 20")
		w, e = R.wantedSides(20, 12, 9, 39)
		assert(w == 8 and e == 11)
		w, e = R.wantedSides(20, 25, 25, 39)
		assert(w == 0 and e == 0, "past the fill: none")
	end,
	["wantedSides: over the budget the side with more soldiers gives up a bot at a time"] = function()
		local w, e = R.wantedSides(20, 0, 0, 30)
		assert(w == 15 and e == 15)
		w, e = R.wantedSides(20, 0, 0, 7)
		assert(w + e == 7 and math.abs(w - e) <= 1)
		w, e = R.wantedSides(20, 0, 10, 12)
		assert(w == 11 and e == 1, "the soldiers kept even: " .. w .. " " .. e)
		w, e = R.wantedSides(20, 0, 0, 0)
		assert(w == 0 and e == 0)
	end,
	["a test's pin may run past the mode's most, up to PinMax: 100 is 50 a side"] = function()
		local DevCfg = require("../src/shared/Config/DevTools")
		local top = Cfg.PinMax.Normal
		assert(R.ceiling(Cfg.Max.Normal, nil, top) == Cfg.Max.Normal, "no pin: the usual most")
		assert(R.ceiling(Cfg.Max.Normal, 10, top) == Cfg.Max.Normal, "a small pin keeps it")
		assert(R.ceiling(Cfg.Max.Normal, 100, top) == 100 and R.ceiling(Cfg.Max.Normal, 500, top) == top)
		assert(R.ceiling(Cfg.Max.FFA, 100, nil) == Cfg.Max.FFA, "no PinMax: never past the most")
		local w, e = R.wantedSides(Cfg.Fill.Normal.perSide, 1, 0, R.ceiling(Cfg.Max.Normal, 100, top), 100)
		assert(w == 50 and e == 50, `{w} v {e}`)
		assert(table.find(DevCfg.Admin.BotCounts, 100), "the admin panel's 100 row")
		local g = R.governor(Cfg.Max.Normal)
		R.govern(g, 0, 60, 1, 0, R.ceiling(Cfg.Max.Normal, 100, top), Cfg.Budget.governor)
		assert(g.cap == Cfg.Max.Normal, "the governor never raises past its cap at once")
	end,
	["wantedSides: a pinned total is split evenly, West taking the odd one"] = function()
		local w, e = R.wantedSides(20, 5, 5, 39, 9)
		assert(w == 5 and e == 4)
		w, e = R.wantedSides(20, 0, 0, 10, 30)
		assert(w == 5 and e == 5, "the pin still under the budget")
	end,
	["govern: trims one under the bots on after a spell over budget, then one per trimEvery"] = function()
		local cfg = Cfg.Budget.governor
		local g = R.governor(39)
		R.govern(g, cfg.ms + 1, 60, cfg.trimAfter - 0.1, 39, 39, cfg)
		assert(g.cap == 39, "not yet")
		R.govern(g, cfg.ms + 1, 60, 0.1, 39, 39, cfg)
		assert(g.cap == 38)
		R.govern(g, cfg.ms + 1, 60, cfg.trimEvery, 38, 39, cfg)
		assert(g.cap == 37)
		-- a slow physics rate counts too
		R.govern(g, 0, cfg.minFps - 5, cfg.trimEvery, 37, 39, cfg)
		assert(g.cap == 36)
	end,
	["govern: lets bots back after a spell within budget, never past the max nor under the floor"] = function()
		local cfg = Cfg.Budget.governor
		local g = R.governor(10)
		g.cap = 8
		R.govern(g, 0, 60, cfg.restoreAfter, 8, 10, cfg)
		assert(g.cap == 9)
		R.govern(g, 0, 60, cfg.restoreEvery, 9, 10, cfg)
		assert(g.cap == 10)
		R.govern(g, 0, 60, cfg.restoreEvery * 5, 10, 10, cfg)
		assert(g.cap == 10, "never past the max")
		local low = R.governor(39)
		for _ = 1, 100 do
			R.govern(low, cfg.ms + 1, 60, cfg.trimAfter, low.cap, 39, cfg)
		end
		assert(low.cap == cfg.floor)
		-- one bad frame breaks a spell within budget
		local h = R.governor(10)
		h.cap = 5
		R.govern(h, 0, 60, cfg.restoreAfter - 1, 5, 10, cfg)
		R.govern(h, cfg.ms + 1, 60, 0.1, 5, 10, cfg)
		R.govern(h, 0, 60, 2, 5, 10, cfg)
		assert(h.cap == 5)
	end,
	["config: Normal's budget numbers are sane"] = function()
		local b = Cfg.Budget
		assert(b.frameMs > 0 and b.raysPerFrame >= 8 and b.pathsPerSecond > 0)
		assert(b.governor.trimEvery <= b.governor.trimAfter and b.governor.restoreEvery <= b.governor.restoreAfter)
		assert(Cfg.Max.Normal >= 2 * Cfg.Fill.Normal.perSide - 1, "room for 20 v 20 with one player")
		assert(Cfg.Normal.defendShare > 0 and Cfg.Normal.defendShare < 1)
	end,
	["roles: pressing on, a far enemy is shot on the move and cover waits for a hit"] = function()
		local b = R.new()
		local s = senses({ target = enemy(100), role = "Assault", threatAt = 0 })
		local i = R.step(b, s, brainCfg, D, 0.5)
		assert(i.move == "Objective" and i.aim, "on toward the goal, aiming")
		s = senses({ now = 1, target = enemy(brainCfg.PressWithin - 5), role = "Assault" })
		i = R.step(b, s, brainCfg, D, 0.5)
		assert(i.move ~= "Objective", "a close enemy is fought where it stands")
		-- shot at but not hit, with cover: pressing on; hit: cover
		local c = R.new()
		i = R.step(
			c,
			senses({ now = 2, target = enemy(80), role = "Move", threatAt = 2, cover = "going" }),
			brainCfg,
			D,
			0.5
		)
		assert(c.state ~= "Cover", "a near miss doesn't stop the push")
		i = R.step(
			c,
			senses({ now = 3, target = enemy(80), role = "Move", threatAt = 3, hurtAt = 3, cover = "going" }),
			brainCfg,
			D,
			0.5
		)
		assert(c.state == "Cover" or c.state == "Retreat", c.state)
	end,
	["roles: support holds its spot and fires at a known enemy spot"] = function()
		local b = R.new()
		local i = R.step(b, senses({ now = 5, role = "Support", suppress = true }), brainCfg, D, 0.5)
		assert(i.move == "Hold" and i.aim and i.fire, "covering fire with nothing in sight")
		local next = R.step(b, senses({ now = 5.1, role = "Support", suppress = true }), brainCfg, D, 0.5)
		assert(not next.fire, "at its own slow rate")
		local h = R.new()
		i = R.step(h, senses({ now = 1, role = "Hold" }), brainCfg, D, 0.5)
		assert(i.move == "Hold" and not i.fire, "holding, nothing to shoot")
		local f = R.new()
		i = R.step(f, senses({ now = 1 }), brainCfg, D, 0.5)
		assert(i.move == "Objective", "no role (FFA): as before")
	end,
	["suppression: a pinned bot takes cover even pressing on, won't peek, and aims wider"] = function()
		local pin = brainCfg.SuppressedCover
		-- pressing on with a near miss: goes on; pinned by suppression: cover
		local b = R.new()
		R.step(
			b,
			senses({ now = 1, target = enemy(80), role = "Assault", threatAt = 1, cover = "going" }),
			brainCfg,
			D,
			0.5
		)
		assert(b.state ~= "Cover")
		R.step(
			b,
			senses({ now = 2, target = enemy(80), role = "Assault", threatAt = 2, cover = "going", suppressed = pin }),
			brainCfg,
			D,
			0.5
		)
		assert(b.state == "Cover", b.state)
		-- in cover with its time up: no peek while pinned, a peek once it calms down
		local c = R.new()
		c.state, c.coverUntil = "Cover", 0
		R.step(c, senses({ now = 10, target = enemy(80, false), cover = "at", suppressed = 1 }), brainCfg, D, 0.5)
		c.targetId, c.lastSeen = "e", 9.9
		R.step(c, senses({ now = 10, target = enemy(80, false), cover = "at", suppressed = 1 }), brainCfg, D, 0.5)
		assert(c.state == "Cover", "pinned: no peek")
		R.step(c, senses({ now = 10.5, target = enemy(80, false), cover = "at", suppressed = 0 }), brainCfg, D, 0.5)
		assert(c.state == "Peek", c.state)
		assert(R.shakenAim(1, 0, brainCfg.SuppressedAim) == 1)
		assert(R.shakenAim(1, 1, brainCfg.SuppressedAim) == 1 + brainCfg.SuppressedAim)
		assert(R.shakenAim(1, 3, brainCfg.SuppressedAim) == 1 + brainCfg.SuppressedAim, "capped at full")
	end,
	["heard: the shot's source guessed along its way, off by at most the angle and range"] = function()
		local A, Rg = brainCfg.HeardAngle, brainCfg.HeardRange
		local x, z = R.heard(0, 0, 100, 0, A, Rg, 0.5, 0.5)
		assert(math.abs(x - 100) < 1e-6 and math.abs(z) < 1e-6, "rolls in the middle: right on it")
		for _, r in { { 0, 0 }, { 1, 1 }, { 0, 1 }, { 1, 0 }, { 0.3, 0.8 } } do
			local gx, gz = R.heard(0, 0, 100, 0, A, Rg, r[1], r[2])
			local d = math.sqrt(gx * gx + gz * gz)
			local off = math.abs(math.deg(math.atan2(gz, gx)))
			assert(off <= A + 1e-6, `bearing off {off}`)
			assert(d >= 100 * (1 - Rg) - 1e-6 and d <= 100 * (1 + Rg) + 1e-6, `distance {d}`)
		end
		local ox, oz = R.heard(5, 5, 5, 5, A, Rg, 0, 1)
		assert(ox == 5 and oz == 5, "on top of it: no bearing to guess")
	end,
	["lod: full rate near a player or in a fight, slower out of sight"] = function()
		local L = Cfg.Budget.lod
		local t, s = R.lod(10, false, L)
		assert(t == L.near.think and s == L.near.sense)
		t = R.lod(L.mid + 1, false, L)
		assert(t == L.middle.think)
		t = R.lod(L.far + 1, false, L)
		assert(t == L.distant.think)
		t = R.lod(L.far + 1, true, L)
		assert(t == L.near.think, "a fight: full rate however far")
		assert(L.distant.think > 0 and L.distant.sense > 0 and L.middle.think <= L.near.think)
	end,
	["pickCover: a spot a teammate already holds is no cover (they spread out)"] = function()
		local pts = {
			{ distance = 6, hidden = true, threat = 50, crowded = true },
			{ distance = 12, hidden = true, threat = 50 },
		}
		assert(R.pickCover(pts, 40, 24) == 2)
		pts[2].crowded = true
		assert(R.pickCover(pts, 40, 24) == nil)
	end,
}
