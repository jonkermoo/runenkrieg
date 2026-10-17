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
	CollapseSupportFraction = 0.35,

	-- Client-side fracture debris (visual only, never replicated, never collides with players).
	-- They fly for `settle` s, then freeze where they lie (anchored: no physics) and stay `lifetime` s in all (user
	-- 2026-10-17: destroyed assets "should stay for some time" without lag); past `maxLive` the oldest go first.
	Debris = { chunksPerSection = 6, settle = 3, lifetime = 60, maxLive = 600 },

	-- Natural map buildings cannot be repaired; only player-built assets can.
	NaturalRepairable = false,
}

return table.freeze(Destruction)
