--!strict
-- Bot soldiers that fill the empty places when too few players are on (Config/Bots, Rules/Bots; stage 1, 2026-10-30:
-- rifles, the FFA zone match).
-- - The director tops the match up to the mode's fill (Rules/Bots.wanted: players first, never over Config/Bots.Max),
--   one bot in at a time; when players join, bots leave (a dead one first, else one that has been over the count a
--   while). Workspace's "Bots" attribute pins the count (testing).
-- - A bot is a soldier like a player's: a kit's body (src/server/Showcase.dummy, dressed by src/server/Bodies: the
--   uniform, helmet, face following health and the death face), the kit's bolt rifle or its semi (src/server/Armory),
--   tagged as an NPC soldier (Config/DevTools.Dummies.Tag) so src/server/Damage hurts it, src/server/Healing heals it
--   and src/server/Dragging drags it; it shoots through src/server/Firing (Firing.fireAs / actAs: the same action
--   state, rate and hitscan as a player's), is knocked and ragdolled (src/server/DevDummies.throw), dies limp and
--   comes back after Config/Metrics.Combat.RespawnDelay at a src/server/ZoneMatch spawn.
-- - One loop steps every bot's brain (Rules/Bots.step) Config/Bots.Think times a second, staggered: it senses (enemies
--   in range and view, a line-of-sight ray for the nearest few, Config/Bots.Sense a second), paths to its goal with
--   PathfindingService (the zone, the last place a target was seen, away from a threat), aims with the difficulty's
--   error and lead, fires, works the bolt and reloads. src/server/Bots/Animate plays its animations.
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
local Metrics = require(Shared.Config.Metrics)
local ModesCfg = require(Shared.Config.Modes)
local RagdollCfg = require(Shared.Config.Ragdoll)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local F = require(Shared.Rules.Firing)
local Rules = require(Shared.Rules.Bots)
local Armory = require(script.Parent.Armory)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local Firing = require(script.Parent.Firing)
local Ragdoll = require(script.Parent.Ragdoll)
local Showcase = require(script.Parent.Showcase)
local ZoneMatch = require(script.Parent.ZoneMatch)
local Animate = require(script.Animate)

local Bots = {}

local Loco = require(Shared.Config.Locomotion)
local M = Metrics.Movement
local brainCfg = table.clone(Cfg.Brain) :: any
brainCfg.CloseRange = Cfg.Move.CloseRange

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
	direct: Vector3?, -- a point walked to straight, without a path (strafing, a step aside)
}

type Bot = {
	id: number,
	kit: string,
	weapon: string,
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
	candidates: { Target },
	target: Target?,
	lastSeenAt: Vector3?,
	hurtAt: number?,
	nav: Nav,
	wanderAt: number,
	wander: Vector3?,
	strafeAt: number,
	spawnedAt: number,
	reachedZone: boolean,
	deadAt: number?,
	overSince: number?,
	shotsAt: number,
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

-- the kit's bolt rifle, or now and then its semi (Config/Classes.Gear)
local function pickWeapon(kit: string): string
	local gear = (Classes :: any).Gear[kit]
	local semi = gear and gear.semi
	if semi and W[semi] and random:NextNumber() < Cfg.SemiShare then
		return semi
	end
	return U.Kits[kit].weapon
end

local spawnBody: (b: Bot) -> ()

-- A body for `b` at a spawn point, dressed, armed and on its feet.
spawnBody = function(b: Bot)
	local cf = ZoneMatch.spawnFor(nil)
	if not cf or b.spawning then
		return
	end
	b.spawning = true
	-- FFA: a fresh kit each life, as a player's is rolled
	b.kit = U.Teams[random:NextInteger(1, #U.Teams)]
	b.weapon = pickWeapon(b.kit)
	local ok, made = pcall(Showcase.dummy, `Bot {-b.id}`, cf :: CFrame, botFolder(), b.kit)
	b.spawning = false
	if not ok then
		warn(`[Bots] no body for {-b.id}: {made}`)
		return
	end
	local m = made :: Model
	if not table.find(bots, b) then
		m:Destroy() -- (removed while it was being built)
		return
	end
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
	Firing.entry(tool) -- (a full rifle, published)
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
	b.target, b.candidates, b.lastSeenAt, b.hurtAt = nil, {}, nil, nil
	b.nav = {
		goal = nil,
		waypoints = {},
		index = 1,
		computing = false,
		pathAt = -math.huge,
		sampleAt = os.clock(),
		samplePos = root.Position,
		jumps = 0,
		repaths = 0,
		direct = nil,
	}
	b.spawnedAt, b.reachedZone, b.deadAt, b.wander = os.clock(), false, nil, nil

	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < last then
			b.hurtAt = os.clock()
		end
		last = health
	end)
	m:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if m:GetAttribute("Ragdolled") ~= true and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
	humanoid.Died:Connect(function()
		stats.deaths += 1
		b.deadAt = os.clock()
		turn.Enabled = false
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
		kit = U.Default,
		weapon = U.Kits[U.Default].weapon,
		brain = Rules.new(),
		nextThink = os.clock() + random:NextNumber() / Cfg.Think,
		nextSense = 0,
		candidates = {},
		nav = {
			goal = nil,
			waypoints = {},
			index = 1,
			computing = false,
			pathAt = 0,
			sampleAt = 0,
			samplePos = Vector3.zero,
			jumps = 0,
			repaths = 0,
		},
		wanderAt = 0,
		strafeAt = 0,
		spawnedAt = 0,
		reachedZone = false,
		shotsAt = 0,
		spawning = false,
	}
	table.insert(bots, b)
	spawnBody(b)
end

local function remove(i: number)
	despawn(bots[i])
	table.remove(bots, i)
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
	local alert = b.hurtAt ~= nil and now - (b.hurtAt :: number) < Cfg.Brain.Alert
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
	local out: { Target } = {}
	for i = 1, math.min(#seen, Cfg.SenseNearest) do
		local t = seen[i]
		local part = aimPart(t.model) :: BasePart
		local hit = workspace:Raycast(from, part.Position - from, rayParams)
		stats.rays += 1
		t.visible = hit ~= nil and hit.Instance:IsDescendantOf(t.model)
		table.insert(out, t)
	end
	-- the current target, still in view but not among the nearest: kept if it's in sight
	local current = b.brain.targetId
	b.candidates = out
	local list = {}
	for _, t in out do
		table.insert(list, { id = t.model, distance = t.distance, visible = t.visible })
	end
	local pick = Rules.pick(list, current)
	b.target = nil
	if pick then
		for _, t in out do
			if t.model == pick.id then
				b.target = t
			end
		end
	end
	if b.target then
		local part = aimPart((b.target :: Target).model)
		if part then
			b.lastSeenAt = part.Position
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
			AgentRadius = Cfg.Move.AgentRadius,
			AgentHeight = Cfg.Move.AgentHeight,
			AgentCanJump = true,
			WaypointSpacing = Cfg.Move.WaypointSpacing,
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
	if not nav.computing and (changed or now - nav.pathAt > Cfg.Move.Repath) then
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
			if flat(wp.Position - root.Position).Magnitude < Cfg.Move.Arrive then
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
		if nav.direct then
			nav.direct = nil
		end
		humanoid:MoveTo(root.Position)
		nav.sampleAt, nav.samplePos = now, root.Position
		return
	end
	humanoid:MoveTo(target :: Vector3)
	-- progress check
	local elapsed = now - nav.sampleAt
	if elapsed >= Cfg.Move.StuckWindow then
		local moved = flat(root.Position - nav.samplePos).Magnitude
		if Rules.stuck(moved, elapsed, Cfg.Move.StuckWindow, Cfg.Move.StuckDistance) then
			stats.stuck += 1
			if nav.jumps < Cfg.Move.StuckJumps then
				nav.jumps += 1
				humanoid.Jump = true
			elseif nav.repaths < Cfg.Move.StuckRepaths and nav.goal and not nav.computing then
				nav.repaths += 1
				nav.jumps = 0
				computePath(b, nav.goal :: Vector3)
			else
				stats.sidesteps += 1
				nav.jumps, nav.repaths = 0, 0
				local a = random:NextNumber() * 2 * math.pi
				nav.direct = root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * Cfg.Move.Sidestep
			end
		end
		nav.sampleAt, nav.samplePos = now, root.Position
	end
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
	}
	local intent = Rules.step(b.brain, senses, brainCfg, d, random:NextNumber())

	-- where to go
	local zone, radius = ZoneMatch.objective()
	local goal: Vector3? = nil
	local targetPart = if target then aimPart(target.model) else nil
	local aimAt: Vector3? = if targetPart then targetPart.Position else b.lastSeenAt
	if intent.move == "Objective" and zone then
		local z = zone :: Vector3
		local inZone = flat(root.Position - z).Magnitude < radius * Cfg.Move.InZoneShare
		if inZone and not b.reachedZone then
			b.reachedZone = true
			stats.toZone += now - b.spawnedAt
			stats.toZoneCount += 1
		end
		if inZone and (not b.wander or now >= b.wanderAt) then
			local a = random:NextNumber() * 2 * math.pi
			local r = radius * Cfg.Move.WanderShare * math.sqrt(random:NextNumber())
			b.wander = z + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			b.wanderAt = now + Cfg.Move.WanderEvery
		end
		goal = if inZone then b.wander else z
		b.nav.direct = nil
	elseif intent.move == "Hunt" then
		goal = b.lastSeenAt
		b.nav.direct = nil
	elseif intent.move == "Away" and aimAt then
		local away = flat(root.Position - aimAt :: Vector3)
		away = if away.Magnitude > 1e-3 then away.Unit else -flat(root.CFrame.LookVector)
		goal = root.Position + away * Cfg.Brain.RetreatDistance
		b.nav.direct = nil
	elseif intent.move == "Strafe" and aimAt then
		if now >= b.strafeAt then
			b.strafeAt = now + random:NextNumber(Cfg.Move.StrafeEvery[1], Cfg.Move.StrafeEvery[2])
			local to = flat((aimAt :: Vector3) - root.Position)
			local side = if to.Magnitude > 1e-3 then to.Unit:Cross(Vector3.yAxis) else root.CFrame.RightVector
			local sign = if random:NextNumber() < 0.5 then -1 else 1
			b.nav.direct = root.Position + side * sign * Cfg.Move.Strafe
		end
	else
		b.nav.direct = nil -- (Hold: stand)
	end
	if intent.move ~= "Hold" and intent.move ~= "Strafe" then
		setGoal(b, goal, now)
	else
		b.nav.goal = nil
	end
	follow(b, now)

	-- speed and facing
	local far = b.nav.goal and flat((b.nav.goal :: Vector3) - root.Position).Magnitude > Cfg.Move.SprintFrom
	local sprint = not intent.aim and intent.move ~= "Hold" and far
	humanoid.WalkSpeed = if intent.aim then M.AimWalkSpeed elseif sprint then M.SprintSpeed else M.WalkSpeed
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
		want = 0 -- (stage 1: only the zone match has spawns and an objective)
	end
	-- back from the dead (or gone, if no longer wanted)
	for i = #bots, 1, -1 do
		local b = bots[i]
		if b.deadAt and now - (b.deadAt :: number) >= Metrics.Combat.RespawnDelay then
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
	for _, b in bots do
		if alive(b) then
			living += 1
		end
	end
	local physics = workspace:GetRealPhysicsFPS()
	print(
		string.format(
			"[Bots] %d bots (%d alive): think %.3f ms avg, %.2f ms max; frame max %.2f ms; %.0f rays/s, %.1f paths/s (%d failed); %d stuck, %d sidesteps; %d shots, %d deaths; to the zone %.1f s avg (%d); physics %.0f fps",
			#bots,
			living,
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
			if stats.toZoneCount > 0 then stats.toZone / stats.toZoneCount else 0,
			stats.toZoneCount,
			physics
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
	-- each match starts with everyone respawned: the bots too
	ZoneMatch.onMatchStart(function()
		for _, b in bots do
			despawn(b)
			b.deadAt = nil
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
						warn(`[Bots] {-b.id}: {err}`)
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
