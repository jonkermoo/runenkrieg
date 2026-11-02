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

-- The sector a side holds nearest the enemy (Map 1 runs west to east: West's easternmost, East's westernmost), or nil.
function BotBuild.front(sectors: { { x: number } }, owner: { string }, side: string): number?
	local best, bestX = nil, nil
	for i, s in sectors do
		if owner[i] == side then
			if bestX == nil or (side == "West" and s.x > bestX) or (side ~= "West" and s.x < bestX) then
				best, bestX = i, s.x
			end
		end
	end
	return best
end

-- The Engineers' build list at its side's front `zone`, the enemy's way in along (tx, tz) (a flat unit): a sandbag pile
-- in front of each outdoor hold spot with no cover (the first `bags.max`), wire across the approaches out past the edge, an MG nest at the hold spot nearest the enemy, and the
-- guns `guns` names (the keys the artillery level opens) behind the zone.
function BotBuild.plan(zone: Zone, tx: number, tz: number, holds: { Hold }, guns: { string }, cfg: any): { Job }
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
	local best, bestDot = nil, -math.huge
	for _, h in holds do
		local dot = (h.x - zone.x) * tx + (h.z - zone.z) * tz
		if dot > bestDot then
			best, bestDot = h, dot
		end
	end
	if best then
		local N = cfg.Nest
		table.insert(jobs, { key = "MGNest", x = best.x + tx * N.ahead, z = best.z + tz * N.ahead, fx = tx, fz = tz })
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
	for _, w in want do
		local made = 0
		for _, back in cfg.back do
			for _, off in cfg.across do
				if made >= w.count then
					break
				end
				local d = zone.radius + back
				local x, z = zone.x - tx * d + ax * off, zone.z - tz * d + az * off
				local clear = true
				for _, j in jobs do
					local gap = math.max(spacing[w.key] or 0, spacing[j.key] or 0)
					if (j.x - x) ^ 2 + (j.z - z) ^ 2 < gap * gap then
						clear = false
						break
					end
				end
				if clear and fits(w.key, x, z) then
					table.insert(jobs, { key = w.key, x = x, z = z, fx = tx, fz = tz })
					made += 1
				end
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

return BotBuild
