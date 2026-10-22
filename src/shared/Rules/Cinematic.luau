--!strict
-- The cinematic layer's maths (src/client/Cinematic, Config/Cinematic): how much of the day grade shows for the sun's
-- height, the grade blended between day and night, and the depth of field's focus and in-focus radius.

local Cinematic = {}

export type Grade = { tint: { number }, brightness: number, contrast: number, saturation: number }

-- 1 with the sun at `dayAbove` (the y of the sun direction) or higher, 0 at `nightBelow` or lower, smooth between
function Cinematic.daylight(sunY: number, dayAbove: number, nightBelow: number): number
	if dayAbove <= nightBelow then
		return if sunY >= dayAbove then 1 else 0
	end
	local t = math.clamp((sunY - nightBelow) / (dayAbove - nightBelow), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- the grade `t` of the way from night (0) to day (1)
function Cinematic.grade(day: Grade, night: Grade, t: number): Grade
	return {
		tint = {
			lerp(night.tint[1], day.tint[1], t),
			lerp(night.tint[2], day.tint[2], t),
			lerp(night.tint[3], day.tint[3], t),
		},
		brightness = lerp(night.brightness, day.brightness, t),
		contrast = lerp(night.contrast, day.contrast, t),
		saturation = lerp(night.saturation, day.saturation, t),
	}
end

-- the focus eased from `current` toward `target` at `rate` per second
function Cinematic.focus(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * math.max(dt, 0)))
end

-- the in-focus radius around a focus distance: a share of it, at least `minRadius`, at most `maxRadius`
function Cinematic.radius(focus: number, share: number, minRadius: number, maxRadius: number): number
	return math.min(math.max(focus * share, minRadius), maxRadius)
end

return Cinematic
