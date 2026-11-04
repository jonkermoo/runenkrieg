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

-- First person (the command post, Config/Cutscenes.View): the yaw and pitch (radians) of a look along (dx, dy, dz),
-- as CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) turns the -z look
function Cutscenes.aim(dx: number, dy: number, dz: number): (number, number)
	return math.atan2(-dx, -dz), math.atan2(dy, math.sqrt(dx * dx + dz * dz))
end

-- A head turn from yaw `a` to `b`, `k` (0..1) of the way: the short way round for `dir` 0, else to the left (`dir`
-- above 0, the yaw growing) or to the right (below 0) whatever the distance.
function Cutscenes.turn(a: number, b: number, k: number, dir: number): number
	local d = (b - a) % (2 * math.pi) -- 0 .. 2 pi: the turn to the left
	if dir < 0 or (dir == 0 and d > math.pi) then
		d -= 2 * math.pi
	end
	return a + d * k
end

-- Where the eyes rest at time `t` on `looks` (each { t1, look } held until its t1, the last held on): which look they
-- move to and how far (0..1, eased), a glance taking `glance` seconds from the previous look's t1. The first look is
-- there from the start.
function Cutscenes.glance(looks: { { t1: number } }, glance: number, t: number): (number, number)
	for i, l in looks do
		if t < l.t1 or i == #looks then
			if i == 1 then
				return 1, 1
			end
			return i, ease(math.clamp((t - looks[i - 1].t1) / glance, 0, 1))
		end
	end
	return 1, 1
end

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
-- `home`, the West's without one), Taken (for `winner`), Centre, Landmark (the map's first special building: its
-- headline one; else Centre).
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
	local first = map.village and map.village.specials and map.village.specials[1]
	out.Landmark = if first then { first.x, first.z } else out.Centre
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

-- Which of `n` points a "Sectors" shot shows `u` through it (each its equal share of the shot, west to east) and how
-- far through that point's own shot (0..1).
function Cutscenes.sector(u: number, n: number): (number, number)
	local s = math.clamp(u, 0, 1) * math.max(n, 1)
	local i = math.clamp(math.floor(s) + 1, 1, math.max(n, 1))
	return i, math.clamp(s - (i - 1), 0, 1)
end

-- A "Sectors" shot's own shot at point `i`: its styles taken in turn (a point with no landmark, `bare`, its
-- `bareStyles`: the flag on its rise), their anchors "S" and "Mark" named for that point (S3, Mark3), their orbits
-- turned `turn` radians a point on; the whole shot turned round its anchor by `spins[i]` radians when given.
function Cutscenes.sectorShot(shot: any, i: number, bare: boolean?): any
	local styles = if bare and shot.bareStyles then shot.bareStyles else shot.styles
	local style = styles[(i - 1) % #styles + 1]
	local out = table.clone(style)
	local function named(key: any): any
		if type(key) ~= "table" then
			return key
		end
		local k = table.clone(key)
		if k.at == "S" or k.at == "Mark" then
			k.at = `{k.at}{i}`
		end
		return k
	end
	out.from, out.to, out.look, out.lookTo = named(style.from), named(style.to), named(style.look), named(style.lookTo)
	if type(style.at) == "string" and (style.at == "S" or style.at == "Mark") then
		out.at = `{style.at}{i}`
	end
	if out.kind == "Orbit" then
		local spin = (shot.turn or 0) * (i - 1)
		out.from, out.to = style.from + spin, style.to + spin
	end
	-- turned further round the point by `spins[i]` radians (the client's: a view the trees don't block)
	local spin = shot.spins and shot.spins[i] or 0
	if spin ~= 0 then
		if out.kind == "Orbit" then
			out.from, out.to = out.from + spin, out.to + spin
		else
			local c, sn = math.cos(spin), math.sin(spin)
			local function turned(key: any): any
				if type(key) ~= "table" then
					return key
				end
				local k = table.clone(key)
				local dx, dz = k.dx or 0, k.dz or 0
				k.dx, k.dz = dx * c - dz * sn, dx * sn + dz * c
				return k
			end
			out.from, out.to, out.look, out.lookTo =
				turned(out.from), turned(out.to), turned(out.look), turned(out.lookTo)
		end
	end
	return out
end

-- Where the camera is and looks `u` through `shot` (Config/Cutscenes' kinds), on a map with these `anchors`, its
-- points `points` ({ { x, z } } west to east), `flip`ped east-west or not; `paperUp` the parked camera's height. An
-- "Self" shot's pose is over the viewer's spawn (Home: the client circles its own soldier, Cutscenes.selfPose).
function Cutscenes.pose(
	shot: any,
	u: number,
	anchors: { [string]: { number } },
	points: { { number } },
	flip: boolean,
	paperUp: number
): Pose
	if shot.kind == "Sectors" then
		local i, v = Cutscenes.sector(u, #points)
		local mark, point = anchors[`Mark{i}`], anchors[`S{i}`]
		local bare = mark ~= nil and point ~= nil and mark[1] == point[1] and mark[2] == point[2]
		return Cutscenes.pose(Cutscenes.sectorShot(shot, i, bare), v, anchors, points, false, paperUp)
	end
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
			fov = shot.fov,
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
	elseif shot.kind == "Self" then
		local h = anchors.Home or { 0, 0 }
		return {
			eye = { x = h[1] - (shot.radius or 0), z = h[2], up = shot.up },
			look = { x = h[1], z = h[2], up = 0 },
			roll = 0,
			fov = shot.fov,
		}
	end
	local k = ease(u)
	local eye = mix(place(shot.from, anchors, flip), place(shot.to or shot.from, anchors, flip), k)
	local look = place(shot.look, anchors, flip)
	if shot.lookTo then
		look = mix(look, place(shot.lookTo, anchors, flip), k)
	end
	return { eye = eye, look = look, roll = roll, fov = shot.fov }
end

-- A "Self" shot `u` through: the camera's angle round the local soldier (radians from straight behind it, `from` ->
-- `to`) and how far it has blended into the soldier's own view (0..1: over the shot's last `into` share).
function Cutscenes.selfPose(shot: any, u: number): (number, number)
	local a = shot.from + (shot.to - shot.from) * ease(u)
	local into = shot.into or 0
	local blend = if into > 0 then math.clamp((u - (1 - into)) / into, 0, 1) else 0
	return a, ease(blend)
end

-- How many of the `n` point seals are stamped `u` through a `stamps` shot: the Front's as the camera comes within half
-- the way to each point (the first at once, the last before the shot ends, so it's seen), any other's one after
-- another over the shot.
function Cutscenes.stamped(shot: any, u: number, n: number): number
	if shot.kind == "Sectors" then
		return (Cutscenes.sector(u, n)) -- (each point's seal as its own shot cuts in)
	elseif shot.kind == "Front" then
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
-- flight opens, one as the camera comes up on each point (its Front or Sectors shot), then the closing call (by the player's own kit `own`, nil: no
-- call) as the camera goes into the soldier's eyes. A map without a plan gets only the call.
function Cutscenes.partTwo(speech: any, cut: any, own: string?, nextMap: string, n: number): { Line }
	local out: { Line } = {}
	local plan = speech.plans[nextMap]
	local starts: { [string]: number } = {}
	local front, frontT0 = nil, 0
	for i, s in cut.shots do
		starts[s.kind] = starts[s.kind] or Cutscenes.start(cut, i)
		if (s.kind == "Front" or s.kind == "Sectors") and not front then
			front, frontT0 = s, Cutscenes.start(cut, i)
		end
	end
	if plan then
		if plan[1] then
			table.insert(out, { text = plan[1], at = 0 })
		end
		for i = 1, n do
			local line = plan[i + 1]
			if line then
				local at = if front then Cutscenes.orderTime(front, frontT0, i, n) else 0
				table.insert(out, { text = line, at = at })
			end
		end
	end
	local close = own and speech.close[own]
	if close then
		table.insert(out, { text = close, at = Cutscenes.length(cut) }) -- (on the whistle)
	end
	return out
end

-- How long one line takes: its recorded clip's length (`clips`: Config/NarratorClips.clips, by text), else its words at
-- `wps` words a second.
function Cutscenes.lineSeconds(text: string, wps: number, clips: { [string]: { number } }?): number
	local clip = clips and clips[text]
	if clip then
		return clip[2]
	end
	local _, words = string.gsub(text, "%S+", "")
	return words / wps
end

-- About how long `lines` take spoken one after another (Cutscenes.lineSeconds each), `gap` between lines.
function Cutscenes.speechSeconds(lines: { Line }, wps: number, gap: number, clips: { [string]: { number } }?): number
	local total = 0
	for k, l in lines do
		total += Cutscenes.lineSeconds(l.text, wps, clips) + (if k > 1 then gap else 0)
	end
	return total
end

-- Every line the narrator can say, each once, sorted: the won lines filled with each of `nations`, the no-winner
-- lines, the momentum lines, every plan's lines and the closing calls (for recording them, and checking each has a clip).
function Cutscenes.allLines(speech: any, nations: { string }): { string }
	local seen: { [string]: boolean } = {}
	for _, template in speech.won do
		for _, nation in nations do
			seen[Cutscenes.text(template, { winner = nation })] = true
		end
	end
	for _, group in { speech.wonNone, speech.momentum, speech.close } do
		for _, line in group do
			seen[line] = true
		end
	end
	for _, plan in speech.plans do
		for _, line in plan do
			seen[line] = true
		end
	end
	local out = {}
	for line in seen do
		table.insert(out, line)
	end
	table.sort(out)
	return out
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

-- The command post's Field kit (Config/Cutscenes Table / Board, user 2026-11-03) ---------------------------------------

-- The point a side's block rests at: its front, the West's last held point going east, the East's first; nil when
-- it holds none (`owners` west to east: "West" / "East" / anything else for nobody).
function Cutscenes.frontPoint(owners: { string }, side: Side): number?
	local found: number? = nil
	for i, o in owners do
		if o == side then
			if side == "East" then
				return i
			end
			found = i
		end
	end
	return found
end

-- The order the red string runs to: the one with the most signatures when no other has as many; on a tie, or with
-- none signed, the last leader (`last`, nil before anyone has led).
function Cutscenes.leader(counts: { number }, last: number?): number?
	local best, at, tied = 0, nil :: number?, false
	for i, n in counts do
		if n > best then
			best, at, tied = n, i, false
		elseif n == best and n > 0 then
			tied = true
		end
	end
	return if at and not tied then at else last
end

-- The stopwatch's hand for `left` of `total` seconds: degrees round from the top, clockwise as we see the dial (the
-- full time at the top, the last seconds just past it).
function Cutscenes.watchAngle(left: number, total: number): number
	return math.clamp(left / math.max(total, 1e-6), 0, 1) * 360
end

-- Past the end and back: `u` (0..1) of a slide that overshoots a little before it settles.
function Cutscenes.overshoot(u: number): number
	local c = 1.70158
	local v = math.clamp(u, 0, 1) - 1
	return 1 + (c + 1) * v * v * v + c * v * v
end

-- A losing order's swing on its one pin `u` seconds after it lets go (degrees; Config/Cutscenes.Board.lose): a swing
-- dying away round a rest a little off straight.
function Cutscenes.swing(lose: any, u: number): number
	if u <= 0 then
		return 0
	end
	return lose.swing * math.exp(-lose.decay * u) * math.sin(lose.rate * u)
		+ lose.rest * math.clamp(u / lose.settle, 0, 1)
end

-- Whether a signature for map `key` counts from a player who has signed `signed` (nil: not yet): a vote can't be taken
-- back (user 2026-11-03), so only the first, and only for a map on `offer`.
function Cutscenes.signs(signed: string?, key: string, offer: { string }): boolean
	return signed == nil and table.find(offer, key) ~= nil
end

-- The after-action report's typed lines with `top` soldiers listed (src/client/CommandPost.report: the map, the
-- winner, its line, the length, "TOP SOLDIERS", the columns' heads, the soldiers, your line, your points).
function Cutscenes.reportLines(top: number): number
	return 8 + top
end

-- The table's replay span for `captures` (the ones it draws: Config/Results.Replay.most at most): `every` seconds
-- between captures from `lead`, `tail` after the last, no longer than `most` (Config/Cutscenes.Table.replay).
function Cutscenes.replaySeconds(replay: any, captures: number): number
	local span = replay.lead + math.max(captures - 1, 0) * replay.every + replay.tail
	return math.min(span, replay.most)
end

-- How long the war table plays (Config/Cutscenes.Table; user 2026-11-03: turn to the board once the replay and the
-- report are both done, never before, never long after): the replay's last arrow drawn (and, with a winner, the
-- loser's piece toppled), the report typed and ticked, then `hold`; at least `least`, at most `most`.
function Cutscenes.tableSeconds(T: any, captures: number, lines: number, won: boolean): number
	local R = T.replay
	local replay = 0
	if captures > 0 then
		replay = Cutscenes.replaySeconds(R, captures) - R.tail + R.draw
		if won then
			replay += T.blocks.back + T.topple.after + T.topple.fall
		end
	end
	local report = T.typing.lead + lines * T.typing.type + T.tick.after + T.tick.draw
	return math.clamp(math.max(replay, report) + T.hold, T.least, T.most)
end

-- How black the screen is at server time `now` round a dip to black that's full at `at` (Config/Cutscenes.Dip):
-- darkening over `out` before it, held `hold`, clearing over `inn` (0 clear, 1 black; no dip: 0).
function Cutscenes.dip(now: number, at: number?, d: any): number
	if not at then
		return 0
	end
	if now < at then
		return 1 - math.clamp((at - now) / d.out, 0, 1)
	end
	return 1 - math.clamp((now - at - d.hold) / d.inn, 0, 1)
end

-- The countdown after a match: the flight's `length` plus the black `d.hold` the dip into it (Config/Cutscenes.FlightDip)
-- keeps before it, so the flight starts as the black clears and plays whole to the whistle.
function Cutscenes.flightSeconds(length: number, d: any): number
	return length + d.hold
end

-- The losing piece's topple `u` seconds in (Config/Cutscenes.Table.topple): degrees off upright, falling faster and
-- faster to `rest` (lying on its side) over `fall` seconds, then a small bounce dying away.
function Cutscenes.topple(t: any, u: number, rest: number): number
	if u <= 0 then
		return 0
	elseif u < t.fall then
		local k = u / t.fall
		return rest * k * k
	end
	local v = u - t.fall
	return rest - t.bounce * math.abs(math.sin(v * t.rate)) * math.exp(-t.decay * v)
end

-- Whether the armory may give way to the next match `elapsed` seconds in: past `least` (the narrator's first part)
-- with no player still loading the next map (`pending`), or at `most` whatever is still loading.
function Cutscenes.loadOver(elapsed: number, least: number, most: number, pending: number): boolean
	return elapsed >= most or (elapsed >= least and pending <= 0)
end

-- The loading ring's share (0..1): the narrator's share of the armory's least time (`spoken`) and the next map's share
-- streamed in (`loaded`), whichever is behind; short of full (`most`) until both are done.
function Cutscenes.loadRing(spoken: number, loaded: number, most: number): number
	if spoken >= 1 and loaded >= 1 then
		return 1
	end
	return math.clamp(math.min(spoken, loaded), 0, most)
end

return Cutscenes
