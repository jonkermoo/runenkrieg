--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotSquads")

local SQ = Cfg.Squads
local RT = Cfg.Routes

local function facts(over: { [string]: any }?): R.Facts
	local f: any = {
		now = 0,
		defend = false,
		contact = false,
		ready = 0,
		inZone = 0,
		ours = 0,
		theirs = 0,
		size = 4,
		moversThere = false,
	}
	for k, v in over or {} do
		f[k] = v
	end
	return f
end

return {
	["pinned: shot at, standing still long enough, most of it out of cover"] = function()
		local O = SQ.Open
		assert(R.pinned(O.after, true, 0, 6, O), "pinned in the open")
		assert(not R.pinned(O.after - 1, true, 0, 6, O), "not long enough")
		assert(not R.pinned(O.after, false, 0, 6, O), "not shot at")
		assert(not R.pinned(O.after, true, 3, 6, O), "half of it in cover")
		assert(not R.pinned(O.after, true, 0, 0, O), "nobody left")
	end,
	["moveOn: half its free members there, or anyone waited long enough; never nobody"] = function()
		local Q = Cfg.Squads
		assert(not R.moveOn(0, 4, 999, Q), "nobody there")
		assert(R.moveOn(2, 4, 0, Q) and not R.moveOn(1, 4, 0, Q), "half its free members")
		assert(R.moveOn(1, 4, Q.waitMax, Q), "one waited long enough")
		assert(R.moveOn(1, 0, 0, Q), "nobody free but it")
	end,
	["form: squads of the size, a small last one joins the one before"] = function()
		local s = R.form({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, 4, 2)
		assert(#s == 2 and #s[1] == 4 and #s[2] == 5, "the lone ninth joins the second")
		s = R.form({ 1, 2, 3, 4, 5, 6 }, 4, 2)
		assert(#s == 2 and #s[2] == 2)
		s = R.form({ 1 }, 4, 2)
		assert(#s == 1 and #s[1] == 1, "a lone bot is still a squad")
		assert(#R.form({}, 4, 2) == 0)
	end,
	["step: moves with no contact, bounds in contact, swapping halves when the movers are there or time is up"] = function()
		local sq = R.new()
		R.step(sq, facts(), SQ)
		assert(sq.phase == "Move")
		R.step(sq, facts({ contact = true, theirs = 6 }), SQ)
		assert(sq.phase == "Bound" and sq.moving == 1)
		R.step(sq, facts({ now = 1, contact = true, theirs = 6 }), SQ)
		assert(sq.moving == 1, "not yet")
		R.step(sq, facts({ now = 2, contact = true, theirs = 6, moversThere = true }), SQ)
		assert(sq.moving == 2, "the movers got there: swap")
		R.step(sq, facts({ now = 2 + SQ.boundMax, contact = true, theirs = 6 }), SQ)
		assert(sq.moving == 1, "time up: swap")
		R.step(sq, facts({ now = 20 }), SQ)
		assert(sq.phase == "Move", "contact lost")
	end,
	["step: pushes at the zone's edge under covering fire, with nobody in the way, or outnumbering them"] = function()
		local sq = R.new()
		R.step(sq, facts({ ready = 1 }), SQ)
		assert(sq.phase == "Assault", "there, no contact")
		sq = R.new()
		R.step(sq, facts({ contact = true, theirs = 8 }), SQ)
		R.step(sq, facts({ contact = true, theirs = 8, ready = 0.75 }), SQ)
		assert(sq.phase == "Assault", "bounding up with covering fire, then in")
		sq = R.new()
		R.step(sq, facts({ contact = true, ours = 3, theirs = 2, ready = 1 }), SQ)
		assert(sq.phase == "Assault", "outnumbering")
		sq = R.new()
		R.step(sq, facts({ contact = true, ours = 0, theirs = 9, ready = 1 }), SQ)
		assert(sq.phase == "Bound", "outnumbered, no covering fire yet: bound first")
		R.step(sq, facts({ contact = true, theirs = 9, ready = 0.1 }), SQ)
		R.step(sq, facts({ contact = false, theirs = 9 }), SQ)
		assert(sq.phase == "Move")
		R.step(sq, facts({ contact = true, theirs = 9, ready = 0 }), SQ)
		R.step(sq, facts({ contact = true, theirs = 9, ready = 0 }), SQ)
		assert(sq.phase == "Bound", "not there yet: no push")
	end,
	["step: an assault holds until the order changes; defenders hold"] = function()
		local sq = R.new()
		R.step(sq, facts({ ready = 1 }), SQ)
		R.step(sq, facts({ contact = true, theirs = 9 }), SQ)
		assert(sq.phase == "Assault")
		R.step(sq, facts({ defend = true }), SQ)
		assert(sq.phase == "Hold")
		R.step(sq, facts(), SQ)
		assert(sq.phase == "Move", "a new attack order starts from the walk")
	end,
	["role: bounding halves alternate by place; the other phases one role for all"] = function()
		local sq = R.new()
		assert(R.role(sq, 1) == "Move" and R.role(sq, 2) == "Move")
		sq.phase, sq.moving = "Bound", 1
		assert(R.role(sq, 1) == "Move" and R.role(sq, 2) == "Support" and R.role(sq, 3) == "Move")
		sq.moving = 2
		assert(R.role(sq, 1) == "Support" and R.role(sq, 2) == "Move")
		sq.phase = "Assault"
		assert(R.role(sq, 2) == "Assault")
		sq.phase = "Hold"
		assert(R.role(sq, 1) == "Hold")
	end,
	["pickSpot: cover and things near first, its lane kept, a crowded lane avoided"] = function()
		local spots: { R.Spot } = {
			{ hidden = false, near = 0, distance = 10, lane = 0 },
			{ hidden = true, near = 2, distance = 20, lane = 0 },
			{ hidden = true, near = 3, distance = 30, lane = 1 },
		}
		local zero = { 0, 0, 0 }
		assert(R.pickSpot(spots, nil, {}, zero, RT.weights, RT.nearCap) == 3, "the most cover overall")
		assert(R.pickSpot(spots, 0, {}, zero, RT.weights, RT.nearCap) == 2, "kept to its lane")
		assert(R.pickSpot(spots, -1, {}, zero, RT.weights, RT.nearCap) == 3, "no spots in its lane: any")
		assert(R.pickSpot(spots, nil, { [1] = 3 }, zero, RT.weights, RT.nearCap) == 2, "the crowded lane avoided")
		assert(R.pickSpot({}, nil, {}, {}, RT.weights, RT.nearCap) == nil)
	end,
	["lane: the centre within the angle, the sides by which side"] = function()
		-- home at the origin, the goal 100 east: spots round the goal, measured against the way back west
		assert(R.lane(0, 0, 100, 0, 80, 2, 25) == 0, "on the way home")
		local north = R.lane(0, 0, 100, 0, 90, 30, 25)
		local south = R.lane(0, 0, 100, 0, 90, -30, 25)
		assert(north ~= 0 and south ~= 0 and north == -south, `{north} {south}`)
	end,
	["quietLane: the emptiest lane, the centre first"] = function()
		assert(R.quietLane({}) == 0)
		assert(R.quietLane({ [0] = 1 }) == -1)
		assert(R.quietLane({ [0] = 1, [-1] = 1 }) == 1)
	end,
	["group: the nearest known enemy in reach and those close to it"] = function()
		local P = SQ.Push
		local known = { { x = 50, z = 0 }, { x = 55, z = 5 }, { x = 50 + P.cluster + 5, z = 0 }, { x = 300, z = 0 } }
		local x, z, n = R.group(known, 0, 0, P)
		assert(n == 2 and x and z and math.abs(x - 52.5) < 1e-6 and math.abs(z - 2.5) < 1e-6, "the two together")
		local nx, _, none = R.group({ { x = P.reach + 1, z = 0 } }, 0, 0, P)
		assert(nx == nil and none == 0, "none in reach")
	end,
	["confident: 1.5 to 1"] = function()
		local P = SQ.Push
		assert(R.confident(3, 2, P) and not R.confident(2, 2, P), "3 on 2, not 2 on 2")
		assert(not R.confident(5, 0, P), "nobody to push at")
	end,
	["step: an offensive holds the squad back while waiting, then all in"] = function()
		local sq = R.new()
		local f = {
			now = 0,
			defend = false,
			contact = false,
			ready = 1,
			inZone = 0,
			ours = 0,
			theirs = 0,
			size = 4,
			moversThere = true,
			wait = true,
		}
		R.step(sq, f, SQ)
		assert(sq.phase == "Move", "ready, but held back")
		sq.phase = "Assault"
		R.step(sq, f, SQ)
		assert(sq.phase == "Move", "back out of an assault")
		f.wait, f.go, f.ready = false, true, 0
		R.step(sq, f, SQ)
		assert(sq.phase == "Assault", "go: in, no ready check")
	end,
	["restart: an Assault squad stuck out of the zone"] = function()
		local O = Cfg.Offensive
		assert(R.restart("Assault", O.stuckFor, 0, O.stuckFor))
		assert(not R.restart("Assault", O.stuckFor - 1, 0, O.stuckFor), "not long enough")
		assert(not R.restart("Assault", O.stuckFor, 0.5, O.stuckFor), "in the zone")
		assert(not R.restart("Bound", O.stuckFor, 0, O.stuckFor), "not assaulting")
	end,
}
