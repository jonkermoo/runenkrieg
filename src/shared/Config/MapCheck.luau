--!strict
-- The map checker (roadmap 2.1; Rules/MapCheck, tests/mapcheck.spec.luau, report: `lune run tests/mapreport`): reach,
-- falls, sight lines and travel times over a map's ground, trees and buildings. Units: studs, seconds.

local MapCheck = {
	Cell = 6, -- grid step over the playable area
	WadeDepth = 2.5, -- deeper water than this blocks walking (the river is crossed at its fords)
	TrunkRadius = 1.2, -- a trunk blocks walking this far round it, x the tree's scale
	-- a canopy as a ball for sight: centred at `centre` x the tree's height, `radius` x the height
	Canopy = { centre = 0.68, radius = 0.2 },
	RoofHeight = 6, -- a building blocks sight up to its stories plus this
	TargetHeight = 4.5, -- a standing soldier is seen when the line to his head is clear (Metrics.Character.EyeHeight)
	Directions = 16, -- sight lines looked down from each sector centre
	Step = 3, -- along a sight line
	-- Each spawn's sprint time to its own nearest sector and to the neutral centre sector (s, over the real ground),
	-- and how much longer one team's run to the centre may be than the other's (share).
	Limits = { ownFirst = 30, centre = 90, fairness = 0.2 },
	PocketCells = 12, -- walkable pockets you can't walk into up to this many cells are reported, not failed
}

return table.freeze(MapCheck)
