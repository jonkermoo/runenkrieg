--!strict
-- The blast flinch (src/server/Flinch, src/client/Flinch, Rules/Flinch; user 2026-10-22: "when you are close to an
-- explosion (but not rag doll radius of course) your character ducks (a tiny tiny tiny bit) and hold their helmet (only
-- when nothing is equipped)"). A soldier with nothing in the hands, not knocked down by a blast but near it, ducks a
-- little and puts the right hand to the helmet. Data only.

local Flinch = {
	-- the band: from where the blast stops knocking soldiers down (Config/Damage.Blast.Soldier.from, ~126 kPa; a
	-- grenade's splinters' `wound`) out to `kpa` of overpressure or `beyond` x that edge, whichever is further. Knock edge
	-- -> outer edge: stage 2 staff (0.5 kg) ~6 -> 14, a 2.5 kg shell ~9 -> 24, the stage 3 staff (10 kg) ~15 -> 38, a
	-- 50 kg bomb ~26 -> 64, the 400 kg shell ~51 -> 128; a Mills (splinters to 28) 28 -> 42.
	kpa = 20,
	beyond = 1.5,
	-- the track's weight: 1 at the knock edge (and behind cover inside it), `least` at the outer edge. 1 for now: under
	-- full weight the hand blends back toward the idle's and stops short of the helmet (Studio 2026-10-22: at 0.82 the
	-- hand sat 0.45 out from the brim)
	least = 1,
	-- a flinch already playing isn't started again by a blast within this many seconds of it (a barrage)
	Again = 0.5,
	Fade = 0.08, -- fade in / out (s)
	-- tools/animation/flinch.luau (FlinchOne approved 2026-10-22), 0.95 s, Action2, split in two (user 2026-10-25:
	-- crouched, the old one stood the soldier up and he floated): the hand to the helmet and the head's duck, over any
	-- stance (arms and head only); and the torso's small dip, only standing still and upright (`Dip`; root only)
	Animation = { id = 92646693297394 },
	Dip = { id = 133653464187124 }, -- standing still: under Config/Locomotion.IdleBelow
}

return table.freeze(Flinch)
