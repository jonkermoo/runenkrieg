--!strict
-- Shooting (M11; user 2026-10-12): bolt rifles fire instantly (hitscan) out of the barrel along its path, aimed or
-- not (never toward a cursor: there is none), with no drop: aimed, the shot lands one sight height under the point of
-- aim at every range (Config/Weapons aiming contract). The bolt is worked by hand (click again after a shot), R
-- reloads a clip. The server checks every shot (src/server/Firing, Rules/Firing).
-- Per-weapon numbers (magazine, clip, bolt and reload times, bolt throw) are in Config/Weapons `ammo` / `action`.
-- Data only.

local Firing = {
	-- (the fire and reload keys are player settings: Config/Settings)
	Range = 600, -- studs a shot travels (Metrics fog end; effective range 450)
	FireTime = 0.15, -- after a shot nothing else can start for this long (the shot itself)
	-- Server checks: timings get this much slack (latency jitter); the reported muzzle must be this close to the
	-- shooter's head (the first-person gun sits ~5 studs ahead of the eye); remotes per second per player.
	Slack = 0.2,
	MaxOrigin = 9,
	RatePerSecond = 12,

	-- Rifles (class BoltRifle) load clips of this many rounds and hold one more in the chamber: 5 + 1 (user 2026-10-12,
	-- for balance). An en-bloc rifle (the Carcano) takes one round more, 6 + 1, because it reloads only once its
	-- magazine is empty. tests/firing.spec checks Config/Weapons ammo.capacity against it.
	RifleClip = 5,

	-- Bolt cycle timeline, as shares of the weapon's boltTime: the right hand reaches the handle, turns it up, pulls it
	-- back (the case flies out), pushes it forward (a round goes into the chamber), turns it down, and goes back to the
	-- grip. The third-person bolt animations (tools/animation/bolt.luau; user 2026-10-13) are keyed on it.
	BoltCycle = { reach = 0.12, up = 0.25, back = 0.45, forward = 0.7, down = 0.84 },
	-- Reload timeline, shares of reloadTime (user 2026-10-13: open the bolt, grab a clip, put it in): the right hand
	-- reaches the bolt handle, turns it up, pulls it back; goes to the ammo pouch and takes a clip (grab: it is in the
	-- hand from here); sets it in the guides (an en-bloc clip over the magazine); pushes the rounds down (an en-bloc
	-- clip goes down with them); back to the handle, pushes the bolt forward (a stripper clip flies out), turns it
	-- down, and the hand goes back to the grip. The reload animations (tools/animation/reload.luau) and the clip
	-- (src/client/GunFx) follow this timeline, so a reload cut short resumes with everything where it was.
	ReloadCycle = {
		reach = 0.08,
		up = 0.16,
		back = 0.26,
		grab = 0.44,
		set = 0.58,
		clip = 0.7,
		knob = 0.8,
		forward = 0.88,
		down = 0.94,
	},
	-- A semi-automatic's action after a shot (W2), shares of its boltTime: the bolt flies back (the case out at `back`),
	-- then returns; nothing turns and no hand moves. On the last round it stops at `back` (held open).
	AutoCycle = { reach = 0, up = 0.01, back = 0.4, forward = 0.85, down = 1 },
	-- Two chargers (a semi-automatic with room for more than one, W2: the Remington 8), shares of reloadTime +
	-- clipTime: the same opening (the same `back`), then a charger taken, set and pushed down, its empty one flung off,
	-- a second the same way, and the bolt let go. The reload animations' Two variants are keyed on it.
	ReloadCycleTwo = {
		reach = 0.08,
		up = 0.16,
		back = 0.26,
		grab = 0.4,
		set = 0.5,
		clip = 0.58,
		grab2 = 0.66,
		set2 = 0.74,
		clip2 = 0.8,
		knob = 0.86,
		forward = 0.91,
		down = 0.95,
	},
	-- An action started partway (a reload from a bolt held open, one resumed after being cut) fades its arms in over
	-- this long (s), so the rifle travels from the hold into the action's pose (at 0.15 s it lunged; A1 audit 2026-10-18)
	ResumeFade = 0.3,
	ClipRise = 0.3, -- studs (model) an empty en-bloc clip drops out the bottom
	-- Single rounds (user 2026-10-13): a stripper-clip rifle (Gewehr, SMLE) with rounds left in the magazine loads them
	-- one at a time through the open action (a whole clip only fits an empty magazine): seconds to open the bolt (hand to
	-- the handle, up, back, then over the magazine), per round (to the pouch, a round, pushed in), to close it (back on
	-- the handle, forward, down, hand on the grip). A click stops it after the round in the hand.
	Single = { open = 0.6, round = 0.55, close = 0.7 },
	-- A rifle put away mid-action (user 2026-10-12): drawn again, the rest of the action plays out `delay` seconds
	-- after the draw starts (the equip animation, ~0.55 s, and a brief beat), and nothing fires until it's done.
	Resume = { delay = 0.75 },

	-- Recoil (local, the global sway layer: src/client/Sway): an impulse on springs. Degrees and studs.
	Recoil = {
		pitch = 4, -- the first-person gun's kick up
		yaw = 0.8, -- random sideways, either way up to this
		back = 0.18, -- the gun shoves back toward the eye
		camera = 1.5, -- the view's own kick up (First / Aim; Shoulder takes half)
		stiffness = 160,
		damping = 16,
		-- the body's gun as everyone sees it (third person): a kick at the Hold motor, eased back over `time`
		body = { pitch = 6, back = 0.12, time = 0.2 },
	},

	Effects = {
		Flash = { color = { 255, 214, 140 }, size = 0.45, time = 0.05, brightness = 4, range = 12 },
		Tracer = { color = { 255, 236, 190 }, width = 0.04, time = 0.06 },
		Hole = { color = { 24, 22, 20 }, size = 0.16, life = 30, max = 60 },
		-- a spent case thrown from the ejection port (studs/s, gun space: out to the right, up, back), flying under
		-- real gravity (9.8 m/s^2 = 27.5 studs/s^2 at 0.357 m per stud; Roblox's 196 is ~7x that, which dropped the case
		-- like a stone, user 2026-10-12) for `flight` seconds, then the world's
		Casing = { out = 9, up = 8, back = 1.5, spin = 25, life = 4, gravity = 27.5, flight = 1.2 },
		TargetFlash = { color = { 255, 255, 255 }, time = 0.15 },
		-- What a bullet throws up where it lands, by surface (src/client/Impacts; user 2026-10-17), local to each client:
		-- `count` bits of `size` studs (a splinter is `long` x that), thrown out of the surface at `speed` studs/s plus
		-- `up`, falling at `gravity` studs/s^2 (real gravity is 27.5), slowed by `drag` per s, gone after `life` s.
		-- Their colour is the surface's own (the terrain material's colour, the part's). Leaves fall from the canopy a
		-- bullet passes through (canopies let bullets through; the box tested is `canopyShare` of the canopy's box).
		Impacts = {
			Dirt = { count = 6, size = 0.28, speed = 9, up = 12, gravity = 55, drag = 1.5, life = 0.8 },
			Chip = { count = 5, size = 0.2, speed = 11, up = 6, gravity = 70, drag = 1, life = 0.6 },
			Splinter = { count = 5, size = 0.14, long = 3.5, speed = 12, up = 5, gravity = 60, drag = 1, life = 0.9 },
			Splash = { count = 7, size = 0.3, speed = 3, up = 18, gravity = 70, drag = 1, life = 0.7 },
			Leaf = { count = 5, size = 0.4, speed = 2, up = 0, gravity = 3, drag = 2.5, life = 2.6, canopyShare = 1 },
			-- a staff beam through a canopy (Net "LeavesHit", x its `react`): this many leaves and a shake of `kick` x the
			-- explosion kick (Config/TreeSway.Explosion) within `radius` of where it entered
			Beam = { leaves = 12, kick = 0.35, radius = 10, scatter = 2, maxReact = 4 }, -- scatter: studs round the entry
			-- a canopy shedding (stripped, or its tree felled): `perSecond` bursts of Leaf.count leaves fall from all over
			-- it while it fades (src/client/TreeFall)
			-- (`spread`: share of the canopy's box they fall from; `endRate`: the rate at the end, x perSecond)
			Shed = { perSecond = 4, spread = 0.8, endRate = 0.5 },
		},
		HitMarker = { time = 1.2 }, -- the shooter's note: what was hit, how far
	},

	-- Creator Store placeholders (user 2026-10-12: replace with a licensed set before release, like the footsteps).
	Sounds = {
		-- "Bolt Action Long Rifle 0m" (ChipTheTrainer2): one point-blank shot with its natural outdoor tail, no ring or
		-- bolt baked in. Its file starts with 0.36 s of silence: `start` skips it. (Was "Bolt Action Fire", 7700083911:
		-- a ring at 0.44 s and a bolt cycle at 0.8 s in the file; cutting them cut the shot short, user 2026-10-12.)
		Shot = { id = 134529004435835, volume = 2.5, start = 0.34 },
		BoltOpen = { id = 85609660605803, volume = 0.8 }, -- "Rifle Bolt Pull 2" (EXPPOINT)
		BoltClose = { id = 86945427224170, volume = 0.8 }, -- "Rifle Bolt Push 1" (EXPPOINT)
		ClipIn = { id = 9116321026, volume = 0.7 }, -- "Locking Wrench 7 (SFX)" (Pro Sound Effects)
		Dry = { id = 114980515844355, volume = 0.6 }, -- "Click"
		-- Heard by everyone else (src/client/ShotAudio, Config/Audio.Heard), Pro Sound Effects; a list is variants, one
		-- picked per shot. `start` skips each file's lead-in silence (measured 2026-10-16), `lead` is seconds from
		-- `start` to the sound's peak (a pass is timed on its peak).
		-- the far report: "Gun Retort 1 / 2 / 3" ("Distant, Present Decay")
		Far = {
			{ id = 9114725082, volume = 1.5, start = 2.14, stop = 6.4, fade = 1.5 },
			{ id = 9114725318, volume = 1.5, start = 0.86, stop = 4.8, fade = 1.5 },
			{ id = 9114725314, volume = 1.5, start = 1.1, stop = 4.2, fade = 1.2 },
		},
		-- a rifle bullet's supersonic crack going by: "Whip Cracks 1 / 2" (a whip's crack is a small sonic boom)
		Pass = {
			{ id = 9120660173, volume = 1.2, start = 0.32, lead = 0.06 },
			{ id = 9120660382, volume = 1.2, start = 0.3, lead = 0.08 },
		},
	},
	-- distance falloff (Config/Audio): the shot is a Gunshot, the far report a Report, the rest of the action Mechanism
}

return table.freeze(Firing)
