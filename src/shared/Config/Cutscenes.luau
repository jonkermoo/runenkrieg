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
		Winner = { big = "{winner}", small = "takes the field", noWinner = "NO VICTOR" },
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
			{ name = "Front", t1 = 15.0, kind = "Front", up = 55, side = 110, lead = 180, back = 0.3, stamps = true },
			{
				name = "WestLine",
				t1 = 15.8,
				kind = "Move",
				from = { at = "WestSpawn", dx = 70, dz = 12, up = 24 },
				to = { at = "WestSpawn", dx = 50, dz = 8, up = 18 },
				look = { at = "WestSpawn", up = 5 },
				caption = "West",
			},
			{
				name = "EastLine",
				t1 = 16.6,
				kind = "Move",
				from = { at = "EastSpawn", dx = -70, dz = -12, up = 24 },
				to = { at = "EastSpawn", dx = -50, dz = -8, up = 18 },
				look = { at = "EastSpawn", up = 5 },
				caption = "East",
			},
			{ name = "Eyes", t1 = 18, kind = "Eyes", from = { at = "Home", dx = -30, up = 10 }, mirror = "home" },
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
	-- The battle table (placeholder: a tent, a table, the papers flat on it): its top `size` (x, z) `top` studs over the
	-- tent floor; the played map's sketch sheet and the after-action report lie flat on it (sizes in studs, places from
	-- the table's middle, x along it); the camera drifts from `from` to `to` (studs from the table top's middle),
	-- looking at `look`.
	Table = {
		size = { 16, 10 },
		top = 3.4,
		map = { at = { -2.6, 0.5 }, size = { 9.6, 2.77 } },
		report = { at = { 5.2, 0 }, size = { 4.4, 6 }, tilt = 6 },
		lines = 7, -- the report's lines: title, map and length, the winner, three honours, your own
		-- the report's lines typed one after another, `type` seconds apart from `lead`
		typing = { lead = 0.8, type = 0.45 },
		shots = {
			{ t1 = 7, from = { -7, 8, 7 }, to = { -1, 9, 6 }, look = { -2, 0, 0.5 } },
			{ t1 = 14, from = { 4, 7.5, 3.5 }, to = { 5, 7, 2.5 }, look = { 5.2, 0, 0 } },
		},
	},
	-- The map board on the tent wall behind the table (the camera turns round to it), `slots` sheets side by side (a
	-- slot with no map is a placeholder), the operations plan beside them. Studs; the camera from the board's middle.
	Board = {
		behind = 9, -- studs behind the table's middle, facing it
		size = { 22, 10 },
		slots = 3,
		sheet = { width = 4.8, height = 6.4, gap = 0.7, tilt = 2 },
		plan = { width = 3.4, height = 4.6 },
		placeholder = "to be drawn",
		turn = 1.2, -- seconds the camera takes to turn round from the table
		shot = { from = { 0, 5, 16 }, to = { 0, 5, 14 }, look = { 0, 5, 0 } },
		-- the operations plan's lines ({winner}: the winning nation)
		planLines = {
			"OPERATIONS PLAN",
			"{winner} High Command",
			"Objective: carry the front onto new ground.",
			"The officers signed below choose the field.",
			"H-hour: at the whistle.",
		},
		noWinnerLines = { "OPERATIONS PLAN", "Joint orders", "Neither side holds the field.", "All officers choose." },
		write = 0.9, -- seconds a signature takes to write, letter by letter, in the signer's nation's ink (Magic)
		-- the arm (an R6 right arm in the winners' uniform holding a wooden stamp): in from `reach` studs right of the
		-- sheet, `lift` over it; down over `down`, a beat, back up over `up`; the stamp's block (studs)
		arm = { reach = 8, lift = 2.5, down = 0.35, hold = 0.25, up = 0.4, stamp = { 1.4, 0.5, 0.9 } },
	},
	-- The armory while the next map loads: the six approved angles (render session, 2026-11-02), a slow drift each, a
	-- cut every `cut` seconds; studs from the armory floor's middle. A placeholder room until the render is modelled.
	Armory = {
		cut = 4.5,
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
		wordsPerSecond = 2.3, -- the server's guess of part one's length (the armory's least time)
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
		plans = {
			Map1 = {
				"Orders for the valley.",
				"Hold the western rise. It is the only high ground you will be given.",
				"Push through the open meadow at the double. Do not stop in the grass.",
				"Take the farm and the oast house. Whoever holds the kilns holds the centre.",
				"Cross at the ford by the coaching inn, and clear it room by room.",
				"And do not stop until the church tower falls.",
			},
			LanternMeadows = {
				"Orders for the Aurel.",
				"From the old watchtower, look east. That is where we are going.",
				"Cross the hedgerow fields by the barn. Use every hedge, and trust none of them.",
				"Take the festival ground under the lantern poles. Let them see our colours in the light.",
				"Ford the river by the ferry house before they can hold the far bank.",
				"Then drive them out of the cascina and into the Aurel.",
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
		maxCards = 3, -- at most this many maps offered (the live one among them)
		-- the end: the winner stamped NEXT, shown `hold` seconds before the armory (src/server/Frontline)
		pick = { hold = 1.5 },
		-- each map's line under its name on the sheet (by Config/Maps key; others show none)
		Regions = { Map1 = "an English valley", LanternMeadows = "festival meadows on the Aurel" },
		rate = 0.25, -- seconds between a player's votes (the server's limit)
		hint = "Click a map to sign for it",
		watch = "{winner} chooses the next field",
	},

	DisplayOrder = 9, -- the cut's bars, cards and subtitles: over the menus
}

return table.freeze(Cutscenes)
