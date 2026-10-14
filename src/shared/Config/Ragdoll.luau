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
	},
}

return table.freeze(Ragdoll)
