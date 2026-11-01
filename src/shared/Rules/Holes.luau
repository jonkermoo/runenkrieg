--!strict
-- Bullet holes (Config/Firing.Effects.Hole, src/client/GunFx): how long one shows before it fades, how many go once
-- one more is made, and which a reshaped patch of ground takes. Pure.

local Holes = {}

export type Hole = { life: number, fade: number, max: number }

-- How long a hole stays whole, then how long it takes to fade out: `fade` at most, inside its `life`.
function Holes.timing(h: Hole): (number, number)
	local fade = math.clamp(h.fade, 0, math.max(h.life, 0))
	return math.max(h.life - fade, 0), fade
end

-- How many of the oldest go once `count` holes show (the list oldest first).
function Holes.excess(count: number, max: number): number
	return math.max(0, count - math.max(max, 0))
end

-- Whether ground reshaped within `radius` studs of a point takes a hole `distance` studs from it (`margin` more).
function Holes.reshaped(distance: number, radius: number, margin: number): boolean
	return distance <= radius + margin
end

return Holes
