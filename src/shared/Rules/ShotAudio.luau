--!strict
-- Someone else's shot as a listener hears it (Config/Audio.Heard): when each part arrives, how loud, how dull. Pure:
-- points are { x, y, z } lists, distances in studs, times in seconds.

local ShotAudio = {}

export type Point = { number }
export type Air = { from: number, low: number, mid: number, high: number, floor: { number } }
export type Pass = { along: number, off: number, point: Point }
export type Echo = { index: number, delay: number, gain: number }

local function sub(a: Point, b: Point): Point
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function dot(a: Point, b: Point): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

-- Seconds a sound takes to come `distance` studs.
function ShotAudio.delay(distance: number, speed: number): number
	return math.max(0, distance) / speed
end

-- How much of the shot's own sound and of the far report play at `distance` (equal power: the sum of squares is 1).
function ShotAudio.mix(distance: number, near: number, far: number): (number, number)
	local t = math.clamp((distance - near) / (far - near), 0, 1)
	return math.cos(t * math.pi / 2), math.sin(t * math.pi / 2)
end

-- The equalizer's low / mid / high gains (dB) after `distance` studs of air.
function ShotAudio.air(distance: number, air: Air): (number, number, number)
	local d = math.max(0, distance - air.from)
	return math.max(air.floor[1], air.low * d),
		math.max(air.floor[2], air.mid * d),
		math.max(air.floor[3], air.high * d)
end

-- Where a bullet from `origin` to `hit` passes `listener`: how far along its path (studs from the muzzle), how far off
-- it, and the point on the path. nil when it passes farther than `radius`, within `clear` of the muzzle, or stops
-- before it gets level with the listener.
function ShotAudio.pass(origin: Point, hit: Point, listener: Point, radius: number, clear: number): Pass?
	local line = sub(hit, origin)
	local length = math.sqrt(dot(line, line))
	if length <= 0 then
		return nil
	end
	local dir = { line[1] / length, line[2] / length, line[3] / length }
	local along = dot(sub(listener, origin), dir)
	if along < clear or along > length then
		return nil
	end
	local point = { origin[1] + dir[1] * along, origin[2] + dir[2] * along, origin[3] + dir[3] * along }
	local gap = sub(listener, point)
	local off = math.sqrt(dot(gap, gap))
	if off > radius then
		return nil
	end
	return { along = along, off = off, point = point }
end

-- When a passing bullet is heard: it flies `along` studs to the point beside the listener, then the sound comes `off`.
function ShotAudio.passTime(along: number, off: number, bullet: number, speed: number): number
	return along / bullet + off / speed
end

-- A passing bullet's volume: 1 on its path, `edge` at the radius.
function ShotAudio.passGain(off: number, radius: number, edge: number): number
	return 1 + (edge - 1) * math.clamp(off / radius, 0, 1)
end

-- Echoes of a shot `direct` studs away, from reflections `paths` ({ to the wall, wall to the listener } each): the
-- strongest `count` whose path is at least `extra` longer than the direct one (the shortest), loudest first. An echo plays from the
-- wall, so its falloff (1 / distance from `ref`) only counts the wall's distance: `gain` (what the reflection keeps) is
-- scaled down to the falloff of the whole path.
function ShotAudio.echoes(
	direct: number,
	paths: { { number } },
	speed: number,
	count: number,
	extra: number,
	gain: number,
	ref: number
): { Echo }
	local out: { Echo } = {}
	for i, p in paths do
		local path = p[1] + p[2]
		if path - direct >= extra then
			table.insert(out, {
				index = i,
				delay = path / speed,
				gain = gain * math.max(p[2], ref) / math.max(path, ref),
			})
		end
	end
	table.sort(out, function(x, y) -- as heard, the shortest path is the loudest
		return x.delay < y.delay
	end)
	while #out > count do
		table.remove(out)
	end
	return out
end

return ShotAudio
