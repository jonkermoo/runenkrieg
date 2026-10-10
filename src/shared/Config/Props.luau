--!strict
-- Village props (src/dev/Props): dimensions in studs. Heights follow Config/Metrics.Cover:
-- garden walls and fences are hoppable (<= HopableLedgeMax); hedges block movement and sight.

local Props = {
	-- Linear props, built along a segment and following the ground.
	StoneWall = { height = 2.0, thickness = 1.6, stone = 1.4, class = "Stone" },
	PicketFence = { height = 2.0, picketGap = 0.9, postEvery = 6, class = "Wood" },
	RailFence = { height = 2.0, postEvery = 5, class = "Wood" },
	Hedge = { height = 4.2, thickness = 2.4, class = "Wood" },

	Pole = { height = 22, spacing = 48, class = "Wood" },
	Wire = { sag = 1.2, segments = 4 },
	Signpost = { height = 7.5 },

	-- Kinds a village plot boundary can use, picked by hash per plot.
	BoundaryKinds = { "StoneWall", "StoneWall", "PicketFence", "RailFence", "Hedge" },

	-- Yard clutter placed beside houses (Rules/Village), picked by hash.
	YardKinds = { "Woodpile", "Barrels", "Cart", "Haystack", "Trough" },
	YardChance = 0.55,

	-- Library samples (gallery) for the linear props.
	SampleLength = 16,
	Kinds = {
		"StoneWall",
		"PicketFence",
		"RailFence",
		"Hedge",
		"Pole",
		"Signpost",
		"Well",
		"Trough",
		"Barrels",
		"Woodpile",
		"Haystack",
		"Cart",
		"Car",
	},
}

return table.freeze(Props)
