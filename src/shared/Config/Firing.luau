--!strict
-- Shooting (M11; user 2026-10-12): bolt rifles fire instantly (hitscan) out of the barrel along its path, aimed or
-- not (never toward a cursor: there is none), with no drop: aimed, the shot lands one sight height under the point of
-- aim at every range (Config/Weapons aiming contract). The bolt is worked by hand (click again after a shot), R
-- reloads a clip. The server checks every shot (src/server/Firing, Rules/Firing).
-- Per-weapon numbers (magazine, clip, bolt and reload times, bolt throw) are in Config/Weapons `ammo` / `action`.
-- Data only.

local Firing = {
	Keys = {
		Fire = { "MouseButton1" }, -- fire; after a shot, the same click works the bolt
		Reload = { "R" },
	},

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

	-- Bolt cycle timeline, as shares of the weapon's boltTime: handle up, pulled back (the case flies out), pushed
	-- forward (a round goes into the chamber), turned down.
	BoltCycle = { up = 0.2, back = 0.45, forward = 0.75, down = 1 },
	-- Reload timeline, shares of reloadTime: bolt open (up + back), the clip goes in, bolt closed.
	ReloadCycle = { up = 0.1, back = 0.2, clip = 0.65, forward = 0.85, down = 1 },
	ClipRise = 0.3, -- studs (model) above its seat that a clip comes in from
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
	},
	-- distance falloff (Config/Audio): the shot is a Gunshot, the rest of the action is Mechanism
}

return table.freeze(Firing)
