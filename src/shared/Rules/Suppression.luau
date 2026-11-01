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

-- the level after a hit adding `hit`, never past `cap`
function Suppression.add(level: number, hit: number, cap: number): number
	return math.clamp(level + math.max(hit, 0), 0, cap)
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
