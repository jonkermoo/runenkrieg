--!strict
-- How strong the screen blur is (Config/ScreenBlur): from a bullet passing close, from a blast nearby, built up over
-- hits and eased over time. Pure: strengths are shares 0..1 of the largest blur, distances in studs, times in seconds.

local ScreenBlur = {}

export type Blast = { reach: number, maxReach: number, full: number, least: number, curve: number }

-- A bullet passing `off` studs from the camera: `peak` on its path, 0 at `radius` and past it.
function ScreenBlur.pass(off: number, radius: number, peak: number, curve: number): number
	if radius <= 0 then
		return 0
	end
	return peak * (1 - math.clamp(off / radius, 0, 1)) ^ curve
end

-- A blast with a fireball `fireball` studs across, `distance` studs away.
function ScreenBlur.blast(distance: number, fireball: number, b: Blast): number
	local reach = math.min(b.reach * fireball, b.maxReach)
	if reach <= 0 then
		return 0
	end
	local size = math.clamp(fireball / b.full, b.least, 1)
	return size * (1 - math.clamp(distance / reach, 0, 1)) ^ b.curve
end

-- A new `hit` over the blur `current`: the stronger one plus `stack` of the weaker, never past `cap`.
function ScreenBlur.add(current: number, hit: number, stack: number, cap: number): number
	return math.min(cap, math.max(current, hit) + stack * math.min(current, hit))
end

-- One frame `dt` long: the blur shown eases up to `level` over about `rise` seconds, and the level eases down over about
-- `fall` once its hold is over (`held`); both drop to 0 under `floor`. Returns the new level and shown strength.
function ScreenBlur.step(
	level: number,
	shown: number,
	dt: number,
	held: boolean,
	rise: number,
	fall: number,
	floor: number
): (number, number)
	if not held then
		level *= math.exp(-dt / fall)
	end
	if level < floor then
		level = 0
	end
	if shown < level then
		shown += (level - shown) * (1 - math.exp(-dt / rise))
	else
		shown = level
	end
	return level, shown
end

return ScreenBlur
