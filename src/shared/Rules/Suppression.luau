--!strict
-- How suppressed a soldier is (Config/Suppression; src/client/Suppression applies it). Pure: numbers only.

local Suppression = {}

-- `add` at distance 0, falling off to nothing at `radius` (`curve`: 1 straight, higher drops off sooner)
local function falloff(add: number, radius: number, curve: number, distance: number): number
	if radius <= 0 or distance >= radius then
		return 0
	end
	return add * (1 - math.max(distance, 0) / radius) ^ curve
end

-- a bullet passing `off` studs from the head
function Suppression.pass(off: number, p: { radius: number, add: number, curve: number }): number
	return falloff(p.add, p.radius, p.curve, off)
end

-- a bullet ending `distance` studs from the head
function Suppression.impact(distance: number, i: { radius: number, add: number, curve: number }): number
	return falloff(i.add, i.radius, i.curve, distance)
end

-- an explosion of `kg` at `distance` studs: its reach grows by the charge's cube root
function Suppression.blast(
	kg: number,
	distance: number,
	b: { add: number, reach: number, maxReach: number, curve: number }
): number
	if kg <= 0 then
		return 0
	end
	return falloff(b.add, math.min(b.reach * kg ^ (1 / 3), b.maxReach), b.curve, distance)
end

-- how far point `p` is from the segment `a` -> `b` (the body: feet to head), { x, y, z } each
function Suppression.toLine(p: { number }, a: { number }, b: { number }): number
	local ab = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local ap = { p[1] - a[1], p[2] - a[2], p[3] - a[3] }
	local len2 = ab[1] * ab[1] + ab[2] * ab[2] + ab[3] * ab[3]
	local t = if len2 > 0 then math.clamp((ap[1] * ab[1] + ap[2] * ab[2] + ap[3] * ab[3]) / len2, 0, 1) else 0
	local d = { ap[1] - ab[1] * t, ap[2] - ab[2] * t, ap[3] - ab[3] * t }
	return math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
end

-- the level after a hit adding `hit`, never past `cap`; a hit never lowers it (a rifle's under a machine gun's pin)
function Suppression.add(level: number, hit: number, cap: number): number
	return math.max(level, math.clamp(level + math.max(hit, 0), 0, cap))
end

-- how pinned a level is: 0 up to `cap` (the most anything but a machine gun reaches), 1 at `top` (Config MG.cap)
function Suppression.pinned(level: number, cap: number, top: number): number
	if top <= cap then
		return 0
	end
	return math.clamp((level - cap) / (top - cap), 0, 1)
end

-- a value from `a` at level 1 to `b` pinned, growing in from 0 below level 1
function Suppression.blend(level: number, pinned: number, a: number, b: number): number
	return math.clamp(level, 0, 1) * (a + (b - a) * math.clamp(pinned, 0, 1))
end

-- the level `dt` s on, `since` s after the last hit at the start of it: held for `hold` s, then falling 1 every `fall` s
function Suppression.decay(level: number, since: number, dt: number, hold: number, fall: number): number
	local falling = math.max(0, since + dt - math.max(since, hold))
	if fall <= 0 then
		return if falling > 0 then 0 else level
	end
	return math.max(0, level - falling / fall)
end

-- the shake's size for a level
function Suppression.size(level: number, grow: number): number
	return math.clamp(level, 0, 1) ^ grow
end

-- a jolt's share `t` s after its hit: 1 at the hit, shuddering `freq` radians per second as it dies away squared over
-- `time` s; 0 after
function Suppression.jolt(t: number, time: number, freq: number): number
	if t < 0 or t >= time then
		return 0
	end
	return (1 - t / time) ^ 2 * math.cos(t * freq)
end

return Suppression
