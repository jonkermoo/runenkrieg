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
	Collider = { 0.7, 0.85, 0.7 }, -- each limb's collider while down, x the limb's size (kept off the torso)
	-- Knocks: how hard each cause throws the body (studs/s back along the push and up, a tumble in rad/s) and how long
	-- after settling it gets up. Callers scale them by their own factors (strength, distance).
	Knocks = {
		-- a stage 3 staff shot's recoil (user 2026-10-13: "a minor knockback ragdoll that lets us stand up .5 seconds
		-- after")
		StaffRecoil = { push = 14, lift = 6, tumble = 6, getUp = 0.5 },
		-- sinking below the height you floated up from (user 2026-10-13: "if they fall below their initial height,
		-- they will rag doll"): you just drop, tipping over
		FloatFall = { push = 2, lift = 0, tumble = 3, getUp = 0.5 },
		-- Hits (M12, Config/Damage.Knocks). Every hit puts you on the ground (user 2026-10-17: "when shot in the arm ...
		-- i want us to ragdoll and have slight knockback (we still must fall on the ground). if we get shot in the torso
		-- i want us to have medium knockback"; "exaggerate the rag doll. we should be sent back, not just a little
		-- knock"):
		Limb = { push = 10, lift = 4, tumble = 6, getUp = 0.5 }, -- an arm, leg or helmet hit: slight knockback
		Torso = { push = 20, lift = 8, tumble = 8, getUp = 0.8 }, -- a torso hit: medium knockback
		-- a headshot kill: the body collapses where it stands (user: "on headshots, we should collapse but we ragdoll
		-- standing up")
		-- (a plain topple: driving it down, `drop` 16 studs/s, folded the legs under a torso that then knelt upright in
		-- the 2-player test, user 2026-10-17: "they still stand up ragdolled")
		-- (thrown along the bullet's travel, away from the shooter; user 2026-10-17: "they need some more knockback on
		-- headshots, make sure to goes the direction the bullet was coming from")
		HeadDrop = { push = 12, lift = 2, tumble = 9, getUp = 0 },
		TorsoDrop = { push = 20, lift = 8, tumble = 8, getUp = 0 },
		LimbDrop = { push = 10, lift = 4, tumble = 6, getUp = 0 },
		StaffThrow = { push = 70, lift = 30, tumble = 10, getUp = 1 }, -- a full beam: sent flying
		BlastThrow = { push = 60, lift = 35, tumble = 10, getUp = 1 }, -- thrown by a blast (away from it)
	},
	-- a hit on a body already dead takes this share of its knock: a nudge, not a throw (user 2026-10-22: "reduce the
	-- knockback on shooting fallen/dead npc's")
	corpse = 0.2,
	-- A limp body that still stands upright (its torso's up within `upright` of straight up, as cos) from `after` s
	-- into a knock is tipped over the way it was thrown (`spin` rad/s, `push` studs/s), again every `every` s while it
	-- stands, for `window` s, by whichever side simulates it (user 2026-10-17: "headshots dont ragdoll with enough
	-- force to fall on the ground sometimes"; a dead body passes to the server some time after the death)
	-- The server throws a dead body it owns `settle` s after the death, holding the throw for `hold` s.
	Tip = { after = 0.3, every = 0.25, window = 3, upright = 0.75, spin = 9, push = 3, settle = 0.1, hold = 0.1 },
	-- A hit that hurts keeps a live soldier down longer the more it took (Rules/Ragdoll.getUp; user 2026-10-22: "add
	-- longer ragdolls for more damage taken"): the get-up wait runs from `floor` s at no damage up to `ceiling` s at
	-- `full` damage and more, in a straight line, never shorter than the knock's own `getUp`. A knock that does no
	-- damage (the staff's recoil, the float fall, your own blast's throw) keeps its own `getUp`.
	ByDamage = { floor = 0.5, ceiling = 2.5, full = 90 },
	-- the knocks a player may ask for on itself (Net "KnockSelf": the staff's recoil, the float fall)
	SelfKnocks = { StaffRecoil = true, FloatFall = true },
	SelfRate = 2, -- "KnockSelf" requests a second at most (and burst)
	-- the client shows a knock it asked for at once and waits this long for the server's ragdoll before giving up
	SelfWait = 1.5,
	-- A server-owned soldier (a bot, a dev dummy: no client of its own) getting up is stood upright on its feet where it
	-- lies, facing the way it lay, then left to the Humanoid's GettingUp (user 2026-10-31: "npc's that ragdoll dont
	-- stand back up properly"): the ground found by a ray `probe` studs down from the torso, the body put `lift` studs
	-- over standing height; FallingDown and Ragdoll, the Humanoid's own tip-over states, are off for them for good (a
	-- body just stood up tipped straight back over)
	Stand = { probe = 8, lift = 0.25 },
}

return table.freeze(Ragdoll)
