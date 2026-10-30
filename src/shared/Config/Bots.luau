--!strict
-- Bot soldiers that fill empty places when too few players are on (src/server/Bots, Rules/Bots; stage 1, 2026-10-30:
-- rifles only, the FFA zone match). They are soldiers like the players' (a kit, its bolt or semi rifle, the same
-- Firing / Damage rules), steered by a small state machine.
local Bots = {
	Enabled = true,
	-- on Workspace: a number pins how many bots there are (testing; 0 none), over the fill below
	Attribute = "Bots",
	-- on Workspace: a Difficulty key below, over Default (testing)
	DifficultyAttribute = "BotDifficulty",
	Tag = "Bot", -- every bot's model (they also carry Config/DevTools.Dummies.Tag: hurt, healed, dragged like soldiers)
	Folder = "Bots", -- in Workspace
	-- on each bot's model: a negative number standing in for a UserId (src/server/ZoneMatch: it holds and contests the
	-- zone, user 2026-10-30, but never scores, leads or wins)
	IdAttribute = "BotId",
	-- soldiers each mode is topped up to: players first, bots for the rest (Rules/Bots.wanted); modes not listed get none
	Fill = {
		FFA = { total = 8 },
	},
	-- the most bots one server runs, whatever the fill (the server's budget; Stage 1 measured 10 and 20)
	Max = 20,
	-- one bot in (or out) at most this often, so a join or a leave never brings a crowd at once
	JoinEvery = 1.5,
	LeaveEvery = 4,
	-- a bot over the count leaves only while dead, or after this long over it (seconds) even alive
	LeaveAliveAfter = 20,

	Think = 10, -- brain steps a second, per bot (staggered)
	Sense = 4, -- sight checks a second, per bot: the nearest few enemies' line-of-sight rays
	SenseNearest = 3, -- how many of the nearest enemies in range and view get a ray
	Eye = 1.5, -- studs over the root: where a bot looks from (the head)
	SemiShare = 0.3, -- share of lives a bot carries its kit's semi rifle instead of the bolt rifle
	Direct = 0.5, -- seconds between the director's counts
	-- turning to the target while aiming (an AlignOrientation on the root)
	Turn = { responsiveness = 25, torque = 1e6 },
	FacingWithin = 20, -- degrees: it fires only when its body faces the target this closely
	PitchLimit = 60, -- degrees the look pitch sent to clients stays within
	Lag = 0.5, -- share of the reaction time its aim lags a moving target by (the difficulty's lead makes up part)

	Move = {
		Repath = 6, -- seconds between path recomputes toward the same goal
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
		-- while engaging: a sidestep left or right now and then (seconds between, studs)
		StrafeEvery = { 1.5, 3.5 },
		Strafe = 5,
		-- a bot closer than this to its target keeps moving while it shoots (strafing); farther it stands and aims
		CloseRange = 25,
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
