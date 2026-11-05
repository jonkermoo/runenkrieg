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
	-- a festival lantern pole (Lantern Meadows): a post `height` high, a crossbar `arm` across its top, a paper lantern
	-- hanging off each end
	LanternPole = { height = 11, arm = 3.4 },
	-- the railway (a map's village.railX, src/dev/Greybox/VillageBuild): two rails `gauge` apart, `height` over the
	-- bed, on sleepers (`sleepers` to a `segment`), each segment laid on the highest ground under it (`samples` along it,
	-- across the sleepers' width; Rules/Village.railBed: the ground never rises over a rail), `beyond` past the bounds
	Railway = { gauge = 4.7, height = 0.45, segment = 4, sleepers = 2, samples = 3, beyond = 150 },

	-- River bridges (a map's river.bridges, src/dev/Greybox/Bridges). A footbridge: `plank`-thick deck laid in `step`
	-- lengths, posts every `postEvery` with a top rail `railHeight` over the deck, trestle legs `leg` thick at `legsAt`
	-- of the way across, down to the river bed. A broken bridge: stone stumps `stoneHeight` over their bank end's ground,
	-- the fallen span `drop` degrees down off each into the water, and `rubble` blocks in the river between.
	Bridge = {
		plank = 0.6,
		step = 4,
		postEvery = 8,
		post = 0.5,
		railHeight = 3,
		leg = 0.8,
		legsAt = { 0.3, 0.5, 0.7 },
		stoneHeight = 5,
		span = 9,
		drop = 24,
		rubble = 3,
		-- a ford's rocks (a ford with `rocks`, src/dev/Greybox/Bridges): stepping stones `rock` across (min, max), one
		-- every `rockStep` (min, max) along a line winding `rockWobble` either side of the square crossing (plus
		-- `rockJitter`), each topped `rockTop` (min, max) over the water and tilted up to `rockTilt` degrees; `pebbles`
		-- half-sunk stones `pebble` across strewn up to `pebbleSpread` off the path; `bankRocks` boulders at each end
		rock = { 2.2, 3.6 },
		rockStep = { 2.8, 4.0 },
		rockWobble = 2.2,
		rockJitter = 0.8,
		rockTop = { 0.4, 0.9 },
		rockTilt = 9,
		pebbles = 18,
		pebble = { 0.8, 1.6 },
		pebbleSpread = 9,
		bankRocks = 2,
	},

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
		"LanternPole",
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
