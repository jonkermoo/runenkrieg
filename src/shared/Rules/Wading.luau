--!strict
-- Wading through water (Config/Locomotion.Wading, src/client/Wading). Soldiers never swim: they walk on the bottom and
-- slow down once the water is hip-deep. Pure: studs, seconds.

local Wading = {}

-- The water's surface over a soldier's feet from one column of terrain voxels (bottom up, each `res` tall, the first
-- starting at `baseY`): `water[i]` whether voxel i is water, `occ[i]` its occupancy (0..1). The water has to reach
-- the feet (the voxel at `feetY` or the one above it, the bed's own voxel being ground); it runs up from there while the
-- voxels stay water and ends `occ` of the way up the last one. nil: no water at the feet.
function Wading.surface(water: { boolean }, occ: { number }, baseY: number, res: number, feetY: number): number?
	local at = math.floor((feetY - baseY) / res) + 1
	local first = nil
	for i = math.max(at, 1), math.min(at + 1, #water) do
		if water[i] then
			first = i
			break
		end
	end
	if not first then
		return nil
	end
	local last = first
	while water[last + 1] do
		last += 1
	end
	return baseY + (last - 1) * res + math.clamp(occ[last] or 1, 0, 1) * res
end

-- How deep the water stands over the feet (0 when dry or the surface is below them).
function Wading.depth(surfaceY: number?, feetY: number): number
	return if surfaceY then math.max(surfaceY - feetY, 0) else 0
end

-- The speed share at `depth`: 1 below `from` (the hip), easing (smoothstep) down to `slow` at `full` and deeper.
function Wading.scale(depth: number, from: number, full: number, slow: number): number
	if depth <= from then
		return 1
	end
	local t = if full > from then math.clamp((depth - from) / (full - from), 0, 1) else 1
	t = t * t * (3 - 2 * t)
	return 1 + (slow - 1) * t
end

-- One step of `x` toward `target` at `rate` per second (exponential: gentle in and out, never past the target).
function Wading.ease(x: number, target: number, rate: number, dt: number): number
	return target + (x - target) * math.exp(-rate * math.max(dt, 0))
end

-- The buoyancy (studs^3 of water pushed aside) of a box part `height` tall centred at `centerY` with `volume`, the
-- water's surface at `surfaceY`: the share of it under the surface.
function Wading.submerged(volume: number, centerY: number, height: number, surfaceY: number): number
	if height <= 0 then
		return if centerY < surfaceY then volume else 0
	end
	return volume * math.clamp((surfaceY - (centerY - height / 2)) / height, 0, 1)
end

return Wading
