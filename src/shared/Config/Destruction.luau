--!strict
-- Building destruction tuning. Design: docs/DESTRUCTION.md. Values are first guesses for playtesting.

local Destruction = {
	SectionWidth = 6, -- target wall-section width; each story of each wall splits into ~6-stud sections
	SectionTag = "DestructibleSection",
	DoorTag = "Door",
	BuildingTag = "NaturalBuilding",

	-- Per material class: section HP, whether rifle bullets pass through it, whether fire spreads on it.
	Materials = {
		Wood = { hp = 300, bulletPenetrable = true, flammable = true },
		Plaster = { hp = 450, bulletPenetrable = false, flammable = false },
		Brick = { hp = 700, bulletPenetrable = false, flammable = false },
		Stone = { hp = 1000, bulletPenetrable = false, flammable = false },
		Tile = { hp = 250, bulletPenetrable = false, flammable = false }, -- roof panels
		Thatch = { hp = 200, bulletPenetrable = true, flammable = true }, -- thatched roof panels: burns well
		Glass = { hp = 1, bulletPenetrable = true, flammable = false }, -- window panes: any hit shatters
		Door = { hp = 150, bulletPenetrable = true, flammable = true }, -- doors: blown off by explosives
	},

	-- A story collapses (with every story above it) when its standing wall sections fall below this
	-- fraction of the original.
	-- (0.35, then 0.6 for "2-3 full blasts at a wall bring a story down"; user 2026-10-17 later: "a stage 3 blast
	-- should not crumble a building (unless it removes all its supporting structures)": a story falls once 3/4 of its
	-- walls are gone)
	CollapseSupportFraction = 0.25,

	-- Support (src/server/Destruction, user 2026-10-23: "anything not supported should fall"): pieces of a building count
	-- as touching within this many studs of each other; what has no chain of touching pieces down to the ground drops.
	SupportTouch = 0.25,

	-- A blast breaks a ragged, round-ish hole (user 2026-10-18: building damage "is always a square"): a broken wall
	-- section of a `kinds` kind is cut into ~`cell`-stud cells; those within the class's fail distance of the blast (at
	-- least the section's own distance + `minBite`), give or take `jitter` x that, break off, the rest stays standing as
	-- "Remains" of the section (`remainsHP` x its MaxHP, not counted as a wall for collapse). Each row's cells merge
	-- into runs, so a ragged edge costs a few parts.
	Jag = { kinds = { Wall = true, Gable = true }, cell = 1.5, jitter = 0.3, minBite = 2, remainsHP = 0.3 },

	-- Client-side fracture debris (visual only, never replicated, never collides with players).
	-- They fly until at rest (`Rest`, Rules/Destruction.rested, checked every `Rest.every` s), then freeze where they lie
	-- (anchored: no physics) and stay `lifetime` s in all (user 2026-10-17: destroyed assets "should stay for some time"
	-- without lag); past `maxLive` the oldest go first. A frozen chunk wakes and falls again when what it may lie on
	-- goes (a chunk under it, a broken section; Rules/Destruction.leanedOn within `wakeMargin` studs). Was: frozen 3 s
	-- after the break wherever it was (user 2026-10-23: "blown up buildings should not have floating blocks").
	Debris = {
		chunksPerSection = 6,
		-- a broken piece is cut into ~`cell`-stud chunks (at most chunksPerSection); glass into ~`Glass.cell`-stud shards
		-- (at most `Glass.max` per pane; user 2026-10-25: "the glass just breaks off, not shatters": at 2.5-stud chunks
		-- a window pane came off in one piece), and a `Glass.brief` share of them is gone after `Glass.briefLife` s (no
		-- part of maxLive; user 2026-10-25: 0.6-stud shards were too many, "make glass shards break in bigger pieces or
		-- have some disappear")
		cell = 2.5,
		Glass = { cell = 1.2, max = 8, brief = 0.5, briefLife = 1.5 },
		lifetime = 60,
		maxLive = 600,
		-- (was still 1.5 / spin 2: Studio 2026-10-24 froze a chunk 1.3 studs over the one under it, caught at 1.25 studs/s
		-- as it began to fall)
		Rest = { still = 0.3, spin = 0.5, time = 0.4, after = 0.5, maxFly = 15, every = 0.1 },
		wakeMargin = 1.5,
		-- a blast's crater reaches the clients after its debris (big terrain edits replicate slowly; Studio 2026-10-24:
		-- frame bars froze on the old ground 4-5 studs over a howitzer crater): frozen chunks over the churned ground
		-- (Rules/Blast.churnFromReach) wake again this many seconds after the blast
		craterWake = { 1, 3 },
		-- a chunk come to rest over `height` studs above the ground or floor under it (a pile of chunks: corner stones
		-- spawned block on block stood as 6-8 stud columns, Studio 2026-10-24) is knocked over instead of frozen: `push`
		-- studs/s to a random side, `spin` rad/s, at most `tries` times (Rules/Destruction.topples)
		Pillar = { height = 4, push = 12, spin = 6, tries = 3 },
		-- how hard each kind of piece is thrown (Config/Damage.Blast.Destroy bands; user 2026-10-23): x the old blast
		-- throw (18-34 studs/s away, 8-22 up, less from far off). Crumpled chunks drop near where they were; glass
		-- shatters as before; a piece that lost its support (or a collapsing story) only drops. Every chunk also gets a
		-- nudge of up to `fallNudge` studs/s to a random side and `fallSpin` rad/s, so it tumbles into a heap (straight
		-- down, a chimney froze as a 15-stud column of loose chunks and corner stones in 5-8 stud columns: Studio
		-- 2026-10-24). A pane a bullet breaks: its shards go `shot` x that, on along the bullet (Config/Firing.Shatter).
		Push = { crumple = 0.25, glass = 1, dust = 1.3, shot = 0.35 },
		fallNudge = 8,
		fallSpin = 5,
		-- a pulverised piece: `shards` small chunks of at most `shard` studs, thrown hard and gone after `shardLife` s
		-- (no lasting rubble), and a puff of dust (Config/Palette.Buildings.Dust, `tint` of the way from its own colour)
		-- per ~`puffEvery` studs of its length (1 to 3), `puffSize` x its size (at most `puffMax`) growing `grow` x and
		-- fading from `alpha` over `puffTime` s; at most `maxPuffs` per break.
		Dust = {
			shards = 2,
			shard = 0.8,
			shardLife = 2,
			puffEvery = 4,
			puffSize = 0.6,
			puffMax = 4,
			grow = 2.2,
			alpha = 0.35,
			puffTime = 1.2,
			tint = 0.5,
			maxPuffs = 30,
		},
	},

	-- Natural map buildings cannot be repaired; only player-built assets can.
	NaturalRepairable = false,
}

return table.freeze(Destruction)
