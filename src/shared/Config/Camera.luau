--!strict
-- The camera (src/client/WeaponCamera; user 2026-10-11). Data only.
-- Zoom (user 2026-10-11, from their screenshots): the shoulder camera (a weapon in the hands) goes out to MaxZoom;
-- Roblox's own camera (no weapon) a few studs further, to FreeMaxZoom = StarterPlayer.CameraMaxZoomDistance
-- (default.project.json, tests/project.spec). Drawing a weapon from further out brings the camera in to MaxZoom.
-- With a weapon in the hands the camera sits over the right shoulder (Metrics.Camera.ShoulderOffset) at the selected
-- zoom, the body turning with it. Equipping keeps the zoom you had. Zoomed all the way in is first person: the body
-- is hidden and the viewmodel plays the first-person holds (src/client/Viewmodel). Aiming down the sights (right
-- mouse) is always first person. Out of first person the body fades translucent as the camera comes near it
-- (zooming in, or a wall pulling the camera in).

local Camera = {
	MaxZoom = 7.5, -- studs from the head, weapon in the hands (user 2026-10-11: their screenshot, measured)
	FreeMaxZoom = 10.5, -- no weapon in the hands: a few studs further out (user 2026-10-11)
	MinZoom = 2, -- the nearest third-person zoom; one more wheel step in is first person
	ZoomStep = 0.8, -- each wheel step multiplies the distance by this (in) or divides by it (out)
	FirstBelow = 1, -- Roblox's camera nearer than this (studs) counts as first person when a weapon is equipped

	Sensitivity = 0.4, -- degrees of turn per pixel of mouse movement
	AimSensitivity = 0.6, -- share of that while aiming down the sights
	PitchLimit = 80, -- degrees up and down

	Fov = 70,
	AimFov = 50,
	Ease = 14, -- how fast the zoom and the FOV follow (per second)
	Blend = 0.15, -- seconds to move between first and third person
	-- into (and out of) the sights from the shoulder: the camera glides in over the shoulder while the body raises
	-- the rifle, as long as the first-person aim-in (0.3 s, Config/Weapons firstPerson.aimIn) (user 2026-10-11: ADS
	-- too snappy)
	AimBlend = 0.3,
	AimEase = 9, -- how fast the FOV narrows into the sights (per second; ~0.33 s)
	ViewmodelFade = 0.35, -- first-person holds crossfade (ready / carry / aim): their poses are far apart, a quick
	-- swap looked choppy going into and out of a sprint

	-- First person: the eye in the Head's space (the R6 head is 1.25 big; front face at -0.6). The viewmodel's torso
	-- sits where the eye is (0, 1.65, -0.45) from it, as in tools/animation/rifle.luau EYE.
	Eye = { 0, 0.15, -0.45 },

	CollisionMargin = 0.4, -- the camera stops this far in front of a wall between it and the head

	-- Out of first person the body fades as the camera nears the head: clear beyond FadeFar, FadeMax at FadeNear.
	FadeFar = 5,
	FadeNear = 2.5,
	FadeMax = 0.75,
	-- Gliding into first person or the sights (and out): over the last stretch the viewmodel fades in (and the body
	-- out) between `far` and `near` studs from the head; the head itself fades out between headFar and headNear, so
	-- it never fills the view (user 2026-10-11: ADS looked choppy). The eye is ~0.47 from the head's centre.
	Handover = { far = 2.5, near = 0.6, headFar = 4.5, headNear = 3 },

	-- Third person, local only: the weapon follows the camera's pitch. The torso tilts a little
	-- (Config/Locomotion.LookTilt) and the arms with the gun turn about the shoulder line for the rest: share of the
	-- pitch the gun follows per hold, and the head's share.
	Follow = { ready = 1, carry = 0.3, aim = 1 },
	HeadFollow = 0.6,
}

return table.freeze(Camera)
