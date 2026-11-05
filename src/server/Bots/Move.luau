--!strict
-- A bot's senses and moves, kept out of src/server/Bots: what it sees and hears (the frame's snapshot of every
-- soldier, sight rays, shots passing), cover and buildings to hide in, paths and following them, its gun slung or
-- drawn, and callouts.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local Hitches = require(Shared.Hitches)
local DamageCfg = require(Shared.Config.Damage)
local FrontCfg = require(Shared.Config.Frontline)
local IndoorCfg = require(Shared.Config.Indoors)
local Net = require(Shared.Net)
local Map = require(Shared.LiveMap).map -- (the match's map)
local ModesCfg = require(Shared.Config.Modes)
local SupCfg = require(Shared.Config.Suppression)
local U = require(Shared.Config.Uniforms)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local Buildings = require(Shared.Rules.BotBuildings)
local Callouts = require(Shared.Rules.BotCallouts)
local Rules = require(Shared.Rules.Bots)
local ShotRules = require(Shared.Rules.ShotAudio)
local Sup = require(Shared.Rules.Suppression)
local Teams = require(Shared.Rules.Teams)
local Armory = require(script.Parent.Parent.Armory)
local Damage = require(script.Parent.Parent.Damage)
local DevDummies = require(script.Parent.Parent.DevDummies)
local Doors = require(script.Parent.Parent.Doors)
local Dragging = require(script.Parent.Parent.Dragging)
local Healing = require(script.Parent.Parent.Healing)
local Indoors = require(script.Parent.Parent.Indoors)
local Ragdoll = require(script.Parent.Parent.Ragdoll)
local Animate = require(script.Parent.Animate)

local MV = Cfg.Move
local NV = Cfg.Normal
local SQ = Cfg.Squads
local CV = MV.Cover
local brainCfg = Cfg.Brain :: any
local IN = Cfg.Indoors
local TM = Cfg.TrenchMove

local Types = require(script.Parent.Types)
type Target = Types.Target
type Bot = Types.Bot
type CoverJob = Types.CoverJob
type Known = Types.Known
type SquadState = Types.SquadState
type Soldier = Types.Soldier
type SharedPath = Types.SharedPath

local State = require(script.Parent.State)
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

local function liveMode(): string?
	local mode = workspace:GetAttribute(ModesCfg.Attribute)
	return if type(mode) == "string" then mode else nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function alive(b: Bot): boolean
	return b.m ~= nil and b.humanoid ~= nil and (b.humanoid :: Humanoid).Health > 0 and (b.m :: Model).Parent ~= nil
end

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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function eye(b: Bot): Vector3
	return if b.head then (b.head :: BasePart).Position else (b.root :: BasePart).Position + Vector3.yAxis * Cfg.Eye
end

local function aimPart(target: Model): BasePart?
	return (target:FindFirstChild("Torso") or target:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

local snapshot: { Soldier } = {}
local snapCount = 0
local snapFrame = -1

local function soldiersNow(): ({ Soldier }, number)
	if snapFrame == budget.frame then
		return snapshot, snapCount
	end
	snapFrame = budget.frame
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
	local near = math.huge
	for k = 1, n do
		local other = all[k]
		if other.model == m or friendly(m, kit, other) then
			continue
		end
		local off = other.pos - from
		local dist = off.Magnitude
		near = math.min(near, dist)
		if Rules.inSight(off.X, off.Z, dist, facing.X, facing.Z, d.spotRange, d.fov, alert) then
			table.insert(seen, { model = other.model, distance = dist, visible = false })
			parts[other.model] = other
		end
	end
	b.enemyNear = near
	local rays = math.min(#seen, Cfg.SenseNearest)
	if rays > budget.rays then
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
		budget.rays -= 1
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
		b.sightAt = now
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

-- studs from the bot to the nearest enemy spot its squad knows (math.huge none; Config/Bots.Calm)
local function knownNear(b: Bot, now: number): number
	local sq = b.squad and squads[b.squad :: string]
	local root = b.root
	if not sq or not root then
		return math.huge
	end
	local best = math.huge
	for _, k in (sq :: SquadState).known do
		if now - k.at <= SQ.knownFor then
			best = math.min(best, flat(k.pos - (root :: BasePart).Position).Magnitude)
		end
	end
	return best
end

-- a ground point under (x, z) near `y`, or nil (off the map, under water)
local function groundAt(x: number, y: number, z: number, exclude: { Instance }): Vector3?
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(Vector3.new(x, y + 8, z), Vector3.new(0, -24, 0), rayParams)
	stats.rays += 1
	budget.rays -= 1
	return hit and hit.Position
end

-- whether the threat's eye `from` can't see a soldier standing at the ground point `p`
local function hidden(from: Vector3, p: Vector3, exclude: { Instance }): boolean
	local chest = p + Vector3.yAxis * (CV.chest + 1.8)
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(from, chest - from, rayParams)
	stats.rays += 1
	budget.rays -= 1
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
	local root = b.root :: BasePart
	-- sheltering under shelling: its dugout is its cover (Config/Bots.Dugouts)
	if b.postKind == "dugout" and b.post then
		b.cover, b.coverFrom, b.coverJob = b.post, threat, nil
		return
	end
	-- shot at by its own dug trench: down into it (Config/Bots.TrenchMove.cover)
	local sb = b.side and buildLists[b.side :: string]
	if sb and b.threatAt and now - (b.threatAt :: number) < brainCfg.ThreatMemory then
		local best, bestD, hole = nil, TM.cover, false
		for _, t in sb.trench do
			local d = flat(t.at - root.Position).Magnitude
			if t.built and d < bestD then
				best, bestD = t.at, d
			end
		end
		-- (or a foxhole its side dug, one bot to it: Config/Bots.Dugouts.Fox)
		for _, h in Tactics.dug.holes do
			local d = flat(h.floor - root.Position).Magnitude
			local free = d < bestD
			for _, o in bots do
				if free and o ~= b and (o.cover == h.floor or o.post == h.floor) then
					free = false
				end
			end
			if free then
				best, bestD, hole = h.floor, d, true
			end
		end
		if best then
			if b.cover ~= best then
				if hole then
					stats.intoHole += 1
				else
					stats.intoTrench += 1
				end
			end
			b.cover, b.coverFrom, b.coverJob = best, threat, nil
			return
		end
	end
	if budget.rays < 1 then
		return
	end
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
		local mid = Vector3.new((cx + 0.5) * IN.cell, at.Y, (cz + 0.5) * IN.cell)
		c = { at = now, spots = Indoors.near(mid, IN.cell * 0.71 + within + IN.slack) }
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
	if budget.rays < CV.perRing * 2 then
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

local sharedPaths: { SharedPath } = {}

local function sharedPath(from: Vector3, goal: Vector3, now: number, danger: boolean): ({ PathWaypoint }?, number)
	local S = MV.Share
	for i = #sharedPaths, 1, -1 do
		local c = sharedPaths[i]
		if now - c.at > S.keep then
			table.remove(sharedPaths, i)
		elseif c.danger == danger and flat(c.goal - goal).Magnitude <= S.goalWithin then
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
		wps, start = sharedPath(from, goal, now, b.danger == true)
	end
	if wps then
		stats.pathsShared += 1
		nav.waypoints, nav.index, nav.pathAt = wps, start, now
		return true
	end
	if budget.paths < 1 then
		stats.pathsDeferred += 1
		return false
	end
	budget.paths -= 1
	nav.computing = true
	nav.pathAt = now
	local danger = b.danger == true
	local paths = if danger then ByTrench.paths else pathOf
	local path = paths[b.id]
	if not path then
		path = PathfindingService:CreatePath({
			AgentRadius = MV.AgentRadius,
			AgentHeight = MV.AgentHeight,
			AgentCanJump = true,
			WaypointSpacing = MV.WaypointSpacing,
			-- (through doorways and up stairs: src/server/Indoors' links; knowing there's danger, along trenches)
			Costs = if danger then ByTrench.costs else IndoorCfg.PathCosts,
		})
		paths[b.id] = path
	end
	if danger then
		stats.dangerPaths += 1
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
			table.insert(sharedPaths, { goal = goal, waypoints = waypoints, at = os.clock(), danger = danger })
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
	-- knowing there's danger it keeps to trenches, and walks straight across once there's none: a fresh path
	if b.mode == "Normal" and b.root then
		local danger = ByTrench.danger(b, now)
		if danger ~= (b.danger == true) then
			b.danger = danger
			nav.pathAt = -1
		end
	end
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

-- a door swung open or shut (src/server/Doors): the paths near it are stale (open, it stands in the room and paths go
-- round it; shut, through it), so the shared paths by it are dropped and the bots close by path again, once the navmesh
-- has caught up (Config/Bots.Indoors.Swung)
Doors.onSwung(function(door: Model)
	local panel = door.PrimaryPart
	if not panel then
		return
	end
	task.wait(IN.Swung.after)
	local at = panel.Position
	for i = #sharedPaths, 1, -1 do
		for _, w in sharedPaths[i].waypoints do
			if (w.Position - at).Magnitude < IN.Swung.near then
				table.remove(sharedPaths, i)
				break
			end
		end
	end
	for _, b in bots do
		if b.root and b.nav.goal and flat((b.root :: BasePart).Position - at).Magnitude < IN.Swung.near then
			b.nav.pathAt = -1
			stats.doorRepaths += 1
		end
	end
end)

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
			-- (shut, out of its reach yet or being shut by someone: it walks on and tries again, never stands there)
			local wasBusy = door ~= nil and door:GetAttribute("Busy") ~= nil
			local opening = door ~= nil and not Doors.isOpen(door) and Doors.openFor(b.m :: Model, door)
			if opening and not wasBusy then
				nav.doorAt = now
				stats.doors += 1
			end
			if door and Buildings.waitForDoor(true, d, opening, now - nav.doorAt, IN) then
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
			-- a flight of stairs on the way (a "Stairs" link's waypoint): up and down its middle
			if wp.Label == IndoorCfg.Links.stairs then
				target = Indoors.stairWay(root.Position, wp.Position)
				if target ~= wp.Position then
					stats.stairSteps += 1
				end
			end
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
			-- a teammate walking too close: the step pushed aside, away from them (Config/Bots.Spread)
			local mate = mateNear(b, root.Position, Cfg.Spread.apart)
			local along = flat(wp.Position - root.Position)
			if mate and along.Magnitude > Cfg.Spread.push and wp.Label ~= IndoorCfg.Links.stairs then
				local away = flat(root.Position - mate :: Vector3)
				local u = along.Unit
				local side = away - u * away:Dot(u)
				side = if side.Magnitude > 1e-3 then side.Unit else u:Cross(Vector3.yAxis)
				target = wp.Position + side * Cfg.Spread.push
				stats.spread += 1
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
			-- a shut door right in front of it (a path straight through a doorway, with no door link on the way: the
			-- navmesh fits it through some, and a shut door passes paths through): it opens it
			local door = Doors.nearest(root.Position, IN.bump)
			if door and not Doors.isOpen(door) and Doors.openFor(b.m :: Model, door) then
				nav.doorAt = now
				stats.doorsBumped += 1
			elseif nav.direct then
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
-- the humanoid reached the point it was walking to, between thinks (its MoveToFinished): on along its path at once,
-- not standing until its next think (Config/Bots.Move.ArriveGap); only a bot its last think walked along a path (not
-- down, crewing, acting, stepping straight to a point or waiting at a door)
local function arrivedAt(b: Bot, reached: boolean)
	local nav = b.nav
	local now = os.clock()
	if not reached or not b.root or not b.humanoid or b.deadAt or b.act or nav.direct then
		return
	end
	if not nav.goal or not nav.waypoints[nav.index] or now - nav.doorAt < IN.doorWait then
		return
	end
	if now - (nav.walkedAt or -math.huge) > MV.ArriveStale or now - (nav.arrivedAt or -math.huge) < MV.ArriveGap then
		return
	end
	nav.arrivedAt = now
	stats.arrivals += 1
	follow(b, now)
end

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
	local t0 = os.clock()
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
		Hitches.since("Bot shovel out", t0)
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

return {
	liveMode = liveMode,
	flat = flat,
	alive = alive,
	talk = talk,
	CO = CO,
	say = say,
	terrainOnly = terrainOnly,
	sectorY = sectorY,
	sectorPoint = sectorPoint,
	centre = centre,
	sling = sling,
	rayParams = rayParams,
	eye = eye,
	aimPart = aimPart,
	snapshot = snapshot,
	snapCount = snapCount,
	snapFrame = snapFrame,
	soldiersNow = soldiersNow,
	friendly = friendly,
	sense = sense,
	knownSpot = knownSpot,
	knownNear = knownNear,
	groundAt = groundAt,
	hidden = hidden,
	exclusions = exclusions,
	findCover = findCover,
	enterable = enterable,
	canEnter = canEnter,
	indoorCells = indoorCells,
	indoorNear = indoorNear,
	asSpot = asSpot,
	mateNear = mateNear,
	coverStep = coverStep,
	shakenNow = shakenNow,
	shake = shake,
	asPoint = asPoint,
	ffa = ffa,
	heardShot = heardShot,
	shotPassed = shotPassed,
	sharedPaths = sharedPaths,
	sharedPath = sharedPath,
	computePath = computePath,
	inside = inside,
	setGoal = setGoal,
	follow = follow,
	strafeStep = strafeStep,
	arrived = arrivedAt,
	stow = stow,
	draw = draw,
	putAway = putAway,
	face = face,
	holdShovel = holdShovel,
	finish = finish,
}
