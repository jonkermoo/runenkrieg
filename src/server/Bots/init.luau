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
-- Every Config/Bots.ReportEvery seconds the log has a line on its cost and its fights.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local Classes = require(Shared.Config.Classes)
local DamageCfg = require(Shared.Config.Damage)
local DevCfg = require(Shared.Config.DevTools)
local Loco = require(Shared.Config.Locomotion)
local Metrics = require(Shared.Config.Metrics)
local ModesCfg = require(Shared.Config.Modes)
local RagdollCfg = require(Shared.Config.Ragdoll)
local U = require(Shared.Config.Uniforms)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local F = require(Shared.Rules.Firing)
local Rules = require(Shared.Rules.Bots)
local Armory = require(script.Parent.Armory)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local Firing = require(script.Parent.Firing)
local Loadouts = require(script.Parent.Loadouts)
local Ragdoll = require(script.Parent.Ragdoll)
local Showcase = require(script.Parent.Showcase)
local ZoneMatch = require(script.Parent.ZoneMatch)
local Animate = require(script.Animate)

local Bots = {}

local M = Metrics.Movement
local MV = Cfg.Move
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
}

local bots: { Bot } = {}
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
	since = os.clock(),
}

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
	local cf = ZoneMatch.spawnFor(nil)
	if not cf or b.spawning then
		return
	end
	b.spawning = true
	-- FFA: a fresh kit each life, as a player's is rolled; the class from its points
	b.kit = U.Teams[random:NextInteger(1, #U.Teams)]
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
	humanoid.DisplayName = b.name
	humanoid.BreakJointsOnDeath = false
	humanoid.MaxHealth = DamageCfg.Health
	humanoid.Health = DamageCfg.Health
	humanoid.WalkSpeed = M.WalkSpeed
	humanoid.JumpHeight = M.JumpHeight
	humanoid.UseJumpPower = false
	humanoid.MaxSlopeAngle = M.MaxSlopeAngle
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	local torso = m:FindFirstChild("Torso") :: BasePart
	local tool = Armory.tool(b.weapon, b.kit)
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
	Damage.protect(m, ZoneCfg.SpawnProtection)

	b.m, b.humanoid, b.root, b.head, b.tool, b.turn =
		m, humanoid, root, m:FindFirstChild("Head") :: BasePart, tool, turn
	b.anim = Animate.attach(m, b.weapon)
	b.brain = Rules.new()
	b.target, b.lastSeenAt, b.lastOpen, b.spotted = nil, nil, nil, false
	b.hurtAt, b.threatAt, b.threatFrom, b.cover, b.coverFrom = nil, nil, nil, nil, nil
	b.nav = newNav(root.Position)
	b.spawnedAt, b.reachedZone, b.deadAt, b.respawnAt, b.wander = os.clock(), false, nil, nil, nil
	-- the way to the zone: now and then a bend off the straight line
	b.flank = nil
	local zone = ZoneMatch.objective()
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
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
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
		end
	end)
	humanoid.Died:Connect(function()
		stats.deaths += 1
		b.deadAt = os.clock()
		-- a player's respawn wait, then a moment in the loadout menu
		b.respawnAt = b.deadAt + Metrics.Combat.RespawnDelay + random:NextNumber(Cfg.MenuTime[1], Cfg.MenuTime[2])
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

local function add()
	count += 1
	local b: Bot = {
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

local function sense(b: Bot, d: Rules.Difficulty, now: number)
	local m, root = b.m :: Model, b.root :: BasePart
	local from = eye(b)
	local facing = flat(root.CFrame.LookVector)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.zAxis
	-- hit or shot at lately: it looks all round
	local alert = b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.Alert
	local seen: { Target } = {}
	for _, other in Damage.soldiers() do
		if other == m then
			continue
		end
		local h = other:FindFirstChildOfClass("Humanoid")
		local part = aimPart(other)
		if not h or h.Health <= 0 or not part or Damage.spares(m, other) then
			continue
		end
		local off = part.Position - from
		local dist = off.Magnitude
		if Rules.inSight(off.X, off.Z, dist, facing.X, facing.Z, d.spotRange, d.fov, alert) then
			table.insert(seen, { model = other, distance = dist, visible = false })
		end
	end
	table.sort(seen, function(x, y)
		return x.distance < y.distance
	end)
	rayParams.FilterDescendantsInstances = { m }
	local list = {}
	local out: { Target } = {}
	b.spotted = false
	for i = 1, math.min(#seen, Cfg.SenseNearest) do
		local t = seen[i]
		local part = aimPart(t.model) :: BasePart
		local hit = workspace:Raycast(from, part.Position - from, rayParams)
		stats.rays += 1
		t.visible = hit ~= nil and hit.Instance:IsDescendantOf(t.model)
		table.insert(out, t)
		table.insert(list, { id = t.model, distance = t.distance, visible = t.visible })
		-- an enemy in sight looking its way has spotted it
		local theirRoot = t.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if t.visible and theirRoot then
			local look = flat(theirRoot.CFrame.LookVector)
			local off = part.Position - from
			if look.Magnitude > 1e-3 and Rules.lookingAt(off.X, off.Z, look.Unit.X, look.Unit.Z, brainCfg.LookCone) then
				b.spotted = true
				if not b.threatFrom or now - (b.threatAt or -math.huge) > brainCfg.ThreatMemory then
					b.threatFrom = part.Position + Vector3.yAxis * Cfg.Eye
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
		end
		b.lastOpen = root.Position
	end
end

-- a ground point under (x, z) near `y`, or nil (off the map, under water)
local function groundAt(x: number, y: number, z: number, exclude: { Instance }): Vector3?
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(Vector3.new(x, y + 8, z), Vector3.new(0, -24, 0), rayParams)
	stats.rays += 1
	return hit and hit.Position
end

-- whether the threat's eye `from` can't see a soldier standing at the ground point `p`
local function hidden(from: Vector3, p: Vector3, exclude: { Instance }): boolean
	local chest = p + Vector3.yAxis * (CV.chest + 1.8)
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(from, chest - from, rayParams)
	stats.rays += 1
	return hit ~= nil and hit.Distance < (chest - from).Magnitude - 1
end

-- cover from the threat: the old point while it's still hidden from where the threat is now; else rings of points
-- round the bot, nearest ring first (Rules/Bots.pickCover)
local function findCover(b: Bot, now: number)
	local from = b.threatFrom or b.lastSeenAt
	if not from then
		b.cover = nil
		return
	end
	local threat = from :: Vector3
	b.coverAt = now
	local root = b.root :: BasePart
	local exclude: { Instance } = { b.m :: Model }
	if b.target then
		table.insert(exclude, (b.target :: Target).model)
	end
	local stale = b.coverFrom and ((b.coverFrom :: Vector3) - threat).Magnitude > CV.moved
	if b.cover and not stale and hidden(threat, b.cover :: Vector3, exclude) then
		return
	end
	b.cover = nil
	local here = flat(root.Position - threat).Magnitude
	for _, r in CV.rings do
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
					hidden = hidden(threat, g, exclude),
					threat = flat(g - threat).Magnitude,
				})
			end
		end
		local i = Rules.pickCover(points, here - CV.minThreatGain, CV.reach)
		if i then
			b.cover = spots[i]
			b.coverFrom = threat
			stats.covers += 1
			return
		end
	end
end

-- shots passing close: every bot near the line feels it (Rules/Bots.nearMiss)
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
			b.threatAt = now
			b.threatFrom = origin
		end
	end
end

-- moving -------------------------------------------------------------------------------------------------------------

local function computePath(b: Bot, goal: Vector3)
	local nav = b.nav
	nav.computing = true
	nav.pathAt = os.clock()
	local root = b.root :: BasePart
	local from = root.Position
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = MV.AgentRadius,
			AgentHeight = MV.AgentHeight,
			AgentCanJump = true,
			WaypointSpacing = MV.WaypointSpacing,
		})
		stats.paths += 1
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		nav.computing = false
		if nav.goal ~= goal then
			return -- (a new goal meanwhile)
		end
		if ok and path.Status == Enum.PathStatus.Success then
			nav.waypoints = path:GetWaypoints()
			nav.index = math.min(2, #nav.waypoints)
		else
			stats.pathFails += 1
			nav.waypoints = {}
			nav.index = 1
		end
	end)
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
	if not nav.computing and (changed or now - nav.pathAt > MV.Repath) then
		nav.goal = g
		computePath(b, g)
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
			if flat(wp.Position - root.Position).Magnitude < MV.Arrive then
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
				nav.repaths += 1
				nav.jumps = 0
				computePath(b, nav.goal :: Vector3)
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
	local step = side * random:NextNumber(MV.Strafe[1], MV.Strafe[2]) + fwd * random:NextNumber(-2, 2)
	nav.direct = root.Position + step
	nav.goal = nil
end

-- thinking -----------------------------------------------------------------------------------------------------------

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
	if now >= b.nextSense then
		b.nextSense = now + 1 / Cfg.Sense
		sense(b, d, now)
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
	-- cover from the threat, while there is one
	local threatened = b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.ThreatMemory
	if (threatened or b.spotted or b.brain.targetId ~= nil) and now - b.coverAt >= CV.every then
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
	}
	local was = b.brain.state
	local intent = Rules.step(b.brain, senses, brainCfg, d, random:NextNumber())
	if b.brain.state ~= was and b.brain.state == "Peek" then
		stats.peeks += 1
	end

	-- where to go
	local zone, radius = ZoneMatch.objective()
	local goal: Vector3? = nil
	local targetPart = if target then aimPart(target.model) else nil
	local aimAt: Vector3? = if targetPart then targetPart.Position else b.lastSeenAt
	local move = intent.move
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
		goal = if inZone then b.wander elseif b.flank then b.flank else z
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
	elseif move ~= "Strafe" and move ~= "Peek" then
		b.nav.goal = nil
	end
	follow(b, now)

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
			local err = Rules.aimError(d, now - b.brain.seenAt - d.reaction, cross)
			local right, up = Rules.scatter(err, random:NextNumber(), random:NextNumber())
			local dir = (CFrame.lookAt(Vector3.zero, line.Unit) * CFrame.Angles(math.rad(up), -math.rad(right), 0)).LookVector
			if Firing.fireAs(m, origin, dir, random:NextInteger(1, 2147483646)) then
				stats.shots += 1
			end
		end
	end
end

-- the director --------------------------------------------------------------------------------------------------------

local nextJoin, nextLeave = 0, 0

local function direct(now: number)
	local mode = workspace:GetAttribute(ModesCfg.Attribute)
	local pin = workspace:GetAttribute(Cfg.Attribute)
	local fill = if Cfg.Enabled and type(mode) == "string" then (Cfg.Fill :: any)[mode] else nil
	local want = Rules.wanted(fill, #Players:GetPlayers(), Cfg.Max, if type(pin) == "number" then pin else nil)
	if not ZoneMatch.running() then
		want = 0 -- (only the zone match has spawns and an objective so far)
	end
	-- back from the dead after the respawn wait (or gone, if no longer wanted)
	for i = #bots, 1, -1 do
		local b = bots[i]
		if b.deadAt and now >= (b.respawnAt or math.huge) then
			if #bots > want then
				remove(i)
			else
				despawn(b)
				spawnBody(b)
			end
		elseif not b.m and not b.deadAt then
			spawnBody(b) -- (no spawn point earlier)
		end
	end
	if #bots < want and now >= nextJoin then
		nextJoin = now + Cfg.JoinEvery
		add()
	elseif #bots > want and now >= nextLeave then
		-- a dead one goes first; else the one longest over the count
		for i, b in bots do
			if b.deadAt then
				nextLeave = now + Cfg.LeaveEvery
				remove(i)
				return
			end
		end
		local last = bots[#bots]
		last.overSince = last.overSince or now
		if now - (last.overSince :: number) >= Cfg.LeaveAliveAfter then
			nextLeave = now + Cfg.LeaveEvery
			remove(#bots)
		end
	else
		for _, b in bots do
			b.overSince = nil
		end
	end
end

local function report(now: number)
	if Cfg.ReportEvery <= 0 or now - stats.since < Cfg.ReportEvery or #bots == 0 then
		return
	end
	local span = now - stats.since
	local living = 0
	local states: { [string]: number } = {}
	for _, b in bots do
		if alive(b) then
			living += 1
			states[b.brain.state] = (states[b.brain.state] or 0) + 1
		end
	end
	local parts = {}
	for k, n in states do
		table.insert(parts, `{k} {n}`)
	end
	table.sort(parts)
	print(
		string.format(
			"[Bots] %d bots (%d alive: %s): think %.3f ms avg, %.2f ms max; frame max %.2f ms; %.0f rays/s, %.1f paths/s (%d failed); %d stuck, %d sidesteps; %d shots, %d deaths, %d covers found, %d peeks, %d upgrades; to the zone %.1f s avg (%d); physics %.0f fps",
			#bots,
			living,
			table.concat(parts, ", "),
			if stats.thinks > 0 then stats.thinkTime / stats.thinks * 1000 else 0,
			stats.thinkMax * 1000,
			stats.frameMax * 1000,
			stats.rays / span,
			stats.paths / span,
			stats.pathFails,
			stats.stuck,
			stats.sidesteps,
			stats.shots,
			stats.deaths,
			stats.covers,
			stats.peeks,
			stats.upgrades,
			if stats.toZoneCount > 0 then stats.toZone / stats.toZoneCount else 0,
			stats.toZoneCount,
			workspace:GetRealPhysicsFPS()
		)
	)
	for k in stats do
		stats[k] = 0
	end
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
	-- a bot's capture pays it like a player's (src/server/Loadouts)
	ZoneMatch.onBotCapture(function(id)
		Loadouts.awardBot(id, "Capture")
	end)
	-- each match starts with everyone respawned: the bots too
	ZoneMatch.onMatchStart(function()
		for _, b in bots do
			despawn(b)
			b.deadAt, b.respawnAt = nil, nil
			spawnBody(b)
		end
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
	RunService.Heartbeat:Connect(function()
		local t0 = os.clock()
		local d = difficulty()
		for _, b in bots do
			if t0 >= b.nextThink then
				b.nextThink += 1 / Cfg.Think
				if b.nextThink < t0 then
					b.nextThink = t0 + 1 / Cfg.Think
				end
				if alive(b) and not b.deadAt then
					local s0 = os.clock()
					local ok, err = pcall(think, b, t0, d)
					if not ok then
						warn(`[Bots] {b.name}: {err}`)
					end
					local spent = os.clock() - s0
					stats.thinkTime += spent
					stats.thinks += 1
					stats.thinkMax = math.max(stats.thinkMax, spent)
				end
			end
		end
		stats.frameMax = math.max(stats.frameMax, os.clock() - t0)
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
