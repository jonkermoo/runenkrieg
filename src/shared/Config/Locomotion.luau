--!strict
-- Soldier movement and its animations (.claude/skills/roblox-animation). Speeds live in Config/Metrics.Movement;
-- this file holds the controls and the animation set. Data only (Lune tests read it).
-- Sprint (user 2026-10-11): hold Shift, unlimited stamina. No firing or aiming while sprinting (enforced by the
-- weapon code once it exists).
-- Animations come from tools/animation/locomotion.luau (keyframe data -> build.luau -> .rbxm -> Open Cloud).

local Locomotion = {
	SprintKeys = { "LeftShift", "RightShift" },

	-- Volume of Roblox's built-in character sounds (RbxCharacterSounds, in each character's HumanoidRootPart; client
	-- side, on every client), held on every character; 0 mutes. Sounds not listed keep Roblox's volume. Footsteps
	-- come from src/client/Footsteps instead of "Running" (user 2026-10-11).
	SoundVolumes = {
		Running = 0, -- Roblox's footstep loop
		Landing = 0,
		Jumping = 0.01, -- the default jump sound, kept quiet (user 2026-10-11; Roblox's is 0.65)
	},

	-- Animation asset ids. Roblox's stock R6 ids fill what we haven't made yet.
	-- Ground cycles: `keyed` is the cycle length in the keyframe data (tools/animation/locomotion.luau), `cycle` the
	-- length it plays at when moving at `speed` (Metrics.Movement); playback also scales with actual speed / `speed`.
	-- Pace (user 2026-10-11: steps were too quick for the speed): walk ~2 steps/s, sprint ~2.8 steps/s, close to a
	-- real walk and run cadence. Tune `cycle` here; no re-upload needed.
	Animations = {
		idle = { id = 180435571 }, -- Roblox stock R6 idle (placeholder)
		walk = { id = 84858012910481, speed = 10, keyed = 0.76, cycle = 1 },
		sprint = { id = 134283453564965, speed = 16, keyed = 0.56, cycle = 0.72 },
		climb = { id = 180436334, speed = 8 }, -- Roblox stock R6 climb (ladders)
		toolnone = { id = 182393478 }, -- Roblox stock R6: the right arm holds an equipped tool out
	},

	IdleBelow = 0.75, -- horizontal speed (studs/s) under which the soldier stands still
	SprintAbove = 13, -- speed over which the sprint cycle plays (between walk 10 and sprint 16)
	PlaybackMin = 0.6, -- clamp on the speed-scaled playback rate
	PlaybackMax = 1.4,

	Fade = 0.15, -- crossfade between ground cycles (seconds)
	-- No jump / fall / land animations (user 2026-10-11): in the air the current idle / walk / sprint keeps playing.

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
