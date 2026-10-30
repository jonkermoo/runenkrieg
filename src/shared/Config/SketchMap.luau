--!strict
-- The sketch map (UI overhaul, Field Grimoire; user 2026-10-30: the Territory Push display, top right in play, and the
-- live match on the title screen): a hand-drawn map of the map, with the sector borders, the points and the front
-- drawn live over a still image of the ground (tools/ui/sketchmap.py draws it from Config/Maps/Map1). src/client/
-- SketchMap builds it, src/client/Ink draws the lines and runes. Colours: Config/Palette UI.Grimoire. Data only.

local SketchMap = {
	-- the still image per map key: its asset, its size in pixels, the pad round the area it covers (the torn edge)
	-- and the studs that area covers (user 2026-10-30: "cut more of the left and right edges", just past each spawn)
	Maps = {
		Map1 = {
			image = 135864882300996,
			size = { 1024, 516 },
			pad = 24,
			x = { 70, 1740 },
			z = { -400, 400 },
		},
	},
	-- sizes as shares of the drawn area's width
	Point = { radius = 0.019, hqRadius = 0.023, ring = 0.004, rune = 0.62 }, -- a rune's height in its circle's width
	Label = { size = 0.026, below = 0.012 }, -- a point's name under it
	Border = { thick = 0.0016, dash = 0.012, gap = 0.009, transparency = 0.35 }, -- the sector borders (dashed blue)
	Front = { thick = 0.0075 }, -- the front (ink)
	WashTransparency = 0.55, -- each side's land
	WashBands = 32, -- the washes are this many strips, top to bottom (their steps hide under the front's ink)
	ContestedPulse = 0.9, -- seconds per beat of a contested point's amber ring
	-- the 9-slice ink plate under buttons and HUD plates (tools/ui/inkslab.py)
	Slab = { image = 89920834909168, slice = { 28, 28, 228, 100 } },
}

return table.freeze(SketchMap)
