--!strict
local Cfg = require("../src/shared/Config/Cutscenes")
local Front = require("../src/shared/Config/Frontline")
local R = require("../src/shared/Rules/Cutscenes")
local Maps = require("./frontlinemaps")

local function points(map: any): { { number } }
	local out = {}
	for _, s in map.sectors do
		table.insert(out, { s.x, s.z })
	end
	return out
end

local function inBounds(map: any, p: R.Place, margin: number): boolean
	local b = map.bounds
	return p.x >= b.minX - margin and p.x <= b.maxX + margin and p.z >= b.minZ - margin and p.z <= b.maxZ + margin
end

local tests: { [string]: () -> () } = {
	["the pre-match cut is exactly the countdown"] = function()
		assert(R.length(Cfg.Pre) == Front.CountdownSeconds, "the pre-match cut fills the countdown")
		for _, cut in { Cfg.Pre } do
			local last = 0
			for _, s in cut.shots do
				assert(s.t1 > last, `{s.name} ends after the shot before it`)
				last = s.t1
			end
		end
	end,
	["the shot at a time, and how far through it"] = function()
		local s, i, u = R.at(Cfg.Pre, 0)
		assert(i == 1 and s.name == "Sheet" and u == 0)
		s, i, u = R.at(Cfg.Pre, 1.6)
		assert(i == 2 and u == 0, "a shot starts where the last ends (a hard cut)")
		s, i, u = R.at(Cfg.Pre, 9.4)
		assert(s.kind == "Front" and math.abs(u - 0.5) < 1e-6)
		s, i, u = R.at(Cfg.Pre, 99)
		assert(i == #Cfg.Pre.shots and u == 1, "past the end: the last shot, done")
		assert(R.start(Cfg.Pre, 3) == 2.8)
	end,
	["a map with its own cuts plays them; the others the shared ones"] = function()
		local stub = { Pre = "shared", Post = "sharedPost", Maps = { Capital = { Pre = "own" } } }
		assert(R.cut(stub, "Pre", "Capital") == "own")
		assert(R.cut(stub, "Post", "Capital") == "sharedPost", "a kind it lacks is the shared one")
		assert(R.cut(stub, "Pre", "Map1") == "shared" and R.cut(stub, "Pre", nil) == "shared")
	end,
	["the match is won at the loser's HQ, a no-winner end shown at the middle"] = function()
		local map = Maps.maps[1].map
		assert(R.taken(map, "West") == #map.sectors and R.taken(map, "East") == 1)
		assert(R.taken(map, nil) == 3)
	end,
	["captions are filled in, unknown keys left empty"] = function()
		assert(R.text("{map}", { map = "Map 1" }) == "Map 1")
		assert(R.text("{west} vs {east}", { west = "Katzmark", east = "Selvara" }) == "Katzmark vs Selvara")
		assert(R.text("{nope}!", {}) == "!" and R.text(nil, {}) == "")
	end,
	["the sheet covers the sheet shots, fades out over the dive and in at the end"] = function()
		local sheet, dive, post = Cfg.Pre.shots[1], Cfg.Pre.shots[2], { kind = "Paper", paper = "in" }
		assert(R.paper(sheet, 0.5, 0.35) == 1)
		assert(R.paper(dive, 0, 0.35) == 1 and R.paper(dive, 0.35, 0.35) == 0)
		assert(R.paper(post, 0, 0.35) == 0 and R.paper(post, 1, 0.35) == 1)
		assert(R.paper(Cfg.Pre.shots[3], 0.5, 0.35) == 0)
	end,
	["the seals are stamped as the flight passes each point, the winner's one by one"] = function()
		local front = Cfg.Pre.shots[3]
		assert(R.stamped(front, 0, 5) == 1 and R.stamped(front, 0.12, 5) == 1 and R.stamped(front, 0.13, 5) == 2)
		assert(R.stamped(front, 0.9, 5) == 5, "the last is stamped while the flight still shows it")
		assert(R.stamped(front, 1, 5) == 5)
		local crane = { kind = "Move", stamps = true }
		assert(R.stamped(crane, 0, 5) == 0 and R.stamped(crane, 1, 5) == 5)
		local last = 0
		for k = 0, 20 do
			local n = R.stamped(crane, k / 20, 5)
			assert(n >= last, "never unstamped")
			last = n
		end
	end,
	["part one: where they won and the momentum, by map and nation"] = function()
		local sp = Cfg.Speech
		local one = R.partOne(sp, "uniform1", "Map1", "Katzmark")
		assert(#one == 2 and one[1].text:find("Katzmark holds the valley", 1, true), one[1].text)
		assert(one[2].text == sp.momentum.uniform1)
		local none = R.partOne(sp, nil, "LanternMeadows", "")
		assert(none[1].text == sp.wonNone.LanternMeadows and none[2].text == sp.momentum.none)
		assert(#R.partOne(sp, "uniform2", "Nowhere", "Selvara") == 1, "a map with no line: the momentum alone")
		for _, l in one do
			assert(not l.text:find("{", 1, true), "every token filled")
		end
	end,
	["part two: a line as the dive starts, one at each point, the call on the whistle"] = function()
		local sp, cut = Cfg.Speech, Cfg.Pre
		local two = R.partTwo(sp, cut, "uniform3", "Map1", 5)
		assert(#two == 7, "the dive, five points, the call")
		assert(two[1].at == R.start(cut, 2), "the first order as the dive starts")
		local front = cut.shots[3]
		for i = 1, 5 do
			assert(two[i + 1].text == sp.plans.Map1[i + 1])
			assert(math.abs(two[i + 1].at - R.orderTime(front, R.start(cut, 3), i, 5)) < 1e-9)
			assert(two[i + 1].at >= two[i].at, "in order along the flight")
		end
		assert(two[7].text == sp.close.uniform3 and two[7].at == R.start(cut, #cut.shots))
		local bare = R.partTwo(sp, cut, nil, "Nowhere", 5)
		assert(#bare == 1 and bare[1].text == sp.close.none, "a map without a plan: the call alone")
	end,
	["each order is said before the flight reaches the next point"] = function()
		local sp, cut = Cfg.Speech, Cfg.Pre
		local front = cut.shots[3]
		local t0 = R.start(cut, 3)
		for key, plan in sp.plans do
			local n = #plan - 1
			for i = 1, n - 1 do
				local room = R.orderTime(front, t0, i + 1, n) - R.orderTime(front, t0, i, n)
				local say = R.speechSeconds({ { text = plan[i + 1], at = 0 } }, sp.wordsPerSecond, 0) + sp.gap
				assert(say <= room, `{key}: "{plan[i + 1]}" takes {say} s, the point gives {room} s`)
			end
		end
	end,
	["no bayonets in the closing calls (user 2026-11-02)"] = function()
		for _, line in Cfg.Speech.close do
			assert(not line:lower():find("bayonet", 1, true), line)
		end
	end,
	["lines never overlap, and never start before their cue"] = function()
		local lines = { { text = "a", at = 0 }, { text = "b", at = 1 }, { text = "c", at = 10 } }
		local t = R.schedule(lines, { 3, 2, 1 }, 0.5)
		assert(t[1] == 0 and t[2] == 3.5 and t[3] == 10)
		local words =
			R.speechSeconds({ { text = "one two three four", at = 0 }, { text = "five six", at = 0 } }, 2, 0.5)
		assert(math.abs(words - 3.5) < 1e-9)
	end,
	["every line fits text-to-speech's 300 characters, part one fits the armory's longest stay"] = function()
		local sp = Cfg.Speech
		for _, group in { sp.won, sp.wonNone, sp.momentum, sp.close } do
			for _, line in group do
				assert(#line <= 300, line)
			end
		end
		for _, plan in sp.plans do
			for _, line in plan do
				assert(#line <= 300, line)
			end
		end
		for key in sp.won do
			for kit in sp.momentum do
				local one = R.partOne(sp, if kit == "none" then nil else kit, key, "Katzmark")
				assert(R.speechSeconds(one, sp.wordsPerSecond, sp.gap) < Front.Loading.max, "part one fits")
			end
		end
	end,
	["the winners sign; everyone when there is no winner or no winner is playing"] = function()
		assert(R.maySign("West", "West", true) and not R.maySign("East", "West", true))
		assert(not R.maySign(nil, "East", true), "someone with no side doesn't sign for the winners")
		assert(R.maySign("East", "West", false) and R.maySign("East", nil, true))
	end,
	["the vote offers the built maps, the live one first, at most the cap"] = function()
		local keys = { "A", "B", "C", "D" }
		local built = { A = true, B = true, C = false, D = true }
		local o = R.offer(keys, built, "B", 3)
		assert(#o == 3 and o[1] == "B" and o[2] == "A" and o[3] == "D")
		assert(#R.offer(keys, built, "B", 2) == 2)
		local none = R.offer(keys, built, "C", 3)
		assert(#none == 3 and none[1] == "A", "an unbuilt live map isn't offered")
	end,
	["most votes win; a tie (or no votes) is drawn among the tied"] = function()
		local offer = { "Map1", "LanternMeadows" }
		local t = R.tally({ [1] = "Map1", [2] = "LanternMeadows", [3] = "LanternMeadows", [4] = "Nope" }, offer)
		assert(t.Map1 == 1 and t.LanternMeadows == 2 and t.Nope == nil, "a vote for a map not offered doesn't count")
		assert(R.pick(t, offer, 0) == "LanternMeadows" and R.pick(t, offer, 0.99) == "LanternMeadows")
		local tie = R.tally({ [1] = "Map1", [2] = "LanternMeadows" }, offer)
		assert(R.pick(tie, offer, 0) == "Map1" and R.pick(tie, offer, 0.99) == "LanternMeadows")
		local empty = R.tally({}, offer)
		assert(R.pick(empty, offer, 0.2) == "Map1" and R.pick(empty, offer, 0.7) == "LanternMeadows")
		assert(R.pick(R.tally({}, {}), {}, 0.5) == nil)
	end,
}

for name, fn in
	Maps.each(function(map: any, _name: string)
		return {
			["every cut's camera stays over the map and above the ground, for either side and winner"] = function()
				local pts = points(map)
				for _, kind in { "Pre" } do
					local cut = R.cut(Cfg, kind, nil)
					for _, home in { "West", "East" } do
						for _, winner in { "West", "East", "None" } do
							local w: R.Side? = if winner == "None" then nil else winner :: R.Side
							local anchors = R.anchors(map, home :: R.Side, w, Cfg.LandmarkReach)
							for _, shot in cut.shots do
								local flip = R.mirrored(shot, home :: R.Side, w)
								for k = 0, 10 do
									local p = R.pose(shot, k / 10, anchors, pts, flip, Cfg.Paper.up)
									assert(inBounds(map, p.eye, 800), `{kind} {shot.name}: camera over the map`)
									assert(p.eye.up > 0, `{kind} {shot.name}: camera over the ground`)
									local d = math.sqrt((p.look.x - p.eye.x) ^ 2 + (p.look.z - p.eye.z) ^ 2)
									assert(d > 1 or p.eye.up > 50, `{kind} {shot.name}: looks somewhere`)
								end
							end
						end
					end
				end
			end,
			["the flight runs west to east over every point"] = function()
				local pts = points(map)
				local anchors = R.anchors(map, "West", nil, Cfg.LandmarkReach)
				local front = Cfg.Pre.shots[3]
				local a = R.pose(front, 0, anchors, pts, false, 0)
				local b = R.pose(front, 1, anchors, pts, false, 0)
				assert(a.look.x == pts[1][1] + front.lead and b.look.x == pts[#pts][1] + front.lead)
			end,
			["the line shots frame each side's spawn, the finale the loser's HQ"] = function()
				local anchors = R.anchors(map, "East", "East", Cfg.LandmarkReach)
				local west = R.pose(Cfg.Pre.shots[4], 1, anchors, points(map), false, 0)
				local wc = anchors.WestSpawn
				assert(west.look.x == wc[1] and west.look.z == wc[2])
				assert(anchors.Home == anchors.EastSpawn and anchors.Taken[1] == map.sectors[1].x)
				local orbit = { kind = "Orbit", at = "Taken", radius = 75, up = 26, lookUp = 28, from = 2.7, to = 1.5 }
				local p = R.pose(orbit, 0.5, anchors, points(map), true, 0)
				local r = math.sqrt((p.eye.x - map.sectors[1].x) ^ 2 + (p.eye.z - map.sectors[1].z) ^ 2)
				assert(math.abs(r - orbit.radius) < 1e-6, "the orbit is round the taken HQ")
			end,
			["the narrator has every line for this map: where it was won, lost, and its orders"] = function()
				local sp = Cfg.Speech
				local key = _name
				assert(sp.won[key] and sp.wonNone[key], `{key} has its won lines`)
				local plan = sp.plans[key]
				assert(plan and #plan == #map.sectors + 1, `{key} has the dive's order and one per point`)
			end,
			["the seals name their landmarks where a point has one"] = function()
				local named = 0
				for i = 1, #map.sectors do
					local id = R.landmark(map, i, Cfg.LandmarkReach)
					if id then
						assert(Cfg.Names[id], `landmark {id} has a name`)
						named += 1
					end
				end
				assert(named >= 3, "most points have a landmark in view")
			end,
		}
	end)
do
	tests[name] = fn
end

return tests
