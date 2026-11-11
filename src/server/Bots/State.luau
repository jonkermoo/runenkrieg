--!strict
-- What src/server/Bots and its parts share: every bot, the report's counters, each side's squads and build list, the
-- frame's budget, and the tables of trench clearing, trench moving and tactics with their small helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local IndoorCfg = require(Shared.Config.Indoors)
local BuildCfg = require(Shared.Config.Build)
local BotBuild = require(Shared.Rules.BotBuild)
local BotTrenches = require(Shared.Rules.BotTrenches)
local BotTrenchCare = require(Shared.Rules.BotTrenchCare)
local BotOrders = require(Shared.Rules.BotOrders)
local BotArcs = require(Shared.Rules.BotArcs)
local Build = require(script.Parent.Parent.Build)

local TR = Cfg.Trenches
local TM = Cfg.TrenchMove

local Types = require(script.Parent.Types)
type Bot = Types.Bot
type SquadState = Types.SquadState
type SideBuild = Types.SideBuild

-- Normal: keeping trench lines clear (Rules/BotTrenches.clearOf), in one table:
-- - keep: how far a piece keeps off a trench line, its wall top (Rules/Build.trenchTop) and Trenches.clear
-- - half: each piece's own half diagonal (Config/Build.Pieces), kept off on top
-- - inside: the pieces part of a trench, never in a run's way
-- - every: every piece and trench square, all teams' (Build.worksOf), as of commander tick `everyAt`
local Clear = {
	keep = require(Shared.Rules.Build).trenchTop(BuildCfg.Trench) + TR.clear,
	half = {} :: { [string]: number },
	inside = { Trench = true, Bridge = true, Dugout = true },
	every = {} :: { Build.Work },
	everyAt = -1,
}
for _, p in BuildCfg.Pieces do
	local w, d = (p :: any).width, (p :: any).depth
	if type(w) == "number" and type(d) == "number" then
		Clear.half[p.key] = math.sqrt(w * w + d * d) / 2
	end
end

local bots: { Bot } = {}
-- each bot's own Path object, made once (CreatePath on every request cost a frame now and then)
local pathOf: { [number]: Path } = {}

-- Normal: moving by trench (Config/Bots.TrenchMove), in one table:
-- - costs: knowing there's danger, the open ground `open` times dearer than a trench square's hole
-- - paths: each bot's Path with them
-- - blasts: shells and grenades lately (Damage.onBlast), danger near them for TrenchMove.blast seconds
-- - counts: the soldiers of each side in each sector's zone (the commander's last tick)
-- - marks: each trench square's pathfinding mark (ByTrench.mark), in `folder`
local ByTrench = {
	costs = table.clone(IndoorCfg.PathCosts) :: { [string]: number },
	paths = {} :: { [number]: Path },
	blasts = {} :: { { x: number, z: number, at: number, kg: number } },
	counts = {} :: { { West: number, East: number } },
	marks = {} :: { [Model]: BasePart },
	folder = nil :: Folder?,
	top = require(Shared.Rules.Build).trenchTop(BuildCfg.Trench), -- (a square's half width at its wall tops)
	-- each side's bots' deaths this match: all, in a trench square, by a shell, in a sector's capture zone (Config/Bots.Trenches.Stats; the admin
	-- trench stats)
	deaths = {} :: { [string]: { all: number, trench: number, shell: number, zone: number, mg: number } },
	-- each side's trench run plans this match, by "<side> <what>": laid, refused (and by Trenches.plan's reason),
	-- chained (started at the real free end of the run before, Config/Bots.Trenches.Chain), redug (buried squares
	-- planned again); the admin trench stats
	runs = {} :: { [string]: number },
	-- how long each side's lost trench squares stood, seconds (dug to buried under Trenches.standHp or gone; Care)
	lives = {} :: { [string]: { number } },
	-- each side's bot-seconds seeing an enemy: from the open, from cover (a cover point reached, a trench square, its
	-- fire step, a foxhole, a building's spot), and in the open within Dugouts.near of a fresh shell (the trench stats'
	-- exposure line; Config/Bots.Brain.SeenSpots)
	exposure = {} :: { [string]: { open: number, covered: number, shelledOpen: number } },
	-- each side's samples of what its bots are doing (one per bot per commander tick; the admin panel's "What bots are
	-- doing"), and bot-seconds with an enemy in sight by what the gun did
	activity = {} :: { [string]: { [string]: number } },
	inSight = {} :: { [string]: { [string]: number } },
	idleWhy = {} :: { [string]: { [string]: number } }, -- its samples of idle bots, by why
	-- each side's samples of its living bots on hold: all, within OffPoint.clear of a flag, in a zone
	holders = {} :: { [string]: { all: number, flag: number, zone: number } },
	-- each side's samples of its living bots by where they stand (Rules/BotBuild.whereIs: front, behind, ahead) and,
	-- behind its front, what they do there (the marked spots readout; user 2026-11-09: "too many people are at the old
	-- sectors")
	where = {} :: { [string]: { [string]: number } },
	behindWhy = {} :: { [string]: { [string]: number } },
	-- how near each side's living bots stood to their nearest teammate this match, by role (Report's spot readout;
	-- user 2026-11-10: "when they are in groups, they are super close together"): samples, under 4 / 8 studs
	gaps = {} :: { [string]: { [string]: { n: number, under4: number, under8: number } } },
	-- how far across from the line through the sector flags each side's living bots stood this match (Report's spot
	-- readout, Rules/BotLanes.fromLine; user 2026-11-10: "still too many are just in the center"): samples in each band
	-- of Report's `acrossBands`; and each side's lanes now (Config/Bots.Lanes: squads in each lane against its share)
	across = {} :: { [string]: { number } },
	lanesNow = {} :: { [string]: { [string]: string } },
	-- each side's players' planned squares dug this match: seconds from first listed to dug (Config/Bots.Trenches.Plans)
	planTimes = {} :: { [string]: { number } },
}
for _, name in TM.materials do
	ByTrench.costs[name] = TM.open
end
ByTrench.costs[TM.label] = 1

-- Normal: fighting together and up close, in one table: the butt stroke
-- (src/server/Melee.strikeAs, Config/Melee: its reach)
local Tactics = {
	melee = require(script.Parent.Parent.Melee),
	meleeCfg = require(Shared.Config.Melee),
	crew = require(script.Parent.Crew), -- (bots on the guns: Config/Bots.Crew)
	fell = require(script.Parent.Fell), -- (trees in the way of the works: Config/Bots.Build.Trees)
	-- the admin panel's bot tests (Bots.dev, Tactics.label): whether the labels are up, their text (Rules/DevActions)
	dev = { labelled = false, rules = require(Shared.Rules.DevActions) },
}

-- Normal: dugouts and foxholes (Config/Bots.Dugouts), in Tactics:
-- - holes: the foxholes its bots dug, the newest Dugouts.Fox.keep (a dug foxhole is only terrain: Build lists it no
--   more), each its middle and its floor
-- - tried: when each bot last tried to dig one at its hold post (a refused spot isn't tried again at once)
-- - heat: the shells and own deaths lately (Rules/BotTrenches.heat; Config/Bots.Dugouts.Heat.keep seconds of them)
-- - use: each dugout's holders gone down into it this match, and why the last one went (the admin readout)
Tactics.dug = {
	holes = {} :: { { x: number, z: number, floor: Vector3 } },
	tried = {} :: { [number]: number },
	heat = {} :: { BotTrenches.HeatEvent },
	use = {} :: { [Model]: { count: number, why: string, who: string } },
	-- the shell map (Rules/BotTrenchCare; Config/Bots.Trenches.Care.Map): the shells' over the whole match, and each
	-- side's own deaths'
	map = { shell = {}, West = {}, East = {} } :: { [string]: BotTrenchCare.ShellMap },
}
-- a shell or an own death remembered for the trenches' heat, and on the shell map; the old ones forgotten
function Tactics.dug.note(kind: string, x: number, z: number, now: number, side: string?)
	local H = Cfg.Dugouts.Heat
	local list = Tactics.dug.heat
	table.insert(list, { x = x, z = z, at = now, kind = kind, side = side })
	while #list > 0 and now - list[1].at > H.keep do
		table.remove(list, 1)
	end
	local M = Cfg.Trenches.Care.Map
	local map = Tactics.dug.map[if kind == "shell" then "shell" else side or ""]
	if map then
		BotTrenchCare.note(map, x, z, if kind == "shell" then M.shell else M.death, now, M)
	end
end
-- how hot the ground at (x, z) is for `side` on the shell map: the shells' and its own deaths'
function Tactics.dug.mapHeat(side: string, x: number, z: number, now: number): number
	local M = Cfg.Trenches.Care.Map
	local maps = Tactics.dug.map
	return BotTrenchCare.heatAt(maps.shell, x, z, now, M) + BotTrenchCare.heatAt(maps[side] or {}, x, z, now, M)
end
-- a dugout's foot: where its steps start, on the trench floor at the foot of its wall (where a bot swings at it), from
-- its "Frame" (the middle of its steps and room, +Z back into the wall) and "Size"
function Tactics.dug.foot(model: Model): Vector3?
	local frame, size = model:GetAttribute("Frame"), model:GetAttribute("Size")
	if typeof(frame) == "CFrame" and typeof(size) == "Vector3" then
		return (frame * CFrame.new(0, 0, -size.Z / 2)).Position
	end
	return nil
end
-- the dugout (any side's, as of the last commander tick: Clear.every) whose steps or room `p` (a root) is down in:
-- lower than one standing on the trench floor at its foot (its root 3 up; a root on the top steps is about -1, 2026-11-04
-- test), over its room's floor (`drop` under the trench floor), inside its "Frame" box along and across (the frame is at
-- the trench floor's height, so its own height box misses a bot standing in the room); with its foot; nil outside
local dugCache: { at: number, list: { Model } } = { at = -2, list = {} }
function Tactics.dug.inside(p: Vector3): (Model?, Vector3?)
	if dugCache.at ~= Clear.everyAt then
		dugCache.at, dugCache.list = Clear.everyAt, {}
		for _, w in Clear.every do
			if w.key == "Dugout" then
				table.insert(dugCache.list, w.model)
			end
		end
	end
	for _, m in dugCache.list do
		local foot = m.Parent and Tactics.dug.foot(m)
		local frame, size = m:GetAttribute("Frame"), m:GetAttribute("Size")
		if
			foot
			and typeof(frame) == "CFrame"
			and typeof(size) == "Vector3"
			and p.Y < foot.Y + 1
			and p.Y > foot.Y - BuildCfg.Dugout.drop - 1
		then
			local o = frame:PointToObjectSpace(p)
			if math.abs(o.X) <= size.X / 2 and math.abs(o.Z) <= size.Z / 2 then
				return m, foot
			end
		end
	end
	return nil, nil
end
-- `team`'s works (Build.worksOf, its swings a `class` builder's) with a dugout's `at` its foot; and each dugout's room
-- (the middle of its floor)
function Tactics.dug.works(team: string?, class: string?): ({ Build.Work }, { [Model]: Vector3 })
	local works = Build.worksOf(team, class)
	local rooms: { [Model]: Vector3 } = {}
	for _, w in works do
		if w.key == "Dugout" then
			rooms[w.model] = w.at
			w.at = Tactics.dug.foot(w.model) or w.at
		end
	end
	return works, rooms
end
-- whether `room` is one of `sb`'s dugouts that shelter still
function Tactics.dug.standing(sb: SideBuild, room: Vector3?): boolean
	for _, rm in sb.rooms do
		if rm.room == room then
			return true
		end
	end
	return false
end
-- a foxhole a bot dug, its spot's middle `at`: remembered (the newest Fox.keep)
function Tactics.dug.dug(at: Vector3): Vector3
	local floor = at - Vector3.yAxis * BuildCfg.Foxhole.depth
	table.insert(Tactics.dug.holes, { x = at.X, z = at.Z, floor = floor })
	if #Tactics.dug.holes > Cfg.Dugouts.Fox.keep then
		table.remove(Tactics.dug.holes, 1)
	end
	return floor
end
local random = Random.new()

-- the report's counters since its last line
local stats = {
	thinkTime = 0,
	thinkMax = 0,
	thinks = 0,
	frameMax = 0,
	rays = 0,
	paths = 0,
	pathFails = 0,
	stuck = 0,
	sidesteps = 0,
	roundHouse = 0, -- walks round a building in the way, with no path or stuck (Config/Bots.Move.Round)
	shots = 0,
	deaths = 0,
	toZone = 0,
	toZoneCount = 0,
	covers = 0,
	peeks = 0,
	upgrades = 0,
	frames = 0,
	frameTime = 0,
	frameSamples = {} :: { number },
	deferred = 0, -- frames that ran out of time with bots still due
	senseDeferred = 0, -- sight checks put off a frame for want of rays
	pathsDeferred = 0, -- path computes put off for want of the server's ration
	pathsShared = 0, -- paths taken from another bot's
	reowned = 0, -- bodies whose physics a player had taken, given back to the server
	callouts = 0, -- lines said
	throws = 0, -- grenades thrown
	heals = 0, -- heals started
	drags = 0, -- drags started
	doors = 0, -- doors opened on the way
	stairSteps = 0, -- thinks a bot walked a flight's middle line, not straight from its link's end (Indoors.stairWay)
	doorsBumped = 0, -- shut doors a stuck bot opened in front of it (no door link on its path)
	arrivals = 0, -- waypoints reached between thinks and walked on from at once (Move.arrived)
	doorRepaths = 0, -- bots that pathed again after a door near them swung open or shut
	laid = 0, -- pieces laid and trenches planned
	swings = 0, -- Build swings that landed
	refused = 0, -- lays refused (the spot moved)
	keptOff = 0, -- lays moved off a trench line
	torn = 0, -- Destroy swings at pieces in a trench run's way
	around = 0, -- trench runs swung aside round a piece in their way
	casts1 = 0, -- staff shots by stage
	casts2 = 0,
	casts3 = 0,
	dropped = 0, -- circles closed without a shot
	runs = 0, -- trench runs planned
	pinnedPiles = 0, -- sandbag piles laid pinned down in the open
	breastworks = 0, -- breastworks put on the list where a trench run was refused
	pioneers = 0, -- bots put on trench duty (Config/Bots.Trenches.pioneers)
	forward = 0, -- forward lines planned (Config/Bots.Trenches.Forward)
	laneLines = 0, -- lane lines planned across the field (Config/Bots.Trenches.Lanes)
	laneJoins = 0, -- runs joining two lane lines end to end
	taken = 0, -- fire steps on enemy trench squares taken over (Config/Bots.Trenches.takeOver), each tick
	partRuns = 0, -- trench runs planned part way, the rest from there (Config/Bots.Trenches.Tree)
	walls = 0, -- walls put on the list round nests and guns
	saps = 0, -- squads that began to sap forward
	sapRuns = 0, -- sap runs dug
	sapsFailed = 0, -- saps given up (refused, through water, or none dug in Sap.dig s)
	sapsDue = 0, -- saps ended at their deadline or as their side's offensive moved on (Config/Bots.Sap)
	sapFords = 0, -- saps ended at, or bent to, a ford instead of across water
	restarts = 0, -- Assault squads stuck out of the zone that found their way again (Config/Bots.Offensive.stuckFor)
	fellBack = 0, -- squads gone in that fell back to re-form (Offensive.Roll)
	pressed = 0, -- squads pinned in the open that pressed on (Squads.Open)
	dangerPaths = 0, -- paths asked for knowing there's danger (kept to trenches)
	intoTrench = 0, -- shot at in the open, down into a trench nearby
	overTop = 0, -- squads over the top from their jump-off trench
	dugouts = 0, -- dugouts put on the build list
	dugoutsRefused = 0, -- support-line squares left out of the dugout list: no ground round a room (Build.dugoutFor)
	sheltered = 0, -- holders down into a dugout under shelling
	cameUp = 0, -- holders up from a dugout to their posts
	dugLifted = 0, -- bots jammed down in a dugout they weren't sheltering in, lifted out (Config/Bots.Dugouts.Free)
	bombed = 0, -- grenades down an enemy dugout's steps
	holes = 0, -- foxholes dug
	pinnedHoles = 0, -- foxholes begun pinned down in the open
	exposedHoles = 0, -- foxholes begun seen from the open with no cover near (Config/Bots.Build.Exposed)
	intoHole = 0, -- shot at in the open, down into a foxhole nearby
	lost = 0, -- fire trenches lost (the holders fell back)
	covering = 0, -- shots of covering fire
	blocked = 0, -- shots held: the muzzle's line to the aim point blocked (Config/Bots.Sight)
	strikes = 0, -- butt strokes that went (Config/Bots.Melee)
	zigzags = 0, -- runs toward the enemy dug as a zig-zag, in a threat's line of fire (Config/Bots.Trenches.Zigzag)
	straights = 0, -- and straight, out of it
	selfHits = 0, -- staff casts held: the beam would hit something right by the caster (its own cover; Staff.ownWithin)
	laneMoves = 0, -- squads moved over to a lane that needed them more (Config/Bots.Lanes.every)
	movedOn = 0, -- squads that moved on from a waypoint without waiting for members off on jobs (Squads.waitMax)
	contacts = 0, -- sides that had their first contact (Config/Bots.Front: from then on by trench)
	parallels = 0, -- parallels planned across close to an objective (Config/Bots.Front)
	workTaken = 0, -- build jobs taken, walked to with the gun out (Config/Bots.Build.Work)
	workStarted = 0, -- tools out there, once safe
	workStopped = 0, -- tools dropped for the gun mid-work (danger)
	workStalled = 0, -- jobs left on the way, no nearer for Work.stall s (no way there)
	workNoSwing = 0, -- jobs left with no swing landed for Work.noSwing s
	workFlapped = 0, -- jobs left after Work.flapMax starts broken off at once
	workOutOfReach = 0, -- jobs Work.giveUpAfter bots left: refused for their side (moved or dropped)
	idleResets = 0, -- bots standing still off their post reset by the idle watchdog (Config/Bots.Move.Idle)
	-- wait spots taken instead of milling (Config/Bots.Move.Wait): in a trench (step, support line, square), at a hidden
	-- spot, a step away from the crowd, where it stood
	waitTrench = 0,
	waitCover = 0,
	waitSpread = 0,
	waitHere = 0,
	guarded = 0, -- teammates guarded, gun out, before a drag or heal (Config/Bots.Actions.Guard)
	rescues = 0, -- casualties claimed by one rescuer (Config/Bots.Actions.Rescue)
	rescuesLet = 0, -- claims let go (the rescuer dead or pulled away)
	pushes = 0, -- squads that pushed a group they outnumber (Config/Bots.Squads.Push)
	pushBombs = 0, -- grenades thrown to open such a push
	wireMoved = 0, -- wire spots moved off (or dropped from) its own side's ways (Config/Bots.Build.Wire)
	waited = 0, -- swings put off at pieces that lost HP lately (Config/Bots.Build.repairWait)
	spread = 0, -- path steps pushed aside off a teammate walking too close (Config/Bots.Spread)
	assaults = 0, -- squads that pushed into a zone
	stoodUp = 0, -- bodies found lying after a knock, stood up
	since = os.clock(),
}

-- one rescuer a casualty (Config/Bots.Actions.Rescue): who rescues each and since when; when a claim was let go
local rescue = {
	claims = {} :: { [Model]: { by: Bot, at: number } },
	freed = {} :: { [Model]: number },
}
local squads: { [string]: SquadState } = {}

local buildLists: { [string]: SideBuild } = {}

-- Normal: how each side fights forward (Rules/BotFront, Config/Bots.Front): when it first had contact, the admin
-- panel's plan for it, its plan now; and the sectors' owners at the commander's last look (a capture is contact).
-- The initiative (Config/Bots.Offensive): the side holding it (nil: the race at the start), each side's offensive and
-- its line for the readouts (`note`), its attack squads' members at their jump-off last tick (`gathered` of
-- `attackers`), when it lost each sector, the enemy strongpoints it knows (gun or nest model: where, when last known),
-- and the match's tallies (`tally`: offensives begun, gone, spent, captured, per side; Assault squads restarted).
local fronts = {
	sides = {} :: {
		[string]: {
			contactAt: number?,
			forced: string?,
			plan: string,
			off: BotOrders.Offensive?,
			note: string?,
			gathered: number?,
			attackers: number?,
			dueDists: { number }?, -- its attack squads' studs to their jump-offs this look (Offensive.pace)
			assaulting: number?, -- its offensive's squads in the Assault phase this look (the Bots' attacks readout)
		},
	},
	owners = nil :: { string }?,
	initiative = nil :: string?,
	lostAt = {} :: { [string]: { [number]: number } },
	strong = {} :: { [string]: { [Model]: { at: Vector3, seen: number, mg: boolean? } } },
	-- the enemy MGs' arcs each side has felt (Config/Bots.Crew.Arcs), its tallies this match for the Bots' MGs readout,
	-- and where it reckons the enemy is likely to be (Config/Bots.Crew.MG)
	arcs = {} :: { [string]: { [Model]: BotArcs.Arc } },
	mg = {} :: { [string]: { pinned: number, far: number, detours: number, walked: number } },
	mgLikely = {} :: { [string]: { at: number, list: { Vector3 } } },
	tally = {} :: { [string]: number },
	took = {} :: { [string]: { sector: number, at: number } }, -- the sector each side took last, and when
	summary = nil :: string?, -- the [Bots] line's offensives part
	-- each side's offensives this match, for the admin panel's Bots' attacks readout (Config/DevTools.Admin.BotAttacks):
	-- how many went, seconds to Go and gather fill (summed), where they formed up (studs off the zone's edge, summed over
	-- `gatherN` squads), waves and squads sent, the longest time with no squad attacking (`maxQuiet` with the initiative,
	-- `goQuiet` from Go), the most attackers within reach of one blast, blasts catching 3 or more, sectors lost gathering
	attacks = {} :: {
		[string]: {
			goes: number,
			toGo: number,
			fill: number,
			gatherDist: number,
			gatherN: number,
			waves: number,
			sent: number,
			maxQuiet: number,
			goQuiet: number,
			quietAt: number?,
			goQuietAt: number?,
			blastMost: number,
			blast3: number,
			lostGather: number,
		},
	},
}
-- the build job a bot takes on its side's list (Rules/BotBuild.pick): an Engineer any within Build.take; a digger (half
-- a holding squad, any class) a trench run or square within Build.take, wire wanting swings within Build.help; nil if
-- none
-- the pieces every class builds (Config/Classes) and the guns, in one table
local Kinds = {
	small = { Trench = true, SandbagPile = true, Hesco = true },
	gun = { FieldGun = true, Howitzer = true },
}
-- whether piece `key` at `at` keeps off `side`'s trench lines (Rules/BotTrenches.clearOf; user 2026-11-02: "never have
-- structures where trenches should be")
function Clear.ofLines(side: string, key: string, at: Vector3): boolean
	local sb = buildLists[side]
	return sb == nil or BotTrenches.clearOf(at.X, at.Z, Clear.half[key] or 0, sb.lines, Clear.keep)
end

-- the piece in trench run `job`'s way, if any, and what its digger does with it (Rules/BotTrenches.blocker): "around"
-- first if any piece wants it, else "tear"; `team` the digger's
function Clear.inWay(team: string, job: BotBuild.Job): (Build.Work?, string?)
	local line = { { kind = "Trench", ax = job.x, az = job.z, bx = job.ex :: number, bz = job.ez :: number } }
	local first: Build.Work? = nil
	for _, w in Clear.every do
		local half = Clear.half[w.key]
		if
			half
			and not Clear.inside[w.key]
			and w.model.Parent
			and not BotTrenches.clearOf(w.at.X, w.at.Z, half, line, Clear.keep)
		then
			local byBot = w.owner ~= nil and (w.owner :: number) < 0
			if BotTrenches.blocker(w.key, w.team == team, byBot, TR.tear) == "around" then
				return w, "around"
			end
			first = first or w
		end
	end
	return first, if first then "tear" else nil
end

-- whether `b` knows there's danger (Rules/BotTrenches.danger): shot at, an enemy its squad knows near, shelling near,
-- its sector contested
function ByTrench.danger(b: Bot, now: number): boolean
	local p = (b.root :: BasePart).Position
	local known = {}
	local sq = b.squad and squads[b.squad :: string]
	if sq then
		for _, k in (sq :: SquadState).known do
			table.insert(known, { x = k.pos.X, z = k.pos.Z, at = k.at })
		end
	end
	local enemy = if b.side == "West" then "East" else "West"
	local counts = b.sector and ByTrench.counts[b.sector :: number]
	local contested = counts ~= nil and ((counts :: any)[enemy] or 0) > 0
	local sinceShot = if b.threatAt then now - (b.threatAt :: number) else math.huge
	return BotTrenches.danger(now, p.X, p.Z, sinceShot, known, ByTrench.blasts, contested, TM)
end

-- the budget's running state: frames since start (the snapshot's key), this frame's rays still to spend, the path
-- computes the ration allows now
local budget = { frame = 0, rays = 0, paths = 0 }

return {
	Clear = Clear,
	bots = bots,
	pathOf = pathOf,
	ByTrench = ByTrench,
	Tactics = Tactics,
	random = random,
	stats = stats,
	squads = squads,
	rescue = rescue,
	buildLists = buildLists,
	Kinds = Kinds,
	budget = budget,
	fronts = fronts,
}
