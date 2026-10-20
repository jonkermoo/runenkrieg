--!strict
-- The global sway layer (docs/HOLD_AND_CAMERA_RULES.md §3; src/client/Sway). One motion state on the local client,
-- fed by several sources and read by the first-person viewmodel and the camera. Data only.
-- Amplitudes are degrees (half of peak to peak) unless noted. They come from the user's reference video
-- (HOLD_AND_CAMERA_RULES.md §8, measured 2026-10-11): there the camera barely moves and the first-person gun carries
-- nearly all the motion.
-- Every source is multiplied by Master, by the held item's class weight (Classes) where it says so, and while aiming
-- by the Aim shares.

local Sway = {
	Master = 1, -- everything at once (a player setting later)
	-- The first-person gun turns about this point (studs from the eye, camera space: +X right, +Y up, +Z back):
	-- below and a little behind the eye, about where the stock meets the shoulder, so the whole gun moves on screen.
	Pivot = { 0.2, -0.6, 0.3 },

	-- Weight W per item class (HOLD_AND_CAMERA_RULES.md §1; bolt rifle = 1). Scales stride sway, breath and look lag.
	Classes = {
		BoltRifle = 1.0,
		SemiRifle = 1.0, -- each its own over this (Config/Weapons `weight`, W2)
		AutoRifle = 1.0,
		Shotgun = 1.1,
		Sniper = 1.3,
		Pistol = 0.5,
		Grenade = 0.3,
		Potion = 0.3,
		Staff = 0.8,
		SpellBook = 0.4,
		Shovel = 0.6, -- docs/MILESTONES.md SV1
	},

	-- Steps: driven by the Footstep markers on the local walk / sprint cycles (the view lands with the feet). A stride
	-- is two steps. The first-person gun draws a figure 8: side to side once per stride, down at every step.
	-- Reference: walk side 17 deg p-p and down 3.4 deg p-p; sprint side ~28 and down ~4 deg p-p (on screen; `down` is
	-- smaller than half because the turn about Pivot moves the gun more than the angle itself: measured in play).
	Stride = {
		walk = { side = 8, down = 1, roll = 2 },
		sprint = { side = 11, down = 0.5, roll = 1.5 },
		WalkSpeed = 10, -- speeds the amplitudes are given at (Metrics.Movement); scaled linearly in between
		SprintSpeed = 16,
		Fade = 6, -- how fast the stride sway builds when starting to move (per second; a critically damped spring of the
		-- same quickness, so it starts gently: following at once jerked the gun on the first frame of a walk, user
		-- 2026-10-13)
		Return = 3, -- how fast it settles back when stopping (per second; ~1 s to the centre): slower, so the sights
		-- drift back to the crosshair instead of snapping (user 2026-10-11)
		Halt = 3, -- the stride's rhythm slows to a stop as the settling speed falls under this (studs/s)
		Settle = 4, -- how fast the stride works off its offset from the feet after a footstep (per second)
		-- that catch-up never speeds or slows the stride by more than this share of its rhythm, and comes in eased
		-- (NudgeEase, per second): applied at once it changed the sway's speed in one frame, a twitch at the first
		-- step after standing still and a small one at every step (user 2026-10-13)
		NudgeMax = 0.3,
		NudgeEase = 6,
		-- the stride's speed follows the cycle's at this rate (per second) instead of at once: walking backwards plays the
		-- cycle in reverse, and the sway reversed in one frame (user 2026-10-13)
		RateEase = 8,
	},

	-- Breath: always on, a slow loop. First person 3 s (user 2026-10-11: visible but minimal enough not to bother
	-- gameplay). Reference, aiming and standing still: ~0.5 deg of slow drift.
	Breath = { period = 3, pitch = 0.25, yaw = 0.2 },

	-- Look lag: the gun trails the view when turning, then springs back. Offset = -Gain x turn rate (deg per deg/s),
	-- capped; roll leans into the turn.
	LookLag = { gain = 0.02, max = 5, roll = 0.012, stiffness = 90, damping = 14 },

	-- Strafe: sideways speed (share of walk speed) cants the gun toward the side it moves and shifts it a little.
	Strafe = { roll = 6, shift = 0.08, stiffness = 60, damping = 12 },

	-- Jump (user 2026-10-11: jumping moves the gun, aiming too): a kick down at takeoff (the gun lags the body), then
	-- in the air the gun trails the vertical speed (rising: rides low; falling: floats up), `gain` deg per stud/s,
	-- capped; `drop` studs of shift per degree. The landing dip below finishes it.
	-- The jump is short (JumpHeight 2.7: ~0.3 s in the air), so the spring is quick enough to follow it.
	-- Twice the first numbers (user 2026-10-11: jumping must sway more than aim-walking, it was the other way round).
	Jump = { kick = 8, gain = 0.2, max = 8, drop = 0.006, stiffness = 90, damping = 12 },

	-- Landing: a dip proportional to the fall speed (studs/s), capped.
	Landing = { pitch = 0.12, drop = 0.006, max = 4, stiffness = 120, damping = 12 },

	-- Aiming down the sights: shares of each source (reference: side sway about a quarter, the step dip stays).
	Aim = { side = 0.25, down = 1, roll = 0.25, breath = 1, lag = 0.4, strafe = 0.3, jump = 1, landing = 1 },

	-- The camera's own small share (reference: walk pitch bob 0.19 deg p-p, roll 0.08; sprint ~0.15; aiming walk
	-- ~0.27 deg p-p), as amplitudes at the step, scaled by view.
	Camera = {
		walk = { pitch = 0.1, roll = 0.04 },
		sprint = { pitch = 0.08, roll = 0.03 },
		aim = { pitch = 0.13, roll = 0.02 },
		View = { First = 1, Aim = 1, Third = 1, ThirdAim = 1 }, -- the staff's third-person views too (Config/Camera.Staff)
	},

	-- Charging a staff spell (src/client/StaffAttack, Sway.shake; user 2026-10-13: "the crazier the camera swaying
	-- gets", at its peak once stage 3 is ready): a smooth wandering shake of the view and the staff, its size growing
	-- with the charge as level^grow (degrees at full charge), wandering `rate` times a second. It moves the aim too.
	Charge = {
		camera = { pitch = 1.4, yaw = 1.6, roll = 2.2 },
		viewmodel = { pitch = 2.5, yaw = 2.5, roll = 3 },
		rate = 0.9,
		grow = 1.6,
		ease = 6, -- how fast the shake follows the charge level (per second)
	},
}

return table.freeze(Sway)
