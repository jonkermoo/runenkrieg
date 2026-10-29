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
	-- every pistol (class "Pistol", the Engineer's) fires at most once this often, unless its entry sets its own
	-- action.fireTime (the design 2026-10-27: the same rate for all three)
	PistolFireTime = 0.25,
	-- Server checks: timings get this much slack (latency jitter); the reported muzzle must be this close to the
	-- shooter's head (the first-person gun sits ~5 studs ahead of the eye); remotes per second per player.
	Slack = 0.2,
	MaxOrigin = 9,
	RatePerSecond = 12,
	-- A bullet (each pellet too) breaks the building sections of these classes it meets (Config/Destruction.Materials)
	-- and carries on, through at most `panes` of them (user 2026-10-22: "bullets currently dont break glass"). The
	-- shards are thrown from `behind` studs back along the bullet, so they fly on the way it went.
	Shatter = { classes = { Glass = true }, panes = 3, behind = 1.5 },

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
	-- down, rests there a beat, and the hand goes back to the grip. The reload animations (tools/animation/reload.luau)
	-- and the clip (src/client/GunFx) follow this timeline, so a reload cut short resumes with everything where it was.
	-- v2 (user 2026-10-19: "a little too fast ... give some time after flicking the clip out", every rifle; the clip
	-- now comes from the pack on the back in third person, a longer reach): every reload 25% longer, a beat (`rest`)
	-- after the flick. `back` is the same in ReloadCycleTwo (a reload from an open bolt starts there).
	ReloadCycle = {
		reach = 0.06,
		up = 0.12,
		back = 0.18,
		grab = 0.38,
		set = 0.5,
		clip = 0.6,
		knob = 0.68,
		forward = 0.74,
		down = 0.78,
		rest = 0.88,
	},
	-- Single rounds keep the reload's first timeline (their animations are keyed on it: tools/animation/single.luau)
	SingleCycle = {
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
	-- Two clips (a semi-automatic with room for more than one, W2: the Remington 8's 5-round chargers, the Mondragón's
	-- 5-round clips topping up the rest, user 2026-10-19), shares of reloadTime +
	-- clipTime: the same opening (the same `back`), then a charger taken, set and pushed down, its empty one flung off,
	-- a second the same way, and the bolt let go. The reload animations' Two variants are keyed on it.
	ReloadCycleTwo = {
		reach = 0.05,
		up = 0.11,
		back = 0.18,
		grab = 0.31,
		set = 0.39,
		clip = 0.46,
		fling = 0.48, -- the first empty clip flicked off
		beat = 0.53, -- a beat before the hand goes for the next
		grab2 = 0.63,
		set2 = 0.7,
		clip2 = 0.76,
		knob = 0.81,
		forward = 0.85,
		down = 0.88,
		rest = 0.94,
	},
	-- A box swapped whole (W2: the Winchester 1907), shares of reloadTime: the right hand goes under the box (`under`),
	-- lets it drop (`drop`), takes a fresh one from the pouch (`grab`), sets it at the well's mouth (`set`) and pushes it
	-- up in (`seat`, = `clip`), back on the grip (`grip`); then the left hand runs the cocking plunger under the barrel:
	-- reaches it, pulls it (the bolt back at `back`), lets go (`forward`). The box reload animations are keyed on it.
	BoxCycle = {
		under = 0.06,
		drop = 0.14,
		grab = 0.34,
		set = 0.5,
		seat = 0.58,
		clip = 0.58,
		grip = 0.66,
		reach = 0.7,
		up = 0.74,
		back = 0.79,
		knob = 0.81,
		forward = 0.85,
		down = 0.86,
	},
	-- The box in the hand (src/client/GunFx): the hand's centre this far (studs) beside the box's side (third person) or
	-- under its bottom (first person: half the 1-stud hand); the last `blend` of the share before `set` settles it onto
	-- the well's mouth; the dropped box leaves at `drop` (studs/s, gun space: right, up, back).
	Box = { hand = 0.5, blend = 0.05, drop = { 1, -3, 0 } },
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
		-- Its tail swells again at ~1.3 s and then hisses (a windy noise floor) until the file stops dead at 3.9 s (user
		-- 2026-10-19: "rings out some type of wind noise and cuts off"; measured). That swell is a reflection off
		-- something ~430 studs off (it peaks 0.9 s after the shot at -20 dB, measured 2026-10-28), so the shooter and
		-- anyone beside them heard a distant echo (user 2026-10-28: "the shot keeps ringing a distant echo when we are
		-- right next to the gun"): it stops at 1.15 s (-24 dB, before the swell), faded from 0.7 s (-14 dB). The far
		-- report and its echoes take over with distance (src/client/ShotAudio).
		Shot = { id = 134529004435835, volume = 2.5, start = 0.34, stop = 1.15, fade = 0.45 },
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
