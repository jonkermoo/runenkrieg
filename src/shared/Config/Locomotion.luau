--!strict
-- Soldier movement and its animations (.claude/skills/roblox-animation). Speeds live in Config/Metrics.Movement;
-- this file holds the controls and the animation set. Data only (Lune tests read it).
-- Sprint (user 2026-10-11): hold Shift, unlimited stamina. No firing or aiming while sprinting (src/client/Stance:
-- Shift wins over aiming; firing, later).
-- Animations come from tools/animation/locomotion.luau (keyframe data -> build.luau -> .rbxm -> Open Cloud).

local Locomotion = {
	SprintKeys = { "LeftShift", "RightShift" },
	-- Sprint only moving forward relative to the camera (user reference video 2026-10-11): within this angle (degrees)
	-- of where the camera looks; strafing or backing up with Shift stays a walk (and can aim).
	SprintCone = 50,
	AimKeys = { "MouseButton2" }, -- hold to aim down the sights (a weapon in the hands)
	CrouchKeys = { "C" }, -- toggles crouch; sprinting (Shift, moving forward) or jumping stands you up
	CrouchCameraEase = 8, -- how fast the camera follows the body down into the crouch and back up (per second)

	-- Volume of Roblox's built-in character sounds (RbxCharacterSounds, in each character's HumanoidRootPart; client
	-- side, on every client), held on every character; 0 mutes. Sounds not listed keep Roblox's volume. Footsteps
	-- come from src/client/Footsteps instead of "Running" (user 2026-10-11).
	SoundVolumes = {
		Running = 0, -- Roblox's footstep loop
		Landing = 0,
		Jumping = 0.05, -- the default jump sound, kept quiet (user 2026-10-11; Roblox's is 0.65)
	},

	-- Animation asset ids. Roblox's stock R6 ids fill what we haven't made yet.
	-- Ground cycles: `keyed` is the cycle length in the keyframe data (tools/animation/locomotion.luau), `cycle` the
	-- length it plays at when moving at `speed` (Metrics.Movement); playback also scales with actual speed / `speed`.
	-- Pace (user 2026-10-11: steps were too quick for the speed): walk ~2 steps/s, sprint ~2.8 steps/s, close to a
	-- real walk and run cadence. Tune `cycle` here; no re-upload needed.
	Animations = {
		idle = { id = 180435571 }, -- Roblox stock R6 idle (placeholder)
		walk = { id = 90079278838820, speed = 10, keyed = 0.76, cycle = 1 },
		sprint = { id = 71642320375175, speed = 16, keyed = 0.56, cycle = 0.72 },
		climb = { id = 180436334, speed = 8 }, -- Roblox stock R6 climb (ladders)
		toolnone = { id = 182393478 }, -- Roblox stock R6: the right arm holds an equipped tool out
		-- Crouch (user 2026-10-11): torso leaning only a little, the legs pushed up into it (only the shins show), the
		-- right knee down at idle; the walk alternates like a real walk
		crouchIdle = { id = 139770444602307 },
		crouchWalk = { id = 140224669320052, speed = 6, keyed = 1.0, cycle = 1.4 }, -- long, slow strides (user)
		-- in the air with the staff aimed (user 2026-10-13): legs loose, drifting (tools/animation/staff.luau)
		float = { id = 127154488107008 },
	},

	IdleBelow = 0.75, -- horizontal speed (studs/s) under which the soldier stands still
	SprintAbove = 13, -- speed over which the sprint cycle plays (between walk 10 and sprint 16)
	PlaybackMin = 0.6, -- clamp on the speed-scaled playback rate
	PlaybackMax = 1.4,

	Fade = 0.15, -- crossfade between ground cycles (seconds)
	HoldFade = 0.12, -- crossfade between weapon holds (ready / carry / aim) and the tool hold
	-- No jump / fall / land animations (user 2026-10-11): in the air the current idle / walk / sprint keeps playing,
	-- except floating with the staff aimed ("Floating", src/client/StaffAttack): the float cycle.

	-- Look tilt (user 2026-10-11): the torso follows the camera's pitch a little, leaning back when you look up and
	-- forward when you look down. Only the torso (with head and arms on it) tilts, about the waist; the legs stay
	-- planted. Share of the camera pitch, capped (degrees).
	LookTilt = {
		Torso = 0.28, -- user 2026-10-11: a bit more apparent (was 0.2 / 10)
		TorsoMax = 13,
		Smoothing = 12, -- how fast the tilt follows the camera (per second)
	},
}

return table.freeze(Locomotion)
