--!strict
-- Pure math for tree sway: idle wind tilt and a damped 2D spring for explosion response.
-- A tilt is a vector (x, z) in radians: the direction the tree leans, with magnitude = lean angle.

local TreeSway = {}

export type Spring = { x: number, z: number, vx: number, vz: number }

function TreeSway.newSpring(): Spring
	return { x = 0, z = 0, vx = 0, vz = 0 }
end

-- Wind strength (0..~1.5) and unit direction from a wind vector.
function TreeSway.wind(wx: number, wz: number, cfg: any): (number, number, number)
	local speed = math.sqrt(wx * wx + wz * wz)
	if speed < 1e-3 then
		wx, wz = cfg.DefaultWind.x, cfg.DefaultWind.z
		speed = math.sqrt(wx * wx + wz * wz)
	end
	return math.clamp(speed / cfg.WindReference, 0, 1.5), wx / speed, wz / speed
end

-- Idle wind tilt for one part of a tree at (px, pz) at time t.
function TreeSway.idleTilt(
	t: number,
	px: number,
	pz: number,
	strength: number,
	dx: number,
	dz: number,
	part: any,
	gust: any
): (number, number)
	local amp = math.rad(part.amp) * strength
	-- phase travels downwind so gusts roll across the forest; a small per-tree offset breaks lockstep
	local along = (px * dx + pz * dz) / gust.waveLength * 2 * math.pi
	local jitter = (px * 0.37 + pz * 0.61) % 1 * 0.8
	local main = 0.65 * math.sin(2 * math.pi * gust.slowFreq * t - along + jitter)
		+ 0.35 * math.sin(2 * math.pi * gust.fastFreq * t - along * 1.7 + jitter * 2.3)
	local side = gust.cross * math.sin(2 * math.pi * gust.slowFreq * 0.77 * t + jitter * 4.1)
	local a = amp * (gust.lean + main)
	local s = amp * side
	return dx * a - dz * s, dz * a + dx * s
end

-- Semi-implicit Euler step of a damped spring toward zero. dt is clamped for stability.
function TreeSway.step(s: Spring, k: number, c: number, dt: number)
	dt = math.min(dt, 1 / 20)
	s.vx += (-k * s.x - c * s.vx) * dt
	s.vz += (-k * s.z - c * s.vz) * dt
	s.x += s.vx * dt
	s.z += s.vz * dt
end

function TreeSway.clamp(s: Spring, maxRad: number)
	local m = math.sqrt(s.x * s.x + s.z * s.z)
	if m > maxRad then
		s.x, s.z = s.x / m * maxRad, s.z / m * maxRad
		-- kill outward velocity so it doesn't pile up against the limit
		local out = (s.vx * s.x + s.vz * s.z) / (maxRad * maxRad)
		if out > 0 then
			s.vx -= s.x * out
			s.vz -= s.z * out
		end
	end
end

function TreeSway.asleep(s: Spring, eps: number): boolean
	return math.abs(s.x) < eps and math.abs(s.z) < eps and math.abs(s.vx) < eps * 10 and math.abs(s.vz) < eps * 10
end

-- Blast falloff: 1 at the center, 0 at the radius, quadratic.
function TreeSway.falloff(d: number, radius: number): number
	if d >= radius then
		return 0
	end
	local f = 1 - d / radius
	return f * f
end

-- Kick a spring away from a blast at (ex, ez). Angular velocity in rad/s.
function TreeSway.kick(s: Spring, px: number, pz: number, ex: number, ez: number, radius: number, kickRad: number)
	local dx, dz = px - ex, pz - ez
	local d = math.sqrt(dx * dx + dz * dz)
	local f = TreeSway.falloff(d, radius)
	if f <= 0 then
		return
	end
	if d < 1e-3 then
		dx, dz, d = 1, 0, 1
	end
	s.vx += dx / d * kickRad * f
	s.vz += dz / d * kickRad * f
end

return TreeSway
