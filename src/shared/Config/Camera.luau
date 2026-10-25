--!strict
-- The camera (src/client/WeaponCamera; user 2026-10-11). Data only.
-- A gun in the hands is first person or over the shoulder by the mouse wheel, aiming always first person (user
-- 2026-10-20, Gun below; from 2026-10-12 it was always first person); the staff is third person only
-- (ThirdPersonClasses, user 2026-10-16, Staff below). In first person the
-- body is hidden and the viewmodel plays the first-person holds (src/client/Viewmodel); right mouse aims down the
-- sights. Without a weapon Roblox's own camera runs, out to FreeMaxZoom = StarterPlayer.CameraMaxZoomDistance
-- (default.project.json, tests/project.spec); putting a weapon away hands it back at the zoom it had.

local Camera = {
	-- no weapon in the hands (and the shovel, FreeClasses): Roblox's camera zooms out this far (user 2026-10-25, from
	-- their screenshot: "make unequipped / shovel this zoom max zoom
	-- angle"; it was 10.5 from 2026-10-11)
	FreeMaxZoom = 9,
	-- Classes (Config/Weapons `class`) that keep Roblox's own camera, as with empty hands (user 2026-10-24: "make it so
	-- your camera doesnt get locked with a shovel out"; the design's
	-- option A): a free cursor, right drag turns, the wheel zooms from FreeMinZoom out (third person only: the
	-- first-person holds belong to the weapon camera's viewmodel). src/client/Build aims at the cursor with one.
	FreeClasses = { Shovel = true },
	FreeMinZoom = 4,

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
	-- under the aim-in / aim-out (which covers it) the hold left behind fades out over this share of what is left of it
	AimHandoff = 0.8,
	-- the first-person arms' thickness (studs; R6's is 1): slimmer, like a real forearm beside the rifle, as the hand
	-- works close to the eye (user 2026-10-19: the reload's forearm too big). Their length (2) and joints stay R6's, so
	-- the hands land where the animations put them. Others see the normal arms.
	ViewmodelArmWidth = 0.7,

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
	-- the centre line at HipConverge. Eased in and out with HipEase. Lowered 0.12 (user 2026-10-19: the hand lower; was
	-- 0.14 up): the turn keeps the barrel on its line, so the rifle's rear and the hand drop, the muzzle hardly moves.
	HipShift = { -0.06, 0.02, -0.25 },
	-- A wider field of view (the player's setting) shrinks the rifle toward the centre and brings the forearm into the
	-- bottom right (user 2026-10-19: "account for high FOV players"). At the hip the rig moves by `shift` (right, up,
	-- back from the eye) at `at` degrees, by the share tan(fov / 2) has grown from Fov's toward `at`'s (none at Fov or
	-- below), so FOV 90 frames like 70 (checked in offline renders, tools/animation/vmrender.py)
	WideFov = { at = 90, shift = { 0.05, -0.1, 0.2 } },

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
	-- turning with it, no crosshair (spells leave toward the screen centre, src/client/StaffAttack). No first person and
	-- no zooming with them (user 2026-10-16: "first person is disabled completely and the camera is locked").
	-- Rules/Camera.
	-- (empty since 2026-10-21: the staff takes the gun's camera, user: "provide the same third person crosshair and
	-- rules for the staff. override how the staff camera currently behaves and have it the same as the rifle (besides
	-- first person ADS forced)"; see AimInPlace)
	ThirdPersonClasses = {},
	Staff = {
		-- the camera's distance behind the head (studs), fixed: lower than FreeMaxZoom (user 2026-10-16)
		Distance = 6,
		-- coming out of the eye (switching from a gun): over this first stretch the camera moves from the eye to behind
		-- the head
		EyeBlend = 1.5,
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
		Fade = { far = 3, near = 0.75 }, -- (far was 2: backed against a wall at ~1.9 the head filled the view, 2026-10-16)
		-- aimed (right mouse) over the shoulder, the whole body (with the staff) goes this see-through for the player, so
		-- the head and raised arm don't hide the screen centre where the circles and the shot are (user 2026-10-16: "when
		-- we are in the shoulder cam, make us translucent"); others see it whole. Fades in with the shoulder slide; solid
		-- again at once when aiming ends (user 2026-10-16: "instantly be back to full opacity once we let go of right
		-- click"), and never after a hip click.
		ShoulderVeil = 0.6,
	},

	-- A gun in the hands (user 2026-10-20: "allow third person while holding the gun, only forced first person while
	-- ADS"): the mouse wheel steps the camera between first person and a third-person view over the right shoulder;
	-- aiming down the sights always glides into first person and back out to the distance chosen. Drawing keeps the
	-- view Roblox's camera had (first person under FirstBelow studs, else its zoom within MinZoom..MaxZoom); putting the
	-- gun away hands the chosen distance back. Rules/Camera.wheel.
	Gun = {
		MinZoom = 2, -- the nearest third-person distance (studs behind the head); one notch in from here is first person
		-- the furthest (user 2026-10-25, from their screenshot: "make equipped weapon this"; it was 7.5, the old
		-- shoulder camera's)
		MaxZoom = 4.5,
		Step = 1, -- studs per wheel notch
		FirstBelow = 1, -- Roblox's camera nearer than this when the gun is drawn: start in first person
		Shoulder = { 1.6, 0.35 }, -- studs right and up, in the view's axes, so the head never covers the crosshair
		EyeBlend = 1.5, -- over this first stretch out of the eye the camera moves from the eye to behind the head
		-- the distance follows a critically damped spring at this rate (per second; never a jump, user 2026-10-20:
		-- "make movement always smooth and never snappy"): ~0.4 s from first person out to MaxZoom
		Spring = 12,
		-- the body (head included) fades only right at the head: clear beyond `far`, gone at `near` (studs from the head),
		-- the same in third person and gliding into first, in Steps levels (fewer writes)
		Fade = { far = 1.8, near = 0.7, Steps = 20 },
	},
	-- Classes (Config/Weapons `class`) that take the gun's camera but aim where the view is (user 2026-10-21: the staff
	-- "the same as the rifle (besides first person ADS forced)"): aiming over the shoulder stays over the shoulder
	-- ("ThirdAim", the narrower Staff.AimFov, the crosshair still shown); aiming in first person is first person.
	AimInPlace = { Staff = true },
	-- Turning the body (src/client/BodyTurn; user 2026-10-20), each a critically damped spring rate (per second):
	-- - a gun in third person, first person, aiming and the staff: the body faces the view (Face: fast, so others see
	--   it turn, not jump; user 2026-10-20: "make the gun always aim towards your general crosshair in third person",
	--   which replaced the earlier walk-facing and head-first rule, Rules/Camera.bodyTarget, kept with Settle);
	-- - nothing in the hands: the body turns to where it walks (Walk; or to the view in Roblox's first person / mouse
	--   lock).
	Turn = {
		Face = 20,
		Walk = 10,
		Settle = 5,
		Moving = 0.1, -- share of MoveDirection that counts as moving
		FirstBelow = 1, -- nothing in the hands: Roblox's camera nearer the head than this (studs) is its first person
		Still = 0.01, -- degrees (and degrees per second) under which the body is left alone, not rewritten
	},
	-- The third-person crosshair (src/client/Crosshair; user 2026-10-20: "small hollow circle (not dot) that can be
	-- disabled in settings"): only with a gun in third person at the hip, never in first person, aiming or with the
	-- staff; Config/Settings "Crosshair". Pixels at the screen centre; fades in and out at Fade per second.
	-- The dark edge under the ring: EdgeWidth pixels wider, at EdgeShare of the ring's opacity.
	Crosshair = {
		Size = 14,
		Thickness = 1.5,
		Transparency = 0.15,
		Fade = 12,
		EdgeWidth = 2,
		EdgeShare = 0.6,
		Hidden = 0.01,
	},

	-- Third person, local only: the weapon follows the camera's pitch. The torso tilts a little
	-- (Config/Locomotion.LookTilt) and the arms with the gun turn about the shoulder line for the rest: share of the
	-- pitch the gun follows per hold, and the head's share.
	Follow = { ready = 1, carry = 0.3, aim = 1, tuck = 0.3 },
	HeadFollow = 0.6,

	-- Third person: the weapon points at the crosshair (user 2026-10-21: "make the player's gun still aim towards your
	-- crosshair while in third person ... (keep the same sway rules)"; src/client/LookTilt, Rules/LookTilt.aimTurn). On
	-- top of Follow, the weapon turns about the right shoulder so the barrel (the staff's head) meets the point under
	-- the crosshair, and each arm turns about its own shoulder to keep its hand on it (user 2026-10-21: "make it so the
	-- arms move the gun where it aims. it looks really snappy and unnatural"), on a spring (Spring). The animation's own
	-- motion of the weapon (breath, stride, recoil) still plays around that line: the turn is taken from where the
	-- animation points on average (Settle per second), not frame by frame. Other players see the same turn (Net
	-- "LookPitch").
	Aim3P = {
		Modes = { Third = true, ThirdAim = true }, -- the views it works in ("ThirdAim": the staff aimed)
		States = { ready = 1, aim = 1, carry = 0 }, -- its share per hold (none while sprinting)
		Ease = 10, -- how fast that share follows (per second)
		Fallback = 450, -- the crosshair over nothing: a point this far out (HipConverge)
		-- the crosshair over something nearer than this past the weapon (studs): pointed at this far instead, so a wall
		-- at the muzzle never swings the weapon round
		MinDistance = 6,
		DistanceEase = 8, -- how fast the point's distance follows the crosshair (per second; never a snap)
		Settle = 2, -- how fast the animation's average pointing is followed (per second)
		-- the turn follows a critically damped spring at this rate (per second; Rules/Camera.spring): a flick of the
		-- mouse brings the arms round after the view, never in one frame
		Spring = 8,
		Max = { yaw = 25, pitch = 20 }, -- the largest turn (degrees)
	},
}

return table.freeze(Camera)
