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

return BotBuildings
