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
	-- The dev test caster (src/client/SpellTest): DEV place, dev tools on, nothing in the hands; left click fires from
	-- where a raised staff's tip would be toward the aim. Visual only, on this client. Tip: in the Torso's space (in
	-- front of the right shoulder, 4 studs up: the 7-stud circle clears the ground).
	Test = { PlaceId = 103459731368962, Tip = { 1.2, 1, -1.2 } },
}

return table.freeze(Spells)
