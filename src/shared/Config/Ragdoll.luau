--!strict
-- The ragdoll (src/client/Ragdoll; user 2026-10-13: "lose complete control (full ragdoll, limbs go limp with realistic
-- constraints). our ragdoll will trigger with different knockback depending on factors"). Data only.

local Ragdoll = {
	-- Each loose joint (R6, in the Torso): how far the limb may swing off its rest direction (degrees) and twist about
	-- itself either way. Roughly a person's range: arms swing wide, legs less, the neck little.
	Joints = {
		["Left Shoulder"] = { swing = 100, twist = 60 },
		["Right Shoulder"] = { swing = 100, twist = 60 },
		["Left Hip"] = { swing = 75, twist = 25 },
		["Right Hip"] = { swing = 75, twist = 25 },
		Neck = { swing = 40, twist = 50 },
	},
	-- The body is down until it has settled (its speed under `still` studs/s, at least `minDown` s after the hit; at
	-- most `maxDown` s), then gets up after the knock's own `getUp` seconds.
	still = 2.5,
	minDown = 0.35,
	maxDown = 3,
	-- Knocks: how hard each cause throws the body (studs/s back along the push and up, a tumble in rad/s) and how long
	-- after settling it gets up. Callers scale them by their own factors (strength, distance).
	Knocks = {
		-- a stage 3 staff shot's recoil (user 2026-10-13: "a minor knockback ragdoll that lets us stand up .5 seconds
		-- after")
		StaffRecoil = { push = 14, lift = 6, tumble = 6, getUp = 0.5 },
		-- sinking below the height you floated up from (user 2026-10-13: "if they fall below their initial height,
		-- they will rag doll"): you just drop, tipping over
		FloatFall = { push = 2, lift = 0, tumble = 3, getUp = 0.5 },
		-- Hits (M12, Config/Damage.Knocks; user 2026-10-17: "a headshot kill will drop the player with little to no
		-- ragdoll. a torso will do a medium one and a arm/leg will do a super light one"):
		Torso = { push = 9, lift = 3, tumble = 4, getUp = 0.6 }, -- a torso hit, alive: a medium ragdoll
		HeadDrop = { push = 0.5, lift = 0, tumble = 0.6, getUp = 0 }, -- a headshot kill: just drops
		TorsoDrop = { push = 9, lift = 3, tumble = 4, getUp = 0 },
		LimbDrop = { push = 3, lift = 1, tumble = 2, getUp = 0 },
		StaffThrow = { push = 40, lift = 18, tumble = 8, getUp = 0.8 }, -- a full beam
		BlastThrow = { push = 32, lift = 20, tumble = 8, getUp = 0.8 }, -- thrown by a blast (away from it)
		-- the very light knock (arm, leg, helmet): no ragdoll, a stagger: the torso tips `lean` degrees away from the
		-- shot and back over `time` s, the arms stay on the weapon, first person stays; a small `push` (studs/s)
		Stagger = { stagger = 1, lean = 14, time = 0.3, push = 3, lift = 0, tumble = 0, getUp = 0 },
	},
	-- knocks that aren't a ragdoll (they have `stagger`) and the ones a player may ask for on itself (Net "KnockSelf":
	-- the staff's recoil, the float fall)
	SelfKnocks = { StaffRecoil = true, FloatFall = true },
	SelfRate = 2, -- "KnockSelf" requests a second at most (and burst)
	-- the client shows a knock it asked for at once and waits this long for the server's ragdoll before giving up
	SelfWait = 1.5,
}

return table.freeze(Ragdoll)
