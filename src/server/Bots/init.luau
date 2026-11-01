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
local Loco = require(Shared.Config.Locomotion)
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
local Rules = require(Shared.Rules.Bots)
local ShotRules = require(Shared.Rules.ShotAudio)
local Sup = require(Shared.Rules.Suppression)
local Teams = require(Shared.Rules.Teams)
local Armory = require(script.Parent.Armory)
local Concussion = require(script.Parent.Concussion)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local Firing = require(script.Parent.Firing)
local Frontline = require(script.Parent.Frontline)
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
	roleWas: Squads.Role?,
	grip: Motor6D?, -- the gun's hold joint (to the torso)
	stowed: boolean, -- its gun put away (standing in the wave line)
	shaken: number, -- its suppression level at its last hit (Rules/Suppression)
	shakenAt: number, -- when that was
	thinkHz: number, -- how often it thinks and looks now (Rules/Bots.lod)
	senseHz: number,
	lod: string, -- "near", "middle" or "distant" (the report)
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
}
local squads: { [string]: SquadState } = {}
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
	}
end

-- A body for `b` at a spawn point, dressed in its class, armed and on its feet.
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
type Soldier = { model: Model, part: BasePart, kit: any, pos: Vector3, look: Vector3 }
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

local function setGoal(b: Bot, goal: Vector3?, now: number)
	local nav = b.nav
	if goal == nil then
		nav.goal = nil
		nav.waypoints = {}
		return
	end
	local g = goal :: Vector3
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
	local target: Vector3? = nav.direct
	if not target and nav.goal then
		local wp = nav.waypoints[nav.index]
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
		if Rules.stuck(moved, elapsed, MV.StuckWindow, MV.StuckDistance) then
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
	local torso = m:FindFirstChild("Torso") :: BasePart?
	if b.grip and torso then
		(b.grip :: Motor6D).Part0 = torso
	end
	if b.anim then
		(b.anim :: Animate.Handle).equip()
	end
	DevDummies.own(m)
end

local function think(b: Bot, now: number, d: Rules.Difficulty)
	local m, humanoid, root, tool = b.m :: Model, b.humanoid :: Humanoid, b.root :: BasePart, b.tool :: Tool
	local entry = Firing.entry(tool)
	if not entry then
		return
	end
	if Ragdoll.active(m) then
		(b.turn :: AlignOrientation).Enabled = false
		return -- (down: nothing until it is up again)
	end
	if m:GetAttribute(FrontCfg.HoldAttribute) ~= nil then
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
	-- cover from the threat, while there is one
	local threatened = b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.ThreatMemory
	if b.coverJob then
		coverStep(b)
	elseif (threatened or b.spotted or b.brain.targetId ~= nil) and now - b.coverAt >= CV.every then
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
	local intent = Rules.step(b.brain, senses, brainCfg, d, random:NextNumber())
	if b.brain.state ~= was and b.brain.state == "Peek" then
		stats.peeks += 1
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
			end
			-- each member's role and goal
			local route = sqs.mid or sqs.approach or c
			local ahead = flat(route - mid)
			local right = if ahead.Magnitude > 1 then ahead.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
			for idx, b in members do
				local role = Squads.role(sqs.sq, idx)
				b.squad, b.role = key, role
				local p = if b.root then (b.root :: BasePart).Position else mid
				if role == "Hold" then
					if not b.post or b.postSector ~= sector or b.roleWas ~= "Hold" then
						b.post = holdSpot(side, sector, taken) or b.stand
						b.postSector = sector
					end
					b.goal = b.post
				elseif role == "Assault" then
					b.goal = b.stand
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
				b.roleWas = role
			end
		end
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
		local plan = Orders.plan(side, owner, control, counts, FrontRules.target(state, side), NV.defendShare)
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
	for _, b in bots do
		lods[b.lod] = (lods[b.lod] or 0) + 1
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
			"[Bots] %d bots (W %d, E %d; %d alive: %s; cap %d): frame avg %.3f ms, p95 %.3f ms, max %.2f ms; think %.3f ms avg, %.2f ms max; %d frames out of time; %.1f rays/frame, %d sights put off; %.1f paths/s (%d failed, %d put off, %d shared); %d stuck, %d sidesteps; %d bodies taken back, %d stood up; %d squads pushed in, %d covering shots, roles %s; %d shots, %d deaths, %d covers found, %d peeks, %d upgrades; to the zone %.1f s avg (%d); physics %.0f fps, heartbeat %.2f ms; thinking near %d, middle %d, distant %d; sending %.0f KB/s",
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
				b.squad, b.role, b.goal, b.stop, b.post, b.roleWas = nil, nil, nil, nil, nil, nil
				spawnBody(b)
			end
		end
	end
	ZoneMatch.onMatchStart(function()
		respawnAll("FFA")
	end)
	Frontline.onMatchStart(function()
		Routes.clear() -- (the map is put back: spots worked out again)
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
