--!strict
-- The types src/server/Bots and its parts share: a bot, its nav, acts and jobs, a squad, a side's build list.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Orders = require(Shared.Rules.BotOrders)
local BotBuild = require(Shared.Rules.BotBuild)
local BotTrenches = require(Shared.Rules.BotTrenches)
local Rules = require(Shared.Rules.Bots)
local Animate = require(script.Parent.Animate)
local Squads = require(Shared.Rules.BotSquads)

export type Target = { model: Model, distance: number, visible: boolean }

export type Nav = {
	goal: Vector3?,
	waypoints: { PathWaypoint },
	index: number,
	computing: boolean,
	pathAt: number,
	sampleAt: number,
	samplePos: Vector3,
	jumps: number,
	repaths: number,
	direct: Vector3?, -- a point walked to straight, without a path (strafing, a peek, a step aside)
	doorAt: number, -- when it last opened a door on its way (it waits while the door swings)
}

-- Normal: a job on its side's build list (Rules/BotBuild): where it is now (moved by refusals), the piece once laid
-- and the Build swings it still wants (src/server/Build.worksOf, each commander tick)
export type BuildJob = {
	job: BotBuild.Job, -- (its spot moved by refusals)
	base: BotBuild.Job, -- as planned
	model: Model?,
	at: Vector3?, -- the piece's spot once laid (what it swings at)
	left: number,
	tries: number,
	treeWaits: number?, -- a trench run's waits for a tree in its way (Config/Bots.Trenches.Tree)
	waitUntil: number,
	open: boolean, -- on the list this tick
	run: BotTrenches.Run?, -- a trench run of the side's system (Rules/BotTrenches): planned, then its squares dug
	underFire: boolean?, -- worked under fire (a sap, a pile laid when pinned): only a hit stops it
	gaveUp: boolean?, -- refused at every spot it was moved to (a trench run: a breastwork goes there instead)
	done: boolean?, -- its breastwork or walls are on the list
	fix: boolean?, -- a gun of its side out of service (Rules/BotCrew.repairOrder): fixed first, wherever it stands
	why: string?, -- why it was last refused (Build.placeAs; the Engineer readout)
	from: { x: number, z: number }?, -- a trench run planned part way: where it began (its job goes on from the part's end)
	buried: boolean?, -- a trench square dug full once and buried since (pioneers dig it first, Config/Bots.Trenches.Redig)
	redig: number?, -- a buried-to-nothing square planned again where it lay: kept on the list until then (Trenches.Redig)
	lostBy: { [number]: boolean }?, -- bots (by id) that left it with no way there, no swing or flapping (Build.Work)
	sys: string?, -- a trench run's system: "S<sector>", or "S<sector>F<k>" a forward line (Config/Bots.Trenches.Forward)
}
-- a side's trench system at a sector (its runs as jobs, kept while the side holds the sector) or a forward line out from
-- it, and the middle of its fire trench (where the next line's communication trench joins it)
export type TrenchSystem = { sector: number, runs: { BuildJob }, mid: { x: number, z: number } }

-- a squad's sap forward (Rules/BotSap): its head (where the next run starts), the run being planned or dug, the jobs
-- open on it, its squares' jobs by model
export type Sap = {
	k: number,
	head: Vector3,
	goal: Vector3, -- its objective
	run: BuildJob?,
	open: { BuildJob },
	digs: { [Model]: BuildJob },
	angle: number?, -- the turn its runs take now: 0 while safe, a zig-zag's against a threat (Config/Bots.Trenches.Zigzag)
	parallel: boolean?, -- its last run the parallel across (Config/Bots.Front): dug, it is over and the squad goes over
	dugAt: number, -- when it began, or its last run was dug (Config/Bots.Sap.dig)
	began: number?, -- when it began (Config/Bots.Sap.maxSeconds)
}
export type TrenchSquare = { x: number, z: number, at: Vector3, model: Model, left: number, built: boolean }

-- Normal: what a bot does instead of fighting for a while (Rules/BotActions): a drag of `who` to `to` (cover from the
-- enemy spot `from`), a heal of `who`, a grenade at `at`
export type Act = {
	kind: string, -- "Drag", "Heal", "Throw" or "Build"
	who: Model?,
	at: Vector3?,
	from: Vector3?,
	to: Vector3?,
	started: number,
	phase: string?, -- the drag's "pull", the heal's "heal", the throw's "throw" and "done"
	job: BuildJob?, -- a build's job
	swingAt: number?, -- a build's next swing
	swingOn: Instance?, -- what that swing is at (another: its first lands at the swing's strike)
}

export type Bot = {
	id: number,
	name: string,
	kit: string,
	weapon: string,
	push: number?,
	m: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	head: BasePart?,
	tool: Tool?,
	anim: Animate.Handle?,
	turn: AlignOrientation?,
	brain: Rules.Brain,
	nextThink: number,
	nextSense: number,
	target: Target?,
	lastSeenAt: Vector3?,
	sightAt: number, -- when its last look's ray found its target
	enemyNear: number, -- studs to the nearest enemy at its last look, seen or not (Config/Bots.Calm)
	sight: string?, -- the admin label's "sees", "remembers", "calm" or "alert" (Rules/Bots.sightWord)
	blockedAt: Vector3?, -- a covering-fire spot whose line was blocked, and until when it is let be (Config/Bots.Sight)
	blockedUntil: number,
	lastOpen: Vector3?, -- where it stood when it last saw its target (a peek goes back there)
	spotted: boolean,
	hurtAt: number?,
	threatAt: number?,
	danger: boolean?, -- Normal: it knows there's danger (Rules/BotTrenches.danger): its paths keep to trenches
	threatFrom: Vector3?, -- the threat's eye (a near miss's muzzle, or the enemy who spotted it)
	cover: Vector3?,
	coverFrom: Vector3?, -- where the threat was when the cover was found
	coverAt: number,
	nav: Nav,
	flank: Vector3?,
	wanderAt: number,
	wander: Vector3?,
	strafeAt: number,
	spawnedAt: number,
	reachedZone: boolean,
	deadAt: number?,
	respawnAt: number?,
	retiring: boolean?, -- over the count: leaves at its death instead of coming back (Config/Bots.RetiringAttribute)
	spawning: boolean, -- a body being built (it yields): never two at once
	mode: string, -- the mode it plays (a bot of another mode leaves)
	side: string?, -- Normal: "West" / "East"
	order: Orders.Order?, -- Normal: its commander's order
	sector: number?, -- Normal: the sector of its order (Config/Maps/Map1.sectors)
	stand: Vector3?, -- Normal: where it stands in that sector's zone
	coverJob: CoverJob?, -- a cover search under way (one ring a think)
	squad: string?, -- Normal: its squad's key
	role: Squads.Role?, -- Normal: its role in the squad
	goal: Vector3?, -- Normal: where its role sends it (a route point, a bound's stop, a hold spot)
	stop: Vector3?, -- Normal: a bound's next stop
	post: Vector3?, -- Normal: where it holds (its covering-fire spot, or its hold spot in the zone)
	postSector: number?, -- the sector its hold spot is in
	-- the admin panel's walk through a house (Bots.dev "House"): its spots in turn, then back out where it started
	devHouse: { spots: { Vector3 }, i: number, from: number, till: number, house: string }?,
	postFace: Vector3?, -- its hold spot is a window or doorway facing this way out (src/server/Indoors)
	roleWas: Squads.Role?,
	grip: Motor6D?, -- the gun's hold joint (to the torso)
	stowed: boolean, -- its gun put away (standing in the wave line)
	shaken: number, -- its suppression level at its last hit (Rules/Suppression)
	shakenAt: number, -- when that was
	thinkHz: number, -- how often it thinks and looks now (Rules/Bots.lod)
	senseHz: number,
	lod: string, -- "near", "middle" or "distant" (the report)
	nearest: number, -- studs to the nearest player at its last think (callouts)
	act: Act?, -- Normal: a drag, a heal or a grenade under way
	-- Normal: a build job it took, walked to with the gun out (Config/Bots.Build.Work): where it works from, when it took
	-- it, whether it works under fire (a sapper); and how it stands with it ("going", "waiting" there until safe,
	-- "working")
	-- (`best`, `bestAt`: nearest it has got on its way and when, Rules/BotBuild.stalled)
	work: { job: BuildJob, at: Vector3, since: number, brave: boolean, best: number?, bestAt: number }?,
	workState: string?,
	skipJobs: { [BuildJob]: number }?, -- jobs it was refused at, left to others until then (Config/Bots.Build.Work.skip)
	-- its build job as the admin panel's job readout shows it (Config/DevTools.Admin.BotJobsAttribute): since when, the
	-- last swing that landed, how often it began and broke off work there, the swings landed and the last why it stopped
	-- (kept while it takes the same job again)
	-- (`flaps`: begun and broken off within Work.flapWithin s, Config/Bots.Build.Work; a fresh note once not held for
	-- Work.keep s)
	jobNote: {
		job: BuildJob,
		since: number,
		landed: number,
		heldAt: number, -- (last think it held it)
		starts: number,
		stops: number,
		swings: number,
		flaps: number,
		why: string,
	}?,
	-- the idle watchdog (Config/Bots.Move.Idle): where it last moved from and when; and the walk it was sent on after a
	-- reset (its stand point or zone) until then
	idleAt: Vector3?,
	idleSince: number?,
	unstick: { to: Vector3, untilAt: number }?,
	-- Normal: a downed or hurt teammate it guards, gun out, until it may drag or heal them (Config/Bots.Actions.Guard)
	guard: { who: Model, since: number }?,
	buildWhy: string?, -- Normal, an Engineer: its build job's key, or why it has none (the admin panel's readout)
	actAt: number, -- when it next weighs one (Config/Bots.Actions.every)
	grenades: Tool?, -- a Grenadier's grenades, out of its hands until a throw
	threwAt: number,
	away: boolean, -- its gun put away for an action
	slung: Model?, -- its gun's copy on the pack's strap while the gun is out of its hands (Armory.stowed)
	shovel: Tool?, -- its shovel, out of its hands until it builds
	cast: Cast?, -- a Mage's circle open
	digger: boolean?, -- Normal: one of its holding squad's diggers (Config/Bots.Trenches.share)
	pioneer: boolean?, -- Normal: on its side's trench duty (Config/Bots.Trenches.pioneers)
	crew: boolean?, -- Normal: an Engineer on gun duty this life (Config/Bots.Build.Crews): gun jobs first
	dugouts: boolean?, -- Normal: an Engineer on dugout duty this life (Config/Bots.Dugouts.engineers): dugout jobs first
	sapper: boolean?, -- Normal: one of its squad's sappers (Config/Bots.Sap.share)
	pileAt: number?, -- when it last laid a sandbag pile pinned down (Config/Bots.Build.Pinned)
	meleeAt: number?, -- when it may next weigh a butt stroke (Config/Bots.Melee.every)
	postFloor: Vector3?, -- its post is a fire step: the trench floor below it (its cover)
	postKind: string?, -- "step", "reserve" (the support line), "dugout" (sheltering), "window" or "open"
	postFoot: Vector3?, -- its dugout's foot (where the steps start): walked straight down from there, and up to it
	dugSince: number?, -- when it went down into its dugout (Config/Bots.Dugouts.Heat.stay)
	dugRest: number?, -- up to fight till then, after a stay (Dugouts.Heat.rest)
	gun: Model?, -- Normal: the gun its commander gave it (src/server/Bots/Crew): it walks there, mans and fires it
	gunWait: number?, -- not given a gun again before this (taken over by a teammate, or gave up the walk)
}

export type CoverJob = { threat: Vector3, ring: number, here: number }

-- a Mage bot's open circle (src/server/StaffCast): the stage it is charging for, where at (a seen target's aim point,
-- or a known enemy's cover), and when the target was last seen
export type Cast = { stage: number, openedAt: number, seenAt: number, at: Vector3, visible: boolean }

-- Normal squads by key (Rules/BotSquads), kept tick to tick: the phase, its lane and route, what its members saw
export type Known = { model: Model?, pos: Vector3, at: number } -- (no model: a shot heard, its source guessed)
export type SquadState = {
	sq: Squads.Squad,
	side: string,
	sector: number,
	lane: number,
	approach: Vector3?,
	mid: Vector3?,
	known: { Known },
	seen: number, -- the commander's tick it was last formed (gone ones are dropped)
	threwAt: number?, -- its last grenade (Config/Bots.Actions.Grenade.squadEvery)
	push: Vector3?, -- pushing a group of enemies it can take (Config/Bots.Squads.Push): their middle
	bomb: Vector3?, -- the group its Grenadier throws at first, until `bombAt` + Push.bombFor
	bombAt: number?,
	clear: Vector3?, -- pushing in: the indoor spot by a known enemy inside a building (its Assault bots go there)
	markAt: number?, -- when it last gained Config/Bots.Sap.progress studs toward its objective, and how far it was
	markDist: number?,
	firedAt: number?, -- when one of its members was last shot at
	sap: Sap?, -- sapping forward (stuck under fire)
	jump: Vector3?, -- attacking: its jump-off trench square's floor (Rules/BotTrenches.jumpOff), gathered in first
	jumpAlong: Vector3?, -- along that square
	jumpAt: number?, -- when the first of it got there
	devPush: { at: Vector3, till: number }?, -- the admin panel's push at a point (Bots.dev "Push"), until `till`
	midAt: number?, -- when the first of its free members reached its waypoint, and its approach spot (Squads.waitMax)
	readyAt: number?,
	flank: number?, -- attacking up a flank (-1 or 1, Config/Bots.Front.Flank): its route by a point off to that side
	noSapUntil: number?, -- a sap given up: none again until then (Config/Bots.Sap.rest)
	stillMid: Vector3?, -- where its middle was when it last moved Squads.Open.moved studs, and when
	stillAt: number?,
	inCover: number?, -- its members in cover at the last commander tick
	pressUntil: number?, -- pinned in the open (Rules/BotSquads.pinned), or a sap given up: pressing on until then
	cut: Vector3?, -- exploiting an offensive: the defenders' approach spot it stands on (Config/Bots.Offensive)
}
-- Normal: each side's build list at its front (Rules/BotBuild), kept each commander tick: the lay jobs (planned again
-- when the front or the side's sectors held change, which sets the guns it may build, or once the hold spots are
-- found), each matched to its piece once laid, and the own pieces near the front wanting swings; `open` the jobs a bot
-- may take now
export type TrenchPost = { pos: Vector3, floor: Vector3?, face: Vector3? }
export type SideBuild = {
	front: number?,
	held: number, -- its sectors held from its end when planned (Rules/Frontline.held)
	holds: boolean,
	lay: { BuildJob },
	works: { [Model]: BuildJob },
	open: { BuildJob },
	-- its trenches at the front (Rules/BotTrenches): fire steps on the dug fire trench, places in the support line,
	-- every dug square (where attackers clear: the enemy's list), whether the support line stands to, until when the
	-- holders fall back from a lost fire trench
	steps: { TrenchPost },
	reserve: { TrenchPost },
	squares: { { x: number, z: number, at: Vector3 } },
	standTo: boolean,
	fallbackUntil: number,
	trench: { TrenchSquare }, -- every own trench square, dug or not (saps)
	lines: { BotTrenches.Run }, -- trench lines its bots lay no piece on: every square's, its runs', its saps'
	guns: number, -- the side's guns standing (anyone's; Config/Bots.Build.Crews)
	-- its dugouts (Config/Bots.Dugouts): the rooms that shelter (the middle of each floor), whether its trenches are
	-- shelled now and have been at this front, its fire bays with a step (one sentry each)
	rooms: { { x: number, z: number, room: Vector3, foot: Vector3, model: Model } },
	enemies: { { x: number, z: number } }, -- the enemies its squads know of now (Dugouts.Heat)
	shelled: boolean,
	shelledOnce: boolean,
	bays: number,
	digging: number, -- its dugouts wanted not yet stood (laid or not)
	hurt: { [Model]: { hp: number, at: number } }, -- its works' HP last tick and when each last lost any (repairWait)
	-- its runs toward the enemy lately, each straight or a zig-zag and why (Config/Bots.Trenches.Zigzag; the newest last)
	runNotes: { string },
	gunNote: string?, -- why each gun is or isn't on its list (locked, its spots, or why none fit; the Engineer readout)
	inFront: { [string]: number }?, -- its guns and MG nests in its front sector by key, captured ones it uses counted
	systems: { [string]: TrenchSystem }, -- its trench systems by key (BuildJob.sys)
	-- its squares dug full, each one's line (BlockA, BlockB), and those buried to nothing to plan again where they lay
	-- (Config/Bots.Trenches.Redig)
	had: { [Model]: { a: Vector3, b: Vector3 } }?,
	redigs: { BuildJob }?,
}
-- every soldier alive this frame, gathered once for all the bots' sight (entries reused frame to frame)
export type Soldier = {
	model: Model,
	part: BasePart,
	kit: any,
	pos: Vector3,
	look: Vector3,
	health: number,
	down: boolean,
}
-- paths found lately, shared: a bot going near the same place from near a waypoint of one follows it from there
-- (Config/Bots.Move.Share) instead of asking for its own
export type SharedPath = { goal: Vector3, waypoints: { PathWaypoint }, at: number, danger: boolean }
-- the bot's gun or staff for its brain: rounds and the action (a staff: its mana for rounds; empty or burnt out it
-- refills, as a reload)
export type Arms = {
	magazine: number,
	chambered: boolean,
	spent: boolean,
	busy: boolean,
	loading: boolean,
	capacity: number,
	auto: boolean,
}

return {}
