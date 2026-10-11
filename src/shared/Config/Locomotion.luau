--!strict
-- Soldier movement and its animations (.claude/skills/roblox-animation). Speeds live in Config/Metrics.Movement;
-- this file holds the controls and the animation set. Data only (Lune tests read it).
-- Sprint (user 2026-10-11): hold Shift, unlimited stamina. No firing or aiming while sprinting (enforced by the
-- weapon code once it exists).
-- Animations come from tools/animation/locomotion.luau (keyframe data -> build.luau -> .rbxm -> Open Cloud).

local Locomotion = {
	SprintKeys = { "LeftShift", "RightShift" },

	-- Roblox's built-in character sounds (RbxCharacterSounds, in each character's HumanoidRootPart) muted on every
	-- character (user 2026-10-11: no stepping or jumping audio). Our own movement audio comes later.
	MutedSounds = { "Running", "Jumping", "Landing" },

	-- Animation asset ids. `speed`: the ground speed the cycle was keyed for (Metrics.Movement); playback is
	-- scaled by actual speed / speed so the feet keep pace. Roblox's stock R6 ids fill what we haven't made yet.
	Animations = {
		idle = { id = 180435571 }, -- Roblox stock R6 idle (placeholder)
		walk = { id = 133173290830038, speed = 12 },
		sprint = { id = 129090682828738, speed = 18 },
		jump = { id = 82084528203249 },
		fall = { id = 132452327933827 },
		land = { id = 88515844098808 },
		climb = { id = 180436334, speed = 8 }, -- Roblox stock R6 climb (ladders)
		toolnone = { id = 182393478 }, -- Roblox stock R6: the right arm holds an equipped tool out
	},

	IdleBelow = 0.75, -- horizontal speed (studs/s) under which the soldier stands still
	SprintAbove = 15, -- speed over which the sprint cycle plays (between walk 12 and sprint 18)
	PlaybackMin = 0.6, -- clamp on the speed-scaled playback rate
	PlaybackMax = 1.4,

	Fade = 0.15, -- crossfade between ground cycles (seconds)
	AirFade = 0.08, -- into jump / fall
	LandMinAir = 0.25, -- seconds airborne before a landing plays (a flat hop is ~0.32 s; steps down are shorter)
	LandWeightMoving = 0.45, -- the landing plays lighter when you land on the move, so the run carries through

	-- Look tilt (user 2026-10-11): the body follows the camera's pitch a little, leaning back when you look up and
	-- forward when you look down; the head follows more. Share of the camera pitch, capped (degrees).
	LookTilt = {
		Torso = 0.2,
		TorsoMax = 10,
		Head = 0.35,
		HeadMax = 20,
		Smoothing = 12, -- how fast the tilt follows the camera (per second)
	},
}

return table.freeze(Locomotion)
