--!strict
-- The movement set in play (Config/Locomotion.Set, user 2026-10-20: the "serious" set, the "veteran" one kept): its
-- animations over the ones both sets share, and the third-person weapon holds it rebuilt for its own torso leans
-- (sprint carry, crouched holds) over Config/Weapons'.

local MovementSet = {}

-- every movement animation of the set in play, by name (Config/Locomotion.Animations plus the set's own)
function MovementSet.animations(cfg: any): { [string]: any }
	local out = table.clone(cfg.Animations)
	for name, a in cfg.Sets[cfg.Set].Animations do
		out[name] = a
	end
	return out
end

-- a weapon's third-person holds (Config/Weapons) with the set's rebuilt ones in place
function MovementSet.holds(cfg: any, weapon: string, holds: { [string]: number }): { [string]: number }
	local own = cfg.Sets[cfg.Set].Holds
	local over = own and own[weapon]
	if not over then
		return holds
	end
	local out = table.clone(holds)
	for hold, id in over do
		out[hold] = id
	end
	return out
end

return MovementSet
