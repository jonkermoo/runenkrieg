--!strict
-- Staff spells (user 2026-10-13): three beams by how long left click is held. Pressing opens the first circle; holding
-- past a stage's `hold` reaches it (its circle opens, Config/Vfx.Cast; stage 3's assembles slowly before it) and
-- release fires the stage reached. A stage not in `Built` fires the highest built one below it. Rules/Spells reads
-- this. Seconds. Data only.

local Spells = {
	Stages = {
		{ name = "Quick", hold = 0 }, -- a tap
		{ name = "Medium", hold = 0.45 },
		{ name = "Full", hold = 2.6 }, -- noticeably longer to charge (user 2026-10-13, twice)
	},
	Built = { Quick = true, Medium = true, Full = true }, -- the stages built so far

	-- Mana (src/client/StaffAttack, the bar: src/client/ManaBar; user 2026-10-13: "fits 6 quick shots, 3 charged shot,
	-- and 1 mega shot ... after 1 mega shot you need to fully reload the bar before firing", and an extended cooldown
	-- for the mega shot). In quick-shot units: `max`, `cost` per stage. A charge stops at the highest stage you can pay
	-- for and waits there until the mana is in (refilling while it waits); with too little for a quick shot nothing
	-- fires. Refills `regen` units/s, `delay` s after a shot. A mega shot burns the bar out: nothing fires until it's full again,
	-- and it only starts refilling after `burnout.delay` s, at `burnout.regen` (the mega's extended cooldown: 1.5 +
	-- 6 / 0.75 = 9.5 s, against 4.8 s for a normal full refill).
	Mana = {
		max = 6,
		cost = { 1, 2, 6 },
		regen = 1.25,
		delay = 0.7,
		burnout = { delay = 1.5, regen = 0.75 },
	},

	-- The staff's attack (src/client/StaffAttack; user 2026-10-13). Visual only, on the caster's client for now.
	-- - Not aiming: left click is a quick fire (stage 1) at once from the staff's head toward the crosshair, turned by
	--   the first-person sway (it sways with the steps like a gun) inside a random cone: Hip.spread, more while walking
	--   (+ walkSpread at full walk speed).
	-- - Aiming (right mouse): the first circle opens and is held ready; a click fires it, holding charges stages 2 and 3
	--   (Stages above). Stage 1 and 2 shots chain while aiming: the next circle opens once the cooldown is over.
	-- - Every shot: no firing for Cooldown[stage] seconds, and walking slowed to Slow[stage] of its speed for as long
	--   (the staff's recoil), standing still or not.
	-- - Charging: walking slows from Charge.from (at the press) to Charge.to (just before stage 3 is ready); once stage 3
	--   is ready you can't move or jump. The camera sway grows the same way (Config/Sway.Charge).
	-- - Sprinting: no firing and no aiming.
	Staff = {
		-- the look of the magic (Config/Vfx.Schemes: Arcane, Hex, Ember, Verdant, Solar, Void; user 2026-10-13: made,
		-- not yet given to anything)
		Scheme = "Arcane",
		Hip = { spread = 2.5, walkSpread = 4 }, -- degrees (half-angle of the cone)
		Cooldown = { 0.45, 1.0, 2.2 }, -- per fired stage, seconds (stage 3 includes the fall and getting up)
		Slow = { 0.75, 0.5, 0.35 }, -- walk speed share while it lasts
		Charge = { from = 0.85, to = 0.3 },
		-- the left hand joins the staff halfway through the build to stage 3 (user 2026-10-13: "midway have the player
		-- start using 2 hands"); it stays on until aiming ends, even after a stage 2 shot
		TwoHands = 1.6,
		-- first person: the left arm shows (src/client/Viewmodel) from this far into a charge, as the charge animation
		-- starts bringing it up to the shaft (tools/animation/staff.luau charge keys: 1.2 hanging, 1.6 halfway, 2.0 on); held in one
		-- hand it's hidden (it hung at the rig's rest pose in the lower left of the view)
		LeftShows = 1.3,
		-- the third-person charge keeps shaking at its peak once stage 3 is ready: the animation's last ChargeLoop
		-- seconds play over and over (tools/animation/staff.luau READY_LOOP)
		ChargeLoop = 0.6,
		-- In the air while aiming: floating (user 2026-10-13). Gravity is cancelled and the body carried slowly (at most
		-- `rise` studs/s, following at `follow` per second, eased in over ~1/`ease` s) to the height it left the ground
		-- from plus the jump's height (Humanoid.JumpHeight) plus `extra`, and hovers there bobbing `bob` studs at
		-- `bobRate` Hz ("hover to the initial max jump height slowly ... a little higher is fine"). After `hover`
		-- seconds it sinks at `descend` studs/s. Falling below the height it left the ground from, after floating, knocks
		-- it down (Config/Ragdoll.Knocks.FloatFall). The float cycle plays; a charge leans back
		-- (Config/Weapons staff `holds.airCharge`). Landing ends it at once.
		-- `below`: how far under the takeoff height counts as fallen below it (landing back level never does)
		Float = {
			rise = 3.5,
			follow = 4,
			ease = 5,
			extra = 0.5,
			bob = 0.12,
			bobRate = 0.6,
			hover = 5,
			descend = 1.5,
			below = 0.3,
			-- no moving about while floating, only up to the hover height (user 2026-10-13: "we cant move freely while
			-- floating"): the walk keys do nothing and the jump's sideways speed dies away at this rate (per second)
			brake = 6,
		},
		-- (the aiming laser shows only while left click is held: the charge; user 2026-10-13)
		-- first person, aiming: the cast starts this far past the staff's head along the line to the crosshair, the
		-- circles opening ahead of it facing where the beam will hit, so the staff (turned onto the crosshair,
		-- Config/Weapons staff `aimConverge`) points through their centres (user 2026-10-13: "the staff in line with the
		-- center of the circle")
		Lead = 0.6,
		-- ...drawn at this size (circles and spacing; user 2026-10-13: "make the first person circle clientside but
		-- use the same circle animation"): at full size the stage 3 circle filled the view
		-- (user 2026-10-13: closer, "so it looks huge in first person"; was 0.6 / 1.7)
		ViewScale = 0.75,
		-- ...and spaced this much further apart (user 2026-10-13: "distance the circles more in first person")
		ViewSpread = 1.05,
		-- the caster's own circles and charge while held (first and third person; user 2026-10-16): this see-through (0 = solid, 1 = invisible),
		-- dimming their glow as much; solid once fired (user 2026-10-13: "translucent in client side first person and
		-- fully visible once fired"; tuned from captures)
		-- (user 2026-10-13: "even more transparent, i can still barely see through the circles"; was 0.6)
		Veil = 0.8,
		-- aiming: each stage's circle its own see-through, visibly different (user 2026-10-13): the first faintest, the
		-- big third the most solid
		StageVeils = { 0.88, 0.74, 0.58 },
		-- ...and each circle opened before the newest one this much more again (compounding), so the older ones don't
		-- overshadow the new (user 2026-10-13; was 0.5 with one veil for all)
		OlderVeil = 0.3,
		-- a stage 3 shot's knock back into a ragdoll: Config/Ragdoll.Knocks.StaffRecoil
	},
}

return table.freeze(Spells)
