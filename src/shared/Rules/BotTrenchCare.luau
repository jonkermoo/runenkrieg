--!strict
-- Normal bots looking after their trenches (Config/Bots.Trenches.Care; user 2026-11-05: "trenches still end up getting
-- destroyed before they get anywhere ... most soldiers trench in the open or already highly conflicted areas ... have
-- some logical thinking for whether a trench should be repaired ... start, build, reinforce, then keep going"): the
-- shell map lines are sited by, freshly shelled ground, what each dug square is worth repairing, the gate before the
-- next forward line, and the separate trench networks worth joining.
-- Pure: the server (src/server/Bots/Commander) reads the world and acts on these.

local Care = {}

-- The shell map: where shells landed and a side's own soldiers died over the whole match, by `cfg.cell`-stud cell,
-- each cell's weight fading by half every `cfg.half` seconds
export type Cell = { v: number, t: number }
export type ShellMap = { [string]: Cell }

local function key(cx: number, cz: number): string
	return `{cx},{cz}`
end

-- the cell (x, z) lies in
function Care.cellOf(x: number, z: number, size: number): (number, number)
	return math.floor(x / size), math.floor(z / size)
end

local function faded(c: Cell, now: number, half: number): number
	return c.v * 0.5 ^ (math.max(now - c.t, 0) / half)
end

-- a shell or a death of weight `w` at (x, z)
function Care.note(map: ShellMap, x: number, z: number, w: number, now: number, cfg: any)
	local cx, cz = Care.cellOf(x, z, cfg.cell)
	local k = key(cx, cz)
	local c = map[k]
	if c then
		c.v, c.t = faded(c, now, cfg.half) + w, now
	else
		map[k] = { v = w, t = now }
	end
end

-- how hot the ground at (x, z) is: its cell's weight, and half each of its eight neighbours' (a shell near a cell's
-- edge counts across it)
function Care.heatAt(map: ShellMap, x: number, z: number, now: number, cfg: any): number
	local cx, cz = Care.cellOf(x, z, cfg.cell)
	local h = 0
	for dx = -1, 1 do
		for dz = -1, 1 do
			local c = map[key(cx + dx, cz + dz)]
			if c then
				h += faded(c, now, cfg.half) * (if dx == 0 and dz == 0 then 1 else 0.5)
			end
		end
	end
	return h
end

-- the points every `step` studs along a run A-B, both ends included
function Care.along(ax: number, az: number, bx: number, bz: number, step: number): { { x: number, z: number } }
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local n = math.max(math.ceil(len / step), 1)
	local out = {}
	for i = 0, n do
		local t = i / n
		table.insert(out, { x = ax + (bx - ax) * t, z = az + (bz - az) * t })
	end
	return out
end

-- Freshly shelled ground: a shell (`events` kind "shell") within `radius` studs of (x, z) in the last `seconds`
export type Event = { x: number, z: number, at: number, kind: string }
function Care.shelledNear(
	events: { Event },
	x: number,
	z: number,
	now: number,
	radius: number,
	seconds: number
): boolean
	for _, e in events do
		if e.kind == "shell" and now - e.at <= seconds and (e.x - x) ^ 2 + (e.z - z) ^ 2 <= radius * radius then
			return true
		end
	end
	return false
end

-- What one dug square is worth (Care.Score `cfg`):
-- - used: how busy it is, 0..1 (the bots in it lately, posts manned there included);
-- - safe: how near safe ground, 0..1 (1 at its side's base line or behind it, 0 `far` studs and more ahead of it);
-- - dugout: it holds a dugout or lies next to one; base: on a system's base (its support line or the way back);
-- - link: the only dug way of its system up to the fire trench; heat: the shell map's heat there;
-- - hot: shelled in the last Care.Hot.seconds.
export type SquareCare = {
	used: number,
	safe: number,
	dugout: boolean,
	base: boolean,
	link: boolean,
	heat: number,
	hot: boolean,
}

-- Its decision: "wait" (hot, not critical: looked at again later), "ignore", "patch" (to `stand` HP: usable again),
-- "fix" (to full) or "reinforce" (full, then the extra: 25, 50 or 75 by its score), and its score. A dugout's square
-- and a base square are critical: never less than "reinforce" (a base square nobody uses yet to the first sheet only).
-- `cfg.always`: every square "reinforce" to the full extra, but one out ahead (`safe` 0) that nobody uses and that isn't
-- critical or its system's only way up ("ignore"), and a hot one ("wait").
function Care.decide(s: SquareCare, cfg: any): (string, number)
	local W = cfg.w
	local score = W.used * math.min(s.used, 1)
		+ W.safe * s.safe
		+ (if s.dugout then W.dugout else 0)
		+ (if s.base then W.base else 0)
		+ (if s.link then W.link else 0)
		- W.heat * math.min(s.heat, cfg.heatMost)
	local critical = s.dugout or s.base
	if s.hot and not critical then
		return "wait", score
	elseif cfg.always then
		-- (every dug square reinforced but for a reason: shelled just now, above, or out ahead of its lines and nobody
		-- using it; the score only orders them; user 2026-11-06: "a built trench should now always be prioritized to be
		-- reinforced unless for a realistic reason")
		if not critical and not s.link and s.used <= 0 and s.safe <= 0 then
			return "ignore", score
		end
		return "reinforce", score
	elseif critical or score >= cfg.reinforce then
		return "reinforce", score
	elseif score >= cfg.fix then
		return "fix", score
	elseif score >= cfg.patch then
		return "patch", score
	end
	return "ignore", score
end

-- The HP and the extra a decision wants (`stand`: the HP a fire step stands at; `extra`: the most extra,
-- Config/Build.Trench.hp.extra; `steps`: the extra's steps, Care.Score.steps)
function Care.target(
	decision: string,
	score: number,
	s: SquareCare,
	max: number,
	stand: number,
	extra: number,
	cfg: any
): (number, number)
	if decision == "patch" then
		return stand, 0
	elseif decision == "fix" then
		return max, 0
	elseif decision ~= "reinforce" then
		return 0, 0
	end
	local step = extra / #cfg.steps
	if s.dugout or cfg.always then
		return max, extra
	end
	local n = 1
	for i, at in cfg.steps do
		if score >= at then
			n = i
		end
	end
	if s.base and s.used <= 0 then
		n = 1
	end
	return max, math.min(step * n, extra)
end

-- The gate before a system's next forward line (Care.Gate `cfg`): its fire trench planned, `dug` of its squares dug,
-- `share` of its base squares reinforced to `extra`, a dugout standing in it; or `wait` s since its fire trench was
-- planned (a line whose dugout the ground refuses, or whose base can't be held, goes on anyway). And why not, for the
-- admin readout.
export type GateState = {
	fireLaid: boolean,
	squares: number,
	dug: number,
	base: number,
	reinforced: number,
	dugout: boolean,
	since: number,
}
function Care.gate(g: GateState, cfg: any): (boolean, string)
	if not g.fireLaid then
		return false, "fire trench"
	elseif g.since >= cfg.wait then
		return true, "waited"
	elseif g.squares == 0 or g.dug < cfg.dug * g.squares then
		return false, "digging"
	elseif not g.dugout then
		return false, "dugout"
	elseif g.base > 0 and g.reinforced < cfg.share * g.base then
		return false, "reinforcing"
	end
	return true, "ready"
end

-- Separate trench networks: each segment's network (its index in `segs`, joined to any segment one of its ends lies
-- within `touch` studs of)
export type Seg = { ax: number, az: number, bx: number, bz: number }

local function offSeg(px: number, pz: number, s: Seg): (number, number, number)
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - s.ax) * dx + (pz - s.az) * dz) / len2, 0, 1) else 0
	local x, z = s.ax + dx * t, s.az + dz * t
	return math.sqrt((px - x) ^ 2 + (pz - z) ^ 2), x, z
end

function Care.networks(segs: { Seg }, touch: number): { number }
	local up: { number } = {}
	for i in segs do
		up[i] = i
	end
	local function root(i: number): number
		while up[i] ~= i do
			up[i] = up[up[i]]
			i = up[i]
		end
		return i
	end
	for i, a in segs do
		for j = i + 1, #segs do
			local b = segs[j]
			local near = (offSeg(a.ax, a.az, b)) <= touch
				or (offSeg(a.bx, a.bz, b)) <= touch
				or (offSeg(b.ax, b.az, a)) <= touch
				or (offSeg(b.bx, b.bz, a)) <= touch
			if near then
				up[root(i)] = root(j)
			end
		end
	end
	local out = {}
	for i in segs do
		out[i] = root(i)
	end
	return out
end

-- The run joining another network to the `main` one (Care.Join `cfg`): of the networks of at least `min` segments
-- (`net`, from networks), the end of one nearest the main network, if within `reach` studs and further than `touch`
-- (not joined already), to the nearest point of the main network's lines, stopping `short` studs off it (the planner
-- tees it into its side); `skip` the ends tried before (by `Care.endKey`). Nil if none.
function Care.endKey(x: number, z: number): string
	return `{math.floor(x + 0.5)},{math.floor(z + 0.5)}`
end

function Care.linkRun(segs: { Seg }, net: { number }, main: number, skip: { [string]: boolean }, cfg: any): Seg?
	local size: { [number]: number } = {}
	for _, n in net do
		size[n] = (size[n] or 0) + 1
	end
	local best: Seg?, bestD = nil, cfg.reach
	for i, s in segs do
		local n = net[i]
		if n ~= main and size[n] >= cfg.min then
			for _, e in { { x = s.ax, z = s.az }, { x = s.bx, z = s.bz } } do
				if not skip[Care.endKey(e.x, e.z)] then
					for j, m in segs do
						if net[j] == main then
							local d, x, z = offSeg(e.x, e.z, m)
							if d > cfg.touch and d <= bestD and d > cfg.short then
								local k = (d - cfg.short) / d
								best, bestD =
									{ ax = e.x, az = e.z, bx = e.x + (x - e.x) * k, bz = e.z + (z - e.z) * k }, d
							end
						end
					end
				end
			end
		end
	end
	return best
end

return Care
