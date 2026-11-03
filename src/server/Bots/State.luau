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
	-- the admin panel's bot tests (Bots.dev, Tactics.label): whether the labels are up, their text (Rules/DevActions)
	dev = { labelled = false, rules = require(Shared.Rules.DevActions) },
}

-- Normal: dugouts and foxholes (Config/Bots.Dugouts), in Tactics:
-- - holes: the foxholes its bots dug, the newest Dugouts.Fox.keep (a dug foxhole is only terrain: Build lists it no
--   more), each its middle and its floor
-- - tried: when each bot last tried to dig one at its hold post (a refused spot isn't tried again at once)
Tactics.dug = {
	holes = {} :: { { x: number, z: number, floor: Vector3 } },
	tried = {} :: { [number]: number },
}
-- a dugout's foot: where its steps start, on the trench floor at the foot of its wall (where a bot swings at it), from
-- its "Frame" (the middle of its steps and room, +Z back into the wall) and "Size"
function Tactics.dug.foot(model: Model): Vector3?
	local frame, size = model:GetAttribute("Frame"), model:GetAttribute("Size")
	if typeof(frame) == "CFrame" and typeof(size) == "Vector3" then
		return (frame * CFrame.new(0, 0, -size.Z / 2)).Position
	end
	return nil
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
	walls = 0, -- walls put on the list round nests and guns
	saps = 0, -- squads that began to sap forward
	sapRuns = 0, -- sap runs dug
	dangerPaths = 0, -- paths asked for knowing there's danger (kept to trenches)
	intoTrench = 0, -- shot at in the open, down into a trench nearby
	overTop = 0, -- squads over the top from their jump-off trench
	dugouts = 0, -- dugouts put on the build list
	sheltered = 0, -- holders down into a dugout under shelling
	cameUp = 0, -- holders up from a dugout to their posts
	bombed = 0, -- grenades down an enemy dugout's steps
	holes = 0, -- foxholes dug
	pinnedHoles = 0, -- foxholes begun pinned down in the open
	intoHole = 0, -- shot at in the open, down into a foxhole nearby
	lost = 0, -- fire trenches lost (the holders fell back)
	covering = 0, -- shots of covering fire
	blocked = 0, -- shots held: the muzzle's line to the aim point blocked (Config/Bots.Sight)
	strikes = 0, -- butt strokes that went (Config/Bots.Melee)
	pushes = 0, -- squads that pushed a group they outnumber (Config/Bots.Squads.Push)
	pushBombs = 0, -- grenades thrown to open such a push
	wireMoved = 0, -- wire spots moved off (or dropped from) its own side's ways (Config/Bots.Build.Wire)
	waited = 0, -- swings put off at pieces that lost HP lately (Config/Bots.Build.repairWait)
	spread = 0, -- path steps pushed aside off a teammate walking too close (Config/Bots.Spread)
	assaults = 0, -- squads that pushed into a zone
	stoodUp = 0, -- bodies found lying after a knock, stood up
	since = os.clock(),
}

local squads: { [string]: SquadState } = {}

local buildLists: { [string]: SideBuild } = {}
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
	buildLists = buildLists,
	Kinds = Kinds,
	budget = budget,
}
