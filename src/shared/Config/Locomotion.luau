--!strict
-- Soldier movement and its animations (.claude/skills/roblox-animation). Speeds live in Config/Metrics.Movement;
-- this file holds the controls and the animation set. Data only (Lune tests read it).
-- Sprint (user 2026-10-11): hold Shift, unlimited stamina. No firing or aiming while sprinting (src/client/Stance:
-- Shift wins over aiming; firing, later).
-- Animations come from tools/animation/locomotion.luau (keyframe data -> build.luau -> .rbxm -> Open Cloud).

local Locomotion = {
	-- (the sprint, aim and crouch keys and their hold / toggle modes are player settings: Config/Settings)
	-- Sprint only moving forward relative to the camera (user reference video 2026-10-11): within this angle (degrees)
	-- of where the camera looks; strafing or backing up with Shift stays a walk (and can aim).
	SprintCone = 50,
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
					crouchReady = 125300819482628,
					crouchWalk = 109286771789007,
					crouchAim = 125788513626290,
				},
				rifle_g98 = {
					carry = 89297360927119,
					crouchReady = 71279703172364,
					crouchWalk = 135152899831020,
					crouchAim = 81865048539698,
				},
				rifle_smle = {
					carry = 131313963233381,
					crouchReady = 124540600132919,
					crouchWalk = 136711785310993,
					crouchAim = 88093230462842,
				},
				rifle_mondragon = {
					carry = 100020439402399,
					crouchReady = 105675657815195,
					crouchWalk = 131013849846517,
					crouchAim = 108054363167309,
				},
				rifle_remington8 = {
					carry = 139712671322785,
					crouchReady = 86600766705324,
					crouchWalk = 117233666710960,
					crouchAim = 138784226712792,
				},
				rifle_winchester1907 = {
					carry = 89132952036365,
					crouchReady = 137575028944948,
					crouchWalk = 72212727683637,
					crouchAim = 88578444180018,
				},
				shotgun_m1897 = {
					carry = 76878677051189,
					crouchReady = 106243506938923,
					crouchWalk = 80397196237031,
					crouchAim = 122339519446187,
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

	Fade = 0.15, -- crossfade between ground cycles (seconds)
	HoldFade = 0.12, -- crossfade between weapon holds (ready / carry / aim) and the tool hold
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
		JumpFade = 0.05, -- into the take-off
		FallFade = 0.1, -- take-off (or ground) into the tuck
		LandFade = 0.05,
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
		-- shown to other players (Net "LookPitch", Rules/LookTilt): the camera pitch and the gun's follow share
		Send = {
			Rate = 10, -- updates per second at most, from each client and relayed by the server per soldier
			Step = 2, -- pitch quantized to this many degrees (a change smaller than this is not sent)
			FollowStep = 0.1, -- the gun's follow share (Config/Camera.Follow), quantized
			MaxPitch = 90, -- the server clamps the received pitch to +-this
			Smoothing = 10, -- how fast other players' soldiers follow the received pitch (per second)
		},
	},
}

return table.freeze(Locomotion)
