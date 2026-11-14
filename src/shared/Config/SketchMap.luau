--!strict
-- The sketch map (UI overhaul, Field Grimoire; user 2026-10-30: the Territory Push display, top right in play, and the
-- live match on the title screen): a hand-drawn map of the map, with the sector borders, the points and the front
-- drawn live over a still image of the ground (tools/ui/sketchmap.py draws it from Config/Maps/Map1). src/client/
-- SketchMap builds it, src/client/Ink draws the lines and runes. Colours: Config/Palette UI.Grimoire. Data only.

local SketchMap = {
	-- the still image per map key: its asset, its size in pixels, the pad round the area it covers (the torn edge)
	-- and the studs that area covers (user 2026-10-30: "cut more of the left and right edges", just past each spawn)
	Maps = {
		-- cropped closer to the spawns (user 2026-10-31: "cut off more unnecessary parts of the map and expand it"); redrawn
		-- for the longer, narrower map (2026-11-01; was 87971867576424, 1024 x 542 over x 120..1700, z -400..400)
		-- redrawn for the rebuilt map (2026-11-10: its east HQ at x 2420 fell off the old 120..2330 frame): both HQs
		-- with room round them (tools/ui/sketchmap_ground.py from tools/ui/sketchmap_export.luau; was 88967963615019,
		-- the Image behind the uploaded Decal 136207333793204, over x 120..2330)
		Map1 = {
			-- painted from the map itself (user 2026-11-12 "Map A", a staff map on parchment: the terrain's form lines and
			-- shade, the river as it lies, every tree, roof, road, hedge and wall, exported from the place and drawn by
			-- the local tools/gunart/build_map.py + final_map.py; was 84146277958910, the 2026-11-11 stretch's)
			image = 135591178368016,
			size = { 1024, 252 },
			pad = 24,
			x = { 80, 2760 }, -- (the 2026-11-11 stretch, points 600 apart and 560 wide; was 270..2570, 1024 x 286)
			z = { -280, 280 },
		},
		-- the campaign's opening map (map vote, user 2026-11-02): the same area as Map 1's image, in world z (its middle
		-- line at z -6000); drawn like Map 1's from Config/Maps/LanternMeadows and its village layout (the Image behind
		-- the uploaded Decal 110579689265385)
		-- redrawn for the reworked map (2026-11-10: the east HQ at x 2420 fell off the old 120..2330 frame, "HQ is off
		-- the map"): both HQs with room round them, centred on the points (tools/ui/sketchmap.py from
		-- tools/ui/sketchmap_export.luau; was 107148285709134 over x 120..2330, z -6280..-5720)
		LanternMeadows = {
			image = 115752208035587, -- (the Image behind the uploaded Decal 98705614522282; redrawn for the 2026-11-11
			-- stretch, was 124788788277258 behind 96847302300448)
			size = { 1024, 252 },
			pad = 24,
			x = { 80, 2760 }, -- (the 2026-11-11 stretch, points 600 apart and 560 wide; was 270..2570, z -6315..-5755)
			z = { -6275, -5715 },
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
	-- the in-play map, top left (reference pixels; its height follows the map image's shape); 1.35x wider than at first
	-- (user 2026-10-31: "... and expand it")
	-- (in a leather map case, drawn: Config/PaperArt `case`, user 2026-11-12 "Both B": `case.pad` px of leather round
	-- the sheet, nine-sliced at `case.slice` of its drawn size)
	-- bigger again (user 2026-11-12: "bigger by default"; was 486), still times the HUD size setting (src/client/ModeHud)
	Hud = { x = 12, y = 10, width = 660, case = { pad = 9, slice = 0.5 } },
	-- the drawn markers (Config/PaperArt): the dot `dot` of its sprite across, the deploy ring's pencil loop `loop` of
	-- the ring's box
	-- (a point's wax seal `wax` of its circle across, darkened by `waxShade` from its holder's colour)
	Drawn = { dot = 0.62, loop = 1.16, wax = 2.1, waxShade = 0.22 },
	-- sizes as shares of the drawn area's width
	-- each point's rune by its place in the chain (the HQs at the two ends `hq`), the same on the sketch map and on the
	-- beacon over its flag (src/client/PointSeal)
	Runes = {
		order = { "hagalaz", "sowilo", "tiwaz", "raidho", "othala", "algiz", "berkanan" },
		hq = "hagalaz",
		fallback = "isa",
	},
	Point = { radius = 0.028, hqRadius = 0.034, ring = 0.005, rune = 0.62 }, -- a rune's height in its circle's width
	Label = { size = 0.038, below = 0.008 }, -- a point's name under it
	Border = { thick = 0.0016, dash = 0.012, gap = 0.009, transparency = 0.35 }, -- the sector borders (dashed blue)
	Front = { thick = 0.004, under = 1.4 }, -- the front: red pencil, an ink line `under` times as thick beneath it
	You = { size = 0.05 }, -- the local soldier's arrow in play, across
	Teammate = { size = 0.022, edge = 0.003 },
	Zone = { size = 0.05, flash = 0.4 }, -- the FFA zone's mark, across; a contested one flashes every `flash` seconds -- a teammate's dot, across (under a point's seal), and its ink edge
	Deploy = { ring = 1.9, thick = 0.004 }, -- the loadout's ring round where you deploy: radii of its point, line
	-- On a sheet of its own (the command post's war table, user 2026-11-03: "make it look more like this", the render's
	-- sheet): no image, the ground in pencil over the whole sheet. Shares of the drawn area's width: the lines' weight,
	-- each point's circle (radius) with its number, its name's height; the river's banks either side of its middle
	-- (studs), the trenches' zigzag (each tooth, how far out), the road's dashes, the scrub (clusters of small rings,
	-- kept `clear` off the points and the river)
	Pencil = {
		lead = { 88, 84, 78 },
		river = { 96, 112, 128 },
		thick = 0.0011,
		ring = 0.014,
		label = 0.018,
		bank = 18,
		trench = { tooth = 0.007, out = 0.004 },
		road = { dash = 0.008, gap = 0.006, bow = 0.04 },
		scrub = { seed = 11, clusters = 70, rings = { 2, 6 }, spread = 0.018, size = { 0.003, 0.007 }, clear = 0.045 },
	},
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
