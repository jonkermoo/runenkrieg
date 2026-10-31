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
		-- the zone-capture FFA map (tools/ui/sketchmap_playtest.py; user 2026-10-30: "make the hold v to show map appear
		-- for FFA mode ... also the title mode too. just have your player and the moving point"): the same image shape
		Playtest = {
			image = 118349306770950,
			size = { 1024, 516 },
			pad = 24,
			x = { -180, 180 },
			z = { 2713.69, 2886.31 },
		},
	},
	-- in play (src/client/ModeHud): top left, under the top bar, in reference pixels at an 800-pixel-tall screen (the
	-- chat sits under it, Config/Chat.Panel.y); height = width x aspect (the image's)
	Hud = { x = 12, y = 10, width = 360, aspect = 516 / 1024 },
	-- sizes as shares of the drawn area's width
	Point = { radius = 0.028, hqRadius = 0.034, ring = 0.005, rune = 0.62 }, -- a rune's height in its circle's width
	Label = { size = 0.038, below = 0.008 }, -- a point's name under it
	Border = { thick = 0.0016, dash = 0.012, gap = 0.009, transparency = 0.35 }, -- the sector borders (dashed blue)
	Front = { thick = 0.0075 }, -- the front (ink)
	You = { size = 0.05 }, -- the local soldier's arrow in play, across
	Teammate = { size = 0.022, edge = 0.003 },
	Zone = { size = 0.05, flash = 0.4 }, -- the FFA zone's mark, across; a contested one flashes every `flash` seconds -- a teammate's dot, across (under a point's seal), and its ink edge
	Deploy = { ring = 1.9, thick = 0.004 }, -- the loadout's ring round where you deploy: radii of its point, line
	WashTransparency = 0.55, -- each side's land
	WashBands = 32, -- the washes are this many strips, top to bottom (their steps hide under the front's ink)
	ContestedPulse = 0.9, -- seconds per beat of a contested point's amber ring
	-- the 9-slice ink plate under buttons and HUD plates (tools/ui/inkslab.py)
	Slab = { image = 89920834909168, white = 134469007922216, slice = { 28, 28, 228, 100 } }, -- white: for tinting
	-- the 9-slice paper sheet with a torn edge and ink rim, under paper panels (the settings notebook;
	-- tools/ui/papersheet.py)
	Paper = { image = 81557441306335, slice = { 44, 44, 212, 212 } },
}

return table.freeze(SketchMap)
