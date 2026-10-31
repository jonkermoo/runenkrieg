--!strict
-- The capture-point flagpoles (Config/Flagpole; src/server/Flagpoles, src/client/Flagpoles): where the flag stands for
-- a sector's control, the stakes and sandbags round a point, the cloth's flap, and what jolts it. Pure: numbers only.
-- Control runs from 1 (West holds the sector) to -1 (East holds it), as in src/server/Frontline.

local Flagpole = {}

-- Whose flag flies and how far up (0 bottom .. 1 top): the side the control leans to, as far as it goes; none at 0.
function Flagpole.flag(control: number): (string?, number)
	local share = math.clamp(math.abs(control), 0, 1)
	if share <= 0 then
		return nil, 0
	end
	return if control > 0 then "West" else "East", share
end

-- The flag's top over the pole's foot for a height share: from `bottomGap` + the flag's height (lowest) up to the pole's
-- top less `topGap` (full control).
function Flagpole.top(share: number, poleHeight: number, flagHeight: number, cfg: any): number
	local lo = cfg.bottomGap + flagHeight
	local hi = poleHeight - cfg.topGap
	return lo + (hi - lo) * math.clamp(share, 0, 1)
end

-- Angles (radians) round a circle of `radius` for things every `spacing` studs along it (at least 3), evenly spread.
function Flagpole.ring(radius: number, spacing: number): { number }
	local n = math.max(3, math.floor(2 * math.pi * radius / spacing + 0.5))
	local out = table.create(n)
	for i = 0, n - 1 do
		out[i + 1] = 2 * math.pi * i / n
	end
	return out
end

-- The wind's strength (0 .. 1.5) and its direction on the ground (unit x, z), GlobalWind's or the default when calm.
function Flagpole.wind(wx: number, wz: number, cfg: any): (number, number, number)
	local speed = math.sqrt(wx * wx + wz * wz)
	if speed < 1e-3 then
		wx, wz = cfg.DefaultWind.x, cfg.DefaultWind.z
		speed = math.sqrt(wx * wx + wz * wz)
	end
	return math.clamp(speed / cfg.WindReference, 0, 1.5), wx / speed, wz / speed
end

-- Strip `i` (1 at the hoist .. n at the free edge)'s turn from the one before it (degrees, about the vertical) at time
-- `t`: a wave travelling out to the free edge, bigger toward it, with the wind's strength; harder while contested.
function Flagpole.flap(i: number, n: number, t: number, strength: number, contested: boolean, cfg: any): number
	local k = if contested then cfg.contested else 1
	local speed = math.max(cfg.minSpeed, cfg.speed * strength) * k
	local amp = cfg.amplitude * (0.35 + 0.65 * strength) * k * (i / n)
	return amp * math.sin(t * speed - i * cfg.wave)
end

-- How far the flag hangs down the pole (degrees from flying straight out), more in a lighter wind.
function Flagpole.droop(strength: number, cfg: any): number
	return 90 * cfg.droop * math.clamp(1 - strength, 0, 1)
end

-- The distance from point p to the segment a..b.
function Flagpole.toSegment(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	px: number,
	py: number,
	pz: number
): number
	local dx, dy, dz = bx - ax, by - ay, bz - az
	local len2 = dx * dx + dy * dy + dz * dz
	local u = if len2 > 0 then math.clamp(((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cy, cz = ax + dx * u - px, ay + dy * u - py, az + dz * u - pz
	return math.sqrt(cx * cx + cy * cy + cz * cz)
end

-- A blast of `kg` at `distance`: how hard it whips the flag (degrees, 0 out of reach).
function Flagpole.whip(kg: number, distance: number, cfg: any): number
	if distance >= cfg.radius then
		return 0
	end
	return math.min(cfg.maxDegrees, kg * cfg.perKg * (1 - distance / cfg.radius))
end

-- How often a flag `distance` from the camera moves: every frame (0) near, every farStep out to far, nil frozen beyond.
function Flagpole.step(distance: number, cfg: any): number?
	if distance <= cfg.near then
		return 0
	elseif distance <= cfg.far then
		return cfg.farStep
	end
	return nil
end

-- A value eased toward `target` at `rate` per second over `dt`.
function Flagpole.ease(value: number, target: number, rate: number, dt: number): number
	return target + (value - target) * math.exp(-rate * dt)
end

return Flagpole
