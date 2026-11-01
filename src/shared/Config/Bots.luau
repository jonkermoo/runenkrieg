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
		{ key = "AutoRifler" },
		{ key = "Shotgunner", push = 18 },
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
