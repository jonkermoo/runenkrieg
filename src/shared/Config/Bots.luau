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
	-- on the bots' Workspace folder: how many bots fight on each side in Normal ("West" / "East" after it), for the
	-- loadout menu's team counts (src/client/Menus)
	SideAttribute = "Side_",
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
	-- the classes a bot can play (Config/Classes; the first is the free default) and the range a short gun closes in to
	-- (nil: it fights from where it is). In FFA a bot buys them with its match points; in Normal it rolls one each
	-- life by `weight` (user 2026-11-03: "just remove bot point earnings entirely and just have each class be a chance
	-- of spawning", so every class is seen: Rules/Bots.rollClass); gun and dugout duty still make an Engineer.
	Classes = {
		{ key = "Rifleman", weight = 35 },
		{ key = "Grenadier", weight = 15 }, -- (user 2026-11-01: bots play it; only Grenadiers throw)
		{ key = "AutoRifler", weight = 15 },
		{ key = "Shotgunner", push = 18, weight = 12 },
		{ key = "Engineer", weight = 13 }, -- (user 2026-11-02: Engineer bots build; Config/Bots.Build)
		{ key = "Mage", weight = 10 }, -- (user 2026-11-02: Mage bots in Normal and FFA; Config/Bots.Staff)
	},
	-- the share of the battle points (Config/Classes.Earn: the kill, headshot and assists) a bot's death pays its killer
	-- (user 2026-10-30: "make the AIs count half the battle points when you kill them")
	KillShare = 0.5,
	-- FFA: the chance a bot buys the dearest class it can pay for each life (else one it can pay for at random: it saves
	-- up)
	Buy = 0.6,
	-- soldiers each mode is topped up to: players first, bots for the rest (Rules/Bots.wanted); modes not listed get none.
	-- Normal tops up each side (Rules/Bots.wantedSides; user 2026-10-31: "this will be a 50vs50 map. however, if there is
	-- only 1 player, lets make it a 20 v 20 game"); 2026-11-04: "Bots should always be 20 on each side but is removed if
	-- total count exceeds 30" (a side's players and bots: 25 players get 5 bots, 40 none)
	Fill = {
		FFA = { total = 8 },
		Normal = { perSide = 20, sideMost = 30 },
	},
	-- the most bots one server runs in each mode, whatever the fill (the server's budget; FFA Stage 1 measured 10 and
	-- 20); the governor (Budget) may hold it lower
	Max = { FFA = 20, Normal = 40 },
	-- the most a test's pin (Attribute) may run in Normal, over Max (user 2026-11-04: "can you give me a 100 bots (50
	-- each side) option in the admin panel?"); the governor still trims it when the server can't keep up
	PinMax = { Normal = 100 },
	-- one bot in (or a dead retiring one out) at most this often, so a join or a leave never brings a crowd at once
	JoinEvery = 1.5,
	LeaveEvery = 4,
	-- Over the count (a player joins, a side passes Fill.Normal.sideMost, the admin's pin drops): living bots are never
	-- taken out of the fight (user 2026-11-04: "it should stay alive and once it dies, it wont respawn"). The surplus
	-- is marked retiring (Rules/Bots.retiring: the dead first, then those not crewing a gun, farthest from any player)
	-- and leaves at its death; the count back up un-marks them before any new bot comes. On the bots' folder for the
	-- admin panel: how many retire on each side ("West" / "East", or "" in FFA, after it)
	RetiringAttribute = "Retiring_",

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
		-- a squad moves on from a point on its way (its waypoint, its approach spot) once `readyShare` of its free
		-- members (not building, rescuing or guarding) are there, or anyone has waited there `waitMax` s (user
		-- 2026-11-03 play test: "a lot of AI's frozen after a sector taken": members off on jobs kept the rest waiting)
		waitMax = 20,
		-- pinned in the open (user 2026-11-04 play test: "bot groups often stay in place ... making them an open target
		-- to artillerys"): an attacking squad shot at whose middle hasn't moved `moved` studs in `after` s, with fewer
		-- than `cover` of its members in cover, presses on toward its objective for `press` s, fighting on the move
		-- (Rules/BotSquads.pinned)
		Open = { after = 12, moved = 8, cover = 0.5, press = 20 },
		-- Pushing a group (Rules/BotSquads.group, confident; user 2026-11-02 hand test: "make AI push as a team / group if
		-- they are confident they can take out a section/group of enemies. they can coordinate too (cover, grenades,
		-- etc)"; "Outnumber 1.5 to 1"; "if they have a grenade, use it. if not, just cover each other as you rush. cover,
		-- (grenade if applicable), bound"): an attacking squad not yet pushing into the zone, with known enemies within
		-- `reach` studs (a group: those within `cluster` of the nearest), and its side's soldiers within `near` studs of it
		-- at least `odds` times the group, bounds at the group (half covering, half rushing, swapping); a Grenadier of it
		-- within reach of the group throws at it first, for up to `bombFor` seconds.
		Push = { odds = 1.5, reach = 90, cluster = 20, near = 40, bombFor = 10 },
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
	-- Spreading out (user 2026-11-02 hand test: "bots walk neck to neck. make them spread out a little even if they are
	-- going to the same place"): walking a path with a teammate within `apart` studs, a bot's next step goes `push`
	-- studs aside, away from them.
	Spread = { apart = 3.5, push = 2.5 },
	-- Firing only with a line of sight (user 2026-11-02 hand test: "some bots are shooting through terrain even though
	-- they cant physicall see the enemy"): each shot needs a clear line from the muzzle to the target (anything in the
	-- way, terrain too); covering fire at a known spot a clear line to within `near` studs of it.
	-- Aiming only at what it sees (user 2026-11-04: "some AIs still keep aiming through walls and hills at enemies"): a
	-- target counts as in sight for `stale` seconds past the bot's own look interval (its last ray found it; between
	-- looks it is not re-checked); a covering-fire spot whose line was blocked is not fired at, nor aimed at, for
	-- `blockedFor` seconds.
	Sight = { near = 6, stale = 0.15, blockedFor = 3 },
	-- How far a bot can make a soldier out (Rules/Bots.sightRange; user 2026-11-05: "are bot visibility range accurate
	-- with fog?"), as far as a player can on screen (Config/Environment's haze, Studio stills): `clear` studs on a clear
	-- day, times the weather's share at its full strength (Fog, Rain; eased over its fades) and `night` at full night
	-- (eased over the twilight). Its difficulty's spotRange caps it too. A soldier who fired within `flashFor` seconds is
	-- seen out to `flash` x the weather's range, night or not (the muzzle flash). Rechecked every `every` seconds.
	Seeing = { clear = 600, Fog = 0.3, Rain = 0.55, night = 0.4, flash = 0.9, flashFor = 0.6, every = 1 },
	-- Butt strokes (Rules/BotBuild.strikes, src/server/Melee.strikeAs; user 2026-11-02 hand test: "also allow AI to melee
	-- (dont force them to just because are withing range)"; "Sometimes"): with its target within Config/Melee.Hit.reach
	-- less `margin`, a bot strikes on a roll under `chance` (`empty` with its gun empty or loading), rolled at most every
	-- `every` seconds.
	Melee = { chance = 0.33, empty = 0.8, every = 1.5, margin = 1 },

	Actions = {
		every = 0.5,
		Drag = { within = 12, cover = 15, seconds = 8 },
		Heal = { calm = 3, below = 0.7, within = 25, reach = 4, seconds = 10 },
		-- in a fight a teammate is dragged or healed only from cover or in cover (Rules/BotActions.mayTend; user
		-- 2026-11-03: "they protect you and grab/heal you once it is safe"): else the bot stays within `near` studs of
		-- them with its gun out, fighting, for up to `keep` s, and goes to them once it may
		Guard = { near = 6, keep = 20 },
		-- one rescuer a casualty (Rules/BotActions.rescuer; user 2026-11-03: "only have 1 soldier save them"): the nearest
		-- free bot of its side within `range` studs, one of its squad first; the rest keep their push, post and
		-- formation. A bot in a push never breaks off for one. A rescuer that dies or is pulled away lets it go, and
		-- another may take it `wait` s later.
		Rescue = { range = 40, wait = 3 },
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
	--   (Doors.openFor) and waits `doorWait` s while it swings, never at a shut one out of its reach (it walks on); paths
	--   cost Config/Indoors.PathCosts. A door swung open or shut (open, it stands in the room: paths go round it): the
	--   shared paths within `Swung.near` studs of it are dropped and the bots that near path again, `Swung.after` s on
	--   (the navmesh catching up; user 2026-11-04: "opening thje door bnreaks their path finding").
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
		Swung = { near = 40, after = 0.5 },
		bump = 4, -- a bot stuck within this of a shut door's panel opens it (a path through a doorway with no link)
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
	-- - Nest: MG nests `ahead` of the `count` hold spots nearest the enemy, less those of its side's already standing
	--   at the front (user 2026-11-03: "3 mg nests if there arent built").
	-- - Guns: the guns its side may build (Rules/Frontline.gunLocked), `back` studs behind the zone's middle, `side` apart.
	-- - repairs: own pieces within `repair` studs past the zone's edge that want swings (the nearest `repairs`).
	-- (the trenches: Trenches below.) Engineers take the nearest job within `take` studs; a digger (Trenches.share of a
	-- holding squad) takes a trench job within `take` and helps work wire within `help`. A bot
	-- builds only when nobody has shot at it or hurt it for `calm` s and it sees no enemy; it stands `stand` studs from
	-- a piece's spot to lay it, gives a job up after `seconds`; a refused spot moves `nudge` studs across (a trench
	-- run's far end swings aside: Rules/BotTrenches.swing; up to `tries` times), then waits `retry` s. A piece of the job's key within `match` studs of
	-- its spot is the job's. The list's swings left are reckoned for a `builder` (a Config/Classes key: its Build swing
	-- share, Config/Build.Power).
	-- Caps (user: "A third, half the guns"): the bots lay at most `caps.pieces` of the team's Config/Build.PerTeam and
	-- `caps.<key>` of a gun's.
	Build = {
		builder = "Engineer",
		calm = 3,
		take = 150, -- (was 90: diggers walked off their front's runs)
		-- an Engineer takes a job this far off (user 2026-11-03 play test: "even when i give free engineers, the bots arent
		-- building": the front's jobs lay past `take` from the sector their squads were sent to)
		engineerTake = 400,
		-- an attacking Engineer takes jobs within this of where it is (not back at its side's front: user 2026-11-04,
		-- "why are they not pushing")
		attackTake = 120,
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
		-- (wire only in the enemy's way, user 2026-11-02 hand test: `gap` studs off its own side's ways forward and
		-- `spawn` off its spawn, moved across `step` at a time up to `shift`, else not laid: Rules/BotBuild.wireSpot)
		Wire = { out = 40, lanes = { -40, 0, 40 }, gap = 12, spawn = 60, step = 6, shift = 24 },
		-- no swing at a piece of theirs within `repairWait` s of it losing HP (user 2026-11-02 hand test: "Dont let ai
		-- repair structures that are being destroyed by players"; "20 seconds": Rules/BotBuild.mayRepair)
		repairWait = 20,
		-- a job is walked to with the gun out, fighting on the way (user 2026-11-03 play test: "shooting and protecting
		-- themselves and finding cover as they move to where they want to go"): the gun goes away only within `near`
		-- studs of where it works and once it is safe there (Rules/BotBuild.safeToWork); danger mid-work drops the tool
		-- and it fights, then goes back to it. The job is kept `keep` s from when it was taken. A bot whose lay or swing
		-- there is refused leaves that job to others for `skip` s and takes another (user 2026-11-04: bots "digging
		-- animation then stops then goes then stops" at a spot the ground or a trench refused, re-taking it each think).
		-- One that gets no `gain` studs nearer it in `stall` s on its way (and isn't fighting) leaves it to others for
		-- `lost` s (an Engineer stood 4 minutes "going" to a Howitzer spot it had no way to, taking it again each time
		-- `keep` ran out: Rules/BotBuild.stalled).
		-- The job's own clock (survives a re-take of the same job, b.jobNote): no swing landed for `noSwing` s since it was
		-- taken (or its last swing), or begun and broken off within `flapWithin` s of beginning `flapMax` times, and the
		-- bot leaves it to others for `lost` s (2026-11-04 match test: "Trench going: on it 3,273 s, swings 0"; "began
		-- 541, broke off 541"). A job `giveUpAfter` bots left for no way there (stall), no swing or flapping is out of
		-- reach for its side: refused (Act.refused), so the planner nudges its spot or drops it for a while.
		Work = {
			near = 3,
			keep = 60,
			skip = 30,
			stall = 20,
			gain = 3,
			lost = 120,
			noSwing = 60,
			flapMax = 5,
			flapWithin = 2,
			giveUpAfter = 3,
		},
		Nest = { ahead = 2, count = 3 },
		Guns = { back = 60, side = 24 },
		-- (pieces 100: a third of Config/Build.PerTeam 300, as the 50 of 150 the user chose)
		-- (the guns and MG nests: its share in each sector, user 2026-11-03: "cannons and artys built should be by sector.
		-- max 6 mgs and cannons and 3 howitzers per sector": half each of Config/Build `sectorCap`, the howitzers' rounded
		-- up; its team's own there and captured ones it uses count, Rules/BotCrew.captured; was 3 field guns and 1
		-- howitzer over the whole map)
		caps = { pieces = 100, FieldGun = 3, Howitzer = 2, MGNest = 3 },
		-- Cover (user 2026-11-02: "have AI build areas of cover with sandbags and barriers", all four kinds; any class
		-- lays sandbag piles and barriers, Config/Classes):
		-- - Breast: a trench run refused at every spot (Trenches.tries) gets a breastwork along its line instead, a lay job
		--   every `step` studs, the `keys` in turn.
		-- - Walls: once an MG nest or gun stands, `count` sandbag piles `ahead` studs on its enemy side, `spread` apart.
		-- - Pinned: a bot shot at within `threat` s, suppressed `shaken` or more, with no cover found within `near` studs and
		--   not in a trench, digs a foxhole at its feet (Dugouts below), or where the ground refuses one lays a sandbag
		--   pile `ahead` studs toward the threat and fills it under fire (at most every `every` s).
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
		-- A spot's shot is flown first (user 2026-11-03: "bots will build cannons behind the hill. they should be sure the
		-- cannon would be able to hit where they want it to hit"): the shell's path from the muzzle laid on that target
		-- (Rules/Artillery.path, `arc.step` s a sample) cast against the world past `arc.near` studs out (its own ground,
		-- levelled when it is laid), kept only where it first comes down within `arc.within` studs of the target (no hill,
		-- house or tree in the way); Config/DevTools.Admin.GunArcs shows them.
		Crews = {
			max = 2,
			enough = 5, -- (all the guns its bots build in a sector: caps 3 field guns and 2 howitzers, user 2026-11-03)
			back = { 90, 60, 30 },
			across = { 0, -60, 60, -120, 120, -180, 180 },
			spawnGap = 40,
			arc = { step = 0.1, within = 25, near = 8 },
		},
		-- Trees in the way (Rules/BotBuild.treesInWay, src/server/Bots/Fell; user 2026-11-03: the forest either side of
		-- the middle stood untouched): Engineers fell the standing trees within `clear` studs of the side's trench lines
		-- (planned or dug runs and squares, its saps' runs), its MG nests' and guns' spots, and a gun's firing line out
		-- to `fireLine` studs ahead of it, the nearest the work first, `open` at once. One tree per Engineer at most every
		-- `every` s, `perSide` a side a match; never a tree in one of the map's buildings. Each stands `stand` studs
		-- from the trunk to chop it.
		-- (`every` 20 to 8, `open` 3 to 6 and `clear` 8 to 15 with the trench priority, user 2026-11-04: Map 1's sectors
		-- stand in woods and the lines waited on their trees; a trench is refused for a tree out to about 14 studs from its
		-- line, its cut, walls and dirt heaps, Config/Build.Trench.treeClear)
		Trees = { clear = 15, fireLine = 60, every = 8, perSide = 40, open = 6, stand = 5 },
	},

	-- Normal: sapping forward (Rules/BotSap; user 2026-11-02: "AI ... should [build trenches to push forward] if they are
	-- obviously unable to advance under fire", "30 s stuck, half dig"). An attacking squad moving up (Move / Bound) is
	-- stuck once `stall` s pass since it last gained `progress` studs toward its objective, while shot at or with `losses`
	-- members down since. It then saps: `share` of it digs (any class) a run `run` studs long from its most forward
	-- member toward the objective, turned `angle` degrees one way then the other (a zig-zag), each run planned once the
	-- last is dug, the rest holding where they are giving covering fire, then all moving up to its head. Sappers dig
	-- under fire (only a hit stops them). It is over at `edge` of the zone's radius from the objective, or after `quiet`
	-- s with nobody shooting at the squad.
	-- Normal: how a side fights forward (Rules/BotFront; user 2026-11-03: "once points are starting be captured and
	-- fights start (pretty early), bots should prioritize trenching lines (use real strategies) to push, rather than the
	-- open field"; "At first contact"). Until contact (the first capture, or the first shots at one of its squads) a
	-- side walks where it's safe; then its attacking squads sap (Sap above: `share` dig, zig-zag runs) once within
	-- `sapFrom` studs of their objective's zone edge, without waiting to be stuck; within `parallel.at` of it the sap
	-- turns into a parallel `parallel.width` studs across, and the squad gathers there and goes over the top together
	-- (Config/Bots.TrenchMove.Jump).
	-- Flank (user: "bots are too focused on pushing down the center"; "1 squad in 3"): `share` of a side's attacking
	-- squads take a lane off to one side (alternating), walking by a point `offset` studs across from the straight
	-- way; every `every`-th MG nest goes at the hold spot farthest across, every `every`-th gun spot at least `gunFrom`
	-- studs across (shelling the enemy's front from an angle).
	-- Offensives and the initiative (Rules/BotOrders.initiative, offensive; user 2026-11-04: fights stale at the zone
	-- edge, "an intense fight should be exciting and engaging, not boring"). Bots only: the game's rules are the
	-- players'. At match start both sides race for the middle; from the first capture one side holds the initiative and
	-- runs an offensive on its target sector, while the other defends at its front with `screen` squads still attacking.
	-- The initiative passes when the offensive captures (the loser counter-attacks), when the defender captures, or when
	-- the offensive is spent.
	-- - Gather: the attack squads go to their jump-off (a dug trench by the zone, else their approach spot) and wait,
	--   no push; at least `gatherWaves` respawn waves (Config/Frontline.Waves.every) and until `ready` of them are
	--   there, at most `gatherSeconds` (a counter-attack into a sector lost under `counterWithin` s ago: all of
	--   `counterGather`, while the side that took it digs in, `dig`).
	-- - Barrage: `barrageSeconds` of every crewed gun on the target: known MG nests and guns first, then
	--   `barragePoints` spots within `barrageSpread` studs of the zone's middle, then its dug squares.
	-- - Go: every attack squad goes in together (Assault, no ready check).
	-- - Exploit: `exploitAt` heads of the side in the zone and more than the enemy's: `exploitHold` of the squads hold
	--   the zone, the rest stand on the defenders' approach spots. Back to Go once nobody of it is in the zone.
	-- - Spent (the initiative passes): `spentShare` of the lives that went in since Go lost, or `maxSeconds` from Go
	--   (`exploitMore` s more while exploiting).
	-- `hold`: the share of the attacking side's bots holding its front meanwhile (Trenches.hold stays for the side
	-- without the initiative). An Assault squad out of the zone whose middle hasn't moved Squads.Open.moved studs in
	-- `stuckFor` s finds its way in again (holders standing to as well, counted from when they stood to).
	-- Strongpoints (`strong`): an enemy-manned gun or MG nest on enemy ground is known once a squad of the side knew an enemy within `seen` studs of it, for `forget` s; within `within` studs of the
	-- target it is the barrage's first target; within `reach` studs of a gathering squad its Grenadier throws at it and,
	-- with a Grenadier or Mage in it, the squad bounds at it.
	Offensive = {
		screen = 1,
		hold = 0.2,
		gatherSeconds = 60,
		gatherWaves = 2,
		ready = 0.6,
		counterWithin = 60,
		-- (20 to 50, user 2026-11-04: every counter-attack retook S4 within a minute or two, so the front only swung there)
		counterGather = 50,
		barrageSeconds = 20,
		barragePoints = 3,
		barrageSpread = 25,
		-- (90 to 75 and spentShare 0.6 to 0.45, user 2026-11-04: "it's fine if it takes like half an hour to get a
		-- sector. this is meant to be a pretty slow paced game": a held, dug-in sector should usually survive a push)
		maxSeconds = 75,
		exploitMore = 60,
		spentShare = 0.45,
		exploitAt = 2,
		exploitHold = 0.5,
		stuckFor = 25,
		strong = { seen = 15, forget = 90, within = 220, reach = 90 },
		-- digging in where it just took a sector (user 2026-11-04: "dig in, slower counter"): for `hold` s every `every`th
		-- holder there holds a spot inside the zone (the flag itself), the rest the fire steps on its own lines and the
		-- enemy's squares it took over (Trenches.takeOver), the support line and hold spots as before
		dig = { hold = 240, every = 2 },
	},

	Front = {
		-- (150 to 90, user 2026-11-04: the 60-150-stud band was where the attackers died sapping)
		sapFrom = 90,
		parallel = { at = 40, width = 24 },
		Flank = { share = 1 / 3, offset = 90, every = 3, gunFrom = 120 },
	},

	-- A sap that gets nowhere is given up (user 2026-11-04: "why are they not pushing": saps at a river bank, uphill,
	-- refused run after run): a run refused `Build.tries` times, a run through water (looked at every `waterStep` studs
	-- along it), or no run dug in `dig` s; the squad then presses on (Squads.Open.press) and starts no sap for `rest` s
	-- (Rules/BotSap.failed).
	-- A sap has a deadline (Rules/BotSap.deadline; the stale-fights plan 2026-11-04): it is for reaching the jump-off,
	-- so with the initiative it starts only while gathering, and it ends after `maxRuns` runs or `maxSeconds`, whichever
	-- comes first; the squad then goes with the offensive. A run that would cross water bends to the nearest ford
	-- (Map.river.fords, Rules/BotSap.ford); within `fordEnd` studs of the ford the sap is over and the squad wades on.
	Sap = {
		maxRuns = 4,
		maxSeconds = 90,
		fordEnd = 25,
		dig = 60,
		rest = 120,
		waterStep = 4,
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
		-- a cast is held while its beam from the head would hit something short of its point (user 2026-11-03 play test:
		-- "mages ... shoot their own trench by accident, then repair it"); within `ownWithin` studs of the caster (its own
		-- cover) it counts as a self-hit held off
		ownWithin = 6,
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
	-- - Keeping the lines clear (user 2026-11-02: "bots should either plan around structures, destroy them if
	--   necessary, or never have structures where trenches should be"): no bot lays a piece within `clear` studs past
	--   a trench's wall top of a run planned or dug, a sap's run or its next one, or any trench square; a digger tears
	--   down a `tear` piece (the enemy's or a bot's) in its run's way first, and swings the run aside round anything
	--   else.
	-- - Trench first (user 2026-11-04: "theres not enough trench fighting ... can we make trench more of a priority that
	--   way we can see whole maps being filled with trenches"; a measured match dug no fire step in 11 min: diggers seen
	--   at the zone's edge stopped, Engineers were on the guns): a trench job is dug under fire (only a hit stops it, as
	--   a sap), and up to `pioneers` of a side's bots (any class, defenders first, never a gun crew) are on trench duty:
	--   they take its trench jobs before anything else, from up to `pioneerTake` studs off.
	-- - Throughput (2026-11-04, the stale-fights plan: Map 1 dug 10-24 squares a side in 11 min, about 6 in 7 run plans
	--   refused): every calm holder digs (`share` 1, was 0.5); `pioneers` a side, one more for each `More.per` squares
	--   planned and not dug yet, up to `More.max`; a run starts from the real free end of the run before it as laid
	--   (`Chain`: the free square end within `off` studs of that run's line and no more than `past` of its length beyond
	--   its end, the furthest along), not its planned point, so the planner joins them; pioneers dig the squares shells
	--   have buried first (a square buried to nothing is planned again where it lay, `Redig`: for up to `keep` s, `tries`
	--   refusals).
	Trenches = {
		share = 1,
		pioneers = 3,
		More = { per = 4, max = 8 },
		Chain = { off = 4, past = 0.25 },
		Redig = { keep = 300, tries = 2 },
		pioneerTake = 600, -- (was 400: Map 1 sectors stand ~420 apart, a held system behind the front out of reach)
		-- a run refused for a tree in its way (Config/Bots.Build.Trees: the pioneers and Engineers fell it) waits `wait` s
		-- for it to come down, up to `waits` times, before it swings aside as for any other refusal (a measured match:
		-- every refusal a try, Map 1's trees had each side's fire trench given up for breastworks within a minute)
		Tree = { wait = 15, waits = 8 },
		-- forward lines (Rules/BotTrenches.forward): a side keeps each sector's system while it holds it (the front moving
		-- back and forth finds its runs as it left them); once its front's fire trench is planned, `lines` more fire
		-- trenches, each `step` of the way on to the enemy's next sector, joined back by a communication trench (a
		-- zig-zag where the enemy sees down it), none within `keep` studs of that sector's zone
		Forward = { lines = 2, step = 1 / 3, keep = 60 },
		-- the enemy's dug squares within `takeOver` studs of its front zone's edge give it fire steps as its own (the
		-- parapet turned: user 2026-11-04, "bots just destroy incoming trenches")
		takeOver = 30,
		-- a system sited on the clearest ground (Map 1's sectors stand in woods: a measured match's runs met a tree 64
		-- times in 81 tries): of its fire line `edges` of the zone's radius out (a forward line: that far on or back from
		-- its spot) and `shifts` studs across, the first with the fewest standing trees within `clear` studs of its fire
		-- and support runs, each spot every Trench.block studs along any run in water counting `wet` trees and each solid
		-- thing across a run (Map 1's stone walls, poles and houses: Trenches' "In the way") `solid`
		-- (`clear` 16: a square's cut, walls and dirt heaps reach about 14 from its line, Config/Build.Trench.treeClear)
		Site = { edges = { 0.6, 0.35, 0.85, 0.1 }, shifts = { 0, -20, 20, -40, 40 }, clear = 16, wet = 5, solid = 4 },
		-- the admin trench stats (Config/DevTools.Admin.BotTrenchStatsAttribute; Rules/BotTrenches.deathKind): a bot
		-- dying within `floor` studs of a dug square's middle died in a trench; one of Dugouts.shell kg or more within
		-- `shellNear` studs in the `shellAge` s before, by a shell
		Stats = { floor = 5, shellNear = 20, shellAge = 0.6 },
		hold = 0.45, -- (was 0.3: more holders to man the fire steps, user 2026-11-04 trench priority)
		Fire = { edge = 0.6, width = 80, bays = 5, traverse = 6 }, -- (80: across the zone, r 45; was 48 in 3; 0.6 was 0.9: diggers on the edge were always under fire)
		-- (56: past the zone's flagpole in its middle, which a line 40 back ran into; past Config/Build.Trench.spacing)
		Support = { back = 56, width = 32 },
		Comm = { jog = 6, short = 1 },
		-- a run dug toward the enemy (a communication trench, a sap) where the enemy can see down it is dug in a
		-- zig-zag (user 2026-11-03 play test: "building straight down will be in line of fire of the enemies uphill.
		-- however if we zigzag, we are in cover while building forward"; Rules/BotTrenches.exposed, zigzag): exposed
		-- with a threat (the enemy's next sector, or an enemy its squad knows of, within `range` studs: 500 reaches the
		-- next sector, Map 1's are some 420 apart) within `cone` degrees of the run's line, or above it by `plunge` degrees of elevation, that a ray from its eye over the
		-- ground reaches; then legs `leg` studs long, each turned off the line by `angle.min` degrees plus `angle.perStud`
		-- for each stud the threat stands above the run (up to `angle.max`), alternately. Safe: straight.
		Zigzag = { cone = 20, plunge = 10, range = 500, leg = 12, angle = { min = 25, perStud = 1, max = 45 } },
		on = 2,
		ends = 0.15,
		cap = 160, -- (was 60)
		-- its squares wanting swings within this of its front zone's edge are dug (Build.repair for other pieces; its
		-- forward lines lie a third of the way to the next sector, Forward)
		digReach = 220,
		digs = 12,
		standHp = 60,
		rise = 3.4, -- (6.3 from the line in the 4.25 floor trench, 5.05 in the slimmer 3 floor one)
		alarm = 60,
		keep = 0.5,
		fallback = 30,
		clearWithin = 8,
		clear = 1.5,
		tear = { SandbagPile = true, Hesco = true, Wire = true },
		-- Looking after its trenches (Rules/BotTrenchCare; user 2026-11-05: "trenches still end up getting destroyed
		-- before they get anywhere ... most soldiers trench in the open or already highly conflicted areas ... start, build,
		-- reinforce, then keep going. if the base of the trench gets destroyed, theres nothing left for the trench"; the
		-- plan's four choices as recommended):
		-- - Map: the shell map, each shell (`shell`) and own death (`death`) counted in its `cell`-stud cell, fading by half
		--   every `half` s. Site: a system or forward line is sited (Trenches.Site) with `heat` for each unit of the map's
		--   heat (at most Score.heatMost) at each spot every `sample` studs along its runs, and `seen` for each such spot
		--   (`seenEvery`th) the enemy's next sector sees from `eye` studs over its ground to `head` over the run's over
		--   the terrain (a reverse slope hides it; a tree line hides only where the planner refuses it), within
		--   Zigzag.range. Of the layouts within `slack` of the clearest ground (Trenches.Site: what the planner refuses
		--   counted first), the one with the least of these; none with a run within `flag` studs of the zone's flagpole.
		-- - Hot: no new square dug within `radius` studs of a shell in the last `seconds` (its diggers go to a cooler
		--   job; the run is still planned: a front line is shelled most of the time, and a measured match with runs held
		--   off for 120 s never planned its fire trench); a critical square (a dugout's, the base) is still repaired
		--   there, though not within `lull` s of a shell.
		-- - Rear: the way back from a system's support line to safe ground, `back` studs: with the support line its base,
		--   planned before the fire trench (Rules/BotTrenches.layout).
		-- - Score: each dug square's decision (Rules/BotTrenchCare.decide): busy at `busy` (its bots' seconds in it lately,
		--   fading by e every `fade` s), safe 1 at its base line to 0 `far` studs ahead; the weights `w`; ignore under
		--   `patch`, patch, fix from `fix`, reinforce from `reinforce`, its extra a step (25) for each of `steps` reached.
		--   `repairs` of its squares wanting repair listed first, the best first; `repairers` of its pioneers take the
		--   best one before any other trench job.
		-- - Gate: before a system's next forward line (Rules/BotTrenchCare.gate); a dugout whose foot is within `dugout`
		--   studs of one of its squares is in it.
		-- - Join: another network of its trenches (players' too) of `min` squares or more, an end within `reach` studs of
		--   its main one (its front system's), gets a communication run to it unless that ground is hot; one at a time,
		--   looked at every `every` s, `touch`: two squares this near are joined already.
		Care = {
			Map = { cell = 20, half = 180, shell = 1, death = 0.6 },
			Site = { heat = 1, sample = 8, seen = 1, seenEvery = 2, eye = 6, head = 3, slack = 0, flag = 8 },
			Hot = { radius = 20, seconds = 120, lull = 15 },
			Rear = { back = 32 },
			Score = {
				busy = 30,
				fade = 60,
				far = 150,
				heatMost = 3,
				w = { used = 2, safe = 1.5, dugout = 3, base = 3, link = 1.5, heat = 0.75 },
				patch = 0.5,
				fix = 1.5,
				reinforce = 3,
				steps = { 3, 4.5, 6 },
				repairs = 6,
			},
			repairers = 2,
			Gate = { dug = 0.8, extra = 25, share = 0.8, wait = 240, dugout = 12 },
			Join = { touch = 5, reach = 48, min = 3, every = 5, short = 1 }, -- (48: within Trench.maxPlan, zig-zagged)
		},
	},

	-- Normal: moving by trench (Rules/BotTrenches.danger; user 2026-11-02: "most pvp should be trench based. if bots can,
	-- they should ideally use trenches to get around if they know there's danger. if it's an open field with no enemies
	-- they should just walk of course. make it realistic, this is mostly a trench fighting game").
	-- - Danger (all four, "Shot at recently, Enemy known near, Shelling near, Contested goal"): shot at within `shot`
	--   seconds; an enemy known to it or its squad within `near` studs in the last `known` seconds; a shell or grenade
	--   within `blastNear` studs in the last `blast` seconds; its goal's sector with enemies in it.
	-- - Knowing there's danger, its path costs `open` times as much over `materials` (the open ground) as along a dug
	--   trench square (each square's hole is marked `label` for pathfinding): a trench route wins while it is under
	--   `open` times the open stretch it stands in for ("Strong, x4"). With no danger it walks straight across.
	-- - Shot at in the open with an own dug trench square within `cover` studs, it drops into it (its cover).
	-- - Over the top ("Yes, gather then go"): an attacking squad gathers first in its side's dug trench square nearest
	--   the objective (no more than `Jump.reach` studs past the zone's edge, `Jump.ahead` studs nearer it than the
	--   squad), within `Jump.at` studs of it; it goes once `Jump.gather` of it is there, or `Jump.wait` seconds after
	--   the first got there.
	TrenchMove = {
		shot = 10,
		known = 15,
		near = 120,
		blast = 15,
		blastNear = 40,
		open = 6, -- (was 4: with the trench priority's lines to use, user 2026-11-04)
		label = "Trench",
		materials = {
			"Grass",
			"LeafyGrass",
			"Ground",
			"Mud",
			"Sand",
			"Rock",
			"Slate",
			"Sandstone",
			"Limestone",
			"Basalt",
			"Snow",
			"Pavement",
			"Asphalt",
			"Cobblestone",
		},
		cover = 25,
		Jump = { reach = 120, ahead = 15, at = 10, gather = 0.75, wait = 25 },
	},

	-- Normal: dugouts and foxholes (Rules/BotTrenches.shelled, dugoutsWanted, dugoutSquares, seat, foxholeWanted,
	-- occupied; user 2026-11-02, "can bots build dug outs?" then "Plan it").
	-- - Shelled: a shell (a blast of `shell` kg or more: not a grenade) within `near` studs of a side's trench squares in
	--   the last `recent` seconds.
	-- - Building ("whenever they need one but dont make bots abuse it"): none until the side's trenches at its front have
	--   been shelled, or one of its squares has been `Heat.build` hot; then room for its holders but its sentries, `room` to a dugout, in its support line's squares dug
	--   to `dug` of their HP, and its fire trench's squares `Heat.build` hot, the rear wall (away from the enemy),
	--   `spacing` studs apart, the hottest squares first (their heat over `Heat.memory` s: the often shelled and fought
	--   over), then the line's middle.
	--   Engineers dig them when calm, as any job on the list; while a side has one to dig, up to `engineers` of its bots
	--   pick Engineer when they respawn, if they can pay (dugout duty, as the gun crews: Build.Crews), and take dugout
	--   jobs first.
	-- - Sheltering (user 2026-11-03: "make bots utilize dug outs more often, especially in trenches highly contested or
	--   often shelled"): by how hot its post is (Rules/BotTrenches.heat, `Heat`): shells landing within `Heat.radius`,
	--   the side's own dead there and enemies known within `Heat.enemyNear`, each fading by e every `Heat.fade` s. At
	--   `Heat.enter` (and not standing to, not falling back) a holder goes down into the nearest standing dugout within `reach` studs with a
	--   place, one per fire bay staying on the fire step as a sentry ("1 per fire bay"); it comes up to its post once
	--   its post cools under `Heat.leave` (the heat where it sheltered from, not at the dugout: user 2026-11-04, "a
	--   crazy amount of bots are stuck in dugouts", holders went down hot and came straight up cold, over and over),
	--   but never before `Heat.least` s down; the side stands to, or after `Heat.stay` s down; then fights `Heat.rest`
	--   s before it may go down again ("They still need to come back out and fight"). A dugout's `room` places count
	--   every body down in it, not only the holders sent there; a holder sent off to attack leaves it.
	-- - Bombing out ("Yes"): a Grenadier of a pushing squad throws a grenade down the steps of an enemy dugout its squad
	--   knows someone is in (a known enemy within `Bomb.inside` studs of its room, under the trench floor), from `min`-`max`
	--   studs, no teammate within Actions.Grenade.safe of the steps.
	-- - Foxholes ("Pinned in the open, Holding before trench"): pinned down in the open (Build.Pinned) a bot digs a
	--   foxhole at its feet (a sandbag pile instead where the ground refuses one) and fights from it; a holder at an open
	--   post with no own dug trench within `Fox.trench` studs digs one there facing the enemy, no two within `Fox.apart`.
	--   The bots remember the foxholes they dug (the newest `Fox.keep`) and take one within TrenchMove.cover studs as
	--   cover, as a trench square.
	Dugouts = {
		shell = 0.5,
		near = 40,
		recent = 8,
		room = 3,
		reach = 50, -- (a holder only goes down into a dugout this near: never across the front to another's)
		dug = 0.95,
		spacing = 16, -- (as Config/Build.Dugout.spacing: a dugout there is refused nearer)
		recheck = 60, -- (a square refused one, Build.dugoutFor: no ground round its room, left out this many seconds)
		engineers = 1,
		Bomb = { inside = 6, min = 6, max = 25 },
		Fox = { trench = 30, apart = 5, keep = 120 },
		-- (a bot down in a dugout's steps or room that isn't sheltering there walks straight up to its foot; still
		-- down after `after` s, it is lifted out onto the trench floor `out` studs in front of the foot)
		Free = { after = 12, out = 2 },
		-- (`weight`: a shell, an own death, an enemy known near; `edge`: a shell's or death's share at `radius`;
		-- `keep`: the seconds a shell or death is remembered; `enemyMost`: the most heat its known enemies add)
		Heat = {
			radius = 30,
			edge = 0.6,
			fade = 25,
			memory = 90,
			keep = 120,
			weight = { shell = 1, death = 0.6, enemy = 0.1 },
			enemyNear = 70,
			enemyMost = 0.5,
			enter = 0.8,
			leave = 0.35,
			least = 10,
			stay = 40,
			rest = 12,
			build = 1.5,
		},
	},

	-- Callouts (Rules/BotCallouts; user 2026-11-01: "make bots say stuff in chat (doesnt appear in actual chat, just above
	-- their person) ... dont let them spam it ... only when necessary", plain English): a bubble over the bot's head on a
	-- real event, only while a player is within `near` studs, shown to players within `hear`. A bot waits `botEvery`
	-- seconds between callouts and `sameEvery` before the same one again; a side `sideEvery` between any of its bots'.
	-- Each event is said with its `chance` (none: never). "{name}" is the fallen teammate's name.
	Callouts = {
		near = 70,
		hear = 90,
		-- about 40% less chatter (user 2026-11-04: the bots should chat about 40% less): botEvery was 8,
		-- sideEvery 2.5, and the chatter chances (Spotted to Reload) x 0.6 of 0.6 / 0.35; the calls that matter stay at 1
		botEvery = 13,
		sideEvery = 4.2,
		sameEvery = 15,
		manDownWithin = 40, -- studs: a teammate this close to a fallen bot calls it
		chance = {
			Hit = 1,
			ManDown = 1,
			Grenade = 1,
			Heal = 1,
			Spotted = 0.36,
			Cover = 0.36,
			MoveUp = 0.21,
			Push = 0.21,
			Covering = 0.21,
			Reload = 0.21,
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
		-- a waypoint reached between thinks is walked on from at once (Move.arrived; user 2026-11-04: bots "move like
		-- 10 studs, stops, then moves again": thinking 2 to 10 times a second, a running bot reached its waypoint and
		-- stood until its next think, and its legs, set at each think from its speed then, stood too); not again
		-- within `ArriveGap` s, and only while its last think walked it, within `ArriveStale` s
		ArriveGap = 0.05,
		ArriveStale = 0.6,
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
		-- the idle watchdog (src/server/Bots think): a bot off its post (`post` studs), not crewing, down, acting or
		-- fighting, out of its zone, that has moved no `studs` in `seconds` s has its job, guard and goal dropped and walks
		-- to its stand point (else the zone) for up to `push` s; counted in the [Bots] line ("idle resets"). (2026-11-04
		-- match test: bots stood 2-23 minutes "going to Trench, no goal" or at "goal 0 studs" far from their post.)
		-- (`seconds` 25, not 20: a squad waits up to Squads.waitMax 20 s at a waypoint for its members)
		-- (a reset bot down inside a dugout that isn't its post walks straight up its steps first)
		Idle = { seconds = 25, studs = 3, post = 4, push = 15 },
		-- waiting instead of milling (Rules/BotWait; user 2026-11-05 hand test: "instead of standing idly, they just move
		-- in the same spot. if they're going to think, at least have them do it in a trench or while they're providing
		-- fire"): a Normal bot engaging in the open (no cover), inside its zone, at its squad's stop, or `stall` s no
		-- `gain` studs nearer its goal goes to a wait spot near where it should be and holds there, firing at what it
		-- sees:
		-- - its side's fire steps, support line, dug trench squares and hidden spots, the best by `weights` (a fire
		--   step facing the enemy best; `distance` a stud off), none within `gap` studs of another soldier or wait spot;
		-- - none free: `step` studs away from the teammates crowding it (none crowding: it stands where it is);
		-- - within `fight` studs of where it stands while engaging, the zone's wander circle in the zone, `stop` of its
		--   squad's stop (a squad counts its members within Squads.arrive * 3 of a waypoint, Trenches.Jump.at of its
		--   jump-off), `stalled` of where it got stuck (for `hold` s, then a fresh path);
		-- - `arrive`: studs from its goal that count as there; a bot with none looks again every `every` s.
		-- The stuck readout lists bots `mill.seconds` s inside `mill.radius` studs off post (shuffling, not standing
		-- still), and how many stand in a clump (`clump.count` others within `clump.within` studs).
		Wait = {
			gap = 5,
			step = 6,
			fight = 30,
			stop = 8,
			stalled = 25,
			arrive = 4,
			stall = 10,
			gain = 4,
			hold = 12,
			every = 1,
			weights = { step = 30, reserve = 22, square = 15, cover = 10, distance = 0.5, facing = 10 },
			mill = { radius = 8, seconds = 20 },
			clump = { within = 4, count = 3 },
		},
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
		Forget = 2.5, -- seconds a target out of sight is still hunted (where it was last seen)
		AimMemory = 1.2, -- seconds a target out of sight is still aimed at (where it was last seen); then the gun drops
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

	-- At ease (Rules/Bots.calm; user 2026-11-04: "make AI not hold weapons if they know for a FACT that theres no enemies
	-- around (just so it looks nice)"): a bot with no target for `after` seconds, not hit, shot at or near a shot for
	-- that long, its suppression under `shaken`, no enemy spot its squad knows within `radius` studs and no enemy at all
	-- within `near` studs (seen or not) carries its gun low: `move` walking, `stand` standing (Config/Locomotion holds).
	-- Looks only: it raises the gun the moment one of those changes. (`stand` "ready", not "carry": the carry hold is a
	-- running cycle, and standing still in it the gun shook as if running, user 2026-11-04; Rules/Bots.hold)
	Calm = { after = 4, radius = 90, near = 40, shaken = 0.05, move = "carry", stand = "ready" },

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

	-- Normal: bots on the guns (Rules/BotCrew, src/server/Bots/Crew; user 2026-11-02, stage 2g). Each commander tick a
	-- free, unbroken field gun, howitzer or MG on a sector its side holds gets a gunner: the nearest defender (or an
	-- Engineer on gun duty, counted `crewFirst` studs nearer) within `walk` studs, at most `max` gunners a side. It
	-- walks there (giving up after `walkFor` s) and mans it; it fights no other way while on it, holds no post and is
	-- in no squad. A teammate taking the gun over (E) sends it back to duty, not on a gun again for `kicked` s.
	-- - Field guns and howitzers (user: "Known enemy groups, else sector"): the biggest group of the enemies its
	--   squads know (`cluster` studs across) the gun reaches, else the enemy sector its side attacks (or the one next
	--   to its front), a shot anywhere within `scatter` studs of its middle; looked at again every `retarget` s and
	--   after each shot. Fired every reload once laid, held while a teammate is within `hold` of the aim point (user:
	--   "Every reload, hold near own"; `big` for a shell of `bigKg` kg or more, the howitzer).
	-- - MGs (user: "Yes, at seen enemies"): at a target it sees within the gun's range, bursts `burst.on` s held and
	--   `burst.off` s let go; a new box once the box is empty, or under `topUp` of it with nothing to shoot at.
	Crew = {
		-- (every gun and nest its bots build manned: 4 guns and 3 nests, user 2026-11-03: "utilize cannons and mgnests
		-- more"; 7 to 5 with the trench priority, user 2026-11-04: "most fights end up being artillery")
		max = 5,
		-- its guns shell the known groups in the open first, then those within `trench` studs of an enemy dug square
		-- (Rules/BotCrew.openFirst)
		trench = 8,
		walk = 300,
		crewFirst = 60,
		walkFor = 45,
		kicked = 60,
		cluster = 20,
		scatter = 25,
		retarget = 6,
		hold = { small = 25, big = 40, bigKg = 50 },
		burst = { on = 1.2, off = 0.8 },
		topUp = 0.4,
		-- (user 2026-11-03, bots "still firing into hills"): a field gun or howitzer fires only where its shot, flown as the
		-- gun spots' are (Build.Crews `arc`), comes down on its target; a sector shot tries `tries` spots in its spread.
		-- A gunner whose every target in reach was blocked `looks` looks in a row leaves the gun, given no gunner for
		-- `wait` s.
		blind = { tries = 3, looks = 3, wait = 90 },
		-- A gun the enemy built on ground the side now holds (Rules/BotCrew.captured): looked at every `every` s; an MG
		-- nest's shot is clear when nothing stands within `sight` studs along its line toward the enemy (its sight
		-- `eye` studs over its pivot), a field gun's or howitzer's when its flown shot (low or lobbed) lands on the
		-- enemy's sector. It stands safe (Rules/BotCrew.safeSpot; user 2026-11-03: "usable and in a safe spot") with no
		-- enemy its squads know of within `safe.threat` studs and no more than `safe.ahead` studs past its sector's middle
		-- toward the enemy. Clear and safe: used, and counted against the sector's guns (Build `caps`); otherwise wrecked
		-- by Engineers (user: "Wreck them all"). Config/DevTools.Admin.Captured labels each with its verdict.
		captured = { every = 10, sight = 60, eye = 1.7, safe = { threat = 60, ahead = 30 } },
	},

	-- the server's log line (cost and how the fights go) every this many seconds while bots are on; 0 none
	ReportEvery = 15,
}

return table.freeze(Bots)
