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
--   "Eyes": `from`, then into the local soldier's head (where it stands in its wave line).
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

	-- Pre A, "The Line Is Drawn" (plays over the countdown, Config/Frontline.CountdownSeconds): the sheet with the
	-- front drawn in red pencil, the dive into the West HQ, the flight along the front with each point's seal stamped
	-- (long enough for the plan's line at each point: Speech.plans), each side's wave line, then into your own
	-- soldier's eyes on the whistle.
	Pre = {
		shots = {
			{ name = "Sheet", t1 = 1.6, kind = "Paper", caption = "Title", pencil = true },
			{
				name = "Dive",
				t1 = 2.8,
				kind = "Move",
				from = { at = "S1", dx = -260, dz = 30, up = 520 },
				to = { at = "S1", dx = -200, dz = 60, up = 120 },
				look = { at = "S1" },
				paper = "out",
			},
			{ name = "Front", t1 = 16.0, kind = "Front", up = 55, side = 110, lead = 180, back = 0.3, stamps = true },
			{
				name = "WestLine",
				t1 = 16.8,
				kind = "Move",
				from = { at = "WestSpawn", dx = 70, dz = 12, up = 24 },
				to = { at = "WestSpawn", dx = 50, dz = 8, up = 18 },
				look = { at = "WestSpawn", up = 5 },
				caption = "West",
			},
			{
				name = "EastLine",
				t1 = 17.6,
				kind = "Move",
				from = { at = "EastSpawn", dx = -70, dz = -12, up = 24 },
				to = { at = "EastSpawn", dx = -50, dz = -8, up = 18 },
				look = { at = "EastSpawn", up = 5 },
				caption = "East",
			},
			{ name = "Eyes", t1 = 19, kind = "Eyes", from = { at = "Home", dx = -30, up = 10 }, mirror = "home" },
		},
	},

	-- per map: its own Pre in place of the shared one (the capital map's, later)
	Maps = {},

	-- The end of a match (Config/Frontline Fade / Table / Vote / Loading seconds).
	-- Fade: the bars in, the world's colour drained over `drain` of the fade, then the winner's land colour
	-- (Config/Palette UI.Grimoire.Wash; `noWinner` without one) fills the screen and holds with the winner's name.
	Fade = { drain = 0.6, cover = 0.35, noWinner = { 21, 18, 15 } },
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
		wash = { at = { 0, 10.4, 5 }, range = 16, brightness = 1.4, angle = 70, color = { 255, 224, 184 } },
		fill = { at = { 0, 9, -2 }, range = 26, brightness = 0.35, color = { 170, 186, 214 } },
		-- the game's own models on the table at real size x1.35 (their longest side in studs), coloured as the game
		-- colours them; places on the table top from its middle (x, z), turned `yaw` degrees, lying on a side if `side`
		props = {
			{ asset = "rifle_g98", length = 5.6, at = { -1.6, -2.3 }, yaw = 90, side = true },
			{ asset = "staff", length = 6.4, at = { -0.9, 2.35 }, yaw = 92, side = true },
			{ asset = "helmet_stahl", length = 1.7, at = { 5.0, -1.9 }, yaw = 30 },
			{ asset = "round_qf18", length = 2.1, at = { -6.2, -0.5 }, yaw = -95, side = true },
		},
		casings = { count = 7, at = { -0.6, 0.2 }, spread = 1.4, length = 0.38 },
		-- the modelled set (Config/Assets command_post, the render session's export 2026-11-03): built from it when the
		-- library has it, else from parts as above. Its blank papers (studs from its Origin: middle, width x height, the
		-- way their text faces and its top) take the game's text; its printed papers take these images.
		-- (`turn`: the degrees the uploaded model turns about its Origin to stand as its part list says; the images are
		-- the uploaded Decals' ids, which a MeshPart's TextureID takes: the Images behind them drew blank, Studio
		-- 2026-11-03)
		set = {
			asset = "command_post",
			turn = 180,
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
				Img_1 = 138301981593552,
				Img_2 = 129212884588351,
				Img_3 = 94649461078249,
				Img_4 = 95040580116295,
				Img_5 = 111147688606628,
				Img_6 = 134416554491092,
				Img_7 = 94649461078249,
				Img_8 = 78117184810401,
				Img_9 = 81014158693634,
				Img_10 = 79981934279343,
				Img_11 = 97338082074898,
				Img_12 = 78117184810401,
				Img_13 = 81014158693634,
				Img_14 = 79981934279343,
				Img_15 = 97338082074898,
				Img_16 = 78117184810401,
			},
		},
	},
	-- The war table: its top `size` (x, z) `top` studs over the floor; one sheet over the whole top: the played map's
	-- sketch across its upper part (`strip`: from its top-left and its width, fractions of the sheet) with this match's
	-- captures in red pencil, the grid's letters and numbers, a legend; the after-action report flat on its lower
	-- right (nothing on it), all reading from the near side, where we stand (View).
	Table = {
		size = { 12, 6 },
		top = 3,
		sheet = { 11.3, 5.3 },
		pixelsPerStud = 110,
		strip = { at = { 0.05, 0.1 }, width = 0.66 },
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
		-- should over look the entire table the whole time without changing view")
		over = { 0, 9.4, 4.4 },
		table = {
			glance = 1.4,
			-- (one look, held until the turn; more would glance between them, an `eye` moving the eyes with its glance)
			looks = { { t1 = 14, look = { 0, 3, 0.3 } } },
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
	-- 2026-11-03) with the count out of the winners present. Studs; the board's middle `at` from the floor's middle.
	Board = {
		at = { 0, 5.83, 11.27 },
		size = { 11.3, 8.7 },
		title = { text = "VOTE", x = -1.3, y = 3.2, size = { 2.4, 0.9 } },
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
	-- The armory while the next map loads: the six approved angles (render session, 2026-11-02), a slow drift each, a
	-- cut every `cut` seconds; studs from the armory floor's middle. A placeholder room until the render is modelled.
	-- A loading bar in the bottom bar (`bar`: width and height of the screen, its colours) fills over the least
	-- loading time (the phase's end), short of full until the match is ready.
	Armory = {
		cut = 3,
		bar = { width = 0.3, height = 0.008, track = { 60, 54, 46 }, fill = { 230, 220, 193 }, most = 0.95 },
		shots = {
			{ name = "Wide", from = { -14, 7, 16 }, to = { -11, 7, 15 }, look = { 4, 2, -4 } },
			{ name = "FieldGun", from = { 2, 2.5, 6 }, to = { 3.5, 2.6, 5.5 }, look = { 6, 1.6, -2 } },
			{ name = "Racks", from = { -6, 4, 4 }, to = { -6.5, 4, 2 }, look = { -14, 3.5, -2 } },
			{ name = "Helmets", from = { 8, 5, 2 }, to = { 9, 5.2, 1 }, look = { 14, 5, -4 } },
			{ name = "Workbench", from = { -2, 4.5, -2 }, to = { -1, 4, -3 }, look = { -2, 2.6, -9 } },
			{ name = "Doorway", from = { 0, 4, -6 }, to = { 0, 4.3, -2 }, look = { 0, 4, 18 } },
		},
	},
	-- The narrator (Roblox text-to-speech: AudioTextToSpeech, voice "1" British male), slowed and lowered. Part one in
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
		-- the voice's pace (measured in Studio 2026-11-02: 29 words in 8.9 s at speed 0.92), for the server's guess of
		-- part one's length (the armory's least time) and for keeping each order inside its point's moment
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
			uniform1 = "Katzmark does not rest on a victory. The frost-mages are already marching, rifles slung, while the enemy is still counting its dead.",
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
		-- (no bayonets in this army: user 2026-11-02)
		close = {
			uniform1 = "For Katzmark. Not one step back.",
			uniform2 = "For Selvara. The river remembers.",
			uniform3 = "For Sowilo. Light the runes.",
			none = "Stand to. Wait for the whistle.",
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
