--!strict
-- The staff's third-person camera (Config/Camera.Staff, src/client/WeaponCamera). Pure: distances in studs, 0 means
-- first person.

local Camera = {}

export type Staff = {
	MaxZoom: number,
	MinZoom: number,
	ZoomStep: number,
	AimZoom: number,
	ShoulderHold: number,
}

-- Whether a weapon class gets the third-person camera.
function Camera.thirdPerson(classes: { [string]: boolean }, class: string?): boolean
	return class ~= nil and classes[class] == true
end

-- The distance on drawing: Roblox's zoom clamped into the staff's range; closer than MinZoom stays first person.
function Camera.start(cfg: Staff, robloxZoom: number): number
	if robloxZoom < cfg.MinZoom then
		return 0
	end
	return math.min(robloxZoom, cfg.MaxZoom)
end

-- The distance after `notches` of the mouse wheel (positive: in). In past MinZoom goes to first person; out of first
-- person lands on MinZoom.
function Camera.zoom(cfg: Staff, distance: number, notches: number): number
	if notches == 0 then
		return distance
	end
	if distance <= 0 then
		return if notches < 0 then cfg.MinZoom else 0
	end
	local d = distance - notches * cfg.ZoomStep
	if d < cfg.MinZoom - 1e-6 then
		return 0
	end
	return math.min(d, cfg.MaxZoom)
end

-- Where the camera heads: aiming brings it in to AimZoom (never out); first person stays first person.
function Camera.target(cfg: Staff, distance: number, aiming: boolean): number
	if distance <= 0 then
		return 0
	end
	return if aiming then math.min(distance, cfg.AimZoom) else distance
end

-- Over the right shoulder while firing: aiming, charging, or within ShoulderHold seconds of a click.
function Camera.shoulder(cfg: Staff, aiming: boolean, casting: boolean, sinceClick: number): boolean
	return aiming or casting or (sinceClick >= 0 and sinceClick < cfg.ShoulderHold)
end

return Camera
