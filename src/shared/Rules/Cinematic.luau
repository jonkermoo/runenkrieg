--!strict
-- The cinematic layer's maths (src/client/Cinematic, Config/Cinematic): the depth of field's focus and in-focus radius.

local Cinematic = {}

-- the focus eased from `current` toward `target` at `rate` per second
function Cinematic.focus(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * math.max(dt, 0)))
end

-- the in-focus radius around a focus distance: a share of it, at least `minRadius`, at most `maxRadius`
function Cinematic.radius(focus: number, share: number, minRadius: number, maxRadius: number): number
	return math.min(math.max(focus * share, minRadius), maxRadius)
end

return Cinematic
