--!strict
-- The camera (src/client/WeaponCamera; user 2026-10-11). Data only.
-- A weapon in the hands is always first person (user 2026-10-12: the third-person shoulder camera is gone), except the
-- staff (ThirdPersonClasses, user 2026-10-16: a third-person orbit, Staff below). In first person the
-- body is hidden and the viewmodel plays the first-person holds (src/client/Viewmodel); right mouse aims down the
-- sights. Without a weapon Roblox's own camera runs, out to FreeMaxZoom = StarterPlayer.CameraMaxZoomDistance
-- (default.project.json, tests/project.spec); putting a weapon away hands it back at the zoom it had.

local Camera = {
	FreeMaxZoom = 10.5, -- no weapon in the hands: Roblox's camera zooms out this far (user 2026-10-11)

	Sensitivity = 0.4, -- degrees of turn per pixel of mouse movement
	AimSensitivity = 0.6, -- share of that while aiming down the sights
	PitchLimit = 80, -- degrees up and down

	Fov = 70,
	AimFov = 50,
	Ease = 14, -- how fast the FOV follows (per second)
	-- drawing a weapon: the camera glides in from Roblox's camera to the eye over this long, as long as the
	-- first-person aim-in (0.3 s, Config/Weapons firstPerson.aimIn)
	AimBlend = 0.3,
	-- putting it away (after its unequip animation, Config/Locomotion.Stow): the camera glides back out from the eye to
	-- Roblox's camera at the zoom it had over this long, the body fading back in (user 2026-10-14: "smoothly go back to
	-- where my camera was")
	LeaveBlend = 0.4,
	AimEase = 9, -- how fast the FOV narrows into the sights (per second; ~0.33 s)
	ViewmodelFade = 0.35, -- first-person holds crossfade (ready / carry / aim): their poses are far apart, a quick
	-- swap looked choppy going into and out of a sprint

	-- First person, not aiming (user 2026-10-12: hip fire should go about where the screen centre is when standing
	-- still): the first-person rifle is turned so its barrel meets the centre line this many studs out; sway still
	-- moves it on top. Aiming down the sights is exact and takes no turn. HipEase: how fast the turn follows (per s).
	-- At the rifles' effective range (Metrics.Combat.RifleEffectiveRange): the barrel runs nearly parallel to the view,
	-- so a hip shot lands within the muzzle's offset (~0.3 stud right and below) of the centre at every range. (At 40
	-- the line crossed the centre there and went on up-left: ~3.5 studs high-left at 450, user 2026-10-12.)
	HipConverge = 450,
	HipEase = 10,
	-- At the hip the first-person rifle sits this far from where the ready hold puts it (studs: right, up, back from the
	-- eye; user 2026-10-13: get the bolt in frame): forward, up and a little left, so the top of the action (the bolt
	-- body and cocking piece, sliding back when worked) shows at the bottom right above the right hand. The handle
	-- itself sits in the R6 hand on the wrist, so more lift only brings the arm up over the view. The barrel still meets
	-- the centre line at HipConverge. Eased in and out with HipEase.
	HipShift = { -0.06, 0.14, -0.25 },

	-- First person: the eye in the Head's space (the R6 head is 1.25 big; front face at -0.6). The viewmodel's torso
	-- sits where the eye is (0, 1.65, -0.45) from it, as in tools/animation/rifle.luau EYE.
	Eye = { 0, 0.15, -0.45 },

	-- Gliding in, the body fades as the camera nears the head: clear beyond FadeFar, FadeMax at FadeNear.
	FadeFar = 5,
	FadeNear = 2.5,
	FadeMax = 0.75,
	-- Gliding in: over the last stretch the viewmodel fades in (and the body out) between `far` and `near` studs from the head; the head itself fades out between headFar and headNear, so
	-- it never fills the view (user 2026-10-11: ADS looked choppy). The eye is ~0.47 from the head's centre.
	Handover = { far = 2.5, near = 0.6, headFar = 4.5, headNear = 3 },

	-- The staff is exempt from "a weapon in the hands is always first person" (user 2026-10-16): with a weapon of one of
	-- these classes (Config/Weapons `class`) the camera orbits behind the body, mouse locked to the centre and the body
	-- turning with it, no crosshair (spells leave toward the screen centre, src/client/StaffAttack). Rules/Camera.
	ThirdPersonClasses = { Staff = true },
	Staff = {
		-- zoom (studs from the head): drawn, Roblox's zoom clamped into MinZoom..MaxZoom (closer than MinZoom: first
		-- person); the mouse wheel steps it by ZoomStep, and stepping in past MinZoom goes to first person (the first-person
		-- staff, as before), out of it back to MinZoom. Lower than FreeMaxZoom (user 2026-10-16).
		MaxZoom = 6,
		MinZoom = 1.5,
		ZoomStep = 1,
		-- aiming (right mouse): closer and narrower, still third person
		AimZoom = 3.5,
		AimFov = 60,
		-- over the right shoulder while firing (user 2026-10-16): aiming, charging, and for ShoulderHold seconds after a
		-- click; centred behind the head otherwise. Studs right and up, in the view's axes.
		Shoulder = { 1.6, 0.35 },
		ShoulderHold = 1.2,
		ZoomEase = 10, -- how fast the distance follows (per second)
		ShoulderEase = 8,
		-- walls: a sphere this big is swept from the head out to the camera, which stops where it hits (snapping in,
		-- easing back out with ZoomEase)
		Radius = 0.4,
		-- the body (head included) fades as the camera closes in: clear beyond `far`, gone at `near` (studs from the head)
		Fade = { far = 2, near = 0.75 },
	},

	-- Third person, local only: the weapon follows the camera's pitch. The torso tilts a little
	-- (Config/Locomotion.LookTilt) and the arms with the gun turn about the shoulder line for the rest: share of the
	-- pitch the gun follows per hold, and the head's share.
	Follow = { ready = 1, carry = 0.3, aim = 1 },
	HeadFollow = 0.6,
}

return table.freeze(Camera)
