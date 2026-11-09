--!strict
-- Bots on the guns (Config/Bots.Crew; user 2026-11-02, stage 2g): who walks to which free gun, what a field gun or
-- howitzer shells, when it holds fire for its own side, and an MG's bursts. Pure: the server (src/server/Bots/Crew)
-- mans, lays and fires through src/server/Artillery's manAs / aimAtAs / fireAs / triggerAs.

local BotCrew = {}

export type Spot = { x: number, z: number }
export type Gun = { x: number, z: number, idle: boolean? } -- `idle`: an MG with no known enemy in reach (BotCrew.inReach)
-- `crew`: an Engineer on gun duty (Config/Bots.Build.Crews); `busyOnly`: just left a gun that couldn't reach, no idle gun
export type Gunner = { x: number, z: number, crew: boolean, busyOnly: boolean? }
export type Group = { x: number, z: number, n: number }

-- Each free gun's gunner: the nearest bot within `cfg.walk` studs, an Engineer on gun duty counted `cfg.crewFirst`
-- studs nearer, nearest pairs first, at most `room` pairs, every gun that isn't `idle` before any that is. Returns gun
-- index -> gunner index.
function BotCrew.assign(
	guns: { Gun },
	gunners: { Gunner },
	room: number,
	cfg: { walk: number, crewFirst: number }
): { [number]: number }
	local pairs = {}
	for gi, g in guns do
		for bi, b in gunners do
			local d = math.sqrt((g.x - b.x) ^ 2 + (g.z - b.z) ^ 2)
			if d <= cfg.walk and not (g.idle and b.busyOnly) then
				table.insert(
					pairs,
					{ gi = gi, bi = bi, idle = g.idle == true, score = d - (if b.crew then cfg.crewFirst else 0) }
				)
			end
		end
	end
	table.sort(pairs, function(a, b)
		if a.idle ~= b.idle then
			return b.idle
		end
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.gi < b.gi
	end)
	local out, used = {}, {}
	local n = 0
	for _, p in pairs do
		if n >= room then
			break
		end
		if out[p.gi] == nil and not used[p.bi] then
			out[p.gi] = p.bi
			used[p.bi] = true
			n += 1
		end
	end
	return out
end

-- Whether any of `spots` is `min` to `reach` studs from (`x`, `z`): an MG there has something to fire at
function BotCrew.inReach(x: number, z: number, spots: { Spot }, min: number, reach: number): boolean
	for _, s in spots do
		local d2 = (s.x - x) ^ 2 + (s.z - z) ^ 2
		if d2 >= min * min and d2 <= reach * reach then
			return true
		end
	end
	return false
end

-- Whether a gunner whose MG last had something to fire at `idleFor` s ago gets off it (Config/Bots.Crew.MG `leave`)
function BotCrew.leaves(idleFor: number, after: number): boolean
	return idleFor >= after
end

-- The pieces to swing at, in order (user 2026-11-03: a gun is operated down to half its HP; the bots fix one below that
-- before manning it): every built gun on its side's ground (`held`) under `keep`% of its HP first, however far from the
-- front, then `near` (the usual repairs near the front) not listed already. Also which of them are such fixes.
export type Fixable = { gun: boolean, built: boolean, held: boolean, hp: number, max: number }
function BotCrew.repairOrder(pieces: { Fixable }, near: { number }, keep: number): ({ number }, { [number]: boolean })
	local out, fix = {}, {}
	for i, p in pieces do
		if p.gun and p.built and p.held and p.max > 0 and p.hp / p.max * 100 < keep - 1e-6 then
			table.insert(out, i)
			fix[i] = true
		end
	end
	for _, i in near do
		if not fix[i] then
			table.insert(out, i)
		end
	end
	return out, fix
end

-- What a side does with a gun the enemy built on ground it now holds (Config/Bots.Crew `captured`; user 2026-11-03:
-- "if artys left by enemies in a captured sector is usable and in a safe spot, we will use those. if not, we will build
-- more"): "use" (manned like its own, and counted against its sector's guns, src/server/Bots/Commander) when its shot
-- at the enemy is `clear` and it stands `safe` (BotCrew.safeSpot); else "wreck" (Engineers' Destroy swings; user:
-- "Wreck them all").
function BotCrew.captured(clear: boolean, safe: boolean): string
	return if clear and safe then "use" else "wreck"
end

-- Whether a gun at (`x`, `z`) stands safe for its side (Config/Bots.Crew.captured `safe`): no enemy it knows of
-- (`enemies`, each { x, z }) within `threat` studs, and no more than `ahead` studs past the middle (`mx`, `mz`) of the
-- sector it stands in toward the enemy (`tx`, `tz`, a flat unit): not out on the front edge facing the enemy's line.
function BotCrew.safeSpot(
	x: number,
	z: number,
	mx: number,
	mz: number,
	tx: number,
	tz: number,
	enemies: { { x: number, z: number } },
	cfg: { threat: number, ahead: number }
): boolean
	if (x - mx) * tx + (z - mz) * tz > cfg.ahead then
		return false
	end
	for _, e in enemies do
		if (e.x - x) ^ 2 + (e.z - z) ^ 2 < cfg.threat * cfg.threat then
			return false
		end
	end
	return true
end

-- The sector (index into `sectors`) nearest (`x`, `z`): whose ground a gun stands on
function BotCrew.sectorAt(x: number, z: number, sectors: { { x: number, z: number } }): number?
	local best, bestD = nil, math.huge
	for i, s in sectors do
		local d = (s.x - x) ^ 2 + (s.z - z) ^ 2
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Known enemies in groups (user: "Known enemy groups, else sector"): the spot with the most others within `cluster`
-- studs first, its members taken out, then the next. Each group's middle and size, biggest first.
function BotCrew.groups(points: { Spot }, cluster: number): { Group }
	local left = table.clone(points)
	local out = {}
	while #left > 0 do
		local best, bestN = 1, -1
		for i, p in left do
			local n = 0
			for _, q in left do
				if (p.x - q.x) ^ 2 + (p.z - q.z) ^ 2 <= cluster * cluster then
					n += 1
				end
			end
			if n > bestN then
				best, bestN = i, n
			end
		end
		local c = left[best]
		local sx, sz, n = 0, 0, 0
		for i = #left, 1, -1 do
			local q = left[i]
			if (c.x - q.x) ^ 2 + (c.z - q.z) ^ 2 <= cluster * cluster then
				sx += q.x
				sz += q.z
				n += 1
				table.remove(left, i)
			end
		end
		table.insert(out, { x = sx / n, z = sz / n, n = n })
	end
	return out
end

-- Whether a shell landing at `x`, `z` is clear of every one of `friends` (user: "hold near own"): none within
-- `radius` studs
function BotCrew.clear(x: number, z: number, friends: { Spot }, radius: number): boolean
	for _, f in friends do
		if (f.x - x) ^ 2 + (f.z - z) ^ 2 <= radius * radius then
			return false
		end
	end
	return true
end

-- The radius a gun holds fire within for its own side: `cfg.big` for a shell of `cfg.bigKg` kg or more (the
-- howitzer), else `cfg.small`
function BotCrew.danger(kg: number, cfg: { small: number, big: number, bigKg: number }): number
	return if kg >= cfg.bigKg then cfg.big else cfg.small
end

-- A shot at a sector (no group known) spread about its middle: within `radius` studs, evenly over the disc (`u1`,
-- `u2` uniform in [0, 1))
function BotCrew.scatter(x: number, z: number, radius: number, u1: number, u2: number): (number, number)
	local r = radius * math.sqrt(u1)
	local a = u2 * 2 * math.pi
	return x + math.cos(a) * r, z + math.sin(a) * r
end

-- An MG's trigger `t` seconds into its firing at a target: held `cfg.on` seconds, let go `cfg.off`, again
function BotCrew.burst(t: number, cfg: { on: number, off: number }): boolean
	return t >= 0 and t % (cfg.on + cfg.off) < cfg.on
end

-- An MG's sweep `t` seconds in: degrees off the middle of its area, there and back, `half` each way every `period` s
function BotCrew.sweep(t: number, cfg: { half: number, period: number }): number
	local u = (t / cfg.period) % 1
	local wave = if u < 0.25 then u * 4 elseif u < 0.75 then 2 - u * 4 else u * 4 - 4
	return wave * cfg.half
end

-- Whether a line of fire from (`ax`, `az`) through (`bx`, `bz`), run on to `past` times the way, is clear of every one of
-- `friends` by `clear` studs (no own soldier in an MG's area fire: Config/Bots.Crew.MG)
function BotCrew.lineClear(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	friends: { Spot },
	clear: number,
	past: number
): boolean
	local dx, dz = (bx - ax) * past, (bz - az) * past
	local len2 = dx * dx + dz * dz
	for _, f in friends do
		local t = if len2 > 0 then math.clamp(((f.x - ax) * dx + (f.z - az) * dz) / len2, 0, 1) else 0
		if (ax + dx * t - f.x) ^ 2 + (az + dz * t - f.z) ^ 2 <= clear * clear then
			return false
		end
	end
	return true
end

-- The order to shell its known enemy groups (`groups`, biggest first; their indices): those in the open before those
-- within `within` studs of one of the enemy's dug trench squares (`dug`), each kept in its order (user 2026-11-04, the
-- trench priority: "most fights end up being artillery"; Config/Bots.Crew.trench)
function BotCrew.openFirst(groups: { Spot }, dug: { Spot }, within: number): { number }
	local open, dugIn = {}, {}
	for i, g in groups do
		local inTrench = false
		for _, s in dug do
			if (s.x - g.x) ^ 2 + (s.z - g.z) ^ 2 <= within * within then
				inTrench = true
				break
			end
		end
		table.insert(if inTrench then dugIn else open, i)
	end
	for _, i in dugIn do
		table.insert(open, i)
	end
	return open
end

return BotCrew
