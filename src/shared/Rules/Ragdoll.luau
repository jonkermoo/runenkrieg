--!strict
-- How long a knocked-down soldier stays down (Config/Ragdoll.ByDamage, src/server/Ragdoll). Pure: seconds.

local Ragdoll = {}

export type ByDamage = { floor: number, ceiling: number, full: number }

-- The get-up wait after the body settles: the knock's own `getUp` for a knock that did no `damage` (nil or 0),
-- else from `by.floor` at no damage up to `by.ceiling` at `by.full` damage and more, never under `getUp`.
function Ragdoll.getUp(getUp: number, damage: number?, by: ByDamage): number
	if not damage or damage <= 0 then
		return getUp
	end
	local t = math.clamp(damage / by.full, 0, 1)
	return math.max(getUp, by.floor + (by.ceiling - by.floor) * t)
end

export type Settle = { still: number, minDown: number, maxDown: number }

-- Whether a body `t` seconds after its knock has settled (the get-up wait starts): at `maxDown`, or from `minDown` once
-- slower than `still` studs/s. A dragged body's speed is the pull's, not the knock's: it counts as still.
function Ragdoll.settled(t: number, speed: number, dragged: boolean, cfg: Settle): boolean
	return t >= cfg.maxDown or (t >= cfg.minDown and (dragged or speed < cfg.still))
end

-- Whether a dragged soldier may break free (src/server/Dragging): its knock's own stand-up time, settled at
-- `settledAt` (nil: not yet) and `getUp` seconds after, has passed at `now`. Being dragged never shortens it.
function Ragdoll.served(settledAt: number?, getUp: number, now: number): boolean
	return settledAt ~= nil and now - settledAt >= getUp
end

-- Whether a soldier with `health` left plays its animations (the idle's breath on a knocked-down body): only alive. A
-- dead body is limp and still (user 2026-11-01: dead bodies' torsos kept moving up and down).
function Ragdoll.animates(health: number): boolean
	return health > 0
end

export type StayDown = { max: number }

-- Whether a living knocked-down soldier gets up at `now`: its get-up wait over at `readyAt` (nil: not yet), and the
-- stay-down key not `holding`, or held `cfg.max` s past the wait.
function Ragdoll.rises(readyAt: number?, holding: boolean, now: number, cfg: StayDown): boolean
	return readyAt ~= nil and now >= readyAt and (not holding or now - readyAt >= cfg.max)
end

return Ragdoll
