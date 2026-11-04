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
-- Its parts (this module keeps spawning, the brain's think, the director and the loop): Bots/Types (the shared types),
-- Bots/State (what they share), Bots/Move (senses, cover, paths), Bots/Act (actions, staffs), Bots/Commander (squads and
-- build lists in Normal), Bots/Report (the log line and the admin panel's tests), Bots/Crew, Bots/Routes, Bots/Animate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local Classes = require(Shared.Config.Classes)
local DamageCfg = require(Shared.Config.Damage)
local DevCfg = require(Shared.Config.DevTools)
local FrontCfg = require(Shared.Config.Frontline)
local BuildCfg = require(Shared.Config.Build)
local W = require(Shared.Config.Weapons)
local SpellsCfg = require(Shared.Config.Spells)
local Loco = require(Shared.Config.Locomotion)
local Map = require(Shared.LiveMap).map -- (the match's map)
local Metrics = require(Shared.Config.Metrics)
local SupCfg = require(Shared.Config.Suppression)
local RagdollCfg = require(Shared.Config.Ragdoll)
local U = require(Shared.Config.Uniforms)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local FrontRules = require(Shared.Rules.Frontline)
local BotBuild = require(Shared.Rules.BotBuild)
local BotTrenches = require(Shared.Rules.BotTrenches)
local Callouts = require(Shared.Rules.BotCallouts)
local Rules = require(Shared.Rules.Bots)
local Sup = require(Shared.Rules.Suppression)
local Armory = require(script.Parent.Armory)
local Artillery = require(script.Parent.Artillery)
local Concussion = require(script.Parent.Concussion)
local Damage = require(script.Parent.Damage)
local DevDummies = require(script.Parent.DevDummies)
local Firing = require(script.Parent.Firing)
local Frontline = require(script.Parent.Frontline)
local Healing = require(script.Parent.Healing)
local Kits = require(script.Parent.Kits)
local Loadouts = require(script.Parent.Loadouts)
local MatchStats = require(script.Parent.MatchStats)
local Ragdoll = require(script.Parent.Ragdoll)
local Showcase = require(script.Parent.Showcase)
local ZoneMatch = require(script.Parent.ZoneMatch)
local Animate = require(script.Animate)
local Routes = require(script.Routes)

local M = Metrics.Movement
local MV = Cfg.Move
local NV = Cfg.Normal
local BG = Cfg.Budget
local CV = MV.Cover
local brainCfg = Cfg.Brain :: any
local BD = Cfg.Build
local TR = Cfg.Trenches
-- the fire step's distance from a trench square's line (Rules/BotTrenches.stepOut: it follows the trench's shape)
local STEP = BotTrenches.stepOut(BuildCfg.Trench.floor, BuildCfg.Trench.wallAngle, TR.rise)

local Types = require(script.Types)
type Target = Types.Target
type Nav = Types.Nav
type Bot = Types.Bot
type Cast = Types.Cast

local State = require(script.State)
local bots, pathOf, ByTrench, Tactics, random, stats, squads, buildLists, budget =
	State.bots,
	State.pathOf,
	State.ByTrench,
	State.Tactics,
	State.random,
	State.stats,
	State.squads,
	State.buildLists,
	State.budget

local Move = require(script.Move)
local liveMode, flat, alive, talk, CO, say, sectorY, sectorPoint, sling, rayParams, eye, aimPart, soldiersNow, friendly, sense, knownSpot, findCover, indoorCells, coverStep, shakenNow, shake, shotPassed, sharedPaths, setGoal, follow, strafeStep, stow, draw, putAway, finish =
	Move.liveMode,
	Move.flat,
	Move.alive,
	Move.talk,
	Move.CO,
	Move.say,
	Move.sectorY,
	Move.sectorPoint,
	Move.sling,
	Move.rayParams,
	Move.eye,
	Move.aimPart,
	Move.soldiersNow,
	Move.friendly,
	Move.sense,
	Move.knownSpot,
	Move.findCover,
	Move.indoorCells,
	Move.coverStep,
	Move.shakenNow,
	Move.shake,
	Move.shotPassed,
	Move.sharedPaths,
	Move.setGoal,
	Move.follow,
	Move.strafeStep,
	Move.stow,
	Move.draw,
	Move.putAway,
	Move.finish

local Act = require(script.Act)
local weigh, doAct, arms, dropCast, staffFire = Act.weigh, Act.doAct, Act.arms, Act.dropCast, Act.staffFire

local Commander = require(script.Commander)
local command = Commander.command

local Report = require(script.Report)
local report, dev = Report.report, Report.dev

local Bots = {}

local count = 0
local folder: Folder? = nil
local cursor = 1 -- the bot the next frame starts with (round-robin)
local governor = Rules.governor(math.max(Cfg.Max.FFA, Cfg.Max.Normal))
local govAt, govTime, govFrames = os.clock(), 0, 0

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
	-- (the admin panel's free Engineer and Grenadier: Config/DevTools.Admin)
	-- Normal: every class free, rolled by weight (Config/Bots.Classes; no points spent); FFA: bought with points
	local normal = b.mode == "Normal"
	local free = normal or workspace:GetAttribute(DevCfg.Admin.FreeEngineerAttribute) == true
	local gratis = {
		Engineer = free,
		Grenadier = normal or workspace:GetAttribute(DevCfg.Admin.FreeGrenadierAttribute) == true,
	}
	local weights = {}
	for _, c in Cfg.Classes do
		local def = Classes.Defs[c.key]
		if def and not def.locked then
			table.insert(options, { key = c.key, cost = if normal or (gratis :: any)[c.key] then 0 else def.cost })
			table.insert(weights, { key = c.key, weight = c.weight or 0 })
			push[c.key] = c.push
		end
	end
	local key, cost =
		Rules.chooseClass(Loadouts.botPoints(b.id), options, Cfg.Buy, random:NextNumber(), random:NextNumber())
	if normal then
		key, cost = Rules.rollClass(weights, random:NextNumber()) or options[1].key, 0
	end
	-- gun duty (Config/Bots.Build.Crews): an Engineer while its side has too few guns standing, if it can pay
	b.crew = nil
	local sb = b.side and buildLists[b.side :: string]
	local eng = Classes.Defs.Engineer
	local engCost = if free then 0 elseif eng then eng.cost else math.huge
	if sb and sb.front and eng and not eng.locked and engCost <= Loadouts.botPoints(b.id) then
		local crews = 0
		for _, o in bots do
			if o ~= b and o.side == b.side and o.crew then
				crews += 1
			end
		end
		if BotBuild.crewWanted(sb.guns, crews, BD.Crews) then
			key, cost, b.crew = "Engineer", engCost, true
		end
	end
	-- dugout duty (Config/Bots.Dugouts.engineers): an Engineer while its side has dugouts to dig, if it can pay
	b.dugouts = nil
	if not b.crew and sb and sb.digging > 0 and eng and not eng.locked and engCost <= Loadouts.botPoints(b.id) then
		local on = 0
		for _, o in bots do
			if o ~= b and o.side == b.side and o.dugouts then
				on += 1
			end
		end
		if on < Cfg.Dugouts.engineers then
			key, cost, b.dugouts = "Engineer", engCost, true
		end
	end
	if cost > 0 then
		Loadouts.botPay(b.id, cost)
		stats.upgrades += 1
	end
	return key, push[key]
end

local spawnBody: (b: Bot) -> ()

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
	humanoid.RequiresNeck = false -- the ragdoll loosens the Neck (src/server/Ragdoll): never a death by itself
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
	b.grenades, b.act, b.away, b.shovel, b.cast, b.slung = nil, nil, false, nil, nil, nil
	b.work, b.workState, b.guard = nil, nil, nil
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
		-- (its side's trench there heats up: Config/Bots.Dugouts.Heat)
		if b.side then
			Tactics.dug.note("death", root.Position.X, root.Position.Z, b.deadAt, b.side)
			-- (the admin trench stats: in a trench or the open, by a shell or not; Rules/BotTrenches.deathKind)
			local squares = {}
			for _, sb in buildLists do
				for _, t in sb.trench do
					if t.built then
						table.insert(squares, t)
					end
				end
			end
			local p = root.Position
			local inT, byShell =
				BotTrenches.deathKind(p.X, p.Z, b.deadAt, squares, ByTrench.blasts, Cfg.Dugouts.shell, TR.Stats)
			local d = ByTrench.deaths[b.side :: string] or { all = 0, trench = 0, shell = 0 }
			ByTrench.deaths[b.side :: string] = d
			d.all += 1
			d.trench += if inT then 1 else 0
			d.shell += if byShell then 1 else 0
		end
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
	b.grenades, b.act, b.away, b.shovel, b.cast, b.slung = nil, nil, false, nil, nil, nil
	b.work, b.workState, b.guard = nil, nil, nil
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
	ByTrench.paths[b.id] = nil
end

-- sensing ------------------------------------------------------------------------------------------------------------

-- where a bot guarding a teammate stands (Config/Bots.Actions.Guard): by them, nil while near enough or none
local function guardSpot(b: Bot): Vector3?
	local g = b.guard
	local part = g and g.who:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not part or not b.root then
		return nil
	end
	local at = (part :: BasePart).Position
	return if flat(at - (b.root :: BasePart).Position).Magnitude > Cfg.Actions.Guard.near then at else nil
end

local function think(b: Bot, now: number, d: Rules.Difficulty)
	local m, humanoid, root, tool = b.m :: Model, b.humanoid :: Humanoid, b.root :: BasePart, b.tool :: Tool
	local entry = Firing.entry(tool)
	local staff = W[b.weapon] ~= nil and W[b.weapon].class == "Staff"
	if not entry and not staff then
		return
	end
	if Ragdoll.active(m) or m:GetAttribute("GetUp") ~= nil then
		local turn = b.turn :: AlignOrientation
		turn.Enabled = false
		dropCast(b)
		if not Ragdoll.active(m) then
			humanoid:MoveTo(root.Position) -- getting up (src/server/DevDummies.getUp): standing still meanwhile
		end
		finish(b)
		return -- (down: nothing until it is up again)
	end
	if m:GetAttribute(FrontCfg.HoldAttribute) ~= nil then
		finish(b)
		dropCast(b)
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
	-- Normal: on a gun, or walking to the one it was given (src/server/Bots/Crew), instead of all the rest
	if b.mode == "Normal" and (b.gun or Artillery.gunOf(m)) and Tactics.crew.think(b, now) then
		return
	end
	-- Normal: a drag, a heal or a grenade instead of fighting for a while (Rules/BotActions)
	if b.mode == "Normal" then
		debug.profilebegin("Bots.act")
		if not b.act and now >= b.actAt then
			weigh(b, now)
		end
		local acting = b.act ~= nil and doAct(b, now)
		debug.profileend()
		if acting then
			dropCast(b)
			return
		end
	end
	-- cover from the threat, while there is one
	local threatened = b.threatAt ~= nil and now - (b.threatAt :: number) < brainCfg.ThreatMemory
	local floor = b.postFloor
	local engaged = threatened or b.spotted or b.brain.targetId ~= nil
	if floor and engaged and flat((floor :: Vector3) - root.Position).Magnitude <= STEP + 3 then
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

	local kitNow = arms(b, entry, now)
	local target = b.target
	local senses: Rules.Senses = {
		now = now,
		health = humanoid.Health / math.max(humanoid.MaxHealth, 1),
		magazine = kitNow.magazine,
		chambered = kitNow.chambered,
		spent = kitNow.spent,
		busy = kitNow.busy,
		loading = kitNow.loading,
		capacity = kitNow.capacity,
		auto = kitNow.auto,
		target = if target then { id = target.model, distance = target.distance, visible = target.visible } else nil,
		hurtAt = b.hurtAt,
		threatAt = b.threatAt,
		spotted = b.spotted,
		cover = coverState,
		push = b.push,
		role = b.role,
		suppressed = shakenNow(b, now),
		-- (a Mage's medium shots go at a known enemy's cover too: user "Soldiers and their cover")
		suppress = (b.role == "Support" or staff) and knownSpot(b, now) ~= nil,
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
	elseif intent.reload and not staff then
		say(b, "Reload")
	end

	-- where to go
	debug.profilebegin("Bots.move")
	local zone, radius = objective(b)
	local goal: Vector3? = nil
	local targetPart = if target then aimPart(target.model) else nil
	local suppressAt = if (b.role == "Support" or staff) and not targetPart then knownSpot(b, now) else nil
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
		-- (a teammate it guards: by them; a build job it took: there; fighting on the way: Config/Bots.Actions.Guard,
		-- Build.Work)
		if b.guard then
			goal = guardSpot(b) or root.Position -- (by them: it stays)
		elseif b.work then
			goal = b.work.at
		end
		b.nav.direct = nil
	elseif move == "Hold" then
		-- on its spot (covering fire, or a hold spot in the zone); there, it stands
		local post = if b.guard then guardSpot(b) elseif b.work then b.work.at else (b.goal or b.post)
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
	-- a dugout (Config/Bots.Dugouts): paths don't go down its steps, so a path to its foot, then straight down them to
	-- the room, crouched under its low doorway; out of it, straight up to the foot first
	local foot = b.postFoot
	local handle = b.anim
	if handle then
		local near = foot and flat(foot - root.Position).Magnitude
		handle.crouch(
			foot ~= nil and (near :: number) <= 16 and (root.Position.Y < foot.Y - 1 or (near :: number) <= 3.5)
		)
	end
	if foot then
		local below = root.Position.Y < foot.Y - 1 and flat(foot - root.Position).Magnitude <= 16
		local atSteps = flat(foot - root.Position).Magnitude <= 3.5
		if b.postKind == "dugout" then
			if goal and goal == b.post and (below or atSteps) then
				b.nav.direct, b.nav.goal, goal = b.post, nil, nil
			elseif goal and goal == b.post then
				goal = foot
			end
		elseif below then
			b.nav.direct, b.nav.goal, goal = foot, nil, nil
		else
			b.postFoot = nil
		end
	end
	-- the admin panel's walk through a house (Bots.dev "House"): its spots in turn, then back out
	local walk = Report.houseGoal(b, now)
	if walk then
		goal, b.nav.direct = walk, nil
	end
	if goal then
		setGoal(b, goal, now)
	elseif move ~= "Strafe" and move ~= "Peek" and move ~= "Hold" then
		b.nav.goal = nil
	end
	if Healing.busy(m) or (b.cast and (b.cast :: Cast).stage == #SpellsCfg.Stages) then
		-- being healed: it stands for it (the heal breaks off once the two are Break studs apart); charging a mega shot
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

	-- the weapon: a butt stroke now and then with the target in reach (Config/Bots.Melee), else the gun
	local struck = false
	local MC = Cfg.Melee
	if
		not staff
		and target
		and target.visible
		and now >= (b.meleeAt or 0)
		and target.distance <= Tactics.meleeCfg.Hit.reach - MC.margin
	then
		b.meleeAt = now + MC.every
		local part = aimPart(target.model)
		if part and BotBuild.strikes(kitNow.magazine <= 0 or kitNow.loading, random:NextNumber(), MC) then
			local dir = part.Position - eye(b)
			if dir.Magnitude > 1e-3 and Tactics.melee.strikeAs(m, dir.Unit) then
				struck = true
				stats.strikes += 1
				local holds = W[b.weapon] and (W[b.weapon].holds :: any)
				if b.anim and holds and holds.strike then
					(b.anim :: Animate.Handle).play(holds.strike)
				end
			end
		end
	end
	if struck then
		return -- (the stroke is under way: no shot, bolt or reload until the gun is back)
	end
	if staff then
		staffFire(b, intent.fire, target, suppressAt, facing, d, now)
	elseif intent.stopLoad then
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
			-- only with a clear line from the muzzle (the eye's look can be stale, or over a lip the muzzle is under)
			rayParams.FilterDescendantsInstances = { m }
			local hit = workspace:Raycast(origin, line, rayParams)
			stats.rays += 1
			if hit and not hit.Instance:IsDescendantOf(target.model) then
				stats.blocked += 1
			elseif Firing.fireAs(m, origin, dir, random:NextInteger(1, 2147483646)) then
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
			-- only with a clear line to near the spot (no covering fire into a hill or a wall: Config/Bots.Sight)
			rayParams.FilterDescendantsInstances = { m }
			local hit = workspace:Raycast(origin, line, rayParams)
			stats.rays += 1
			if hit and hit.Distance < line.Magnitude - Cfg.Sight.near then
				stats.blocked += 1
			elseif Firing.fireAs(m, origin, dir, random:NextInteger(1, 2147483646)) then
				stats.shots += 1
				stats.covering += 1
			end
		end
	end
end

-- the director --------------------------------------------------------------------------------------------------------

local nextJoin, nextLeave = 0, 0

-- tops the bots of `side` (nil: FFA's) up or down to `want`, one in or out at a time; true when it acted
-- how far `b` is from the nearest player's soldier (studs; math.huge: none), for picking who retires
local function fromPlayers(b: Bot): number
	local root = b.root
	if not root then
		return math.huge
	end
	local best = math.huge
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			best = math.min(best, (r.Position - (root :: BasePart).Position).Magnitude)
		end
	end
	return best
end

-- One group (a side in Normal, everyone in FFA) towards `want` bots: one in at a time while short; over it, the surplus
-- marked retiring (Rules/Bots.retiring), a dead retiring one gone (the living fight on and leave at their death:
-- user 2026-11-04); back at or under it, every mark lifted.
local function balance(mode: string, side: string?, want: number, now: number): boolean
	local have = 0
	local cands: { Rules.RetireCand } = {}
	local byId: { [number]: number } = {}
	for i, b in bots do
		if b.side == side then
			have += 1
			byId[b.id] = i
			local m = b.m
			table.insert(cands, {
				id = b.id,
				dead = b.deadAt ~= nil,
				marked = b.retiring == true,
				crewing = b.gun ~= nil or (m ~= nil and Artillery.gunOf(m) ~= nil),
				far = fromPlayers(b),
			})
		end
	end
	local marks = Rules.retiring(cands, have - want)
	local retiring = 0
	for id, i in byId do
		bots[i].retiring = if marks[id] then true else nil
		retiring += if marks[id] then 1 else 0
	end
	local key = Cfg.RetiringAttribute .. (side or "")
	if botFolder():GetAttribute(key) ~= retiring then
		botFolder():SetAttribute(key, retiring)
	end
	if have < want then
		if now >= nextJoin then
			nextJoin = now + (if mode == "Normal" then NV.joinEvery else Cfg.JoinEvery)
			add(mode, side)
			return true
		end
	elseif have > want and now >= nextLeave then
		for id, i in byId do
			if marks[id] and bots[i].deadAt then
				nextLeave = now + Cfg.LeaveEvery
				remove(i)
				return true
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
		-- (a test's pin may go past Max, Config/Bots.PinMax; a new pin starts the governor at it)
		local ceiling = Rules.ceiling(Cfg.Max.Normal, pinned, Cfg.PinMax.Normal)
		if governor.pinned ~= pinned then
			governor.pinned, governor.cap, governor.bad, governor.good = pinned, ceiling, 0, 0
		end
		local cap = math.min(ceiling, governor.cap)
		wants.West, wants.East = Rules.wantedSides(Cfg.Fill.Normal, players.West, players.East, cap, pinned)
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
			if b.retiring or have[key] > wants[key] then -- (a retiring bot doesn't come back)
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
	-- each side's bots, for the menu's team counts ("players + bots": src/client/Menus)
	local onSide = { West = 0, East = 0 }
	for _, b in bots do
		if b.side == "West" or b.side == "East" then
			onSide[b.side] += 1
		end
	end
	for side, n in onSide do
		if botFolder():GetAttribute(Cfg.SideAttribute .. side) ~= n then
			botFolder():SetAttribute(Cfg.SideAttribute .. side, n)
		end
	end
	for _, side in { "West", "East", "" } do
		local want = wants[side]
		if want and balance(mode :: string, if side == "" then nil else side, want, now) then
			return
		end
	end
end

-- Forgets every map-derived thing the bots keep (a new match: the map put back; or the match moved to another map,
-- src/server/Frontline's vote): spots, build lists, squads, crews, each sector's ground, dug foxholes, blasts, shared
-- paths. Their trench marks go at the next commander tick (ByTrench.mark: no build list, no mark).
Bots.dev = dev

function Bots.forgetMap()
	Routes.clear()
	table.clear(indoorCells)
	table.clear(buildLists)
	table.clear(squads)
	Tactics.crew.clear()
	Tactics.fell.clear()
	table.clear(sectorY)
	table.clear(Tactics.dug.holes)
	table.clear(Tactics.dug.tried)
	table.clear(Tactics.dug.heat)
	table.clear(Tactics.dug.use)
	table.clear(ByTrench.blasts)
	table.clear(ByTrench.deaths)
	ByTrench.counts = {}
	table.clear(sharedPaths)
	-- (each side back to walking until its first contact there: Config/Bots.Front)
	table.clear(State.fronts.sides)
	State.fronts.owners = nil
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
	Tactics.crew.init({
		bots = bots,
		alive = alive,
		setGoal = setGoal,
		follow = follow,
		finish = finish,
		dropCast = dropCast,
		putAway = putAway,
		aimPart = aimPart,
		friends = function(b: Bot)
			local all, n = soldiersNow()
			local m = b.m :: Model
			local kit = m:GetAttribute("Kit")
			local out = {}
			for k = 1, n do
				local o = all[k]
				if o.model ~= m and friendly(m, kit, o) then
					table.insert(out, { x = o.pos.X, z = o.pos.Z })
				end
			end
			return out
		end,
	})
	-- explosions suppress bots as they do players (Config/Suppression.Blast), and count as a threat close by
	Damage.onBlast(function(pos: Vector3, kg: number)
		local now = os.clock()
		local blasts = ByTrench.blasts
		table.insert(blasts, { x = pos.X, z = pos.Z, at = now, kg = kg })
		if #blasts > 24 then
			table.remove(blasts, 1)
		end
		-- (a shell, not a grenade, heats the trenches round it: Config/Bots.Dugouts.Heat)
		if kg >= Cfg.Dugouts.shell then
			Tactics.dug.note("shell", pos.X, pos.Z, now)
		end
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
				-- (nothing of the last match's ground kept: it may have been another map)
				b.postSector, b.postFloor, b.postKind, b.postFoot, b.gun, b.gunWait = nil, nil, nil, nil, nil, nil
				b.wander, b.coverJob, b.work, b.workState, b.guard = nil, nil, nil, nil, nil
				spawnBody(b)
			end
		end
	end
	ZoneMatch.onMatchStart(function()
		respawnAll("FFA")
	end)
	Frontline.onMatchStart(function()
		Bots.forgetMap() -- (the map is put back, or another map: spots worked out again)
		respawnAll("Normal")
	end)
	-- the match moved to another map (src/server/Frontline: the vote's pick): nothing of the old one kept meanwhile
	workspace:GetAttributeChangedSignal(FrontCfg.MapAttribute):Connect(Bots.forgetMap)
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
		if Frontline.over() then
			return -- (a Normal match's end: everyone stands frozen while the table, vote and armory play)
		end
		local t0 = os.clock()
		budget.frame += 1
		budget.rays = BG.raysPerFrame
		budget.paths = math.min(math.max(BG.pathsPerSecond, 1), budget.paths + BG.pathsPerSecond * dt)
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
			local max = if liveMode() == "Normal"
				then Rules.ceiling(Cfg.Max.Normal, governor.pinned, Cfg.PinMax.Normal)
				else Cfg.Max.FFA
			if n > 0 then
				local ms = govTime / govFrames * 1000
				Rules.govern(governor, ms, workspace:GetRealPhysicsFPS(), t0 - govAt, n, max, BG.governor)
			end
			govAt, govTime, govFrames = t0, 0, 0
		end
		report(t0, governor)
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
