--!strict
-- Zone capture maths (Config/ZoneMatch): who holds the zone, where it moves, where a soldier spawns, the ranking.
-- Pure: positions are { x, z } tables, players their ids.

local ZoneMatch = {}

export type State = "Free" | "Held" | "Contested"

-- Whether a soldier at (x, y, z) is in a zone at (zx, zy, zz).
function ZoneMatch.inside(x: number, y: number, z: number, zx: number, zy: number, zz: number, cfg: any): boolean
	return (x - zx) ^ 2 + (z - zz) ^ 2 <= cfg.Radius ^ 2 and math.abs(y - zy) <= cfg.Height
end

-- The zone's state from the ids of the soldiers able to hold it who are in it, and its holder when held.
function ZoneMatch.occupancy(inside: { number }): (State, number?)
	if #inside == 0 then
		return "Free", nil
	elseif #inside == 1 then
		return "Held", inside[1]
	end
	return "Contested", nil
end

-- Whether a soldier who has held the live spot alone for `held` seconds (added up) has captured it: once `need` is
-- reached, and only once per live spot (`already`).
function ZoneMatch.captured(held: number, need: number, already: boolean): boolean
	return not already and held >= need
end

-- Another of `count` spots than `current` (a random `u` in [0, 1)); the only spot when there is one.
function ZoneMatch.nextSpot(current: number?, count: number, u: number): number
	if count <= 1 then
		return 1
	end
	if not current then
		return math.floor(u * count) + 1
	end
	local k = math.floor(u * (count - 1)) + 1 -- 1 .. count - 1 places after the current one
	return (current - 1 + k) % count + 1
end

local function dist(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

-- The spawn point (an index of `points`) farthest from every other living soldier in `others`, among those at least
-- `clear` from the live zone `zone`; every point when none is that far. With nobody else about, the one farthest from
-- the zone.
function ZoneMatch.pickSpawn(points: { { number } }, others: { { number } }, zone: { number }?, clear: number): number
	local allowed = {}
	for i, p in points do
		if not zone or dist(p, zone) >= clear then
			table.insert(allowed, i)
		end
	end
	if #allowed == 0 then
		for i in points do
			table.insert(allowed, i)
		end
	end
	local best, bestScore = allowed[1], -math.huge
	for _, i in allowed do
		local p = points[i]
		local score = math.huge
		for _, o in others do
			score = math.min(score, dist(p, o))
		end
		if #others == 0 then
			score = if zone then dist(p, zone) else 0
		end
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	return best
end

-- The ids by score, highest first (ties: the lower id first, so every client agrees).
function ZoneMatch.ranking(scores: { [number]: number }): { number }
	local ids = {}
	for id in scores do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		if scores[a] ~= scores[b] then
			return scores[a] > scores[b]
		end
		return a < b
	end)
	return ids
end

-- Seconds as m:ss (a clock that never shows below 0).
function ZoneMatch.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return ZoneMatch
