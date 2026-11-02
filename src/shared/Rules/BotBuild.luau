--!strict
-- Normal bots building (Config/Bots.Build; user 2026-11-02): each side's build list at its front, which job a bot
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

-- The side's build list at its front `zone`, the enemy's way in along (tx, tz) (a flat unit): a trench line across
-- the zone's enemy-facing edge, a sandbag pile in front of each outdoor hold spot with no cover (the first
-- `bags.max`), wire across the approaches out past the edge, an MG nest at the hold spot nearest the enemy, and the
-- guns `guns` names (the keys the artillery level opens) behind the zone.
function BotBuild.plan(zone: Zone, tx: number, tz: number, holds: { Hold }, guns: { string }, cfg: any): { Job }
	local jobs: { Job } = {}
	-- across: the line at right angles to the way in
	local ax, az = -tz, tx
	local T = cfg.Trench
	local ex, ez = zone.x + tx * zone.radius * T.edge, zone.z + tz * zone.radius * T.edge
	local half = T.length / 2
	table.insert(jobs, {
		key = "Trench",
		x = ex - ax * half,
		z = ez - az * half,
		ex = ex + ax * half,
		ez = ez + az * half,
		fx = tx,
		fz = tz,
	})
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

return BotBuild
