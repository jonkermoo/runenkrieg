--!strict
-- Normal bots and buildings (Config/Bots.Indoors; user 2026-11-02): which window or doorway a defender holds, which
-- indoor cover spots a cover search tries, and the spot an attacker clears a building through. Pure picks on the
-- spots src/server/Indoors finds (floor point, facing out, story).

local BotBuildings = {}

export type Spot = {
	x: number,
	z: number,
	fx: number, -- facing out of the building (flat unit)
	fz: number,
	story: number,
	taken: number, -- bots holding it already
}

-- The window or doorway spot a defender holds within `radius` of the zone at (cx, cz), facing the enemy's way in
-- (tx, tz: a flat unit toward the enemy): out of it by more than `facing` (a dot product), not taken, the most
-- facing first with `upstairs` per story above the ground (they see further) and `random` (0..1 `roll`s) to spread
-- them; nil if none.
function BotBuildings.pickHold(
	spots: { Spot },
	cx: number,
	cz: number,
	radius: number,
	tx: number,
	tz: number,
	rolls: { number },
	cfg: { facing: number, upstairs: number, random: number }
): number?
	local best, bestScore = nil, -math.huge
	for i, s in spots do
		local dx, dz = s.x - cx, s.z - cz
		local dot = s.fx * tx + s.fz * tz
		if s.taken == 0 and dx * dx + dz * dz <= radius * radius and dot > cfg.facing then
			local score = dot + s.story * cfg.upstairs + (rolls[i] or 0) * cfg.random
			if score > bestScore then
				best, bestScore = i, score
			end
		end
	end
	return best
end

-- The spots (indexes, nearest first) a cover search adds from indoors: at most `count`, within `reach` of the bot
-- at (x, z) and farther from the threat at (hx, hz) than the bot is less `gain` (never toward it).
function BotBuildings.coverCandidates(
	spots: { Spot },
	x: number,
	z: number,
	hx: number,
	hz: number,
	reach: number,
	gain: number,
	count: number
): { number }
	local here = math.sqrt((x - hx) ^ 2 + (z - hz) ^ 2)
	local list: { { i: number, d: number } } = {}
	for i, s in spots do
		local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
		local threat = math.sqrt((s.x - hx) ^ 2 + (s.z - hz) ^ 2)
		if d <= reach and threat >= here - gain then
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

-- The spot of a building nearest an enemy at (ex, ez) within `within` studs (the enemy is in that building), or nil.
function BotBuildings.inside(spots: { Spot }, ex: number, ez: number, within: number): number?
	local best, bestD = nil, within * within
	for i, s in spots do
		local d = (s.x - ex) ^ 2 + (s.z - ez) ^ 2
		if d <= bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Whether a bot walking a path stops for a door: the waypoint ahead is a door link's (`door`), it is within
-- `doorReach` of it, and the door is opening for it (`opening`: shut, and it reached it to open) or it opened it less
-- than `doorWait` seconds ago, while it swings. A shut door it can't open yet (out of the prompt's reach, someone
-- shutting it) never holds it: it walks on and tries again (user 2026-11-04: "AI often get stuck in houses").
function BotBuildings.waitForDoor(door: boolean, distance: number, opening: boolean, since: number, cfg: any): boolean
	if not door or distance > cfg.doorReach then
		return false
	end
	return opening or since < cfg.doorWait
end

-- A building's footprint: a rectangle round (cx, cz), `hu` studs each way along the flat unit (ux, uz) and `hv` across it
export type Box = { cx: number, cz: number, ux: number, uz: number, hu: number, hv: number }

-- Whether the segment (ax, az)-(bx, bz) (in a box's own studs) passes through the rectangle [-hu, hu] x [-hv, hv]
local function crosses(ax: number, az: number, bx: number, bz: number, hu: number, hv: number): boolean
	local t0, t1 = 0, 1
	local dx, dz = bx - ax, bz - az
	for _, e in { { -dx, ax + hu }, { dx, hu - ax }, { -dz, az + hv }, { dz, hv - az } } do
		local p, q = e[1], e[2]
		if math.abs(p) < 1e-9 then
			if q < 0 then
				return false
			end
		else
			local r = q / p
			if p < 0 then
				t0 = math.max(t0, r)
			else
				t1 = math.min(t1, r)
			end
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

-- Round a building (Config/Bots.Move.Round; user 2026-11-09, photo: "a group of enemy bots is stuck against a house"):
-- from (px, pz) toward (gx, gz) with `box` in the way, the corner `clear` studs out past the building to walk to first:
-- of the corners it can walk straight to, the one with the shortest way on to the goal. Nil when the way doesn't
-- cross the building or no corner can be reached straight.
function BotBuildings.roundCorner(
	px: number,
	pz: number,
	gx: number,
	gz: number,
	box: Box,
	clear: number
): (number?, number?)
	local function loc(x: number, z: number): (number, number)
		local dx, dz = x - box.cx, z - box.cz
		return dx * box.ux + dz * box.uz, -dx * box.uz + dz * box.ux
	end
	-- (a little inside its walls, so a bot pressed against one, or walking along it, doesn't count as through it)
	local hu, hv = math.max(box.hu - 0.5, 0), math.max(box.hv - 0.5, 0)
	local pa, pb = loc(px, pz)
	local ga, gb = loc(gx, gz)
	if not crosses(pa, pb, ga, gb, hu, hv) then
		return nil, nil
	end
	local best, bx, bz = math.huge, nil, nil
	for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local ca, cb = s[1] * (box.hu + clear), s[2] * (box.hv + clear)
		if not crosses(pa, pb, ca, cb, hu, hv) then
			local cost = math.sqrt((ca - pa) ^ 2 + (cb - pb) ^ 2) + math.sqrt((ga - ca) ^ 2 + (gb - cb) ^ 2)
			if cost < best then
				best = cost
				bx, bz = box.cx + ca * box.ux - cb * box.uz, box.cz + ca * box.uz + cb * box.ux
			end
		end
	end
	return bx, bz
end

return BotBuildings
