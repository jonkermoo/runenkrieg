--!strict
-- The staff's third-person camera (Config/Camera.Staff, src/client/WeaponCamera). Pure: distances in studs.

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

return Camera
