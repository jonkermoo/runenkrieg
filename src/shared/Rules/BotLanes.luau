--!strict
-- Lanes across the front (Config/Bots.Lanes; user 2026-11-10: "can you make the bots just more spread out? ... still too
-- many are just in the center. it should be a almost even spread, with the area that needs most attention with more
-- bots accordingly to how desperate the situation is"). A sector's squads share `count` lanes over the map's width
-- across the enemy's way; each lane gets squads by its weight, more where its known enemies outnumber the side's bots
-- there. Plain numbers; src/server/Bots/Commander gives the lanes.

local BotLanes = {}

export type Frame = {
	ox: number, -- the line's middle (the sector's point moved along the enemy's way)
	oz: number,
	ax: number, -- across the enemy's way (a flat unit)
	az: number,
	centres: { number }, -- each lane's middle, studs across from (ox, oz)
	half: number, -- half a lane's width
}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

-- How far from (x, z) along (ux, uz) (a flat unit) stays inside `b` less `margin`, at most `cap` (0 when outside)
function BotLanes.reach(x: number, z: number, ux: number, uz: number, b: Bounds, margin: number, cap: number): number
	local t = cap
	local function limit(p: number, u: number, lo: number, hi: number)
		if u > 1e-9 then
			t = math.min(t, (hi - margin - p) / u)
		elseif u < -1e-9 then
			t = math.min(t, (lo + margin - p) / u)
		end
	end
	limit(x, ux, b.minX, b.maxX)
	limit(z, uz, b.minZ, b.maxZ)
	return math.max(t, 0)
end

-- The lanes at the sector point (cx, cz), the enemy's way (tx, tz) (a flat unit), the line `shift` studs along that
-- way (negative: back toward home): `cfg.count` lanes of one width over the map's width there (`bounds` less
-- `cfg.margin`, at most `cfg.reach` studs each way).
function BotLanes.frame(
	cx: number,
	cz: number,
	tx: number,
	tz: number,
	shift: number,
	bounds: Bounds,
	cfg: { count: number, reach: number, margin: number }
): Frame
	local ox, oz = cx + tx * shift, cz + tz * shift
	local ax, az = -tz, tx
	local left = BotLanes.reach(ox, oz, ax, az, bounds, cfg.margin, cfg.reach)
	local right = BotLanes.reach(ox, oz, -ax, -az, bounds, cfg.margin, cfg.reach)
	local n = math.max(cfg.count, 1)
	local w = (left + right) / n
	local centres = {}
	for k = 1, n do
		centres[k] = -right + (k - 0.5) * w
	end
	return { ox = ox, oz = oz, ax = ax, az = az, centres = centres, half = w / 2 }
end

-- How far across the line (x, z) stands (studs, + to the frame's `ax` side)
function BotLanes.offset(f: Frame, x: number, z: number): number
	return (x - f.ox) * f.ax + (z - f.oz) * f.az
end

-- The lane an offset falls in (the nearest middle)
function BotLanes.laneOf(f: Frame, off: number): number
	local best, bestD = 1, math.huge
	for k, c in f.centres do
		local d = math.abs(off - c)
		if d < bestD then
			best, bestD = k, d
		end
	end
	return best
end

-- Whether an offset lies in lane `k` (the outer lanes run on out past the map's edge)
function BotLanes.inLane(f: Frame, k: number, off: number): boolean
	local c = f.centres[k]
	if not c then
		return false
	end
	local lo = if k == 1 then -math.huge else c - f.half
	local hi = if k == #f.centres then math.huge else c + f.half
	return off >= lo and off <= hi
end

-- Lane `k`'s middle on the line, `extra` studs on along the enemy's way (tx, tz)
function BotLanes.point(f: Frame, k: number, tx: number, tz: number, extra: number): (number, number)
	local c = f.centres[k] or 0
	return f.ox + f.ax * c + tx * extra, f.oz + f.az * c + tz * extra
end

-- How far (x, z) stands from the line through the sector flags (the nearest leg between two neighbours; the readout)
function BotLanes.fromLine(sectors: { { x: number, z: number } }, x: number, z: number): number
	local best = math.huge
	if #sectors == 1 then
		return math.sqrt((x - sectors[1].x) ^ 2 + (z - sectors[1].z) ^ 2)
	end
	for i = 1, #sectors - 1 do
		local a, b = sectors[i], sectors[i + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local l2 = dx * dx + dz * dz
		local t = if l2 > 1e-9 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / l2, 0, 1) else 0
		best = math.min(best, math.sqrt((x - a.x - dx * t) ^ 2 + (z - a.z - dz * t) ^ 2))
	end
	return best
end

-- Each lane's weight: 1, up to `cfg.most` as its known enemies (`foes[k]`) outnumber the side's bots there (`own[k]`)
-- `cfg.odds` to 1
function BotLanes.weights(foes: { number }, own: { number }, n: number, cfg: { most: number, odds: number }): { number }
	local w = {}
	for k = 1, n do
		local f, o = foes[k] or 0, own[k] or 0
		local need = math.clamp(f / ((o + 1) * cfg.odds), 0, 1)
		w[k] = 1 + (cfg.most - 1) * need
	end
	return w
end

-- How many of `squads` each lane should have (fractions): `least` each while there are enough, the rest by weight
function BotLanes.targets(weights: { number }, squads: number, least: number): { number }
	local n = #weights
	local sum = 0
	for _, w in weights do
		sum += w
	end
	local base = if squads >= n * least then least else 0
	local rest = squads - base * n
	local t = {}
	for k, w in weights do
		t[k] = base + (if sum > 0 then rest * w / sum else rest / n)
	end
	return t
end

-- The lane a new squad takes: the one furthest under its target (`have[k]` squads there now); on a tie the one furthest
-- from any lane in use, then the one nearest the middle
function BotLanes.pick(targets: { number }, have: { number }): number
	local n = #targets
	local function gapTo(k: number): number
		local g = math.huge
		for j = 1, n do
			if (have[j] or 0) > 0 then
				g = math.min(g, math.abs(j - k))
			end
		end
		return g
	end
	local best, bestNeed, bestGap, bestMid = 1, -math.huge, -1, math.huge
	for k = 1, n do
		local need = targets[k] - (have[k] or 0)
		local gap, mid = gapTo(k), math.abs(k - (n + 1) / 2)
		if
			need > bestNeed + 1e-6
			or (math.abs(need - bestNeed) <= 1e-6 and (gap > bestGap or (gap == bestGap and mid < bestMid)))
		then
			best, bestNeed, bestGap, bestMid = k, need, gap, mid
		end
	end
	return best
end

-- One squad to move: from the lane furthest over its target to the one furthest under it, once the two add up to
-- `moveAt` squads or more. Returns (from, to), nil when none.
function BotLanes.rebalance(targets: { number }, have: { number }, moveAt: number): (number?, number?)
	local over, overBy, under, underBy = nil, 0, nil, 0
	for k, t in targets do
		local e = (have[k] or 0) - t
		if e > overBy and (have[k] or 0) > 0 then
			over, overBy = k, e
		elseif -e > underBy then
			under, underBy = k, -e
		end
	end
	if over and under and overBy + underBy >= moveAt then
		return over, under
	end
	return nil, nil
end

return BotLanes
