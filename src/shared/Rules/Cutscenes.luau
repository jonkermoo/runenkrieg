--!strict
-- The match cutscenes' shots and the map vote (Config/Cutscenes; src/client/MatchCutscene, src/client/MapVote,
-- src/server/MapVote). Pure: positions are { x, z, up } (up over the ground there; the client finds the ground).

local Cutscenes = {}

export type Place = { x: number, z: number, up: number }
export type Pose = { eye: Place, look: Place, roll: number, fov: number? }
export type Side = "West" | "East"

-- The cut of `kind` ("Pre" / "Post") for map `key`: the map's own when Config/Cutscenes.Maps has one.
function Cutscenes.cut(cfg: any, kind: string, key: string?): any
	local own = key and cfg.Maps[key]
	return own and own[kind] or cfg[kind]
end

-- A cut's length in seconds: its last shot's end.
function Cutscenes.length(cut: any): number
	return cut.shots[#cut.shots].t1
end

-- The shot playing `t` seconds into `cut`, its index and how far through it (0..1). Past the end: the last, at 1.
function Cutscenes.at(cut: any, t: number): (any, number, number)
	local t0 = 0
	for i, s in cut.shots do
		if t < s.t1 then
			return s, i, math.clamp((t - t0) / math.max(s.t1 - t0, 1e-6), 0, 1)
		end
		t0 = s.t1
	end
	return cut.shots[#cut.shots], #cut.shots, 1
end

-- When shot `i` of `cut` starts.
function Cutscenes.start(cut: any, i: number): number
	return if i <= 1 then 0 else cut.shots[i - 1].t1
end

local function ease(u: number): number
	return if u < 0.5 then 2 * u * u else 1 - (-2 * u + 2) ^ 2 / 2
end
Cutscenes.ease = ease

local function centre(r: any): { number }
	return { (r.minX + r.maxX) / 2, (r.minZ + r.maxZ) / 2 }
end

-- The landmark of point `i`: the id of the map's special building (village.specials) nearest it within `reach`, and
-- where it stands.
function Cutscenes.landmark(map: any, i: number, reach: number): (string?, { number }?)
	local s = map.sectors[i]
	local village = map.village
	local best, at, bestD = nil, nil, reach
	for _, sp in (village and village.specials) or {} do
		local d = math.sqrt((sp.x - s.x) ^ 2 + (sp.z - s.z) ^ 2)
		if d <= bestD then
			best, at, bestD = sp.id, { sp.x, sp.z }, d
		end
	end
	return best, at
end

-- The point the match was won on: the loser's HQ (the West wins at the last point, the East at the first); with no
-- winner the middle point.
function Cutscenes.taken(map: any, winner: Side?): number
	local n = #map.sectors
	return if winner == "West" then n elseif winner == "East" then 1 else math.ceil(n / 2)
end

-- Every anchor a shot can name on `map` ({ x, z }): S1..Sn, Mark1..Markn, WestSpawn, EastSpawn, Home (the spawn of
-- `home`, the West's without one), Taken (for `winner`), Centre.
function Cutscenes.anchors(map: any, home: Side?, winner: Side?, reach: number): { [string]: { number } }
	local out: { [string]: { number } } = {}
	for i, s in map.sectors do
		out[`S{i}`] = { s.x, s.z }
		local _, at = Cutscenes.landmark(map, i, reach)
		out[`Mark{i}`] = at or { s.x, s.z }
	end
	out.WestSpawn = centre(map.spawnZones.West)
	out.EastSpawn = centre(map.spawnZones.East)
	out.Home = if home == "East" then out.EastSpawn else out.WestSpawn
	out.Taken = out[`S{Cutscenes.taken(map, winner)}`]
	out.Centre = out[`S{math.ceil(#map.sectors / 2)}`]
	return out
end

-- Whether shot `shot` is turned east-west for this viewer (`home`) and match (`winner`).
function Cutscenes.mirrored(shot: any, home: Side?, winner: Side?): boolean
	return (shot.mirror == "home" and home == "East") or (shot.mirror == "winner" and winner == "East")
end

local function place(key: any, anchors: { [string]: { number } }, flip: boolean): Place
	local a = anchors[key.at] or { 0, 0 }
	local dx = (key.dx or 0) * (if flip then -1 else 1)
	return { x = a[1] + dx, z = a[2] + (key.dz or 0), up = key.up or 0 }
end

local function mix(a: Place, b: Place, u: number): Place
	return { x = a.x + (b.x - a.x) * u, z = a.z + (b.z - a.z) * u, up = a.up + (b.up - a.up) * u }
end

-- Where the camera is and looks `u` through `shot` (Config/Cutscenes' kinds), on a map with these `anchors`, its
-- points `points` ({ { x, z } } west to east), `flip`ped east-west or not; `paperUp` the parked camera's height. An
-- "Eyes" shot's pose is its `from` (the client blends into the soldier's head).
function Cutscenes.pose(
	shot: any,
	u: number,
	anchors: { [string]: { number } },
	points: { { number } },
	flip: boolean,
	paperUp: number
): Pose
	local roll = (shot.roll or 0) * (if flip then -1 else 1)
	if shot.kind == "Paper" then
		local c = anchors.Centre
		return { eye = { x = c[1], z = c[2] - 1, up = paperUp }, look = { x = c[1], z = c[2], up = 0 }, roll = 0 }
	elseif shot.kind == "Orbit" then
		local c = anchors[shot.at] or { 0, 0 }
		local a = shot.from + (shot.to - shot.from) * ease(u)
		if flip then
			a = math.pi - a
		end
		return {
			eye = { x = c[1] + math.cos(a) * shot.radius, z = c[2] + math.sin(a) * shot.radius, up = shot.up },
			look = { x = c[1], z = c[2], up = shot.lookUp or 0 },
			roll = roll,
		}
	elseif shot.kind == "Front" then
		local n = #points
		local s = u * (n - 1)
		local i = math.min(n - 1, math.floor(s) + 1)
		local f = s - (i - 1)
		local x = points[i][1] + (points[i + 1][1] - points[i][1]) * f
		local z = points[i][2] + (points[i + 1][2] - points[i][2]) * f
		return {
			eye = { x = x - shot.lead * shot.back, z = z + shot.side, up = shot.up },
			look = { x = x + shot.lead, z = z, up = 0 },
			roll = roll,
		}
	elseif shot.kind == "Eyes" then
		local e = place(shot.from, anchors, flip)
		local dir = if flip then -1 else 1
		return { eye = e, look = { x = e.x + dir * 400, z = e.z, up = 4 }, roll = 0 }
	end
	local k = ease(u)
	local eye = mix(place(shot.from, anchors, flip), place(shot.to or shot.from, anchors, flip), k)
	local look = place(shot.look, anchors, flip)
	if shot.lookTo then
		look = mix(look, place(shot.lookTo, anchors, flip), k)
	end
	return { eye = eye, look = look, roll = roll, fov = shot.fov }
end

-- How many of the `n` point seals are stamped `u` through a `stamps` shot: the Front's as the camera comes within half
-- the way to each point (the first at once, the last before the shot ends, so it's seen), any other's one after
-- another over the shot.
function Cutscenes.stamped(shot: any, u: number, n: number): number
	if shot.kind == "Front" then
		return math.clamp(math.floor(u * (n - 1) + 0.5) + 1, 1, n)
	end
	return math.clamp(math.floor(u * (n + 0.999)), 0, n)
end

-- The share of the sheet over the world `u` through `shot` (1 = all paper), with `fade` of the shot's time to turn.
function Cutscenes.paper(shot: any, u: number, fade: number): number
	if shot.kind == "Paper" and shot.paper ~= "in" then
		return 1
	elseif shot.paper == "out" then
		return 1 - math.clamp(u / math.max(fade, 1e-6), 0, 1)
	elseif shot.paper == "in" then
		return math.clamp(u / math.max(fade, 1e-6), 0, 1)
	end
	return 0
end

-- A caption's text: `{map}`, `{west}`, `{east}`, `{winner}` filled from `fill`.
function Cutscenes.text(template: string?, fill: { [string]: string }): string
	if not template then
		return ""
	end
	return (template:gsub("{(%w+)}", function(k)
		return fill[k] or ""
	end))
end

-- The narrator (Config/Cutscenes.Speech). A line: its words and the earliest it may start (seconds into its part).
export type Line = { text: string, at: number }

-- Part one, in the armory: where the match was won (`played`: the map's key) and the momentum, for the winning kit
-- (`winner`, nil: no winner) whose nation is `nation`. Every line at 0: they follow one another.
function Cutscenes.partOne(speech: any, winner: string?, played: string, nation: string): { Line }
	local won = if winner then speech.won[played] else speech.wonNone[played]
	local out: { Line } = {}
	if won then
		table.insert(out, { text = Cutscenes.text(won, { winner = nation }), at = 0 })
	end
	local momentum = speech.momentum[winner or "none"]
	if momentum then
		table.insert(out, { text = momentum, at = 0 })
	end
	return out
end

-- When the order for point `i` of `n` is spoken in the flight's `shot` (which runs from `t0`): the flight shared out
-- evenly, the first at its start, each as the camera comes up on its point.
function Cutscenes.orderTime(shot: any, t0: number, i: number, n: number): number
	return t0 + (i - 1) / math.max(n, 1) * (shot.t1 - t0)
end

-- Part two, over the pre-match flight `cut` on a map with `n` points (`nextMap` its key): the plan's first line as the
-- dive starts, one as the camera comes up on each point, then the closing call (by the winning kit) as the camera goes into
-- the soldier's eyes. A map without a plan gets only the call.
function Cutscenes.partTwo(speech: any, cut: any, winner: string?, nextMap: string, n: number): { Line }
	local out: { Line } = {}
	local plan = speech.plans[nextMap]
	local starts: { [string]: number } = {}
	local front, frontT0 = nil, 0
	for i, s in cut.shots do
		starts[s.kind] = starts[s.kind] or Cutscenes.start(cut, i)
		if s.kind == "Front" and not front then
			front, frontT0 = s, Cutscenes.start(cut, i)
		end
	end
	if plan then
		if plan[1] then
			table.insert(out, { text = plan[1], at = starts.Move or 0 })
		end
		for i = 1, n do
			local line = plan[i + 1]
			if line then
				local at = if front then Cutscenes.orderTime(front, frontT0, i, n) else 0
				table.insert(out, { text = line, at = at })
			end
		end
	end
	local close = speech.close[winner or "none"]
	if close then
		table.insert(out, { text = close, at = starts.Eyes or Cutscenes.length(cut) })
	end
	return out
end

-- About how long `lines` take spoken one after another: their words at `wps` words a second, `gap` between lines.
function Cutscenes.speechSeconds(lines: { Line }, wps: number, gap: number): number
	local total = 0
	for k, l in lines do
		local _, words = string.gsub(l.text, "%S+", "")
		total += words / wps + (if k > 1 then gap else 0)
	end
	return total
end

-- When each line starts, given how long each takes (`seconds`, by index): no earlier than its cue, never before the
-- line before it has ended and `gap` passed.
function Cutscenes.schedule(lines: { Line }, seconds: { number }, gap: number): { number }
	local out, free = {}, -math.huge
	for k, l in lines do
		local start = math.max(l.at, free)
		out[k] = start
		free = start + (seconds[k] or 0) + gap
	end
	return out
end

-- Whether a soldier of `side` may sign for the next map: the winners only (user 2026-11-02: "winners sign"), everyone
-- when there is no winner or no player on the winning side (`winnersPresent` false).
function Cutscenes.maySign(side: Side?, winner: Side?, winnersPresent: boolean): boolean
	if not winner or not winnersPresent then
		return true
	end
	return side == winner
end

-- The vote's offer: the frontline maps in `keys` that are built (`built[key]`), the live one first, at most `max`.
function Cutscenes.offer(keys: { string }, built: { [string]: boolean }, live: string, max: number): { string }
	local out = {}
	if built[live] then
		table.insert(out, live)
	end
	for _, k in keys do
		if #out >= max then
			break
		end
		if built[k] and k ~= live then
			table.insert(out, k)
		end
	end
	return out
end

-- Each offered map's votes from `votes` (voter -> map key; votes for a map not offered don't count).
function Cutscenes.tally(votes: { [any]: string }, offer: { string }): { [string]: number }
	local out: { [string]: number } = {}
	for _, k in offer do
		out[k] = 0
	end
	for _, k in votes do
		if out[k] then
			out[k] += 1
		end
	end
	return out
end

-- The map the vote picks: the most votes; a tie (no votes: all) picked at random by `r` (0..1) in the offer's order.
function Cutscenes.pick(tally: { [string]: number }, offer: { string }, r: number): string?
	local best, tied = -1, {}
	for _, k in offer do
		local n = tally[k] or 0
		if n > best then
			best, tied = n, { k }
		elseif n == best then
			table.insert(tied, k)
		end
	end
	if #tied == 0 then
		return nil
	end
	return tied[math.clamp(math.floor(r * #tied) + 1, 1, #tied)]
end

return Cutscenes
