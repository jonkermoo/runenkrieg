--!strict
-- The camera (src/client/WeaponCamera; user 2026-10-11). Data only.
-- One zoom range everywhere: MaxZoom is also StarterPlayer.CameraMaxZoomDistance (default.project.json,
-- tests/project.spec), so Roblox's own camera (no weapon in the hands) stops at the same distance.
-- With a weapon in the hands the camera sits over the right shoulder (Metrics.Camera.ShoulderOffset) at the selected
-- zoom, the body turning with it. Equipping keeps the zoom you had. Zoomed all the way in is first person: the body
-- is hidden and the viewmodel plays the first-person holds (src/client/Viewmodel). Aiming down the sights (right
-- mouse) is always first person. Out of first person the body fades translucent as the camera comes near it
-- (zooming in, or a wall pulling the camera in).

local Camera = {
	MaxZoom = 20, -- studs from the head, everywhere (was the rifle's free-orbit limit)
	MinZoom = 2, -- the nearest third-person zoom; one more wheel step in is first person
	ZoomStep = 0.8, -- each wheel step multiplies the distance by this (in) or divides by it (out)
	FirstBelow = 1, -- Roblox's camera nearer than this (studs) counts as first person when a weapon is equipped

	Sensitivity = 0.4, -- degrees of turn per pixel of mouse movement
	AimSensitivity = 0.6, -- share of that while aiming down the sights
	PitchLimit = 80, -- degrees up and down

	Fov = 70,
	AimFov = 50,
	Ease = 14, -- how fast the zoom and the FOV follow (per second)
	Blend = 0.15, -- seconds to move between first and third person (or into the sights)

	-- First person: the eye in the Head's space (the R6 head is 1.25 big; front face at -0.6). The viewmodel's torso
	-- sits where the eye is (0, 1.65, -0.45) from it, as in tools/animation/rifle.luau EYE.
	Eye = { 0, 0.15, -0.45 },

	CollisionMargin = 0.4, -- the camera stops this far in front of a wall between it and the head

	-- Out of first person the body fades as the camera nears the head: clear beyond FadeFar, FadeMax at FadeNear.
	FadeFar = 5,
	FadeNear = 2.5,
	FadeMax = 0.75,

	-- Third person, local only: the weapon follows the camera's pitch. The torso tilts a little
	-- (Config/Locomotion.LookTilt) and the arms with the gun turn about the shoulder line for the rest: share of the
	-- pitch the gun follows per hold, and the head's share.
	Follow = { ready = 1, carry = 0.3, aim = 1 },
	HeadFollow = 0.6,
}

return table.freeze(Camera)
