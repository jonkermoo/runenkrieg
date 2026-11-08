--!strict
-- Normal bots building (Config/Bots.Build; user 2026-11-02): each side's build list at its front (its trenches:
-- Rules/BotTrenches), which job a bot
-- takes, and the share of the team's caps the bots may use. Pure: the server (src/server/Bots) lays and works the
-- pieces through src/server/Build's placeAs / planAs / workAs, with the players' checks.

local BotBuild = {}

-- A job: a piece to lay at (x, z) facing (fx, fz) (a flat unit, toward the enemy), a trench planned from (x, z) to
-- (ex, ez), or (`work`) a piece standing there wanting Build swings (dug, built up or repaired).
export type Job = {
	key: string, -- a Config/Build.Pieces key ("Trench" for a trench line or square)
	x: number,
	z: number,
	fx: number,
	fz: number,
	ex: number?, -- a trench line's far end
	ez: number?,
	work: boolean?,
}

export type Zone = { x: number, z: number, radius: number }
export type Hold = { x: number, z: number, hidden: boolean }
export type Piece = { key: string, x: number, z: number, left: number }

-- The sector a side holds nearest the enemy along the map's sector chain (West's home is sector 1, East's the last:
-- West's highest it holds, East's lowest), or nil.
function BotBuild.front(sectors: { any }, owner: { string }, side: string): number?
	local best = nil
	for i in sectors do
		if owner[i] == side and (best == nil or (if side == "West" then i > best else i < best)) then
			best = i
		end
	end
	return best
end

-- The enemy's way at sector `i` for `side` (a flat unit (tx, tz)), taken from the map's sector chain (any map, any
-- heading): toward the next sector on the enemy's side, else (at the chain's end) on from the one before; West goes
-- up the chain, East down it. (1, 0) / (-1, 0) when the chain gives no heading.
function BotBuild.toward(sectors: { { x: number, z: number } }, i: number, side: string): (number, number)
	local step = if side == "West" then 1 else -1
	local a, b = sectors[i], sectors[i + step]
	if not b then
		a, b = sectors[i - step], sectors[i]
	end
	if a and b then
		local dx, dz = b.x - a.x, b.z - a.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 1e-6 then
			return dx / d, dz / d
		end
	end
	return step, 0
end

-- The Engineers' build list at its side's front `zone`, the enemy's way in along (tx, tz) (a flat unit): a sandbag pile
-- in front of each outdoor hold spot with no cover (the first `bags.max`), wire across the approaches out past the
-- edge, MG nests ahead of the `nests` hold spots nearest the enemy (default `cfg.Nest.count`: those missing, user
-- 2026-11-03: "3 mg nests if there arent built"), and the guns `guns` names (the keys its side may build) behind the
-- zone.
function BotBuild.plan(
	zone: Zone,
	tx: number,
	tz: number,
	holds: { Hold },
	guns: { string },
	cfg: any,
	nests: number?
): { Job }
	local jobs: { Job } = {}
	-- across: the line at right angles to the way in
	local ax, az = -tz, tx
	local B = cfg.Bags
	local bagged = 0
	for _, h in holds do
		if not h.hidden and bagged < B.max then
			bagged += 1
			table.insert(
				jobs,
				{ key = "SandbagPile", x = h.x + tx * B.ahead, z = h.z + tz * B.ahead, fx = tx, fz = tz }
			)
		end
	end
	local Wr = cfg.Wire
	local out = zone.radius + Wr.out
	for _, off in Wr.lanes do
		table.insert(jobs, {
			key = "Wire",
			x = zone.x + tx * out + ax * off,
			z = zone.z + tz * out + az * off,
			fx = tx,
			fz = tz,
		})
	end
	local N = cfg.Nest
	local order = table.clone(holds)
	table.sort(order, function(a, b)
		return (a.x - zone.x) * tx + (a.z - zone.z) * tz > (b.x - zone.x) * tx + (b.z - zone.z) * tz
	end)
	-- (every `cfg.Flank.every`-th at the hold spot farthest across: a flank; Config/Bots.Front)
	local every = cfg.Flank and cfg.Flank.every
	local used: { [Hold]: boolean } = {}
	for k = 1, math.min(nests or N.count, #order) do
		local h: Hold? = nil
		if every and k % every == 0 then
			local far = -1
			for _, o in order do
				local across = math.abs((o.x - zone.x) * ax + (o.z - zone.z) * az)
				if not used[o] and across > far then
					h, far = o, across
				end
			end
		end
		if not h then
			for _, o in order do
				if not used[o] then
					h = o
					break
				end
			end
		end
		local hh = h :: Hold
		used[hh] = true
		table.insert(jobs, { key = "MGNest", x = hh.x + tx * N.ahead, z = hh.z + tz * N.ahead, fx = tx, fz = tz })
	end
	local G = cfg.Guns
	for k, key in guns do
		local side = (k - (#guns + 1) / 2) * G.side
		table.insert(jobs, {
			key = key,
			x = zone.x - tx * G.back + ax * side,
			z = zone.z - tz * G.back + az * side,
			fx = tx,
			fz = tz,
		})
	end
	return jobs
end

-- Whether one more of a side's bots should go Engineer for its guns (Config/Bots.Build.Crews): fewer than `enough`
-- guns stand and fewer than `max` of its bots are on gun duty already.
function BotBuild.crewWanted(standing: number, crews: number, cfg: any): boolean
	return standing < cfg.enough and crews < cfg.max
end

-- The bots' gun spots behind a front `zone`, the enemy's way in along (tx, tz) (Config/Bots.Build.Crews): for each
-- { key, count } in `want` (in order), candidates `back` studs behind the zone's edge by `across` studs either side of
-- its middle, farthest back first; a spot is kept where `fits(key, x, z)` and it is `spacing[key]` (the larger of the
-- two keys') from every spot kept. Lay jobs facing the enemy; fewer than asked where none fits.
function BotBuild.gunSpots(
	zone: Zone,
	tx: number,
	tz: number,
	want: { { key: string, count: number } },
	cfg: any,
	spacing: { [string]: number },
	fits: (string, number, number) -> boolean
): { Job }
	local ax, az = -tz, tx
	local jobs: { Job } = {}
	-- (every `flank.every`-th spot at least `flank.gunFrom` studs across, shelling the front from an angle, where one
	-- fits: Config/Bots.Front.Flank)
	local flank = cfg.flank
	local function place(key: string, wide: boolean): boolean
		for _, back in cfg.back do
			for _, off in cfg.across do
				if wide and math.abs(off) < flank.gunFrom then
					continue
				end
				local d = zone.radius + back
				local x, z = zone.x - tx * d + ax * off, zone.z - tz * d + az * off
				local clear = true
				for _, j in jobs do
					local gap = math.max(spacing[key] or 0, spacing[j.key] or 0)
					if (j.x - x) ^ 2 + (j.z - z) ^ 2 < gap * gap then
						clear = false
						break
					end
				end
				if clear and fits(key, x, z) then
					table.insert(jobs, { key = key, x = x, z = z, fx = tx, fz = tz })
					return true
				end
			end
		end
		return false
	end
	for _, w in want do
		for _ = 1, w.count do
			local wide = flank ~= nil and (#jobs + 1) % flank.every == 0
			if not (wide and place(w.key, true)) and not place(w.key, false) then
				break
			end
		end
	end
	return jobs
end

-- Whether the bots may lay one more `key`: their team's bot-laid pieces under `caps.pieces` (a third of the team's,
-- user 2026-11-02) and, for a key `caps` names (the guns: half of each), under that.
function BotBuild.allowed(key: string, pieces: number, ofKey: number, caps: { [string]: number }): boolean
	if pieces >= caps.pieces then
		return false
	end
	local cap = caps[key]
	return cap == nil or ofKey < cap
end

-- For each lay job, the piece of its key standing within `within` of its spot (an index into `pieces`), or nil: the
-- job is laid already (then worked while it wants swings, done once it doesn't).
function BotBuild.match(jobs: { Job }, pieces: { Piece }, within: number): { [number]: number }
	local out: { [number]: number } = {}
	local used: { [number]: boolean } = {}
	for j, job in jobs do
		if not job.work then
			-- (a trench line: any square near its middle)
			local x = if job.ex then (job.x + (job.ex :: number)) / 2 else job.x
			local z = if job.ez then (job.z + (job.ez :: number)) / 2 else job.z
			local reach = if job.ex then within + math.sqrt((job.x - x) ^ 2 + (job.z - z) ^ 2) else within
			local best, bestD = nil, reach * reach
			for i, p in pieces do
				local d = (p.x - x) ^ 2 + (p.z - z) ^ 2
				if p.key == job.key and not used[i] and d <= bestD then
					best, bestD = i, d
				end
			end
			if best then
				out[j] = best
				if not job.ex then
					used[best] = true
				end
			end
		end
	end
	return out
end

-- The pieces (indexes) within `reach` of the zone that want swings, nearest the zone first, at most `count`.
function BotBuild.repairs(pieces: { Piece }, zone: Zone, reach: number, count: number): { number }
	local list: { { i: number, d: number } } = {}
	local r = zone.radius + reach
	for i, p in pieces do
		local d = (p.x - zone.x) ^ 2 + (p.z - zone.z) ^ 2
		if p.left > 0 and d <= r * r then
			table.insert(list, { i = i, d = d })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for k = 1, math.min(count, #list) do
		out[k] = list[k].i
	end
	return out
end

-- The job a bot at (x, z) takes: the nearest within `within` not taken (`taken[j]`) or waiting (`waiting[j]`); a
-- helper (not an Engineer) only work jobs of the keys `helps` names. Nil if none.
function BotBuild.pick(
	jobs: { Job },
	x: number,
	z: number,
	within: number,
	taken: { [number]: boolean },
	waiting: { [number]: boolean },
	helps: { [string]: boolean }?
): number?
	local best, bestD = nil, within * within
	for j, job in jobs do
		if not taken[j] and not waiting[j] and (helps == nil or (job.work and helps[job.key])) then
			local d = (job.x - x) ^ 2 + (job.z - z) ^ 2
			if d <= bestD then
				best, bestD = j, d
			end
		end
	end
	return best
end

-- Where a lay job's spot moves after a refusal (the ground, a piece in the way): `tries` (1, 2, ...) steps of `step`,
-- one way then the other: along the line across, or for a trench line (which runs across) back and forth along the
-- way in, back first.
function BotBuild.nudge(job: Job, tries: number, step: number): (number, number)
	local k = math.ceil(tries / 2) * (if tries % 2 == 1 then 1 else -1)
	if job.ex then
		return job.x - job.fx * step * k, job.z - job.fz * step * k
	end
	return job.x - job.fz * step * k, job.z + job.fx * step * k
end

-- A breastwork along the line A-B (a trench run the ground refused, user 2026-11-02: "Breastworks"): a lay job every
-- `step` studs along it, the keys taken in turn from `keys` (sandbag piles and barriers), facing (fx, fz).
function BotBuild.line(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	fx: number,
	fz: number,
	step: number,
	keys: { string }
): { Job }
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.floor(len / step + 0.5))
	local jobs: { Job } = {}
	for i = 0, n - 1 do
		local t = (i + 0.5) / n
		table.insert(jobs, { key = keys[i % #keys + 1], x = ax + dx * t, z = az + dz * t, fx = fx, fz = fz })
	end
	return jobs
end

-- A wall of `count` sandbag piles `ahead` studs on the enemy side (fx, fz) of a nest or gun at (x, z), `spread` studs
-- apart across (user 2026-11-02: "Walls round nest and gun").
function BotBuild.wall(
	x: number,
	z: number,
	fx: number,
	fz: number,
	ahead: number,
	spread: number,
	count: number
): { Job }
	local jobs: { Job } = {}
	for i = 1, count do
		local off = (i - (count + 1) / 2) * spread
		table.insert(jobs, {
			key = "SandbagPile",
			x = x + fx * ahead - fz * off,
			z = z + fz * ahead + fx * off,
			fx = fx,
			fz = fz,
		})
	end
	return jobs
end

-- Whether a bot is pinned in the open and lays a sandbag pile in front of itself (user 2026-11-02: "Pile under
-- fire"): shot at within `threat` seconds, at least `shaken` suppressed, no cover found or under way, not in a
-- trench, and its last such pile at least `every` seconds ago.
function BotBuild.pinned(
	sinceThreat: number,
	shaken: number,
	hasCover: boolean,
	inTrench: boolean,
	sinceLast: number,
	cfg: { threat: number, shaken: number, every: number }
): boolean
	return sinceThreat <= cfg.threat
		and shaken >= cfg.shaken
		and not hasCover
		and not inTrench
		and sinceLast >= cfg.every
end

-- Whether a bot seen in the open digs in where it stands (Config/Bots.Build.Exposed; user 2026-11-06: "just being
-- able to see an enemy is considered not safe"): seen from the open `exposedFor` s, `after` or more, no cover near, not
-- in a trench, not pressing on, and its last foxhole or pile `sinceLast` s ago, `every` or more
function BotBuild.exposedDig(
	exposedFor: number,
	hasCover: boolean,
	inTrench: boolean,
	pressing: boolean,
	sinceLast: number,
	cfg: { after: number, every: number }
): boolean
	return exposedFor >= cfg.after and not hasCover and not inTrench and not pressing and sinceLast >= cfg.every
end

-- how far (x, z) is from the segment (ax, az)-(bx, bz)
local function offSegment(x: number, z: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((x - ax) * dx + (z - az) * dz) / len2, 0, 1) else 0
	return math.sqrt((x - (ax + dx * t)) ^ 2 + (z - (az + dz * t)) ^ 2)
end

-- The trees (indexes into `trees`) in the way of a side's works (Config/Bots.Build.Trees; user 2026-11-03): within
-- `clear` studs of any of `ways` (segments: trench runs and squares, saps, a nest's or gun's spot as a point, a gun's
-- firing line), never one in a building, nearest its way first (then by index).
function BotBuild.treesInWay(
	trees: { { x: number, z: number, building: boolean? } },
	ways: { { ax: number, az: number, bx: number, bz: number } },
	clear: number
): { number }
	local list: { { i: number, d: number } } = {}
	for i, t in trees do
		if not t.building then
			local best = math.huge
			for _, w in ways do
				best = math.min(best, offSegment(t.x, t.z, w.ax, w.az, w.bx, w.bz))
			end
			if best <= clear then
				table.insert(list, { i = i, d = best })
			end
		end
	end
	table.sort(list, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.i < b.i
	end)
	local out = {}
	for k, e in list do
		out[k] = e.i
	end
	return out
end

-- A gun's firing line: from its spot (x, z) `length` studs along its facing (fx, fz).
function BotBuild.fireLine(
	x: number,
	z: number,
	fx: number,
	fz: number,
	length: number
): { ax: number, az: number, bx: number, bz: number }
	return { ax = x, az = z, bx = x + fx * length, bz = z + fz * length }
end

-- Whether an Engineer may fell one more tree (Config/Bots.Build.Trees): its side under `perSide` this match and its
-- own last at least `every` s ago (`sinceLast` nil: none yet).
function BotBuild.mayFell(felled: number, sinceLast: number?, cfg: { perSide: number, every: number }): boolean
	return felled < cfg.perSide and (sinceLast == nil or sinceLast >= cfg.every)
end

-- Where wire planned at (x, z) goes so it is only in the enemy's way (user 2026-11-02 hand test: "they should be very
-- safe as not to annoy real players. place where it would only be an inconvenience to enemies"): `cfg.gap` studs off
-- each of its own side's ways forward (`lines`: { ax, az, bx, bz }) and `cfg.spawn` off its spawn (`spawn`: a rect),
-- moved across (ux, uz) by `cfg.step` up to `cfg.shift` studs either way, the nearest first; nil, nil if nowhere.
function BotBuild.wireSpot(
	x: number,
	z: number,
	ux: number,
	uz: number,
	lines: { { ax: number, az: number, bx: number, bz: number } },
	spawn: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	cfg: { gap: number, spawn: number, step: number, shift: number }
): (number?, number?)
	local function clear(px: number, pz: number): boolean
		for _, l in lines do
			if offSegment(px, pz, l.ax, l.az, l.bx, l.bz) < cfg.gap then
				return false
			end
		end
		if spawn then
			local dx = math.max(spawn.minX - px, px - spawn.maxX, 0)
			local dz = math.max(spawn.minZ - pz, pz - spawn.maxZ, 0)
			if math.sqrt(dx * dx + dz * dz) < cfg.spawn then
				return false
			end
		end
		return true
	end
	local k = 0
	while k * cfg.step <= cfg.shift do
		for _, sign in (if k == 0 then { 1 } else { 1, -1 }) do
			local px, pz = x + ux * k * cfg.step * sign, z + uz * k * cfg.step * sign
			if clear(px, pz) then
				return px, pz
			end
		end
		k += 1
	end
	return nil, nil
end

-- Whether bots may swing at a piece of theirs that lost HP `since` seconds ago (user 2026-11-02 hand test: "Dont let
-- ai repair structures that are being destroyed by players. if players start destroying and stop, have a timer before
-- friendly AI repairs it"): `wait` seconds after it last lost any.
function BotBuild.mayRepair(since: number, wait: number): boolean
	return since >= wait
end

-- Whether a bot with an enemy within a butt stroke's reach strikes (user 2026-11-02: "allow AI to melee (dont force
-- them to just because are withing range)", "Sometimes"): a roll (`roll` 0..1) under `cfg.chance`, `cfg.empty` with
-- its gun empty or loading.
function BotBuild.strikes(empty: boolean, roll: number, cfg: { chance: number, empty: number }): boolean
	return roll < (if empty then cfg.empty else cfg.chance)
end

-- Whether a bot at its build job's spot may put its gun away and work (user 2026-11-03 play test: "they should always
-- be ready to shoot and fight until they know they are safe to work on trench"): its own foxhole or pile dug pinned
-- down (`underFire`: that is the point of it); else no enemy in sight, and either nothing shot at it or hurt it for
-- `calm` seconds or the spot is hidden from where the last threat came from (`hidden`).
-- A bot on its way to its build job: its best (nearest) distance so far and when it got there, now that it is `dist`
-- off; and whether it has got no `gain` studs nearer for `stall` s (no way there: it leaves the job to others).
-- `fighting`: it fights on the way, not stuck (the clock starts again).
function BotBuild.stalled(
	dist: number,
	best: number?,
	bestAt: number,
	now: number,
	fighting: boolean,
	cfg: { stall: number, gain: number }
): (number, number, boolean)
	if best == nil or dist < best - cfg.gain or fighting then
		return math.min(dist, best or dist), now, false
	end
	return best, bestAt, now - bestAt >= cfg.stall
end

function BotBuild.safeToWork(
	underFire: boolean,
	seen: boolean,
	sinceThreat: number,
	sinceHurt: number,
	hidden: boolean,
	calm: number
): boolean
	if underFire then
		return true
	end
	if seen then
		return false
	end
	return (sinceThreat >= calm and sinceHurt >= calm) or hidden
end

return BotBuild
