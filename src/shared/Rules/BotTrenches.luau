--!strict
-- Normal bots and trenches (Config/Bots.Trenches; user 2026-11-02: "bots that arent engineers should build trenches
-- too. they should follow real strategy and tactics and have their own advanced trench behavior"): the trench system
-- a side digs at a held zone, laid out as WW1 lines were (scaled to the map), and the picks for fighting from it.
-- Pure: the server (src/server/Bots) plans and digs the runs through src/server/Build's planAs / workAs.

local BotTrenches = {}

-- A straight run to plan (Build.planAs from A to B): "Fire", "Support" or "Comm"
export type Run = { kind: string, ax: number, az: number, bx: number, bz: number }

export type Zone = { x: number, z: number, radius: number }

-- The system at `zone`, the enemy's way in along (tx, tz) (a flat unit), in the order it is dug:
-- - Fire: across the zone's enemy-facing edge (`Fire.edge` of its radius out), `Fire.width` wide in `Fire.bays` runs
--   joined end to end, every other joint `Fire.traverse` studs toward the enemy: bays and traverses, so no shell burst
--   or gunner in it sweeps the whole line;
-- - Support: a straight line `Support.back` studs behind the fire trench's rear joints, `Support.width` wide;
-- - Comm: a communication trench from the support line's middle up to the fire trench's, in two runs jogging
--   `Comm.jog` studs across at half way (a zig-zag, no straight line of sight down it).
-- `fireOnly`: the fire trench alone.
function BotTrenches.layout(zone: Zone, tx: number, tz: number, cfg: any, fireOnly: boolean?): { Run }
	local ax, az = -tz, tx -- (across: right angles to the way in)
	local F = cfg.Fire
	local ex, ez = zone.x + tx * zone.radius * F.edge, zone.z + tz * zone.radius * F.edge
	local runs: { Run } = {}
	local seg = F.width / F.bays
	local function at(i: number): (number, number)
		local along = -F.width / 2 + i * seg
		local fwd = if i % 2 == 1 then F.traverse else 0
		return ex + ax * along + tx * fwd, ez + az * along + tz * fwd
	end
	for i = 0, F.bays - 1 do
		local x1, z1 = at(i)
		local x2, z2 = at(i + 1)
		table.insert(runs, { kind = "Fire", ax = x1, az = z1, bx = x2, bz = z2 })
	end
	if fireOnly then
		return runs
	end
	local S = cfg.Support
	local sx, sz = ex - tx * S.back, ez - tz * S.back
	table.insert(runs, {
		kind = "Support",
		ax = sx - ax * S.width / 2,
		az = sz - az * S.width / 2,
		bx = sx + ax * S.width / 2,
		bz = sz + az * S.width / 2,
	})
	-- (the fire trench's middle: on the run across `along` 0)
	local mid = F.width / 2 / seg
	local i = math.floor(mid)
	local x1, z1 = at(i)
	local x2, z2 = at(math.min(i + 1, F.bays))
	local t = mid - i
	local fx, fz = x1 + (x2 - x1) * t, z1 + (z2 - z1) * t
	local C = cfg.Comm
	local jx, jz = (sx + fx) / 2 + ax * C.jog, (sz + fz) / 2 + az * C.jog
	-- (it stops `C.short` studs off each line: the planner tees it into their sides)
	local function toward(px: number, pz: number, qx: number, qz: number, by: number): (number, number)
		local dx, dz = qx - px, qz - pz
		local len = math.sqrt(dx * dx + dz * dz)
		return px + dx / len * by, pz + dz / len * by
	end
	local s0x, s0z = toward(sx, sz, jx, jz, C.short)
	local f0x, f0z = toward(fx, fz, jx, jz, C.short)
	table.insert(runs, { kind = "Comm", ax = s0x, az = s0z, bx = jx, bz = jz })
	table.insert(runs, { kind = "Comm", ax = jx, az = jz, bx = f0x, bz = f0z })
	return runs
end

-- The middle of a system's fire trench (its runs from layout or forward): the middle of its middle bay
function BotTrenches.fireMid(runs: { Run }): { x: number, z: number }
	local fire = {}
	for _, r in runs do
		if r.kind == "Fire" then
			table.insert(fire, r)
		end
	end
	local r = fire[math.max(math.ceil(#fire / 2), 1)]
	if not r then
		return { x = 0, z = 0 }
	end
	return { x = (r.ax + r.bx) / 2, z = (r.az + r.bz) / 2 }
end

-- A forward line (Config/Bots.Trenches.Forward): a fire trench across (ux, uz) at `at`, as layout's (`Fire` bays and
-- traverses), then a communication trench from the last line's fire trench middle `from` up to its middle, stopping
-- `Comm.short` studs off each (the planner tees it into their sides)
function BotTrenches.forward(
	from: { x: number, z: number },
	at: { x: number, z: number },
	ux: number,
	uz: number,
	cfg: any
): { Run }
	local runs = BotTrenches.layout({ x = at.x, z = at.z, radius = 0 }, ux, uz, cfg, true)
	local mid = BotTrenches.fireMid(runs)
	local dx, dz = mid.x - from.x, mid.z - from.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len > 2 * cfg.Comm.short then
		local sx, sz = dx / len * cfg.Comm.short, dz / len * cfg.Comm.short
		table.insert(runs, { kind = "Comm", ax = from.x + sx, az = from.z + sz, bx = mid.x - sx, bz = mid.z - sz })
	end
	return runs
end

-- How far (px, pz) lies from the segment A-B, and where along it (0 at A, 1 at B; outside 0..1 past an end).
function BotTrenches.offRun(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then ((px - ax) * dx + (pz - az) * dz) / len2 else 0
	local c = math.clamp(t, 0, 1)
	return math.sqrt((px - (ax + dx * c)) ^ 2 + (pz - (az + dz * c)) ^ 2), t
end

-- The square (an index into `squares`, flat points) that shows `run` was planned: one lying on its line (within
-- `within`) in its middle part (`ends` of its length off each end, where the runs it joins lie), or nil.
function BotTrenches.laid(run: Run, squares: { { x: number, z: number } }, within: number, ends: number): number?
	for i, s in squares do
		local d, t = BotTrenches.offRun(s.x, s.z, run.ax, run.az, run.bx, run.bz)
		if d <= within and t >= ends and t <= 1 - ends then
			return i
		end
	end
	return nil
end

-- The real free end of a run A-B as it was laid (Config/Bots.Trenches.Chain): of `ends` (the free ends of its side's
-- squares, flat points), those within `off` studs of its line and no further than `past` of its length beyond B, the
-- one furthest along it; nil when none (nothing of it laid yet). The next run starts there, so the planner joins it
-- (a run starting anywhere else near a trench is refused "Too close to another trench").
function BotTrenches.lastEnd(
	ends: { { x: number, z: number } },
	ax: number,
	az: number,
	bx: number,
	bz: number,
	off: number,
	past: number
): { x: number, z: number }?
	local best, bestT = nil, -math.huge
	for _, e in ends do
		local d, t = BotTrenches.offRun(e.x, e.z, ax, az, bx, bz)
		if d <= off and t <= 1 + past and t > bestT then
			best, bestT = e, t
		end
	end
	return best
end

-- How many pioneers a side wants (Config/Bots.Trenches.pioneers, More): `base`, one more for each `per` squares it has
-- planned and not dug yet, up to `max`.
function BotTrenches.pioneersWanted(base: number, undug: number, more: { per: number, max: number }): number
	return math.clamp(base + math.floor(undug / math.max(more.per, 1)), 0, math.max(more.max, base))
end

-- Whether run `k` of `runs` may be planned yet: every run before it planned (`laid`), so each one joins the last (a
-- run that joins nothing must keep Config/Build.Trench.spacing from every other trench, and the bays lie closer):
-- the fire trench bay by bay, then the support line, then the communication trench. The support line joins nothing and
-- lies `Support.back` behind, so it may be planned at once alongside the fire trench (`kinds`: each run's kind; user
-- 2026-11-04, the trench priority: one run open at a time left a side's diggers idle); the communication trench once
-- the support line and the fire bays up to the middle one are.
function BotTrenches.ready(laid: { [number]: boolean }, k: number, kinds: { string }?): boolean
	if kinds and kinds[k] == "Support" then
		return true
	end
	-- (a communication run once the support line, its own runs before it and the fire bays up to the middle one, which
	-- it tees into (fireMid), are planned: dug alongside the fire trench's far bays, 2026-11-04 throughput)
	if kinds and kinds[k] == "Comm" then
		local fires = 0
		for i = 1, #kinds do
			fires += if kinds[i] == "Fire" then 1 else 0
		end
		local need, seen = math.ceil(fires / 2), 0
		for i = 1, k - 1 do
			local kind = kinds[i]
			if kind == "Fire" then
				seen += 1
			end
			if not laid[i] and (kind ~= "Fire" or seen <= need) then
				return false
			end
		end
		return true
	end
	for i = 1, k - 1 do
		if not laid[i] then
			return false
		end
	end
	return true
end

-- Where a refused run's far end B goes (the ground, something in the way, too near another trench): `tries` (1, 2,
-- ...) steps of `step` at right angles to the run, one way then the other; its start A stays where it joins the last
-- run.
function BotTrenches.swing(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	tries: number,
	step: number
): (number, number)
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return bx, bz
	end
	local k = math.ceil(tries / 2) * (if tries % 2 == 1 then 1 else -1)
	return bx - dz / len * step * k, bz + dx / len * step * k
end

-- How far from a trench square's line its fire step is: `rise` studs up its forward wall from the floor's edge (the
-- trench's `floor` half width, its walls at `angle` degrees: Config/Build.Trench), so the step follows the trench's
-- shape.
function BotTrenches.stepOut(floor: number, angle: number, rise: number): number
	return floor + rise / math.tan(math.rad(angle))
end

-- A dug trench square: its ground line's ends A and B, and its ground's rise per stud across to its right (its "Tilt":
-- src/server/Trenches turns its whole cross-section by it, Rules/Build.tiltedCut)
export type Square = { ax: number, ay: number, az: number, bx: number, by: number, bz: number, tilt: number }

-- A fire-trench square's post facing the enemy's way (tx, tz): its fire step on the wall at right angles to its line on
-- the enemy's side, `step` studs out (stepOut) and `rise` up from its floor `depth` under the line, in the square's own
-- tilted frame, so a bot there has its eyes just over that wall's parapet on any slope; the floor in its middle below,
-- `fill` studs up off the full floor as the square is buried (Rules/Build.trenchSink); the flat way out (ox, oz).
export type FirePost =
	{ sx: number, sy: number, sz: number, fx: number, fy: number, fz: number, ox: number, oz: number }

function BotTrenches.firePost(
	sq: Square,
	tx: number,
	tz: number,
	step: number,
	rise: number,
	depth: number,
	fill: number
): FirePost
	local dx, dz = sq.bx - sq.ax, sq.bz - sq.az
	local len = math.sqrt(dx * dx + dz * dz)
	-- (its right, src/server/Trenches' `across`; a square with no length faces the enemy straight)
	local rx, rz = if len > 1e-6 then -dz / len else tx, if len > 1e-6 then dx / len else tz
	local side = if rx * tx + rz * tz >= 0 then 1 else -1
	local mx, my, mz = (sq.ax + sq.bx) / 2, (sq.ay + sq.by) / 2, (sq.az + sq.bz) / 2
	-- a point `w` across (to its right) and `d` up in the square's frame: w c - d t c across, w t c + d c up
	local t = sq.tilt
	local c = 1 / math.sqrt(1 + t * t)
	local w, d = side * step, rise - depth
	local v = (w - d * t) * c
	return {
		sx = mx + rx * v,
		sy = my + (w * t + d) * c,
		sz = mz + rz * v,
		fx = mx + rx * (depth - fill) * t * c,
		fy = my - (depth - fill) * c,
		fz = mz + rz * (depth - fill) * t * c,
		ox = rx * side,
		oz = rz * side,
	}
end

-- Whether a bot is a digger: half of a holding squad digs (`share`), the rest stand guard (user 2026-11-02: "Half dig,
-- half guard"); `idx` its place in the squad (1-based) of `count`.
function BotTrenches.digs(idx: number, count: number, share: number): boolean
	return idx <= math.max(1, math.floor(count * share + 0.5))
end

-- Whether a fire trench is lost: `inside` enemies known in or past it, and fewer than `keep` of its `held` holders
-- (`alive` of them) still standing.
function BotTrenches.overrun(inside: number, alive: number, held: number, keep: number): boolean
	return inside > 0 and (held == 0 or alive / held < keep)
end

-- Whether the reserve in the support line moves up to the fire step: an enemy known within `alarm` studs of the fire
-- trench.
function BotTrenches.standTo(nearest: number, alarm: number): boolean
	return nearest <= alarm
end

-- The trench square (an index) whose floor `p` is in: within `floor` studs of the square's middle, or nil.
function BotTrenches.inSquare(px: number, pz: number, squares: { { x: number, z: number } }, floor: number): number?
	local best, bestD = nil, floor
	for i, s in squares do
		local d = math.sqrt((s.x - px) ^ 2 + (s.z - pz) ^ 2)
		if d <= bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Whether a piece at (x, z), `half` studs from its middle to its corners, keeps off every trench line in `lines` (runs
-- planned or dug, and saps): `reach` studs (the trench's wall top and a margin) and its own `half` from each (user
-- 2026-11-02: "never have structures where trenches should be").
function BotTrenches.clearOf(x: number, z: number, half: number, lines: { Run }, reach: number): boolean
	for _, l in lines do
		if BotTrenches.offRun(x, z, l.ax, l.az, l.bx, l.bz) < reach + half then
			return false
		end
	end
	return true
end

-- What a digger does with a piece in a trench run's way (user 2026-11-02: "plan around structures, destroy them if
-- necessary"): "tear" it down (a small piece, `tear[key]`, the enemy's or a bot's), else "around" (the run swings
-- aside: a gun, a nest, a dugout, or a player's own piece).
function BotTrenches.blocker(key: string, own: boolean, byBot: boolean, tear: { [string]: boolean }): string
	return if tear[key] and (not own or byBot) then "tear" else "around"
end

-- Whether a bot at (x, z) knows there's danger (user 2026-11-02: "they should ideally use trenches to get around if
-- they know there's danger. if it's an open field with no enemies they should just walk"): shot at within `cfg.shot`
-- seconds (`sinceShot`), an enemy known (`known`: { x, z, at }) within `cfg.near` studs in the last `cfg.known`
-- seconds, a shell or grenade (`blasts`: { x, z, at }) within `cfg.blastNear` studs in the last `cfg.blast` seconds, or
-- its goal's sector `contested` (enemies in it).
function BotTrenches.danger(
	now: number,
	x: number,
	z: number,
	sinceShot: number,
	known: { { x: number, z: number, at: number } },
	blasts: { { x: number, z: number, at: number } },
	contested: boolean,
	cfg: { shot: number, known: number, near: number, blast: number, blastNear: number }
): boolean
	if contested or sinceShot <= cfg.shot then
		return true
	end
	for _, k in known do
		if now - k.at <= cfg.known and math.sqrt((k.x - x) ^ 2 + (k.z - z) ^ 2) <= cfg.near then
			return true
		end
	end
	for _, k in blasts do
		if now - k.at <= cfg.blast and math.sqrt((k.x - x) ^ 2 + (k.z - z) ^ 2) <= cfg.blastNear then
			return true
		end
	end
	return false
end

-- An attacking squad's jump-off trench (user 2026-11-02: "Yes, gather then go"): of its side's dug squares
-- (`squares`), the one nearest its objective (cx, cz) that lies outside the objective's zone (`radius`), no more than
-- `cfg.reach` studs past its edge, and at least `cfg.ahead` studs nearer it than the squad (mx, mz); nil if none.
function BotTrenches.jumpOff(
	squares: { { x: number, z: number } },
	mx: number,
	mz: number,
	cx: number,
	cz: number,
	radius: number,
	cfg: { reach: number, ahead: number }
): number?
	local here = math.sqrt((mx - cx) ^ 2 + (mz - cz) ^ 2)
	local best, bestD = nil, math.huge
	for i, s in squares do
		local d = math.sqrt((s.x - cx) ^ 2 + (s.z - cz) ^ 2)
		if d >= radius and d <= radius + cfg.reach and d <= here - cfg.ahead and d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Whether a squad gathered in its jump-off trench goes over the top: `cfg.gather` of its living members there, or
-- `cfg.wait` seconds since the first got there (no waiting for ever on a straggler).
function BotTrenches.overTop(
	there: number,
	living: number,
	since: number,
	cfg: { gather: number, wait: number }
): boolean
	return living > 0 and (there / living >= cfg.gather or since >= cfg.wait)
end

-- Whether a side's trenches are being shelled (user 2026-11-02, dugouts): a shell (a blast of `cfg.shell` kg or more,
-- not a grenade) within `cfg.near` studs of any of its trench squares (`squares`) in the last `cfg.recent` seconds.
function BotTrenches.shelled(
	now: number,
	blasts: { { x: number, z: number, at: number, kg: number } },
	squares: { { x: number, z: number } },
	cfg: { shell: number, near: number, recent: number }
): boolean
	for _, k in blasts do
		if k.kg >= cfg.shell and now - k.at <= cfg.recent then
			for _, s in squares do
				if math.sqrt((k.x - s.x) ^ 2 + (k.z - s.z) ^ 2) <= cfg.near then
					return true
				end
			end
		end
	end
	return false
end

-- How hot a spot (x, z) of `side`'s trenches is (user 2026-11-03: "make bots utilize dug outs more often, especially in
-- trenches highly contested or often shelled"; Config/Bots.Dugouts.Heat `cfg`): each shell (`events` kind "shell") and
-- each of the side's own deaths ("death", its `side`) within `cfg.radius` studs, its `cfg.weight` by kind from full at
-- the spot to `cfg.edge` of it at the radius, fading by e every `fade` seconds (`cfg.fade` unless given); and each
-- enemy known within `cfg.enemyNear` (`enemies`) `cfg.weight.enemy`, at most `cfg.enemyMost` in all. Returns the heat
-- and its shells', deaths' and enemies' shares.
export type HeatEvent = { x: number, z: number, at: number, kind: string, side: string? }
function BotTrenches.heat(
	now: number,
	x: number,
	z: number,
	side: string,
	events: { HeatEvent },
	enemies: { { x: number, z: number } },
	cfg: any,
	fade: number?
): (number, number, number, number)
	local f = fade or cfg.fade
	local shells, deaths = 0, 0
	for _, e in events do
		local age = now - e.at
		if age >= 0 and (e.kind == "shell" or (e.kind == "death" and e.side == side)) then
			local d = math.sqrt((e.x - x) ^ 2 + (e.z - z) ^ 2)
			if d <= cfg.radius then
				local v = cfg.weight[e.kind] * (1 - (1 - cfg.edge) * d / cfg.radius) * math.exp(-age / f)
				if e.kind == "shell" then
					shells += v
				else
					deaths += v
				end
			end
		end
	end
	local near = 0
	for _, k in enemies do
		if math.sqrt((k.x - x) ^ 2 + (k.z - z) ^ 2) <= cfg.enemyNear then
			near += 1
		end
	end
	local foes = math.min(near * cfg.weight.enemy, cfg.enemyMost)
	return shells + deaths + foes, shells, deaths, foes
end

-- Whether a holder shelters in a dugout at `heat` (BotTrenches.heat; Config/Bots.Dugouts.Heat `cfg`), and why: down
-- once it reaches `cfg.enter`, unless it is resting (up again after a stay, to fight); once down (`inside`) it stays
-- while the heat is `cfg.leave` or more, but never `cfg.stay` seconds (`stayed`) at a time: "stay" is up to fight for
-- `cfg.rest` before it may go down again ("They still need to come back out and fight").
function BotTrenches.shelter(
	inside: boolean,
	heat: number,
	stayed: number,
	resting: boolean,
	cfg: any
): (boolean, string)
	if inside then
		if stayed >= cfg.stay then
			return false, "stay"
		end
		return heat >= cfg.leave, if heat >= cfg.leave then "hot" else "calm"
	end
	if resting then
		return false, "resting"
	end
	return heat >= cfg.enter, if heat >= cfg.enter then "hot" else "calm"
end

-- Why a holder went down, for the admin readout: the heat and what made it
function BotTrenches.heatWhy(heat: number, shells: number, deaths: number, foes: number): string
	local parts = {}
	if shells > 0.05 then
		table.insert(parts, string.format("shells %.1f", shells))
	end
	if deaths > 0.05 then
		table.insert(parts, string.format("deaths %.1f", deaths))
	end
	if foes > 0.05 then
		table.insert(parts, string.format("enemies %.1f", foes))
	end
	return string.format("heat %.1f", heat) .. (if #parts > 0 then ` ({table.concat(parts, ", ")})` else "")
end

-- How many dugouts a side wants (user 2026-11-02: "whenever they need one but dont make bots abuse it"): none until its
-- trenches have been shelled or fought over (Config/Bots.Dugouts.Heat.build), then room (`cfg.room` each) for its holders but its sentries ("1 per fire bay", one
-- each of `bays`).
function BotTrenches.dugoutsWanted(shelledOnce: boolean, holders: number, bays: number, cfg: { room: number }): number
	if not shelledOnce then
		return 0
	end
	return math.ceil(math.max(holders - bays, 0) / cfg.room)
end

-- Where a side's next dugouts go: up to `want` of its support line's squares (`squares`, each dug `share` of its HP,
-- `len` studs long on the flat), dug to `cfg.dug` or more, at least `long` studs long (a dugout's width and its spare:
-- Config/Build.Dugout), `cfg.spacing` studs (centre to centre) from every dugout it has (`have`) and from each other,
-- the hottest first (each square's `heat`, BotTrenches.heat over the side's memory: often shelled or fought over),
-- then the nearest to the line's middle. Returns indices into `squares`.
function BotTrenches.dugoutSquares(
	squares: { { x: number, z: number, share: number, len: number, heat: number? } },
	have: { { x: number, z: number } },
	want: number,
	cfg: { dug: number, spacing: number },
	long: number
): { number }
	local mx, mz, n = 0, 0, 0
	for _, s in squares do
		mx, mz, n = mx + s.x, mz + s.z, n + 1
	end
	if n == 0 or want <= 0 then
		return {}
	end
	mx, mz = mx / n, mz / n
	local order = {}
	for i, s in squares do
		if s.share >= cfg.dug and s.len >= long then
			table.insert(order, i)
		end
	end
	table.sort(order, function(a, b)
		local sa, sb = squares[a], squares[b]
		local ha, hb = sa.heat or 0, sb.heat or 0
		if math.abs(ha - hb) > 1e-6 then
			return ha > hb
		end
		return (sa.x - mx) ^ 2 + (sa.z - mz) ^ 2 < (sb.x - mx) ^ 2 + (sb.z - mz) ^ 2
	end)
	local taken = table.clone(have)
	local out = {}
	for _, i in order do
		if #out >= want then
			break
		end
		local s = squares[i]
		local free = true
		for _, h in taken do
			if math.sqrt((h.x - s.x) ^ 2 + (h.z - s.z) ^ 2) < cfg.spacing then
				free = false
				break
			end
		end
		if free then
			table.insert(out, i)
			table.insert(taken, { x = s.x, z = s.z })
		end
	end
	return out
end

-- The dugout a holder shelters in: of `rooms` (each with `free` places left), the nearest to (px, pz) with a place;
-- nil if none.
function BotTrenches.seat(rooms: { { x: number, z: number, free: number } }, px: number, pz: number): number?
	local best, bestD = nil, math.huge
	for i, r in rooms do
		local d = (r.x - px) ^ 2 + (r.z - pz) ^ 2
		if r.free > 0 and d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Whether a holder at an open post (x, z) digs a foxhole there (user 2026-11-02: "Holding before trench"): no dug own
-- trench square (`squares`) within `cfg.trench` studs and no foxhole (`holes`) within `cfg.apart`.
function BotTrenches.foxholeWanted(
	x: number,
	z: number,
	squares: { { x: number, z: number } },
	holes: { { x: number, z: number } },
	cfg: { trench: number, apart: number }
): boolean
	for _, s in squares do
		if math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2) <= cfg.trench then
			return false
		end
	end
	for _, h in holes do
		if math.sqrt((h.x - x) ^ 2 + (h.z - z) ^ 2) <= cfg.apart then
			return false
		end
	end
	return true
end

-- Whether an enemy dugout's room (its floor's middle `room`) has someone in it its attackers know of (user 2026-11-02,
-- bombing out dugouts): a known enemy (`known`) within `cfg.inside` studs of it across and below the trench floor
-- (`floorY`).
function BotTrenches.occupied(
	known: { { x: number, y: number, z: number } },
	room: { x: number, z: number },
	floorY: number,
	cfg: { inside: number }
): boolean
	for _, k in known do
		if k.y < floorY and math.sqrt((k.x - room.x) ^ 2 + (k.z - room.z) ^ 2) <= cfg.inside then
			return true
		end
	end
	return false
end

-- Why a run dug from A toward B lies in the line of fire of a threat at (x, y, z) (user 2026-11-03 play test: "building
-- straight down will be in line of fire of the enemies uphill"; Config/Bots.Trenches.Zigzag): "in line" with the
-- threat within `cfg.cone` degrees of the run's line, ahead of it; "from above" with it `cfg.plunge` degrees or more up
-- from the run's start (ground `groundY`); nil while it can't look down the run. The server checks the threat can see
-- the ground there at all (a ray over the terrain).
function BotTrenches.exposed(
	run: Run,
	groundY: number,
	threat: { x: number, y: number, z: number },
	cfg: { cone: number, plunge: number }
): string?
	local dx, dz = run.bx - run.ax, run.bz - run.az
	local tx, tz = threat.x - run.ax, threat.z - run.az
	local dl, tl = math.sqrt(dx * dx + dz * dz), math.sqrt(tx * tx + tz * tz)
	if dl < 1e-6 or tl < 1e-6 then
		return nil
	end
	local cos = (dx * tx + dz * tz) / (dl * tl)
	if cos >= math.cos(math.rad(cfg.cone)) then
		return "in line"
	end
	if cos > 0 and math.deg(math.atan((threat.y - groundY) / tl)) >= cfg.plunge then
		return "from above"
	end
	return nil
end

-- The turn off a run's line for each zig-zag leg against a threat `height` studs above it (Config/Bots.Trenches.Zigzag
-- `angle`): steeper the higher it stands. Degrees.
function BotTrenches.zigAngle(height: number, cfg: { min: number, perStud: number, max: number }): number
	return math.clamp(cfg.min + math.max(height, 0) * cfg.perStud, cfg.min, cfg.max)
end

-- A run from A to B dug as a zig-zag: legs `leg` studs long, each turned `angle` degrees off the line to B, one way
-- then the other, the last straight onto B (each leg's line ends off the next one's: no straight sight down it). The
-- legs, of the run's kind.
function BotTrenches.zigzag(run: Run, angle: number, leg: number): { Run }
	local dx, dz = run.bx - run.ax, run.bz - run.az
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-6 or leg <= 0 then
		return { run }
	end
	local ux, uz = dx / d, dz / d
	local cx, cz = -uz, ux -- (across)
	local a = math.rad(angle)
	local fwd, side = math.cos(a) * leg, math.sin(a) * leg
	local legs: { Run } = {}
	local px, pz, done, sign = run.ax, run.az, 0, 1
	while d - done > fwd + 1e-6 do
		local nx = px + ux * fwd + cx * side * sign
		local nz = pz + uz * fwd + cz * side * sign
		table.insert(legs, { kind = run.kind, ax = px, az = pz, bx = nx, bz = nz })
		px, pz, done = nx, nz, done + fwd
		sign = -sign
	end
	table.insert(legs, { kind = run.kind, ax = px, az = pz, bx = run.bx, bz = run.bz })
	return legs
end

-- How a soldier at (px, pz) died, for the trench stats (Config/Bots.Trenches.Stats `cfg`): in a dug trench square
-- (`squares`, any side's: inSquare within `cfg.floor`), and by a shell (`blasts`: { x, z, at, kg }, one of `shell` kg or
-- more within `cfg.shellNear` studs in the last `cfg.shellAge` seconds before `now`)
function BotTrenches.deathKind(
	px: number,
	pz: number,
	now: number,
	squares: { { x: number, z: number } },
	blasts: { { x: number, z: number, at: number, kg: number } },
	shell: number,
	cfg: any
): (boolean, boolean)
	local byShell = false
	for _, b in blasts do
		if
			b.kg >= shell
			and now - b.at <= cfg.shellAge
			and math.sqrt((b.x - px) ^ 2 + (b.z - pz) ^ 2) <= cfg.shellNear
		then
			byShell = true
		end
	end
	return BotTrenches.inSquare(px, pz, squares, cfg.floor) ~= nil, byShell
end

return BotTrenches
