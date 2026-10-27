--!strict
-- Soldier movement and its animations. Speeds live in Config/Metrics.Movement;
-- this file holds the controls and the animation set. Data only (Lune tests read it).
-- Sprint (user 2026-10-11): hold Shift, unlimited stamina. No firing or aiming while sprinting (src/client/Stance:
-- Shift wins over aiming; firing, later).
-- Animations come from tools/animation/locomotion.luau (keyframe data -> build.luau -> .rbxm -> Open Cloud).

local Locomotion = {
	-- (the sprint, aim and crouch keys and their hold / toggle modes are player settings: Config/Settings)
	-- Sprint only moving forward relative to the camera (user reference video 2026-10-11): within this angle (degrees)
	-- of where the camera looks; strafing or backing up with Shift stays a walk (and can aim).
	SprintCone = 50,
	-- Folding the gun in (user 2026-10-21: "make avatars fold their gun inwards (as if their hugging it against their
	-- chest but still at ready ...) whenever the barrel is blocked or about to be collided with"; src/client/Tuck,
	-- Rules/Tuck): a sphere of `Radius` swept from the right shoulder along the look, as far as the barrel reaches at
	-- the ready hold plus `Ahead` (about to hit), finds anything in the way; the soldier then holds the "tuck" hold
	-- (Config/Weapons holds / firstPerson `tuck`) until the way is clear by `Clear` more, and can't aim or fire.
	-- Pulled back first (user 2026-10-25: "the gun comes close to your shoulder, but still points to where its aiming
	-- ... this is supposed to be a realism visual feature, not something that actually makes the game hard"): from
	-- `Ahead` out the gun slides back toward the shoulder along its line, still aimed and still firing, up to `Give`
	-- studs; it folds only when even pulled back that far the barrel would be in the way, and only against a surface
	-- the look meets head on (`Facing`). A wall glanced along only pulls it back.
	Tuck = {
		Radius = 0.3,
		Ahead = 0.6, -- studs past the muzzle: the pull-back starts just before the barrel would touch
		Clear = 0.5, -- studs further still before it comes back out (no flicker at the edge)
		Shoulder = { 1, 0.5, 0 }, -- the sweep's start, in the torso's space
		GripAhead = 0.7, -- the ready hold's grip ahead of the shoulder (studs)
		Give = 2, -- studs the gun can come back before it folds
		Facing = 0.6, -- folds only on a surface the look meets this head on (cosine between the look and into it: ~53 deg)
		FacingClear = 0.1, -- folded, it stays so down to Facing minus this (no flicker turning along a wall)
		Ease = 12, -- how fast the pull-back follows (per second)
		-- how far the pulled-back gun is shown moving at the full pull (studs; the barrel may meet the wall a little
		-- before it folds: the server stops a shot at a wall between the head and the muzzle)
		Body = 0.4, -- third person: the gun and arms slide back along the barrel
		First = 0.5, -- first person at the hip: the viewmodel comes back toward the eye
		FirstAim = 0.12, -- first person aimed (the sight stays in front of the eye)
		-- shown to other players (Net "GunPull"): the pull share quantized to Step, at most Rate a second
		Send = { Rate = 10, Step = 0.1 },
		-- trench dirt folds the gun only when the look meets it this head on (cosine; 0.75: within about 40 degrees)
		-- and within the barrel's reach (Rules/Tuck.trenchBlocked)
		TrenchFacing = 0.75,
		-- near trench dirt the sweep starts here instead (torso space): the shouldered gun's height (Metrics
		-- AimMuzzleHeight 4.3: the torso's centre is 3 up), so a rifle rested on a trench's parapet doesn't fold
		TrenchFrom = { 1, 1.3, 0 },
	},
	ToggleSprintMoving = 0.1, -- a toggled sprint counts as moving above this share of MoveDirection (stopping ends it)
	-- the camera follows the body down into the crouch and back up on a critically damped spring at this rate (per
	-- second; user 2026-10-20: never snappy, so it starts and stops gently)
	CrouchCameraSpring = 10,

	-- Volume of Roblox's built-in character sounds (RbxCharacterSounds, in each character's HumanoidRootPart; client
	-- side, on every client), held on every character; 0 mutes. Sounds not listed keep Roblox's volume. Footsteps
	-- come from src/client/Footsteps instead of "Running" (user 2026-10-11).
	SoundVolumes = {
		Running = 0, -- Roblox's footstep loop
		Landing = 0,
		Died = 0, -- the "oof" on death (user 2026-10-27: "remove the oof sound on death")
		Jumping = 0.05, -- the default jump sound, kept quiet (user 2026-10-11; Roblox's is 0.65)
	},

	-- Animation asset ids. Roblox's stock R6 ids fill what we haven't made yet.
	-- Ground cycles: `keyed` is the cycle length in the keyframe data, `cycle` the length it plays at when moving at
	-- `speed` (Metrics.Movement); playback also scales with actual speed / `speed`. Tune `cycle` here; no re-upload.
	-- These are shared by both movement sets; each set below adds its own idle / walk / sprint / crouch / air ones
	-- (Rules/MovementSet).
	Animations = {
		climb = { id = 180436334, speed = 8 }, -- Roblox stock R6 climb (ladders)
		toolnone = { id = 182393478 }, -- Roblox stock R6: the right arm holds an equipped tool out
		-- in the air with the staff aimed (user 2026-10-13): legs loose, drifting (tools/animation/staff.luau)
		float = { id = 127154488107008 },
	},

	-- Which movement set plays (user 2026-10-20: "save this current animation, but make a more serious one"): "serious"
	-- or "veteran". Each has its own torso leans, so the third-person holds that ride a lean (sprint carry, crouched
	-- holds) are rebuilt per set: `Holds` replaces those Config/Weapons ids by weapon (the veteran set uses Weapons').
	Set = "serious",
	Sets = {
		-- Serious (user 2026-10-20, "combat-ready", arms at the sides; tools/animation/locomotion_serious.luau): restrained,
		-- a small bob, no shoulder roll or side lean, no head glances (the head turns to the view live, src/client/LookTilt).
		-- Leans: walk 3, sprint 18, crouch 20. Walk 2.0 steps/s, sprint 2.8, crouch walk 1.2.
		serious = {
			Animations = {
				idle = { id = 93195360424907 }, -- 4 s: feet a little apart, arms at the sides, one slow breath
				walk = { id = 75341378184097, speed = 10, keyed = 0.76, cycle = 1 },
				sprint = { id = 91348749956199, speed = 16, keyed = 0.56, cycle = 0.72 },
				crouchIdle = { id = 100480478844590 },
				crouchWalk = { id = 117100925469674, speed = 6, keyed = 1.0, cycle = 1.67 },
				jump = { id = 136481397424505 },
				fall = { id = 96238825240673 },
				land = { id = 81188383733947 },
			},
			-- the carry built over the 18 deg sprint, the crouched holds over the 20 deg crouch (rifle.luau, grenade.luau and
			-- staff.luau with those leans)
			Holds = {
				rifle_m91 = {
					carry = 119417853025094,
					crouchReady = 136315123666568,
					crouchWalk = 113288767652439,
					crouchAim = 125788513626290,
					crouchTuck = 132650677327308,
				},
				rifle_g98 = {
					carry = 89297360927119,
					crouchReady = 128009872668539,
					crouchWalk = 140341474894701,
					crouchAim = 81865048539698,
					crouchTuck = 75184218736588,
				},
				rifle_smle = {
					carry = 131313963233381,
					crouchReady = 72054231730916,
					crouchWalk = 100516419832508,
					crouchAim = 88093230462842,
					crouchTuck = 127147207467670,
				},
				rifle_mondragon = {
					carry = 100020439402399,
					crouchReady = 106561969997726,
					crouchWalk = 133463326844299,
					crouchAim = 108054363167309,
					crouchTuck = 126878471955941,
				},
				rifle_remington8 = {
					carry = 139712671322785,
					crouchReady = 95483335801365,
					crouchWalk = 133779447408753,
					crouchAim = 138784226712792,
					crouchTuck = 115286704577287,
				},
				rifle_winchester1907 = {
					carry = 89132952036365,
					crouchReady = 134458450532849,
					crouchWalk = 86859355193467,
					crouchAim = 88578444180018,
					crouchTuck = 112800624654038,
				},
				shotgun_m1897 = {
					carry = 76878677051189,
					crouchReady = 117168558988120,
					crouchWalk = 108497758139278,
					crouchAim = 122339519446187,
					crouchTuck = 131431173277700,
				},
				grenade_mills = { carry = 88834675278602 },
				grenade_stick = { carry = 88834675278602 },
				grenade_sipe = { carry = 88834675278602 },
				staff_grey = { carry = 99125305553684 },
				staff_olive = { carry = 99125305553684 },
				staff_white = { carry = 99125305553684 },
			},
		},
		-- Veteran (user 2026-10-18, "burdened veteran"; tools/animation/locomotion.luau): heavy heel-first steps, a small
		-- shoulder roll, arms hanging low; the sprint a lumbering charge at 2.6 steps/s; crouch hunched 28 deg.
		veteran = {
			Animations = {
				idle = { id = 71032700662557 }, -- 8 s: slumped, slow breath, weight shifts leg to leg, a glance each side
				walk = { id = 92205569241192, speed = 10, keyed = 0.76, cycle = 1 },
				sprint = { id = 130475958716124, speed = 16, keyed = 0.56, cycle = 0.77 },
				crouchIdle = { id = 110587356929380 },
				crouchWalk = { id = 138761604001437, speed = 6, keyed = 1.0, cycle = 1.67 },
				jump = { id = 127631172361702 },
				fall = { id = 112064982682133 },
				land = { id = 117973662730647 }, -- once on landing, over the ground cycle
			},
		},
	},

	IdleBelow = 0.75, -- horizontal speed (studs/s) under which the soldier stands still
	SprintAbove = 13, -- speed over which the sprint cycle plays (between walk 10 and sprint 16)
	PlaybackMin = 0.6, -- clamp on the speed-scaled playback rate
	PlaybackMax = 1.4,

	-- Water (user 2026-10-22: "remove swimming. just slow players down when they are submerged hip below in water";
	-- src/client/Wading, Rules/Wading): soldiers never swim (Roblox's Swimming state is off) and walk on the bottom,
	-- the water's lift cancelled by a downward force on the root. From hip-deep water (`From`, studs over the feet) the
	-- walk / sprint / crouch speed eases down to `Slow` of itself at `Full` (chest-deep) and deeper; the slow follows
	-- the depth at `Rate` per second, so wading in and out is gentle. The walk cycle keeps playing (slower, down to
	-- PlaybackMin).
	Wading = {
		From = 2, -- the hip (Metrics.Character.LegLength)
		Full = 3.5, -- about the chest
		Slow = 0.6, -- walk 10 -> 6, sprint 16 -> 9.6, crouch 6 -> 3.6
		Rate = 4,
		Sink = 1.05, -- share of the estimated lift pushed back down (a touch over 1: the feet stay on the bed)
	},

	-- Smooth, never snappy (user 2026-10-20): every change of animation blends over a while. Switching between the
	-- stepping cycles (walk / sprint / crouch walk) also carries the stride across (the new cycle starts at the same
	-- point of its step as the old one was), so the legs never jump to a new stride (src/client/Locomotion).
	Fade = 0.3, -- crossfade between ground cycles (seconds; was 0.15)
	HoldFade = 0.25, -- crossfade between weapon holds (ready / carry / aim) and the tool hold (was 0.12)
	-- Putting a weapon away (user 2026-10-14: "an unequip animation where i put my gun back on my back"): the weapon's
	-- unequip animations play for `time` seconds (body and first person, Config/Weapons holds / firstPerson .unequip)
	-- while the server keeps a copy in the hands (src/server/Armory) and the camera stays at the eye, then the slung
	-- copy shows and the camera glides back out (Config/Camera.LeaveBlend). The client says it's putting the weapon
	-- away (Net "Stow"); a weapon taken away with no word for `wait` seconds (a ragdoll knock) goes straight on the
	-- back.
	Stow = { time = 0.55, wait = 0.2 },
	-- In the air (user 2026-10-18): jumping plays the take-off, then the fall tuck loops until landing (walking off a
	-- ledge goes straight to the tuck); floating with the staff aimed ("Floating", src/client/StaffAttack) plays the
	-- float cycle instead. Landing plays the land once over the ground cycle: full weight standing, lighter on the move.
	Air = {
		JumpFade = 0.1, -- into the take-off (was 0.05)
		FallFade = 0.2, -- take-off (or ground) into the tuck (was 0.1)
		LandFade = 0.1, -- (was 0.05)
		-- stepping down a stair or a ledge drops into free fall for a moment: the tuck only after this long falling
		-- without a jump, and the land only after this long in the air (seconds)
		FallDelay = 0.15,
		LandMinAir = 0.3,
		LandWeight = 1, -- landing standing still
		LandWeightMoving = 0.4, -- landing on the move (blends with the walk / sprint under it)
	},

	-- Look tilt (user 2026-10-11): the torso follows the camera's pitch a little, leaning back when you look up and
	-- forward when you look down. Only the torso (with head and arms on it) tilts, about the waist; the legs stay
	-- planted. Share of the camera pitch, capped (degrees).
	LookTilt = {
		Torso = 0.28, -- user 2026-10-11: a bit more apparent (was 0.2 / 10)
		TorsoMax = 13,
		Smoothing = 12, -- how fast the tilt follows the camera (per second)
		-- The head turns left and right toward where the camera looks (user 2026-10-20: "heads will now face where you
		-- look ... only rotate left and right to a realistic angle"; up and down stays the torso's). Degrees from the
		-- torso's facing, the animation's own neck turn included (the idle's glances); eased at Smoothing per second.
		-- Others within Send.Range studs see it (Net "HeadYaw": user 2026-10-20, only people nearby), quantized to
		-- Send.Step, at most Send.Rate a second.
		Head = {
			Max = 70,
			Behind = 90, -- looking round further than this, the head stays on the side it is on
			Smoothing = 10,
			Send = { Rate = 10, Step = 3, Range = 120, Smoothing = 10 },
		},
		-- shown to other players (Net "LookPitch", Rules/LookTilt): the camera pitch, the gun's follow share and its
		-- turn onto the crosshair (Config/Camera.Aim3P, clamped to its Max by the server)
		Send = {
			Rate = 10, -- updates per second at most, from each client and relayed by the server per soldier
			Step = 2, -- pitch quantized to this many degrees (a change smaller than this is not sent)
			FollowStep = 0.1, -- the gun's follow share (Config/Camera.Follow), quantized
			AimStep = 1, -- the turn onto the crosshair (yaw and pitch), quantized to this many degrees
			MaxPitch = 90, -- the server clamps the received pitch to +-this
			Smoothing = 10, -- how fast other players' soldiers follow the received pitch (per second)
		},
	},
}

return table.freeze(Locomotion)
