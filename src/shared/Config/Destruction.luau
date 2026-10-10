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
		Glass = { hp = 1, bulletPenetrable = true, flammable = false }, -- window panes: any hit shatters
		Door = { hp = 150, bulletPenetrable = true, flammable = true }, -- doors: blown off by explosives
	},

	-- A story collapses (with every story above it) when its standing wall sections fall below this
	-- fraction of the original.
	CollapseSupportFraction = 0.35,

	-- Client-side fracture debris (visual only, never replicated, never collides with players).
	Debris = { chunksPerSection = 6, lifetime = 6, maxLive = 400 },

	-- Natural map buildings cannot be repaired; only player-built assets can.
	NaturalRepairable = false,
}

return table.freeze(Destruction)
