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
		AutoRifle = 1.0,
		Shotgun = 1.1,
		Sniper = 1.3,
		Pistol = 0.5,
		Grenade = 0.3,
		Potion = 0.3,
		Staff = 0.8,
		SpellBook = 0.4,
	},

	-- Steps: driven by the Footstep markers on the local walk / sprint cycles (the view lands with the feet). A stride
	-- is two steps. The first-person gun draws a figure 8: side to side once per stride, down at every step.
	-- Reference: walk side 17 deg p-p and down 3.4 deg p-p; sprint side ~28 and down ~4 deg p-p.
	Stride = {
		walk = { side = 8, down = 1.7, roll = 2 },
		sprint = { side = 14, down = 2, roll = 4 },
		WalkSpeed = 10, -- speeds the amplitudes are given at (Metrics.Movement); scaled linearly in between
		SprintSpeed = 16,
		Fade = 6, -- how fast the stride sway fades in and out when starting and stopping (per second)
	},

	-- Breath: always on, a slow loop. First person 3 s (user 2026-10-11: visible but minimal enough not to bother
	-- gameplay). Reference, aiming and standing still: ~0.5 deg of slow drift.
	Breath = { period = 3, pitch = 0.25, yaw = 0.2 },

	-- Look lag: the gun trails the view when turning, then springs back. Offset = -Gain x turn rate (deg per deg/s),
	-- capped; roll leans into the turn.
	LookLag = { gain = 0.02, max = 5, roll = 0.012, stiffness = 90, damping = 14 },

	-- Strafe: sideways speed (share of walk speed) cants the gun toward the side it moves and shifts it a little.
	Strafe = { roll = 6, shift = 0.08, stiffness = 60, damping = 12 },

	-- Landing: a dip proportional to the fall speed (studs/s), capped.
	Landing = { pitch = 0.12, drop = 0.006, max = 4, stiffness = 120, damping = 12 },

	-- Aiming down the sights: shares of each source (reference: side sway about a quarter, the step dip stays).
	Aim = { side = 0.25, down = 1, roll = 0.25, breath = 1, lag = 0.4, strafe = 0.3, landing = 0.5 },

	-- The camera's own small share (reference: walk pitch bob 0.19 deg p-p, roll 0.08; sprint ~0.15; aiming walk
	-- ~0.27 deg p-p), as amplitudes at the step, scaled by view.
	Camera = {
		walk = { pitch = 0.1, roll = 0.04 },
		sprint = { pitch = 0.08, roll = 0.03 },
		aim = { pitch = 0.13, roll = 0.02 },
		View = { First = 1, Aim = 1, Shoulder = 0.25, Free = 0 },
	},
}

return table.freeze(Sway)
