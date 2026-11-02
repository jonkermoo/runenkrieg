--!strict
-- Bot soldiers that fill empty places when too few players are on (src/server/Bots, Rules/Bots; 2026-10-30: the FFA
-- zone match). They are soldiers like the players' (a kit, its class's gun, the same Firing / Damage rules) and in FFA
-- they play as players (user 2026-10-30: "enemies are treated as players"): a name, zone score that can lead and win,
-- match points spent on a class, a respawn wait, always moving, taking cover when shot at or spotted.
local Bots = {
	Enabled = true,
	-- on Workspace: a number pins how many bots there are (testing; 0 none), over the fill below
	Attribute = "Bots",
	-- on Workspace: a Difficulty key below, over Default (testing)
	DifficultyAttribute = "BotDifficulty",
	Tag = "Bot", -- every bot's model (they also carry Config/DevTools.Dummies.Tag: hurt, healed, dragged like soldiers)
	Folder = "Bots", -- in Workspace
	-- on each bot's model: a negative number standing in for a UserId (src/server/ZoneMatch scores, leader and winner;
	-- src/server/Loadouts kill credit and match points)
	IdAttribute = "BotId",
	-- on the bots' Workspace folder, per bot (the id's number without its sign): its name and zone score, for every
	-- client's match HUD (src/client/ZoneHud)
	NameAttribute = "Name_",
	ScoreAttribute = "Score_",
	-- the names bots play under (each bot keeps one; no two at once)
	Names = {
		"Weber",
		"Fischer",
		"Becker",
		"Hoffmann",
		"Krause",
		"Lehmann",
		"Rossi",
		"Bianchi",
		"Ferrari",
		"Moretti",
		"Ricci",
		"Conti",
		"Hughes",
		"Evans",
		"Turner",
		"Price",
		"Walsh",
		"Barker",
		"Novak",
		"Horvat",
		"Kovac",
		"Dvorak",
		"Leclerc",
		"Moreau",
		"Schulz",
		"Wagner",
		"Brandt",
		"Vogel",
		"Keller",
		"Galli",
		"Marino",
		"Greco",
		"Fowler",
		"Hayes",
		"Collins",
		"Doyle",
		"Svoboda",
		"Marek",
		"Babic",
		"Girard",
		"Fontaine",
		"Dubois",
	},
	-- after a death: the respawn wait (Config/Metrics.Combat.RespawnDelay, as a player's) plus this long in the loadout
	-- menu (seconds, a random share between), as a player picks a class and deploys
	MenuTime = { 1, 5 },
	-- the classes a bot can play and buy with its match points (Config/Classes; the first is the free default), the
	-- range a short gun closes in to (nil: it fights from where it is); the others (grenades, the staff, the pistol)
	-- come later
	Classes = {
		{ key = "Rifleman" },
		{ key = "Grenadier" }, -- (user 2026-11-01: bots play it; only Grenadiers throw)
		{ key = "AutoRifler" },
		{ key = "Shotgunner", push = 18 },
		{ key = "Engineer" }, -- (user 2026-11-02: Engineer bots build; Config/Bots.Build)
		{ key = "Mage" }, -- (user 2026-11-02: Mage bots in Normal and FFA, by points; Config/Bots.Staff)
	},
	-- the share of the battle points (Config/Classes.Earn: the kill, headshot and assists) a bot's death pays its killer
	-- (user 2026-10-30: "make the AIs count half the battle points when you kill them")
	KillShare = 0.5,
	-- the chance a bot buys the dearest class it can pay for each life (else one it can pay for at random: it saves up)
	Buy = 0.6,
	-- soldiers each mode is topped up to: players first, bots for the rest (Rules/Bots.wanted); modes not listed get none.
	-- Normal tops up each side (Rules/Bots.wantedSides; user 2026-10-31: "this will be a 50vs50 map. however, if there is
	-- only 1 player, lets make it a 20 v 20 game")
	Fill = {
		FFA = { total = 8 },
		Normal = { perSide = 20 },
	},
	-- the most bots one server runs in each mode, whatever the fill (the server's budget; FFA Stage 1 measured 10 and
	-- 20); the governor (Budget) may hold it lower
	Max = { FFA = 20, Normal = 39 },
	-- one bot in (or out) at most this often, so a join or a leave never brings a crowd at once
	JoinEvery = 1.5,
	LeaveEvery = 4,
	-- a bot over the count leaves only while dead, or after this long over it (seconds) even alive
	LeaveAliveAfter = 20,

	-- the server's budget for all the bots together (src/server/Bots)
	Budget = {
		-- milliseconds of bot thinking a frame: the bots past it wait for the next frame (round-robin, so all get a turn)
		frameMs = 1.5,
		-- rays a frame for cover searches (a search walks one ring a think, its rays counted here; line-of-sight rays
		-- are counted too)
		raysPerFrame = 40,
		-- path computes a second, all bots together (the rest wait in a queue)
		pathsPerSecond = 6,
		-- how often a bot thinks and looks (a second) by the nearest player's distance (Rules/Bots.lod): full within `mid`
		-- studs or in a fight, `middle` to `far`, `distant` past it (sight and moves a little coarser where nobody sees)
		lod = {
			mid = 200,
			far = 450,
			near = { think = 10, sense = 4 },
			middle = { think = 5, sense = 2 },
			distant = { think = 2, sense = 1 },
		},
		-- the governor: while the bots' frame cost (a one-second average) is over `ms`, or the physics rate under
		-- `minFps`, for `trimAfter` seconds, it holds the count one lower (then one more every `trimEvery`); after
		-- `restoreAfter` seconds within budget it lets one back (then one more every `restoreEvery`); never under `floor`
		governor = {
			ms = 3,
			minFps = 55,
			trimAfter = 10,
			trimEvery = 4,
			restoreAfter = 30,
			restoreEvery = 10,
			floor = 4,
		},
	},
	-- Normal (the frontline push, src/server/Frontline): bots fight on a side, deploy in its waves and take orders from
	-- their side's commander (Rules/BotOrders)
	Normal = {
		-- before a bot's name (user 2026-10-31: names marked as bots)
		nameTag = "[BOT] ",
		commandEvery = 1, -- seconds between each side's orders
		joinEvery = 0.5, -- one bot in at most this often (20 v 20 fills in about 20 s)
		-- while an own sector has enemies in its zone (and they lead there or it is losing control), this share of the
		-- side's bots defend it; the rest attack the side's target sector
		defendShare = 0.5,
		-- a stand point in the ordered sector's zone: within this share of its radius
		standShare = 0.6,
		-- seconds between path recomputes toward the same far goal (the long walks between sectors)
		repath = 15,
		-- studs from the ordered sector's point a hunt may lead a bot (past it, it goes back to its order)
		leash = 90,
	},

	-- Normal squads (Rules/BotSquads; user 2026-11-01: teamwork, pushing under covering fire): `size` bots a squad (a
	-- last one under `least` joins the one before); `readyShare` of a squad at its approach spot (or in the zone) is
	-- ready to push; it pushes then with covering fire, with no enemy known, or when the side's soldiers in the zone
	-- and the squad outnumber the enemy's by more than `margin`. An enemy a member saw within `knownFor` seconds and
	-- `contact` studs of the squad is contact: the squad bounds (each half runs at most `boundMax` seconds, a stop
	-- `hop` studs on along the route, reached within `arrive`). Members stand `spread` studs apart at a spot.
	Squads = {
		size = 4,
		least = 2,
		readyShare = 0.5,
		margin = 0,
		knownFor = 6,
		contact = 120,
		boundMax = 7,
		hop = 30,
		arrive = 6,
		spread = 5,
	},
	-- Normal routes (Rules/BotSquads; user 2026-11-01: "take advantage of the size of the map"): round each sector,
	-- approach spots on rings `rings` studs out from its zone's edge (`perRing` across `arc` degrees each side of the way
	-- home) and hold spots inside it (`holdRings` shares of its radius); each scored by cover from the far side's view
	-- (`view` studs out past the zone, `eye` up), walls, trees and houses within `nearRadius` studs (up to `nearCap`), and
	-- distance (Rules/BotSquads.scoreSpot `weights`); `laneWithin` degrees of the straight line is the centre lane.
	-- Worked out again every `refresh` seconds (built pieces change it), `perFrame` spots a frame. A squad going more
	-- than `midFrom` studs walks through a waypoint `midShare` of the way along, `laneOffset` of the distance to its
	-- lane's side.
	Routes = {
		rings = { 15, 35 },
		perRing = 9,
		arc = 80,
		holdRings = { 0.35, 0.7 },
		holdPerRing = 8,
		view = 40,
		eye = 5,
		chest = 3,
		nearRadius = 7,
		nearCap = 4,
		laneWithin = 25,
		refresh = 60,
		perFrame = 6,
		midFrom = 140,
		midShare = 0.5,
		laneOffset = 0.25,
		weights = { hidden = 3, near = 0.6, distance = 0.02, crowd = 1.5, random = 1 },
	},

	-- Normal's actions besides fighting (Rules/BotActions; user 2026-11-01), weighed every `every` seconds a bot:
	-- - Drag: a knocked-down teammate in sight of a known enemy within `within` studs is dragged to cover (Rules/Bots'
	--   cover points, away from the threat) at most `cover` studs off, for at most `seconds`; then healed if hurt.
	-- - Heal: with nobody shooting at it or hitting it for `calm` seconds, a bot walks to the nearest teammate under
	--   `below` health within `within` studs and heals them (Healing.startAs) from `reach` studs; it gives up after
	--   `seconds` walking. Squads pushing in don't stop for it.
	-- - Grenade (Grenadiers): at an enemy with `group` or more enemies within `cluster` studs, or one in cover (known,
	--   unseen) for `hidden` s, `min`-`max` studs off, no teammate within `safe` studs of it; at most one throw every
	--   `every` s a bot and `squadEvery` s a squad. The gun goes away and the grenade is in hand for `hold` s before it
	--   goes (user: "Swap for ~0.6 s"); aimed `short` of the spot (it rolls on) on the low arc.
	Actions = {
		every = 0.5,
		Drag = { within = 12, cover = 15, seconds = 8 },
		Heal = { calm = 3, below = 0.7, within = 25, reach = 4, seconds = 10 },
		Grenade = {
			min = 15,
			max = 35,
			cluster = 6,
			group = 2,
			hidden = 3,
			safe = 12,
			every = 8,
			squadEvery = 4,
			hold = 0.6,
			short = 0.85,
		},
	},

	-- Normal bots and buildings (Rules/BotBuildings; user 2026-11-02, src/server/Indoors spots, Doors):
	-- - doors: a path's door waypoint (Config/Indoors.Links.door) within `doorReach` studs: it opens the door
	--   (Doors.openFor) and waits `doorWait` s while it swings; paths cost Config/Indoors.PathCosts.
	-- - holds: each defending squad puts up to `perSquad` bots at window or doorway spots within the zone's radius plus
	--   `around` (windows overlooking it count), facing the enemy's way in by more than `facing`, `upstairs` a story above the ground, `random` to spread
	--   them (user: "A few (1-2 a squad)"); with no target it faces out of the window.
	-- - cover: a cover search also tries up to `cover` indoor cover spots within its reach.
	-- - clearing (user: "Yes, clear buildings"): a pushing squad's Assault bots go for the indoor spot nearest a known
	--   enemy within `clearWithin` studs of one (that enemy is inside).
	-- Spots are looked up by `cell`-stud squares, each kept `keep` s (`slack` studs more round each square).
	Indoors = {
		doorReach = 6,
		doorWait = 0.8,
		perSquad = 2,
		around = 55, -- (Map 1's houses stand 82+ studs from the zones' centres; user 2026-11-02: "Widen to 100")
		facing = 0.3,
		upstairs = 0.5,
		random = 0.5,
		cover = 4,
		clearWithin = 6,
		cell = 50,
		keep = 20,
		slack = 10,
	},

	-- Normal: bots building (Rules/BotBuild; src/server/Build placeAs / planAs / workAs, the players' checks; user
	-- 2026-11-02: "Engineers + small help", "Only when calm"). Each side's commander keeps a build list at its front (the
	-- sector it holds nearest the enemy), facing the enemy's way in:
	-- - Bags: a sandbag pile `ahead` studs in front of each outdoor hold spot with no cover (the first `max`).
	-- - Wire: a strip `out` studs past the zone's edge on each of `lanes` (studs across from the middle).
	-- - Nest: an MG nest `ahead` of the hold spot nearest the enemy.
	-- - Guns: the guns the artillery level opens, `back` studs behind the zone's middle, `side` apart.
	-- - repairs: own pieces within `repair` studs past the zone's edge that want swings (the nearest `repairs`).
	-- (the trenches: Trenches below.) Engineers take the nearest job within `take` studs; a digger (Trenches.share of a
	-- holding squad) takes a trench job within `take` and helps work wire within `help`. A bot
	-- builds only when nobody has shot at it or hurt it for `calm` s and it sees no enemy; it stands `stand` studs from
	-- a piece's spot to lay it, gives a job up after `seconds`; a refused spot moves `nudge` studs across (a trench
	-- run's far end swings aside: Rules/BotTrenches.swing; up to `tries` times), then waits `retry` s. A piece of the job's key within `match` studs of
	-- its spot is the job's.
	-- Caps (user: "A third, half the guns"): the bots lay at most `caps.pieces` of the team's Config/Build.PerTeam and
	-- `caps.<key>` of a gun's.
	Build = {
		calm = 3,
		take = 90,
		help = 25,
		stand = 4,
		seconds = 60,
		nudge = 6,
		tries = 8, -- (steps of `nudge` out to 24 studs each way: Map 1's tree clumps stand on some fronts' lines)
		retry = 30,
		match = 8,
		repair = 30,
		repairs = 6,
		Bags = { ahead = 3, max = 8 }, -- (8: any class lays them now, user 2026-11-02: "Piles at open holds")
		Wire = { out = 40, lanes = { -40, 0, 40 } },
		Nest = { ahead = 2 },
		Guns = { back = 60, side = 24 },
		-- (pieces 100: a third of Config/Build.PerTeam 300, as the 50 of 150 the user chose)
		caps = { pieces = 100, FieldGun = 3, Howitzer = 1 },
		-- Cover (user 2026-11-02: "have AI build areas of cover with sandbags and barriers", all four kinds; any class
		-- lays sandbag piles and barriers, Config/Classes):
		-- - Breast: a trench run refused at every spot (Trenches.tries) gets a breastwork along its line instead, a lay job
		--   every `step` studs, the `keys` in turn.
		-- - Walls: once an MG nest or gun stands, `count` sandbag piles `ahead` studs on its enemy side, `spread` apart.
		-- - Pinned: a bot shot at within `threat` s, suppressed `shaken` or more, with no cover found within `near` studs and
		--   not in a trench, lays a sandbag pile `ahead` studs toward the threat and fills it under fire (at most every
		--   `every` s).
		Breast = { step = 8, keys = { "SandbagPile", "Hesco" } },
		Walls = { ahead = 5, spread = 8.5, count = 2 },
		Pinned = { threat = 1.5, shaken = 0.5, every = 45, ahead = 2.5, near = 20 },
		-- Gun crews (Rules/BotBuild.crewWanted / gunSpots; user 2026-11-02: "if artillery has been unlocked for a side and
		-- not a lot of any has been placed, some bots should take priority in getting engineer and start building it in
		-- strategic places"; "Up to 2, if they can pay"): while a side has fewer than `enough` guns standing (anyone's
		-- field guns and howitzers), up to `max` of its bots pick Engineer when they respawn (paid as any class; one that
		-- can't pay picks as usual) and take gun jobs first, from anywhere on the front. Back to their usual picks on the
		-- next respawn once the side has enough. The guns' spots (scored: "Scored spots behind the line"): `back` studs
		-- behind the front zone's edge by `across` studs either side of its middle, farthest back first, each kept only
		-- where the gun reaches the enemy's nearest sector's middle (Rules/Artillery.layFor) and lies `spawnGap` studs
		-- clear of every spawn and wave line (Rules/Artillery.nearSpawn), `spacing` (Config/Build.Pieces) from the other
		-- guns' spots; the bots' share of each gun (`caps` above) gets a spot. None fits: the fixed spot (`Guns` above).
		Crews = {
			max = 2,
			enough = 3,
			back = { 90, 60, 30 },
			across = { 0, -60, 60, -120, 120, -180, 180 },
			spawnGap = 40,
		},
	},

	-- Normal: sapping forward (Rules/BotSap; user 2026-11-02: "AI ... should [build trenches to push forward] if they are
	-- obviously unable to advance under fire", "30 s stuck, half dig"). An attacking squad moving up (Move / Bound) is
	-- stuck once `stall` s pass since it last gained `progress` studs toward its objective, while shot at or with `losses`
	-- members down since. It then saps: `share` of it digs (any class) a run `run` studs long from its most forward
	-- member toward the objective, turned `angle` degrees one way then the other (a zig-zag), each run planned once the
	-- last is dug, the rest holding where they are giving covering fire, then all moving up to its head. Sappers dig
	-- under fire (only a hit stops them). It is over at `edge` of the zone's radius from the objective, or after `quiet`
	-- s with nobody shooting at the squad.
	Sap = {
		stall = 30,
		progress = 10,
		losses = 2,
		share = 0.5,
		run = 16,
		angle = 25,
		edge = 1.1,
		quiet = 20,
	},

	-- Mage bots (Rules/BotStaff; src/server/StaffCast openAs / aimAs / castAs, the players' mana, cooldowns and holds;
	-- user 2026-11-02): the stage by Rules/BotStaff.stage (Config/Damage.Staff.Range each stage's reach); a mega shot
	-- at `megaGroup` enemies within `cluster` studs of the target, or a target in a building, an MG nest or within `gun`
	-- studs of a gun ("Groups and strongpoints"), never with a teammate within `blast` studs of where it lands; no
	-- shot with a teammate within `line` studs of the beam. Seen-or-not: medium and mega shots also go at where its
	-- squad last knew an enemy (their cover: "Soldiers and their cover"). An open circle is dropped once the target
	-- has been out of sight `lost` seconds; a mega shot is charged standing still.
	Staff = {
		megaGroup = 2,
		cluster = 10,
		gun = 8,
		blast = 25,
		line = 4,
		lost = 0.8,
	},

	-- Normal: bots and trenches (Rules/BotTrenches; user 2026-11-02: "bots that arent engineers should build trenches
	-- too. they should follow real strategy and tactics and have their own advanced trench behavior"). Any class digs.
	-- - Who: `share` of each squad holding its side's front zone digs when calm, the rest stand guard ("Half dig, half
	--   guard"). With no own sector under attack, `hold` of the side holds the front zone (a zone just taken is dug in
	--   at once: "Yes, dig in at once").
	-- - The system ("Fire + support + comms"), dug in that order: Fire, a trench `width` wide across the zone's enemy
	--   edge (`edge` of its radius out) in `bays` runs, every other joint `traverse` studs forward (bays and traverses);
	--   Support, a line `back` studs behind it, `width` wide; Comm, from the support line's middle to the fire trench's,
	--   jogging `jog` studs across half way, stopping `short` studs off each line. A run counts as planned once a square
	--   lies within `on` studs of its line, `ends` of its length in from either end. A side's bots keep at most `cap`
	--   squares planned or dug, and work the nearest `digs` squares wanting swings at once.
	-- - Fighting: a fire-trench square dug full once and at `standHp` HP or more gives a fire step `rise` studs up its
	--   forward wall from the floor (Rules/BotTrenches.stepOut of Config/Build.Trench's floor and wall angle: under the
	--   parapet, eyes over it); holders take fire steps first. Shot at, reloading or pinned there, a bot drops to the
	--   square's floor (its cover). About half the holders wait in the support line until an enemy is known within
	--   `alarm` studs of the fire trench (they stand to). When enemies are known in the fire trench and fewer than `keep`
	--   of its holders still stand, it is lost: the rest fall back to the support line for `fallback` seconds.
	-- - Clearing ("Yes, clear along them"): a pushing squad's Assault bots go down into an enemy trench square within
	--   `clearWithin` studs of a known enemy and fight along it.
	Trenches = {
		share = 0.5,
		hold = 0.3,
		Fire = { edge = 0.9, width = 48, bays = 3, traverse = 6 },
		-- (56: past the zone's flagpole in its middle, which a line 40 back ran into; past Config/Build.Trench.spacing)
		Support = { back = 56, width = 32 },
		Comm = { jog = 6, short = 1 },
		on = 2,
		ends = 0.15,
		cap = 60,
		digs = 12,
		standHp = 60,
		rise = 3.4, -- (6.3 from the line in the 4.25 floor trench, 5.05 in the slimmer 3 floor one)
		alarm = 60,
		keep = 0.5,
		fallback = 30,
		clearWithin = 8,
	},

	-- Callouts (Rules/BotCallouts; user 2026-11-01: "make bots say stuff in chat (doesnt appear in actual chat, just above
	-- their person) ... dont let them spam it ... only when necessary", plain English): a bubble over the bot's head on a
	-- real event, only while a player is within `near` studs, shown to players within `hear`. A bot waits `botEvery`
	-- seconds between callouts and `sameEvery` before the same one again; a side `sideEvery` between any of its bots'.
	-- Each event is said with its `chance` (none: never). "{name}" is the fallen teammate's name.
	Callouts = {
		near = 70,
		hear = 90,
		botEvery = 8,
		sideEvery = 2.5,
		sameEvery = 15,
		manDownWithin = 40, -- studs: a teammate this close to a fallen bot calls it
		chance = {
			Hit = 1,
			ManDown = 1,
			Grenade = 1,
			Heal = 1,
			Spotted = 0.6,
			Cover = 0.6,
			MoveUp = 0.35,
			Push = 0.35,
			Covering = 0.35,
			Reload = 0.35,
		},
		-- each team's lines (Config/Uniforms.Kits `team`); Grenade and Heal wait for bots that throw and heal
		Lines = {
			Katzmark = {
				Hit = { "I'm hit!", "Argh, I'm hit!", "Medic!" },
				Spotted = { "Enemy ahead!", "Look out, there!" },
				Cover = { "Take cover!", "Down, down!" },
				MoveUp = { "Forward!", "Move up!" },
				Push = { "Take the position!", "Now, all together!" },
				Covering = { "Covering you!", "Go, I've got you!" },
				Reload = { "Reloading!", "Loading!" },
				ManDown = { "Man down!", "They got him!", "{name} is down!" },
				Grenade = { "Grenade!", "Grenade out!" },
				Heal = { "Hold still, I've got you." },
			},
			Selvara = {
				Hit = { "I'm hit!", "They got me!", "Medic!" },
				Spotted = { "Enemy, there!", "Watch out, ahead!" },
				Cover = { "Get down!", "Take cover!" },
				MoveUp = { "Forward!", "Forward, lads!" },
				Push = { "Take the flag!", "All together, go!" },
				Covering = { "I'll cover you!", "Go, go!" },
				Reload = { "Reloading!", "Loading!" },
				ManDown = { "Man down!", "No! He's down!", "{name} is down!" },
				Grenade = { "Grenade!", "Grenade, get back!" },
				Heal = { "Stay with me, I'll patch you." },
			},
			Sowilo = {
				Hit = { "I'm hit!", "Blast, I'm hit!", "Stretcher-bearer!" },
				Spotted = { "Enemy ahead!", "Look out, front!" },
				Cover = { "Get down!", "Into cover, lads!" },
				MoveUp = { "Forward!", "Up and at 'em!" },
				Push = { "Over the top, lads!", "Take that flag!" },
				Covering = { "Covering fire!", "Go on, I'll cover!" },
				Reload = { "Reloading!", "Changing clips!" },
				ManDown = { "Man down!", "They've got {name}!" },
				Grenade = { "Grenade! Get clear!" },
				Heal = { "Steady, I'll see to you." },
			},
		},
	},

	Think = 10, -- brain steps a second, per bot (staggered)
	Sense = 4, -- sight checks a second, per bot: the nearest few enemies' line-of-sight rays
	SenseNearest = 3, -- how many of the nearest enemies in range and view get a ray
	Eye = 1.5, -- studs over the root: where a bot looks from (the head)
	Direct = 0.5, -- seconds between the director's counts
	-- turning to the target while aiming (an AlignOrientation on the root)
	Turn = { responsiveness = 25, torque = 1e6 },
	FacingWithin = 20, -- degrees: it fires only when its body faces the target this closely
	PitchLimit = 60, -- degrees the look pitch sent to clients stays within
	Lag = 0.5, -- share of the reaction time its aim lags a moving target by (the difficulty's lead makes up part)

	Move = {
		Repath = 6, -- seconds between path recomputes toward the same goal
		-- a path found for one bot serves others for `keep` seconds: one going within `goalWithin` studs of its goal and
		-- standing within `fromWithin` of one of its waypoints joins it there; only paths `longer` than that are kept
		-- (the long walks), the newest `max`
		Share = { keep = 30, goalWithin = 30, fromWithin = 20, longer = 60, max = 64 },
		Arrive = 3, -- studs from a waypoint (flat) that count as reached
		StuckWindow = 1.5, -- seconds over which a moving bot must make StuckDistance of progress
		StuckDistance = 1.5,
		-- a progress sample older than this (s) is no sign: the bot wasn't walking (held in the wave line, down)
		StuckStale = 4,
		-- studs inside the map's walls every goal stays (the walls stop soldiers, paths don't see them)
		Edge = 6,
		StuckJumps = 2, -- jumps tried before a fresh path
		StuckRepaths = 3, -- fresh paths before a random step aside
		Sidestep = 12, -- studs: the random step aside
		WaypointSpacing = 6,
		AgentRadius = 1.6,
		AgentHeight = 5,
		InZoneShare = 0.9, -- within this share of the zone's radius it counts as in the zone (and wanders there)
		SprintFrom = 60, -- studs to the goal over which an advancing bot sprints
		-- inside the zone: a new spot to stand on every this many seconds, within this share of the radius
		WanderEvery = 4,
		WanderShare = 0.6,
		-- while engaging in the open: never standing still, a step left or right every so often (seconds between,
		-- studs), sometimes forward or back
		StrafeEvery = { 0.8, 2 },
		Strafe = { 4, 9 },
		-- on the way to the zone, a bend through a point off the straight line (a share of the way across, either
		-- side), so bots come from different directions
		Flank = { 0.15, 0.4 },
		FlankChance = 0.6,
		-- cover (Rules/Bots.pickCover): points round the bot in rings, each checked with a ray from the threat's eye to
		-- the point's chest height (hidden if it hits something first); the nearest hidden one within reach, not nearer
		-- the threat than the bot is less MinThreatGain
		Cover = {
			rings = { 6, 12, 20 },
			perRing = 8,
			chest = 1.2, -- studs over the ground point (the root's height is ~3)
			reach = 24,
			minThreatGain = 4,
			at = 2.5, -- studs from the point that count as in cover
			every = 0.75, -- seconds between searches while a threat is known
			moved = 8, -- the threat moving this far makes the cover found stale
		},
		-- the peek: where it last stood in the open (or a step to the side of cover toward the target)
		PeekStep = 4,
	},

	-- the brain's thresholds (Rules/Bots.step)
	Brain = {
		RetreatBelow = 0.35, -- health share under which a bot that is being shot falls back
		RetreatFor = 6, -- seconds it falls back
		RetreatDistance = 40,
		RetreatUntil = 0.6, -- health share at which it stops falling back early
		ReloadBelow = 0.4, -- rounds share under which it reloads when nothing is in sight
		Forget = 2.5, -- seconds a target out of sight is still hunted (aimed at where it was last seen)
		Alert = 3, -- seconds after being hit that it looks all round (no view cone)
		BoltDelay = { 0.25, 0.45 }, -- seconds after a bolt rifle's shot before it works the bolt
		Reacquire = 1, -- seconds out of sight after which seeing the target again takes the reaction time again
		ThreatMemory = 2.5, -- seconds a near miss or a hit keeps it under threat
		CoverFor = { 1.2, 3 }, -- seconds it stays in cover before peeking
		CoverEvery = 4, -- seconds between dashes to cover (it fights in the open in between)
		PeekFor = { 1.5, 3 }, -- seconds a peek lasts at most
		PeekQuiet = 0.6, -- seconds without a near miss before it dares to peek
		NearMiss = 5, -- studs from its head a shot passing counts as a near miss
		LookCone = 15, -- degrees: an enemy facing it this closely (and in sight) has spotted it
		-- Normal roles (Rules/BotSquads): pressing on, an enemy past this many studs is shot at on the move, not fought
		-- where it stands
		PressWithin = 25,
		-- covering fire: seconds between shots at a known enemy spot, and the extra spread (degrees) of those shots
		SuppressGap = { 0.7, 1.5 },
		SuppressSpread = 3,
		-- suppressed itself (Config/Suppression's level from passes, impacts and blasts, as a player's): its aim this
		-- many degrees wider at full, and from this level up it is pinned: cover even while pressing on, no peeks
		SuppressedAim = 4,
		SuppressedCover = 0.6,
		-- shot at (user 2026-11-01: "they should disperse and be aware of where your shot came from (not where you are,
		-- but where it came from)"): it guesses the shot's source along the bullet's way, the bearing off by up to
		-- HeardAngle degrees and the distance by up to HeardRange of it; teammates within AlertRadius studs of it are
		-- alerted too (their own guess); cover a teammate stands within SpreadMin studs of is no cover, and a step aside
		-- goes away from a teammate that close
		HeardAngle = 20,
		HeardRange = 0.35,
		AlertRadius = 15,
		SpreadMin = 6,
	},

	-- difficulty (user 2026-10-30: reaction time, aim error, spot range)
	Default = "Medium",
	Difficulty = {
		Easy = {
			reaction = 0.8, -- seconds from first seeing an enemy to the first shot's aim
			aimError = 5, -- degrees: the aim's error on a new target
			aimFloor = 1.6, -- degrees: what it settles to
			settle = 1.6, -- seconds for the error to fall most of the way (exponential)
			moving = 1.5, -- extra degrees against a target crossing at walk speed (10 studs/s)
			spotRange = 150,
			fov = 100, -- degrees across
			lead = 0.3, -- share of the target's motion over the reaction time it leads by
			fireGap = { 0.35, 0.8 }, -- seconds a semi rifle waits between shots (over its fire time)
		},
		Medium = {
			reaction = 0.45,
			aimError = 2.5,
			aimFloor = 0.8,
			settle = 1.2,
			moving = 1,
			spotRange = 250,
			fov = 120,
			lead = 0.6,
			fireGap = { 0.25, 0.6 },
		},
		Hard = {
			reaction = 0.25,
			aimError = 1.2,
			aimFloor = 0.35,
			settle = 0.8,
			moving = 0.5,
			spotRange = 400,
			fov = 140,
			lead = 0.9,
			fireGap = { 0.15, 0.4 },
		},
	},

	-- the server's log line (cost and how the fights go) every this many seconds while bots are on; 0 none
	ReportEvery = 15,
}

return table.freeze(Bots)
