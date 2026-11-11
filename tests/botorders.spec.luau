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

local W = Cfg.Routes.weights
local CAP = Cfg.Routes.nearCap

return {
	["clearOfOwn: never on a zone the side holds, a neutral or enemy one is no bar"] = function()
		local s = { { x = 0, z = 0, radius = 50 }, { x = 400, z = 0, radius = 50 } }
		local owner = { "West", "East" }
		assert(not R.clearOfOwn(60, 0, s, owner, "West", 20), "inside its zone plus the clearance")
		assert(R.clearOfOwn(80, 0, s, owner, "West", 20))
		assert(R.clearOfOwn(400, 0, s, owner, "West", 20), "the enemy's point is not its own")
		assert(R.clearOfOwn(60, 0, s, nil, "West", 20), "no owners known yet")
	end,
	["gatherSpot: in its lane if it can, nearer the squad and hidden better, full spots out"] = function()
		local spots = {
			{ x = 0, z = 0, hidden = false, near = 0, lane = 0 },
			{ x = 10, z = 0, hidden = true, near = 0, lane = 0 },
			{ x = 500, z = 0, hidden = true, near = 0, lane = 1 },
		}
		assert(R.gatherSpot(spots, {}, 0, 0, 0, {}, W, CAP, 2) == 2, "hidden beats a few studs")
		assert(R.gatherSpot(spots, { [2] = 2 }, 0, 0, 0, {}, W, CAP, 2) == 1, "a full spot is passed over")
		assert(R.gatherSpot(spots, {}, 1, 0, 0, {}, W, CAP, 2) == 3, "its own lane first")
		assert(R.gatherSpot(spots, { 2, 2 }, 0, 0, 0, {}, W, CAP, 2) == 3, "no room in its lane: another's")
		assert(R.gatherSpot(spots, { 2, 2, 2 }, 0, 0, 0, {}, W, CAP, 2) == nil)
	end,
	["rollDue: the first wave at once, then on its time, sooner with nobody attacking"] = function()
		local o = R.newOffensive(3, 0, false)
		local cfg = { quiet = 3 }
		assert(R.rollDue(o, 100, 0, cfg))
		o.lastWave, o.nextWave = 100, 110
		assert(not R.rollDue(o, 105, 2, cfg))
		assert(R.rollDue(o, 110, 2, cfg))
		assert(not R.rollDue(o, 102, 0, cfg), "just gone")
		assert(R.rollDue(o, 103, 0, cfg))
	end,
	["pickWave: ready squads, lanes the last wave didn't use, the rest only when nobody attacks"] = function()
		local c = {
			{ lane = 0, there = true },
			{ lane = 0, there = true },
			{ lane = 1, there = true },
			{ lane = -1, there = false },
		}
		local a = R.pickWave(c, 2, { 0 }, false)
		assert(#a == 2 and a[1] == 3 and a[2] == 1, "a fresh lane first, then a different one")
		a = R.pickWave(c, 2, {}, false)
		assert(a[1] == 1 and a[2] == 3, "two lanes before two in one")
		assert(#R.pickWave({ c[4] }, 2, {}, false) == 0, "nobody ready")
		assert(#R.pickWave({ c[4] }, 2, {}, true) == 1, "nobody attacking: it goes as it is")
	end,
	["fellBack: under half left and out of the zone"] = function()
		local cfg = { fallBelow = 0.5 }
		assert(R.fellBack(1, 4, 0, cfg))
		assert(not R.fellBack(2, 4, 0, cfg))
		assert(not R.fellBack(1, 4, 1, cfg), "in the zone it stays")
	end,
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
	["danger: control lost or outnumbered in the zone, the worse; the defend share rises with it"] = function()
		assert(R.danger("West", 1, { West = 3, East = 0 }) == 0, "calm")
		assert(R.danger("West", 0.5, { West = 3, East = 1 }) == 0.5, "half its control gone halfway")
		assert(R.danger("West", 0, { West = 3, East = 1 }) == 1, "control half gone: all")
		assert(R.danger("West", 1, { West = 1, East = 2 }) == 1, "twice as many: all")
		assert(R.danger("East", -1, { West = 4, East = 3 }) > 0, "East outnumbered")
		local cap = Cfg.Lanes.danger
		local calm = R.plan("West", OWNER, REST, counts({ { 0, 0 }, { 2, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		local p = R.plan(
			"West",
			OWNER,
			REST,
			counts({ { 0, 0 }, { 1, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }),
			3,
			0.5,
			nil,
			nil,
			cap
		)
		assert(calm.defend == nil and p.defend == 2 and math.abs(p.share - cap) < 1e-6, "desperate: up to the cap")
		local some = R.plan(
			"West",
			OWNER,
			{ 1, 0.8, 0, -1, -1 },
			counts({ { 0, 0 }, { 3, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }),
			3,
			0.5,
			nil,
			nil,
			cap
		)
		assert(some.share > 0.5 and some.share < cap, "slipping a little: a little more")
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
	["offensive: past gatherSeconds it waits for squads still walking up, at most gatherMax"] = function()
		local O = Cfg.Offensive
		-- (Lantern Meadows: squads 150-400 studs back at 60 s went in piecemeal)
		local o = R.newOffensive(3, 0, false)
		local due = R.due({ 400, 300, 150, 150, 20 }, O.ready, O.pace) :: number
		assert(math.abs(due - 150 / O.pace) < 1e-9, "the ready share's walk: the 3rd nearest of 5 (60%)")
		R.offensive(o, { now = O.gatherSeconds, ready = 0, ours = 0, theirs = 0, waveEvery = 15, due = due }, O)
		assert(o.phase == "Gather", "still on their way: it waits")
		R.offensive(o, { now = O.gatherSeconds + 20, ready = 0.2, ours = 0, theirs = 0, waveEvery = 15, due = 4 }, O)
		assert(o.phase == "Barrage", "near enough (within dueSlack): it goes")
		local slow = R.newOffensive(3, 0, false)
		R.offensive(slow, { now = O.gatherMax, ready = 0, ours = 0, theirs = 0, waveEvery = 15, due = 999 }, O)
		assert(slow.phase == "Barrage", "never waits past gatherMax")
		assert(R.due({}, O.ready, O.pace) == nil, "nobody on the way")
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
	["standTo: the holders of the sector the enemy's offensive goes into"] = function()
		local o = R.newOffensive(3, 0, false)
		assert(not R.standTo(true, o, 3), "still gathering")
		o.phase = "Go"
		assert(R.standTo(true, o, 3) and not R.standTo(true, o, 2) and not R.standTo(false, o, 3))
		o.phase = "Exploit"
		assert(R.standTo(true, o, 3) and not R.standTo(true, nil, 3))
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
