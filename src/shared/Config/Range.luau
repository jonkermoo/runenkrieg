--!strict
-- The dev test range (built by src/dev/Range, dev place only): a space off the map to test movement, animations and
-- firing. Layout only; every obstacle size comes from Config/Metrics in the builder (ledges, cover, slopes, stairs,
-- door, window, trench), so the range always tests the real contract.
-- Local layout: x across, -z downrange; origin = the centre of the firing line, y = 0 is the floor top.

local Range = {
	Origin = { 1000, 0, -2600 }, -- world position of the firing line centre (off the map, past the gallery)

	Colors = {
		Floor = { 104, 128, 76 },
		Lane = { 92, 114, 66 },
		Line = { 230, 226, 210 },
		Block = { 150, 146, 136 },
		Target = { 200, 196, 182 },
		TargetHead = { 176, 70, 58 },
		Stage = { 120, 118, 112 },
	},

	-- Firing range: floor from behind the firing line to past the farthest target.
	Firing = {
		Width = 64,
		Behind = 30,
		Beyond = 20, -- floor past the farthest target
		-- one body-sized target per distance (studs from the firing line), staggered across the lanes so near
		-- targets don't hide far ones; the last is Metrics.Combat.RifleEffectiveRange
		Targets = {
			{ distance = 25, x = -20 },
			{ distance = 50, x = -12 },
			{ distance = 100, x = -4 },
			{ distance = 200, x = 4 },
			{ distance = 300, x = 12 },
			{ distance = 450, x = 20 },
		},
		-- firing positions along the line (x): open ground, a trench bay with a firestep, a wall with a window
		OpenX = -18,
		TrenchX = 0,
		WindowX = 18,
		TrenchLength = 14,
		WindowWallWidth = 10,
	},

	TargetThickness = 0.4,
	HeadSize = 1.25, -- the R6 head block

	-- Movement course, to the right of the firing range, running downrange (-z).
	Course = {
		StartX = 50,
		LaneLength = 100, -- sprint / walk timing lane
		MarkEvery = 10,
		SlopeOffset = 5, -- degrees either side of Metrics.Movement.MaxSlopeAngle
		BlockDepth = 6,
		Gap = 6,
	},

	-- Animation stage, to the left of the firing range: a flat pad with a grid to read motion against.
	Stage = { X = -60, Size = 24, Grid = 2 },
}

return table.freeze(Range)
