--!strict
-- Bot soldiers that fill the empty places when too few players are on (Config/Bots, Rules/Bots; 2026-10-30: the FFA
-- zone match). In FFA they play as players (user 2026-10-30: "enemies are treated as players. they have their own
-- points that they can use to upgrade when they feel and they have a respawn timer. they should always be moving and
-- try to find cover if spotted or shot at").
-- - The director tops the match up to the mode's fill (Rules/Bots.wanted: players first, never over Config/Bots.Max),
--   one bot in at a time; when players join, bots leave (a dead one first, else one that has been over the count a
--   while). Workspace's "Bots" attribute pins the count (testing; the admin panel's Bots rows).
-- - A bot is a soldier like a player's: a name kept for its stay, a kit's body each life (src/server/Showcase.dummy,
--   dressed by src/server/Bodies: the uniform, its class's helmet, the face following health and the death face), its
--   class's gun (src/server/Loadouts.gear), tagged as an NPC soldier (Config/DevTools.Dummies.Tag) so src/server/Damage
--   hurts it, src/server/Healing heals it and src/server/Dragging drags it. It shoots through src/server/Firing
--   (Firing.fireAs / actAs: the same action state, rate and hitscan as a player's), is knocked and ragdolled
--   (src/server/DevDummies.throw), dies limp, and after a player's respawn wait plus a moment "in the menu"
--   (Config/Bots.MenuTime) comes back at a src/server/ZoneMatch spawn.
-- - Points: kills, assists and captures pay it like a player (src/server/Loadouts: botPoints); each life it may buy a
--   dearer class (Rules/Bots.chooseClass). Zone score, the lead and the win are src/server/ZoneMatch's.
-- - One loop steps every bot's brain (Rules/Bots.step) Config/Bots.Think times a second, staggered. It senses (enemies
--   in range and view, a line-of-sight ray for the nearest few, whether one is looking at it; shots passing close,
--   Firing.onShot), looks for cover the threat can't see (rings of points, a ray from the threat's eye to each), paths
--   with PathfindingService (the zone by a flank, the last place a target was seen, cover, away), aims with the
--   difficulty's error and lead, fires, works the bolt and reloads. src/server/Bots/Animate plays its animations.
-- - In Normal (src/server/Frontline) each bot fights on a side: the director tops each side up to its fill
--   (Rules/Bots.wantedSides), a bot wears its side's team, deploys in its side's wave line (Frontline.deployBot) and
--   counts in the zones like a player. Each side's commander (Rules/BotOrders), once a second, reads the sectors from
--   the Frontline folder and sends each bot to attack the side's target sector or defend an own one being taken; a bot
--   walks to a stand point in that sector's zone and fights there with the same brain.
-- - Normal squads (Rules/BotSquads, Config/Bots.Squads; user 2026-11-01: teamwork, pushing under covering fire, using
--   the whole map): the commander splits each order into squads, each with a lane and an approach spot by the zone
--   (src/server/Bots/Routes: spots scored by cover from the map), sometimes a waypoint on its lane's side on the way.
--   A squad walks there, bounds in contact (half fire at where its members saw enemies, half run on), and pushes in
--   together when it is ready; defenders stand on hold spots in their zone. Each bot's role in its squad tells the
--   brain to press on, give covering fire or hold.
-- The server's budget (Config/Bots.Budget): bots think round-robin within a frame's milliseconds (the rest wait a
-- frame); one snapshot of every soldier a frame serves all the bots' sight; cover searches walk one ring a think within
-- a frame's rays; path computes are rationed server-wide; a governor holds the count lower while the bots cost too much
-- or physics slows. MicroProfiler labels: Bots.frame, Bots.snapshot, Bots.sense, Bots.cover, Bots.move, Bots.command.
-- - Callouts (Config/Bots.Callouts, Rules/BotCallouts; user 2026-11-01): on a real event (hit, a teammate down, an
--   enemy seen, into cover, reloading, its squad moving up, pushing in or covering) a bot may say a short line, a bubble
--   over its head (src/client/BotSay, never in the chat log), only with a player near it and never often.
-- Every Config/Bots.ReportEvery seconds the log has a line on its cost and its fights.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local Classes = require(Shared.Config.Classes)
local DamageCfg = require(Shared.Config.Damage)
local DevCfg = require(Shared.Config.DevTools)
local FrontCfg = require(Shared.Config.Frontline)
local IndoorCfg = require(Shared.Config.Indoors)
local DragCfg = require(Shared.Config.Dragging)
local BuildCfg = require(Shared.Config.Build)
local GrenadeCfg = require(Shared.Config.Grenades)
local HealCfg = require(Shared.Config.Healing)
local W = require(Shared.Config.Weapons)
local Loco = require(Shared.Config.Locomotion)
local Net = require(Shared.Net)
local Map = require(Shared.Config.Maps.Map1)
local Metrics = require(Shared.Config.Metrics)
local ModesCfg = require(Shared.Config.Modes)
local SupCfg = require(Shared.Config.Suppression)
local RagdollCfg = require(Shared.Config.Ragdoll)
local U = require(Shared.Config.Uniforms)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local F = require(Shared.Rules.Firing)
local FrontRules = require(Shared.Rules.Frontline)
local Orders = require(Shared.Rules.BotOrders)
local Actions = require(Shared.Rules.BotActions)
local Buildings = require(Shared.Rules.BotBuildings)
local BotBuild = require(Shared.Rules.BotBuild)
local BotTrenches = require(Shared.Rules.BotTrenches)
local Callouts = require(Shared.Rules.BotCallouts)
local Rules = require(Shared.Rules.Bots)
local ShotRules = require(Shared.Rules.ShotAudio)
local Sup = require(Shared.Rules.Suppression)
local Teams = require(Shared.Rules.Teams)
local Armory = require(script.Parent.Armory)
local Build = require(script.Parent.Build)
local Concussion = require(script.Parent.Concussion)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local Doors = require(script.Parent.Doors)
local Dragging = require(script.Parent.Dragging)
local Firing = require(script.Parent.Firing)
local Frontline = require(script.Parent.Frontline)
local Grenades = require(script.Parent.Grenades)
local Healing = require(script.Parent.Healing)
local Indoors = require(script.Parent.Indoors)
local Kits = require(script.Parent.Kits)
local Loadouts = require(script.Parent.Loadouts)
local MatchStats = require(script.Parent.MatchStats)
local Ragdoll = require(script.Parent.Ragdoll)
local Showcase = require(script.Parent.Showcase)
local ZoneMatch = require(script.Parent.ZoneMatch)
local Animate = require(script.Animate)
local Routes = require(script.Routes)
local Squads = require(Shared.Rules.BotSquads)

local Bots = {}

local M = Metrics.Movement
local MV = Cfg.Move
local NV = Cfg.Normal
local SQ = Cfg.Squads
local RT = Cfg.Routes
local BG = Cfg.Budget
local CV = MV.Cover
local brainCfg = Cfg.Brain :: any
local AC = Cfg.Actions
local IN = Cfg.Indoors
local BD = Cfg.Build
local TR = Cfg.Trenches

type Target = { model: Model, distance: number, visible: boolean }

type Nav = {
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
type BuildJob = {
	job: BotBuild.Job, -- (its spot moved by refusals)
	base: BotBuild.Job, -- as planned
	model: Model?,
	at: Vector3?, -- the piece's spot once laid (what it swings at)
	left: number,
	tries: number,
	waitUntil: number,
	open: boolean, -- on the list this tick
	run: BotTrenches.Run?, -- a trench run of the side's system (Rules/BotTrenches): planned, then its squares dug
}

-- Normal: what a bot does instead of fighting for a while (Rules/BotActions): a drag of `who` to `to` (cover from the
-- enemy spot `from`), a heal of `who`, a grenade at `at`
type Act = {
	kind: string, -- "Drag", "Heal", "Throw" or "Build"
	who: Model?,
	at: Vector3?,
	from: Vector3?,
	to: Vector3?,
	started: number,
	phase: string?, -- the drag's "pull", the heal's "heal", the throw's "throw" and "done"
	job: BuildJob?, -- a build's job
	swingAt: number?, -- a build's next swing
}

type Bot = {
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
	lastOpen: Vector3?, -- where it stood when it last saw its target (a peek goes back there)
	spotted: boolean,
	hurtAt: number?,
	threatAt: number?,
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
	overSince: number?,
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
	actAt: number, -- when it next weighs one (Config/Bots.Actions.every)
	grenades: Tool?, -- a Grenadier's grenades, out of its hands until a throw
	threwAt: number,
	away: boolean, -- its gun put away for an action
	slung: Model?, -- its gun's copy on the pack's strap while the gun is out of its hands (Armory.stowed)
	shovel: Tool?, -- its shovel, out of its hands until it builds
	digger: boolean?, -- Normal: one of its holding squad's diggers (Config/Bots.Trenches.share)
	postFloor: Vector3?, -- its post is a fire step: the trench floor below it (its cover)
	postKind: string?, -- "step", "reserve" (the support line), "window" or "open"
}

type CoverJob = { threat: Vector3, ring: number, here: number }

local bots: { Bot } = {}
-- each bot's own Path object, made once (CreatePath on every request cost a frame now and then)
local pathOf: { [number]: Path } = {}
local count = 0
local folder: Folder? = nil
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
	runs = 0, -- trench runs planned
	lost = 0, -- fire trenches lost (the holders fell back)
	covering = 0, -- shots of covering fire
	assaults = 0, -- squads that pushed into a zone
	stoodUp = 0, -- bodies found lying after a knock, stood up
	since = os.clock(),
}

-- Normal squads by key (Rules/BotSquads), kept tick to tick: the phase, its lane and route, what its members saw
type Known = { model: Model?, pos: Vector3, at: number } -- (no model: a shot heard, its source guessed)
type SquadState = {
	sq: Squads.Squad,
	side: string,
	sector: number,
	lane: number,
	approach: Vector3?,
	mid: Vector3?,
	known: { Known },
	seen: number, -- the commander's tick it was last formed (gone ones are dropped)
	threwAt: number?, -- its last grenade (Config/Bots.Actions.Grenade.squadEvery)
	clear: Vector3?, -- pushing in: the indoor spot by a known enemy inside a building (its Assault bots go there)
}
local squads: { [string]: SquadState } = {}

-- Normal: each side's build list at its front (Rules/BotBuild), kept each commander tick: the lay jobs (planned again
-- when the front or the artillery level changes, or once the hold spots are found), each matched to its piece once
-- laid, and the own pieces near the front wanting swings; `open` the jobs a bot may take now
type TrenchPost = { pos: Vector3, floor: Vector3?, face: Vector3? }
type SideBuild = {
	front: number?,
	level: number,
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
}
local buildLists: { [string]: SideBuild } = {}
local commandTick = 0

-- the budget's running state
local frame = 0 -- frames since start (the snapshot's key)
local raysLeft = 0 -- this frame's rays still to spend
local pathTokens = 0 -- path computes the ration allows now
local cursor = 1 -- the bot the next frame starts with (round-robin)
local governor = Rules.governor(math.max(Cfg.Max.FFA, Cfg.Max.Normal))
local govAt, govTime, govFrames = os.clock(), 0, 0

local function liveMode(): string?
	local mode = workspace:GetAttribute(ModesCfg.Attribute)
	return if type(mode) == "string" then mode else nil
end

local function difficulty(): Rules.Difficulty
	local key = workspace:GetAttribute(Cfg.DifficultyAttribute)
	return ((type(key) == "string" and (Cfg.Difficulty :: any)[key]) or (Cfg.Difficulty :: any)[Cfg.Default])
end

local function botFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = Cfg.Folder
	f.Parent = workspace
	folder = f
	return f
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function alive(b: Bot): boolean
	return b.m ~= nil and b.humanoid ~= nil and (b.humanoid :: Humanoid).Health > 0 and (b.m :: Model).Parent ~= nil
end

-- a name no bot on now has (the list's first free one; numbered once it runs out)
local function freeName(): string
	local used = {}
	for _, b in bots do
		used[b.name] = true
	end
	local start = random:NextInteger(1, #Cfg.Names)
	for i = 0, #Cfg.Names - 1 do
		local n = Cfg.Names[(start + i - 1) % #Cfg.Names + 1]
		if not used[n] then
			return n
		end
	end
	return `{Cfg.Names[start]} {count}`
end

-- the class this life from its match points (Rules/Bots.chooseClass), paid now
local function chooseClass(b: Bot): (string, number?)
	local options = {}
	local push = {}
	for _, c in Cfg.Classes do
		local def = Classes.Defs[c.key]
		if def and not def.locked then
			table.insert(options, { key = c.key, cost = def.cost })
			push[c.key] = c.push
		end
	end
	local key, cost =
		Rules.chooseClass(Loadouts.botPoints(b.id), options, Cfg.Buy, random:NextNumber(), random:NextNumber())
	if cost > 0 then
		Loadouts.botPay(b.id, cost)
		stats.upgrades += 1
	end
	return key, push[key]
end

local spawnBody: (b: Bot) -> ()

-- callouts: who said what lately (Rules/BotCallouts)
local talk = Callouts.new()
local CO = Cfg.Callouts

-- Bot `b` says its line for `event` (Config/Bots.Callouts) when it may: a player near, its waits and its side's over,
-- the event's chance; the bubble goes to the players within `hear` studs. `name`: a fallen teammate's. True if said.
local function say(b: Bot, event: string, name: string?): boolean
	local root = b.root
	if not root or not b.m or not alive(b) then
		return false
	end
	local now = os.clock()
	local side = b.side or b.kit
	if not Callouts.can(talk, b.id, side, event, now, b.nearest, random:NextNumber(), CO) then
		return false
	end
	local kit = (U.Kits :: any)[b.kit]
	local lines = kit and (CO.Lines :: any)[kit.team]
	local line = Callouts.line(lines and lines[event], random:NextNumber(), name)
	if not line then
		return false
	end
	Callouts.said(talk, b.id, side, event, now)
	stats.callouts += 1
	local at = (root :: BasePart).Position
	for _, p in Players:GetPlayers() do
		local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pr and (pr.Position - at).Magnitude <= CO.hear then
			Net.event("BotSay"):FireClient(p, b.m, line)
		end
	end
	return true
end

-- Normal: each sector's ground at its point (found once, by a ray on terrain)
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
local sectorY: { [number]: number } = {}
local function sectorPoint(i: number): Vector3
	local s = Map.sectors[i]
	if not sectorY[i] then
		local g = FrontCfg.GroundRay
		local hit = workspace:Raycast(Vector3.new(s.x, g.top, s.z), Vector3.new(0, -g.depth, 0), terrainOnly)
		sectorY[i] = if hit then hit.Position.Y else 0
	end
	return Vector3.new(s.x, sectorY[i], s.z)
end

-- where the bot is headed and the zone's radius: FFA's zone, or in Normal its order's sector
local function objective(b: Bot): (Vector3?, number)
	if b.mode == "Normal" then
		if not b.sector then
			return nil, 0
		end
		return sectorPoint(b.sector :: number), Map.sectors[b.sector :: number].radius
	end
	return ZoneMatch.objective()
end

local function newNav(at: Vector3): Nav
	return {
		goal = nil,
		waypoints = {},
		index = 1,
		computing = false,
		pathAt = -math.huge,
		sampleAt = os.clock(),
		samplePos = at,
		jumps = 0,
		repaths = 0,
		direct = nil,
		doorAt = -math.huge,
	}
end

-- A body for `b` at a spawn point, dressed in its class, armed and on its feet.
-- its gun slung on the pack's strap while it is out of its hands (Armory.stowed: a player's put-away gun; user
-- 2026-11-02: "whenever the gun is down for ai's, it should be on the bag strap"), or taken off it
local function sling(b: Bot, on: boolean)
	local m = b.m :: Model
	if on and not b.slung then
		b.slung = Armory.stowed(m, b.weapon)
	end
	local slung = b.slung
	if slung and slung.Parent ~= (if on then m else nil) then
		slung.Parent = if on then m else nil
	end
end

spawnBody = function(b: Bot)
	if b.spawning then
		return
	end
	local cf: CFrame?
	if b.mode == "Normal" then
		-- its side's team this match; built over its home end, then stood in the wave line (Frontline.deployBot)
		local pair = FrontRules.parsePair(workspace:GetAttribute(FrontCfg.TeamsAttribute))
		if not pair or not b.side or not Frontline.running() then
			return
		end
		b.kit = (pair :: any)[b.side]
		local home = sectorPoint(if b.side == "West" then 1 else #Map.sectors)
		cf = CFrame.new(home + Vector3.yAxis * FrontCfg.SpawnLift)
	else
		cf = ZoneMatch.spawnFor(nil)
		if not cf then
			return
		end
		-- FFA: a fresh kit each life, as a player's is rolled
		b.kit = U.Teams[random:NextInteger(1, #U.Teams)]
	end
	b.spawning = true
	-- the class from its points
	local class, push = chooseClass(b)
	local ok, made = pcall(Showcase.dummy, b.name, cf :: CFrame, botFolder(), b.kit, { Class = class })
	b.spawning = false
	if not ok then
		warn(`[Bots] no body for {b.name}: {made}`)
		return
	end
	local m = made :: Model
	if not table.find(bots, b) then
		m:Destroy() -- (removed while it was being built)
		return
	end
	b.weapon = Loadouts.gear(m).Primary or U.Kits[b.kit].weapon
	b.push = push
	m:SetAttribute("Muted", nil) -- heard, unlike the showcase's
	m:SetAttribute(Cfg.IdAttribute, b.id)
	CollectionService:AddTag(m, DevCfg.Dummies.Tag)
	CollectionService:AddTag(m, Cfg.Tag)
	local function group(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Characters"
		end
	end
	for _, d in m:GetDescendants() do
		group(d)
	end
	m.DescendantAdded:Connect(group)
	local humanoid = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = if b.mode == "Normal" then NV.nameTag .. b.name else b.name
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = DamageCfg.Health
	humanoid.Health = DamageCfg.Health
	humanoid.WalkSpeed = M.WalkSpeed
	humanoid.JumpHeight = M.JumpHeight
	humanoid.UseJumpPower = false
	humanoid.MaxSlopeAngle = M.MaxSlopeAngle
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	DevDummies.steady(humanoid)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	local torso = m:FindFirstChild("Torso") :: BasePart
	local armed, gun = pcall(Armory.tool, b.weapon, b.kit)
	if not armed then
		-- (no gun to be had: the body goes, not left standing unarmed; the director tries again)
		m:Destroy()
		warn(`[Bots] no gun for {b.name}: {gun}`)
		return
	end
	local tool = gun :: Tool
	local hold = tool:FindFirstChild("Hold", true) :: Motor6D
	hold.Part0 = torso
	tool.Parent = m
	Firing.entry(tool) -- (a full gun, published)
	-- turned toward its target while aiming (AutoRotate faces where it walks)
	local att = Instance.new("Attachment")
	att.Name = "BotTurnAt"
	att.Parent = root
	local turn = Instance.new("AlignOrientation")
	turn.Name = "BotTurn"
	turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turn.Attachment0 = att
	turn.Responsiveness = Cfg.Turn.responsiveness
	turn.MaxTorque = Cfg.Turn.torque
	turn.Enabled = false
	turn.Parent = root
	root.Anchored = false
	DevDummies.own(m)
	if b.mode ~= "Normal" then
		Damage.protect(m, ZoneCfg.SpawnProtection)
	end

	b.m, b.humanoid, b.root, b.head, b.tool, b.turn =
		m, humanoid, root, m:FindFirstChild("Head") :: BasePart, tool, turn
	b.grip, b.stowed = hold, false
	b.anim = Animate.attach(m, b.weapon)
	-- a Grenadier's grenades (Config/Classes `grenades`), held only for a throw
	if b.grenades then
		(b.grenades :: Tool):Destroy()
	end
	if b.shovel then
		(b.shovel :: Tool):Destroy()
	end
	if b.slung then
		(b.slung :: Model):Destroy()
	end
	b.grenades, b.act, b.away, b.shovel, b.slung = nil, nil, false, nil, nil
	local nade = Loadouts.gear(m).Grenade
	if nade then
		local given, g = pcall(Armory.tool, nade, b.kit)
		if given then
			b.grenades = g
		end
	end
	b.brain = Rules.new()
	b.target, b.lastSeenAt, b.lastOpen, b.spotted = nil, nil, nil, false
	b.hurtAt, b.threatAt, b.threatFrom, b.cover, b.coverFrom = nil, nil, nil, nil, nil
	b.nav = newNav(root.Position)
	b.spawnedAt, b.reachedZone, b.deadAt, b.respawnAt, b.wander = os.clock(), false, nil, nil, nil
	b.coverJob, b.stand = nil, nil
	b.shaken, b.shakenAt = 0, 0
	if b.mode == "Normal" then
		Frontline.deployBot(m) -- (its side's wave line: held and shielded until the wave goes)
		b.nav = newNav(root.Position)
	end
	-- the way to the zone: now and then a bend off the straight line
	b.flank = nil
	local zone = objective(b)
	if zone and random:NextNumber() < MV.FlankChance then
		local z = zone :: Vector3
		local across = flat(z - root.Position)
		if across.Magnitude > 1 then
			local side = across.Unit:Cross(Vector3.yAxis) * (if random:NextNumber() < 0.5 then -1 else 1)
			local share = random:NextNumber(MV.Flank[1], MV.Flank[2])
			b.flank = root.Position + across * 0.5 + side * across.Magnitude * share
		end
	end

	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last then
			b.hurtAt = os.clock()
			b.threatAt = b.hurtAt
			if health > 0 then
				say(b, "Hit")
			end
		end
		last = health
	end)
	m:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if m:GetAttribute("Ragdolled") ~= true and humanoid.Health > 0 then
			DevDummies.getUp(m, humanoid)
			-- a knock puts the weapon away (src/server/Ragdoll: UnequipTools); a player draws it again, so the bot does too
			-- (user 2026-10-30: "bots also dont stand up with their weapon when ragdolled")
			if tool.Parent ~= m and pcall(function()
				tool.Parent = m
			end) then
				sling(b, false)
				hold.Part0 = torso
				if b.anim then
					(b.anim :: Animate.Handle).equip()
				end
			end
			-- (a joint made or broken hands the body's physics to the nearest player, where the server's get-up is
			-- ignored: taken back after the gun goes in the hands)
			DevDummies.own(m)
		end
	end)
	humanoid.Died:Connect(function()
		stats.deaths += 1
		b.deadAt = os.clock()
		-- a teammate close by calls it
		for _, o in bots do
			if
				o ~= b
				and o.root
				and o.kit == b.kit
				and ((o.root :: BasePart).Position - root.Position).Magnitude <= CO.manDownWithin
				and say(o, "ManDown", b.name)
			then
				break
			end
		end
		-- a player's respawn wait (Normal: until deploy opens), then a moment in the loadout menu
		local wait = if b.mode == "Normal" then FrontCfg.Waves.dead else Metrics.Combat.RespawnDelay
		b.respawnAt = b.deadAt + wait + random:NextNumber(Cfg.MenuTime[1], Cfg.MenuTime[2])
		turn.Enabled = false
		Loadouts.died(m) -- (the killer and the assists paid)
		DevDummies.own(m)
		task.wait() -- (a hit's own knock comes with its death: let it land first)
		if not Ragdoll.active(m) then
			Ragdoll.knock(m, DamageCfg.Knocks.Other, -root.CFrame.LookVector)
		end
	end)
end

local function despawn(b: Bot)
	if b.m then
		(b.m :: Model):Destroy()
	end
	b.m, b.humanoid, b.root, b.head, b.tool, b.anim, b.turn = nil, nil, nil, nil, nil, nil, nil
	if b.grenades then
		(b.grenades :: Tool):Destroy()
	end
	if b.shovel then
		(b.shovel :: Tool):Destroy()
	end
	if b.slung then
		(b.slung :: Model):Destroy()
	end
	b.grenades, b.act, b.away, b.shovel, b.slung = nil, nil, false, nil, nil
end

local function add(mode: string, side: string?)
	count += 1
	local b: Bot = {
		mode = mode,
		side = side,
		id = -count,
		name = "",
		kit = U.Default,
		weapon = U.Kits[U.Default].weapon,
		brain = Rules.new(),
		nextThink = os.clock() + random:NextNumber() / Cfg.Think,
		nextSense = 0,
		spotted = false,
		coverAt = 0,
		nav = newNav(Vector3.zero),
		wanderAt = 0,
		strafeAt = 0,
		spawnedAt = 0,
		reachedZone = false,
		spawning = false,
		stowed = false,
		shaken = 0,
		shakenAt = 0,
		thinkHz = Cfg.Think,
		senseHz = Cfg.Sense,
		lod = "near",
		nearest = math.huge,
		actAt = 0,
		threwAt = -math.huge,
		away = false,
	}
	b.name = freeName()
	table.insert(bots, b)
	botFolder():SetAttribute(Cfg.NameAttribute .. tostring(count), b.name)
	spawnBody(b)
end

local function remove(i: number)
	local b = bots[i]
	despawn(b)
	table.remove(bots, i)
	botFolder():SetAttribute(Cfg.NameAttribute .. tostring(-b.id), nil)
	Loadouts.forgetBot(b.id)
	ZoneMatch.forgetBot(b.id)
	Callouts.forget(talk, b.id)
	pathOf[b.id] = nil
end

-- sensing ------------------------------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function eye(b: Bot): Vector3
	return if b.head then (b.head :: BasePart).Position else (b.root :: BasePart).Position + Vector3.yAxis * Cfg.Eye
end

local function aimPart(target: Model): BasePart?
	return (target:FindFirstChild("Torso") or target:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- every soldier alive this frame, gathered once for all the bots' sight (entries reused frame to frame)
type Soldier = { model: Model, part: BasePart, kit: any, pos: Vector3, look: Vector3, health: number, down: boolean }
local snapshot: { Soldier } = {}
local snapCount = 0
local snapFrame = -1

local function soldiersNow(): ({ Soldier }, number)
	if snapFrame == frame then
		return snapshot, snapCount
	end
	snapFrame = frame
	debug.profilebegin("Bots.snapshot")
	snapCount = 0
	for _, m in Damage.soldiers() do
		local h = m:FindFirstChildOfClass("Humanoid")
		local part = aimPart(m)
		if h and h.Health > 0 and part then
			local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			local look = if root then flat(root.CFrame.LookVector) else Vector3.zero
			snapCount += 1
			local e = snapshot[snapCount]
			if not e then
				e = {} :: any
				snapshot[snapCount] = e
			end
			e.model, e.part, e.kit, e.pos = m, part, m:GetAttribute("Kit"), part.Position
			e.look = if look.Magnitude > 1e-3 then look.Unit else Vector3.zero
			e.health, e.down = h.Health / math.max(h.MaxHealth, 1), Ragdoll.active(m)
		end
	end
	debug.profileend()
	return snapshot, snapCount
end

-- whether `other` is on `m`'s side (Damage.spares' rule, from the snapshot's kits)
local function friendly(m: Model, kit: any, other: Soldier): boolean
	if kit == nil or other.kit == nil then
		return Damage.spares(m, other.model)
	end
	return Teams.spared(
		kit,
		other.kit,
		DamageCfg.FriendlyFire,
		workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true
	)
end

-- the bot's sight now; false when the frame's rays are spent (it looks again next think)
local function sense(b: Bot, d: Rules.Difficulty, now: number): boolean
	local m, root = b.m :: Model, b.root :: BasePart
	local from = eye(b)
	local facing = flat(root.CFrame.LookVector)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.zAxis
	-- hit or shot at lately: it looks all round
	local alert = b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.Alert
	local seen: { Target } = {}
	local parts: { [Model]: Soldier } = {}
	local all, n = soldiersNow()
	local kit = m:GetAttribute("Kit")
	for k = 1, n do
		local other = all[k]
		if other.model == m or friendly(m, kit, other) then
			continue
		end
		local off = other.pos - from
		local dist = off.Magnitude
		if Rules.inSight(off.X, off.Z, dist, facing.X, facing.Z, d.spotRange, d.fov, alert) then
			table.insert(seen, { model = other.model, distance = dist, visible = false })
			parts[other.model] = other
		end
	end
	local rays = math.min(#seen, Cfg.SenseNearest)
	if rays > raysLeft then
		stats.senseDeferred += 1
		return false
	end
	table.sort(seen, function(x, y)
		return x.distance < y.distance
	end)
	rayParams.FilterDescendantsInstances = { m }
	local list = {}
	local out: { Target } = {}
	b.spotted = false
	for i = 1, rays do
		local t = seen[i]
		local other = parts[t.model]
		local hit = workspace:Raycast(from, other.pos - from, rayParams)
		stats.rays += 1
		raysLeft -= 1
		t.visible = hit ~= nil and hit.Instance:IsDescendantOf(t.model)
		table.insert(out, t)
		table.insert(list, { id = t.model, distance = t.distance, visible = t.visible })
		-- an enemy in sight looking its way has spotted it
		if t.visible and other.look.Magnitude > 0 then
			local off = other.pos - from
			if Rules.lookingAt(off.X, off.Z, other.look.X, other.look.Z, brainCfg.LookCone) then
				b.spotted = true
				if not b.threatFrom or now - (b.threatAt or -math.huge) > brainCfg.ThreatMemory then
					b.threatFrom = other.pos + Vector3.yAxis * Cfg.Eye
				end
			end
		end
	end
	local pick = Rules.pick(list, b.brain.targetId)
	b.target = nil
	if pick then
		for _, t in out do
			if t.model == pick.id then
				b.target = t
			end
		end
	end
	if b.target and (b.target :: Target).visible then
		local part = aimPart((b.target :: Target).model)
		if part then
			b.lastSeenAt = part.Position
			-- the squad knows it too (covering fire, contact)
			local sq = b.squad and squads[b.squad :: string]
			if sq then
				local known = (sq :: SquadState).known
				local found = false
				for _, k in known do
					if k.model == (b.target :: Target).model then
						k.pos, k.at, found = part.Position, now, true
					end
				end
				if not found then
					table.insert(known, { model = (b.target :: Target).model, pos = part.Position, at = now })
					if #known > 6 then
						table.remove(known, 1)
					end
				end
			end
		end
		b.lastOpen = root.Position
	end
	return true
end

-- the latest enemy spot the bot's squad knows (covering fire), or nil
local function knownSpot(b: Bot, now: number): Vector3?
	local sq = b.squad and squads[b.squad :: string]
	if not sq then
		return nil
	end
	local best: Known? = nil
	for _, k in (sq :: SquadState).known do
		if now - k.at <= SQ.knownFor and (not best or k.at > (best :: Known).at) then
			best = k
		end
	end
	return if best then best.pos else nil
end

-- a ground point under (x, z) near `y`, or nil (off the map, under water)
local function groundAt(x: number, y: number, z: number, exclude: { Instance }): Vector3?
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(Vector3.new(x, y + 8, z), Vector3.new(0, -24, 0), rayParams)
	stats.rays += 1
	raysLeft -= 1
	return hit and hit.Position
end

-- whether the threat's eye `from` can't see a soldier standing at the ground point `p`
local function hidden(from: Vector3, p: Vector3, exclude: { Instance }): boolean
	local chest = p + Vector3.yAxis * (CV.chest + 1.8)
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(from, chest - from, rayParams)
	stats.rays += 1
	raysLeft -= 1
	return hit ~= nil and hit.Distance < (chest - from).Magnitude - 1
end

-- cover from the threat: the old point while it's still hidden from where the threat is now; else rings of points
-- round the bot, nearest ring first (Rules/Bots.pickCover), one ring a think within the frame's rays (b.coverJob)
local function exclusions(b: Bot): { Instance }
	local exclude: { Instance } = { b.m :: Model }
	if b.target then
		table.insert(exclude, (b.target :: Target).model)
	end
	return exclude
end

local function findCover(b: Bot, now: number)
	local from = b.threatFrom or b.lastSeenAt
	if not from then
		b.cover = nil
		return
	end
	local threat = from :: Vector3
	b.coverAt = now
	if raysLeft < 1 then
		return
	end
	local root = b.root :: BasePart
	local stale = b.coverFrom and ((b.coverFrom :: Vector3) - threat).Magnitude > CV.moved
	if b.cover and not stale and hidden(threat, b.cover :: Vector3, exclusions(b)) then
		return
	end
	b.cover = nil
	b.coverJob = { threat = threat, ring = 1, here = flat(root.Position - threat).Magnitude }
end

-- whether a building has a way in (a door link: src/server/Indoors makes none for a door far up a bank)
local enterable: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function canEnter(building: Model): boolean
	local known = enterable[building]
	if known == nil then
		known = false
		for _, d in building:GetDescendants() do
			if d:IsA("PathfindingLink") and d.Label == IndoorCfg.Links.door then
				known = true
				break
			end
		end
		enterable[building] = known
	end
	return known :: boolean
end

-- the indoor spots (src/server/Indoors) within `within` studs of `at` in buildings with a way in, looked up by
-- Config/Bots.Indoors `cell`-stud squares, each kept `keep` seconds (a building broken meanwhile shows up at the next
-- look)
local indoorCells: { [string]: { at: number, spots: { Indoors.Spot } } } = {}
local function indoorNear(at: Vector3, within: number): { Indoors.Spot }
	local cx, cz = math.floor(at.X / IN.cell), math.floor(at.Z / IN.cell)
	local key = `{cx}:{cz}`
	local now = os.clock()
	local c = indoorCells[key]
	if not c or now - c.at > IN.keep then
		local centre = Vector3.new((cx + 0.5) * IN.cell, at.Y, (cz + 0.5) * IN.cell)
		c = { at = now, spots = Indoors.near(centre, IN.cell * 0.71 + within + IN.slack) }
		indoorCells[key] = c
	end
	local out = {}
	for _, s in (c :: any).spots do
		if flat(s.at - at).Magnitude <= within and canEnter(s.building) then
			table.insert(out, s)
		end
	end
	return out
end

local function asSpot(s: Indoors.Spot, taken: number): Buildings.Spot
	return { x = s.at.X, z = s.at.Z, fx = s.face.X, fz = s.face.Z, story = s.story, taken = taken }
end

-- the nearest teammate (from this frame's snapshot) within `within` studs of `at`, not `b` itself; nil if none
local function mateNear(b: Bot, at: Vector3, within: number): Vector3?
	local all, n = soldiersNow()
	local m = b.m :: Model
	local kit = m:GetAttribute("Kit")
	local best, bestAt = within, nil
	for k = 1, n do
		local o = all[k]
		if o.model ~= m and friendly(m, kit, o) then
			local d = flat(o.pos - at).Magnitude
			if d < best then
				best, bestAt = d, o.pos
			end
		end
	end
	return bestAt
end

-- the search's next ring, when the frame has the rays for it
local function coverStep(b: Bot)
	local job = b.coverJob :: CoverJob
	if raysLeft < CV.perRing * 2 then
		return
	end
	debug.profilebegin("Bots.cover")
	local root = b.root :: BasePart
	local exclude = exclusions(b)
	local r = CV.rings[job.ring]
	local points = {}
	local spots = {}
	for k = 0, CV.perRing - 1 do
		local a = (k / CV.perRing + random:NextNumber() * 0.1) * 2 * math.pi
		local x, z = root.Position.X + math.cos(a) * r, root.Position.Z + math.sin(a) * r
		local g = groundAt(x, root.Position.Y, z, exclude)
		if g then
			table.insert(spots, g)
			table.insert(points, {
				distance = r,
				hidden = hidden(job.threat, g, exclude),
				threat = flat(g - job.threat).Magnitude,
				crowded = mateNear(b, g, brainCfg.SpreadMin) ~= nil,
			})
		end
	end
	-- the first ring also tries the indoor cover spots close by (Config/Bots.Indoors.cover)
	if job.ring == 1 then
		local indoor = {}
		for _, s in indoorNear(root.Position, CV.reach) do
			if s.kind == "Cover" then
				table.insert(indoor, s)
			end
		end
		local list = {}
		for k, s in indoor do
			list[k] = asSpot(s, 0)
		end
		local p = root.Position
		for _, k in
			Buildings.coverCandidates(list, p.X, p.Z, job.threat.X, job.threat.Z, CV.reach, CV.minThreatGain, IN.cover)
		do
			local g = indoor[k].at
			table.insert(spots, g)
			table.insert(points, {
				distance = flat(g - p).Magnitude,
				hidden = hidden(job.threat, g, exclude),
				threat = flat(g - job.threat).Magnitude,
				crowded = mateNear(b, g, brainCfg.SpreadMin) ~= nil,
			})
		end
	end
	local i = Rules.pickCover(points, job.here - CV.minThreatGain, CV.reach)
	if i then
		b.cover = spots[i]
		b.coverFrom = job.threat
		b.coverJob = nil
		stats.covers += 1
	elseif job.ring >= #CV.rings then
		b.coverJob = nil
	else
		job.ring += 1
	end
	debug.profileend()
end

-- a bot's suppression level now (held, then falling: Rules/Suppression.decay)
local function shakenNow(b: Bot, now: number): number
	return Sup.decay(b.shaken, 0, now - b.shakenAt, SupCfg.Hold, SupCfg.Fall)
end

local function shake(b: Bot, amount: number, now: number)
	if amount > 0 then
		b.shaken = Sup.add(shakenNow(b, now), amount, SupCfg.Cap)
		b.shakenAt = now
	end
end

local function asPoint(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

local function ffa(): boolean
	return workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true
end

-- a shot heard close by: under threat, from where it guesses the shot came (Rules/Bots.heard: not the shooter's own
-- spot), which its squad then knows too (covering fire, contact)
local function heardShot(b: Bot, origin: Vector3, now: number)
	local root = b.root :: BasePart?
	if not root then
		return
	end
	local p = (root :: BasePart).Position
	local x, z = Rules.heard(
		p.X,
		p.Z,
		origin.X,
		origin.Z,
		brainCfg.HeardAngle,
		brainCfg.HeardRange,
		random:NextNumber(),
		random:NextNumber()
	)
	local guess = Vector3.new(x, origin.Y, z)
	b.threatAt = now
	b.threatFrom = guess
	local sq = b.squad and squads[b.squad :: string]
	if sq then
		local known = (sq :: SquadState).known
		for _, k in known do
			if k.model == nil and flat(k.pos - guess).Magnitude < brainCfg.HeardRange * 60 then
				k.pos, k.at = guess, now
				return
			end
		end
		table.insert(known, { model = nil, pos = guess, at = now })
		if #known > 6 then
			table.remove(known, 1)
		end
	end
end

-- shots passing close: every bot near the line feels it (Rules/Bots.nearMiss) and is suppressed by it, as a player
-- is (Config/Suppression Pass and Impact)
local function shotPassed(shooter: Model, origin: Vector3, hit: Vector3)
	local line = hit - origin
	local len = line.Magnitude
	if len < 1e-3 then
		return
	end
	local l = line / len
	local now = os.clock()
	for _, b in bots do
		if b.m == shooter or not alive(b) or Damage.spares(shooter, b.m) then
			continue
		end
		local p = eye(b)
		if Rules.nearMiss(origin.X, origin.Y, origin.Z, l.X, l.Y, l.Z, len, p.X, p.Y, p.Z, brainCfg.NearMiss) then
			heardShot(b, origin, now)
			-- its teammates close by hear it too (they disperse and look that way)
			for _, o in bots do
				if
					o ~= b
					and alive(o)
					and o.root
					and Teams.spared(o.kit, b.kit, DamageCfg.FriendlyFire, ffa())
					and flat((o.root :: BasePart).Position - p).Magnitude <= brainCfg.AlertRadius
				then
					heardShot(o, origin, now)
				end
			end
		end
		local P, I = SupCfg.Pass, SupCfg.Impact
		local pass = ShotRules.pass(asPoint(origin), asPoint(hit), asPoint(p), P.radius, P.clear)
		shake(b, math.max(Sup.impact((hit - p).Magnitude, I), if pass then Sup.pass(pass.off, P) else 0), now)
	end
end

-- moving -------------------------------------------------------------------------------------------------------------

-- paths found lately, shared: a bot going near the same place from near a waypoint of one follows it from there
-- (Config/Bots.Move.Share) instead of asking for its own
type SharedPath = { goal: Vector3, waypoints: { PathWaypoint }, at: number }
local sharedPaths: { SharedPath } = {}

local function sharedPath(from: Vector3, goal: Vector3, now: number): ({ PathWaypoint }?, number)
	local S = MV.Share
	for i = #sharedPaths, 1, -1 do
		local c = sharedPaths[i]
		if now - c.at > S.keep then
			table.remove(sharedPaths, i)
		elseif flat(c.goal - goal).Magnitude <= S.goalWithin then
			-- the nearest of its waypoints to where the bot stands, close enough to join there
			local best, bestAt = S.fromWithin, nil
			for k, wp in c.waypoints do
				local d = flat(wp.Position - from).Magnitude
				if d < best then
					best, bestAt = d, k
				end
			end
			if bestAt then
				return c.waypoints, math.min(bestAt + 1, #c.waypoints)
			end
		end
	end
	return nil, 1
end

-- a path to `goal`: a shared one when there is one, else its own when the server's ration allows
-- (Budget.pathsPerSecond); false when it waits (the bot walks straight at the goal meanwhile and asks again next think).
-- `own`: never a shared one (a bot stuck on its path asks afresh)
local function computePath(b: Bot, goal: Vector3, own: boolean?): boolean
	local nav = b.nav
	local root = b.root :: BasePart
	local from = root.Position
	local now = os.clock()
	local wps, start = nil, 1
	if not own then
		wps, start = sharedPath(from, goal, now)
	end
	if wps then
		stats.pathsShared += 1
		nav.waypoints, nav.index, nav.pathAt = wps, start, now
		return true
	end
	if pathTokens < 1 then
		stats.pathsDeferred += 1
		return false
	end
	pathTokens -= 1
	nav.computing = true
	nav.pathAt = now
	local path = pathOf[b.id]
	if not path then
		path = PathfindingService:CreatePath({
			AgentRadius = MV.AgentRadius,
			AgentHeight = MV.AgentHeight,
			AgentCanJump = true,
			WaypointSpacing = MV.WaypointSpacing,
			Costs = IndoorCfg.PathCosts, -- (through doorways and up stairs: src/server/Indoors' links)
		})
		pathOf[b.id] = path
	end
	task.spawn(function()
		stats.paths += 1
		local ok = pcall(function()
			(path :: Path):ComputeAsync(from, goal)
		end)
		nav.computing = false
		local found = ok and (path :: Path).Status == Enum.PathStatus.Success
		local waypoints = if found then (path :: Path):GetWaypoints() else {}
		if found and flat(goal - from).Magnitude >= MV.Share.longer then
			table.insert(sharedPaths, { goal = goal, waypoints = waypoints, at = os.clock() })
			if #sharedPaths > MV.Share.max then
				table.remove(sharedPaths, 1)
			end
		end
		if nav.goal ~= goal then
			return -- (a new goal meanwhile)
		end
		if found then
			nav.waypoints = waypoints
			nav.index = math.min(2, #nav.waypoints)
		else
			stats.pathFails += 1
			nav.waypoints = {}
			nav.index = 1
		end
	end)
	return true
end

-- `v` moved inside the map's walls (Config/Bots.Move.Edge): paths don't see the walls, so a goal beyond them leaves
-- the bot pressed against one
local function inside(b: Bot, v: Vector3): Vector3
	if b.mode ~= "Normal" then
		return v
	end
	local x, z = Rules.inside(v.X, v.Z, Map.bounds, MV.Edge)
	return if x == v.X and z == v.Z then v else Vector3.new(x, v.Y, z)
end

local function setGoal(b: Bot, goal: Vector3?, now: number)
	local nav = b.nav
	if goal == nil then
		nav.goal = nil
		nav.waypoints = {}
		return
	end
	local g = inside(b, goal :: Vector3)
	local changed = nav.goal == nil or (flat((nav.goal :: Vector3) - g)).Magnitude > 4
	if changed then
		nav.goal = g
		nav.waypoints = {}
		nav.jumps, nav.repaths = 0, 0
	end
	local repath = if b.mode == "Normal" then NV.repath else MV.Repath
	if not nav.computing and (changed or nav.pathAt < 0 or now - nav.pathAt > repath) then
		nav.goal = g
		if not computePath(b, g) and changed then
			nav.pathAt = -1 -- (asked again next think)
		end
	end
end

-- walks along the path (or straight at the goal while there's none); stuck: jumps, then a fresh path, then a step aside
local function follow(b: Bot, now: number)
	local nav = b.nav
	local humanoid, root = b.humanoid :: Humanoid, b.root :: BasePart
	local target: Vector3? = if nav.direct then inside(b, nav.direct :: Vector3) else nil
	if not target and nav.goal then
		local wp = nav.waypoints[nav.index]
		-- a door on the way (a "Door" link's waypoint): opened from its reach, then a moment while it swings
		if wp and wp.Label == IndoorCfg.Links.door then
			local d = flat(wp.Position - root.Position).Magnitude
			local door = if d <= IN.doorReach then Doors.nearest(wp.Position, 8) else nil
			local shut = door ~= nil and not Doors.isOpen(door)
			if door and shut and Doors.openFor(b.m :: Model, door) then
				nav.doorAt = now
				stats.doors += 1
			end
			if door and Buildings.waitForDoor(true, d, shut, now - nav.doorAt, IN) then
				humanoid:MoveTo(root.Position)
				nav.sampleAt, nav.samplePos = now, root.Position
				return
			end
		end
		if wp then
			-- (thinking less often, it counts a waypoint reached from farther, so it never stops at one)
			local arrive = math.max(MV.Arrive, humanoid.WalkSpeed / b.thinkHz * 0.6)
			if flat(wp.Position - root.Position).Magnitude < arrive then
				nav.index += 1
				wp = nav.waypoints[nav.index]
			end
		end
		if wp then
			target = wp.Position
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
		else
			target = nav.goal
		end
	end
	if not target or flat((target :: Vector3) - root.Position).Magnitude < 1 then
		nav.direct = nil
		humanoid:MoveTo(root.Position)
		nav.sampleAt, nav.samplePos = now, root.Position
		return
	end
	humanoid:MoveTo(target :: Vector3)
	-- progress check
	local elapsed = now - nav.sampleAt
	if elapsed >= MV.StuckWindow then
		local moved = flat(root.Position - nav.samplePos).Magnitude
		if Rules.stuck(moved, elapsed, MV.StuckWindow, MV.StuckDistance, MV.StuckStale) then
			stats.stuck += 1
			if nav.direct then
				nav.direct = nil -- (a straight step into something: give it up)
			elseif nav.jumps < MV.StuckJumps then
				nav.jumps += 1
				humanoid.Jump = true
			elseif nav.repaths < MV.StuckRepaths and nav.goal and not nav.computing then
				if computePath(b, nav.goal :: Vector3, true) then
					nav.repaths += 1
					nav.jumps = 0
				end
			else
				stats.sidesteps += 1
				nav.jumps, nav.repaths = 0, 0
				local a = random:NextNumber() * 2 * math.pi
				nav.direct = root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * MV.Sidestep
			end
		end
		nav.sampleAt, nav.samplePos = now, root.Position
	end
end

-- a step left or right of the line to `toward` (sometimes a little forward or back): the strafe in the open
local function strafeStep(b: Bot, toward: Vector3?, now: number)
	local root = b.root :: BasePart
	local nav = b.nav
	local arrived = nav.direct == nil or flat((nav.direct :: Vector3) - root.Position).Magnitude < 1.5
	if now < b.strafeAt and not arrived then
		return
	end
	b.strafeAt = now + random:NextNumber(MV.StrafeEvery[1], MV.StrafeEvery[2])
	local to = if toward then flat((toward :: Vector3) - root.Position) else flat(root.CFrame.LookVector)
	local fwd = if to.Magnitude > 1e-3 then to.Unit else Vector3.zAxis
	local side = fwd:Cross(Vector3.yAxis) * (if random:NextNumber() < 0.5 then -1 else 1)
	-- a teammate close by: the step goes away from them (spreading out)
	local mate = mateNear(b, root.Position, brainCfg.SpreadMin)
	if mate and side:Dot(root.Position - mate :: Vector3) < 0 then
		side = -side
	end
	local step = side * random:NextNumber(MV.Strafe[1], MV.Strafe[2]) + fwd * random:NextNumber(-2, 2)
	nav.direct = root.Position + step
	nav.goal = nil
end

-- thinking -----------------------------------------------------------------------------------------------------------

-- the gun put away (the wave line: idle, empty hands) and drawn again when the wave goes
local function stow(b: Bot)
	local m, tool = b.m :: Model, b.tool :: Tool
	b.stowed = true
	tool.Parent = nil
	sling(b, true)
	if b.turn then
		(b.turn :: AlignOrientation).Enabled = false
	end
	if b.anim then
		(b.anim :: Animate.Handle).update(0, "none", 0)
	end
	DevDummies.own(m) -- (a joint gone: the body's physics kept the server's)
end

local function draw(b: Bot)
	local m, tool = b.m :: Model, b.tool :: Tool
	b.stowed = false
	tool.Parent = m
	sling(b, false)
	local torso = m:FindFirstChild("Torso") :: BasePart?
	if b.grip and torso then
		(b.grip :: Motor6D).Part0 = torso
	end
	if b.anim then
		(b.anim :: Animate.Handle).equip()
	end
	DevDummies.own(m)
end

-- actions besides fighting (Normal; Rules/BotActions, Config/Bots.Actions) -----------------------------------------

-- its gun put away for an action (a heal, a drag, a throw), or taken out again
local function putAway(b: Bot, on: boolean)
	if on == b.away then
		return
	end
	local m, tool = b.m :: Model, b.tool :: Tool
	b.away = on
	sling(b, on)
	if on then
		tool.Parent = nil
		if b.anim then
			(b.anim :: Animate.Handle).update(0, "none", 0)
		end
	else
		tool.Parent = m
		local torso = m:FindFirstChild("Torso") :: BasePart?
		if b.grip and torso then
			(b.grip :: Motor6D).Part0 = torso
		end
		if b.anim then
			(b.anim :: Animate.Handle).equip()
		end
	end
	DevDummies.own(m) -- (a joint made or broken: the body's physics kept the server's)
end

-- turned to face `at` (the body it drags, the one it heals, where its grenade goes)
local function face(b: Bot, at: Vector3)
	local root, turn = b.root :: BasePart, b.turn :: AlignOrientation
	local f = flat(at - root.Position)
	if f.Magnitude > 1e-3 then
		(b.humanoid :: Humanoid).AutoRotate = false
		turn.CFrame = CFrame.lookAt(Vector3.zero, f.Unit)
		turn.Enabled = true
	end
end

-- its shovel in its hands (made the first time; its gun put away), or put back
local function holdShovel(b: Bot, on: boolean)
	local m = b.m :: Model
	if not on then
		if b.shovel and (b.shovel :: Tool).Parent ~= nil then
			(b.shovel :: Tool).Parent = nil
		end
		return
	end
	putAway(b, true)
	if not b.shovel then
		local made, t = pcall(Armory.tool, "shovel", b.kit)
		if made then
			b.shovel = t
		end
	end
	local t = b.shovel
	if t and t.Parent ~= m then
		local hold = t:FindFirstChild("Hold", true) :: Motor6D?
		t.Parent = m
		if hold then
			hold.Part0 = m:FindFirstChild("Torso") :: BasePart?
		end
		DevDummies.own(m)
	end
end

-- the action over (done, given up, or cut short): the heal or the drag stopped, the grenades put back, the gun out
local function finish(b: Bot)
	local act = b.act
	if not act then
		return
	end
	b.act = nil
	local m = b.m
	if m then
		if act.kind == "Heal" then
			Healing.stopAs(m)
		elseif act.kind == "Drag" then
			Dragging.stopAs(m)
		end
	end
	if b.shovel then
		holdShovel(b, false)
	end
	local g = b.grenades
	if g then
		local left = g:GetAttribute("Count")
		if type(left) ~= "number" or left < 1 then
			b.grenades = nil -- (the last one thrown: the Tool is gone)
		elseif g.Parent ~= nil then
			g.Parent = nil
		end
	end
	if b.anim then
		(b.anim :: Animate.Handle).stop()
	end
	if b.turn then
		(b.turn :: AlignOrientation).Enabled = false
	end
	if b.humanoid then
		(b.humanoid :: Humanoid).AutoRotate = true
	end
	if m and not Ragdoll.active(m) then
		putAway(b, false)
	else
		b.away = false -- (a knock: the get-up draws the gun, see spawnBody)
	end
end

-- the throw's look from its head toward `at` (a soldier's torso): the low arc that lands `short` of it
local function throwLook(b: Bot, at: Vector3): Vector3
	local head = (b.head :: BasePart).Position
	local off = flat(at - head)
	local name = (b.grenades :: Tool):GetAttribute("Weapon")
	local speed = (GrenadeCfg.Types :: any)[name].speed
	local ground = at.Y - CV.chest -- (about where its feet are)
	local pitch = Actions.lobPitch(off.Magnitude * AC.Grenade.short, ground - head.Y, speed, workspace.Gravity)
		or math.rad(45)
	pitch -= math.rad(GrenadeCfg.Throw.loft)
	local u = if off.Magnitude > 1e-3 then off.Unit else Vector3.zAxis
	return u * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
end

-- the build job a bot takes on its side's list (Rules/BotBuild.pick): an Engineer any within Build.take; a digger (half
-- a holding squad, any class) a trench run or square within Build.take, wire wanting swings within Build.help; nil if
-- none
local function pickJob(b: Bot): BuildJob?
	local sb = buildLists[b.side :: string]
	if not sb or #sb.open == 0 then
		return nil
	end
	local engineer = Loadouts.classOf(b.m :: Model) == "Engineer"
	if not engineer and not b.digger then
		return nil
	end
	local root = (b.root :: BasePart).Position
	local held: { [BuildJob]: boolean } = {}
	for _, o in bots do
		local a = o.act
		if a and a.kind == "Build" and a.job then
			held[a.job :: BuildJob] = true
		end
	end
	local list: { BotBuild.Job } = {}
	local taken: { [number]: boolean } = {}
	for k, r in sb.open do
		local at = r.at
		local j = r.job
		list[k] = {
			key = j.key,
			x = if at then at.X else j.x,
			z = if at then at.Z else j.z,
			fx = j.fx,
			fz = j.fz,
			work = r.model ~= nil,
		}
		local d = flat(Vector3.new(list[k].x, 0, list[k].z) - root).Magnitude
		local fits = engineer or j.key == "Trench" or (j.key == "Wire" and r.model ~= nil and d <= BD.help)
		taken[k] = held[r] == true or not fits
	end
	local k = BotBuild.pick(list, root.X, root.Z, BD.take, taken, {}, nil)
	return if k then sb.open[k] else nil
end

-- what to do besides fighting, if anything (drag > heal > build > grenade)
local function weigh(b: Bot, now: number)
	b.actAt = now + AC.every
	local m, root = b.m :: Model, b.root :: BasePart
	if Healing.busy(m) then
		return -- (being healed: it stays for it)
	end
	local all, n = soldiersNow()
	local kit = m:GetAttribute("Kit")
	local spot = knownSpot(b, now) or b.lastSeenAt
	local mates: { Actions.Mate } = {}
	local who: { Soldier } = {}
	local near = math.max(AC.Drag.within, AC.Heal.within)
	for k = 1, n do
		local o = all[k]
		if o.model ~= m and friendly(m, kit, o) then
			local d = flat(o.pos - root.Position).Magnitude
			if d <= near then
				local busy = Healing.busy(o.model) or o.model:GetAttribute("Dragged") == true
				table.insert(mates, { distance = d, health = o.health, down = o.down, busy = busy, exposed = false })
				table.insert(who, o)
			end
		end
	end
	-- a downed teammate in sight of where the enemy is
	if spot then
		local eyeAt = (spot :: Vector3) + Vector3.yAxis * Cfg.Eye
		for i, mt in mates do
			if mt.down and not mt.busy and mt.distance <= AC.Drag.within and raysLeft > 0 then
				rayParams.FilterDescendantsInstances = { m }
				local hit = workspace:Raycast(eyeAt, who[i].pos - eyeAt, rayParams)
				stats.rays += 1
				raysLeft -= 1
				mt.exposed = hit == nil or hit.Instance:IsDescendantOf(who[i].model)
			end
		end
	end
	local i = Actions.dragPick(mates, AC.Drag)
	if i and spot then
		b.act = { kind = "Drag", who = who[i].model, from = spot, started = now }
		return
	end
	local sq = b.squad and squads[b.squad :: string]
	local pushing = sq ~= nil and (sq :: SquadState).sq.phase == "Assault"
	local sinceThreat = if b.threatAt then now - (b.threatAt :: number) else math.huge
	local sinceHurt = if b.hurtAt then now - (b.hurtAt :: number) else math.huge
	if not pushing and Actions.calm(sinceThreat, sinceHurt, AC.Heal.calm) then
		i = Actions.healPick(mates, AC.Heal)
		if i then
			b.act = { kind = "Heal", who = who[i].model, started = now }
			return
		end
	end
	-- a job on its side's build list, when calm and it sees no enemy (Config/Bots.Build)
	local seen = b.target ~= nil and (b.target :: Target).visible
	if not pushing and not seen and b.side and Actions.calm(sinceThreat, sinceHurt, BD.calm) then
		local r = pickJob(b)
		if r then
			b.act = { kind = "Build", job = r, started = now }
			return
		end
	end
	-- a Grenadier's grenade at what its squad knows of the enemy
	local G = AC.Grenade
	if
		not b.grenades
		or now - b.threwAt < G.every
		or (sq and now - ((sq :: SquadState).threwAt or -math.huge) < G.squadEvery)
	then
		return
	end
	local known: { Known } = if sq then (sq :: SquadState).known else {}
	if not sq and b.target and b.lastSeenAt then
		known = { { model = (b.target :: Target).model, pos = b.lastSeenAt :: Vector3, at = now } }
	end
	local enemies: { Actions.Enemy } = {}
	local points: { Vector3 } = {}
	for _, k in known do
		local model = k.model
		local h = model and model:FindFirstChildOfClass("Humanoid")
		local part = model and aimPart(model :: Model)
		if model and h and part and h.Health > 0 and now - k.at <= SQ.knownFor then
			local visible = b.target ~= nil and (b.target :: Target).model == model and (b.target :: Target).visible
			local p = if visible then part.Position else k.pos
			table.insert(enemies, {
				x = p.X,
				z = p.Z,
				distance = flat(p - root.Position).Magnitude,
				visible = visible,
				hiddenFor = if visible then 0 else now - k.at,
			})
			table.insert(points, p)
		end
	end
	if #enemies == 0 then
		return
	end
	local friends = {}
	for k = 1, n do
		local o = all[k]
		if o.model ~= m and friendly(m, kit, o) then
			table.insert(friends, { x = o.pos.X, z = o.pos.Z })
		end
	end
	i = Actions.grenadeAt(enemies, friends, G)
	if i then
		b.act = { kind = "Throw", at = points[i], started = now }
	end
end

-- the walk's pose while it acts (the gun away: empty hands)
local function actPose(b: Bot)
	local speed = flat((b.root :: BasePart).AssemblyLinearVelocity).Magnitude
	if b.anim then
		(b.anim :: Animate.Handle).update(speed, "none", 0)
	end
end

-- the grenade out of the pack: the pin, the wind-up, the throw (Config/Grenades.Throw: the release into the throw's
-- animation), then the gun back
local function throwSequence(b: Bot, act: Act)
	local m, g = b.m :: Model, b.grenades :: Tool
	putAway(b, true)
	local hold = g:FindFirstChild("Hold", true) :: Motor6D?
	g.Parent = m
	if hold then
		hold.Part0 = m:FindFirstChild("Torso") :: BasePart?
	end
	DevDummies.own(m)
	local holds = W[g:GetAttribute("Weapon") :: string].holds :: any
	if b.anim then
		(b.anim :: Animate.Handle).play(holds.pin)
	end
	task.spawn(function()
		task.wait(AC.Grenade.hold)
		if b.act ~= act or b.m ~= m or Ragdoll.active(m) then
			return
		end
		if b.anim then
			(b.anim :: Animate.Handle).play(holds.throw)
		end
		task.wait(GrenadeCfg.Throw.release)
		if b.act ~= act or b.m ~= m or not b.head then
			return
		end
		if Grenades.throwAs(m, throwLook(b, act.at :: Vector3)) then
			stats.throws += 1
			b.threwAt = os.clock()
			local sq = b.squad and squads[b.squad :: string]
			if sq then
				(sq :: SquadState).threwAt = b.threwAt
			end
			say(b, "Grenade")
		end
		task.wait(math.max(GrenadeCfg.Throw.length - GrenadeCfg.Throw.release, 0))
		if b.act == act then
			act.phase = "done"
		end
	end)
end

-- the healer's animations, as src/client/Healing plays a player's: the grab, then the wrap or the open and press
local function healAnimations(b: Bot, act: Act)
	local m = b.m :: Model
	local kind = m:GetAttribute("Healing")
	local A = HealCfg.Animations :: any
	local function later(delay: number, name: string)
		task.delay(delay, function()
			if b.act == act and b.anim and m:GetAttribute("Healing") == kind then
				(b.anim :: Animate.Handle).play(A[name].id)
			end
		end)
	end
	later(0, "grab")
	if kind == "Bandage" then
		later(HealCfg.Grab.time, "wrap")
	else
		later(HealCfg.Grab.time, "open")
		later(HealCfg.Grab.time + HealCfg.Open.time, "press")
	end
end

-- standing still facing `at` (a heal under way, a throw)
local function standFacing(b: Bot, at: Vector3, now: number)
	setGoal(b, nil, now)
	follow(b, now)
	face(b, at)
end

-- the piece a bot just laid for `job`: its side's work of the key nearest the spot (a trench: its first end), or nil
local function laidFor(b: Bot, job: BotBuild.Job): Build.Work?
	local best, bestD = nil, BD.match
	for _, w in Build.worksOf(b.kit) do
		local d = math.sqrt((w.at.X - job.x) ^ 2 + (w.at.Z - job.z) ^ 2)
		if w.key == job.key and d <= bestD then
			best, bestD = w, d
		end
	end
	return best
end

-- a refused lay: its spot moved across (Rules/BotBuild.nudge), after Build.tries the planned spot again a while later
local function refused(r: BuildJob, now: number)
	stats.refused += 1
	r.tries += 1
	local base = r.base
	if r.tries >= BD.tries then
		r.tries, r.job, r.waitUntil, r.open = 0, base, now + BD.retry, false
		return
	end
	if r.run then
		-- a trench run keeps its start (it joins the last run there): its far end swings aside
		local j = r.job
		local bx, bz = BotTrenches.swing(j.x, j.z, base.ex :: number, base.ez :: number, r.tries, BD.nudge)
		r.job = { key = base.key, x = j.x, z = j.z, ex = bx, ez = bz, fx = base.fx, fz = base.fz }
		return
	end
	local x, z = BotBuild.nudge(base, r.tries, BD.nudge)
	local dx, dz = x - base.x, z - base.z
	r.job = {
		key = base.key,
		x = x,
		z = z,
		ex = if base.ex then (base.ex :: number) + dx else nil,
		ez = if base.ez then (base.ez :: number) + dz else nil,
		fx = base.fx,
		fz = base.fz,
	}
end

-- a build, one think of it: to the job, the piece laid (once), then Build swings at it until it wants none, the
-- shovel in hand; given up when it's shot at, sees an enemy, the job leaves the list or takes too long
local function doBuild(b: Bot, act: Act, now: number): boolean
	local r = act.job :: BuildJob
	local m, humanoid, root = b.m :: Model, b.humanoid :: Humanoid, b.root :: BasePart
	local sinceThreat = if b.threatAt then now - (b.threatAt :: number) else math.huge
	local hurt = b.hurtAt ~= nil and (b.hurtAt :: number) > act.started
	local seen = b.target ~= nil and (b.target :: Target).visible
	if not r.open or now - act.started > BD.seconds or hurt or sinceThreat < BD.calm or seen then
		finish(b)
		return false
	end
	local job = r.job
	local f = Vector3.new(job.fx, 0, job.fz)
	local spot = if r.model and r.at then r.at :: Vector3 else Routes.ground(job.x, job.z)
	-- (it lays a piece from behind it, its own side; it swings at one from where it is)
	local reach = if r.model then BuildCfg.SwingReach - 1 else BD.stand + 2
	if flat(spot - root.Position).Magnitude > reach then
		humanoid.WalkSpeed = M.WalkSpeed
		setGoal(b, if r.model then spot else spot - f * BD.stand, now)
		follow(b, now)
		actPose(b)
		return true
	end
	holdShovel(b, true)
	if not act.phase then
		act.phase = "dig"
		if b.anim then
			(b.anim :: Animate.Handle).play(W.shovel.holds.dig, true)
		end
	end
	standFacing(b, if r.model then spot else spot + f, now)
	if not r.model then
		local reason = if job.key == "Trench"
			then Build.planAs(m, spot, Routes.ground(job.ex :: number, job.ez :: number))
			else Build.placeAs(m, job.key, spot, f)
		if reason then
			refused(r, now)
			finish(b)
			return false
		end
		stats.laid += 1
		if r.run then
			stats.runs += 1
		end
		local w = laidFor(b, job)
		if not w then
			finish(b) -- (it is on the next tick's list)
			return false
		end
		r.model, r.at, r.left = w.model, w.at, w.left
		act.swingAt = now + Build.swingGap()
		return true
	end
	if now >= (act.swingAt or 0) then
		local reason = Build.workAs(m, r.model :: Model, "Build")
		if reason == nil then
			stats.swings += 1
			act.swingAt = now + Build.swingGap()
		elseif reason ~= "Too soon" then
			finish(b) -- (whole now, or gone)
			return false
		end
	end
	return true
end

-- the action under way, one think of it; false once it's over (the bot fights again this think)
local function doAct(b: Bot, now: number): boolean
	local act = b.act :: Act
	local m, humanoid, root = b.m :: Model, b.humanoid :: Humanoid, b.root :: BasePart
	-- (the gun on the pack's strap from the start: walking to it with the gun in hands and no hold left it through the
	-- body, user 2026-11-02)
	putAway(b, true)
	if act.kind == "Build" then
		return doBuild(b, act, now)
	end
	if act.kind == "Throw" then
		if act.phase == "done" or now - act.started > AC.Grenade.hold + GrenadeCfg.Throw.length + 1 then
			finish(b)
			return false
		end
		if not act.phase then
			act.phase = "throw"
			throwSequence(b, act)
		end
		standFacing(b, act.at :: Vector3, now)
		return true
	end

	local other = act.who :: Model
	local oh = other.Parent and other:FindFirstChildOfClass("Humanoid")
	local part = aimPart(other)
	if not oh or not part or oh.Health <= 0 or (b.hurtAt and (b.hurtAt :: number) > act.started) then
		finish(b) -- (gone, dead, or it was hit meanwhile)
		return false
	end
	local at = (part :: BasePart).Position
	local dist = flat(at - root.Position).Magnitude

	if act.kind == "Drag" then
		if act.phase == "pull" and not Dragging.dragging(m) then
			-- let go (there, caught on something, up again): then a heal if they're hurt
			finish(b)
			if oh.Health / math.max(oh.MaxHealth, 1) < AC.Heal.below then
				b.act = { kind = "Heal", who = other, started = now }
				return true
			end
			return false
		end
		if now - act.started > AC.Drag.seconds or (act.phase == nil and not Ragdoll.active(other)) then
			finish(b)
			return false
		end
		if act.phase == nil then
			if dist > DragCfg.Range - 1 then
				humanoid.WalkSpeed = M.SprintSpeed
				setGoal(b, at, now)
				follow(b, now)
				actPose(b)
				return true
			end
			putAway(b, true)
			if not Dragging.startAs(m, other) then
				finish(b)
				return false
			end
			act.phase = "pull"
			stats.drags += 1
			if b.anim then
				(b.anim :: Animate.Handle).play(DragCfg.Animation.id, true)
			end
			-- where to: cover from the enemy spot (the cover search's rings), else straight away from it
			b.threatFrom = (act.from :: Vector3) + Vector3.yAxis * Cfg.Eye
			b.cover = nil
			findCover(b, now)
		end
		if not act.to then
			if b.coverJob then
				coverStep(b)
			end
			if b.cover then
				act.to = b.cover
			elseif not b.coverJob then
				local back = flat(root.Position - (act.from :: Vector3))
				back = if back.Magnitude > 1e-3 then back.Unit else -flat(root.CFrame.LookVector)
				act.to = inside(b, root.Position + back * AC.Drag.cover)
			end
		end
		if act.to and flat((act.to :: Vector3) - root.Position).Magnitude < MV.Arrive then
			Dragging.stopAs(m) -- (there: a heal next think, if they're hurt)
			return true
		end
		humanoid.WalkSpeed = DragCfg.Speed
		setGoal(b, act.to, now)
		follow(b, now)
		face(b, at)
		return true
	end

	-- a heal
	if act.phase == "heal" then
		if not Healing.busy(m) then
			finish(b) -- (done, or broken off)
			return false
		end
		standFacing(b, at, now)
		return true
	end
	if oh.Health >= oh.MaxHealth or now - act.started > AC.Heal.seconds or Healing.busy(other) then
		finish(b)
		return false
	end
	if dist > AC.Heal.reach then
		humanoid.WalkSpeed = if dist > MV.SprintFrom then M.SprintSpeed else M.WalkSpeed
		setGoal(b, at, now)
		follow(b, now)
		actPose(b)
		return true
	end
	putAway(b, true)
	if not Healing.startAs(m, other) then
		finish(b)
		return false
	end
	act.phase = "heal"
	stats.heals += 1
	say(b, "Heal")
	healAnimations(b, act)
	standFacing(b, at, now)
	return true
end

local function think(b: Bot, now: number, d: Rules.Difficulty)
	local m, humanoid, root, tool = b.m :: Model, b.humanoid :: Humanoid, b.root :: BasePart, b.tool :: Tool
	local entry = Firing.entry(tool)
	if not entry then
		return
	end
	if Ragdoll.active(m) or m:GetAttribute("GetUp") ~= nil then
		(b.turn :: AlignOrientation).Enabled = false
		if not Ragdoll.active(m) then
			humanoid:MoveTo(root.Position) -- getting up (src/server/DevDummies.getUp): standing still meanwhile
		end
		finish(b)
		return -- (down: nothing until it is up again)
	end
	if m:GetAttribute(FrontCfg.HoldAttribute) ~= nil then
		finish(b)
		-- standing in the wave line until the wave goes: idle, nothing in the hands (user 2026-11-01)
		if not b.stowed then
			stow(b)
		end
		return
	end
	if b.stowed then
		draw(b)
	end
	-- the body's physics stays the server's: any joint made or broken (a helmet knocked off, the gun drawn) hands it to
	-- the nearest player, and a body a player owns ignores the server's get-up and lies there in Physics
	local owned, owner = pcall(root.GetNetworkOwner, root)
	if owned and owner ~= nil then
		DevDummies.own(m)
		stats.reowned += 1
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Physics then
		DevDummies.getUp(m, humanoid) -- (left lying after a knock)
		stats.stoodUp += 1
		return
	end
	-- how often it thinks and looks, by the nearest player's distance (Rules/Bots.lod)
	local nearest = math.huge
	for _, p in Players:GetPlayers() do
		local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if pr then
			nearest = math.min(nearest, flat(pr.Position - root.Position).Magnitude)
		end
	end
	local fighting = b.target ~= nil
		or (b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.ThreatMemory)
		or (b.hurtAt ~= nil and now - (b.hurtAt :: number) < brainCfg.ThreatMemory)
	b.thinkHz, b.senseHz = Rules.lod(nearest, fighting, BG.lod)
	b.nearest = nearest
	b.lod = if b.thinkHz >= BG.lod.near.think
		then "near"
		elseif b.thinkHz >= BG.lod.middle.think then "middle"
		else "distant"
	debug.profilebegin("Bots.sense")
	if now >= b.nextSense and sense(b, d, now) then
		b.nextSense = now + 1 / b.senseHz
	elseif b.target then
		-- between looks: the same target, its distance kept fresh
		local t = b.target :: Target
		local part = aimPart(t.model)
		local h = t.model:FindFirstChildOfClass("Humanoid")
		if not part or not h or h.Health <= 0 or not t.model.Parent then
			b.target = nil
		else
			t.distance = (part.Position - eye(b)).Magnitude
		end
	end
	debug.profileend()
	-- Normal: a drag, a heal or a grenade instead of fighting for a while (Rules/BotActions)
	if b.mode == "Normal" then
		debug.profilebegin("Bots.act")
		if not b.act and now >= b.actAt then
			weigh(b, now)
		end
		local acting = b.act ~= nil and doAct(b, now)
		debug.profileend()
		if acting then
			return
		end
	end
	-- cover from the threat, while there is one
	local threatened = b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.ThreatMemory
	local floor = b.postFloor
	local engaged = threatened or b.spotted or b.brain.targetId ~= nil
	if floor and engaged and flat((floor :: Vector3) - root.Position).Magnitude <= TR.step + 3 then
		-- at its fire step: the trench floor below is its cover (Rules/BotTrenches), no search
		b.cover, b.coverFrom, b.coverAt, b.coverJob = floor, b.threatFrom, now, nil
	elseif b.coverJob then
		coverStep(b)
	elseif engaged and now - b.coverAt >= CV.every then
		findCover(b, now)
	elseif not threatened and not b.spotted and b.brain.targetId == nil and b.brain.state ~= "Cover" then
		b.cover = nil
	end
	local coverState: Rules.CoverState = if not b.cover
		then "none"
		elseif flat((b.cover :: Vector3) - root.Position).Magnitude < CV.at then "at"
		else "going"

	local s = entry.state
	F.settle(s, now)
	local target = b.target
	local senses: Rules.Senses = {
		now = now,
		health = humanoid.Health / math.max(humanoid.MaxHealth, 1),
		magazine = s.magazine,
		chambered = s.chambered,
		spent = s.spent,
		busy = F.busy(s, now, 0),
		loading = s.load ~= nil,
		capacity = entry.gun.capacity + 1,
		auto = entry.gun.auto == true,
		target = if target then { id = target.model, distance = target.distance, visible = target.visible } else nil,
		hurtAt = b.hurtAt,
		threatAt = b.threatAt,
		spotted = b.spotted,
		cover = coverState,
		push = b.push,
		role = b.role,
		suppressed = shakenNow(b, now),
		suppress = b.role == "Support" and knownSpot(b, now) ~= nil,
	}
	local was = b.brain.state
	local hadTarget = b.brain.targetId ~= nil
	local intent = Rules.step(b.brain, senses, brainCfg, d, random:NextNumber())
	if b.brain.state ~= was and b.brain.state == "Peek" then
		stats.peeks += 1
	end
	-- callouts on what just changed
	if not hadTarget and b.brain.targetId ~= nil then
		say(b, "Spotted")
	elseif b.brain.state ~= was and b.brain.state == "Cover" then
		say(b, "Cover")
	elseif intent.reload then
		say(b, "Reload")
	end

	-- where to go
	debug.profilebegin("Bots.move")
	local zone, radius = objective(b)
	local goal: Vector3? = nil
	local targetPart = if target then aimPart(target.model) else nil
	local suppressAt = if b.role == "Support" and not targetPart then knownSpot(b, now) else nil
	local aimAt: Vector3? = if targetPart then targetPart.Position else (suppressAt or b.lastSeenAt)
	local move = intent.move
	-- Normal: a hunt that would lead it far from its order's sector gives way to the order
	if move == "Hunt" and b.mode == "Normal" and zone and b.lastSeenAt then
		if flat((b.lastSeenAt :: Vector3) - (zone :: Vector3)).Magnitude > NV.leash then
			move = "Objective"
		end
	end
	if move == "Objective" and zone then
		local z = zone :: Vector3
		if b.flank and flat((b.flank :: Vector3) - root.Position).Magnitude < MV.Arrive * 3 then
			b.flank = nil
		end
		local inZone = flat(root.Position - z).Magnitude < radius * MV.InZoneShare
		if inZone and not b.reachedZone then
			b.reachedZone = true
			stats.toZone += now - b.spawnedAt
			stats.toZoneCount += 1
		end
		if inZone then
			b.flank = nil
			local there = b.wander and flat((b.wander :: Vector3) - root.Position).Magnitude < MV.Arrive
			if not b.wander or now >= b.wanderAt or there then
				local a = random:NextNumber() * 2 * math.pi
				local r = radius * MV.WanderShare * math.sqrt(random:NextNumber())
				b.wander = z + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				b.wanderAt = now + MV.WanderEvery
			end
		end
		-- (Normal: outside the zone its squad's route: a waypoint, a bound's stop, the approach spot; then its own
		-- stand point there)
		goal = if inZone and b.role ~= "Move" then b.wander elseif b.flank then b.flank else (b.goal or b.stand or z)
		b.nav.direct = nil
	elseif move == "Hold" then
		-- on its spot (covering fire, or a hold spot in the zone); there, it stands
		local post = b.goal or b.post
		if post and flat((post :: Vector3) - root.Position).Magnitude > MV.Arrive then
			goal = post
		else
			b.nav.goal = nil
		end
		b.nav.direct = nil
	elseif move == "Hunt" then
		goal = b.lastSeenAt
		b.nav.direct = nil
	elseif move == "Push" then
		goal = aimAt
		b.nav.direct = nil
	elseif move == "Cover" and b.cover then
		goal = b.cover
		b.nav.direct = nil
	elseif move == "Peek" then
		-- back out to where it last saw the target, or a step from cover toward it
		local out = b.lastOpen
		if not out and aimAt then
			local to = flat((aimAt :: Vector3) - root.Position)
			out = root.Position + (if to.Magnitude > 1e-3 then to.Unit else Vector3.zAxis) * MV.PeekStep
		end
		b.nav.direct = out
		b.nav.goal = nil
	elseif move == "Away" and aimAt then
		local away = flat(root.Position - aimAt :: Vector3)
		away = if away.Magnitude > 1e-3 then away.Unit else -flat(root.CFrame.LookVector)
		goal = root.Position + away * brainCfg.RetreatDistance
		b.nav.direct = nil
	else
		-- Strafe (and anything with nowhere to go): never standing still
		strafeStep(b, aimAt or zone, now)
	end
	if goal then
		setGoal(b, goal, now)
	elseif move ~= "Strafe" and move ~= "Peek" and move ~= "Hold" then
		b.nav.goal = nil
	end
	if Healing.busy(m) then
		-- being healed: it stands for it (the heal breaks off once the two are Break studs apart)
		b.nav.goal, b.nav.direct = nil, nil
	end
	follow(b, now)
	debug.profileend()

	-- speed and facing
	local far = b.nav.goal ~= nil and flat((b.nav.goal :: Vector3) - root.Position).Magnitude > MV.SprintFrom
	local dash = move == "Cover" or move == "Away"
	humanoid.WalkSpeed = if dash or (not intent.aim and far)
		then M.SprintSpeed
		elseif intent.aim and move ~= "Push" then M.AimWalkSpeed
		else M.WalkSpeed
	local turn = b.turn :: AlignOrientation
	local pitch = 0
	local facing = true
	if intent.aim and aimAt then
		local to = (aimAt :: Vector3) - eye(b)
		local f = flat(to)
		if f.Magnitude > 1e-3 then
			humanoid.AutoRotate = false
			turn.CFrame = CFrame.lookAt(Vector3.zero, f.Unit)
			turn.Enabled = true
			local look = flat(root.CFrame.LookVector)
			facing = look.Magnitude > 1e-3 and look.Unit:Dot(f.Unit) > math.cos(math.rad(Cfg.FacingWithin))
		end
		pitch = math.clamp(math.deg(math.atan2(to.Y, math.max(f.Magnitude, 1e-3))), -Cfg.PitchLimit, Cfg.PitchLimit)
	elseif
		b.postFace
		and b.role == "Hold"
		and b.post
		and flat((b.post :: Vector3) - root.Position).Magnitude < MV.Arrive
	then
		-- at its window or doorway with nothing to aim at: looking out of it
		humanoid.AutoRotate = false
		turn.CFrame = CFrame.lookAt(Vector3.zero, b.postFace :: Vector3)
		turn.Enabled = true
	else
		humanoid.AutoRotate = true
		turn.Enabled = false
	end
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	local hold = if intent.aim
		then "aim"
		elseif speed > Loco.SprintAbove then "carry"
		elseif speed > Loco.IdleBelow then "walk"
		else "ready"
	if b.anim then
		(b.anim :: Animate.Handle).update(speed, hold, pitch)
	end

	-- the weapon
	if intent.stopLoad then
		Firing.actAs(m, "StopLoad")
	elseif intent.reload then
		Firing.actAs(m, "Reload")
	elseif intent.bolt then
		Firing.actAs(m, "Bolt")
	elseif intent.fire and facing and target and target.visible then
		local gun = tool:FindFirstChild("Gun") :: BasePart?
		local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
		local part = aimPart(target.model)
		if muzzle and part then
			local origin = muzzle.WorldPosition
			-- lead: aim where it will be, short of the lag the difficulty leaves
			local v = part.AssemblyLinearVelocity
			local lag = d.reaction * Cfg.Lag
			local p = part.Position
			local point = Vector3.new(
				Rules.lead(p.X, v.X, lag, d.lead),
				Rules.lead(p.Y, v.Y, lag, d.lead),
				Rules.lead(p.Z, v.Z, lag, d.lead)
			)
			local line = point - origin
			local cross = (v - line.Unit * v:Dot(line.Unit)).Magnitude
			local err = Rules.shakenAim(
				Rules.aimError(d, now - b.brain.seenAt - d.reaction, cross),
				shakenNow(b, now),
				brainCfg.SuppressedAim
			)
			local right, up = Rules.scatter(err, random:NextNumber(), random:NextNumber())
			local dir = (CFrame.lookAt(Vector3.zero, line.Unit) * CFrame.Angles(math.rad(up), -math.rad(right), 0)).LookVector
			if Firing.fireAs(m, origin, dir, random:NextInteger(1, 2147483646)) then
				stats.shots += 1
			end
		end
	elseif intent.fire and facing and suppressAt then
		-- covering fire at where an enemy was seen: a wider spread, no lead
		local gun = tool:FindFirstChild("Gun") :: BasePart?
		local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
		if muzzle then
			local origin = muzzle.WorldPosition
			local line = (suppressAt :: Vector3) - origin
			local err = Rules.shakenAim(d.aimFloor + brainCfg.SuppressSpread, shakenNow(b, now), brainCfg.SuppressedAim)
			local right, up = Rules.scatter(err, random:NextNumber(), random:NextNumber())
			local dir = (CFrame.lookAt(Vector3.zero, line.Unit) * CFrame.Angles(math.rad(up), -math.rad(right), 0)).LookVector
			if Firing.fireAs(m, origin, dir, random:NextInteger(1, 2147483646)) then
				stats.shots += 1
				stats.covering += 1
			end
		end
	end
end

-- the director --------------------------------------------------------------------------------------------------------

local nextJoin, nextLeave = 0, 0

-- tops the bots of `side` (nil: FFA's) up or down to `want`, one in or out at a time; true when it acted
local function balance(mode: string, side: string?, want: number, now: number): boolean
	local have = 0
	local dead: number? = nil
	local last: number? = nil
	for i, b in bots do
		if b.side == side then
			have += 1
			if b.deadAt and not dead then
				dead = i
			end
			last = i
		end
	end
	if have < want then
		if now >= nextJoin then
			nextJoin = now + (if mode == "Normal" then NV.joinEvery else Cfg.JoinEvery)
			add(mode, side)
			return true
		end
	elseif have > want and now >= nextLeave then
		-- a dead one goes first; else the one longest over the count
		if dead then
			nextLeave = now + Cfg.LeaveEvery
			remove(dead :: number)
			return true
		end
		local b = bots[last :: number]
		b.overSince = b.overSince or now
		if now - (b.overSince :: number) >= Cfg.LeaveAliveAfter then
			nextLeave = now + Cfg.LeaveEvery
			remove(last :: number)
			return true
		end
	elseif have <= want then
		for _, b in bots do
			if b.side == side then
				b.overSince = nil
			end
		end
	end
	return false
end

local function direct(now: number)
	local mode = liveMode()
	local pin = workspace:GetAttribute(Cfg.Attribute)
	local pinned = if type(pin) == "number" then pin else nil
	-- how many bots each group wants: FFA one group (""), Normal one a side (players first, under the governor's cap)
	local wants: { [string]: number } = {}
	if Cfg.Enabled and mode == "Normal" and Frontline.running() then
		local pair = FrontRules.parsePair(workspace:GetAttribute(FrontCfg.TeamsAttribute))
		local players = { West = 0, East = 0 }
		for _, p in Players:GetPlayers() do
			local side = FrontRules.sideOf(pair, Kits.next(p))
			if side then
				(players :: any)[side] += 1
			end
		end
		local cap = math.min(Cfg.Max.Normal, governor.cap)
		wants.West, wants.East = Rules.wantedSides(Cfg.Fill.Normal.perSide, players.West, players.East, cap, pinned)
	elseif Cfg.Enabled and mode == "FFA" and ZoneMatch.running() then
		local cap = math.min(Cfg.Max.FFA, governor.cap)
		wants[""] = Rules.wanted(Cfg.Fill.FFA, #Players:GetPlayers(), cap, pinned)
	end
	-- bots of another mode (or a group no longer wanted) go at once
	for i = #bots, 1, -1 do
		local b = bots[i]
		if b.mode ~= mode or wants[b.side or ""] == nil then
			remove(i)
		end
	end
	-- back from the dead after the respawn wait (or gone, if over the count)
	local have: { [string]: number } = {}
	for _, b in bots do
		local key = b.side or ""
		have[key] = (have[key] or 0) + 1
	end
	for i = #bots, 1, -1 do
		local b = bots[i]
		if not b then
			continue -- (removed while a body was being built)
		end
		local key = b.side or ""
		if b.deadAt and now >= (b.respawnAt or math.huge) then
			if have[key] > wants[key] then
				remove(i)
				have[key] -= 1
			else
				despawn(b)
				spawnBody(b)
			end
		elseif not b.m and not b.deadAt then
			spawnBody(b) -- (no spawn point earlier)
		end
	end
	for _, side in { "West", "East", "" } do
		local want = wants[side]
		if want and balance(mode :: string, if side == "" then nil else side, want, now) then
			return
		end
	end
end

-- Normal: a stand point in sector `i`'s zone, on the ground (a ray on terrain)
local function standPoint(i: number): Vector3
	local s = Map.sectors[i]
	local a = random:NextNumber() * 2 * math.pi
	local r = s.radius * NV.standShare * math.sqrt(random:NextNumber())
	local x, z = s.x + math.cos(a) * r, s.z + math.sin(a) * r
	local g = FrontCfg.GroundRay
	local hit = workspace:Raycast(Vector3.new(x, g.top, z), Vector3.new(0, -g.depth, 0), terrainOnly)
	return Vector3.new(x, if hit then hit.Position.Y else sectorPoint(i).Y, z)
end

-- the flat centre of `list`'s living bodies, or nil
local function centre(list: { Bot }): Vector3?
	local sum, n = Vector3.zero, 0
	for _, b in list do
		if b.root and alive(b) then
			sum += (b.root :: BasePart).Position
			n += 1
		end
	end
	return if n > 0 then sum / n else nil
end

-- a defender's hold spot in sector `i`: the best one fewest of the side's defenders stand on
local function holdSpot(side: string, i: number, taken: { [Vector3]: number }): Vector3?
	local spots = Routes.spots(i, side, true)
	if not spots or #spots == 0 then
		return nil
	end
	local best, bestAt = -math.huge, nil
	for _, sp in spots :: { Routes.Spot } do
		local v = Squads.scoreSpot(sp, taken[sp.pos] or 0, random:NextNumber(), RT.weights, RT.nearCap)
		if v > best then
			best, bestAt = v, sp.pos
		end
	end
	if bestAt then
		taken[bestAt] = (taken[bestAt] or 0) + 1
	end
	return bestAt
end

-- a window or doorway in sector `i`'s zone facing the enemy's way in, not taken (Rules/BotBuildings.pickHold), or nil
local function indoorHold(side: string, i: number, taken: { [Vector3]: number }): Indoors.Spot?
	local s = Map.sectors[i]
	local c = sectorPoint(i)
	local within = s.radius + IN.around
	local spots = {}
	for _, sp in indoorNear(c, within) do
		if sp.kind ~= "Cover" then
			table.insert(spots, sp)
		end
	end
	if #spots == 0 then
		return nil
	end
	local list, rolls = {}, {}
	for k, sp in spots do
		list[k] = asSpot(sp, taken[sp.at] or 0)
		rolls[k] = random:NextNumber()
	end
	local toward = if side == "West" then 1 else -1 -- (the enemy's home end: Map 1 runs west to east)
	local k = Buildings.pickHold(list, c.X, c.Z, within, toward, 0, rolls, IN)
	if not k then
		return nil
	end
	local sp = spots[k]
	taken[sp.at] = (taken[sp.at] or 0) + 1
	return sp
end

-- the nearest free fire step (`want` "step") or support-line place ("reserve") of a side's trenches to `p`, taken
local function trenchPost(sb: SideBuild, want: string, taken: { [Vector3]: number }, p: Vector3): TrenchPost?
	local best, bestD = nil, math.huge
	for _, tp in (if want == "step" then sb.steps else sb.reserve) do
		local d = flat(tp.pos - p).Magnitude
		if (taken[tp.pos] or 0) == 0 and d < bestD then
			best, bestD = tp, d
		end
	end
	if best then
		taken[best.pos] = 1
	end
	return best
end

-- Normal: `side`'s bots in squads by order and sector (Rules/BotSquads): each squad's phase this tick, its route
-- (lane, approach spot, a waypoint on the lane's side) and each member's role and goal
local function formSquads(side: string, counts: { { West: number, East: number } })
	local now = os.clock()
	local enemy = if side == "West" then "East" else "West"
	local groups: { [string]: { Bot } } = {}
	local order: { string } = {}
	for _, b in bots do
		if b.side == side and b.sector and b.order then
			local key = `{side}{b.order}{b.sector}`
			if not groups[key] then
				groups[key] = {}
				table.insert(order, key)
			end
			table.insert(groups[key], b)
		end
	end
	-- the lanes each sector's squads use already (a new squad takes the quietest)
	local crowd: { [number]: { [number]: number } } = {}
	for _, sq in squads do
		if sq.side == side and sq.seen == commandTick - 1 then
			crowd[sq.sector] = crowd[sq.sector] or {}
			crowd[sq.sector][sq.lane] = (crowd[sq.sector][sq.lane] or 0) + 1
		end
	end
	local taken: { [Vector3]: number } = {}
	for _, b in bots do
		if b.side == side and (b.postFace or b.postKind == "reserve") and b.post then
			-- (windows, fire steps and support-line places held already)
			taken[b.post :: Vector3] = (taken[b.post :: Vector3] or 0) + 1
		end
	end
	local sb = buildLists[side]
	local enemyLines = buildLists[enemy]
	for _, gkey in order do
		local list = groups[gkey]
		local first = list[1]
		local sector = first.sector :: number
		local defend = first.order == "Defend"
		local s = Map.sectors[sector]
		local c = sectorPoint(sector)
		for k, members in Squads.form(list, SQ.size, SQ.least) do
			local key = `{gkey}#{k}`
			local st = squads[key]
			if not st or st.sector ~= sector then
				local lanes = crowd[sector] or {}
				crowd[sector] = lanes
				local lane = Squads.quietLane(lanes)
				lanes[lane] = (lanes[lane] or 0) + 1
				st = { sq = Squads.new(), side = side, sector = sector, lane = lane, known = {}, seen = commandTick }
				squads[key] = st
			end
			local sqs = st :: SquadState
			sqs.seen = commandTick
			local mid = centre(members) or c
			-- the route: an approach spot in its lane, and on a long way a waypoint off to that side
			if not defend and not sqs.approach then
				local spots = Routes.spots(sector, side, false)
				if spots and #spots > 0 then
					local rolls = {}
					for i in spots :: { Routes.Spot } do
						rolls[i] = random:NextNumber()
					end
					local i =
						Squads.pickSpot(spots :: any, sqs.lane, crowd[sector] or {}, rolls, RT.weights, RT.nearCap)
					if i then
						local spot = (spots :: { Routes.Spot })[i]
						sqs.approach = spot.pos
						local way = flat(spot.pos - mid)
						local off = flat(spot.pos - c)
						local home = flat(mid - c)
						local across = if home.Magnitude > 1 then off - home.Unit * off:Dot(home.Unit) else Vector3.zero
						if way.Magnitude > RT.midFrom and across.Magnitude > 1 then
							local p = mid:Lerp(spot.pos, RT.midShare) + across.Unit * way.Magnitude * RT.laneOffset
							sqs.mid = Routes.ground(p.X, p.Z)
						end
					end
				end
			end
			if sqs.mid and flat((sqs.mid :: Vector3) - mid).Magnitude < SQ.arrive * 3 then
				sqs.mid = nil
			end
			-- the facts for its phase
			local living, ready, inZone = 0, 0, 0
			local moversThere = true
			for _, b in members do
				if b.root and alive(b) then
					living += 1
					local p = (b.root :: BasePart).Position
					if flat(p - c).Magnitude < s.radius then
						inZone += 1
					end
					if sqs.approach and flat(p - sqs.approach :: Vector3).Magnitude < SQ.arrive * 2 then
						ready += 1
					end
					if b.role == "Move" and b.stop and flat(p - b.stop :: Vector3).Magnitude > SQ.arrive then
						moversThere = false
					end
				end
			end
			if not sqs.approach then
				-- (no spots yet: ready once near the zone)
				for _, b in members do
					if b.root and alive(b) then
						local d = flat((b.root :: BasePart).Position - c).Magnitude
						if d < s.radius + RT.rings[#RT.rings] then
							ready += 1
						end
					end
				end
			end
			local contact = false
			for _, kn in sqs.known do
				if now - kn.at <= SQ.knownFor and flat(kn.pos - mid).Magnitude <= SQ.contact then
					contact = true
				end
			end
			local was = sqs.sq.phase
			Squads.step(sqs.sq, {
				now = now,
				defend = defend,
				contact = contact,
				ready = if living > 0 then ready / living else 0,
				inZone = if living > 0 then inZone / living else 0,
				ours = (counts[sector] :: any)[side],
				theirs = (counts[sector] :: any)[enemy],
				size = living,
				moversThere = moversThere,
			}, SQ)
			if sqs.sq.phase == "Assault" and was ~= "Assault" then
				stats.assaults += 1
				for _, b in members do
					if say(b, "Push") then
						break
					end
				end
			end
			-- pushing in: a known enemy inside a building there is cleared out (its Assault bots go to the spot by it)
			sqs.clear = nil
			if sqs.sq.phase == "Assault" then
				for _, kn in sqs.known do
					if now - kn.at <= SQ.knownFor and flat(kn.pos - c).Magnitude <= s.radius + IN.around then
						local near = indoorNear(kn.pos, IN.clearWithin)
						local nearSpots = {}
						for j, sp in near do
							nearSpots[j] = asSpot(sp, 0)
						end
						local by = Buildings.inside(nearSpots, kn.pos.X, kn.pos.Z, IN.clearWithin)
						if by then
							sqs.clear = near[by].at
							break
						end
						-- in an enemy trench: down into it, fighting along it (Rules/BotTrenches; "Yes, clear along them")
						local lines = enemyLines and enemyLines.squares
						local sqi = lines and BotTrenches.inSquare(kn.pos.X, kn.pos.Z, lines, TR.clearWithin)
						if lines and sqi then
							sqs.clear = lines[sqi].at
							break
						end
					end
				end
			end
			-- each member's role and goal
			local indoorHeld = 0
			for _, b in members do
				if b.role == "Hold" and b.postFace then
					indoorHeld += 1
				end
			end
			-- its trenches here (the side's front): fire steps, the support line, falling back from a lost fire trench
			local lines = sb ~= nil and sb.front == sector and #sb.steps > 0
			local fallback = lines and now < (sb :: SideBuild).fallbackUntil
			local holdN = 0
			local route = sqs.mid or sqs.approach or c
			local ahead = flat(route - mid)
			local right = if ahead.Magnitude > 1 then ahead.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
			for idx, b in members do
				local role = Squads.role(sqs.sq, idx)
				b.squad, b.role = key, role
				local p = if b.root then (b.root :: BasePart).Position else mid
				-- half of a squad holding the front digs (Config/Bots.Trenches.share), the rest stand guard
				b.digger = defend and sb ~= nil and sb.front == sector and BotTrenches.digs(idx, #members, TR.share)
				if role == "Hold" then
					holdN += 1
					-- in its trenches: every other holder in the support line until it stands to, the rest on the fire
					-- step; all back to the support line once the fire trench is lost
					local want: string? = nil
					if lines then
						local s2 = sb :: SideBuild
						if fallback then
							want = if #s2.reserve > 0 then "reserve" else nil
						elseif holdN % 2 == 0 and #s2.reserve > 0 and not s2.standTo then
							want = "reserve"
						else
							want = "step"
						end
					end
					local again = not b.post or b.postSector ~= sector or b.roleWas ~= "Hold"
					local tp = if want and (again or b.postKind ~= want)
						then trenchPost(sb :: SideBuild, want :: string, taken, p)
						else nil
					if tp then
						b.post, b.postFace, b.postKind = tp.pos, tp.face, want
						b.postFloor = tp.floor
						b.postSector = sector
					elseif again then
						-- a few at windows and doorways (Config/Bots.Indoors.perSquad), the rest outside
						local sp = if indoorHeld < IN.perSquad then indoorHold(side, sector, taken) else nil
						if sp then
							indoorHeld += 1
							b.post, b.postFace, b.postKind = sp.at, sp.face, "window"
						else
							b.post, b.postFace, b.postKind = holdSpot(side, sector, taken) or b.stand, nil, "open"
						end
						b.postFloor = nil
						b.postSector = sector
					end
					b.goal = b.post
				elseif role == "Assault" then
					b.goal = sqs.clear or b.stand
				elseif role == "Support" then
					if b.roleWas ~= "Support" then
						b.post = p -- (it holds where it stands, covering the others)
					end
					b.goal = b.post
				else
					local slot = route + right * ((idx - (#members + 1) / 2) * SQ.spread)
					if sqs.sq.phase == "Bound" then
						if b.roleWas ~= "Move" or not b.stop then
							local way = flat(slot - p)
							local hop = math.min(SQ.hop, way.Magnitude)
							local at = if way.Magnitude > 1 then p + way.Unit * hop else slot
							b.stop = Routes.ground(at.X, at.Z)
						end
						b.goal = b.stop
					else
						b.stop = nil
						b.goal = slot
					end
				end
				if role ~= b.roleWas then
					if role == "Support" then
						say(b, "Covering")
					elseif role == "Move" and sqs.sq.phase == "Bound" then
						say(b, "MoveUp")
					end
				end
				b.roleWas = role
			end
		end
	end
end

-- Normal: `side`'s build list at its front (Rules/BotBuild; Config/Bots.Build): the lay jobs, each matched to its
-- piece once laid (open while it wants swings; an unlaid one while the bots' caps allow it and it isn't waiting), and
-- the own pieces near the front wanting swings
local GUNS = { "FieldGun", "Howitzer" }
local function buildList(side: string, owner: { string }, level: number)
	local now = os.clock()
	local kit: string? = nil
	for _, b in bots do
		if b.side == side then
			kit = b.kit
			break
		end
	end
	local sb = buildLists[side]
	if not sb then
		sb = {
			front = nil,
			level = -1,
			holds = false,
			lay = {},
			works = {},
			open = {},
			steps = {},
			reserve = {},
			squares = {},
			standTo = false,
			fallbackUntil = 0,
		}
		buildLists[side] = sb
	end
	local sbs = sb :: SideBuild
	sbs.open = {}
	for _, r in sbs.lay do
		r.open = false
	end
	local front = BotBuild.front(Map.sectors, owner, side)
	if not front or not kit then
		sbs.front, sbs.lay, sbs.works, sbs.steps, sbs.reserve, sbs.squares = nil, {}, {}, {}, {}, {}
		return
	end
	local s = Map.sectors[front :: number]
	local zone = { x = s.x, z = s.z, radius = s.radius }
	local tx = if side == "West" then 1 else -1 -- (the enemy's home end: Map 1 runs west to east)
	local spots = Routes.spots(front :: number, side, true)
	if front ~= sbs.front or level ~= sbs.level or (not sbs.holds and spots ~= nil) then
		local holds = {}
		for _, sp in spots or {} do
			table.insert(holds, { x = sp.pos.X, z = sp.pos.Z, hidden = sp.hidden })
		end
		local guns = {}
		for _, key in GUNS do
			if FrontRules.gunLocked(FrontCfg.Artillery, key, level) == nil then
				table.insert(guns, key)
			end
		end
		sbs.lay = {}
		for _, job in BotBuild.plan(zone, tx, 0, holds, guns, BD) do
			table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
		end
		-- the trench system (Rules/BotTrenches): fire, support and communication trenches, dug in that order
		for _, run in BotTrenches.layout(zone, tx, 0, TR) do
			local job = { key = "Trench", x = run.ax, z = run.az, ex = run.bx, ez = run.bz, fx = tx, fz = 0 }
			local r = { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false, run = run }
			table.insert(sbs.lay, r)
		end
		sbs.front, sbs.level, sbs.holds = front, level, spots ~= nil
	end
	local works = Build.worksOf(kit)
	local pieces: { BotBuild.Piece } = {}
	local mine, ofKey = 0, {}
	for i, w in works do
		pieces[i] = { key = w.key, x = w.at.X, z = w.at.Z, left = w.left }
		if w.owner and (w.owner :: number) < 0 then
			mine += 1
			ofKey[w.key] = (ofKey[w.key] or 0) + 1
		end
	end
	-- (a trench run is matched by its squares, Rules/BotTrenches.laid; the rest by BotBuild.match)
	local jobs = {}
	local runs: { BotTrenches.Run } = {}
	local runLaid: { [number]: boolean } = {}
	local squares: { { x: number, z: number, at: Vector3 } } = {}
	local dug = 0
	for _, w in works do
		if w.key == "Trench" then
			dug += 1
			table.insert(squares, { x = w.at.X, z = w.at.Z, at = w.at })
		end
	end
	-- (each fire bay starts where the last one ends, the second communication run where the first ends)
	local chain: { [string]: BotBuild.Job } = {}
	for _, r in sbs.lay do
		local run = r.run
		if run and run.kind ~= "Support" then
			local last = chain[run.kind]
			local j = r.job
			if last and (j.x ~= last.ex or j.z ~= last.ez) then
				r.job = {
					key = j.key,
					x = last.ex :: number,
					z = last.ez :: number,
					ex = j.ex,
					ez = j.ez,
					fx = j.fx,
					fz = j.fz,
				}
			end
			chain[run.kind] = r.job
		end
	end
	for k, r in sbs.lay do
		local j = r.job
		if r.run then
			local run =
				{ kind = (r.run :: BotTrenches.Run).kind, ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number }
			table.insert(runs, run)
			runLaid[#runs] = BotTrenches.laid(run, squares, TR.on, TR.ends) ~= nil
			jobs[k] = { key = "", x = 0, z = 0, fx = 0, fz = 0 }
		else
			jobs[k] = j
		end
	end
	local matched = BotBuild.match(jobs, pieces, BD.match)
	local claimed: { [Model]: boolean } = {}
	local ri = 0
	for k, r in sbs.lay do
		local i = matched[k]
		if r.run then
			ri += 1
			r.model, r.at, r.left = nil, nil, 0
			r.open = not runLaid[ri] and now >= r.waitUntil and dug < TR.cap and BotTrenches.ready(runLaid, ri)
		elseif i then
			local w = works[i]
			r.model, r.at, r.left = w.model, w.at, w.left
			claimed[w.model] = true
			r.open = w.left > 0
		else
			r.model, r.at, r.left = nil, nil, 0
			local key = r.job.key
			r.open = now >= r.waitUntil and (key == "Trench" or BotBuild.allowed(key, mine, ofKey[key] or 0, BD.caps))
		end
		if r.open then
			table.insert(sbs.open, r)
		end
	end
	-- swings wanted: the nearest pieces (Build.repairs of them) and trench squares (Trenches.digs)
	local keep: { [Model]: BuildJob } = {}
	local n, nd = 0, 0
	for _, i in BotBuild.repairs(pieces, zone, BD.repair, #pieces) do
		local w = works[i]
		local square = w.key == "Trench"
		if not claimed[w.model] and (if square then nd < TR.digs else n < BD.repairs) then
			if square then
				nd += 1
			else
				n += 1
			end
			local r = sbs.works[w.model]
			if not r then
				local job = { key = w.key, x = w.at.X, z = w.at.Z, fx = tx, fz = 0, work = true }
				r = { job = job, base = job, model = w.model, tries = 0, waitUntil = 0, left = 0, open = true }
			end
			local rr = r :: BuildJob
			rr.at, rr.left, rr.open = w.at, w.left, true
			keep[w.model] = rr
			table.insert(sbs.open, rr)
		end
	end
	for model, r in sbs.works do
		if not keep[model] then
			r.open = false
		end
	end
	sbs.works = keep
	-- the posts its trenches give: a fire step on each dug fire-trench square, a place on each support-line square
	local outward = Vector3.new(tx, 0, 0)
	sbs.steps, sbs.reserve, sbs.squares = {}, {}, {}
	for _, w in works do
		if w.key == "Trench" and w.built and w.hp >= TR.standHp then
			table.insert(sbs.squares, { x = w.at.X, z = w.at.Z, at = w.at })
			for _, run in runs do
				local d, t = BotTrenches.offRun(w.at.X, w.at.Z, run.ax, run.az, run.bx, run.bz)
				if d <= TR.on + 1 and t >= -0.05 and t <= 1.05 then
					if run.kind == "Fire" then
						local x, z = BotTrenches.fireStep(w.at.X, w.at.Z, tx, 0, TR.step)
						table.insert(sbs.steps, { pos = Vector3.new(x, w.at.Y, z), floor = w.at, face = outward })
					elseif run.kind == "Support" then
						table.insert(sbs.reserve, { pos = w.at })
					end
					break
				end
			end
		end
	end
	-- the support line stands to with an enemy known near the fire trench; the fire trench is lost with enemies known
	-- in it or past it and too few of its holders standing
	local nearest, enemiesIn = math.huge, 0
	local edgeX = zone.x + tx * zone.radius * TR.Fire.edge
	for _, sq in squads do
		if sq.side == side then
			for _, kn in sq.known do
				if now - kn.at <= SQ.knownFor then
					local d = math.huge
					for _, run in runs do
						if run.kind == "Fire" then
							d = math.min(d, (BotTrenches.offRun(kn.pos.X, kn.pos.Z, run.ax, run.az, run.bx, run.bz)))
						end
					end
					nearest = math.min(nearest, d)
					local past = (kn.pos.X - edgeX) * tx < 0
						and flat(kn.pos - sectorPoint(front :: number)).Magnitude <= zone.radius
					if d <= TR.clearWithin or past then
						enemiesIn += 1
					end
				end
			end
		end
	end
	sbs.standTo = BotTrenches.standTo(nearest, TR.alarm)
	local held, standing = 0, 0
	for _, b in bots do
		if b.side == side and b.postKind == "step" then
			held += 1
			if alive(b) then
				standing += 1
			end
		end
	end
	if #sbs.steps > 0 and now >= sbs.fallbackUntil and BotTrenches.overrun(enemiesIn, standing, held, TR.keep) then
		sbs.fallbackUntil = now + TR.fallback
		stats.lost += 1
	end
end

-- Normal: each side's commander (Rules/BotOrders) from the sectors on the Frontline folder: who attacks the side's
-- target sector and who defends an own sector being taken; then its squads (formSquads)
local function command()
	local f = workspace:FindFirstChild(FrontCfg.FolderName)
	if liveMode() ~= "Normal" or not Frontline.running() or not f then
		return
	end
	debug.profilebegin("Bots.command")
	commandTick += 1
	local owner, control, counts = {}, {}, {}
	for i, s in Map.sectors do
		local sf = f:FindFirstChild(s.id)
		local o = sf and sf:GetAttribute("Owner")
		owner[i] = if type(o) == "string" then o else s.startOwner
		local c = sf and sf:GetAttribute("Control")
		control[i] = if type(c) == "number" then c else FrontRules.rest(owner[i])
		local w = sf and sf:GetAttribute("West")
		local e = sf and sf:GetAttribute("East")
		counts[i] = { West = if type(w) == "number" then w else 0, East = if type(e) == "number" then e else 0 }
	end
	local state = { owner = owner, control = control }
	for _, side in { "West", "East" } do
		local ids, current = {}, {}
		for _, b in bots do
			if b.side == side then
				table.insert(ids, b.id)
				current[b.id] = b.order
			end
		end
		local front = BotBuild.front(Map.sectors, owner, side)
		local target = FrontRules.target(state, side)
		local plan = Orders.plan(side, owner, control, counts, target, NV.defendShare, front, TR.hold)
		local given = Orders.assign(ids, current, Orders.defenders(#ids, plan.share, plan.attack ~= nil))
		for _, b in bots do
			if b.side == side then
				b.order = given[b.id]
				local sector = if b.order == "Defend" then plan.defend else plan.attack
				if sector ~= b.sector then
					b.sector = sector
					b.stand = if sector then standPoint(sector) else nil
					b.wander, b.reachedZone, b.flank = nil, false, nil
				end
			end
		end
		formSquads(side, counts)
		local level = f:GetAttribute(FrontCfg.LevelAttribute)
		buildList(side, owner, if type(level) == "number" then level else 0)
	end
	-- squads no longer formed go
	for key, sq in squads do
		if sq.seen ~= commandTick then
			squads[key] = nil
		end
	end
	debug.profileend()
end

local function report(now: number)
	if Cfg.ReportEvery <= 0 or now - stats.since < Cfg.ReportEvery or #bots == 0 then
		return
	end
	local span = now - stats.since
	local living = 0
	local states: { [string]: number } = {}
	local sides: { [string]: number } = {}
	local roles: { [string]: number } = {}
	local lods: { [string]: number } = {}
	local windows, clearing = 0, 0
	local jobsOpen, onSteps, inReserve = 0, 0, 0
	for _, b in bots do
		if b.role == "Hold" and alive(b) then
			onSteps += if b.postKind == "step" then 1 else 0
			inReserve += if b.postKind == "reserve" then 1 else 0
		end
	end
	for _, sb in buildLists do
		jobsOpen += #sb.open
	end
	for _, sq in squads do
		if sq.clear then
			clearing += 1
		end
	end
	for _, b in bots do
		lods[b.lod] = (lods[b.lod] or 0) + 1
		if b.postFace and b.role == "Hold" and alive(b) then
			windows += 1
		end
		if b.side then
			sides[b.side :: string] = (sides[b.side :: string] or 0) + 1
		end
		if alive(b) then
			living += 1
			states[b.brain.state] = (states[b.brain.state] or 0) + 1
			if b.role then
				roles[b.role :: string] = (roles[b.role :: string] or 0) + 1
			end
		end
	end
	local parts = {}
	local roleParts = {}
	for k, n in roles do
		table.insert(roleParts, `{k} {n}`)
	end
	table.sort(roleParts)
	for k, n in states do
		table.insert(parts, `{k} {n}`)
	end
	table.sort(parts)
	local samples = stats.frameSamples
	table.sort(samples)
	local p95 = if #samples > 0 then samples[math.max(1, math.ceil(#samples * 0.95))] else 0
	local heartbeat, send = 0, 0
	pcall(function()
		heartbeat = (Stats :: any).HeartbeatTimeMs
		send = (Stats :: any).DataSendKbps
	end)
	print(
		string.format(
			"[Bots] %d bots (W %d, E %d; %d alive: %s; cap %d): frame avg %.3f ms, p95 %.3f ms, max %.2f ms; think %.3f ms avg, %.2f ms max; %d frames out of time; %.1f rays/frame, %d sights put off; %.1f paths/s (%d failed, %d put off, %d shared); %d stuck, %d sidesteps; %d bodies taken back, %d stood up; %d squads pushed in, %d covering shots, roles %s; %d callouts; %d grenades, %d heals, %d drags; %d laid, %d swings, %d refused, %d jobs open; trenches %d runs planned, %d on fire steps, %d in reserve, %d lines lost; %d doors opened, %d at windows, %d squads clearing; %d shots, %d deaths, %d covers found, %d peeks, %d upgrades; to the zone %.1f s avg (%d); physics %.0f fps, heartbeat %.2f ms; thinking near %d, middle %d, distant %d; sending %.0f KB/s",
			#bots,
			sides.West or 0,
			sides.East or 0,
			living,
			table.concat(parts, ", "),
			governor.cap,
			if stats.frames > 0 then stats.frameTime / stats.frames * 1000 else 0,
			p95 * 1000,
			stats.frameMax * 1000,
			if stats.thinks > 0 then stats.thinkTime / stats.thinks * 1000 else 0,
			stats.thinkMax * 1000,
			stats.deferred,
			if stats.frames > 0 then stats.rays / stats.frames else 0,
			stats.senseDeferred,
			stats.paths / span,
			stats.pathFails,
			stats.pathsDeferred,
			stats.pathsShared,
			stats.stuck,
			stats.sidesteps,
			stats.reowned,
			stats.stoodUp,
			stats.assaults,
			stats.covering,
			if #roleParts > 0 then table.concat(roleParts, ", ") else "none",
			stats.callouts,
			stats.throws,
			stats.heals,
			stats.drags,
			stats.laid,
			stats.swings,
			stats.refused,
			jobsOpen,
			stats.runs,
			onSteps,
			inReserve,
			stats.lost,
			stats.doors,
			windows,
			clearing,
			stats.shots,
			stats.deaths,
			stats.covers,
			stats.peeks,
			stats.upgrades,
			if stats.toZoneCount > 0 then stats.toZone / stats.toZoneCount else 0,
			stats.toZoneCount,
			workspace:GetRealPhysicsFPS(),
			heartbeat,
			lods.near or 0,
			lods.middle or 0,
			lods.distant or 0,
			send
		)
	)
	for k, v in stats :: any do
		if type(v) == "number" then
			(stats :: any)[k] = 0
		end
	end
	table.clear(samples)
	stats.since = now
end

function Bots.start()
	if not Cfg.Enabled then
		return
	end
	-- knocked alive: thrown on the server (no client of its own), as a dev dummy is
	Ragdoll.knocked.Event:Connect(function(m: Model, name: string, direction: Vector3, scale: number)
		if not CollectionService:HasTag(m, Cfg.Tag) then
			return
		end
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if humanoid then
			DevDummies.own(m)
			DevDummies.throw(m, humanoid, RagdollCfg.Knocks[name] :: any, direction, scale)
		end
	end)
	Firing.onShot(shotPassed)
	-- explosions suppress bots as they do players (Config/Suppression.Blast), and count as a threat close by
	Damage.onBlast(function(pos: Vector3, kg: number)
		local now = os.clock()
		for _, b in bots do
			if alive(b) then
				local amount = Sup.blast(kg, (pos - eye(b)).Magnitude, SupCfg.Blast)
				if amount > 0 then
					shake(b, amount, now)
					b.threatAt, b.threatFrom = now, pos
				end
			end
		end
	end)
	-- a bot's capture pays it like a player's (src/server/Loadouts)
	ZoneMatch.onBotCapture(function(id)
		Loadouts.awardBot(id, "Capture")
	end)
	-- a bot's kills count for a match's honours (src/server/MatchStats), under its shown name
	Loadouts.onBotKill(function(id: number)
		for _, b in bots do
			if b.id == id then
				local shown = if b.mode == "Normal" then NV.nameTag .. b.name else b.name
				MatchStats.addBot(id, shown, b.kit, "Kills", 1)
			end
		end
	end)
	Frontline.onBotAward(function(m: Model, reason: string)
		local id = m:GetAttribute(Cfg.IdAttribute)
		if type(id) == "number" then
			Loadouts.awardBot(id, reason)
		end
	end)
	-- each match starts with everyone respawned: the bots too (in Normal, on the new match's teams)
	local function respawnAll(mode: string)
		for _, b in bots do
			if b.mode == mode then
				despawn(b)
				b.deadAt, b.respawnAt = nil, nil
				b.order, b.sector, b.stand = nil, nil, nil
				b.squad, b.role, b.goal, b.stop, b.post, b.roleWas, b.postFace = nil, nil, nil, nil, nil, nil, nil
				spawnBody(b)
			end
		end
	end
	ZoneMatch.onMatchStart(function()
		respawnAll("FFA")
	end)
	Frontline.onMatchStart(function()
		Routes.clear() -- (the map is put back: spots worked out again)
		table.clear(indoorCells)
		table.clear(buildLists)
		table.clear(squads)
		respawnAll("Normal")
	end)
	-- the director in its own loop: a new body yields (the avatar is built), never inside the frame's step
	task.spawn(function()
		while true do
			task.wait(Cfg.Direct)
			local ok, err = pcall(direct, os.clock())
			if not ok then
				warn(`[Bots] director: {err}`)
			end
		end
	end)
	-- Normal's commanders, in their own slow loop
	task.spawn(function()
		while true do
			task.wait(NV.commandEvery)
			local ok, err = pcall(command)
			if not ok then
				warn(`[Bots] commander: {err}`)
			end
		end
	end)
	-- every frame: the bots due think, round-robin, until the frame's milliseconds are spent
	RunService.Heartbeat:Connect(function(dt: number)
		local t0 = os.clock()
		frame += 1
		raysLeft = BG.raysPerFrame
		pathTokens = math.min(math.max(BG.pathsPerSecond, 1), pathTokens + BG.pathsPerSecond * dt)
		debug.profilebegin("Bots.frame")
		local d = difficulty()
		local n = #bots
		local deadline = t0 + BG.frameMs / 1000
		local start = if cursor > n then 1 else cursor
		for k = 0, n - 1 do
			local i = (start + k - 1) % n + 1
			local b = bots[i]
			if t0 < b.nextThink then
				continue
			end
			if os.clock() >= deadline then
				cursor = i -- (the next frame starts here)
				stats.deferred += 1
				break
			end
			b.nextThink += 1 / b.thinkHz
			if b.nextThink < t0 then
				b.nextThink = t0 + 1 / b.thinkHz
			end
			if alive(b) and not b.deadAt then
				local s0 = os.clock()
				-- a concussed bot reacts later and aims worse while it lasts (src/server/Concussion)
				local ok, err = pcall(think, b, t0, if b.m then Concussion.daze(b.m, d, t0) else d)
				if not ok then
					warn(`[Bots] {b.name}: {err}`)
				end
				local spent = os.clock() - s0
				stats.thinkTime += spent
				stats.thinks += 1
				stats.thinkMax = math.max(stats.thinkMax, spent)
			end
		end
		debug.profileend()
		local spent = os.clock() - t0
		stats.frameMax = math.max(stats.frameMax, spent)
		stats.frames += 1
		stats.frameTime += spent
		table.insert(stats.frameSamples, spent)
		-- the governor, once a second, on the bots' average frame cost and the physics rate
		govTime += spent
		govFrames += 1
		if t0 - govAt >= 1 then
			local max = if liveMode() == "Normal" then Cfg.Max.Normal else Cfg.Max.FFA
			if n > 0 then
				local ms = govTime / govFrames * 1000
				Rules.govern(governor, ms, workspace:GetRealPhysicsFPS(), t0 - govAt, n, max, BG.governor)
			end
			govAt, govTime, govFrames = t0, 0, 0
		end
		report(t0)
	end)
end

-- (tests and the admin panel) every bot now
function Bots.list(): { Model }
	local out = {}
	for _, b in bots do
		if b.m then
			table.insert(out, b.m :: Model)
		end
	end
	return out
end

return Bots
