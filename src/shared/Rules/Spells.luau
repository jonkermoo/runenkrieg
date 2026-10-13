--!strict
-- Staff spell stages from the hold time (Config/Spells). Pure.

local Spells = {}

export type Stage = { name: string, hold: number }

-- The stage reached after holding left click `held` seconds: the last one whose `hold` it passed.
function Spells.stage(stages: { Stage }, held: number): number
	local reached = 1
	for i, s in stages do
		if held >= s.hold then
			reached = i
		end
	end
	return reached
end

-- The stage that actually fires: the reached one if it is built, else the highest built one below it.
function Spells.firing(stages: { Stage }, built: { [string]: boolean }, held: number): number?
	for i = Spells.stage(stages, held), 1, -1 do
		if built[stages[i].name] then
			return i
		end
	end
	return nil
end

return Spells
