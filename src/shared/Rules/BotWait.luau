--!strict
-- Where a bot waits instead of milling about (Config/Bots.Move.Wait; src/server/Bots think). User 2026-11-05 hand test:
-- "these bots seem to be stuck wondering what to do. it seems instead of standing idly, they just move in the same
-- spot. if they're going to think, at least have them do it in a trench or while they're providing fire".
-- - A bot with nothing to do where it is (engaging in the open, inside its zone, at its squad's stop, or getting no
--   nearer its goal) goes to a wait spot near where it should be: a fire step of its side's trenches facing the enemy,
--   a place in the support line, a dug trench square, or a hidden spot; none free, a spot stepped away from the
--   teammates crowding it. It holds there, firing at what it sees.
-- - A spot within `gap` studs of another soldier or another bot's wait spot is taken: crowds spread out.

local BotWait = {}

-- a place a bot could wait: where, what (Config/Bots.Move.Wait.weights' keys), the way it faces (fire steps)
export type Spot = { x: number, z: number, kind: string, fx: number?, fz: number? }
export type Point = { x: number, z: number }

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- Whether a spot at (x, z) is free: no point of `others` within `gap` studs of it, `me` (the bot's own spot, nil for
-- none) not counted.
function BotWait.free(x: number, z: number, others: { Point }, gap: number, me: Point?): boolean
	for _, o in others do
		if o ~= me and dist(x, z, o.x, o.z) < gap then
			return false
		end
	end
	return true
end

-- A spot's worth: its kind, nearer `from` better, a fire step facing the enemy's way (ex, ez: a flat direction, nil
-- unknown) better and one facing away worse. `w`: Config/Bots.Move.Wait.weights.
function BotWait.score(s: Spot, fromX: number, fromZ: number, ex: number?, ez: number?, w: any): number
	local v = (w[s.kind] or 0) - dist(s.x, s.z, fromX, fromZ) * w.distance
	if s.fx and s.fz and ex and ez then
		v += (s.fx * ex + s.fz * ez) * w.facing
	end
	return v
end

-- The best free spot of `spots` within `reach` studs of the anchor (ax, az), scored from the bot's place (px, pz);
-- its index, nil when none is free. `others`: the soldiers and claimed wait spots near (the bot itself left out).
function BotWait.pick(
	spots: { Spot },
	ax: number,
	az: number,
	reach: number,
	px: number,
	pz: number,
	ex: number?,
	ez: number?,
	others: { Point },
	cfg: any
): number?
	local order = {}
	for i, s in spots do
		if dist(s.x, s.z, ax, az) <= reach then
			table.insert(order, { i = i, v = BotWait.score(s, px, pz, ex, ez, cfg.weights) })
		end
	end
	table.sort(order, function(a, b)
		return a.v > b.v
	end)
	for _, o in order do
		local s = spots[o.i]
		if BotWait.free(s.x, s.z, others, cfg.gap) then
			return o.i
		end
	end
	return nil
end

-- A spot stepped away from the teammates crowding (px, pz) (`others` within `gap`), `step` studs from where it stands,
-- kept within `reach` of the anchor (ax, az): nil when nobody crowds it (it stays where it is). `roll` 0..1 picks the
-- way when the crowd stands evenly round it.
function BotWait.spread(
	px: number,
	pz: number,
	ax: number,
	az: number,
	reach: number,
	others: { Point },
	gap: number,
	step: number,
	roll: number
): (number?, number?)
	local sx, sz, n = 0, 0, 0
	for _, o in others do
		local d = dist(px, pz, o.x, o.z)
		if d < gap then
			n += 1
			if d > 1e-3 then
				-- (the nearer, the harder the push)
				sx += (px - o.x) / d * (gap - d)
				sz += (pz - o.z) / d * (gap - d)
			end
		end
	end
	if n == 0 then
		return nil, nil
	end
	local m = math.sqrt(sx * sx + sz * sz)
	if m < 1e-3 then
		local a = roll * 2 * math.pi
		sx, sz, m = math.cos(a), math.sin(a), 1
	end
	local x, z = px + sx / m * step, pz + sz / m * step
	local d = dist(x, z, ax, az)
	if d > reach and d > 1e-3 then
		x, z = ax + (x - ax) / d * reach, az + (z - az) / d * reach
	end
	return x, z
end

-- A bot's progress toward its goal (`p`: { key: the goal it tracks, best: its nearest yet, at: when it got there }),
-- one think at `d` studs from goal `key`: true once it has got no `cfg.gain` studs nearer for `cfg.stall` seconds (a
-- path that stops short, a way blocked). A new goal starts it afresh.
function BotWait.stalled(
	p: { key: Point?, best: number, at: number },
	key: Point,
	d: number,
	now: number,
	cfg: any
): boolean
	if not p.key or dist(p.key.x, p.key.z, key.x, key.z) > cfg.gain then
		p.key, p.best, p.at = key, d, now
		return false
	end
	if d < p.best - cfg.gain then
		p.best, p.at = d, now
		return false
	end
	return now - p.at >= cfg.stall
end

-- How many of `points` stand in a clump: each with at least `count` others within `within` studs.
function BotWait.clumped(points: { Point }, within: number, count: number): number
	local n = 0
	for i, a in points do
		local k = 0
		for j, b in points do
			if i ~= j and dist(a.x, a.z, b.x, b.z) < within then
				k += 1
			end
		end
		if k >= count then
			n += 1
		end
	end
	return n
end

return BotWait
