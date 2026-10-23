--!strict
-- How hard the camera shakes (Config/CameraShake; src/client/CameraShake applies it). Pure: numbers only.

local CameraShake = {}

-- a kick of `size` degrees at its source, at `distance` studs: dying away squared to nothing at `reach`
function CameraShake.falloff(size: number, reach: number, distance: number): number
	if reach <= 0 or distance >= reach then
		return 0
	end
	return size * (1 - math.max(distance, 0) / reach) ^ 2
end

-- a `kg` charge's kick (degrees) at `distance` studs: its size and reach grow by the charge's cube root
function CameraShake.blast(kg: number, distance: number, cfg: { size: number, reach: number }): number
	if kg <= 0 then
		return 0
	end
	local k = kg ^ (1 / 3)
	return CameraShake.falloff(cfg.size * k, cfg.reach * k, distance)
end

-- a kick's size `t` s after it, dying away squared over `time` s; nil once it is over
function CameraShake.decay(size: number, t: number, time: number): number?
	if t > time then
		return nil
	end
	return size * (1 - math.max(t, 0) / time) ^ 2
end

-- the charge (kg) a staff stage's blast shakes the camera as
function CameraShake.stageKg(stage: number, stages: { number }): number
	return stages[math.clamp(math.round(stage), 1, #stages)]
end

return CameraShake
