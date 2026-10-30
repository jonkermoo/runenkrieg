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
		assert(R.stuck(0.5, 2, 1.5, 1.5))
		assert(not R.stuck(0.5, 1, 1.5, 1.5), "window not up")
		assert(not R.stuck(3, 2, 1.5, 1.5))
	end,
	["every class a bot plays is a real class, the first free"] = function()
		local Classes = require("../src/shared/Config/Classes")
		for _, c in Cfg.Classes do
			assert(Classes.Defs[c.key], c.key)
		end
		assert(Classes.Defs[Cfg.Classes[1].key].cost == 0)
		assert(#Cfg.Names >= Cfg.Max, "a name for every bot")
	end,
	["the admin panel's bot rows name real difficulties and counts within the budget"] = function()
		local Dev = require("../src/shared/Config/DevTools")
		for _, k in Dev.Admin.BotDifficulties do
			assert(Cfg.Difficulty[k], k)
		end
		for _, n in Dev.Admin.BotCounts do
			assert(n >= 0 and n <= Cfg.Max, `{n}`)
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
}
