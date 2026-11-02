--!strict
-- Normal bots and trenches (Config/Bots.Trenches; user 2026-11-02: "bots that arent engineers should build trenches
-- too. they should follow real strategy and tactics and have their own advanced trench behavior"): the trench system
-- a side digs at a held zone, laid out as WW1 lines were (scaled to the map), and the picks for fighting from it.
-- Pure: the server (src/server/Bots) plans and digs the runs through src/server/Build's planAs / workAs.

local BotTrenches = {}

-- A straight run to plan (Build.planAs from A to B): "Fire", "Support" or "Comm"
export type Run = { kind: string, ax: number, az: number, bx: number, bz: number }

export type Zone = { x: number, z: number, radius: number }

-- The system at `zone`, the enemy's way in along (tx, tz) (a flat unit), in the order it is dug:
-- - Fire: across the zone's enemy-facing edge (`Fire.edge` of its radius out), `Fire.width` wide in `Fire.bays` runs
--   joined end to end, every other joint `Fire.traverse` studs toward the enemy: bays and traverses, so no shell burst
--   or gunner in it sweeps the whole line;
-- - Support: a straight line `Support.back` studs behind the fire trench's rear joints, `Support.width` wide;
-- - Comm: a communication trench from the support line's middle up to the fire trench's, in two runs jogging
--   `Comm.jog` studs across at half way (a zig-zag, no straight line of sight down it).
-- `fireOnly`: the fire trench alone.
function BotTrenches.layout(zone: Zone, tx: number, tz: number, cfg: any, fireOnly: boolean?): { Run }
	local ax, az = -tz, tx -- (across: right angles to the way in)
	local F = cfg.Fire
	local ex, ez = zone.x + tx * zone.radius * F.edge, zone.z + tz * zone.radius * F.edge
	local runs: { Run } = {}
	local seg = F.width / F.bays
	local function at(i: number): (number, number)
		local along = -F.width / 2 + i * seg
		local fwd = if i % 2 == 1 then F.traverse else 0
		return ex + ax * along + tx * fwd, ez + az * along + tz * fwd
	end
	for i = 0, F.bays - 1 do
		local x1, z1 = at(i)
		local x2, z2 = at(i + 1)
		table.insert(runs, { kind = "Fire", ax = x1, az = z1, bx = x2, bz = z2 })
	end
	if fireOnly then
		return runs
	end
	local S = cfg.Support
	local sx, sz = ex - tx * S.back, ez - tz * S.back
	table.insert(runs, {
		kind = "Support",
		ax = sx - ax * S.width / 2,
		az = sz - az * S.width / 2,
		bx = sx + ax * S.width / 2,
		bz = sz + az * S.width / 2,
	})
	-- (the fire trench's middle: on the run across `along` 0)
	local mid = F.width / 2 / seg
	local i = math.floor(mid)
	local x1, z1 = at(i)
	local x2, z2 = at(math.min(i + 1, F.bays))
	local t = mid - i
	local fx, fz = x1 + (x2 - x1) * t, z1 + (z2 - z1) * t
	local C = cfg.Comm
	local jx, jz = (sx + fx) / 2 + ax * C.jog, (sz + fz) / 2 + az * C.jog
	-- (it stops `C.short` studs off each line: the planner tees it into their sides)
	local function toward(px: number, pz: number, qx: number, qz: number, by: number): (number, number)
		local dx, dz = qx - px, qz - pz
		local len = math.sqrt(dx * dx + dz * dz)
		return px + dx / len * by, pz + dz / len * by
	end
	local s0x, s0z = toward(sx, sz, jx, jz, C.short)
	local f0x, f0z = toward(fx, fz, jx, jz, C.short)
	table.insert(runs, { kind = "Comm", ax = s0x, az = s0z, bx = jx, bz = jz })
	table.insert(runs, { kind = "Comm", ax = jx, az = jz, bx = f0x, bz = f0z })
	return runs
end

-- How far (px, pz) lies from the segment A-B, and where along it (0 at A, 1 at B; outside 0..1 past an end).
function BotTrenches.offRun(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then ((px - ax) * dx + (pz - az) * dz) / len2 else 0
	local c = math.clamp(t, 0, 1)
	return math.sqrt((px - (ax + dx * c)) ^ 2 + (pz - (az + dz * c)) ^ 2), t
end

-- The square (an index into `squares`, flat points) that shows `run` was planned: one lying on its line (within
-- `within`) in its middle part (`ends` of its length off each end, where the runs it joins lie), or nil.
function BotTrenches.laid(run: Run, squares: { { x: number, z: number } }, within: number, ends: number): number?
	for i, s in squares do
		local d, t = BotTrenches.offRun(s.x, s.z, run.ax, run.az, run.bx, run.bz)
		if d <= within and t >= ends and t <= 1 - ends then
			return i
		end
	end
	return nil
end

-- Whether run `k` of `runs` may be planned yet: every run before it planned (`laid`), so each one joins the last (a
-- run that joins nothing must keep Config/Build.Trench.spacing from every other trench, and the bays lie closer):
-- the fire trench bay by bay, then the support line, then the communication trench.
function BotTrenches.ready(laid: { [number]: boolean }, k: number): boolean
	for i = 1, k - 1 do
		if not laid[i] then
			return false
		end
	end
	return true
end

-- Where a refused run's far end B goes (the ground, something in the way, too near another trench): `tries` (1, 2,
-- ...) steps of `step` at right angles to the run, one way then the other; its start A stays where it joins the last
-- run.
function BotTrenches.swing(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	tries: number,
	step: number
): (number, number)
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return bx, bz
	end
	local k = math.ceil(tries / 2) * (if tries % 2 == 1 then 1 else -1)
	return bx - dz / len * step * k, bz + dx / len * step * k
end

-- How far from a trench square's line its fire step is: `rise` studs up its forward wall from the floor's edge (the
-- trench's `floor` half width, its walls at `angle` degrees: Config/Build.Trench), so the step follows the trench's
-- shape.
function BotTrenches.stepOut(floor: number, angle: number, rise: number): number
	return floor + rise / math.tan(math.rad(angle))
end

-- A fire step on a dug fire-trench square at (x, z): up its forward wall under the parapet, `step` studs from the
-- square's line toward the enemy (tx, tz), facing out.
function BotTrenches.fireStep(x: number, z: number, tx: number, tz: number, step: number): (number, number)
	return x + tx * step, z + tz * step
end

-- Whether a bot is a digger: half of a holding squad digs (`share`), the rest stand guard (user 2026-11-02: "Half dig,
-- half guard"); `idx` its place in the squad (1-based) of `count`.
function BotTrenches.digs(idx: number, count: number, share: number): boolean
	return idx <= math.max(1, math.floor(count * share + 0.5))
end

-- Whether a fire trench is lost: `inside` enemies known in or past it, and fewer than `keep` of its `held` holders
-- (`alive` of them) still standing.
function BotTrenches.overrun(inside: number, alive: number, held: number, keep: number): boolean
	return inside > 0 and (held == 0 or alive / held < keep)
end

-- Whether the reserve in the support line moves up to the fire step: an enemy known within `alarm` studs of the fire
-- trench.
function BotTrenches.standTo(nearest: number, alarm: number): boolean
	return nearest <= alarm
end

-- The trench square (an index) whose floor `p` is in: within `floor` studs of the square's middle, or nil.
function BotTrenches.inSquare(px: number, pz: number, squares: { { x: number, z: number } }, floor: number): number?
	local best, bestD = nil, floor
	for i, s in squares do
		local d = math.sqrt((s.x - px) ^ 2 + (s.z - pz) ^ 2)
		if d <= bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Whether a piece at (x, z), `half` studs from its middle to its corners, keeps off every trench line in `lines` (runs
-- planned or dug, and saps): `reach` studs (the trench's wall top and a margin) and its own `half` from each (user
-- 2026-11-02: "never have structures where trenches should be").
function BotTrenches.clearOf(x: number, z: number, half: number, lines: { Run }, reach: number): boolean
	for _, l in lines do
		if BotTrenches.offRun(x, z, l.ax, l.az, l.bx, l.bz) < reach + half then
			return false
		end
	end
	return true
end

-- What a digger does with a piece in a trench run's way (user 2026-11-02: "plan around structures, destroy them if
-- necessary"): "tear" it down (a small piece, `tear[key]`, the enemy's or a bot's), else "around" (the run swings
-- aside: a gun, a nest, a dugout, or a player's own piece).
function BotTrenches.blocker(key: string, own: boolean, byBot: boolean, tear: { [string]: boolean }): string
	return if tear[key] and (not own or byBot) then "tear" else "around"
end

return BotTrenches
