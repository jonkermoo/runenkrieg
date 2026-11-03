--!strict
-- Bot squads in Normal as plain numbers (Config/Bots.Squads, Config/Bots.Routes; src/server/Bots runs them). User
-- 2026-11-01: "make AI want to push as well ... make them have teamwork coded in too. they push when they have covering
-- fire", and "make them take advantage of the size of the map ... logical choices of where they decide to go".
-- - A side's bots with the same order go in squads of a few (form). An attacking squad has a phase:
--   Move: no enemy known near, everyone walks the route (a side's lane, then the approach spot by the zone);
--   Bound: in contact, one half holds and fires at where enemies were seen while the other runs forward, then they
--   swap (the movers there, or after `boundMax` seconds);
--   Assault: at the approach spot with covering fire, or with no enemy known, or outnumbering the zone's enemies:
--   all go in together and fight on the move.
--   A defending squad holds spots in its zone.
-- - Spots round a sector (approach spots outside its zone on the attackers' side, hold spots inside it) are scored
--   by cover, nearby walls, trees and houses, distance, how many squads already use their lane, and a little chance
--   (scoreSpot, pickSpot); a squad keeps its lane (north, centre or south of the straight line).

local BotSquads = {}

export type Phase = "Move" | "Bound" | "Assault" | "Hold"
export type Role = "Move" | "Support" | "Assault" | "Hold"
export type Squad = {
	phase: Phase,
	moving: number, -- the half running in a bound (1 or 2)
	swapAt: number, -- the bound's swap at the latest
}
export type Facts = {
	now: number,
	defend: boolean, -- its order is to defend
	contact: boolean, -- an enemy seen lately near the squad
	ready: number, -- share of the squad at its approach spot (0..1)
	inZone: number, -- share of the squad in the zone already
	ours: number, -- the side's soldiers in the zone
	theirs: number, -- the enemy's soldiers in the zone
	size: number, -- the squad's living members
	moversThere: boolean, -- the running half has reached its next stop
}
export type Spot = { hidden: boolean, near: number, distance: number, lane: number }

-- `ids` (in a steady order) in squads of `size`; a last squad under `least` joins the one before it.
function BotSquads.form(ids: { any }, size: number, least: number): { { any } }
	local out: { { any } } = {}
	for i, id in ids do
		local k = (i - 1) // size + 1
		out[k] = out[k] or {}
		table.insert(out[k], id)
	end
	local n = #out
	if n >= 2 and #out[n] < least then
		for _, id in out[n] do
			table.insert(out[n - 1], id)
		end
		out[n] = nil
	end
	return out
end

-- A fresh squad.
function BotSquads.new(): Squad
	return { phase = "Move", moving = 1, swapAt = 0 }
end

-- The squad's phase after this tick (Config/Bots.Squads `cfg`).
function BotSquads.step(sq: Squad, f: Facts, cfg: any)
	if f.defend then
		sq.phase = "Hold"
		return
	end
	if sq.phase == "Hold" then
		sq.phase = "Move"
	end
	-- the push: at the zone's edge with cover from the squad's fire, or nobody in the way, or more of us than them
	local there = f.ready >= cfg.readyShare or f.inZone >= cfg.readyShare
	local outnumber = f.ours + f.size > f.theirs + cfg.margin
	if sq.phase == "Assault" or (there and (not f.contact or sq.phase == "Bound" or outnumber)) then
		sq.phase = "Assault"
		return
	end
	if f.contact then
		if sq.phase ~= "Bound" then
			sq.phase = "Bound"
			sq.moving = 1
			sq.swapAt = f.now + cfg.boundMax
		elseif f.moversThere or f.now >= sq.swapAt then
			sq.moving = 3 - sq.moving
			sq.swapAt = f.now + cfg.boundMax
		end
	else
		sq.phase = "Move"
	end
end

-- The role of the member at `index` (1-based, in the squad's order): in a bound, the halves alternate by index.
function BotSquads.role(sq: Squad, index: number): Role
	if sq.phase == "Hold" then
		return "Hold"
	elseif sq.phase == "Assault" then
		return "Assault"
	elseif sq.phase == "Bound" then
		local half = if index % 2 == 1 then 1 else 2
		return if half == sq.moving then "Move" else "Support"
	end
	return "Move"
end

-- A spot's worth: cover, things close by (capped), nearer better, its lane's squads already there worse, a little
-- chance (`roll` 0..1). `w`: Config/Bots.Routes.weights.
function BotSquads.scoreSpot(s: Spot, crowd: number, roll: number, w: any, nearCap: number): number
	return (if s.hidden then w.hidden else 0)
		+ math.min(s.near, nearCap) * w.near
		- s.distance * w.distance
		- crowd * w.crowd
		+ roll * w.random
end

-- The best of `spots` for a squad: `lane` (nil: any) keeps it to its lane when that lane has spots; `crowd[lane]` the
-- squads already using each lane; `rolls[i]` a random 0..1 per spot. Returns its index, nil when there are none.
function BotSquads.pickSpot(
	spots: { Spot },
	lane: number?,
	crowd: { [number]: number },
	rolls: { number },
	w: any,
	nearCap: number
): number?
	local inLane = false
	if lane ~= nil then
		for _, s in spots do
			if s.lane == lane then
				inLane = true
				break
			end
		end
	end
	local best, bestAt = -math.huge, nil
	for i, s in spots do
		if not inLane or s.lane == lane then
			local v = BotSquads.scoreSpot(s, crowd[s.lane] or 0, rolls[i] or 0, w, nearCap)
			if v > best then
				best, bestAt = v, i
			end
		end
	end
	return bestAt
end

-- The lane (-1, 0 or 1) a point sits in, seen from `home` toward `goal` (flat x, z): the angle off the straight line
-- past `within` degrees is a side lane (its sign: which side).
function BotSquads.lane(hx: number, hz: number, gx: number, gz: number, px: number, pz: number, within: number): number
	local ax, az = gx - hx, gz - hz
	local bx, bz = px - gx, pz - gz
	-- the spot measured from the goal, against the way back home
	local backX, backZ = -ax, -az
	local cross = backX * bz - backZ * bx
	local dot = backX * bx + backZ * bz
	local angle = math.deg(math.atan2(math.abs(cross), dot))
	if angle <= within then
		return 0
	end
	return if cross > 0 then 1 else -1
end

-- Whether a squad moves on from a point it walks to (its waypoint, its approach spot; Config/Bots.Squads.waitMax): `there`
-- of its `free` members (those not off building, rescuing or guarding) there, `cfg.readyShare` of them at least one;
-- or anyone there for `waited` >= `cfg.waitMax` seconds.
function BotSquads.moveOn(
	there: number,
	free: number,
	waited: number,
	cfg: { readyShare: number, waitMax: number }
): boolean
	if there <= 0 then
		return false
	end
	return there >= math.max(1, math.ceil(free * cfg.readyShare)) or waited >= cfg.waitMax
end

-- The lane with the fewest squads (`crowd`), the centre first on a tie, then -1, then 1.
function BotSquads.quietLane(crowd: { [number]: number }): number
	local best, bestLane = math.huge, 0
	for _, lane in { 0, -1, 1 } do
		local n = crowd[lane] or 0
		if n < best then
			best, bestLane = n, lane
		end
	end
	return bestLane
end

-- A group of enemies a squad at (mx, mz) could push at (user 2026-11-02 hand test: "make AI push as a team / group if
-- they are confident they can take out a section/group of enemies"): the known enemy (`known`) nearest it within
-- `cfg.reach` studs and every other within `cfg.cluster` studs of that one; their middle and how many. Nil if none.
function BotSquads.group(
	known: { { x: number, z: number } },
	mx: number,
	mz: number,
	cfg: { reach: number, cluster: number }
): (number?, number?, number)
	local first, firstD = nil, cfg.reach
	for _, k in known do
		local d = math.sqrt((k.x - mx) ^ 2 + (k.z - mz) ^ 2)
		if d <= firstD then
			first, firstD = k, d
		end
	end
	if not first then
		return nil, nil, 0
	end
	local sx, sz, n = 0, 0, 0
	for _, k in known do
		if math.sqrt((k.x - first.x) ^ 2 + (k.z - first.z) ^ 2) <= cfg.cluster then
			sx, sz, n = sx + k.x, sz + k.z, n + 1
		end
	end
	return sx / n, sz / n, n
end

-- Whether a squad is confident it can take a group (user 2026-11-02: "Outnumber 1.5 to 1"): its side's soldiers near
-- it (`ours`) at least `cfg.odds` times the group (`theirs`).
function BotSquads.confident(ours: number, theirs: number, cfg: { odds: number }): boolean
	return theirs > 0 and ours >= cfg.odds * theirs
end

return BotSquads
