--!strict
-- The match's cutscenes and the map vote (user 2026-11-02: "cutscene animations before and after matches along with
-- the voting screen for a new map"; picked from the design page: Pre A "The Line Is Drawn"). Every frontline map plays
-- the same flight: each shot is placed by the map's own anchors (Rules/Cutscenes.anchors: its points, spawn zones and
-- landmarks), so a new map needs no numbers here. A map that needs its own (the campaign's final capital map: user
-- 2026-11-02, "we will need separate ones for the final capital map") gets an entry in `Maps` with its own Pre.
-- After a win (user 2026-11-02, the match-end sequence): the screen fades to the winner's colour (Fade), the
-- after-action report on the battle table (Table), the camera turns round to the map board where the winners sign for
-- the next map and an arm in their uniform stamps it (Vote), the empty armory while the map is put back and loaded
-- (Loading), then the pre-match flight; a narrator speaks the plan over the armory and the flight (Speech, subtitled).
-- The table, board and armory are sets each client builds at Stage (src/client/EndScenes): placeholders until the
-- approved renders are modelled. src/client/MatchCutscene plays the fade and the flight, src/server/Frontline runs the
-- phases (Config/Frontline).
--
-- A shot: `t1` its end (seconds from the cut's start; the next starts there: a hard cut), `kind`:
--   "Paper": the sketch map fills the screen (the camera parked over the map's centre, `Paper.up` high, looking down);
--   "Move": the camera eases from `from` to `to`, looking at `look` (or from `look` to `lookTo`);
--   "Orbit": round anchor `at`, `radius` out and `up` high, from angle `from` to `to` (radians, 0 = east, pi/2 =
--     north), looking at `lookUp` over it;
--   "Front": along the points S1 -> last at `up`, `side` studs north of the chain, looking `lead` ahead, the camera
--     `back` of `lead` behind the spot it passes;
--   "Self": round the local soldier where it stands (`radius` out, `up` high, looking at `lookUp` over its feet), from
--     angle `from` to `to` (radians, 0 = straight behind it), blending into its own view over the last `into` share.
-- A place: { at = anchor, dx, dz, up } (studs east, north and over the ground at that spot). Anchors: S1..Sn (the
-- points), Mark1..Markn (each point's landmark: Rules/Cutscenes.landmark), WestSpawn / EastSpawn (the spawn zones'
-- middles), Home (the viewer's side's spawn), Taken (the match's last capture: the loser's HQ; no winner: the middle
-- point), Centre (the middle point). `mirror`: "home" / "winner": a shot written for the West is mirrored east-west when
-- that side is East (dx turned round, orbit angles reflected). `roll`: a Dutch tilt (degrees). `caption`: a title card
-- (Captions). `paper`: "out" (the sheet fades as the shot goes) / "in" (fades in). `flash`: an impact frame (white,
-- then ink). `stamps`: the point seals stamped along the bottom bar as the shot goes (the Front's as it passes each
-- point; otherwise in the winner's colour, one after another). `fov`: the camera's field of view (default `Fov`).

local Cutscenes = {
	Fov = 60,
	-- widescreen bars: each this share of the screen's height
	Bars = 0.11,
	-- the parked camera over the sheet (Paper shots and the dives' ends)
	Paper = { up = 900, fade = 0.35 },
	-- a point's landmark: the map's nearest special building (village.specials) within this many studs of the point
	LandmarkReach = 200,
	-- the far ground the camera may show ahead is asked to stream in this many seconds before each shot
	StreamAhead = 1.2,
	-- the armory streams in every spot the next flight looks at before it plays (Net "MapLoad"): spots this many studs
	-- apart (closer ones are asked for once)
	LoadSpacing = 60,
	-- skipping: hold this key (or press the Skip button) this long
	Skip = { key = "Space", hold = 0.6, text = "Hold Space to skip", touch = "Skip" }, -- (an Enum.KeyCode name)
	-- the title cards: text keys (the client fills in the map, the nations, the winner)
	Captions = {
		Title = { big = "{map}", small = "{west} · West    vs    {east} · East" },
		West = { big = "{west}" },
		East = { big = "{east}" },
		Winner = { big = "{winner}", small = "VICTORY", noWinner = "NO VICTOR" }, -- ("KATZMARK VICTORY": the demo)
	},
	-- the landmarks' names under their seals (by village.specials id; others show the point's name alone)
	Names = {
		Church = "The church",
		Inn = "The coaching inn",
		Oast = "The oast house",
		FarmYard = "The farm yard",
		Mill = "The watermill",
		Halt = "The railway halt",
		Stage = "The festival stage",
		LanternHall = "The lantern-makers' hall",
		Watchtower = "The watchtower",
		FieldBarn = "The field barn",
		Cascina = "The cascina",
		Ferry = "The ferry house",
	},

	-- The pre-match flight (plays over the countdown, Config/Frontline.CountdownSeconds, after a match: a fresh server
	-- goes in behind a loading screen instead, src/client/EndScenes). User 2026-11-03: "cinematic shots circling and
	-- going around and peeking points of interest in sectors ... change angles to a new sector whenever a new sector is
	-- being described ... not just flying over the map showing everything": a high slow orbit over the middle with
	-- the title, then one shot per point (`Sectors`: the point's share of the shot each, cut as the narrator's order for
	-- it starts, Speech.plans) round its landmark, its seal stamped as it cuts in; then round your own soldier and into
	-- its own view by the whistle.
	-- A "Sectors" shot's own shots are its `styles` in turn, at the point's landmark ("Mark") or the point ("S"); an
	-- orbit's angles turned `turn` radians further at each point, so no two cuts look the same way.
	Pre = {
		shots = {
			{
				name = "Establish",
				t1 = 2.8,
				kind = "Orbit",
				at = "Centre",
				radius = 380,
				up = 170,
				lookUp = 0,
				from = -1.95,
				to = -1.6,
				fov = 50,
				caption = "Title",
			},
			{
				name = "Sectors",
				t1 = 16.0,
				kind = "Sectors",
				stamps = true,
				turn = 1.1,
				styles = {
					-- circling the landmark, high enough to see over its roof
					{
						kind = "Orbit",
						at = "Mark",
						radius = 85,
						up = 36,
						lookUp = 8,
						from = -2.3,
						to = -1.75,
						fov = 48,
					},
					-- peeking at it low over the fields, pushing in
					{
						kind = "Move",
						from = { at = "Mark", dx = -120, dz = -80, up = 18 },
						to = { at = "Mark", dx = -90, dz = -58, up = 15 },
						look = { at = "Mark", up = 9 },
						fov = 40,
					},
					-- a crane rising off the ground beside it
					{
						kind = "Move",
						from = { at = "Mark", dx = 75, dz = -95, up = 14 },
						to = { at = "Mark", dx = 68, dz = -85, up = 62 },
						look = { at = "Mark", up = 10 },
						fov = 46,
					},
					-- a tight orbit with a Dutch tilt
					{
						kind = "Orbit",
						at = "Mark",
						radius = 65,
						up = 24,
						lookUp = 12,
						from = 0.4,
						to = 0.95,
						roll = -7,
						fov = 44,
					},
				},
			},
			-- round your own soldier where it stands in its wave line, then into your own view; the closing call on the
			-- whistle (user 2026-11-03: no team lines)
			{
				name = "Self",
				t1 = 19,
				kind = "Self",
				from = 3.4,
				to = 0,
				radius = 11,
				up = 4.5,
				lookUp = 1.5,
				into = 0.35,
				fov = 55,
			},
		},
	},

	-- per map: its own Pre in place of the shared one (the capital map's, later)
	Maps = {},

	-- The end of a match (Config/Frontline Fade / Table / Vote / Loading seconds).
	-- Fade: the bars in, the world's colour drained over `drain` of the fade, then the winner's land colour
	-- (Config/Palette UI.Grimoire.Wash; `noWinner` without one) fills the screen and holds with the winner's name.
	Fade = { drain = 0.6, cover = 0.35, noWinner = { 21, 18, 15 } },
	-- The dips to black between the end's scenes (user 2026-11-03: the victor screen, fade out, fade into the war room,
	-- ..., fade out, fade into the loading screen, ..., fade out, fade into the map cutscene): the screen darkens over
	-- `out` seconds to the moment the server changes scene (Config/Frontline.DipAttribute), stays black `hold`, clears
	-- over `inn`.
	Dip = { out = 0.5, hold = 0.3, inn = 0.6 },
	-- where the sets stand (studs): high over the world's origin, out of every map's sight (each client builds its own);
	-- the papers on them drawn at this many pixels a stud
	PixelsPerStud = 60,
	Stage = { tent = { 0, 1800, 0 }, armory = { 0, 1800, 400 } },
	-- The command post (the approved render, user 2026-11-03: src/client/CommandPost): a flat-roofed timber hut with
	-- the war table in the middle and the orders board on the front wall, behind us as we stand at the table (first
	-- person, View). The render's metres at 10/3 studs each; places in studs from the hut floor's middle, x across, y
	-- up, the board toward +z. Solemn light: a warm lamp over the table, a low wash on the board, a dim cool fill.
	Post = {
		room = { size = { 20, 11, 20 }, z = 1.67 }, -- inside: x -10..10, z -8.33 .. 11.67 (the board's wall)
		lamp = { at = { 7.2, 7.7, 1.3 }, range = 16, brightness = 1.8, color = { 255, 206, 150 } },
		-- the lamp's slow sway over the table (Field kit, user 2026-11-03): its light drifts `x` and `z` studs either way,
		-- at `rates` (radians a second)
		sway = { x = 0.24, z = 0.08, rates = { 0.9, 0.7 } },
		wash = { at = { 0, 10.4, 5 }, range = 16, brightness = 1.4, angle = 70, color = { 255, 224, 184 } },
		fill = { at = { 0, 9, -2 }, range = 26, brightness = 0.35, color = { 170, 186, 214 } },
		-- the game's own models on the table at real size x1.35 (their longest side in studs), coloured as the game
		-- colours them; places on the table top from its middle (x, z), turned `yaw` degrees, lying on a side if `side`
		props = {
			{ asset = "rifle_g98", length = 4.4, at = { -1.6, -2.3 }, yaw = 90, side = true }, -- (true to scale: set.rifle)
			{ asset = "staff", length = 6.4, at = { -0.9, 2.35 }, yaw = 92, side = true },
			{ asset = "helmet_stahl", length = 1.7, at = { 5.0, -1.9 }, yaw = 30 },
			{ asset = "round_qf18", length = 2.1, at = { -6.2, -0.5 }, yaw = -95, side = true },
		},
		casings = { count = 7, at = { -0.6, 0.2 }, spread = 1.4, length = 0.38 },
		-- the modelled set (Config/Assets command_post, the render session's export 2026-11-03): built from it when the
		-- library has it, else from parts as above. Its blank papers (studs from its Origin: middle, width x height, the
		-- way their text faces and its top) take the game's text; its printed papers take these images.
		-- (`turn`: the degrees the uploaded model turns about its Origin to stand as its part list says; the images are
		-- the Images behind the uploaded Decals: a TextureID can't take a Decal's id, Studio 2026-11-03)
		set = {
			asset = "command_post",
			turn = 180,
			-- its meshes taken out (Studio 2026-11-03): its own map pins and their flags (the game's pennants stand on
			-- the played map's points), and its rifles, the one on the table half again too long (user 2026-11-03:
			-- "the rifle is not to proper size") with the rack's behind it (out of every view)
			hide = { "C_9898A0", "C_A0A0A0", "C_98A0A0", "C_505858", "C_904828", "C_303838" },
			-- the game's own rifle in its place, true to scale: the eye 5.8 studs over the floor (about 1.65 m), so a
			-- stud is about 0.28 m and the Gewehr 98's 1.25 m is 4.4 studs; from its middle (x, z studs from the
			-- Origin) along x, on its side, clear of the shell and the pocket watch; kept clear of like the props below
			rifle = { asset = "rifle_g98", length = 4.4, at = { -1.5, -2.3 }, r = 0.17, h = 0.3 },
			-- the props merged into its big meshes, lying on the table (a ray finds their hull, not them: Studio
			-- 2026-11-03), kept clear by hand: each from `a` to `b` (x, z studs from the Origin; one place for a round
			-- thing) `r` round and `h` tall over the sheet; measured from the straight-down view
			keepOut = {
				{ a = { -4.99, -2.17 }, b = { -4.25, 0.14 }, r = 0.32, h = 0.45 }, -- the shell
				{ a = { 5.09, -1.96 }, b = { 5.09, -1.96 }, r = 1.05, h = 1.0 }, -- the helmet
				{ a = { 0.75, -0.45 }, b = { 0.95, 0.3 }, r = 0.15, h = 0.1 }, -- the dividers
				-- the casings
				{ a = { -1.43, -0.13 }, b = { -1.43, -0.13 }, r = 0.15, h = 0.1 },
				{ a = { -0.84, -0.34 }, b = { -0.84, -0.34 }, r = 0.15, h = 0.1 },
				{ a = { -0.5, -0.08 }, b = { -0.5, -0.08 }, r = 0.15, h = 0.1 },
				{ a = { -0.14, -0.24 }, b = { -0.14, -0.24 }, r = 0.15, h = 0.1 },
				{ a = { 0.2, 0.03 }, b = { 0.2, 0.03 }, r = 0.15, h = 0.1 },
				{ a = { 0.47, -0.11 }, b = { 0.47, -0.11 }, r = 0.15, h = 0.1 },
				{ a = { -1.02, 0.95 }, b = { -1.02, 0.95 }, r = 0.15, h = 0.1 },
				{ a = { 0.12, 2.42 }, b = { 0.12, 2.42 }, r = 0.2, h = 0.1 },
				{ a = { -3.75, 0.36 }, b = { -3.75, 0.36 }, r = 0.15, h = 0.1 },
			},
			papers = {
				TableSheet = { at = { 0, 3.007, 0 }, size = { 11.333, 5.312 }, front = { 0, 1, 0 }, up = { 0, 0, -1 } },
				Report = {
					at = { 3.5, 3.03, 1.333 },
					size = { 2, 2.842 },
					front = { 0, 1, 0 },
					up = { -0.0698, 0, -0.9976 },
				},
				Vote = { at = { 0.333, 7.733, 11.25 }, size = { 2.667, 0.948 }, front = { 0, 0, -1 }, up = { 0, 1, 0 } },
				Timer = {
					at = { -2.4, 7.767, 11.243 },
					size = { 1, 1 },
					front = { 0, 0, -1 },
					up = { 0.0523, 0.9986, 0 },
				},
				Order1 = {
					at = { 3.5, 4.933, 11.25 },
					size = { 2.833, 4 },
					front = { 0, 0, -1 },
					up = { 0.0262, 0.9997, 0 },
				},
				Order2 = {
					at = { 0, 4.933, 11.25 },
					size = { 2.833, 4 },
					front = { 0, 0, -1 },
					up = { -0.014, 0.9999, 0 },
				},
				Order3 = {
					at = { -3.5, 4.933, 11.25 },
					size = { 2.833, 4 },
					front = { 0, 0, -1 },
					up = { -0.0314, 0.9995, 0 },
				},
				Telegram = {
					at = { 5, 7.067, 11.24 },
					size = { 1.067, 0.686 },
					front = { 0, 0, -1 },
					up = { 0.1045, 0.9945, 0 },
				},
			},
			images = {
				Img_1 = 131261313635777,
				Img_2 = 96457879714885,
				Img_3 = 86277421946221,
				Img_4 = 104618719400917,
				Img_5 = 100197914705557,
				Img_6 = 81547446918473,
				Img_7 = 86277421946221,
				Img_8 = 129369465097993,
				Img_9 = 98806013426731,
				Img_10 = 114205926537027,
				Img_11 = 104069299930156,
				Img_12 = 129369465097993,
				Img_13 = 98806013426731,
				Img_14 = 114205926537027,
				Img_15 = 104069299930156,
				Img_16 = 129369465097993,
			},
		},
	},
	-- The war table: its top `size` (x, z) `top` studs over the floor; one sheet over the whole top, the whole of it the
	-- map (user 2026-11-03: "use the other map design though where the whole table is the map", the approved render):
	-- the played map's sketch across the sheet (`strip`: from its top-left and its width, fractions of the sheet, at
	-- most `most` of its height) with this match's captures in red pencil, the grid's letters and numbers, heights'
	-- contours round it, the legend, the scale and the sheet's title below; the after-action report flat on its lower
	-- right (nothing on it), all reading from the near side, where we stand (View).
	-- Field kit (picked from the drafts, user 2026-11-03): a painted wooden block per side moves with the replay and a
	-- pin pennant on each point flips to its taker's colour; the report on a clipboard.
	Table = {
		size = { 12, 6 },
		top = 3,
		sheet = { 11.3, 5.3 },
		pixelsPerStud = 110,
		strip = { at = { 0.039, 0.083 }, width = 0.922, most = 0.58 },
		-- heights' contours on the sheet: middle (sheet shares), rings, half-width and half-height (shares of the width)
		contours = {
			{ 0.127, 0.833, 5, 0.107, 0.054 },
			{ 0.605, 0.854, 4, 0.088, 0.044 },
			{ 0.928, 0.135, 4, 0.073, 0.034 },
			{ 0.073, 0.135, 3, 0.054, 0.029 },
			{ 0.479, 0.094, 3, 0.073, 0.022 },
		},
		-- the replay on the table (not the results screen's Config/Results.Replay): a capture every `every` seconds from
		-- `lead`, `tail` after the last start, the whole of it at most `most` (Rules/Cutscenes.replaySeconds)
		replay = { most = 14, every = 1.5, lead = 0.6, tail = 0.4, draw = 1.0 },
		-- how long the table plays (Rules/Cutscenes.tableSeconds; user 2026-11-03): until the replay and the report are
		-- both done, then `hold`; at least `least`, at most `most` seconds
		hold = 1.2,
		least = 6,
		most = 24,
		-- the losing side's piece topples once the last capture is drawn and the pieces have settled (`after`): falling
		-- over `fall` seconds onto its side (the way off the map, else where it's clear), a small bounce (`bounce`
		-- degrees, `rate` radians a second, dying by `decay` a second)
		topple = { after = 0.3, fall = 0.55, bounce = 5, rate = 14, decay = 7 },
		-- the painted blocks (studs: across, deep, tall), each resting `rest` (x right, z toward us, studs) from its
		-- side's front point; the taker's slides there along its arrow while the arrow is drawn, lifting `lift` at the
		-- middle; a block pushed off its point slides back over `back` seconds (once its side holds nothing, `off`
		-- beyond its HQ, clear of the taker's block there)
		blocks = { rest = { 0.55, 0.05 }, lift = 0.12, back = 0.6, off = 1.35 },
		-- each side's piece a chess rook (user 2026-11-03: "use chess pieces for the pieces"), lacquered in its side's
		-- colour on a felt base: `radius` and `tall` studs; kept `clear` studs off each point (its ring and name) and
		-- off the arrows' heads
		piece = { radius = 0.16, tall = 0.46, clear = 0.3 },
		-- nothing on the table inside another (user 2026-11-03: "if an item is inside another it should be put in
		-- another spot or stacked on top (realistically)"): a piece or pin rests on the nearest level place to where it
		-- belongs, out in rings `step` studs apart (`rings` of them, `around` places each); level: its footprint's
		-- heights within `level` studs (a paper's edge, not the clipboard's) and no slope, so it stands on a paper or the
		-- clipboard but never across the board's edge or on a round prop; it stays `edge` studs inside the table
		spot = { step = 0.1, rings = 12, around = 12, level = 0.01, edge = 0.25 },
		-- the pin pennants: pin `tall` studs, pennant `flag` (long, high); on a capture it lifts `lift` and drops back
		-- over `flip` seconds, changing colour at the top
		pennants = { tall = 0.55, flag = { 0.32, 0.2 }, lift = 0.1, flip = 0.45, at = { 0.14, -0.06 } },
		-- the clipboard under the report: its margin round the paper (studs), more above for the clip
		clipboard = { margin = 0.12, top = 0.38, color = { 110, 75, 43 } },
		-- a red pencil tick beside the result, `after` the last line is typed, drawn over `draw` seconds
		tick = { after = 0.2, draw = 0.35 },
		grid = { cols = 11, rows = 6 },
		report = { at = { 3.75, 1.3 }, size = { 2.6, 3.3 }, tilt = 6, pixelsPerStud = 200 },
		top3 = 3, -- the report's top soldiers (by battle points)
		-- the report's lines typed one after another, `type` seconds apart from `lead`
		-- (beside the map's replay, both in view the whole time: View.table)
		typing = { lead = 0.8, type = 0.4 },
	},
	-- First person (user 2026-11-03: "just like a natural first person"): standing at the war table's near side (`stand`,
	-- x and z; eyes `eye` over the floor) looking down at the map, the eyes resting on each `looks` point until its t1
	-- and moving on over `glance` seconds; at the vote turning round to the right to the board over `turn` seconds,
	-- then stepping toward it (`walk`: to x, z by its t1), looking at `board`; at the pick stepping up to the winning
	-- order (`pick`: `back` in front of it, `up` over its middle, over `ease` seconds) and stamping it with our own arm.
	-- Studs from the hut floor's middle; `fov` vertical; a slow breath under it all (`sway` studs, `rate` a second).
	View = {
		eye = 5.8,
		fov = 70, -- (the render session's first-person renders)
		sway = { amount = 0.025, rate = 0.25 },
		-- at the table: leaning over it, the whole table in view, the map and the report at once (user 2026-11-03: "we
		-- should over look the entire table the whole time without changing view"); straight down over the sheet's
		-- middle (a little from our side, so the pennants show their cloth) with a narrower `fov` there, the sheet's
		-- edges just inside the bars (user 2026-11-03: the render's angle), easing to the room's `fov` as we turn to the
		-- board
		over = { 0, 9.2, 1.7 },
		table = {
			fov = 60,
			glance = 1.4,
			-- (one look, held until the turn; more would glance between them, an `eye` moving the eyes with its glance)
			looks = { { t1 = 14, look = { 0, 3, 0 } } },
		},
		turn = 1.5,
		walk = { t1 = 3.6, to = { 0, 5.9 } },
		board = { 0, 5.6, 11.25 },
		pick = { back = 3.6, up = 0.5, ease = 0.9 },
		-- where our arm comes from on the screen: right of, under and ahead of the eye (studs)
		arm = { right = 1.1, down = 1.6, ahead = 0.4 },
	},
	-- The orders board on the front wall (we turn round to it from the table): "VOTE" on a plaque beside a paper counting the
	-- vote's time down (user 2026-11-03: no words in the bars), one OPERATION ORDER
	-- per map on offer (`slots` of them, `xs` across; an empty slot "to be announced"), photos pinned round them with red
	-- string, a field telegram with the plan. Each order: its objective, a clipping of its map, its orders
	-- (Vote.Orders), and "SIGNED, FOR THE FRONT" over a `grid` of signature lines (cols x rows: up to 40 signers, user
	-- 2026-11-03), the names alone (no count: user 2026-11-03). Studs; the board's middle `at` from the floor's middle.
	Board = {
		at = { 0, 5.83, 11.27 },
		size = { 11.3, 8.7 },
		title = { text = "VOTE", x = -1.3, y = 3.2, size = { 2.4, 0.9 } },
		-- (Field kit) VOTE stencilled on a plank nailed over its paper (`grow` studs bigger each way, `deep` thick, its
		-- wood's colour), and under it a strip of paper (`hint`: width, height, how far under the plank's middle)
		sign = {
			grow = 0.18,
			deep = 0.1,
			color = { 122, 85, 50 },
			hint = { text = "SIGN ONE ORDER", size = { 2.2, 0.24 }, down = 0.63 },
		},
		-- a brass stopwatch hung on the time's paper: `radius` studs, its middle `up` over the paper's; 30 seconds round
		-- the dial, the last `warn` in red; its hand sweeps round the time left; the label on the paper under it
		watch = { radius = 0.36, up = 0.08, deep = 0.08, label = "POLLS CLOSE IN", closed = "--" },
		-- the red string from a pin under the sign to the leading order's top pin, sliding to a new leader over `slide`
		-- seconds (a little past, then back); `width` studs, its sag `sag`
		string = { width = 0.03, sag = 0.35, slide = 1.0, color = { 168, 38, 31 } },
		-- once you've signed (a vote can't be taken back, user 2026-11-03): the strip under the sign says so
		signed = "YOUR ORDER IS SIGNED",
		-- after the stamp (`after` seconds past the pick), each losing order swings on one pin: `swing` degrees, dying
		-- away by `decay` a second at `rate` radians a second, coming to rest `rest` degrees off
		lose = { after = 2.0, swing = 9, decay = 2.4, rate = 7, rest = 3, settle = 0.3 },
		-- (the time left in ink, in red pencil for the last `warn` seconds)
		timer = { x = 1.5, y = 3.2, size = { 1.7, 0.9 }, label = "POLLS CLOSE IN", closed = "CLOSED", warn = 5 },
		slots = 3,
		sheet = { width = 2.85, height = 3.75, xs = { -3.5, 0, 3.5 }, y = -0.9, tilt = 1, pixelsPerStud = 200 },
		grid = { cols = 4, rows = 10 },
		placeholder = { "TO BE ANNOUNCED", "TO BE DRAWN", "ORDERS TO FOLLOW" },
		-- the field telegram's lines ({winner}: the winning nation)
		planLines = {
			"FIELD TELEGRAM",
			"{winner} HIGH COMMAND",
			"CARRY THE FRONT ONTO NEW GROUND",
			"OFFICERS SIGN THE ORDER BELOW",
			"H-HOUR AT THE WHISTLE",
		},
		noWinnerLines = { "FIELD TELEGRAM", "JOINT ORDERS", "NEITHER SIDE HOLDS THE FIELD", "ALL OFFICERS SIGN" },
		write = 0.9, -- seconds a signature takes to write, letter by letter, in the signer's nation's ink
		-- the stamp's thump as it lands (Roblox-licensed "Rock Impact Dirt Hard Muted Thuds 1", quickened)
		stampSound = { id = 9118616114, volume = 0.9, speed = 1.3 },
		-- our arm (an R6 right arm in the winners' uniform holding a wooden stamp), only at the pick: in `reach` studs
		-- from the lower right of the screen (View.arm), `lift` off the order; down over `down`, a beat, back up over
		-- `up`, then away; the stamp's block (studs)
		arm = { reach = 2.5, lift = 0.8, down = 0.3, hold = 0.25, up = 0.35, stamp = { 0.9, 0.35, 0.6 } },
	},
	-- The armory while the next map loads: the six approved angles (render session, 2026-11-03; studs from the hall
	-- floor's middle, `fov` vertical), a cut every `cut` seconds, each drifting over it (`drift`: "push" along the view
	-- or "rise" by studs, "truck" along x by studs, "arc" round the look-at by degrees). The modelled hall (`set`,
	-- Config/Assets armory) with its lights and the fields outside the door; a placeholder room (`placeholder` shots)
	-- where the library hasn't got it.
	-- The loading ring in the bottom left (user 2026-11-03: "move the loading bar bottom left as a circle with a %";
	-- `ring`: `dots` round a circle `size` of the screen's height across, its middle `at` (shares of the width from the
	-- left, of the height from the bottom), each dot `dot` of the ring across, its colours, the % in the middle) fills over
	-- the least loading time (the phase's end), short of full (`most`) until the match is ready.
	Armory = {
		cut = 3,
		shots = {
			{
				name = "Wide",
				from = { 48.2, 15.0, 17.9 },
				look = { -35.7, 5.7, -3.6 },
				fov = 49.4,
				drift = { "push", 1.79 },
			},
			{ name = "Gun", from = { 8.9, 8.2, 18.2 }, look = { -11.4, 4.6, 1.4 }, fov = 42.6, drift = { "arc", -6 } },
			{
				name = "Racks",
				from = { 2.1, 5.7, 10.7 },
				look = { 23.2, 3.2, 23.6 },
				fov = 35.1,
				drift = { "truck", 1.79 },
			},
			{
				name = "Helmets",
				from = { -25.7, 6.1, 9.3 },
				look = { -40.0, 5.4, 23.6 },
				fov = 35.1,
				drift = { "truck", -1.79 },
			},
			{
				name = "Workbench",
				from = { -20.0, 7.5, -10.7 },
				look = { -32.9, 3.9, -22.9 },
				fov = 37.3,
				drift = { "rise", 1.25 },
			},
			{
				name = "Doorway",
				from = { -3.6, 5.7, -5.4 },
				look = { 53.6, 7.1, 1.8 },
				fov = 39.8,
				drift = { "push", 1.79 },
			},
		},
		-- (`turn`: the degrees the uploaded model turns about its Origin to stand as its part list says; the images are
		-- the Images behind the uploaded Decals)
		set = {
			asset = "armory",
			turn = 180,
			-- the walls' brick and the floor's concrete in Roblox's own materials (the export flattens the render's brick
			-- and concrete shaders to one pale colour; user 2026-11-03: "the walls look too basic"), the boarded dado, its rails, the
			-- brick string courses and the wall plate (the armory's v2 export) in wood and brick: each a mesh name's
			-- start, at least `taller` / at most `flatter` studs tall, an Enum.Material name and a colour
			looks = {
				{ prefix = "C_E8E8E8", taller = 5, material = "Brick", colour = { 120, 84, 70 } },
				{ prefix = "C_909080", material = "Concrete" },
				{ prefix = "C_604030", material = "Wood" },
				{ prefix = "C_503828", material = "Wood" },
				{ prefix = "C_403020", material = "Wood" },
				{ prefix = "C_483028", material = "Wood" },
				{ prefix = "C_784838", material = "Brick" },
			},
			images = {
				Img_1 = 116344564819606,
				Img_2 = 122778476046810,
				Img_3 = 83806370527000,
				Img_4 = 111689612121287,
				Img_5 = 83619357275800,
				Img_6 = 84735106426499,
				Img_7 = 121643901023522,
				Img_8 = 121643901023522,
				Img_9 = 121643901023522,
				Img_10 = 124328881084396,
				Img_11 = 121643901023522,
				Img_12 = 108516032515404,
				Img_13 = 124328881084396,
				Img_14 = 70829317224016,
				Img_15 = 121643901023522,
				Img_16 = 121643901023522,
				Img_17 = 97664635734423,
				Img_18 = 126061938217827,
				Img_19 = 122778476046810,
				Img_20 = 116344564819606,
				Img_21 = 73966110128854,
				Img_22 = 122778476046810,
				Img_23 = 122778476046810,
				Img_24 = 117758605158491,
				Img_25 = 122778476046810,
				Img_26 = 122778476046810,
				Img_27 = 116344564819606,
				Img_28 = 116344564819606,
				Img_29 = 116344564819606,
				Img_30 = 116344564819606,
				Img_31 = 122778476046810,
				Img_32 = 107903310551890,
				Img_33 = 121643901023522,
				Img_34 = 131323995988620,
				Img_35 = 131323995988620,
				Img_36 = 121643901023522,
				Img_37 = 121643901023522,
				Img_38 = 124328881084396,
				Img_39 = 121859788398732,
				Img_40 = 99109641098468,
				Img_41 = 86598651509789,
				Img_42 = 73966110128854,
				Img_43 = 72150391611745,
				Img_44 = 70829317224016,
				Img_45 = 70829317224016,
				Img_46 = 72682666329228,
				Img_47 = 124729538500319,
				Img_48 = 138588064359600,
				Img_49 = 117758605158491,
				Img_50 = 108516032515404,
				Img_51 = 124328881084396,
				Img_52 = 115062314683033,
			},
			-- the lamp over the bench and the crystal's glow; daylight in at the door and soft fills from above, each a
			-- SurfaceLight facing `face` (`width` studs across it)
			points = {
				{
					at = { -32.1, 11.1, -17.5 },
					colour = { 255, 184, 115 },
					range = 26,
					brightness = 1.6,
					shadows = true,
				},
				{ at = { -26.4, 3.4, 12.1 }, colour = { 140, 209, 255 }, range = 10, brightness = 0.8 },
			},
			fills = {
				{
					at = { 55.7, 10, 0 },
					face = { -0.989, -0.146, 0 },
					colour = { 219, 235, 255 },
					range = 70,
					brightness = 2.2,
					angle = 80,
				},
				{
					at = { 0, 28.6, 0 },
					face = { 0, -1, 0 },
					colour = { 255, 219, 178 },
					range = 40,
					brightness = 0.6,
					angle = 110,
				},
				{
					at = { -28.6, 25, 0 },
					face = { -0.978, -0.21, 0 },
					colour = { 255, 219, 178 },
					range = 40,
					brightness = 0.4,
					angle = 90,
				},
				{
					at = { 23.2, 23.2, 14.3 },
					face = { 0, -0.904, 0.427 },
					colour = { 255, 214, 168 },
					range = 30,
					brightness = 0.6,
					angle = 90,
				},
				{
					at = { -39.3, 21.4, 12.9 },
					face = { 0, -0.832, 0.555 },
					colour = { 255, 214, 168 },
					range = 30,
					brightness = 0.6,
					angle = 90,
				},
				{
					at = { -26.8, 14.3, -8.9 },
					face = { -0.292, -0.583, -0.758 },
					colour = { 255, 217, 178 },
					range = 24,
					brightness = 0.4,
					angle = 90,
				},
			},
			-- the fields and the road past the door: slabs at these extents (model studs, each side at most 2048)
			outside = {
				{ colour = { 104, 116, 70 }, min = { 17.857, -0.786, -2500 }, max = { 2946.43, -0.071, 2500 } },
				{ colour = { 128, 108, 80 }, min = { 48.885, -0.339, -14.482 }, max = { 1543.09, 0.018, 165.398 } },
				{ colour = { 104, 86, 64 }, min = { 49.491, -0.036, 1.235 }, max = { 1541.44, 0.036, 159.626 } },
				{ colour = { 104, 86, 64 }, min = { 50.536, -0.036, -8.71 }, max = { 1542.49, 0.036, 149.681 } },
				{ colour = { 88, 92, 58 }, min = { 48.623, -0.196, 8.606 }, max = { 1540.67, -0.018, 167.885 } },
				{ colour = { 88, 92, 58 }, min = { 51.311, -0.196, -16.968 }, max = { 1543.36, -0.018, 142.311 } },
				{ colour = { 110, 122, 78 }, min = { 941.458, -148.571, -309.295 }, max = { 2798.6, 37.143, 1547.85 } },
				{ colour = { 104, 118, 76 }, min = { 1045.2, -171.429, -1431.74 }, max = { 3188.06, 42.857, 711.115 } },
				{ colour = { 120, 128, 92 }, min = { 1197.02, -217.143, -1096.89 }, max = { 3911.3, 54.286, 1617.39 } },
				{ colour = { 116, 124, 86 }, min = { 1142.69, -171.429, 374.056 }, max = { 3285.55, 42.857, 2516.91 } },
				{ colour = { 112, 122, 84 }, min = { 1375.57, -182.857, -2250.98 }, max = { 3661.29, 45.714, 34.732 } },
			},
		},
		placeholder = {
			{ from = { -14, 7, 16 }, to = { -11, 7, 15 }, look = { 4, 2, -4 } },
			{ from = { 2, 2.5, 6 }, to = { 3.5, 2.6, 5.5 }, look = { 6, 1.6, -2 } },
			{ from = { -6, 4, 4 }, to = { -6.5, 4, 2 }, look = { -14, 3.5, -2 } },
			{ from = { 8, 5, 2 }, to = { 9, 5.2, 1 }, look = { 14, 5, -4 } },
			{ from = { -2, 4.5, -2 }, to = { -1, 4, -3 }, look = { -2, 2.6, -9 } },
			{ from = { 0, 4, -6 }, to = { 0, 4.3, -2 }, look = { 0, 4, 18 } },
		},
		ring = {
			size = 0.075,
			at = { 0.045, 0.055 },
			dots = 36,
			dot = 0.1,
			track = { 60, 54, 46 },
			fill = { 230, 220, 193 },
			text = 0.3, -- (the %'s height, of the ring's)
			most = 0.95,
		},
	},
	-- The narrator: a British woman's voice, every line recorded (Config/NarratorClips; user 2026-11-03), and Roblox
	-- text-to-speech (AudioTextToSpeech, voice "1" British male, slowed and lowered) for a line not recorded. Part one in
	-- the armory: where they won (by the map just played) and the momentum (by the winning nation). Part two over the
	-- flight: the plan (by the next map: the dive's line, then a line as each point's seal is stamped) and the closing
	-- call on the whistle. Lines play one after another, never over each other, each no earlier than its cue; the
	-- subtitle shows the line playing. {winner}: the winning nation; `none`: no winner. A map without its own plan
	-- gets none.
	Speech = {
		voice = "1",
		speed = 0.92,
		pitch = -2,
		volume = 1.6,
		gap = 0.3, -- seconds of quiet between lines
		-- the text-to-speech voice's pace (measured in Studio 2026-11-02: 29 words in 8.9 s at speed 0.92): how long a
		-- line not recorded takes (a recorded line takes its clip's length), for the server's guess of part one's
		-- length (the armory's least time) and for keeping each order inside its point's moment
		wordsPerSecond = 3.0,
		won = {
			Map1 = "{winner} holds the valley. Their colours fly from the church tower, and the enemy's last line lies broken in the mud of the river ford.",
			LanternMeadows = "The lanterns of the Aurel burn for {winner} tonight. The enemy has been driven from the festival ground, and the meadows belong to them.",
		},
		wonNone = {
			Map1 = "No banner flies over the valley tonight. The guns have fallen silent above the watermill, and the dead lie on both banks of the river.",
			LanternMeadows = "The festival lanterns of the Aurel burn for no one tonight. The meadows are trampled flat, and neither army holds them.",
		},
		momentum = {
			uniform1 = "Katzmark does not rest on a victory. The mages are already marching, rifles slung, while the enemy is still counting its dead.",
			uniform2 = "Selvara rides the current of this victory. The brass of their mages is still ringing in the hills, and they mean to strike again before the mud can dry.",
			uniform3 = "Sowilo's banners are torn, but they have tasted blood. The crimson rune-casters swear on their scars that the next field will be theirs by nightfall.",
			none = "Neither side could break the other. Both armies limp from the field, and both have sworn the next fight will end it.",
		},
		-- (each order short enough to finish before the next point, about 7 words: tests/cutscenes.spec)
		plans = {
			Map1 = {
				"Orders for the valley.",
				"Hold the western rise.",
				"Cross the meadow at the double.",
				"Take the oast house. Hold the centre.",
				"Ford the river by the coaching inn.",
				"Then bring down the church tower.",
			},
			LanternMeadows = {
				"Orders for the Aurel.",
				"From the watchtower, look east.",
				"Through the hedgerows by the barn.",
				"Take the festival ground under the lanterns.",
				"Cross the river at the ferry.",
				"Drive them out of the cascina.",
			},
		},
		-- the closing call, by the player's own kit: the same whether their side won or lost (user 2026-11-03; no
		-- bayonets in this army: user 2026-11-02)
		close = {
			uniform1 = "For Katzmark! Not one step back!",
			uniform2 = "For Selvara! The river remembers!",
			uniform3 = "For Sowilo! Light the runes!",
		},
		subtitle = 22, -- the subtitles' size (pixels at an 800-pixel-tall screen), in the bottom bar
	},

	-- The vote on the map board (Config/Frontline.VoteSeconds; src/client/EndScenes, src/server/MapVote): the winners
	-- sign the sheet of the map they want (user 2026-11-02: "winners sign"; everyone if the winning side has no players
	-- or there was no winner), the others watch; the most signatures wins and the arm stamps NEXT on it.
	Vote = {
		-- each map's orders on its sheet (by Config/Maps key; the approved render's)
		Orders = {
			Map1 = { "HOLD ALL 5 SECTORS", "TAKE THE BRIDGE", "GUNS BEHIND LINE 2" },
			LanternMeadows = { "ADVANCE ON THE ROAD", "SEIZE THE LANTERN RING", "HOLD THE FARMS" },
		},
		maxCards = 3, -- at most this many maps offered (the live one among them)
		-- the end: the winner stamped NEXT, shown `hold` seconds before the armory (src/server/Frontline)
		pick = { hold = 3 },
		rate = 0.25, -- seconds between a player's votes (the server's limit)
	},

	DisplayOrder = 9, -- the cut's bars, cards and subtitles: over the menus
}

return table.freeze(Cutscenes)
