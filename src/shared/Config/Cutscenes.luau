--!strict
-- The match's cutscenes and the map vote (user 2026-11-02: "cutscene animations before and after matches along with
-- the voting screen for a new map"; picked from the design page: Pre A "The Line Is Drawn", Post A "Last Point", Vote A
-- "Campaign Table"). Every frontline map plays the same cuts: each shot is placed by the map's own anchors
-- (Rules/Cutscenes.anchors: its points, spawn zones and landmarks), so a new map needs no numbers here. A map that
-- needs its own (the campaign's final capital map: user 2026-11-02, "we will need separate ones for the final capital
-- map") gets an entry in `Maps` with its own Pre / Post. src/client/MatchCutscene plays them, src/client/MapVote shows
-- the vote, src/server/Frontline runs the phases (Config/Frontline Countdown / Finale / Results / Vote seconds).
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
	-- front drawn in red pencil, the dive into the West HQ, the flight along the front with each point's seal stamped,
	-- each side's wave line, then into your own soldier's eyes on the whistle.
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
			{ name = "Front", t1 = 9.0, kind = "Front", up = 55, side = 110, lead = 180, back = 0.3, stamps = true },
			{
				name = "WestLine",
				t1 = 9.7,
				kind = "Move",
				from = { at = "WestSpawn", dx = 80, dz = 10, up = 9 },
				to = { at = "WestSpawn", dx = 60, dz = 6, up = 8 },
				look = { at = "WestSpawn", up = 5 },
				caption = "West",
			},
			{
				name = "EastLine",
				t1 = 10.4,
				kind = "Move",
				from = { at = "EastSpawn", dx = -80, dz = -10, up = 9 },
				to = { at = "EastSpawn", dx = -60, dz = -6, up = 8 },
				look = { at = "EastSpawn", up = 5 },
				caption = "East",
			},
			{ name = "Eyes", t1 = 12, kind = "Eyes", from = { at = "Home", dx = -30, up = 10 }, mirror = "home" },
		},
	},

	-- Post A, "Last Point" (Config/Frontline.FinaleSeconds): the impact frame at the last capture, a Dutch-angle orbit
	-- round the taken HQ's flag, a crane up over the front with the winner's seals stamped, then down into the paper
	-- the results replay is drawn on.
	Post = {
		shots = {
			{
				name = "Impact",
				t1 = 0.4,
				kind = "Move",
				from = { at = "Taken", dx = 60, dz = 30, up = 12 },
				to = { at = "Taken", dx = 58, dz = 30, up = 12 },
				look = { at = "Taken", up = 12 },
				mirror = "winner",
				flash = true,
			},
			{
				name = "Orbit",
				t1 = 3.4,
				kind = "Orbit",
				at = "Taken",
				radius = 75,
				up = 26,
				lookUp = 28,
				from = 2.7,
				to = 1.5,
				roll = 10,
				mirror = "winner",
				caption = "Winner",
			},
			{
				name = "Crane",
				t1 = 5.4,
				kind = "Move",
				from = { at = "Taken", dx = 60, dz = 40, up = 20 },
				to = { at = "Taken", dx = -600, dz = -500, up = 520 },
				look = { at = "Taken", up = 10 },
				lookTo = { at = "Centre" },
				mirror = "winner",
				stamps = true,
			},
			{ name = "Paper", t1 = 7, kind = "Paper", paper = "in" },
		},
	},

	-- per map: its own Pre / Post in place of the shared ones (the capital map's, later)
	Maps = {},

	-- Vote A, "Campaign Table" (Config/Frontline.VoteSeconds; src/client/MapVote, src/server/MapVote): each map's
	-- sketch sheet pinned on the table, your nation's wax seal pressed on the one you vote for, a fuse burning down; at
	-- the end the winner slides to the middle and is stamped NEXT
	Vote = {
		maxCards = 3, -- at most this many maps offered (the live one among them)
		-- (the screen's layout: src/shared/ui/MapVote.json) the gap between the sheets, the wax seals under a sheet
		-- (reference pixels at an 800-pixel-tall screen)
		gap = 30,
		seal = { size = 26, gap = 4, perRow = 8 },
		-- the end: the winner grows over `seconds`, shown `hold` seconds before the next match starts (src/server/Frontline)
		pick = { seconds = 0.8, grow = 1.12, hold = 1.5 },
		-- each map's line under its name on the sheet (by Config/Maps key; others show none)
		Regions = { Map1 = "an English valley", LanternMeadows = "festival meadows on the Aurel" },
		fuse = { thick = 3, spark = 12, flicker = 0.12 }, -- the fuse's line and its burning end (reference pixels, seconds)
		-- a vote's seal: each nation's rune (Config/Runes) on a wax disc of its land colour
		Rune = { uniform1 = "kaunan", uniform2 = "sowilo", uniform3 = "othala" },
		rate = 0.25, -- seconds between a player's votes (the server's limit)
		DisplayOrder = 8, -- over the results (Config/Results.DisplayOrder)
	},

	DisplayOrder = 9, -- the cut's bars, cards and skip prompt: over the menus and the results
}

return table.freeze(Cutscenes)
