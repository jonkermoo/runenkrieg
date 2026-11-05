--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotOrders")

local function counts(list: { { number } }): { { West: number, East: number } }
	local out = {}
	for i, c in list do
		out[i] = { West = c[1], East = c[2] }
	end
	return out
end

local OWNER = { "West", "West", "Neutral", "East", "East" }
local REST = { 1, 1, 0, -1, -1 }

return {
	["plan: all attack the target while no own sector is under attack"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 3, 0 }, { 2, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.attack == 3 and p.defend == nil and p.share == 0)
	end,
	["plan: with nothing under attack, a share holds the front (dug in there)"] = function()
		local quiet = counts({ { 3, 0 }, { 2, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } })
		local p = R.plan("West", OWNER, REST, quiet, 3, 0.5, 2, 0.3)
		assert(p.attack == 3 and p.defend == 2 and p.share == 0.3)
		p = R.plan("West", OWNER, REST, counts({ { 0, 0 }, { 1, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5, 2, 0.3)
		assert(p.defend == 2 and p.share == 0.5, "under attack: the defend share")
	end,
	["plan: an own sector the enemy leads in, or is draining, is defended"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 0, 0 }, { 1, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 2 and p.share == 0.5 and p.attack == 3)
		local control = { 1, 0.7, 0, -1, -1 }
		p = R.plan("West", OWNER, control, counts({ { 0, 0 }, { 3, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 2, "fewer enemies, but the control is slipping")
		p = R.plan("West", OWNER, REST, counts({ { 0, 0 }, { 3, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == nil, "held firmly by more defenders")
	end,
	["plan: the sector with most enemies, the frontmost on a tie; East counts from its own end"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 0, 3 }, { 0, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 1)
		p = R.plan("West", OWNER, REST, counts({ { 0, 2 }, { 0, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 2, "frontmost on a tie")
		p = R.plan("East", OWNER, REST, counts({ { 0, 0 }, { 0, 0 }, { 0, 0 }, { 2, 0 }, { 2, 0 } }), 3, 0.5)
		assert(p.defend == 4, "East's front is S4")
	end,
	["plan: no target left, everyone defends"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 0, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), nil, 0.5)
		assert(p.attack == nil and p.defend == 1 and p.share == 1)
	end,
	["defenders: rounded share, at least one, never all while attacking"] = function()
		assert(R.defenders(20, 0.5, true) == 10)
		assert(R.defenders(3, 0.5, true) == 2)
		assert(R.defenders(2, 0.1, true) == 1)
		assert(R.defenders(2, 0.99, true) == 1)
		assert(R.defenders(1, 0.5, true) == 0)
		assert(R.defenders(5, 0, true) == 0)
		assert(R.defenders(5, 1, false) == 5)
	end,
	["assign: keeps current defenders first, moves as few as it can"] = function()
		local ids = { 1, 2, 3, 4 }
		local a = R.assign(ids, { [3] = "Defend", [4] = "Defend" }, 1)
		assert(a[3] == "Defend" and a[4] == "Attack" and a[1] == "Attack" and a[2] == "Attack")
		a = R.assign(ids, { [3] = "Defend" }, 2)
		assert(a[3] == "Defend" and a[1] == "Defend" and a[2] == "Attack" and a[4] == "Attack")
		a = R.assign(ids, {}, 0)
		for _, id in ids do
			assert(a[id] == "Attack")
		end
	end,
	["capturedBy: the side a sector turned to, none for a neutralised one or the first look"] = function()
		assert(R.capturedBy(nil, OWNER) == nil, "first look")
		assert(R.capturedBy(OWNER, OWNER) == nil, "nothing changed")
		assert(R.capturedBy(OWNER, { "West", "West", "West", "East", "East" }) == "West")
		assert(R.capturedBy(OWNER, { "West", "West", "Neutral", "Neutral", "East" }) == nil, "only neutralised")
	end,
	["initiative: the race's capturer takes it, an offensive's capture or a spent one hands it over"] = function()
		assert(R.initiative(nil, nil, false) == nil, "the race goes on")
		assert(R.initiative(nil, "West", false) == "West", "the race won")
		assert(R.initiative("West", "West", false) == "East", "its offensive took the sector: the counter-attack")
		assert(R.initiative("West", "East", false) == "East", "the defender took one")
		assert(R.initiative("West", nil, true) == "East", "spent")
		assert(R.initiative("West", nil, false) == "West", "still going")
	end,
	["offensive: gathers for the waves and the ready share, at most gatherSeconds"] = function()
		local O = Cfg.Offensive
		local o = R.newOffensive(4, 0, false)
		local least = O.gatherWaves * 15
		local f = { now = least - 1, ready = 1, ours = 0, theirs = 0, waveEvery = 15 }
		assert(not R.offensive(o, f, O) and o.phase == "Gather", "the waves not in yet")
		f.now, f.ready = least, O.ready - 0.01
		R.offensive(o, f, O)
		assert(o.phase == "Gather", "not enough there")
		f.ready = O.ready
		R.offensive(o, f, O)
		assert(o.phase == "Barrage" and o.since == least, "ready: the barrage")
		local late = R.newOffensive(4, 0, false)
		R.offensive(late, { now = O.gatherSeconds, ready = 0, ours = 0, theirs = 0, waveEvery = 15 }, O)
		assert(late.phase == "Barrage", "out of time")
		local counter = R.newOffensive(4, 0, true)
		R.offensive(counter, { now = O.counterGather - 1, ready = 1, ours = 0, theirs = 0, waveEvery = 15 }, O)
		assert(counter.phase == "Gather", "a counter-attack waits its whole gather, ready or not")
		R.offensive(counter, { now = O.counterGather, ready = 0, ours = 0, theirs = 0, waveEvery = 15 }, O)
		assert(counter.phase == "Barrage", "then goes")
	end,
	["offensive: barrage, go, exploit and back, spent by losses or time"] = function()
		local O = Cfg.Offensive
		local o = R.newOffensive(4, 0, false)
		o.phase, o.since = "Barrage", 100
		local f = { now = 100 + O.barrageSeconds - 1, ready = 1, ours = 0, theirs = 0, waveEvery = 15 }
		R.offensive(o, f, O)
		assert(o.phase == "Barrage" and R.waiting(o) and not R.going(o))
		f.now = 100 + O.barrageSeconds
		R.offensive(o, f, O)
		assert(o.phase == "Go" and o.goAt == f.now and R.going(o) and not R.waiting(o))
		local go = f.now
		f.ours, f.theirs = O.exploitAt, O.exploitAt
		R.offensive(o, f, O)
		assert(o.phase == "Go", "not more than theirs")
		f.theirs = O.exploitAt - 1
		R.offensive(o, f, O)
		assert(o.phase == "Exploit")
		f.ours = 0
		R.offensive(o, f, O)
		assert(o.phase == "Go", "pushed out: back to Go")
		o.went, o.lost = 10, math.ceil(10 * O.spentShare) - 1
		assert(not R.offensive(o, f, O), "losses short of the share")
		o.lost += 1
		assert(R.offensive(o, f, O), "spent by losses")
		o.lost = 0
		f.now = go + O.maxSeconds
		assert(R.offensive(o, f, O), "spent by time")
		o.phase = "Exploit"
		f.ours = O.exploitAt
		assert(not R.offensive(o, f, O) and o.phase == "Exploit", "exploiting gets more time")
		f.now = go + O.maxSeconds + O.exploitMore
		assert(R.offensive(o, f, O), "but not for ever")
	end,
	["holdBack: everyone defends the sector under attack or the front, but the screen"] = function()
		local O = Cfg.Offensive
		local p = R.holdBack({ attack = 3, defend = nil, share = 0 }, 2, O, 4)
		assert(p.attack == 3 and p.defend == 2 and p.keep == O.screen * 4)
		assert(R.defendersFor(p, 20) == 20 - O.screen * 4 and R.defendersFor(p, 2) == 0)
		p = R.holdBack({ attack = 3, defend = 1, share = 0.5 }, 2, O, 4)
		assert(p.defend == 1, "the sector under attack first")
		p = R.holdBack({ attack = nil, defend = 1, share = 1 }, 1, O, 4)
		assert(p.keep == 0, "no target, no screen")
		assert(R.defendersFor({ attack = 3, defend = 2, share = 0.5 }, 20) == 10, "no keep: as before")
	end,
	["digIn: every other holder in the zone for a while after taking it"] = function()
		local D = Cfg.Offensive.dig
		assert(R.digIn(1, 0, D) and not R.digIn(2, 0, D) and R.digIn(1 + D.every, 0, D))
		assert(not R.digIn(1, D.hold, D), "over")
	end,
	["holdsZone: the first share of the squads, at least one"] = function()
		assert(R.holdsZone(1, 4, 0.5) and R.holdsZone(2, 4, 0.5) and not R.holdsZone(3, 4, 0.5))
		assert(R.holdsZone(1, 1, 0.5) and R.holdsZone(1, 3, 0.1) and not R.holdsZone(2, 3, 0.1))
	end,
}
