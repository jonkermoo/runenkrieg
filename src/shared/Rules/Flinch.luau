--!strict
-- Who flinches at a blast (Config/Flinch; user 2026-10-22: "when you are close to an explosion (but not rag doll
-- radius of course) your character ducks ... and hold their helmet (only when nothing is equipped)"). The band starts
-- where the blast stops knocking soldiers down (Rules/Blast: no damage below Config/Damage.Blast.Soldier.from, or a
-- grenade's splinters' `wound`) and reaches out to `kpa` of overpressure, or `beyond` x that edge, whichever is
-- further. Pure: distances in studs (the caller works out the blast's reaches with Rules/Blast.reachOf).

local Flinch = {}

export type Cfg = { kpa: number, beyond: number, least: number }

-- The band of a blast whose damage ends at `hurts` studs (Blast.reachOf Soldier.from), its splinters' at `wound` (nil:
-- none), its overpressure falling to `kpa` at `faint` (Blast.reachOf f.kpa): where it stops knocking soldiers down and
-- how far out they flinch.
function Flinch.band(hurts: number, wound: number?, faint: number, f: Cfg): (number, number)
	local knock = math.max(hurts, wound or 0)
	return knock, math.max(faint, knock * f.beyond)
end

-- How hard a soldier `d` studs from the blast flinches (the track's weight): nil when they don't. Not one it knocked
-- (`knocked`: it hurt and flung them), nor with something in the hands (`armed`), nor down already (`down`: ragdolled
-- or dead). Inside the knock reach (behind cover that took it all) in full; from the knock edge out, `1` fading to
-- `least` at `outer`.
function Flinch.weight(
	d: number,
	knock: number,
	outer: number,
	knocked: boolean,
	armed: boolean,
	down: boolean,
	f: Cfg
): number?
	if knocked or armed or down or d > outer then
		return nil
	end
	if d <= knock or outer <= knock then
		return 1
	end
	return 1 - (1 - f.least) * (d - knock) / (outer - knock)
end

return Flinch
