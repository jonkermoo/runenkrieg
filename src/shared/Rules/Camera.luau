--!strict
-- The weapon camera's rules (Config/Camera, src/client/WeaponCamera, src/client/BodyTurn): the staff's third person,
-- the gun's wheel zoom, the body's turn toward the view and the spring everything eases on. Pure: distances in studs,
-- angles in degrees.

local Camera = {}

export type Staff = {
	Distance: number,
	AimZoom: number,
	ShoulderHold: number,
}

-- Whether a weapon class gets the third-person camera.
function Camera.thirdPerson(classes: { [string]: boolean }, class: string?): boolean
	return class ~= nil and classes[class] == true
end

-- Where the camera heads: the fixed distance, closer while aiming (never further out).
function Camera.target(cfg: Staff, aiming: boolean): number
	return if aiming then math.min(cfg.Distance, cfg.AimZoom) else cfg.Distance
end

-- Over the right shoulder while firing: aiming, charging, or within ShoulderHold seconds of a click.
function Camera.shoulder(cfg: Staff, aiming: boolean, casting: boolean, sinceClick: number): boolean
	return aiming or casting or (sinceClick >= 0 and sinceClick < cfg.ShoulderHold)
end

export type Gun = { MinZoom: number, MaxZoom: number, Step: number, FirstBelow: number }

-- A gun's distance (0: first person) after one wheel notch: `notches` > 0 zooms in. One notch in from MinZoom is first
-- person, one out of first person is MinZoom.
function Camera.wheel(cfg: Gun, distance: number, notches: number): number
	if notches > 0 then
		return if distance <= cfg.MinZoom + 1e-6 then 0 else math.max(cfg.MinZoom, distance - cfg.Step)
	elseif notches < 0 then
		return if distance <= 0 then cfg.MinZoom else math.min(cfg.MaxZoom, distance + cfg.Step)
	end
	return distance
end

-- The gun's starting distance from Roblox's camera zoom when it is drawn (first person stays first person).
function Camera.drawn(cfg: Gun, zoom: number): number
	return if zoom < cfg.FirstBelow then 0 else math.clamp(zoom, cfg.MinZoom, cfg.MaxZoom)
end

-- Where a gun's camera heads: first person while aiming, else the distance chosen. `inPlace` (Config/Camera.AimInPlace,
-- the staff): aiming keeps the distance chosen.
function Camera.gunTarget(distance: number, aiming: boolean, inPlace: boolean?): number
	return if aiming and not inPlace then 0 else distance
end

-- The gun camera's view ("CameraMode"): first person, over the shoulder ("Third"), aimed in first person ("Aim"), or
-- aimed over the shoulder by a class that aims in place ("ThirdAim").
function Camera.gunView(distance: number, aiming: boolean, inPlace: boolean?): string
	if aiming then
		return if inPlace and distance > 0 then "ThirdAim" else "Aim"
	end
	return if distance > 0 then "Third" else "First"
end

-- An angle brought into -180..180.
function Camera.wrap(angle: number): number
	return (angle + 180) % 360 - 180
end

-- The body's facing to turn toward with a gun in third person (body, look, heading: yaw in degrees), and whether it
-- is catching up. Moving (`heading`, the walk direction; user 2026-10-20: "while running, the torso should follow
-- where the player is directing"), the body faces where it goes, and once it stops it turns to the view. Standing,
-- the head turns first, up to headMax; past that, or when engaged (just fired), the body turns to face the view, and
-- keeps turning until within settle degrees. Firing faces the view even on the move. The target is unwrapped near
-- `body`.
function Camera.bodyTarget(
	body: number,
	look: number,
	headMax: number,
	settle: number,
	engaged: boolean,
	catching: boolean,
	heading: number?
): (number, boolean)
	if heading and not engaged then
		return body + Camera.wrap(heading - body), true -- (stopping: on to the view)
	end
	local d = Camera.wrap(look - body)
	if engaged or math.abs(d) > headMax then
		catching = true
	elseif catching and math.abs(d) < settle then
		catching = false
	end
	return if catching then body + d else body, catching
end

-- One step of a critically damped spring from x (velocity v) toward target at `rate` per second: never a jump in
-- position or speed, no overshoot. Returns the new position and velocity.
function Camera.spring(x: number, v: number, target: number, rate: number, dt: number): (number, number)
	local d = x - target
	local e = math.exp(-rate * dt)
	local k = (v + rate * d) * dt
	return target + (d + k) * e, (v - rate * k) * e
end

return Camera
