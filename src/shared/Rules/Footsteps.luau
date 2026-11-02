--!strict
-- Footsteps (Config/Footsteps, src/client/Footsteps): the ground a step lands on, how loud it is and whether it is
-- played at all, and where its recording sits in the sheet. Pure: studs, seconds.

local Footsteps = {}

-- What a foot lands on: `terrain` the terrain material's name when it is terrain, else the part's building `class`
-- (nil when it has none) and its `name`.
function Footsteps.surface(cfg: any, terrain: string?, class: string?, name: string?): string
	if terrain then
		return cfg.Terrain[terrain] or cfg.TerrainDefault
	end
	if class and cfg.Class[class] then
		return cfg.Class[class]
	end
	if name then
		for _, rule in cfg.Names do
			if string.find(name, rule[1], 1, true) then
				return rule[2]
			end
		end
	end
	return cfg.PartDefault
end

-- A step's volume by gait and surface (`own`: this player's own soldier).
function Footsteps.volume(cfg: any, gait: string, surface: string, own: boolean): number
	return cfg.Volume * (cfg.Gait[gait] or 1) * (cfg.Surface[surface] or 1) * (if own then cfg.Own else 1)
end

-- Whether a step `distance` studs from the listener is played at all.
function Footsteps.heard(cfg: any, gait: string, distance: number): boolean
	return distance <= (cfg.Range[gait] or cfg.Range.walk)
end

-- How many recordings `surface` has (its group in the sheet: Config/Footsteps.Recordings, else its own name).
function Footsteps.count(cfg: any, surface: string): number
	return cfg.Count[cfg.Recordings[surface] or surface] or 0
end

-- Where the `k`th recording (1-based, wrapping) of `surface` starts in the sheet, and how long it plays.
function Footsteps.slot(cfg: any, surface: string, k: number): (number, number)
	local group = cfg.Recordings[surface] or surface
	local first = 0
	for _, g in cfg.Order do
		if g == group then
			local i = (k - 1) % cfg.Count[g]
			return (first + i) * cfg.Slot, cfg.Length
		end
		first += cfg.Count[g]
	end
	error(`no footsteps for surface {surface}`)
end

return Footsteps
