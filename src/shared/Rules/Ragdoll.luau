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

export type Vec = { x: number, y: number, z: number }

-- Which get-up a body lying with its torso's `look` (the chest) and `up` (the head) directions plays (Config/Ragdoll.GetUp):
-- "Back" with the chest facing up, else "Front"; and the way it stands facing, flat (x, z): toward the feet from the
-- back, toward the head from the front (along the chest while it isn't lying down).
function Ragdoll.getUpWay(look: Vec, up: Vec): (string, number, number)
	local back = look.y >= 0
	local s = if back then -1 else 1
	local fx, fz = up.x * s, up.z * s
	local m = math.sqrt(fx * fx + fz * fz)
	if m < 0.3 then
		fx, fz = look.x, look.z
		m = math.sqrt(fx * fx + fz * fz)
	end
	if m < 1e-6 then
		return if back then "Back" else "Front", 0, -1
	end
	return if back then "Back" else "Front", fx / m, fz / m
end

export type DownView = { state: string, left: number?, fill: number }

-- What a knocked-down, living player's own prompt shows (src/client/DownHud; user 2026-11-06: "a hold space to stay
-- down indicator"). `upAt`: when the get-up wait ends (server time, the "UpAt" attribute; nil while still settling),
-- `holding` the stay-down key, `dragged` by a teammate. States: "dragged" (the key breaks free instead), "held" (down
-- until let go, at most `max` s past the wait: `left` s of that, `fill` its share), "rising" (up in `left` s unless the
-- key is held), "settling" (no wait yet: `left` nil).
function Ragdoll.downView(now: number, upAt: number?, holding: boolean, dragged: boolean, cfg: StayDown): DownView
	if dragged then
		return { state = "dragged", fill = 0 }
	end
	if holding then
		if not upAt then
			return { state = "held", fill = 1 }
		end
		local left = math.max(upAt + cfg.max - now, 0)
		return { state = "held", left = left, fill = math.clamp(left / cfg.max, 0, 1) }
	end
	if not upAt then
		return { state = "settling", fill = 0 }
	end
	return { state = "rising", left = math.max(upAt - now, 0), fill = 0 }
end

return Ragdoll
