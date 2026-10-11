--!strict
-- Soldier movement and its animations (.claude/skills/roblox-animation). Speeds live in Config/Metrics.Movement;
-- this file holds the controls and the animation set. Data only (Lune tests read it).
-- Sprint (user 2026-10-11): hold Shift, unlimited stamina. No firing or aiming while sprinting (enforced by the
-- weapon code once it exists).
-- Animations come from tools/animation/locomotion.luau (keyframe data -> build.luau -> .rbxm -> Open Cloud).

local Locomotion = {
	SprintKeys = { "LeftShift", "RightShift" },

	-- Animation asset ids. `speed`: the ground speed the cycle was keyed for (Metrics.Movement); playback is
	-- scaled by actual speed / speed so the feet keep pace. Roblox's stock R6 ids fill what we haven't made yet.
	Animations = {
		idle = { id = 180435571 }, -- Roblox stock R6 idle (placeholder)
		walk = { id = 131162843658767, speed = 12 },
		sprint = { id = 102164383274848, speed = 18 },
		jump = { id = 80629177613698 },
		fall = { id = 74494614741937 },
		land = { id = 73026045041116 },
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
}

return table.freeze(Locomotion)
