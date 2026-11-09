--!strict
-- What a side has learned of an enemy machine gun's fire (Config/Bots.Crew.Arcs; user 2026-11-06: "machine guns should
-- be a terrifying threat as a soldier"): the arc it has been sweeping, felt from the rounds passing its soldiers, whether
-- a spot lies in it, and the way round it. Pure: src/server/Bots/Move feels the rounds and walks the detours.

local BotArcs = {}

export type Arc = {
	x: number, -- the gun
	z: number,
	yaw: number, -- the arc's middle, degrees (0 toward +z, 90 toward +x)
	half: number, -- degrees each way of it
	at: number, -- when a round was last felt
	first: number, -- when it was first felt
}

local function wrap(deg: number): number
	return (deg + 180) % 360 - 180
end

function BotArcs.yawOf(dx: number, dz: number): number
	return math.deg(math.atan2(dx, dz))
end

-- A gun's arc as first felt: a round along `yaw`
function BotArcs.new(x: number, z: number, yaw: number, now: number, cfg: { half: number }): Arc
	return { x = x, z = z, yaw = yaw, half = cfg.half, at = now, first = now }
end

-- `arc` with one more round felt along `yaw`: widened to take it in, never past `cfg.maxHalf` each way
function BotArcs.feel(arc: Arc, yaw: number, now: number, cfg: { maxHalf: number })
	arc.at = now
	local off = wrap(yaw - arc.yaw)
	if math.abs(off) <= arc.half then
		return
	end
	local lo, hi = -arc.half, arc.half
	if off > hi then
		hi = off
	else
		lo = off
	end
	arc.yaw = wrap(arc.yaw + (lo + hi) / 2)
	arc.half = math.min((hi - lo) / 2, cfg.maxHalf)
end

-- Whether (`x`, `z`) lies in `arc`, within `cfg.reach` studs of the gun
function BotArcs.inside(arc: Arc, x: number, z: number, cfg: { reach: number }): boolean
	local dx, dz = x - arc.x, z - arc.z
	if dx * dx + dz * dz > cfg.reach * cfg.reach then
		return false
	end
	return math.abs(wrap(BotArcs.yawOf(dx, dz) - arc.yaw)) <= arc.half
end

-- Whether any of `cfg.steps` looks along the walk lies in `arc`; and the mean distance of those from the gun
local function crossing(
	arc: Arc,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	cfg: { reach: number, steps: number }
): (boolean, number)
	local sum, n = 0, 0
	for i = 1, cfg.steps do
		local t = i / cfg.steps
		local x, z = ax + (bx - ax) * t, az + (bz - az) * t
		if BotArcs.inside(arc, x, z, cfg) then
			sum += math.sqrt((x - arc.x) ^ 2 + (z - arc.z) ^ 2)
			n += 1
		end
	end
	return n > 0, if n > 0 then sum / n else 0
end

-- Where a walk from (`ax`, `az`) to (`bx`, `bz`) goes next to keep out of `arc`: a point `cfg.margin` degrees off one of
-- its edges, as far out as the stretch it would have crossed or at the arc's far end, reached without entering the arc.
-- A goal in the arc is then come at from that edge (the flank); a goal outside it must be reached clear of the arc too, so
-- a walk from one side of a fan to the other has no way round and goes across. Nil when it needn't or can't: the walk is
-- under `cfg.close` studs, doesn't cross the arc, starts in it (it gets out first: its cover), or going round is over
-- `cfg.extra` times as long.
function BotArcs.detour(
	arc: Arc,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	cfg: { reach: number, close: number, extra: number, margin: number, steps: number }
): (number?, number?)
	local straight = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	if straight < cfg.close or BotArcs.inside(arc, ax, az, cfg) then
		return nil, nil
	end
	local crosses, mid = crossing(arc, ax, az, bx, bz, cfg)
	if not crosses then
		return nil, nil
	end
	local goalIn = BotArcs.inside(arc, bx, bz, cfg)
	local bestX, bestZ, bestLen = nil, nil, cfg.extra * straight
	for _, r in { mid, cfg.reach } do
		for _, sign in { -1, 1 } do
			local a = math.rad(arc.yaw + sign * (arc.half + cfg.margin))
			local x, z = arc.x + math.sin(a) * r, arc.z + math.cos(a) * r
			local len = math.sqrt((x - ax) ^ 2 + (z - az) ^ 2) + math.sqrt((bx - x) ^ 2 + (bz - z) ^ 2)
			if
				len <= bestLen
				and not (crossing(arc, ax, az, x, z, cfg))
				and (goalIn or not (crossing(arc, x, z, bx, bz, cfg)))
			then
				bestX, bestZ, bestLen = x, z, len
			end
		end
	end
	return bestX, bestZ
end

-- How far (`px`, `pz`) lies off the shot's line from (`ax`, `az`) to (`bx`, `bz`), flat
function BotArcs.offLine(ax: number, az: number, bx: number, bz: number, px: number, pz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	return math.sqrt((ax + dx * t - px) ^ 2 + (az + dz * t - pz) ^ 2)
end

return BotArcs
