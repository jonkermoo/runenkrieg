--!strict
-- Each side's commander in Normal, kept out of src/server/Bots: once a second it reads the sectors, sends its bots
-- to attack or defend, forms the squads (lanes, approach spots, bounds, pushes, saps) and keeps the side's build list
-- (trenches, dugouts, wire, guns).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local FrontCfg = require(Shared.Config.Frontline)
local BuildCfg = require(Shared.Config.Build)
local Map = require(Shared.LiveMap).map -- (the match's map)
local MapTerrain = require(Shared.Rules.MapTerrain)
local ArtCfg = require(Shared.Config.Artillery)
local ArtRules = require(Shared.Rules.Artillery)
local FrontRules = require(Shared.Rules.Frontline)
local Orders = require(Shared.Rules.BotOrders)
local Buildings = require(Shared.Rules.BotBuildings)
local BotBuild = require(Shared.Rules.BotBuild)
local BuildRules = require(Shared.Rules.Build)
local BotTrenches = require(Shared.Rules.BotTrenches)
local BotTrenchCare = require(Shared.Rules.BotTrenchCare)
local BotSap = require(Shared.Rules.BotSap)
local BotArcs = require(Shared.Rules.BotArcs)
local BotCrew = require(Shared.Rules.BotCrew)
local BotFront = require(Shared.Rules.BotFront)
local BotLanes = require(Shared.Rules.BotLanes)
local Build = require(script.Parent.Parent.Build)
local Trees = require(script.Parent.Parent.Trees)
local Frontline = require(script.Parent.Parent.Frontline)
local Indoors = require(script.Parent.Parent.Indoors)
local Routes = require(script.Parent.Routes)
local Squads = require(Shared.Rules.BotSquads)
local Artillery = require(script.Parent.Parent.Artillery)
local Loadouts = require(script.Parent.Parent.Loadouts)

local NV = Cfg.Normal
local SQ = Cfg.Squads
local RT = Cfg.Routes
local brainCfg = Cfg.Brain :: any
local IN = Cfg.Indoors
local BD = Cfg.Build
local TR = Cfg.Trenches
local CA = TR.Care
local TM = Cfg.TrenchMove
local SP = Cfg.Sap
local CV = Cfg.Move.Cover
local FR = Cfg.Front
local DH = Cfg.Dugouts.Heat
local OF = Cfg.Offensive
local LN = Cfg.Lanes
-- (the lanes' map edges: Config/Bots.Lanes; a map without bounds: as far as Lanes.reach)
local laneBounds: BotLanes.Bounds = (Map :: any).bounds
	or { minX = -math.huge, maxX = math.huge, minZ = -math.huge, maxZ = math.huge }
-- (when each side's sector squads last looked to move a squad between lanes: Lanes.every)
local laneLooked: { [string]: number } = {}
-- (the build list's and the gun spots' settings with the flanks', Config/Bots.Front.Flank)
local Flanked = { plan = table.clone(BD), guns = table.clone(BD.Crews) }
Flanked.plan.Flank = FR.Flank
Flanked.guns.flank = FR.Flank
-- the fire step's distance from a trench square's line (Rules/BotTrenches.stepOut: it follows the trench's shape)
local STEP = BotTrenches.stepOut(BuildCfg.Trench.floor, BuildCfg.Trench.wallAngle, TR.rise)

local Types = require(script.Parent.Types)
type BuildJob = Types.BuildJob
type Sap = Types.Sap
type TrenchSquare = Types.TrenchSquare
type TrenchSystem = Types.TrenchSystem
type Bot = Types.Bot
type SquadState = Types.SquadState
type TrenchPost = Types.TrenchPost
type SideBuild = Types.SideBuild

local State = require(script.Parent.State)
local Clear, bots, ByTrench, Tactics, random, stats, squads, buildLists, Kinds, fronts =
	State.Clear,
	State.bots,
	State.ByTrench,
	State.Tactics,
	State.random,
	State.stats,
	State.squads,
	State.buildLists,
	State.Kinds,
	State.fronts

local Move = require(script.Parent.Move)
local liveMode, flat, alive, say, terrainOnly, sectorPoint, centre, soldiersNow, friendly, indoorNear, asSpot =
	Move.liveMode,
	Move.flat,
	Move.alive,
	Move.say,
	Move.terrainOnly,
	Move.sectorPoint,
	Move.centre,
	Move.soldiersNow,
	Move.friendly,
	Move.indoorNear,
	Move.asSpot

local Report = require(script.Parent.Report)
local label = Report.label

local commandTick = 0
-- support-line squares a dugout was refused in (Build.dugoutFor: no ground round its room), until when (os.clock)
local noDugout: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

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

-- the map's marked spots per sector (Rules/MapTerrain.tactics on a map with the leg pattern, else its own `tactics`)
local OP = Cfg.OffPoint
local Marks: { [number]: any } = (if (Map :: any).legs then MapTerrain.tactics(Map) else (Map :: any).tactics) or {}

-- Where a squad of `side` in lane `lane` at `mid` forms up for its offensive on sector `sector`
-- (Config/Bots.Offensive.Forward): the map's marked gather spots with room, else the scored spots out from the zone, none
-- on a point its side holds; `used`: the squads on each spot already. Nil until there are any. In a lane (`near`, its
-- point: Config/Bots.Lanes) only spots within Lanes.gatherNear of it, else beside it (Lanes.gatherNear apart across the
-- enemy's way for each squad there already).
local function gatherPoint(
	side: string,
	sector: number,
	mid: Vector3,
	lane: number,
	used: { [Vector3]: number },
	near: Vector3?
): Vector3?
	local FW = OF.Forward
	local function choose(list: { any }): Vector3?
		local spots, rolls, count = {}, {}, {}
		for _, sp in list do
			if near and (sp.x - near.X) ^ 2 + (sp.z - near.Z) ^ 2 > LN.gatherNear ^ 2 then
				continue
			end
			if Orders.clearOfOwn(sp.x, sp.z, Map.sectors, fronts.owners, side, FW.ownClear) then
				table.insert(spots, sp)
				rolls[#spots] = random:NextNumber()
				count[#spots] = used[sp.pos] or 0
			end
		end
		local i = Orders.gatherSpot(spots, count, lane, mid.X, mid.Z, rolls, RT.weights, RT.nearCap, FW.perSpot)
		return if i then spots[i].pos else nil
	end
	local s = Map.sectors[sector]
	local tx, tz = BotBuild.toward(Map.sectors, sector, side)
	local marked = {}
	for _, sp in BotBuild.serving(Marks[sector] and Marks[sector].gather, side) do
		table.insert(marked, {
			x = sp.x,
			z = sp.z,
			pos = Routes.ground(sp.x, sp.z),
			hidden = true,
			near = RT.nearCap,
			lane = Squads.lane(s.x - tx * 100, s.z - tz * 100, s.x, s.z, sp.x, sp.z, RT.laneWithin),
		})
	end
	local at = choose(marked)
	if at then
		return at
	end
	local scored = {}
	for _, sp in Routes.gatherSpots(sector, side) or {} do
		table.insert(
			scored,
			{ x = sp.pos.X, z = sp.pos.Z, pos = sp.pos, hidden = sp.hidden, near = sp.near, lane = sp.lane }
		)
	end
	local got = choose(scored)
	if got or not near then
		return got
	end
	local n = 0
	for spot, k in used do
		n += if flat(spot - near :: Vector3).Magnitude <= LN.gatherNear then k else 0
	end
	local x, z = BotBuild.markedPlace(near.X, near.Z, n, LN.gatherNear, tx, tz)
	return Routes.ground(x, z)
end

-- a holder's marked spot in sector `i` nearest `p` with room, or nil: the zone's own (`inZone`), else the cover and
-- support spots naming its side ahead of the point; with `ok`, only spots it passes (its lane: Config/Bots.Lanes)
local function markedPost(
	side: string,
	i: number,
	p: Vector3,
	inZone: boolean,
	ok: ((x: number, z: number) -> boolean)?
): Vector3?
	local t = Marks[i]
	if not t then
		return nil
	end
	local list = BotBuild.serving(t.cover, nil)
	if not inZone then
		local s = Map.sectors[i]
		local tx, tz = BotBuild.toward(Map.sectors, i, side)
		list = BotBuild.serving(t.cover, side)
		for _, sp in BotBuild.serving(t.support, side) do
			table.insert(list, sp)
		end
		list = BotBuild.aheadOf(list, s.x, s.z, tx, tz)
	end
	if ok then
		local kept = {}
		for _, sp in list do
			if ok(sp.x, sp.z) then
				table.insert(kept, sp)
			end
		end
		list = kept
	end
	-- (its holders stand OP.gap apart across the enemy's way: Rules/BotBuild.markedPlace)
	local tx, tz = BotBuild.toward(Map.sectors, i, side)
	local used, free = {}, {}
	for k, sp in list do
		local held = {}
		for _, b in bots do
			if b.side == side and b.role == "Hold" and b.post then
				local bp = b.post :: Vector3
				for m = 0, (sp.n or OP.room) - 1 do
					local x, z = BotBuild.markedPlace(sp.x, sp.z, m, OP.gap, tx, tz)
					if not held[m] and (bp.X - x) ^ 2 + (bp.Z - z) ^ 2 <= OP.held ^ 2 then
						held[m] = true
						break
					end
				end
			end
		end
		local n = 0
		for m = 0, (sp.n or OP.room) - 1 do
			if held[m] then
				n += 1
			elseif free[k] == nil then
				free[k] = m
			end
		end
		used[k] = n
	end
	local k = BotBuild.pickMarked(list, used, p.X, p.Z, OP.room)
	if not k then
		return nil
	end
	local x, z = BotBuild.markedPlace(list[k].x, list[k].z, free[k] or 0, OP.gap, tx, tz)
	return Routes.ground(x, z)
end

-- a defender's hold spot in sector `i`: the best one fewest of the side's defenders stand on, off the flag
-- (Config/Bots.OffPoint) where any is; with `ok`, only spots it passes (its lane: Config/Bots.Lanes)
local function holdSpot(
	side: string,
	i: number,
	taken: { [Vector3]: number },
	ok: ((x: number, z: number) -> boolean)?
): Vector3?
	local spots = Routes.spots(i, side, true)
	if not spots or #spots == 0 then
		return nil
	end
	local s = Map.sectors[i]
	local flag = Vector3.new(s.x, 0, s.z)
	local anyOff = false
	for _, sp in spots :: { Routes.Spot } do
		anyOff = anyOff or flat(sp.pos - flag).Magnitude >= OP.clear
	end
	-- (one holder a spot while one is free: the fewest posts within OP.gap first, user 2026-11-10: "when they are in
	-- groups, they are super close together")
	local posts = {}
	for at in taken do
		table.insert(posts, { x = at.X, z = at.Z })
	end
	local best, bestCrowd, bestAt = -math.huge, math.huge, nil
	for _, sp in spots :: { Routes.Spot } do
		if anyOff and flat(sp.pos - flag).Magnitude < OP.clear then
			continue
		end
		if ok and not ok(sp.pos.X, sp.pos.Z) then
			continue
		end
		local crowd = BotBuild.crowd(sp.pos.X, sp.pos.Z, posts, OP.gap)
		local v = Squads.scoreSpot(sp, crowd, random:NextNumber(), RT.weights, RT.nearCap)
		if crowd < bestCrowd or (crowd == bestCrowd and v > best) then
			best, bestCrowd, bestAt = v, crowd, sp.pos
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
	local tx, tz = BotBuild.toward(Map.sectors, i, side) -- (the enemy's way, from the live map's sector chain)
	local k = Buildings.pickHold(list, c.X, c.Z, within, tx, tz, rolls, IN)
	if not k then
		return nil
	end
	local sp = spots[k]
	taken[sp.at] = (taken[sp.at] or 0) + 1
	return sp
end

-- the nearest free fire step (`want` "step") or support-line place ("reserve") of a side's trenches to `p`, taken; with
-- `ok`, only places it passes (its lane: Config/Bots.Lanes)
local function trenchPost(
	sb: SideBuild,
	want: string,
	taken: { [Vector3]: number },
	p: Vector3,
	ok: ((x: number, z: number) -> boolean)?
): TrenchPost?
	-- (one with no held post within OP.gap first, every other square: user 2026-11-10, "when they are in groups, they
	-- are super close together")
	local posts = {}
	for at in taken do
		table.insert(posts, { x = at.X, z = at.Z })
	end
	local best, bestD, bestCrowd = nil, math.huge, math.huge
	for _, tp in (if want == "step" then sb.steps else sb.reserve) do
		local d = flat(tp.pos - p).Magnitude
		if (taken[tp.pos] or 0) == 0 and (not ok or ok(tp.pos.X, tp.pos.Z)) then
			local crowd = math.min(BotBuild.crowd(tp.pos.X, tp.pos.Z, posts, OP.gap), 1)
			if crowd < bestCrowd or (crowd == bestCrowd and d < bestD) then
				best, bestD, bestCrowd = tp, d, crowd
			end
		end
	end
	if best then
		taken[best.pos] = 1
	end
	return best
end

-- Normal: an attacking squad's sap forward (Rules/BotSap, Config/Bots.Sap), one commander tick: stuck under fire (no
-- ground gained toward `objective` for Sap.stall s), it saps from its most forward member, run by run, half of it
-- digging (Build.planAs, then each square's swings), the rest holding there giving covering fire, all moving up to the
-- head of the last run dug; over at the objective's edge or once nobody has shot at it for Sap.quiet s
-- Whether a run toward the enemy lies in a threat's line of fire (Config/Bots.Trenches.Zigzag; user 2026-11-03: "make
-- bots do that if its not safe"): the threats (points on the ground) in line with it or above it (Rules/BotTrenches
-- .exposed) and seeing the ground at its start or middle over the terrain. The turn its legs take (0: straight) and why.
local function runCover(run: BotTrenches.Run, threats: { Vector3 }): (number, string)
	local Z = TR.Zigzag
	local a = Routes.ground(run.ax, run.az)
	local m = Routes.ground((run.ax + run.bx) / 2, (run.az + run.bz) / 2)
	for _, t in threats do
		if flat(t - a).Magnitude <= Z.range then
			local eyeAt = t + Vector3.yAxis * Cfg.Eye
			local why = BotTrenches.exposed(run, a.Y, { x = eyeAt.X, y = eyeAt.Y, z = eyeAt.Z }, Z)
			if why then
				for _, p in { a, m } do
					local to = p + Vector3.yAxis * (CV.chest + 1.8) - eyeAt
					local hit = workspace:Raycast(eyeAt, to, terrainOnly)
					if not hit or hit.Distance >= to.Magnitude - 1 then
						local up = eyeAt.Y - a.Y
						return BotTrenches.zigAngle(up, Z.angle), `{why}, {math.floor(up + 0.5)} studs up`
					end
				end
			end
		end
	end
	return 0, "no sight down it"
end

-- a side's note on a run toward the enemy (the admin panel's readout; the newest few)
local function noteRun(sb: SideBuild?, what: string, angle: number, why: string)
	if angle > 0 then
		stats.zigzags += 1
	else
		stats.straights += 1
	end
	if sb then
		local notes = (sb :: SideBuild).runNotes
		table.insert(notes, `{what} {if angle > 0 then `zigzag {math.floor(angle + 0.5)}°` else "straight"} ({why})`)
		if #notes > 6 then
			table.remove(notes, 1)
		end
	end
end

-- whether a run from (ax, az) to (bx, bz) goes through water (Config/Bots.Sap.waterStep)
local function throughWater(ax: number, az: number, bx: number, bz: number): boolean
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local n = math.max(1, math.ceil(len / SP.waterStep))
	for k = 0, n do
		local t = k / n
		local x, z = ax + (bx - ax) * t, az + (bz - az) * t
		local hit = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -2000, 0), terrainOnly)
		if hit and hit.Material == Enum.Material.Water then
			return true
		end
	end
	return false
end

-- a sap given up (Rules/BotSap.failed): its squad presses on and starts none for Sap.rest seconds
local function giveUpSap(sqs: SquadState, members: { Bot }, d: number, now: number)
	sqs.sap = nil
	sqs.markAt, sqs.markDist = now, d
	sqs.noSapUntil = now + SP.rest
	sqs.pressUntil = now + SQ.Open.press
	stats.sapsFailed += 1
	for _, b in members do
		b.sapper = nil
	end
end

-- a sap ended at its deadline, at a ford, or because its side's offensive has moved on past gathering
-- (Config/Bots.Sap): the squad goes on with the offensive and starts none for Sap.rest seconds
local function endSap(sqs: SquadState, members: { Bot }, d: number, now: number)
	sqs.sap = nil
	sqs.markAt, sqs.markDist = now, d
	sqs.noSapUntil = now + SP.rest
	for _, b in members do
		b.sapper = nil
	end
end

-- (`allowed`: its side may start or keep a sap now, Rules/BotFront.sapNow: no initiative yet, or gathering)
local function sapTick(
	sqs: SquadState,
	members: { Bot },
	mid: Vector3,
	goalAt: Vector3,
	radius: number,
	now: number,
	plan: string,
	allowed: boolean
)
	local sb = buildLists[sqs.side]
	local d = flat(mid - goalAt).Magnitude
	local lost = 0
	for _, b in members do
		if b.threatAt and now - (b.threatAt :: number) < brainCfg.ThreatMemory then
			sqs.firedAt = now
		end
		if b.deadAt and sqs.markAt and (b.deadAt :: number) >= (sqs.markAt :: number) then
			lost += 1
		end
	end
	local underFire = sqs.firedAt ~= nil and now - (sqs.firedAt :: number) < brainCfg.ThreatMemory
	local phase = sqs.sq.phase
	if not sqs.sap then
		for _, b in members do
			b.sapper = nil
		end
		-- (its progress by its most forward member: one walking up from the spawn after a respawn drags its middle back,
		-- and a squad waiting at its gather point while its side gathers is where it was told to be; user 2026-11-06:
		-- "everyone breaks at sector 4": half of each offensive's squads sapped from 130-220 studs short of it)
		local fore = d
		for _, b in members do
			if b.root and alive(b) then
				fore = math.min(fore, flat((b.root :: BasePart).Position - goalAt).Magnitude)
			end
		end
		local gatherAt: Vector3? = sqs.jump or sqs.gather or sqs.approach
		local waiting = false
		if allowed and gatherAt and not underFire then
			for _, b in members do
				if
					b.root
					and alive(b)
					and flat((b.root :: BasePart).Position - gatherAt :: Vector3).Magnitude <= SQ.arrive * 3
				then
					waiting = true
				end
			end
		end
		if phase ~= "Move" and phase ~= "Bound" or not sb or waiting then
			sqs.markAt, sqs.markDist = now, fore
			return
		end
		if not sqs.markAt or fore < (sqs.markDist :: number) - SP.progress then
			sqs.markAt, sqs.markDist = now, fore
		end
		local since, gained = now - (sqs.markAt :: number), (sqs.markDist :: number) - fore
		-- (stuck under fire; fighting by trench, also once near the objective: Rules/BotFront.sapNow)
		local stalled = BotSap.stalled(since, gained, underFire, lost, SP)
		-- (none while one given up rests, or while pressing on out of the open)
		local resting = (sqs.noSapUntil ~= nil and now < sqs.noSapUntil :: number)
			or (sqs.pressUntil ~= nil and now < sqs.pressUntil :: number)
		if resting or d <= radius * SP.edge or not BotFront.sapNow(plan, stalled, d - radius, FR, allowed) then
			return
		end
		local head, best = nil, math.huge
		for _, b in members do
			if b.root and alive(b) then
				local e = flat((b.root :: BasePart).Position - goalAt).Magnitude
				if e < best then
					head, best = (b.root :: BasePart).Position, e
				end
			end
		end
		if not head then
			return
		end
		sqs.sap = { k = 0, head = head, goal = goalAt, open = {}, digs = {}, dugAt = now, began = now }
		stats.saps += 1
	end
	local sap = sqs.sap :: Sap
	sap.goal = goalAt
	-- (fighting by trench it runs on through quiet spells, until its parallel is dug: Config/Bots.Front)
	local headTo = flat(sap.head - goalAt).Magnitude
	local over = if plan == "open"
		then BotSap.over(headTo, radius * SP.edge, now - (sqs.firedAt or now), SP.quiet)
		else (sap.parallel == true and not sap.run) or headTo <= radius * SP.edge or plan == "assault"
	local gaveUp = sap.run ~= nil and (sap.run :: BuildJob).gaveUp == true
	if not over and sb and BotSap.failed(now - sap.dugAt, gaveUp, false, SP) then
		giveUpSap(sqs, members, d, now)
		return
	end
	if not over and not allowed then
		-- (its side's offensive past gathering: Config/Bots.Sap)
		stats.sapsDue += 1
		endSap(sqs, members, d, now)
		return
	end
	if over or not sb then
		sqs.sap = nil
		sqs.markAt, sqs.markDist = now, d
		for _, b in members do
			b.sapper = nil
		end
		return
	end
	local squares = (sb :: SideBuild).trench
	local open: { BuildJob } = {}
	local r = sap.run
	if r then
		local j = r.job
		local run = { kind = "Sap", ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number }
		if BotTrenches.laid(run, squares, TR.on, TR.ends) then
			-- planned: its squares wanting swings; none left, the run is dug and the next starts from its end
			local keep: { [Model]: BuildJob } = {}
			for _, sq in squares do
				local off, t = BotTrenches.offRun(sq.x, sq.z, run.ax, run.az, run.bx, run.bz)
				if off <= TR.on + 1 and t >= -0.1 and t <= 1.1 and sq.left > 0 then
					local dj = sap.digs[sq.model]
					if not dj then
						local job = { key = "Trench", x = sq.x, z = sq.z, fx = 0, fz = 0, work = true }
						dj =
							{ job = job, base = job, model = sq.model, tries = 0, waitUntil = 0, left = 0, open = true }
					end
					local dd = dj :: BuildJob
					dd.at, dd.left, dd.open, dd.underFire = sq.at, sq.left, true, true
					keep[sq.model] = dd
					table.insert(open, dd)
				end
			end
			for model, dj in sap.digs do
				if not keep[model] then
					dj.open = false
				end
			end
			sap.digs = keep
			if #open == 0 then
				r.open = false
				local was = Vector3.new(j.x, 0, j.z)
				sap.head = Vector3.new(j.ex :: number, sap.head.Y, j.ez :: number)
				local went = Vector3.new(j.ex :: number, 0, j.ez :: number) - was
				sap.dir = if went.Magnitude > 1e-3 then went.Unit else sap.dir
				sap.run = nil
				sap.dugAt = now
				stats.sapRuns += 1
			end
		else
			r.open = now >= r.waitUntil
			if r.open then
				table.insert(open, r)
			end
		end
	end
	if not sap.run and BotSap.deadline(sap.k, now - (sap.began or now), SP) then
		-- (its deadline: Config/Bots.Sap maxRuns, maxSeconds)
		stats.sapsDue += 1
		endSap(sqs, members, d, now)
		return
	end
	if not sap.run then
		sap.k += 1
		local ax, az = sap.head.X, sap.head.Z
		-- (straight while nothing can see down it, else a zig-zag against the threat: Trenches.Zigzag)
		local threats = { goalAt }
		for _, kn in sqs.known do
			if now - kn.at <= SQ.knownFor then
				table.insert(threats, kn.pos)
			end
		end
		local ex, ez = BotSap.run(ax, az, goalAt.X, goalAt.Z, 1, { run = SP.run, angle = 0 })
		local turn, why = runCover({ kind = "Sap", ax = ax, az = az, bx = ex, bz = ez }, threats)
		sap.angle = turn
		noteRun(sb, `S{sqs.sector} sap`, turn, why)
		local bx, bz = BotSap.run(ax, az, goalAt.X, goalAt.Z, sap.k, { run = SP.run, angle = turn })
		if plan ~= "open" and BotFront.parallelNow(headTo - radius, FR) then
			-- close: the parallel across, the squad's jump-off (Rules/BotTrenches.jumpOff)
			ax, az, bx, bz = BotFront.parallel(sap.head.X, sap.head.Z, goalAt.X, goalAt.Z, FR.parallel.width)
			sap.parallel = true
			stats.parallels += 1
		end
		if throughWater(ax, az, bx, bz) then
			-- across water: bent to the nearest ford (Map.river.fords); by it already, the sap is over and the squad
			-- wades on (Config/Bots.Sap.fordEnd)
			local river = (Map :: any).river
			local fx, fz = BotSap.ford(sap.head.X, sap.head.Z, goalAt.X, goalAt.Z, river and river.fords)
			if not fx or not fz or sap.parallel then
				giveUpSap(sqs, members, d, now)
				return
			end
			if math.sqrt((fx - sap.head.X) ^ 2 + (fz - sap.head.Z) ^ 2) <= SP.fordEnd then
				stats.sapFords += 1
				endSap(sqs, members, d, now)
				return
			end
			ax, az = sap.head.X, sap.head.Z
			bx, bz = BotSap.run(ax, az, fx, fz, sap.k, { run = SP.run, angle = turn })
			if throughWater(ax, az, bx, bz) then
				stats.sapFords += 1
				endSap(sqs, members, d, now)
				return
			end
		end
		-- (a run on from the head bends off the last no more than Trenches.Shape.maxBend: near its objective the way to it
		-- swings, and a sharper run is refused, user 2026-11-06: "make sure bots dont build abnormal trenches")
		if sap.dir and not sap.parallel then
			bx, bz = BotTrenches.clampBend(sap.dir.X, sap.dir.Z, ax, az, bx, bz, TR.Shape.maxBend - 5)
		end
		local to = flat(goalAt - sap.head)
		to = if to.Magnitude > 1e-3 then to.Unit else Vector3.xAxis
		local job = { key = "Trench", x = ax, z = az, ex = bx, ez = bz, fx = to.X, fz = to.Z }
		local run = { kind = "Sap", ax = job.x, az = job.z, bx = bx, bz = bz }
		local nr =
			{ job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = true, run = run, underFire = true }
		sap.run = nr
		open = { nr }
	end
	sap.open = open
	-- half dig, the rest hold by the sap's head giving covering fire
	local fwd = flat(goalAt - sap.head)
	fwd = if fwd.Magnitude > 1e-3 then fwd.Unit else Vector3.xAxis
	local right = fwd:Cross(Vector3.yAxis)
	for idx, b in members do
		b.sapper = BotTrenches.digs(idx, #members, SP.share)
		local spot = sap.head - fwd * 3 + right * ((idx - (#members + 1) / 2) * SQ.spread)
		b.goal = Routes.ground(spot.X, spot.Z)
		if not b.sapper then
			b.role, b.roleWas, b.post = "Support", "Support", b.goal
		end
		if b.postKind == "dugout" then
			b.postKind, b.dugFrom = nil, nil
		end
	end
end

-- Normal: each trench square's hole marked for pathfinding (Config/Bots.TrenchMove.label: a path knowing there's
-- danger keeps to them), once a commander tick: an invisible box from just under its ground line down past its floor,
-- the width of its wall tops, made for a new square and dropped with a gone one
local function markTrenches()
	local marks = ByTrench.marks
	local seen: { [Model]: boolean } = {}
	for _, side in { "West", "East" } do
		local sb = buildLists[side]
		for _, t in (if sb then sb.trench else {}) do
			local m = t.model
			local a, e = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
			if m.Parent and typeof(a) == "Vector3" and typeof(e) == "Vector3" and (e - a).Magnitude > 0.1 then
				seen[m] = true
				if not marks[m] then
					if not ByTrench.folder or not (ByTrench.folder :: Folder).Parent then
						local f = Instance.new("Folder")
						f.Name = "BotTrenchMarks"
						f.Parent = workspace
						ByTrench.folder = f
					end
					local depth = BuildCfg.Trench.depth
					local mid = (a + e) / 2
					local part = Instance.new("Part")
					part.Name = "Mark"
					part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
					part.Transparency = 1
					part.Size = Vector3.new(2 * ByTrench.top, depth + 0.5, (e - a).Magnitude + 1)
					part.CFrame = CFrame.lookAt(mid, e) * CFrame.new(0, -(depth + 1.5) / 2, 0)
					local mod = Instance.new("PathfindingModifier")
					mod.Label = TM.label
					mod.Parent = part
					part.Parent = ByTrench.folder
					marks[m] = part
				end
			end
		end
	end
	for m, part in marks do
		if not seen[m] then
			part:Destroy()
			marks[m] = nil
		end
	end
end

-- Normal: `side`'s bots in squads by order and sector (Rules/BotSquads): each squad's phase this tick, its route
-- (lane, approach spot, a waypoint on the lane's side) and each member's role and goal
local function formSquads(side: string, counts: { { West: number, East: number } })
	local now = os.clock()
	local front = fronts.sides[side] or { plan = "open" }
	local enemy = if side == "West" then "East" else "West"
	-- its offensive (Config/Bots.Offensive): its attack squads held back while it gathers and shells, then all in; saps
	-- only before the initiative is first taken, or while gathering
	local offence = front.off
	local enemyOff = (fronts.sides[enemy] or {} :: any).off
	local mayDig = fronts.initiative == nil or (offence ~= nil and offence.phase == "Gather")
	local strong = fronts.strong[side] or {}
	front.gathered, front.attackers, front.dueDists = 0, 0, {}
	ByTrench.lanesNow[side] = {}
	local groups: { [string]: { Bot } } = {}
	local order: { string } = {}
	for _, b in bots do
		if b.side == side and b.sector and b.order and not b.gun then
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
		if b.side == side and (b.postFace or b.postKind == "reserve" or b.postKind == "open") and b.post then
			-- (windows, fire steps, support-line places and open hold spots held already)
			taken[b.post :: Vector3] = (taken[b.post :: Vector3] or 0) + 1
		end
	end
	local sb = buildLists[side]
	-- (its holders' posts in each sector's zone: Config/Bots.OffPoint)
	local zoneHeld: { [number]: number } = {}
	local function postInZone(b: Bot, i: number): boolean
		local c = Map.sectors[i]
		return b.postKind == "open"
			and b.post ~= nil
			and b.postSector == i
			and flat(b.post :: Vector3 - Vector3.new(c.x, 0, c.z)).Magnitude <= c.radius
	end
	for _, b in bots do
		if
			b.side == side
			and not b.deadAt
			and b.role == "Hold"
			and b.postSector
			and postInZone(b, b.postSector :: number)
		then
			zoneHeld[b.postSector :: number] = (zoneHeld[b.postSector :: number] or 0) + 1
		end
	end
	local enemyLines = buildLists[enemy]
	-- under shelling (Config/Bots.Dugouts): the places left in each dugout, the sentries kept up so far
	local free: { { x: number, z: number, free: number } } = {}
	local up = 0
	-- (every body down in it takes a place, not only the holders sent there: Rules/BotTrenches.placesLeft)
	local downIn: { [Bot]: Model } = {}
	for _, o in bots do
		if o.side == side and o.root and not o.deadAt then
			local m = Tactics.dug.inside((o.root :: BasePart).Position)
			if m then
				downIn[o] = m
			end
		end
	end
	for _, rm in (if sb then sb.rooms else {}) do
		local bodies = {}
		for _, o in bots do
			local sent = o.side == side and o.postKind == "dugout" and o.post == rm.room
			local inside = downIn[o] == rm.model
			if sent or inside then
				table.insert(bodies, { sent = sent, inside = inside })
			end
		end
		table.insert(free, { x = rm.x, z = rm.z, free = BotTrenches.placesLeft(Cfg.Dugouts.room, bodies) })
	end
	-- (its squads on each gather point, the squads ready to go in, those gone in and those in the Assault phase this look:
	-- Config/Bots.Offensive.Forward, Roll)
	local gatherUsed: { [Vector3]: number } = {}
	if offence then
		for _, o in squads do
			if o.side == side and o.gather and o.gatherOf == offence.began then
				gatherUsed[o.gather :: Vector3] = (gatherUsed[o.gather :: Vector3] or 0) + 1
			end
		end
	end
	local rollCands: { { key: string, lane: number, there: boolean } } = {}
	local rollingNow, assaulting = 0, 0
	-- (exploiting: its first Offensive.exploitHold of the squads hold the zone, the rest cut the defenders' approach)
	local offSquads, offIndex = 0, 0
	if offence and offence.phase == "Exploit" then
		for _, gkey in order do
			local g1 = groups[gkey][1]
			if g1.order ~= "Defend" and g1.sector == offence.sector then
				offSquads += #Squads.form(groups[gkey], SQ.size, SQ.least)
			end
		end
	end
	for _, gkey in order do
		local list = groups[gkey]
		local first = list[1]
		local sector = first.sector :: number
		local defend = first.order == "Defend"
		local s = Map.sectors[sector]
		local c = sectorPoint(sector)
		local inOff = offence ~= nil and not defend and sector == offence.sector
		local formed = Squads.form(list, SQ.size, SQ.least)
		-- its lanes across the front (Config/Bots.Lanes): each lane's share of its squads by how outnumbered it is there,
		-- one squad moved over at most every Lanes.every s
		local ltx, ltz = BotBuild.toward(Map.sectors, sector, side)
		local lf: BotLanes.Frame? = nil
		local lt: { number } = {}
		local have: { number } = {}
		local foes: { number } = {}
		if LN.on then
			local f = BotLanes.frame(s.x, s.z, ltx, ltz, if defend then LN.ahead else -LN.back, laneBounds, LN)
			lf = f
			local own = {}
			-- (each known enemy once: by its model, else the entry itself; a known spot may have no model, and a nil key
			-- stopped the commander every tick in the first trenches-stage match)
			local seenFoe: { [any]: boolean } = {}
			for _, o in squads do
				if o.side == side then
					for _, kn in o.known do
						local at = kn.pos
						local id: any = kn.model or kn
						if
							now - kn.at <= SQ.knownFor
							and not seenFoe[id]
							and (at.X - s.x) ^ 2 + (at.Z - s.z) ^ 2 <= LN.depth ^ 2
						then
							seenFoe[id] = true
							local k = BotLanes.laneOf(f, BotLanes.offset(f, at.X, at.Z))
							foes[k] = (foes[k] or 0) + 1
						end
					end
				end
			end
			for _, o in bots do
				if o.side == side and o.root and alive(o) then
					local at = (o.root :: BasePart).Position
					if (at.X - s.x) ^ 2 + (at.Z - s.z) ^ 2 <= LN.depth ^ 2 then
						local k = BotLanes.laneOf(f, BotLanes.offset(f, at.X, at.Z))
						own[k] = (own[k] or 0) + 1
					end
				end
			end
			lt = BotLanes.targets(BotLanes.weights(foes, own, #f.centres, LN), #formed, LN.least)
			for k = 1, #formed do
				local o = squads[`{gkey}#{k}`]
				if o and o.sector == sector and o.slot then
					have[o.slot :: number] = (have[o.slot :: number] or 0) + 1
				end
			end
			if now - (laneLooked[gkey] or -math.huge) >= LN.every then
				laneLooked[gkey] = now
				local from, to = BotLanes.rebalance(lt, have, LN.moveAt)
				for k = 1, #formed do
					local o = squads[`{gkey}#{k}`]
					if
						from
						and to
						and o
						and o.sector == sector
						and o.slot == from
						and o.sq.phase ~= "Assault"
						and not o.push
					then
						-- (over to the lane that needs it: its route and posts found again)
						o.slot, o.slotAt = to, nil
						o.approach, o.mid, o.midAt, o.gather, o.gatherOf = nil, nil, nil, nil, nil
						o.jump, o.jumpAlong, o.jumpAt = nil, nil, nil
						have[from] -= 1
						have[to] = (have[to] or 0) + 1
						stats.laneMoves += 1
						break
					end
				end
			end
			local text = {}
			for k = 1, #f.centres do
				table.insert(text, `{have[k] or 0}/{string.format("%.1f", lt[k])}`)
			end
			ByTrench.lanesNow[side][`{first.order} S{sector}`] = table.concat(text, " ")
		end
		for k, members in formed do
			local key = `{gkey}#{k}`
			local st = squads[key]
			if not st or st.sector ~= sector then
				local lanes = crowd[sector] or {}
				crowd[sector] = lanes
				local lane = Squads.quietLane(lanes)
				-- (attacking: a share up the flanks, Rules/BotFront.flank)
				local flank: number? = nil
				if not defend and not LN.on then
					local total, left, right = 1, 0, 0
					for _, o in squads do
						if o.side == side and o.seen >= commandTick - 1 and o.approach ~= nil then
							total += 1
							left += if o.flank == -1 then 1 else 0
							right += if o.flank == 1 then 1 else 0
						end
					end
					flank = BotFront.flank(total, left, right, FR.Flank.share)
				end
				lane = flank or lane
				lanes[lane] = (lanes[lane] or 0) + 1
				st = {
					sq = Squads.new(),
					side = side,
					sector = sector,
					lane = lane,
					known = {},
					seen = commandTick,
					flank = flank,
				}
				squads[key] = st
			end
			local sqs = st :: SquadState
			-- its lane across the front (Config/Bots.Lanes): the one furthest under its share; attacking, by the lane's
			-- point short of the sector, to the approach spots on that side
			if lf and not sqs.slot then
				sqs.slot = BotLanes.pick(lt, have)
				have[sqs.slot :: number] = (have[sqs.slot :: number] or 0) + 1
				sqs.slotAt = nil
			end
			if lf and sqs.slot and not sqs.slotAt then
				local px, pz = BotLanes.point(lf, sqs.slot :: number, ltx, ltz, 0)
				local W = RT.wet
				-- (not in the water: in toward the line through the flags until dry)
				for _ = 1, 8 do
					if not MapTerrain.wetSpan(Map, px, pz, px, pz, W.step, W.pad) then
						break
					end
					px, pz = px + (lf.ox - px) * LN.dry, pz + (lf.oz - pz) * LN.dry
				end
				sqs.slotAt = Routes.ground(px, pz)
				if not defend then
					sqs.lane = Squads.lane(s.x - ltx * 100, s.z - ltz * 100, s.x, s.z, px, pz, RT.laneWithin)
					sqs.approach = nil
				end
			end
			-- the admin panel's flank push: every attacking squad up a flank now, alternating (its route found again)
			if front.plan == "flank" and not defend and not sqs.flank then
				local left = 0
				for _, o in squads do
					left += if o.side == side and o.flank == -1 then 1 else 0
				end
				local right = 0
				for _, o in squads do
					right += if o.side == side and o.flank == 1 then 1 else 0
				end
				sqs.flank = if left <= right then -1 else 1
				sqs.lane, sqs.approach, sqs.mid = sqs.flank :: number, nil, nil
			end
			-- the admin panel's assault: over the top now
			if
				front.plan == "assault"
				and not defend
				and (not OF.Roll.on or not inOff or front.forced == "assault")
			then
				sqs.sq.phase = "Assault"
			end
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
						if sqs.slotAt and not sqs.flank then
							-- (in its lane: by the lane's point, unless it is there or past it already)
							local at = sqs.slotAt :: Vector3
							if
								flat(at - mid).Magnitude > SQ.arrive * 3
								and flat(mid - c).Magnitude > flat(at - c).Magnitude
							then
								sqs.mid = at
							end
						elseif sqs.flank and home.Magnitude > 1 then
							-- up a flank: by a point `Front.Flank.offset` studs off the straight way, to that side
							local side1 = Vector3.new(-home.Unit.Z, 0, home.Unit.X) * (sqs.flank :: number)
							local p = mid:Lerp(spot.pos, RT.midShare) + side1 * FR.Flank.offset
							sqs.mid = Routes.ground(p.X, p.Z)
						elseif way.Magnitude > RT.midFrom and across.Magnitude > 1 then
							local p = mid:Lerp(spot.pos, RT.midShare) + across.Unit * way.Magnitude * RT.laneOffset
							sqs.mid = Routes.ground(p.X, p.Z)
						end
					end
				end
			end
			-- (its members off building, rescuing or guarding don't hold the rest at a point: Rules/BotSquads.moveOn)
			local loose, atMid = 0, 0
			for _, b in members do
				if b.root and alive(b) and not (b.act or b.work or b.guard) then
					loose += 1
					local at = sqs.mid
					if at and flat((b.root :: BasePart).Position - at :: Vector3).Magnitude < SQ.arrive * 3 then
						atMid += 1
					end
				end
			end
			sqs.midAt = if atMid > 0 then sqs.midAt or now else nil
			if
				sqs.mid
				and (
					flat((sqs.mid :: Vector3) - mid).Magnitude < SQ.arrive * 3
					or Squads.moveOn(atMid, loose, now - (sqs.midAt or now), SQ)
				)
			then
				sqs.mid, sqs.midAt = nil, nil
				stats.movedOn += 1
			end
			if not defend and sb and not sqs.jump and sqs.sq.phase ~= "Assault" then
				local dug = {}
				for _, t in (sb :: SideBuild).trench do
					if t.built then
						table.insert(dug, t)
					end
				end
				-- (none across the river from the squad: the next best on its own bank, Config/Bots.Routes.wet)
				local W = RT.wet
				-- (in a lane: the jump-off nearest its lane's point, none further than Lanes.gatherNear x 2 from it)
				local from = sqs.slotAt or mid
				local i = BotTrenches.jumpOff(dug, from.X, from.Z, c.X, c.Z, s.radius, TM.Jump)
				for _ = 1, W.tries do
					local t = i and dug[i :: number]
					if not t or not MapTerrain.wetSpan(Map, mid.X, mid.Z, t.at.X, t.at.Z, W.step, W.pad) then
						break
					end
					table.remove(dug, i :: number)
					i = BotTrenches.jumpOff(dug, from.X, from.Z, c.X, c.Z, s.radius, TM.Jump)
				end
				local t0 = i and dug[i :: number]
				if t0 and MapTerrain.wetSpan(Map, mid.X, mid.Z, t0.at.X, t0.at.Z, W.step, W.pad) then
					i = nil
				end
				if t0 and sqs.slotAt and flat(t0.at - from).Magnitude > LN.gatherNear * 2 then
					i = nil
				end
				if i then
					local t = dug[i]
					local a, e = t.model:GetAttribute("BlockA"), t.model:GetAttribute("BlockB")
					local along = if typeof(a) == "Vector3" and typeof(e) == "Vector3"
						then flat(e - a)
						else Vector3.zero
					sqs.jump, sqs.jumpAt = t.at, nil
					sqs.jumpAlong = if along.Magnitude > 1e-3 then along.Unit else nil
				end
			end
			-- gone in on its offensive: its squads go by waves (Config/Bots.Offensive.Roll; the admin panel's assault: all now)
			local began: number? = if offence then offence.began else nil
			local released = inOff
				and Orders.going(offence)
				and (not OF.Roll.on or front.forced == "assault" or sqs.rollOf == began)
			-- where it forms up for its offensive (Config/Bots.Offensive.Forward)
			if not inOff then
				sqs.gather, sqs.gatherOf = nil, nil
			elseif OF.Forward.on and not released and sqs.gatherOf ~= began then
				local at = gatherPoint(side, sector, sqs.slotAt or mid, sqs.lane, gatherUsed, sqs.slotAt)
				sqs.gather = at
				if at then
					sqs.gatherOf = began
					gatherUsed[at] = (gatherUsed[at] or 0) + 1
				end
			end
			local gatherTo: Vector3? = if inOff and not released then sqs.gather else nil
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
					if gatherTo then
						ready += if flat(p - gatherTo :: Vector3).Magnitude <= OF.Forward.at then 1 else 0
					elseif sqs.approach and flat(p - sqs.approach :: Vector3).Magnitude < SQ.arrive * 2 then
						ready += 1
					end
					if b.role == "Move" and b.stop and flat(p - b.stop :: Vector3).Magnitude > SQ.arrive then
						moversThere = false
					end
				end
			end
			if not sqs.approach and not gatherTo then
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
			-- (its side's first contact: from now on it fights forward by trench, Config/Bots.Front)
			local shotAt = sqs.firedAt ~= nil and now - (sqs.firedAt :: number) < brainCfg.ThreatMemory
			if (contact or shotAt) and not front.contactAt then
				front.contactAt = now
				stats.contacts += 1
			end
			local was = sqs.sq.phase
			-- (ready: its free members at the approach spot, or anyone waited there long enough: Squads.waitMax)
			sqs.readyAt = if ready > 0 then sqs.readyAt or now else nil
			local readyShare = if Squads.moveOn(ready, loose, now - (sqs.readyAt or now), SQ)
				then 1
				elseif living > 0 then ready / living
				else 0
			local gatheredHere = ready
			if sqs.jump then
				-- gathered in the jump-off trench: ready only once over the top
				local there = 0
				for _, b in members do
					if
						b.root
						and alive(b)
						and flat((b.root :: BasePart).Position - sqs.jump :: Vector3).Magnitude <= TM.Jump.at
					then
						there += 1
					end
				end
				if there > 0 and not sqs.jumpAt then
					sqs.jumpAt = now
				end
				local since = if sqs.jumpAt then now - (sqs.jumpAt :: number) else 0
				readyShare = if sqs.jumpAt and BotTrenches.overTop(there, living, since, TM.Jump) then 1 else 0
				gatheredHere = there
			end
			if inOff then
				-- (only its members within Offensive.gatherNear of where it gathers count: one still walking up from
				-- the spawn after a respawn never makes the share, Config/Bots.Offensive)
				local gatherAt: Vector3? = sqs.jump or gatherTo or sqs.approach
				local nearUp = living
				if gatherAt then
					nearUp = 0
					for _, b in members do
						if b.root and alive(b) then
							local d = flat((gatherAt :: Vector3) - (b.root :: BasePart).Position).Magnitude
							if d <= OF.gatherNear then
								nearUp += 1
								table.insert(front.dueDists :: { number }, d)
							end
						end
					end
				end
				front.gathered = (front.gathered :: number) + math.min(gatheredHere, nearUp)
				front.attackers = (front.attackers :: number) + nearUp
			end
			-- shot to pieces out of the zone: it falls back, re-forms at its gather point and goes again (Offensive.Roll)
			if
				released
				and OF.Roll.on
				and front.forced ~= "assault"
				and Orders.fellBack(living, #members, if living > 0 then inZone / living else 0, OF.Roll)
			then
				sqs.rollOf, sqs.rollAgain = nil, now + OF.Roll.again
				released = false
				gatherTo = sqs.gather
				stats.fellBack += 1
			end
			local waitHere = inOff and (Orders.waiting(offence) or (Orders.going(offence) and not released))
			local goHere = released
			if inOff and OF.Roll.on and Orders.going(offence) then
				if released then
					rollingNow += if living > 0 then 1 else 0
				elseif living > 0 and now >= (sqs.rollAgain or 0) then
					local need = math.max(1, math.ceil(living * SQ.readyShare))
					table.insert(rollCands, { key = key, lane = sqs.lane, there = gatheredHere >= need })
				end
			end
			Squads.step(sqs.sq, {
				now = now,
				defend = defend,
				contact = contact,
				ready = readyShare,
				inZone = if living > 0 then inZone / living else 0,
				ours = (counts[sector] :: any)[side],
				theirs = (counts[sector] :: any)[enemy],
				size = living,
				moversThere = moversThere,
				wait = waitHere,
				go = goHere,
			}, SQ)
			-- holding a sector the enemy's offensive is going into: it stands to, into its own zone, fighting on the
			-- move (counter-attackers at its own front, Config/Bots.Offensive; under the barrage they kept to cover)
			local standTo = Orders.standTo(defend, enemyOff, sector)
			-- (in a lane: only the lane through the flag and lanes with enemies known in them stand to; the rest hold
			-- their lane, Config/Bots.Lanes)
			if standTo and lf and sqs.slot then
				local slot = sqs.slot :: number
				standTo = BotLanes.inLane(lf :: BotLanes.Frame, slot, BotLanes.offset(lf :: BotLanes.Frame, c.X, c.Z))
					or (foes[slot] or 0) > 0
			end
			if standTo then
				sqs.sq.phase = "Assault"
				if not sqs.stoodTo then
					-- (its stillness counted from standing to, not from its time on the posts)
					sqs.stillMid, sqs.stillAt = mid, now
				end
			end
			sqs.stoodTo = standTo
			assaulting += if inOff and sqs.sq.phase == "Assault" and living > 0 then 1 else 0
			if sqs.sq.phase == "Assault" and was ~= "Assault" then
				stats.assaults += 1
				if sqs.jump then
					stats.overTop += 1
					sqs.jump, sqs.jumpAlong, sqs.jumpAt = nil, nil, nil
				end
				for _, b in members do
					if say(b, "Push") then
						break
					end
				end
			end
			-- a group of enemies it can take (Config/Bots.Squads.Push): cover, a grenade if it has one, a bound at them
			local PU = SQ.Push
			local pushAt: Vector3? = nil
			local lead: Bot? = nil
			for _, b in members do
				if b.m and alive(b) then
					lead = b
					break
				end
			end
			-- gathering or under its barrage: a known enemy MG nest or gun near is its Grenadier's first throw, and a
			-- squad with a Grenadier or Mage in it bounds at it while gathering (Config/Bots.Offensive.strong)
			local strongAt: Vector3? = nil
			if waitHere or (Cfg.Crew.Arcs.on and not defend) then
				local bestD = OF.strong.reach
				for _, sp in strong do
					local dd = flat(sp.at - mid).Magnitude
					if dd <= bestD then
						strongAt, bestD = sp.at, dd
					end
				end
			end
			if strongAt then
				sqs.bomb, sqs.bombAt = strongAt, now
				if offence and offence.phase == "Gather" then
					for _, b in members do
						local m = b.m
						if m and alive(b) and (b.grenades or Loadouts.classOf(m) == "Mage") then
							pushAt = strongAt
							break
						end
					end
				end
			end
			if not pushAt and not defend and sqs.sq.phase ~= "Assault" and lead then
				local kn = {}
				for _, known in sqs.known do
					if now - known.at <= SQ.knownFor then
						table.insert(kn, { x = known.pos.X, z = known.pos.Z })
					end
				end
				local gx, gz, many = Squads.group(kn, mid.X, mid.Z, PU)
				if gx and gz then
					local lm = (lead :: Bot).m :: Model
					local lkit = lm:GetAttribute("Kit")
					local all, cnt = soldiersNow()
					local ours = 0
					for j = 1, cnt do
						local o = all[j]
						if flat(o.pos - mid).Magnitude <= PU.near and (o.model == lm or friendly(lm, lkit, o)) then
							ours += 1
						end
					end
					if Squads.confident(ours, many, PU) then
						pushAt = Routes.ground(gx, gz)
					end
				end
			end
			local forced = sqs.devPush
			if forced and now < forced.till and sqs.sq.phase ~= "Assault" then
				pushAt = pushAt or forced.at
			elseif forced and now >= forced.till then
				sqs.devPush = nil
			end
			if pushAt and not sqs.push then
				stats.pushes += 1
				sqs.bomb, sqs.bombAt = pushAt, now
				for _, b in members do
					if say(b, "Push") then
						break
					end
				end
			end
			sqs.push = pushAt
			if pushAt and sqs.sq.phase ~= "Bound" then
				sqs.sq.phase, sqs.sq.moving, sqs.sq.swapAt = "Bound", 1, now + SQ.boundMax
			end
			if sqs.bomb and now - (sqs.bombAt or 0) > PU.bombFor then
				sqs.bomb = nil
			end
			-- exploiting: the squads past Offensive.exploitHold stand on the defenders' approach spots
			if goHere and offence and offence.phase == "Exploit" then
				offIndex += 1
				if Orders.holdsZone(offIndex, offSquads, OF.exploitHold) then
					sqs.cut = nil
				elseif not sqs.cut then
					local spots = Routes.spots(sector, enemy, false)
					if spots and #spots > 0 then
						local rolls = {}
						for i in spots :: { Routes.Spot } do
							rolls[i] = random:NextNumber()
						end
						local i = Squads.pickSpot(spots :: any, nil, {}, rolls, RT.weights, RT.nearCap)
						sqs.cut = if i then (spots :: { Routes.Spot })[i].pos else nil
					end
				end
			else
				sqs.cut = nil
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
			-- (defending in a lane: its holders' posts in that lane, Config/Bots.Lanes)
			local laneOk: ((x: number, z: number) -> boolean)? = nil
			if lf and defend and sqs.slot then
				local f, slot = lf :: BotLanes.Frame, sqs.slot :: number
				laneOk = function(x: number, z: number): boolean
					return BotLanes.inLane(f, slot, BotLanes.offset(f, x, z))
				end
			end
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
			-- attacking: over the top together from its side's front trench (Rules/BotTrenches.jumpOff, overTop)
			if defend or sqs.sq.phase == "Assault" or not sb then
				sqs.jump, sqs.jumpAlong, sqs.jumpAt = nil, nil, nil
			end
			local route = sqs.push or sqs.jump or sqs.mid or gatherTo or sqs.approach or c
			local formsAt: Vector3? = if OF.Forward.on and waitHere then sqs.jump or gatherTo else nil
			local ahead = flat(route - mid)
			local right = if ahead.Magnitude > 1 then ahead.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
			for idx, b in members do
				local role = Squads.role(sqs.sq, idx)
				b.squad, b.role = key, role
				local gathered = false
				local p = if b.root then (b.root :: BasePart).Position else mid
				-- half of a squad holding the front digs (Config/Bots.Trenches.share), the rest stand guard
				b.digger = defend and sb ~= nil and sb.front == sector and BotTrenches.digs(idx, #members, TR.share)
				if role == "Hold" then
					holdN += 1
					-- in its trenches: every other holder in the support line until it stands to, the rest on the fire
					-- step; all back to the support line once the fire trench is lost
					local want: string? = nil
					-- (a sector it just took: a share of its holders on hold spots inside the zone, holding the flag
					-- itself against the counter-attack: Config/Bots.Offensive.dig)
					local took = fronts.took[side]
					local inZoneHold = took ~= nil
						and took.sector == sector
						and Orders.digIn(holdN, now - took.at, OF.dig)
					-- (a defended sector keeps its few in the zone, so it stays held: Config/Bots.OffPoint)
					local inZoneNow = postInZone(b, sector)
					local zoneN = zoneHeld[sector] or 0
					local keepsZone = defend and (if inZoneNow then zoneN <= OP.inZone else zoneN < OP.inZone)
					if inZoneNow and not keepsZone then
						zoneHeld[sector] = zoneN - 1
					end
					inZoneHold = inZoneHold or keepsZone
					if inZoneHold then
						want = "zone"
					elseif lines then
						local s2 = sb :: SideBuild
						if fallback then
							want = if #s2.reserve > 0 then "reserve" else nil
						elseif holdN % 2 == 0 and #s2.reserve > 0 and not s2.standTo then
							want = "reserve"
						else
							want = "step"
						end
						-- hot here (shelled, fought over: Dugouts.Heat): one sentry a fire bay stays up, the rest down into
						-- a dugout with a place, until it cools, they stand to, or they have stayed down long enough
						local inside = b.postKind == "dugout"
							and b.postSector == sector
							and Tactics.dug.standing(s2, b.post)
						if want and not fallback and not s2.standTo then
							-- (heat where it went down from while down, else at its post here, else where it is: never at
							-- the dugout, which may be cold while its post is shelled, sending it straight back up)
							local pos = if inside and b.dugFrom
								then b.dugFrom :: Vector3
								elseif b.post and b.postSector == sector then b.post :: Vector3
								else p
							local h, hs, hd, he =
								BotTrenches.heat(now, pos.X, pos.Z, side, Tactics.dug.heat, s2.enemies, DH)
							local down =
								BotTrenches.shelter(inside, h, now - (b.dugSince or now), now < (b.dugRest or 0), DH)
							if inside and not down then
								b.dugRest = now + DH.rest
							end
							if inside and down then
								want = "dugout"
							elseif down and want == "step" and up < s2.bays then
								up += 1
							elseif down then
								local i = BotTrenches.seat(free, p.X, p.Z, Cfg.Dugouts.reach)
								if i then
									free[i].free -= 1
									want = "dugout"
									local rm = s2.rooms[i]
									b.dugFrom = pos
									b.post, b.postFace, b.postKind, b.postFloor = rm.room, nil, "dugout", rm.room
									b.postFoot = rm.foot
									b.postSector = sector
									b.dugSince = now
									stats.sheltered += 1
									local u = Tactics.dug.use[rm.model] or { count = 0, why = "", who = "" }
									u.count += 1
									u.why, u.who = BotTrenches.heatWhy(h, hs, hd, he), b.name
									Tactics.dug.use[rm.model] = u
								end
							end
						end
					end
					local again = not b.post or b.postSector ~= sector or b.roleWas ~= "Hold"
					if want == "zone" and not inZoneNow then
						again = true
					end
					-- (a post out of its lane: another in it)
					local inLane = if want ~= "zone" then laneOk else nil
					if
						inLane
						and b.post
						and b.postKind ~= "dugout"
						and not inLane((b.post :: Vector3).X, (b.post :: Vector3).Z)
					then
						again = true
					end
					if b.postKind == "dugout" and want ~= "dugout" then
						-- (up to its post again: shelling over, standing to, or the dugout gone)
						stats.cameUp += 1
						again = true
					end
					local tp = if want
							and want ~= "dugout"
							and want ~= "zone"
							and (again or b.postKind ~= want)
						then trenchPost(sb :: SideBuild, want :: string, taken, p, inLane)
						else nil
					if tp then
						b.post, b.postFace, b.postKind = tp.pos, tp.face, want
						b.postFloor = tp.floor
						b.postSector = sector
					elseif again and want ~= "dugout" then
						-- a few at windows and doorways (Config/Bots.Indoors.perSquad), the rest outside
						-- (in a lane: windows only in the lane through the flag)
						local sp = if indoorHeld < IN.perSquad
								and want ~= "zone"
								and (not inLane or inLane(c.X, c.Z))
							then indoorHold(side, sector, taken)
							else nil
						if sp then
							indoorHeld += 1
							b.post, b.postFace, b.postKind = sp.at, sp.face, "window"
						else
							local marked = markedPost(side, sector, p, want == "zone", inLane)
							local spot = marked or holdSpot(side, sector, taken, inLane)
							if not spot and inLane and sqs.slotAt then
								-- (nothing marked or dug in its lane: on the lane's point, OffPoint.gap apart across)
								local at = sqs.slotAt :: Vector3
								local x, z = BotBuild.markedPlace(at.X, at.Z, holdN - 1, OP.gap, ltx, ltz)
								spot = Routes.ground(x, z)
							end
							b.post, b.postFace, b.postKind = spot or b.stand, nil, "open"
						end
						b.postFloor = nil
						b.postSector = sector
						if want == "zone" and not inZoneNow then
							zoneHeld[sector] = (zoneHeld[sector] or 0) + 1
						end
					end
					b.goal = b.post
				elseif role == "Assault" then
					-- (on the defenders' approach spot: side by side across its way, SQ.spread apart)
					local cut = if sqs.cut and not sqs.clear
						then Routes.ground(
							(sqs.cut :: Vector3).X + right.X * (idx - (#members + 1) / 2) * SQ.spread,
							(sqs.cut :: Vector3).Z + right.Z * (idx - (#members + 1) / 2) * SQ.spread
						)
						else nil
					b.goal = sqs.clear or cut or b.stand
				elseif role == "Support" then
					if b.roleWas ~= "Support" then
						b.post = p -- (it holds where it stands, covering the others)
					end
					b.goal = b.post
				else
					-- (in the jump-off trench: spread along it)
					local across = if sqs.jump and sqs.jumpAlong then sqs.jumpAlong :: Vector3 else right
					local slot = route + across * ((idx - (#members + 1) / 2) * SQ.spread)
					-- (at its place where it forms up: it holds there and fires at where enemies were seen, Offensive.Forward)
					local keepTo = if b.roleWas == "Support" then OF.Forward.at else SQ.arrive * 2
					if formsAt and route == formsAt and flat(slot - p).Magnitude <= keepTo then
						gathered = true
						role, b.role, b.stop = "Support", "Support", nil
						if b.roleWas ~= "Support" then
							b.post = p
						end
						b.goal = b.post
					elseif sqs.sq.phase == "Bound" then
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
				if role ~= "Hold" and b.postKind == "dugout" then
					-- (sent off to attack or move: out of its dugout, up its steps first (think), its place freed)
					b.postKind, b.dugFrom = nil, nil
					stats.cameUp += 1
				end
				if role ~= b.roleWas then
					if role == "Support" and not gathered then
						say(b, "Covering")
					elseif role == "Move" and sqs.sq.phase == "Bound" then
						say(b, "MoveUp")
					end
				end
				b.roleWas = role
			end
			-- pinned in the open under fire, not getting anywhere: it presses on toward its objective, fighting on the
			-- move (Rules/BotSquads.pinned; Config/Bots.Squads.Open)
			local O = SQ.Open
			if not sqs.stillMid or not sqs.stillAt or flat(mid - sqs.stillMid :: Vector3).Magnitude > O.moved then
				sqs.stillMid, sqs.stillAt = mid, now
			end
			local inCover, standing = 0, 0
			for _, b in members do
				if b.root and alive(b) then
					standing += 1
					local cv = b.cover
					if cv and flat((cv :: Vector3) - (b.root :: BasePart).Position).Magnitude < CV.at then
						inCover += 1
					end
				end
			end
			sqs.inCover = inCover
			local pressing = sqs.pressUntil ~= nil and now < sqs.pressUntil :: number
			local pinned = Squads.pinned(now - (sqs.stillAt :: number), shotAt, inCover, standing, O)
			if not defend and not sqs.sap and not pressing and pinned then
				sqs.pressUntil = now + O.press
				sqs.stillMid, sqs.stillAt = mid, now
				stats.pressed += 1
				-- (no ready check for a pinned squad unless its offensive holds it back: in now, fighting on the move)
				if not waitHere and sqs.sq.phase ~= "Assault" then
					sqs.sq.phase = "Assault"
					stats.assaults += 1
				end
				for _, b in members do
					if say(b, "Push") then
						break
					end
				end
			end
			-- an Assault squad stuck out of the zone finds its way in again: fresh stand points, fresh paths
			-- (Config/Bots.Offensive.stuckFor)
			local share = if living > 0 then inZone / living else 0
			-- (holders standing to as well: Rules/BotOrders.standTo)
			if
				(not defend or standTo)
				and not sqs.cut
				and Squads.restart(sqs.sq.phase, now - (sqs.stillAt :: number), share, OF.stuckFor)
			then
				sqs.stillMid, sqs.stillAt = mid, now
				sqs.approach, sqs.mid, sqs.cut = nil, nil, nil
				stats.restarts += 1
				fronts.tally.restarts = (fronts.tally.restarts or 0) + 1
				for _, b in members do
					b.stand = standPoint(sector)
					b.wander = nil
					b.nav.pathAt = -math.huge
				end
			end
			-- stuck under fire on the way: a sap forward (Rules/BotSap); a defending squad never saps
			if defend then
				sqs.sap = nil
			else
				sapTick(sqs, members, mid, c, s.radius, now, front.plan, mayDig)
			end
		end
	end
	front.assaulting = assaulting
	-- the next wave of its offensive (Config/Bots.Offensive.Roll): they go from the next look
	if offence and OF.Roll.on and Orders.going(offence) and Orders.rollDue(offence, now, rollingNow, OF.Roll) then
		local picks = Orders.pickWave(rollCands, OF.Roll.perWave, offence.lastLanes or {}, rollingNow <= 0)
		if #picks > 0 then
			local lanes = {}
			for _, i in picks do
				local cand = rollCands[i]
				squads[cand.key].rollOf = offence.began
				table.insert(lanes, cand.lane)
			end
			offence.lastWave, offence.lastLanes = now, lanes
			offence.nextWave = now + random:NextNumber(OF.Roll.gap[1], OF.Roll.gap[2])
			local A = fronts.attacks[side]
			if A then
				A.waves += 1
				A.sent += #picks
			end
		end
	end
end

-- Normal: `side`'s build list at its front (Rules/BotBuild; Config/Bots.Build): the lay jobs, each matched to its
-- piece once laid (open while it wants swings; an unlaid one while the bots' caps allow it and it isn't waiting), and
-- the own pieces near the front wanting swings
-- (the bots' guns in one table: `asset` each gun piece's Config/Artillery.Guns
-- key, `spacing` its own, `piece` its Config/Build piece)
local Guns = {
	list = { "FieldGun", "Howitzer" },
	asset = {} :: { [string]: string },
	spacing = {} :: { [string]: number },
	piece = {} :: { [string]: { [string]: any } },
	ground = RaycastParams.new(),
	world = RaycastParams.new(), -- (a shot's path: everything but soldiers)
	drawn = {} :: { { points: { { number } }, clear: boolean } }, -- the shots checked this plan (Admin.GunArcs)
	-- why each gun's candidate spots were turned down this plan, a count each (the Engineer bots readout)
	why = {} :: { [string]: { [string]: number } },
	dev = require(Shared.Config.DevTools).Admin.GunArcs,
}
for _, piece in BuildCfg.Pieces do
	if Kinds.gun[piece.key] then
		Guns.asset[piece.key] = piece.gun
		Guns.spacing[piece.key] = piece.spacing
		Guns.piece[piece.key] = piece
	end
end

-- `side`'s gun spots behind its front sector `front` (Rules/BotBuild.gunSpots; Config/Bots.Build.Crews): where the
-- gun reaches the middle of the enemy's nearest sector and stands clear of every spawn and wave line; the howitzer
-- first (the farthest back), then the field guns, the bots' share of each (Build.caps)
Guns.ground.FilterType = Enum.RaycastFilterType.Include
function Guns.terrainAt(x: number, z: number): Vector3?
	Guns.ground.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), Guns.ground)
	return hit and hit.Position
end
-- Whether a shot from gun `gun` standing on `at` comes down on `target` (Config/Bots.Build.Crews `arc`): laid on it
-- from its muzzle (Rules/Artillery.layFor, within its reach), its path (Rules/Artillery.path) cast against the world;
-- false when out of reach, or a hill, house or tree stops it short. The low arc, then the lobbed one (the field gun
-- fires over cover). Each one checked is kept for Admin.GunArcs.
function Guns.flyShot(gun: any, key: string, at: Vector3, target: Vector3, arc: string, quiet: boolean?): boolean
	local A = BD.Crews.arc
	-- (from its muzzle over the ground as it is now: a howitzer's pit is dug round it later)
	local frame = CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z))
	local mx, my, mz = ArtRules.muzzle(gun, 0, 0)
	local origin = frame:PointToWorldSpace(Vector3.new(mx, my, mz))
	local off = target - origin
	local d = Vector3.new(off.X, 0, off.Z).Magnitude
	local e = if d <= ArtRules.reachCap(ArtRules.sectorSpan(Map.sectors), ArtCfg.Reach, key)
		then ArtRules.layFor(gun, d, off.Y, nil, arc)
		else nil
	if not e then
		return false
	end
	local _, _, _, dx, dy, dz = ArtRules.muzzle(gun, 0, e)
	local v = frame:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed
	local floor = math.min(origin.Y, target.Y) - 50
	local points =
		ArtRules.path(origin.X, origin.Y, origin.Z, v.X, v.Y, v.Z, gun.gravity, A.step, ArtCfg.MaxFlight, floor)
	local skip = {}
	for _, b in bots do
		if b.m then
			table.insert(skip, b.m)
		end
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local arcs = workspace:FindFirstChild(Guns.dev.folder)
	if arcs then
		table.insert(skip, arcs)
	end
	Guns.world.FilterDescendantsInstances = skip
	local clear, drawn = false, {}
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local from = Vector3.new(a[1], a[2], a[3])
		if Vector3.new(b[1] - origin.X, 0, b[3] - origin.Z).Magnitude < A.near then
			continue -- (its own ground, levelled when it is laid)
		end
		local hit = workspace:Raycast(from, Vector3.new(b[1], b[2], b[3]) - from, Guns.world)
		table.insert(drawn, a)
		if hit then
			table.insert(drawn, { hit.Position.X, hit.Position.Y, hit.Position.Z })
			clear = Vector3.new(hit.Position.X - target.X, 0, hit.Position.Z - target.Z).Magnitude <= A.within
			break
		end
	end
	if not quiet then
		table.insert(Guns.drawn, { points = drawn, clear = clear })
	end
	return clear
end

-- Admin.GunArcs: `side`'s checked shots drawn (a folder per side, redrawn each plan), or taken down while it is off
function Guns.draw(side: string)
	local G = Guns.dev
	local root = workspace:FindFirstChild(G.folder)
	local old = root and root:FindFirstChild(side)
	if old then
		old:Destroy()
	end
	if workspace:GetAttribute(G.attribute) ~= true then
		if root and #root:GetChildren() == 0 then
			root:Destroy()
		end
		return
	end
	if not root then
		root = Instance.new("Folder")
		root.Name = G.folder
		root.Parent = workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = side
	for _, arc in Guns.drawn do
		local c = if arc.clear then G.clear else G.blocked
		local color = Color3.fromRGB(c[1], c[2], c[3])
		local pts = arc.points
		local i = 1
		while i < #pts do
			local j = math.min(i + G.every, #pts)
			local a = Vector3.new(pts[i][1], pts[i][2], pts[i][3])
			local b = Vector3.new(pts[j][1], pts[j][2], pts[j][3])
			local part = Instance.new("Part")
			part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
			part.Material = Enum.Material.Neon
			part.Color = color
			part.Size = Vector3.new(G.width, G.width, (b - a).Magnitude)
			part.CFrame = CFrame.lookAt((a + b) / 2, b)
			part.Parent = folder
			i = j
		end
	end
	folder.Parent = root
end

function Guns.spots(
	front: number,
	side: string,
	zone: BotBuild.Zone,
	tx: number,
	tz: number,
	guns: { string }
): { BotBuild.Job }
	local C = Flanked.guns
	local enemy = Map.sectors[front + (if side == "West" then 1 else -1)]
	if not enemy then
		return {}
	end
	local target = Guns.terrainAt(enemy.x, enemy.z)
	local lines = {}
	local fl = workspace:FindFirstChild(FrontCfg.FolderName)
	for _, sd in { "West", "East" } do
		local c = fl and fl:GetAttribute(sd .. FrontCfg.LineAttribute)
		if typeof(c) == "Vector3" then
			table.insert(lines, { c.X, c.Z, ArtCfg.SpawnGuard.line })
		end
	end
	local want = {}
	for _, key in { "Howitzer", "FieldGun" } do
		if table.find(guns, key) and (BD.caps[key] or 0) > 0 then
			table.insert(want, { key = key, count = BD.caps[key] })
		end
	end
	local function no(key: string, why: string): boolean
		local w = Guns.why[key] or {}
		Guns.why[key] = w
		w[why] = (w[why] or 0) + 1
		return false
	end
	local function fits(key: string, x: number, z: number): boolean
		local gun = ArtCfg.Guns[Guns.asset[key]]
		local B = Map.bounds
		if not gun or not target or x < B.minX or x > B.maxX or z < B.minZ or z > B.maxZ then
			return no(key, "off the map")
		end
		if ArtRules.nearSpawn(x, z, Map.spawnZones, lines, C.spawnGap) then
			return no(key, "by a spawn")
		end
		local at = Guns.terrainAt(x, z)
		if not at then
			return no(key, "no ground")
		end
		-- (where Build.placeAs would lay it, facing the enemy's way as its job does: open, gentle ground, nothing in the way, off trenches and
		-- the other guns; Build then levels or tilts it, Config/Build.Slope)
		local why = Build.siteFor(key, CFrame.lookAt(at, at + Vector3.new(tx, 0, tz)))
		if why then
			return no(key, string.lower(why))
		end
		-- (its shot flown: within its reach on this map, Config/Artillery.Reach, and nothing in the way)
		return Guns.flyShot(gun, Guns.asset[key], at, target, "low")
			or Guns.flyShot(gun, Guns.asset[key], at, target, "high")
			or no(key, "shot blocked or out of reach")
	end
	-- (the map's marked gun spots first, each checked as a scored one; the scored ones for the rest)
	local seed: { BotBuild.Job } = {}
	local marks = BotBuild.serving(Marks[front] and Marks[front].guns, side)
	for _, w in want do
		for _, sp in marks do
			if w.count > 0 and (sp.kind == nil or sp.kind == w.key) then
				local clear = true
				for _, j in seed do
					local gap = math.max(Guns.spacing[w.key] or 0, Guns.spacing[j.key] or 0)
					clear = clear and (j.x - sp.x) ^ 2 + (j.z - sp.z) ^ 2 >= gap * gap
				end
				if clear and fits(w.key, sp.x, sp.z) then
					table.insert(seed, { key = w.key, x = sp.x, z = sp.z, fx = tx, fz = tz })
					w.count -= 1
				end
			end
		end
	end
	return BotBuild.gunSpots(zone, tx, tz, want, C, Guns.spacing, fits, seed)
end
-- `side`'s guns and MG nests in sector `i` by Config/Build piece key: its team's own `works` there (laid or standing;
-- `built`: standing only) and the enemy's there it judged "use" (src/server/Bots/Crew); with `fight`, an MG nest more than
-- Config/Bots.Crew.MG `reach` from it left out (`n.outOfFight` counts those)
local function sectorGuns(
	side: string,
	works: { Build.Work },
	i: number,
	built: boolean?,
	fight: BotCrew.Spot?
): { [string]: number }
	local n = {}
	local function add(key: string, at: Vector3)
		if fight and key == "MGNest" and not BotCrew.inReach(at.X, at.Z, { fight }, 0, Cfg.Crew.MG.reach) then
			n.outOfFight = (n.outOfFight or 0) + 1
		else
			n[key] = (n[key] or 0) + 1
		end
	end
	for _, w in works do
		if
			(w.kind == "Gun" or w.kind == "Nest")
			and (w.built or not built)
			and BotCrew.sectorAt(w.at.X, w.at.Z, Map.sectors) == i
		then
			add(w.key, w.at)
		end
	end
	for _, g in Tactics.crew.usable(side) do
		if BotCrew.sectorAt(g.at.X, g.at.Z, Map.sectors) == i then
			add(g.key, g.at)
		end
	end
	return n
end

-- the fire step a dug square gives facing the enemy's way (tx, tz): across its own line, turned with its tilt, its
-- floor riding up as it is buried (Rules/BotTrenches.firePost); nil for a square with no line
local function stepOf(w: Build.Work, tx: number, tz: number): TrenchPost?
	local m = w.model
	local a, e, tilt = m:GetAttribute("BlockA"), m:GetAttribute("BlockB"), m:GetAttribute("Tilt")
	if typeof(a) ~= "Vector3" or typeof(e) ~= "Vector3" then
		return nil
	end
	local TB, B = BuildCfg.Trench, require(Shared.Rules.Build)
	local lean = if type(tilt) == "number" then tilt else 0
	local sq = { ax = a.X, ay = a.Y, az = a.Z, bx = e.X, by = e.Y, bz = e.Z, tilt = lean }
	local fill = B.trenchSink(B.trenchDepth(w.hp, true, TB.hp), TB)
	local p = BotTrenches.firePost(sq, tx, tz, STEP, TR.rise, TB.depth, fill)
	return {
		pos = Vector3.new(p.sx, p.sy, p.sz),
		floor = Vector3.new(p.fx, p.fy, p.fz),
		face = Vector3.new(p.ox, 0, p.oz),
	}
end

-- the threats a side's runs toward the enemy are dug against (Config/Bots.Trenches.Zigzag): the enemy's next sector
-- from its front, and the enemies its squads know of
local function threatsOf(side: string, front: number, now: number): { Vector3 }
	local threats: { Vector3 } = {}
	local ahead = Map.sectors[front + (if side == "West" then 1 else -1)]
	if ahead then
		table.insert(threats, Routes.ground(ahead.x, ahead.z))
	end
	for _, sq in squads do
		if sq.side == side then
			for _, kn in sq.known do
				if now - kn.at <= SQ.knownFor then
					table.insert(threats, kn.pos)
				end
			end
		end
	end
	return threats
end

-- a trench system's runs as jobs (system `sys`): a communication trench in a zig-zag where the enemy can see down it
local function systemJobs(
	sbs: SideBuild,
	runs: { BotTrenches.Run },
	threats: { Vector3 },
	tx: number,
	tz: number,
	sys: string
): { BuildJob }
	local out: { BuildJob } = {}
	for _, run in runs do
		local legs = { run }
		if run.kind == "Comm" then
			local turn, why = runCover(run, threats)
			noteRun(sbs, "comm", turn, why)
			if turn > 0 then
				legs = BotTrenches.zigzag(run, turn, TR.Zigzag.leg)
			end
		end
		for _, leg in legs do
			local job = { key = "Trench", x = leg.ax, z = leg.az, ex = leg.bx, ez = leg.bz, fx = tx, fz = tz }
			local r = { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false, run = leg, sys = sys }
			table.insert(out, r)
		end
	end
	return out
end

-- (terrain only, water too: a square is never planned in water, Trenches.plan)
local wetParams = RaycastParams.new()
wetParams.FilterType = Enum.RaycastFilterType.Include
wetParams.FilterDescendantsInstances = { workspace.Terrain }
wetParams.IgnoreWater = false

-- (what a run's box meets: solid parts but the soldiers', the trees' and the trenches' own)
local solidParams = OverlapParams.new()
solidParams.FilterType = Enum.RaycastFilterType.Exclude
solidParams.FilterDescendantsInstances = { workspace.Terrain }

-- what stands in a system's way (Config/Bots.Trenches.Site): the standing trees on its fire and support runs (within
-- `clear` of their lines), what its diggers would wait on; `wet` for each spot along any run (every Trench.block
-- studs) in water, where no square is planned; and `solid` for each thing standing across a run (walls, poles,
-- buildings: Trenches.plan's "In the way", which no digger clears)
local function treesOn(runs: { BotTrenches.Run }): number
	local n = 0
	for _, r in runs do
		local len = math.sqrt((r.bx - r.ax) ^ 2 + (r.bz - r.az) ^ 2)
		if len > 1e-3 then
			local mid = Routes.ground((r.ax + r.bx) / 2, (r.az + r.bz) / 2)
			local box = CFrame.lookAt(mid, mid + Vector3.new(r.bx - r.ax, 0, r.bz - r.az))
			local seen: { [Instance]: boolean } = {}
			local size = Vector3.new(2 * TR.Site.clear, 2 * BuildCfg.Trench.wayHeight, len)
			for _, p in workspace:GetPartBoundsInBox(box, size, solidParams) do
				local top: Instance = p:FindFirstAncestorWhichIsA("Model") or p
				local tree = top:IsA("Model") and Trees.standing(top :: Model)
				if
					p.CanCollide
					and not tree
					and not seen[top]
					and not (top :: any):FindFirstChildOfClass("Humanoid")
				then
					seen[top] = true
					n += TR.Site.solid
				end
			end
		end
		for i = 0, math.ceil(len / BuildCfg.Trench.block) do
			local t = math.min(i * BuildCfg.Trench.block / math.max(len, 1e-3), 1)
			local x, z = r.ax + (r.bx - r.ax) * t, r.az + (r.bz - r.az) * t
			local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), wetParams)
			if hit and hit.Material == Enum.Material.Water then
				n += TR.Site.wet
			end
		end
		if r.kind ~= "Comm" then
			for _, tree in Trees.near(Vector3.new(r.ax, 0, r.az), Vector3.new(r.bx, 0, r.bz), TR.Site.clear) do
				local p = tree:GetPivot().Position
				if Trees.standing(tree) and BotTrenches.offRun(p.X, p.Z, r.ax, r.az, r.bx, r.bz) <= TR.Site.clear then
					n += 1
				end
			end
		end
	end
	return n
end

-- what a system's ground costs it (Config/Bots.Trenches.Care.Site; user 2026-11-05: "most soldiers trench in the open
-- or already highly conflicted areas, whhich ends up with them getting bombared severely by all artilleries"): the
-- shell map's heat at each spot along its runs, and each spot the enemy's `eye` (its next sector, over the ground)
-- sees over the terrain (a reverse slope hides it; trees and walls don't count: they hide a line only where they
-- stand in its way, and the planner refuses it there)
local function exposedCost(side: string, runs: { BotTrenches.Run }, eye: Vector3?): number
	local S, now = CA.Site, os.clock()
	local cost, k = 0, 0
	for _, r in runs do
		for _, p in BotTrenchCare.along(r.ax, r.az, r.bx, r.bz, S.sample) do
			cost += S.heat * math.min(Tactics.dug.mapHeat(side, p.x, p.z, now), CA.Score.heatMost)
			k += 1
			if eye and k % S.seenEvery == 0 then
				local g = Routes.ground(p.x, p.z)
				local to = g + Vector3.yAxis * S.head - eye
				if to.Magnitude <= TR.Zigzag.range then
					local hit = workspace:Raycast(eye, to, terrainOnly)
					if not hit or hit.Distance >= to.Magnitude - 1 then
						cost += S.seen
					end
				end
			end
		end
	end
	return cost
end

-- a system sited on the clearest, safest ground (Config/Bots.Trenches.Site, Care.Site): of `make(edge, shift)`'s
-- layouts, each fire line `edge` of the zone's radius out and `shift` studs across, the one with the fewest trees on
-- its runs and the least shelled and seen ground (`side`; `eye`: where the enemy looks from)
local function sited(
	make: (number, number) -> { BotTrenches.Run },
	side: string,
	eye: Vector3?,
	flag: { x: number, z: number }?
): { BotTrenches.Run }
	-- (the clearest ground first, what the planner refuses; of the layouts within Care.Site.slack of the clearest,
	-- the least shelled and seen: a measured match sited for cover first ran its fire bays into walls; none of its
	-- runs within Care.Site.flag studs of the zone's flagpole, which another measured match's fire bay ran into)
	local all, fewest = {}, math.huge
	for _, edge in TR.Site.edges do
		for _, shift in TR.Site.shifts do
			local runs = make(edge, shift)
			local n = treesOn(runs)
			for _, r in runs do
				if flag and BotTrenches.offRun(flag.x, flag.z, r.ax, r.az, r.bx, r.bz) < CA.Site.flag then
					n += math.huge
				end
			end
			table.insert(all, { runs = runs, n = n })
			fewest = math.min(fewest, n)
		end
	end
	local best, least = nil, math.huge
	for _, c in all do
		if c.n <= fewest + CA.Site.slack then
			local e = exposedCost(side, c.runs, eye)
			if e < least then
				best, least = c.runs, e
			end
		end
	end
	return best :: { BotTrenches.Run }
end

-- where the enemy looks from at sector `i` (Care.Site): its middle, `eye` studs over the ground
local function eyeAt(i: number?): Vector3?
	local sec = if i then Map.sectors[i] else nil
	return if sec then Routes.ground(sec.x, sec.z) + Vector3.yAxis * CA.Site.eye else nil
end

-- a system's fire trench planned (or refused everywhere: its breastwork stands in), every bay of it
local function fireLaid(sys: TrenchSystem, squares: { TrenchSquare }): boolean
	for _, r in sys.runs do
		local run = r.run :: BotTrenches.Run
		if run.kind == "Fire" and not r.gaveUp then
			local j = r.job
			local at = { kind = run.kind, ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number }
			if not BotTrenches.laid(at, squares, TR.on, TR.ends) then
				return false
			end
		end
	end
	return true
end

-- a system's squares (of `squares`, by its runs' lines): all of them, and its base's (a sector's support line and way
-- back; a forward line has none)
local function squaresOf(sys: TrenchSystem, squares: { TrenchSquare }): ({ TrenchSquare }, { TrenchSquare })
	local all, base = {}, {}
	for _, sq in squares do
		for _, r in sys.runs do
			local run = r.run :: BotTrenches.Run
			local j = r.job
			local from = r.from or { x = r.base.x, z = r.base.z }
			local d, t = BotTrenches.offRun(sq.x, sq.z, from.x, from.z, j.ex :: number, j.ez :: number)
			if d <= TR.on + 1 and t >= -0.05 and t <= 1.05 then
				table.insert(all, sq)
				if run.kind == "Support" or run.kind == "Rear" then
					table.insert(base, sq)
				end
				break
			end
		end
	end
	return all, base
end

-- whether a system's next forward line may be planned (Rules/BotTrenchCare.gate; Config/Bots.Trenches.Care.Gate), and
-- why not: its fire trench planned, its squares dug, a dugout (`dugouts`: each one's foot) by them, its base reinforced
local function gateOf(
	sys: TrenchSystem,
	squares: { TrenchSquare },
	dugouts: { Vector3 },
	now: number
): (boolean, string)
	local G = CA.Gate
	local laid = fireLaid(sys, squares)
	if laid and not sys.firedAt then
		sys.firedAt = now
	end
	local all, base = squaresOf(sys, squares)
	local dug, reinforced, dugout = 0, 0, false
	for _, sq in all do
		dug += if sq.built and sq.hp >= TR.standHp then 1 else 0
		for _, f in dugouts do
			if not dugout and flat(f - sq.at).Magnitude <= G.dugout then
				dugout = true
			end
		end
	end
	for _, sq in base do
		reinforced += if sq.built and sq.extra >= G.extra then 1 else 0
	end
	return BotTrenchCare.gate({
		fireLaid = laid,
		squares = #all,
		dug = dug,
		base = #base,
		reinforced = reinforced,
		dugout = dugout,
		since = if sys.firedAt then now - sys.firedAt else 0,
	}, G)
end

-- the forward fire lines out from a side's front toward the enemy's next sector (Config/Bots.Trenches.Forward; user
-- 2026-11-04: "we can see whole maps being filled with trenches"): once a system's fire trench is planned, the next
-- line `step` of the way on, joined back by a communication trench; `lines` of them, none within `keep` studs of the
-- enemy sector's zone. Its jobs go on the list (`lay`) as it is made.
local function forwardLines(
	sbs: SideBuild,
	side: string,
	owner: { string },
	front: number,
	squares: { TrenchSquare },
	dugouts: { Vector3 },
	now: number
)
	local F = TR.Forward
	local last = sbs.systems[`S{front}`]
	if not last then
		return
	end
	local s = Map.sectors[front]
	local tx, tz = BotBuild.toward(Map.sectors, front, side)
	local nextS, nextD = nil, math.huge
	for i, sec in Map.sectors do
		local d = (sec.x - s.x) * tx + (sec.z - s.z) * tz
		if owner[i] ~= side and d > 0 and d < nextD then
			nextS, nextD = i, d
		end
	end
	if not nextS then
		return
	end
	local e = Map.sectors[nextS]
	for k = 1, F.lines do
		local key = `S{front}F{k}`
		local sys = sbs.systems[key]
		if not sys then
			-- (the gate: the last line dug, a dugout in it, its base reinforced: "start, build, reinforce, then keep
			-- going", Care.Gate)
			local lastSys = last :: TrenchSystem
			local ok, why = gateOf(lastSys, squares, dugouts, now)
			lastSys.gate = why
			if not ok then
				return
			end
			local px, pz = s.x + (e.x - s.x) * F.step * k, s.z + (e.z - s.z) * F.step * k
			if math.sqrt((e.x - px) ^ 2 + (e.z - pz) ^ 2) < e.radius + F.keep then
				return
			end
			local dx, dz = e.x - s.x, e.z - s.z
			local len = math.sqrt(dx * dx + dz * dz)
			local ux, uz = dx / len, dz / len
			local runs = sited(function(edge: number, shift: number)
				-- (nearer or further along the way, across it: Trenches.Site)
				local along = (edge - TR.Fire.edge) * len * F.step
				local at = { x = px + ux * along - uz * shift, z = pz + uz * along + ux * shift }
				return BotTrenches.forward((last :: TrenchSystem).ends, at, ux, uz, TR)
			end, side, eyeAt(nextS))
			local made = systemJobs(sbs, runs, threatsOf(side, front, now), ux, uz, key)
			sbs.systems[key] =
				{ sector = front, runs = made, mid = BotTrenches.fireMid(runs), ends = BotTrenches.routeEnds(runs) }
			for _, r in made do
				table.insert(sbs.lay, r)
			end
			stats.forward += 1
			return
		end
		last = sys
	end
end

-- the free ends of a side's squares as laid, dug or only planned (no link at that end)
local function freeEnds(squares: { TrenchSquare }): { { x: number, z: number } }
	local ends: { { x: number, z: number } } = {}
	for _, sq in squares do
		for _, which in { "A", "B" } do
			local p = sq.model:GetAttribute("Block" .. which)
			if typeof(p) == "Vector3" and sq.model:GetAttribute("Link" .. which) == "" then
				table.insert(ends, { x = p.X, z = p.Z })
			end
		end
	end
	return ends
end

-- a system's fire trench ends as laid (its first bay's start and last bay's end, each the nearest real free end
-- within Trenches.Lanes.endNear of where it was planned to: Rules/BotTrenches.join)
local function fireEndsOf(sys: TrenchSystem, ends: { { x: number, z: number } }): { { x: number, z: number } }
	local first, last
	for _, r in sys.runs do
		if (r.run :: BotTrenches.Run).kind == "Fire" and not r.gaveUp then
			first = first or r
			last = r
		end
	end
	if not first or not last then
		return {}
	end
	local out = {}
	for _, p in { { x = first.job.x, z = first.job.z }, { x = last.job.ex :: number, z = last.job.ez :: number } } do
		local best, bestD = p, TR.Lanes.endNear
		for _, e in ends do
			local d = math.sqrt((e.x - p.x) ^ 2 + (e.z - p.z) ^ 2)
			if d < bestD then
				best, bestD = e, d
			end
		end
		table.insert(out, best)
	end
	return out
end

-- a line in each lane across the open field (Config/Bots.Trenches.Lanes; user 2026-11-10 via the map session: "for how
-- much open field there is, i dont see any trenches", chose a line in each lane): once its front has its own system,
-- each other lane of the front (Config/Bots.Lanes) gets a fire trench level with it and a way back, the lanes its
-- holders stand in first, one a tick; neighbouring lines (its front's own in the middle lane, as it stands) are joined
-- end to end once both are planned, into one line across the field.
local function laneLines(sbs: SideBuild, side: string, front: number, squares: { TrenchSquare }, now: number)
	local L = TR.Lanes
	local main = sbs.systems[`S{front}`]
	-- (not waiting on its own fire trench: a measured Lantern Meadows match had every point's refused for the village's
	-- walls and houses, "In the way", and nothing past it ever planned)
	if not L.on or not LN.on or not main then
		return
	end
	local s = Map.sectors[front]
	local tx, tz = BotBuild.toward(Map.sectors, front, side)
	local f = BotLanes.frame(s.x, s.z, tx, tz, s.radius * TR.Fire.edge, laneBounds, LN)
	local mid = BotLanes.laneOf(f, BotLanes.offset(f, main.mid.x, main.mid.z))
	local held: { [number]: boolean } = {}
	for _, st in squads do
		if st.side == side and st.sector == front and st.slot then
			held[st.slot :: number] = true
		end
	end
	local function line(k: number): TrenchSystem?
		return if k == mid then main else sbs.systems[`S{front}L{k}`]
	end
	local ends = freeEnds(squares)
	for k = 1, #f.centres - 1 do
		local key = `S{front}J{k}`
		local a, b = line(k), line(k + 1)
		-- (the front's own line joined as it stands: its ends as laid, else as planned)
		local ready = a and b and (a == main or fireLaid(a, squares)) and (b == main or fireLaid(b, squares))
		if not sbs.systems[key] and ready then
			local runs = BotTrenches.join(
				fireEndsOf(a :: TrenchSystem, ends),
				fireEndsOf(b :: TrenchSystem, ends),
				L.joinMost,
				L.joinLeast,
				L.joinFar
			)
			local made = systemJobs(sbs, runs, {}, tx, tz, key)
			sbs.systems[key] = { sector = front, runs = made, mid = { x = 0, z = 0 }, ends = {} }
			for _, r in made do
				table.insert(sbs.lay, r)
			end
			stats.laneJoins += if #made > 0 then 1 else 0
			ByTrench.runs[`{side} laneJoins`] = (ByTrench.runs[`{side} laneJoins`] or 0) + (if #made > 0 then 1 else 0)
			return
		end
	end
	local ahead = front + (if side == "West" then 1 else -1)
	local eye = if Map.sectors[ahead] then eyeAt(ahead) else nil
	for _, k in BotTrenches.laneOrder(#f.centres, mid, held) do
		local key = `S{front}L{k}`
		if not sbs.systems[key] then
			local px, pz = BotLanes.point(f, k, tx, tz, 0)
			local cfg = {
				gap = L.gap,
				bay = L.bay,
				bays = L.bays,
				back = L.back,
				traverse = TR.Fire.traverse,
				short = TR.Comm.short,
			}
			local runs = sited(function(edge: number, shift: number)
				-- (nearer or further along the way, across it: Trenches.Site)
				local along = (edge - TR.Fire.edge) * s.radius
				return BotTrenches.laneLine(
					px + tx * along + f.ax * shift * L.shift,
					pz + tz * along + f.az * shift * L.shift,
					tx,
					tz,
					2 * f.half,
					cfg
				)
			end, side, eye)
			local made = systemJobs(sbs, runs, threatsOf(side, front, now), tx, tz, key)
			sbs.systems[key] =
				{ sector = front, runs = made, mid = BotTrenches.fireMid(runs), ends = BotTrenches.routeEnds(runs) }
			for _, r in made do
				table.insert(sbs.lay, r)
			end
			stats.laneLines += 1
			ByTrench.runs[`{side} laneLines`] = (ByTrench.runs[`{side} laneLines`] or 0) + 1
			return
		end
	end
end

-- a side's trench duty (Config/Bots.Trenches.pioneers): while its list has a trench job open (or a tree in its lines'
-- way), up to `pioneers` of its (more as squares wait to be dug, Trenches.More)
-- living bots (those already on it, then defenders, the nearest its front first; never a gun or dugout Engineer, nor
-- one manning a gun) dig its lines; none while it has none
local function pioneers(side: string)
	local sb = buildLists[side]
	local want = false
	for _, r in (if sb and sb.front then sb.open else {}) do
		if r.job.key == "Trench" or r.job.key == "Tree" then
			want = true
			break
		end
	end
	local at = if want then Map.sectors[(sb :: SideBuild).front :: number] else nil
	-- (more once its lines are planned: one for each Trenches.More.per squares waiting to be dug)
	local undug = 0
	for _, t in (if sb then sb.trench else {}) do
		undug += if t.built then 0 else 1
	end
	local most = BotTrenches.pioneersWanted(TR.pioneers, undug, TR.More)
	local on, free = 0, {}
	for _, b in bots do
		if b.side == side then
			local fit = at ~= nil
				and b.m ~= nil
				and b.root ~= nil
				and not b.deadAt
				and not b.crew
				and not b.dugouts
				and not b.gun
			if b.pioneer and fit and on < most then
				on += 1
			else
				b.pioneer = nil
				if fit then
					local p = (b.root :: BasePart).Position
					local d = Vector3.new(p.X - at.x, 0, p.Z - at.z).Magnitude
					table.insert(free, { b = b, d = d + (if b.order == "Defend" then 0 else 1e4) })
				end
			end
		end
	end
	table.sort(free, function(x, y)
		return x.d < y.d
	end)
	for i = 1, math.min(most - on, #free) do
		free[i].b.pioneer = true
		stats.pioneers += 1
	end
	-- (`Care.repairers` of them take its best repair first while it has one: Act.pickTrench)
	local repairs = false
	for _, r in (if sb and sb.front then sb.open else {}) do
		repairs = repairs or r.care ~= nil
	end
	local n = 0
	for _, b in bots do
		if b.side == side then
			b.repairer = nil
			if repairs and b.pioneer and n < CA.repairers then
				b.repairer = true
				n += 1
			end
		end
	end
end
local function buildList(side: string, owner: { string }, fromEnd: number)
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
			held = -1,
			holds = false,
			latched = false,
			lay = {},
			works = {},
			open = {},
			steps = {},
			reserve = {},
			squares = {},
			standTo = false,
			fallbackUntil = 0,
			trench = {},
			lines = {},
			guns = 0,
			rooms = {},
			enemies = {},
			shelled = false,
			shelledOnce = false,
			bays = 0,
			digging = 0,
			hurt = {},
			runNotes = {},
			systems = {},
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
		sbs.trench = {}
		sbs.lines = {}
		sbs.rooms, sbs.shelled, sbs.digging = {}, false, 0
		sbs.enemies = {}
		return
	end
	local s = Map.sectors[front :: number]
	local zone = { x = s.x, z = s.z, radius = s.radius }
	local tx, tz = BotBuild.toward(Map.sectors, front :: number, side) -- (the enemy's way, from the live map's chain)
	local fightX, fightZ = BotBuild.fightPoint(Map.sectors, front :: number, side, Cfg.Crew.MG.fightAt)
	local fight = { x = fightX, z = fightZ }
	local spots = Routes.spots(front :: number, side, true)
	local fl = workspace:FindFirstChild(FrontCfg.FolderName)
	local latched = fl ~= nil and fl:GetAttribute(side .. FrontCfg.LatchAttribute) == true
	if front ~= sbs.front or fromEnd ~= sbs.held or latched ~= sbs.latched or (not sbs.holds and spots ~= nil) then
		local holds = {}
		-- (MG nests off the flag: Config/Bots.OffPoint, where any hold spot is)
		for _, sp in spots or {} do
			if (sp.pos.X - s.x) ^ 2 + (sp.pos.Z - s.z) ^ 2 >= OP.clear ^ 2 then
				table.insert(holds, { x = sp.pos.X, z = sp.pos.Z, hidden = sp.hidden })
			end
		end
		if #holds == 0 then
			for _, sp in spots or {} do
				table.insert(holds, { x = sp.pos.X, z = sp.pos.Z, hidden = sp.hidden })
			end
		end
		local guns = {}
		for _, key in Guns.list do
			if FrontRules.gunLocked(FrontCfg.Artillery, key, fromEnd, latched) == nil then
				table.insert(guns, key)
			end
		end
		-- the guns on scored spots behind the line (Rules/BotBuild.gunSpots), else the plan's fixed ones
		table.clear(Guns.drawn)
		table.clear(Guns.why)
		local spotted = Guns.spots(front :: number, side, zone, tx, tz, guns)
		Guns.draw(side)
		-- (a gun its side may build with no scored spot gets the plan's fixed one, behind the zone: Build.placeAs then
		-- nudges it; and why each gun is or isn't planned, for the Engineer bots readout)
		local unplaced: { string } = {}
		local notes: { string } = {}
		for _, key in Guns.list do
			local placed = 0
			for _, j in spotted do
				placed += if j.key == key then 1 else 0
			end
			local locked = FrontRules.gunLocked(FrontCfg.Artillery, key, fromEnd, latched)
			if locked then
				table.insert(notes, `{key} locked ({locked})`)
			elseif (BD.caps[key] or 0) <= 0 then
				table.insert(notes, `{key} none for bots`)
			elseif placed > 0 then
				table.insert(notes, `{key} {placed} spot{if placed > 1 then "s" else ""}`)
			else
				table.insert(unplaced, key)
				local why = {}
				for w, n in Guns.why[key] or {} do
					table.insert(why, `{w} {n}`)
				end
				table.sort(why)
				table.insert(notes, `{key} no scored spot ({table.concat(why, ", ")}): the fixed one`)
			end
		end
		sbs.gunNote = table.concat(notes, "; ")
		sbs.lay = {}
		-- (wire only in the enemy's way, Rules/BotBuild.wireSpot: off its own side's ways forward, from the front to the
		-- enemy's nearest sector and the approach spots round it, and off its spawn)
		local ways: { { ax: number, az: number, bx: number, bz: number } } = {}
		local nextS, nextD = nil, math.huge
		for i, sec in Map.sectors do
			local dx = (sec.x - s.x) * tx + (sec.z - s.z) * tz
			if owner[i] ~= side and dx > 0 and dx < nextD then
				nextS, nextD = i, dx
			end
		end
		if nextS then
			local sec = Map.sectors[nextS]
			table.insert(ways, { ax = s.x, az = s.z, bx = sec.x, bz = sec.z })
			for _, sp in Routes.spots(nextS, side, false) or {} do
				table.insert(ways, { ax = s.x, az = s.z, bx = sp.pos.X, bz = sp.pos.Z })
			end
		end
		-- (MG nests: those missing of its share, its side's standing ones in its front sector and captured ones it uses
		-- there counted; one still going up gets its job again)
		-- (one that can't reach the fight doesn't count: a nearer one is planned)
		local standing = sectorGuns(side, Build.worksOf(kit), front :: number, true, fight)
		local missing = math.max((BD.caps.MGNest or 0) - (standing.MGNest or 0), 0)
		-- (the nests on the map's marked MG spots first, those with no nest of its side by them yet)
		local mgSpots = {}
		for _, sp in BotBuild.serving(Marks[front :: number] and Marks[front :: number].mg, side) do
			local free = BotCrew.inReach(sp.x, sp.z, { fight }, 0, Cfg.Crew.MG.reach)
			for _, w in Build.worksOf(kit) do
				free = free and not (w.key == "MGNest" and (w.at.X - sp.x) ^ 2 + (w.at.Z - sp.z) ^ 2 <= OP.nestGap ^ 2)
			end
			if free then
				table.insert(mgSpots, sp)
			end
		end
		-- (each nest `Nest.gap` studs from every nest of its side, standing, going up or captured and used, and from the
		-- others planned now: the marked spots first, then the hold spots nearest the enemy, Rules/BotBuild.spaced)
		local nestCands: { BotBuild.Job } = {}
		for _, sp in mgSpots do
			local fx, fz = tx, tz
			if sp.face then
				fx, fz = BotBuild.bearingWay(sp.face)
			end
			table.insert(nestCands, { key = "MGNest", x = sp.x, z = sp.z, fx = fx, fz = fz })
		end
		local planned =
			BotBuild.plan(zone, tx, tz, holds, if #spotted > 0 then unplaced else guns, Flanked.plan, #holds)
		for _, job in planned do
			if job.key == "MGNest" then
				table.insert(nestCands, job)
			end
		end
		local nestsAt = {}
		for _, w in Build.worksOf(kit) do
			if w.key == "MGNest" then
				table.insert(nestsAt, { x = w.at.X, z = w.at.Z })
			end
		end
		for _, u in Tactics.crew.usable(side) do
			if u.key == "MGNest" then
				table.insert(nestsAt, { x = u.at.X, z = u.at.Z })
			end
		end
		local nestJobs, passed = BotBuild.spaced(nestCands, nestsAt, BD.Nest.gap, missing)
		Tactics.crew.nestsTight[side] = (Tactics.crew.nestsTight[side] or 0) + passed
		for _, job in planned do
			if job.key ~= "MGNest" then
				table.insert(nestJobs, job)
			end
		end
		for _, job in nestJobs do
			local keep = true
			if job.key == "Wire" then
				local wx, wz = BotBuild.wireSpot(job.x, job.z, -tz, tx, ways, (Map.spawnZones :: any)[side], BD.Wire)
				if wx ~= job.x or wz ~= job.z then
					stats.wireMoved += 1
				end
				if wx and wz then
					job = { key = job.key, x = wx, z = wz, fx = job.fx, fz = job.fz }
				else
					keep = false
				end
			end
			if keep then
				table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
			end
		end
		for _, job in spotted do
			table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
		end
		-- the trench system (Rules/BotTrenches): fire, support and communication trenches, dug in that order
		-- (its communication trenches run toward the enemy: a zig-zag where the enemy's next sector, or an enemy its
		-- squads know of, can see down one; Trenches.Zigzag)
		-- one system a sector, kept while the side holds it, as it was left when the front moved (user 2026-11-04, the
		-- trench priority: a measured match's fronts flipped every 2 min and each flip planned the lines afresh)
		local key = `S{front}`
		if not sbs.systems[key] then
			local runs = sited(function(edge: number, shift: number)
				local cfg = table.clone(TR)
				cfg.Fire = table.clone(TR.Fire)
				cfg.Fire.edge = edge
				local at = { x = zone.x - tz * shift, z = zone.z + tx * shift, radius = zone.radius }
				return BotTrenches.layout(at, tx, tz, cfg)
			end, side, eyeAt(nextS), zone)
			local made = systemJobs(sbs, runs, threatsOf(side, front :: number, now), tx, tz, key)
			sbs.systems[key] = {
				sector = front :: number,
				runs = made,
				mid = BotTrenches.fireMid(runs),
				ends = BotTrenches.routeEnds(runs),
			}
		end
		for _, sys in sbs.systems do
			if owner[sys.sector] == side then
				for _, r in sys.runs do
					table.insert(sbs.lay, r)
				end
			end
		end
		if front ~= sbs.front then
			sbs.shelledOnce = false
		end
		sbs.front, sbs.held, sbs.holds, sbs.latched = front, fromEnd, spots ~= nil, latched
	end
	local works, roomOf = Tactics.dug.works(kit, BD.builder)
	-- (no new square while its own offensive shells and goes in, nor on freshly shelled ground: Care.Hot; user
	-- 2026-11-05: "most soldiers trench in the open or already highly conflicted areas")
	local myOff = (fronts.sides[side] or {} :: any).off :: Orders.Offensive?
	local pushNow = myOff ~= nil and (myOff.phase == "Barrage" or myOff.phase == "Go")
	local care: { [string]: number } = {}
	sbs.care = care
	local function hotAt(x: number, z: number): boolean
		local hot = BotTrenchCare.shelledNear(Tactics.dug.heat, x, z, now, CA.Hot.radius, CA.Hot.seconds)
		if hot then
			care.hotSkips = (care.hotSkips or 0) + 1
		end
		return hot
	end
	-- what lost HP lately (Rules/BotBuild.mayRepair): no swings at it until BD.repairWait after
	local hurt = sbs.hurt
	local present: { [Model]: boolean } = {}
	for _, w in works do
		local h = hurt[w.model]
		if h and w.hp < h.hp - 1e-3 then
			h.at = now
		end
		if h then
			h.hp = w.hp
		else
			hurt[w.model] = { hp = w.hp, at = -math.huge }
		end
		present[w.model] = true
	end
	for model in hurt do
		if not present[model] then
			hurt[model] = nil
		end
	end
	local function quiet(model: Model): boolean
		local h = hurt[model]
		local ok = BotBuild.mayRepair(now - (if h then h.at else -math.huge), BD.repairWait)
		if not ok then
			stats.waited += 1
		end
		return ok
	end
	local pieces: { BotBuild.Piece } = {}
	local mine, ofKey = 0, {}
	sbs.guns = 0
	for i, w in works do
		pieces[i] = { key = w.key, x = w.at.X, z = w.at.Z, left = w.left }
		if Kinds.gun[w.key] then
			sbs.guns += 1
		end
		if w.owner and (w.owner :: number) < 0 and w.key ~= "Trench" then
			mine += 1
			ofKey[w.key] = (ofKey[w.key] or 0) + 1
		end
	end
	-- (its guns and MG nests are counted by the sector: the team's own in its front sector, anyone's laying them, and the
	-- enemy's there it judged worth using, against its share, BD.caps; user 2026-11-03: "cannons and artys built
	-- should be by sector")
	local inFront = sectorGuns(side, works, front :: number, nil, fight)
	sbs.inFront = inFront
	Tactics.crew.nestsOut[side] = inFront.outOfFight or 0
	-- (a trench run is matched by its squares, Rules/BotTrenches.laid; the rest by BotBuild.match)
	local jobs = {}
	local runs: { BotTrenches.Run } = {}
	local runMeta: { { kind: string, sys: string, route: number? } } = {}
	local runLaid: { [number]: boolean } = {}
	local squares: { TrenchSquare } = {}
	local dug = 0
	for _, w in works do
		if w.key == "Trench" then
			dug += 1
			table.insert(squares, {
				x = w.at.X,
				z = w.at.Z,
				at = w.at,
				model = w.model,
				left = w.left,
				built = w.built,
				extra = w.extra or 0,
				hp = w.hp,
				max = w.max,
			})
		end
	end
	sbs.trench = squares
	-- (its dugouts' feet: the forward lines' gate, Care.Gate)
	local feet: { Vector3 } = {}
	for _, w in works do
		if w.key == "Dugout" and w.built then
			table.insert(feet, w.at)
		end
	end
	forwardLines(sbs, side, owner, front :: number, squares, feet, now)
	laneLines(sbs, side, front :: number, squares, now)
	if Clear.everyAt ~= commandTick then
		Clear.everyAt, Clear.every = commandTick, Build.worksOf(nil)
	end
	-- (each fire bay starts where the last one ends, the second communication run where the first ends: at the real free
	-- end of its squares as laid (dug or only planned), Trenches.Chain, else its planned end; one planned part way goes
	-- on from its part's real end. A run already laid keeps its line.)
	local ends = freeEnds(squares)
	local CH = TR.Chain
	local chain: { [string]: BuildJob } = {}
	for _, r in sbs.lay do
		local run = r.run
		if run and run.kind ~= "Support" then
			local ck = `{r.sys or ""}{run.kind}{run.route or ""}`
			local last = chain[ck]
			local j = r.job
			local rest = { kind = run.kind, ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number }
			if not r.gaveUp and not BotTrenches.laid(rest, squares, TR.on, TR.ends) then
				local x, z = j.x, j.z
				if r.from then
					local e = BotTrenches.lastEnd(ends, r.from.x, r.from.z, j.ex :: number, j.ez :: number, CH.off, 0)
					if e then
						x, z = e.x, e.z
					end
				elseif last then
					-- (only once the run before is planned: before that its "end" is whatever trench lies at its
					-- start, a support line's end where a way up begins)
					local lj = last.job
					local from = last.from or { x = lj.x, z = lj.z }
					local lastRun =
						{ kind = run.kind, ax = from.x, az = from.z, bx = lj.ex :: number, bz = lj.ez :: number }
					if last.gaveUp or BotTrenches.laid(lastRun, squares, TR.on, TR.ends) then
						local e =
							BotTrenches.lastEnd(ends, from.x, from.z, lj.ex :: number, lj.ez :: number, CH.off, CH.past)
						x, z = if e then e.x else lj.ex :: number, if e then e.z else lj.ez :: number
					end
				end
				if x ~= j.x or z ~= j.z then
					local k = `{side} chained`
					ByTrench.runs[k] = (ByTrench.runs[k] or 0) + 1
					r.job = { key = j.key, x = x, z = z, ex = j.ex, ez = j.ez, fx = j.fx, fz = j.fz }
				end
			end
			chain[ck] = r
		end
	end
	-- (each system's runs in order, for Rules/BotTrenches.ready: its own runs before it, not another system's)
	local sysLaid: { [string]: { boolean } } = {}
	local sysKinds: { [string]: { string } } = {}
	local sysRoutes: { [string]: { [number]: number } } = {}
	local sysAt: { [number]: number } = {}
	for k, r in sbs.lay do
		local j = r.job
		if r.run then
			-- (a run planned part way: its whole line for the posts, what is left of it to plan)
			local kind = (r.run :: BotTrenches.Run).kind
			local from = r.from or { x = j.x, z = j.z }
			local run = { kind = kind, ax = from.x, az = from.z, bx = j.ex :: number, bz = j.ez :: number }
			local rest = { kind = kind, ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number }
			local short = r.from ~= nil
				and math.sqrt((rest.bx - rest.ax) ^ 2 + (rest.bz - rest.az) ^ 2) < BuildCfg.Trench.block
			table.insert(runs, run)
			runMeta[#runs] = { kind = kind, sys = r.sys or "", route = (r.run :: BotTrenches.Run).route }
			-- (a run refused everywhere counts as done: a breastwork stands in for it, the next run goes on)
			runLaid[#runs] = r.gaveUp == true or short or BotTrenches.laid(rest, squares, TR.on, TR.ends) ~= nil
			local sys = r.sys or ""
			sysLaid[sys] = sysLaid[sys] or {}
			sysKinds[sys] = sysKinds[sys] or {}
			sysRoutes[sys] = sysRoutes[sys] or {}
			table.insert(sysLaid[sys], runLaid[#runs])
			table.insert(sysKinds[sys], run.kind)
			sysAt[#runs] = #sysLaid[sys]
			sysRoutes[sys][#sysLaid[sys]] = (r.run :: BotTrenches.Run).route :: number
			jobs[k] = { key = "", x = 0, z = 0, fx = 0, fz = 0 }
		else
			jobs[k] = j
		end
	end
	local matched = BotBuild.match(jobs, pieces, BD.match)
	local claimed: { [Model]: boolean } = {}
	local ri = 0
	local more: { BotBuild.Job } = {} -- breastworks and walls to add
	local WL = BD.Walls
	for k, r in sbs.lay do
		local i = matched[k]
		if r.run and r.gaveUp and not r.done and r.run.kind ~= "Comm" and r.run.kind ~= "Rear" then
			-- a breastwork where the ground refused the trench (user 2026-11-02: "Breastworks")
			r.done = true
			stats.breastworks += 1
			local b0 = r.base
			for _, job in
				BotBuild.line(b0.x, b0.z, b0.ex :: number, b0.ez :: number, tx, tz, BD.Breast.step, BD.Breast.keys)
			do
				table.insert(more, job)
			end
		elseif i and not r.done and works[i].built and (r.job.key == "MGNest" or Kinds.gun[r.job.key]) then
			-- a wall on the enemy side of a nest or gun that stands (user 2026-11-02: "Walls round nest and gun")
			r.done = true
			stats.walls += 1
			local at = works[i].at
			for _, job in BotBuild.wall(at.X, at.Z, tx, tz, WL.ahead, WL.spread, WL.count) do
				table.insert(more, job)
			end
		end
		if r.run then
			ri += 1
			r.model, r.at, r.left = nil, nil, 0
			local sys = r.sys or ""
			r.open = not runLaid[ri]
				and now >= r.waitUntil
				and dug < TR.cap
				and not pushNow
				and BotTrenches.ready(sysLaid[sys], sysAt[ri], sysKinds[sys], sysRoutes[sys])
		elseif i then
			local w = works[i]
			r.model, r.at, r.left = w.model, w.at, w.left
			claimed[w.model] = true
			r.open = w.left > 0 and quiet(w.model)
		else
			r.model, r.at, r.left = nil, nil, 0
			local key = r.job.key
			local had = if BD.caps[key] then inFront[key] or 0 else ofKey[key] or 0
			r.open = now >= r.waitUntil and (key == "Trench" or BotBuild.allowed(key, mine, had, BD.caps))
		end
		if r.open then
			table.insert(sbs.open, r)
		end
	end
	for _, job in more do
		table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
	end
	-- what each of its squares is worth looking after (Rules/BotTrenchCare; Config/Bots.Trenches.Care.Score; user
	-- 2026-11-05: "have some logical thinking for whether a trench should be repaired")
	-- (its bots in each square lately: one second of one bot is one, fading by e every Score.fade s)
	local SC = CA.Score
	local traffic = sbs.traffic or {}
	sbs.traffic = traffic
	for model, t in traffic do
		t.v, t.t = t.v * math.exp(-(now - t.t) / SC.fade), now
		if t.v < 0.01 then
			traffic[model] = nil
		end
	end
	local tick = now - (sbs.trafficAt or now)
	sbs.trafficAt = now
	for _, b in bots do
		if b.side == side and alive(b) and b.root then
			local p = (b.root :: BasePart).Position
			local i = BotTrenches.inSquare(p.X, p.Z, squares, TR.Stats.floor)
			if i then
				local m = squares[i].model
				local t = traffic[m] or { v = 0, t = now }
				t.v += math.min(tick, 2)
				traffic[m] = t
			end
		end
	end
	-- (the line each square lies on, and each system's ways up dug whole)
	local function lineOf(x: number, z: number): { kind: string, sys: string, route: number? }?
		for k, run in runs do
			local d, t = BotTrenches.offRun(x, z, run.ax, run.az, run.bx, run.bz)
			if d <= TR.on + 1 and t >= -0.05 and t <= 1.05 then
				return runMeta[k]
			end
		end
		return nil
	end
	local onLine: { [Model]: { kind: string, sys: string, route: number? }? } = {}
	local routeAll, routeUp = {}, {}
	for _, sq in squares do
		local m = lineOf(sq.x, sq.z)
		onLine[sq.model] = m
		if m and m.kind == "Comm" and m.route then
			local rk = `{m.sys} {m.route}`
			routeAll[rk] = (routeAll[rk] or 0) + 1
			routeUp[rk] = (routeUp[rk] or 0) + (if sq.built and sq.hp >= TR.standHp then 1 else 0)
		end
	end
	local routesDug: { [string]: number } = {}
	for rk, all in routeAll do
		if routeUp[rk] == all then
			local sys = string.match(rk, "^(%S+)") :: string
			routesDug[sys] = (routesDug[sys] or 0) + 1
			care.routes = (care.routes or 0) + 1
		end
	end
	-- (how long its squares stand: from dug, or dug again, to buried under Trenches.standHp or gone; the admin trench
	-- stats, Care; and its base's squares standing)
	local born = sbs.born or {}
	sbs.born = born
	local up: { [Model]: boolean } = {}
	for _, sq in squares do
		local standing = sq.built and sq.hp >= TR.standHp
		up[sq.model] = standing or nil
		if standing and not born[sq.model] then
			born[sq.model] = now
		end
		local line = onLine[sq.model]
		if line and (line.kind == "Support" or line.kind == "Rear") then
			care.baseAll = (care.baseAll or 0) + 1
			care.baseUp = (care.baseUp or 0) + (if standing then 1 else 0)
		end
	end
	for model, at in born do
		if not up[model] then
			born[model] = nil
			local lives = ByTrench.lives[side] or {}
			ByTrench.lives[side] = lives
			table.insert(lives, now - at)
		end
	end
	-- (safe ground: its front system's support line, and behind it)
	local baseAt = { x = zone.x - tx * TR.Support.back, z = zone.z - tz * TR.Support.back }
	for _, r in (sbs.systems[`S{front}`] or { runs = {} } :: any).runs do
		if r.run and r.run.kind == "Support" then
			baseAt = { x = (r.base.x + (r.base.ex :: number)) / 2, z = (r.base.z + (r.base.ez :: number)) / 2 }
		end
	end
	local function careFor(
		x: number,
		z: number,
		model: Model?,
		line: { kind: string, sys: string, route: number? }?
	): BotTrenchCare.SquareCare
		local ahead = (x - baseAt.x) * tx + (z - baseAt.z) * tz
		local t = if model then traffic[model] else nil
		local dugout = false
		for _, f in feet do
			dugout = dugout or (f.X - x) ^ 2 + (f.Z - z) ^ 2 <= CA.Gate.dugout ^ 2
		end
		local kind = if line then line.kind else ""
		return {
			used = if t then t.v / SC.busy else 0,
			safe = math.clamp(1 - ahead / SC.far, 0, 1),
			dugout = dugout,
			base = kind == "Support" or kind == "Rear",
			link = kind == "Comm" and (routesDug[(line :: any).sys] or 0) < 2,
			heat = Tactics.dug.mapHeat(side, x, z, now),
			hot = BotTrenchCare.shelledNear(Tactics.dug.heat, x, z, now, CA.Hot.radius, CA.Hot.seconds),
		}
	end
	-- a square dug full and buried to nothing (gone from its works) is planned again where it lay, if not at a sector
	-- the enemy holds and worth it (Care.Score: not "ignore"), for Trenches.Redig.keep s; open within Trenches.digReach
	-- of its front zone, not while its offensive goes in nor on freshly shelled ground (Trenches.Redig, Care.Hot)
	local had = sbs.had or {}
	sbs.had = had
	local redigs = sbs.redigs or {}
	sbs.redigs = redigs
	local stillDug: { [Model]: boolean } = {}
	for _, w in works do
		if w.key == "Trench" and w.built then
			stillDug[w.model] = true
			if not had[w.model] then
				local a, c = w.model:GetAttribute("BlockA"), w.model:GetAttribute("BlockB")
				if typeof(a) == "Vector3" and typeof(c) == "Vector3" then
					had[w.model] = { a = a, b = c }
				end
			end
		end
	end
	for model, line in had do
		if not stillDug[model] then
			had[model] = nil
			local mx, mz = (line.a.X + line.b.X) / 2, (line.a.Z + line.b.Z) / 2
			local at = BotCrew.sectorAt(mx, mz, Map.sectors)
			local worth = BotTrenchCare.decide(careFor(mx, mz, model, lineOf(mx, mz)), SC) ~= "ignore"
			if not worth then
				care.lost = (care.lost or 0) + 1
			end
			if worth and (at == nil or owner[at] == side) then
				local job =
					{ key = "Trench", x = line.a.X, z = line.a.Z, ex = line.b.X, ez = line.b.Z, fx = tx, fz = tz }
				table.insert(redigs, {
					job = job,
					base = job,
					left = 0,
					tries = 0,
					waitUntil = 0,
					open = false,
					redig = now + TR.Redig.keep,
				})
			end
		end
	end
	local reach = zone.radius + TR.digReach
	for k = #redigs, 1, -1 do
		local r = redigs[k]
		local j = r.job
		local line = { kind = "Redig", ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number }
		local laidAt = BotTrenches.laid(line, squares, TR.on, TR.ends)
		if laidAt or r.gaveUp or now > (r.redig :: number) then
			r.open = false
			table.remove(redigs, k)
			if laidAt then
				local tk = `{side} redug`
				ByTrench.runs[tk] = (ByTrench.runs[tk] or 0) + 1
			end
		else
			local mx, mz = (j.x + (j.ex :: number)) / 2, (j.z + (j.ez :: number)) / 2
			r.open = now >= r.waitUntil
				and dug < TR.cap
				and not pushNow
				and (mx - zone.x) ^ 2 + (mz - zone.z) ^ 2 <= reach * reach
				and not hotAt(mx, mz)
			if r.open then
				table.insert(sbs.open, r)
			end
		end
	end
	-- another network of its trenches joined to its main one (Config/Bots.Trenches.Care.Join; the user, 2026-11-05: "do
	-- bots connect their trench to an existing one when it helps?"): its squares (players' too) in networks, the main
	-- one its front system's base is in; the nearest end of another of `min` squares or more within `reach` gets a
	-- communication run to it, one at a time, not on freshly shelled ground nor while its offensive goes in
	local joins = sbs.joins or { skip = {}, at = -math.huge, n = 0 }
	sbs.joins = joins
	local pending = false
	for _, r in sbs.lay do
		pending = pending or (r.sys ~= nil and string.sub(r.sys, 1, 1) == "J" and r.open)
	end
	if not pending and not pushNow and now - joins.at >= CA.Join.every then
		joins.at = now
		local segs: { BotTrenchCare.Seg } = {}
		local mainAt, mainD = nil, math.huge
		for _, w in Clear.every do
			if w.key == "Trench" and w.team == kit then
				local a, c = w.model:GetAttribute("BlockA"), w.model:GetAttribute("BlockB")
				if typeof(a) == "Vector3" and typeof(c) == "Vector3" then
					table.insert(segs, { ax = a.X, az = a.Z, bx = c.X, bz = c.Z })
					local d = (w.at.X - baseAt.x) ^ 2 + (w.at.Z - baseAt.z) ^ 2
					if d < mainD then
						mainAt, mainD = #segs, d
					end
				end
			end
		end
		if mainAt then
			local net = BotTrenchCare.networks(segs, CA.Join.touch)
			local run = BotTrenchCare.linkRun(segs, net, net[mainAt], joins.skip, CA.Join)
			if run then
				joins.skip[BotTrenchCare.endKey(run.ax, run.az)] = true
				local mx, mz = (run.ax + run.bx) / 2, (run.az + run.bz) / 2
				if not hotAt(mx, mz) then
					joins.n += 1
					local leg = { kind = "Comm", ax = run.ax, az = run.az, bx = run.bx, bz = run.bz }
					for _, r in systemJobs(sbs, { leg }, threatsOf(side, front :: number, now), tx, tz, `J{joins.n}`) do
						table.insert(sbs.lay, r)
					end
					local k = `{side} joins`
					ByTrench.runs[k] = (ByTrench.runs[k] or 0) + 1
				end
			end
		end
	end
	-- the trench lines its bots lay no piece on (user 2026-11-02: "never have structures where trenches should be"):
	-- every trench square's, any team's; its runs not refused everywhere; each of its saps' run and the next
	local lines: { BotTrenches.Run } = {}
	for _, w in Clear.every do
		if w.key == "Trench" then
			local a, c = w.model:GetAttribute("BlockA"), w.model:GetAttribute("BlockB")
			if typeof(a) == "Vector3" and typeof(c) == "Vector3" then
				table.insert(lines, { kind = "Square", ax = a.X, az = a.Z, bx = c.X, bz = c.Z })
			end
		end
	end
	for _, r in sbs.lay do
		local j = r.job
		if r.run and not r.gaveUp then
			table.insert(lines, { kind = "Run", ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number })
		end
	end
	for _, sq in squads do
		local sap = sq.sap
		if sq.side == side and sap then
			local hx, hz = sap.head.X, sap.head.Z
			local r = sap.run
			if r and not r.gaveUp then
				local j = r.job
				table.insert(lines, { kind = "Sap", ax = j.x, az = j.z, bx = j.ex :: number, bz = j.ez :: number })
				hx, hz = j.ex :: number, j.ez :: number
			end
			local bx, bz =
				BotSap.run(hx, hz, sap.goal.X, sap.goal.Z, sap.k + 1, { run = SP.run, angle = sap.angle or SP.angle })
			table.insert(lines, { kind = "Sap", ax = hx, az = hz, bx = bx, bz = bz })
		end
	end
	sbs.lines = lines
	-- swings wanted: the nearest pieces (Build.repairs of them) and trench squares (Trenches.digs)
	local keep: { [Model]: BuildJob } = {}
	local n, nd = 0, 0
	-- (its guns out of service first, wherever they stand: fixed before anyone mans them, Rules/BotCrew.repairOrder)
	-- (one whose shot no longer reaches the enemy isn't: Crew.useful; the broken ones tallied for the readout)
	local fixable = {}
	local broken = Tactics.crew.broken[side] or { fixing = 0, left = 0, captured = 0 }
	Tactics.crew.broken[side] = broken
	broken.fixing, broken.left = 0, 0
	for i, w in works do
		local at = BotCrew.sectorAt(w.at.X, w.at.Z, Map.sectors)
		local gun = w.kind == "Gun" or w.kind == "Nest"
		local useful = if gun then Tactics.crew.usefulAt(side, w.at, BD.usefulNear) else nil
		fixable[i] = {
			gun = gun,
			built = w.built,
			held = at ~= nil and owner[at] == side,
			hp = w.hp,
			max = w.max,
			useful = useful,
		}
		local f = fixable[i]
		if gun and f.built and f.held and w.max > 0 and w.hp / w.max * 100 < ArtCfg.Man.keep - 1e-6 then
			if useful == false then
				broken.left += 1
			else
				broken.fixing += 1
			end
		end
	end
	-- (its trench squares from further off: its lines at the sectors it holds and its forward lines, Trenches.digReach)
	-- (its dug squares by what each is worth, Care.Score: those wanting repair first, the best first, then the base's
	-- squares not dug yet, then the rest; its dugouts with them, kept healthy as its trenches' critical points)
	-- (a player's plan is its side's first trench job, Trenches.Plans: dug under fire, on shelled ground and while its
	-- offensive goes in, from further off; user 2026-11-06: "they are beiong shelled and shot and wont even dig my pre
	-- plan")
	local others, squaresOnly, baseOnly, plansOnly = {}, {}, {}, {}
	local plansWaiting = 0
	local seen = sbs.planSeen or {}
	sbs.planSeen = seen
	for _, w in works do
		local theirs = w.key == "Trench" and w.owner ~= nil and (w.owner :: number) > 0
		if theirs and not w.built and not seen[w.model] then
			seen[w.model] = now
		elseif theirs and w.built and seen[w.model] then
			local times = ByTrench.planTimes[side] or {}
			ByTrench.planTimes[side] = times
			table.insert(times, now - seen[w.model])
			seen[w.model] = nil
		end
	end
	for model in seen do
		if not model.Parent then
			seen[model] = nil
		end
	end
	for i, p in pieces do
		local square = p.key == "Trench"
		local none = { key = p.key, x = p.x, z = p.z, left = 0 }
		local w = works[i]
		local byPlayer = square and not w.built and w.owner ~= nil and (w.owner :: number) > 0
		local new = square and not w.built and not byPlayer and not pushNow and not hotAt(p.x, p.z)
		local line = if new then onLine[w.model] else nil
		local base = line ~= nil and (line.kind == "Support" or line.kind == "Rear")
		others[i] = if square or p.key == "Dugout" then none else p
		squaresOnly[i] = if new and not base then p else none
		baseOnly[i] = if new and base then p else none
		plansOnly[i] = if byPlayer then p else none
		if byPlayer then
			plansWaiting += 1
		end
	end
	care.plansWaiting = plansWaiting
	local near = BotBuild.repairs(others, zone, BD.repair, #pieces)
	-- (near its front zone first, then near each other sector it holds with a trench system: lines left behind as the
	-- front moved on are dug too, a measured match's front moving on left 19 planned squares out of reach)
	local digZones = { zone }
	for _, sys in sbs.systems do
		local sec = Map.sectors[sys.sector]
		if sys.sector ~= front and owner[sys.sector] == side and sec then
			table.insert(digZones, { x = sec.x, z = sec.z, radius = sec.radius })
		end
	end
	local listed: { [number]: boolean } = {}
	local function dig(list: { BotBuild.Piece }, zones: { BotBuild.Zone }?, within: number?)
		for _, z in zones or digZones do
			for _, i in BotBuild.repairs(list, z, within or TR.digReach, TR.digs) do
				if not listed[i] then
					listed[i] = true
					table.insert(near, i)
				end
			end
		end
	end
	local before = #near
	-- (each dug square's decision and the swings it wants to its target: patched to Trenches.standHp, fixed to full,
	-- reinforced past it, Rules/BotTrenchCare.target; extra only while its holders don't stand to)
	local TH = BuildCfg.Trench.hp
	local reach2 = (zone.radius + TR.digReach) ^ 2
	local wanted: { { i: number, score: number, hp: boolean } } = {}
	local swings: { [number]: number } = {}
	local decided: { [number]: string } = {}
	local scoreOf: { [number]: number } = {}
	local reinforcing: { [number]: boolean } = {}
	for i, w in works do
		local inReach = false
		for _, z in digZones do
			inReach = inReach or (w.at.X - z.x) ^ 2 + (w.at.Z - z.z) ^ 2 <= reach2
		end
		if inReach and w.key == "Dugout" and w.built and w.left > 0 then
			table.insert(wanted, { i = i, score = math.huge, hp = true })
			swings[i] = w.left
		elseif inReach and w.key == "Trench" and w.built then
			local sc = careFor(w.at.X, w.at.Z, w.model, onLine[w.model])
			local d, score = BotTrenchCare.decide(sc, SC)
			care[d] = (care[d] or 0) + 1
			local hpT, xT = BotTrenchCare.target(d, score, sc, w.max, TR.standHp, TH.extra, SC)
			local critical = sc.dugout or sc.base
			local lull = critical
				and sc.hot
				and BotTrenchCare.shelledNear(Tactics.dug.heat, w.at.X, w.at.Z, now, CA.Hot.radius, CA.Hot.lull)
			local x = w.extra or 0
			if not lull and w.hp < hpT then
				table.insert(wanted, { i = i, score = score, hp = true })
				local share = (hpT - w.hp) / math.max(w.max - w.hp, 1e-3)
				swings[i] = math.max(math.ceil(w.left * share), 1)
				decided[i] = d
			elseif not lull and not sbs.standTo and w.hp >= w.max and x < xT then
				table.insert(wanted, { i = i, score = score, hp = false })
				swings[i] = BuildRules.workLeft(x, xT, math.max(w.swing, 1e-3))
				reinforcing[i] = true
				decided[i] = d
			end
			scoreOf[i] = score
		end
	end
	table.sort(wanted, function(a, b)
		if a.hp ~= b.hp then
			return a.hp
		end
		return a.score > b.score
	end)
	-- (start, build, reinforce, then keep going: the repairs first, then the squares not dug yet, the extra only once
	-- none of those waits)
	local fixes = 0
	for _, wt in wanted do
		if wt.hp and fixes < SC.repairs then
			fixes += 1
			listed[wt.i] = true
			table.insert(near, wt.i)
		end
	end
	-- (players' plans near its front, the sectors it holds and the enemy's next one first, Trenches.Plans)
	local nextS, nextD = nil, math.huge
	for i, sec in Map.sectors do
		local dx = (sec.x - zone.x) * tx + (sec.z - zone.z) * tz
		if owner[i] ~= side and dx > 0 and dx < nextD then
			nextS, nextD = i, dx
		end
	end
	local newFrom = #near
	dig(plansOnly, digZones, TR.Plans.reach)
	if nextS then
		local sec = Map.sectors[nextS]
		dig(plansOnly, { { x = sec.x, z = sec.z, radius = sec.radius } }, TR.Plans.ahead)
	end
	dig(baseOnly)
	dig(squaresOnly)
	-- (reinforcing doesn't wait for every new square: `Care.Reinforce.share` of the slots left go to it while new
	-- squares wait, all of them once none waits; user 2026-11-06: "a built trench should now always be prioritized to
	-- be reinforced unless for a realistic reason")
	local slots = math.max(TR.digs - fixes, 0)
	local newCount = #near - newFrom
	local strong = {}
	for _, wt in wanted do
		if not wt.hp and not listed[wt.i] then
			table.insert(strong, wt.i)
		end
	end
	local rSlots = if newCount == 0
		then math.min(#strong, SC.repairs, slots)
		else math.min(#strong, math.ceil(slots * CA.Reinforce.share))
	for k = #near, newFrom + math.max(slots - rSlots, 0) + 1, -1 do
		listed[near[k]] = nil
		table.remove(near, k)
	end
	for k = 1, rSlots do
		listed[strong[k]] = true
		table.insert(near, strong[k])
	end
	care.reinforceSlots = rSlots
	for k = #near, before + TR.digs + 1, -1 do
		table.remove(near, k)
	end
	local order, fix = BotCrew.repairOrder(fixable, near, ArtCfg.Man.keep)
	for _, i in order do
		local w = works[i]
		local square = w.key == "Trench"
		if
			not claimed[w.model]
			and (fix[i] or (if square then nd < TR.digs else n < BD.repairs))
			and quiet(w.model)
		then
			if square then
				nd += 1
			elseif not fix[i] then
				n += 1
			end
			local r = sbs.works[w.model]
			if not r then
				local job = { key = w.key, x = w.at.X, z = w.at.Z, fx = tx, fz = tz, work = true }
				r = { job = job, base = job, model = w.model, tries = 0, waitUntil = 0, left = 0, open = true }
			end
			local rr = r :: BuildJob
			rr.at, rr.left, rr.open, rr.fix = w.at, swings[i] or w.left, true, fix[i] == true
			rr.buried = square and w.built and w.hp < w.max
			rr.plan = square and not w.built and w.owner ~= nil and (w.owner :: number) > 0
			rr.reinforce = reinforcing[i] == true -- (a plain dig job at a full square swings no more: Act.doBuild)
			rr.decision = decided[i]
			rr.care = if decided[i] then scoreOf[i] else nil
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
	sbs.steps, sbs.reserve, sbs.squares = {}, {}, {}
	local bays: { [number]: boolean } = {}
	local support: { { x: number, z: number, share: number, len: number, w: Build.Work, heat: number? } } = {}
	local fireSquares: { { x: number, z: number, share: number, len: number, w: Build.Work, heat: number? } } = {}
	for _, w in works do
		if w.key == "Trench" and w.built and w.hp >= TR.standHp then
			table.insert(sbs.squares, { x = w.at.X, z = w.at.Z, at = w.at })
			for k, run in runs do
				local d, t = BotTrenches.offRun(w.at.X, w.at.Z, run.ax, run.az, run.bx, run.bz)
				if d <= TR.on + 1 and t >= -0.05 and t <= 1.05 then
					if run.kind == "Fire" then
						local step = stepOf(w, tx, tz)
						if step then
							local a, e =
								w.model:GetAttribute("BlockA") :: Vector3, w.model:GetAttribute("BlockB") :: Vector3
							table.insert(sbs.steps, step)
							bays[k] = true
							table.insert(fireSquares, {
								x = w.at.X,
								z = w.at.Z,
								share = w.hp / math.max(w.max, 1),
								len = flat(e - a).Magnitude,
								w = w,
							})
						end
					elseif run.kind == "Support" then
						table.insert(sbs.reserve, { pos = w.at })
						local a, e = w.model:GetAttribute("BlockA"), w.model:GetAttribute("BlockB")
						local len = if typeof(a) == "Vector3" and typeof(e) == "Vector3"
							then flat(e - a).Magnitude
							else 0
						table.insert(
							support,
							{ x = w.at.X, z = w.at.Z, share = w.hp / math.max(w.max, 1), len = len, w = w }
						)
					end
					break
				end
			end
		end
	end
	-- the enemy's trench squares dug in its front zone, taken over rather than left (Config/Bots.Trenches.takeOver; user
	-- 2026-11-04: "bots just destroy incoming trenches"): a fire step on each, facing the enemy's way from here (the
	-- parapet turned), its holders' posts as their own
	for _, w in Clear.every do
		if
			w.key == "Trench"
			and w.team ~= kit
			and w.built
			and w.hp >= TR.standHp
			and flat(w.at - Vector3.new(zone.x, w.at.Y, zone.z)).Magnitude <= zone.radius + TR.takeOver
		then
			local step = stepOf(w, tx, tz)
			if step then
				table.insert(sbs.steps, step)
				table.insert(sbs.squares, { x = w.at.X, z = w.at.Z, at = w.at })
				stats.taken += 1
			end
		end
	end
	-- dugouts (Config/Bots.Dugouts): shelled now and once at this front; the rooms that shelter; once shelled, room for
	-- its holders but one sentry a fire bay, dug in the support line's rear wall, or a hot fire-trench square's
	local DG = Cfg.Dugouts
	sbs.bays = 0
	for _ in bays do
		sbs.bays += 1
	end
	sbs.shelled = BotTrenches.shelled(now, ByTrench.blasts, sbs.squares, DG)
	-- how hot its trenches are (Dugouts.Heat): the enemies its squads know of now; each support square's heat over the
	-- side's memory (where dugouts go first); a square that hot once wants dugouts as a shelling does
	local HT = DG.Heat
	sbs.enemies = {}
	for _, sq in squads do
		if sq.side == side then
			for _, kn in sq.known do
				if now - kn.at <= SQ.knownFor then
					table.insert(sbs.enemies, { x = kn.pos.X, z = kn.pos.Z })
				end
			end
		end
	end
	-- (fire-trench squares get dugouts too, the hot ones first: "especially in trenches highly contested or often shelled")
	local sites = table.clone(support)
	for _, list in { support, fireSquares } do
		for _, sq in list do
			sq.heat = BotTrenches.heat(now, sq.x, sq.z, side, Tactics.dug.heat, sbs.enemies, HT, HT.memory)
			if (sq.heat :: number) >= HT.build then
				sbs.shelledOnce = true
			end
			-- (a fire-trench square takes one in its rear wall too, hot or not: a 32-stud support line holds one
			-- dugout at Dugouts.spacing, the rest of Dugouts.perBays went undug, a Lantern Meadows match 2026-11-06)
			if list == fireSquares then
				table.insert(sites, sq)
			end
		end
	end
	sbs.shelledOnce = sbs.shelledOnce or sbs.shelled
	sbs.rooms = {}
	local have: { { x: number, z: number } } = {}
	for _, w in works do
		local room = roomOf[w.model]
		if room then
			table.insert(have, { x = w.at.X, z = w.at.Z })
			if w.built and w.hp > 0 then
				table.insert(sbs.rooms, { x = room.X, z = room.Z, room = room, foot = w.at, model = w.model })
			end
		end
	end
	for _, r in sbs.lay do
		if r.job.key == "Dugout" and not r.model then
			table.insert(have, { x = r.job.x, z = r.job.z })
		end
	end
	local holders = 0
	for _, b in bots do
		if b.side == side and (b.postKind == "step" or b.postKind == "reserve" or b.postKind == "dugout") then
			holders += 1
		end
	end
	local want = BotTrenches.dugoutsWanted(sbs.shelledOnce, holders, sbs.bays, DG) - #have
	-- (a square long enough on the flat for one: its doorway and its spare less the slack, Config/Build)
	local long = BuildCfg.Dugout.door + BuildCfg.Dugout.spare - BuildCfg.Dugout.lengthSlack
	-- (squares a dugout can't go in are left out: no ground round its room, Build.dugoutFor; read again after a while)
	local open = {}
	for _, site in sites do
		local no = noDugout[site.w.model]
		if not (no and now < no) then
			table.insert(open, site)
		end
	end
	-- (a dugout in a square's rear wall (away from the enemy), facing out of it into the trench; false where the ground
	-- refuses one, Build.dugoutFor)
	local function dugoutIn(model: Model, at: Vector3): boolean
		local a, c = model:GetAttribute("BlockA"), model:GetAttribute("BlockB")
		if typeof(a) ~= "Vector3" or typeof(c) ~= "Vector3" then
			return false
		end
		local along = flat(c - a)
		local out = if along.Magnitude > 1e-3 then along.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
		if out.X * tx + out.Z * tz > 0 then
			out = -out
		end
		local p = at + out * (BuildCfg.Trench.floor + 0.5)
		if Build.dugoutFor(p) then
			noDugout[model] = now + DG.recheck
			stats.dugoutsRefused += 1
			return false
		end
		local job = { key = "Dugout", x = p.X, z = p.Z, fx = -out.X, fz = -out.Z }
		table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
		table.insert(have, { x = p.X, z = p.Z })
		stats.dugouts += 1
		return true
	end
	for _, i in BotTrenches.dugoutSquares(open, have, want, DG, long) do
		local w = open[i].w
		dugoutIn(w.model, w.at)
	end
	-- one dugout in every system it holds, shelled or not (user 2026-11-05: "dugouts should be utilized as safety and
	-- should be kept healthy as critical points of trenches"; the forward lines' gate, Care.Gate): a sector's in its
	-- support line nearest the middle, a forward line's in its fire trench nearest the middle, once dug there
	for _, sys in sbs.systems do
		if owner[sys.sector] == side then
			local all, base = squaresOf(sys, squares)
			local forward = #base == 0
			local mid = if forward then sys.mid else baseAt
			local best, bestD, inIt = nil, math.huge, false
			for _, sq in all do
				for _, h in have do
					inIt = inIt or (h.x - sq.x) ^ 2 + (h.z - sq.z) ^ 2 <= (2 * CA.Gate.dugout) ^ 2
				end
				local line = onLine[sq.model]
				local kind = if line then line.kind else ""
				local no = noDugout[sq.model]
				if
					sq.built
					and sq.hp >= TR.standHp
					and kind == (if forward then "Fire" else "Support")
					and not (no and now < no)
				then
					local d = (sq.x - mid.x) ^ 2 + (sq.z - mid.z) ^ 2
					if d < bestD then
						best, bestD = sq, d
					end
				end
			end
			if best and not inIt then
				dugoutIn(best.model, best.at)
			end
		end
	end
	sbs.digging = 0
	for _, r in sbs.lay do
		if r.job.key == "Dugout" and (not r.model or r.left > 0) then
			sbs.digging += 1
		end
	end
	-- the support line stands to with an enemy known near the fire trench; the fire trench is lost with enemies known
	-- in it or past it and too few of its holders standing
	local nearest, enemiesIn = math.huge, 0
	local edgeX, edgeZ = zone.x + tx * zone.radius * TR.Fire.edge, zone.z + tz * zone.radius * TR.Fire.edge
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
					local past = (kn.pos.X - edgeX) * tx + (kn.pos.Z - edgeZ) * tz < 0
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

-- Normal: the enemy MG nests and guns `side` knows of (Config/Bots.Offensive.strong): manned, on ground the enemy
-- holds, with an enemy its squads knew of (`known`) close by; forgotten after `strong.forget` s or once left or wrecked
local function knowStrong(side: string, owner: { string }, known: { Vector3 }, now: number)
	local mine = fronts.strong[side] or {}
	fronts.strong[side] = mine
	local manned: { [Model]: boolean } = {}
	for _, g in Artillery.list() do
		local i = BotCrew.sectorAt(g.crew.X, g.crew.Z, Map.sectors)
		if not g.free and not g.broken and i and owner[i] ~= side and owner[i] ~= "Neutral" then
			manned[g.model] = true
			for _, p in known do
				if flat(p - g.crew).Magnitude <= OF.strong.seen then
					mine[g.model] = { at = g.crew, seen = now, mg = g.mg }
					break
				end
			end
		end
	end
	for model, sp in mine do
		if not manned[model] or model.Parent == nil or now - sp.seen > OF.strong.forget then
			mine[model] = nil
		end
	end
end

-- Normal: what `side`'s guns shell before any group (Crew.command `first`; Config/Bots.Offensive): while its
-- offensive gathers or shells, the known strongpoints within `strong.within` of the target (nearest it first); under
-- the barrage then spots in the target's zone, then about half the enemy's dug squares there
local function shellFirst(side: string, off: Orders.Offensive?): { Vector3 }?
	if not off or not Orders.waiting(off) then
		-- (a known MG is shelled at any time: Config/Bots.Crew.Arcs)
		local mgs: { Vector3 } = {}
		for _, sp in if Cfg.Crew.Arcs.on then fronts.strong[side] or {} else {} do
			if sp.mg then
				table.insert(mgs, sp.at)
			end
		end
		return if #mgs > 0 then mgs else nil
	end
	local tc = sectorPoint(off.sector)
	local list: { Vector3 } = {}
	for _, sp in fronts.strong[side] or {} do
		if flat(sp.at - tc).Magnitude <= OF.strong.within then
			table.insert(list, sp.at)
		end
	end
	table.sort(list, function(a, b)
		return flat(a - tc).Magnitude < flat(b - tc).Magnitude
	end)
	if off.phase == "Barrage" then
		for _ = 1, OF.barragePoints do
			local a = random:NextNumber() * 2 * math.pi
			local r = OF.barrageSpread * math.sqrt(random:NextNumber())
			table.insert(list, Routes.ground(tc.X + math.cos(a) * r, tc.Z + math.sin(a) * r))
		end
		local zone = Map.sectors[off.sector]
		local foe = buildLists[if side == "West" then "East" else "West"]
		for _, sq in (if foe then foe.squares else {}) :: { any } do
			if math.sqrt((sq.x - zone.x) ^ 2 + (sq.z - zone.z) ^ 2) <= zone.radius and random:NextNumber() < 0.5 then
				table.insert(list, Routes.ground(sq.x, sq.z))
			end
		end
	end
	return list
end

-- Normal: where `side`'s MGs fire with no enemy known (Config/Bots.Crew.MG): some of the enemy's dug squares and points on
-- the way between its front `front` and the enemy's sector `shell`, in three lanes, looked up every `likelyEvery` s
local function mgLikely(side: string, front: number?, shell: number?, foe: any, now: number): { Vector3 }
	local M = Cfg.Crew.MG
	local c = fronts.mgLikely[side]
	if c and now - c.at < M.likelyEvery then
		return c.list
	end
	local list: { Vector3 } = {}
	local up = Vector3.new(0, M.chest, 0)
	local squares = if foe then foe.squares else {}
	for i = 1, #squares, math.max(1, math.ceil(#squares / M.likelySquares)) do
		table.insert(list, Routes.ground(squares[i].x, squares[i].z) + up)
	end
	if front and shell and Map.sectors[front] and Map.sectors[shell] then
		local a, e = sectorPoint(front), sectorPoint(shell)
		local across = Vector3.new(e.Z - a.Z, 0, a.X - e.X)
		across = if across.Magnitude > 1 then across.Unit else Vector3.xAxis
		for _, t in M.along do
			for _, lane in { -M.lanes, 0, M.lanes } do
				local p = a + (e - a) * t + across * lane
				table.insert(list, Routes.ground(p.X, p.Z) + up)
			end
		end
	end
	fronts.mgLikely[side] = { at = now, list = list }
	return list
end

-- Normal: `side`'s known enemy MG arcs forgotten once stale or gone, and its soldiers who walked into one counted (the
-- Bots' MGs readout; Config/Bots.Crew.Arcs)
local function arcTick(side: string, now: number)
	local A = Cfg.Crew.Arcs
	local arcs = fronts.arcs[side]
	if not arcs then
		return
	end
	for gun, arc in arcs do
		if gun.Parent == nil or now - arc.at > A.forget then
			arcs[gun] = nil
		end
	end
	for _, b in bots do
		if b.side == side and alive(b) and b.root and not b.gun then
			local p = (b.root :: BasePart).Position
			local inOne = false
			for _, arc in arcs do
				if now - arc.first >= A.knownFor and BotArcs.inside(arc, p.X, p.Z, A) then
					inOne = true
					break
				end
			end
			if inOne and not b.inArc and b.nav.goal then
				local t = fronts.mg[side]
				if t then
					t.walked += 1
				end
			end
			b.inArc = inOne
		end
	end
end

-- Normal: the initiative and each side's offensive, one commander tick (Rules/BotOrders.initiative, offensive;
-- Config/Bots.Offensive): who took a sector, the holder's offensive stepped (its lives in and lost since Go counted),
-- the initiative passed on a capture or a spent offensive, and the holder's offensive (re)started on its target
local lives: { [string]: { [any]: any } } = {}
local function initiativeTick(owner: { string }, counts: { { West: number, East: number } }, state: any, now: number)
	-- (the longest with no squad attacking, with the initiative and from Go: the Bots' attacks readout)
	for _, sd in { "West", "East" } do
		local A = fronts.attacks[sd]
		if not A then
			A = {
				goes = 0,
				toGo = 0,
				fill = 0,
				gatherDist = 0,
				gatherN = 0,
				waves = 0,
				sent = 0,
				maxQuiet = 0,
				goQuiet = 0,
				blastMost = 0,
				blast3 = 0,
				lostGather = 0,
			}
			fronts.attacks[sd] = A
		end
		local a = A :: any
		local fs0 = fronts.sides[sd]
		local o0 = if fs0 and fronts.initiative == sd then fs0.off else nil
		local quiet = o0 ~= nil and (fs0.assaulting or 0) <= 0
		a.quietAt = if quiet then a.quietAt or now else nil
		a.goQuietAt = if quiet and Orders.going(o0) then a.goQuietAt or now else nil
		a.maxQuiet = math.max(a.maxQuiet, if a.quietAt then now - a.quietAt else 0)
		a.goQuiet = math.max(a.goQuiet, if a.goQuietAt then now - a.goQuietAt else 0)
	end
	local was = fronts.owners
	local by = Orders.capturedBy(was, owner)
	if was then
		for i, o in was :: { string } do
			if (o == "West" or o == "East") and owner[i] ~= o then
				local l = fronts.lostAt[o] or {}
				fronts.lostAt[o] = l
				l[i] = now
				local fsL = fronts.sides[o]
				local tl = fronts.attacks[o]
				if tl and fsL and fsL.off and (fsL.off :: Orders.Offensive).phase == "Gather" then
					tl.lostGather += 1
				end
			end
		end
	end
	local holder = fronts.initiative
	local spent = false
	local hs = if holder then fronts.sides[holder] else nil
	local off = if hs then hs.off else nil
	if holder and hs and off then
		if Orders.going(off) then
			local seen = lives[holder] or {}
			lives[holder] = seen
			for _, b in bots do
				if b.side == holder and b.order == "Attack" then
					if alive(b) and not b.deadAt and seen[b.id] ~= true then
						seen[b.id] = true
						off.went += 1
					elseif b.deadAt and seen[b.id] == true then
						seen[b.id] = b.deadAt
						off.lost += 1
					end
				end
			end
		end
		local enemy = if holder == "West" then "East" else "West"
		local c = counts[off.sector] or { West = 0, East = 0 }
		local was1 = off.phase
		spent = Orders.offensive(off, {
			now = now,
			ready = if (hs.attackers or 0) > 0 then (hs.gathered or 0) / (hs.attackers :: number) else 0,
			ours = (c :: any)[holder],
			theirs = (c :: any)[enemy],
			waveEvery = FrontCfg.Waves.every,
			due = Orders.due(hs.dueDists or {}, OF.ready, OF.pace),
		}, OF)
		if off.phase == "Go" and was1 ~= "Go" and was1 ~= "Exploit" then
			fronts.tally[`go{holder}`] = (fronts.tally[`go{holder}`] or 0) + 1
			local A = fronts.attacks[holder]
			local tz = Map.sectors[off.sector]
			A.goes += 1
			A.toGo += now - off.began
			A.fill += if (hs.attackers or 0) > 0 then (hs.gathered or 0) / (hs.attackers :: number) else 0
			for _, o in squads do
				local at = o.jump or (if o.gatherOf == off.began then o.gather else nil) or o.approach
				if o.side == holder and o.sector == off.sector and at and o.seen >= commandTick - 1 then
					A.gatherDist += math.max(
						flat((at :: Vector3) - Vector3.new(tz.x, 0, tz.z)).Magnitude - tz.radius,
						0
					)
					A.gatherN += 1
				end
			end
		end
		if spent then
			fronts.tally[`spent{holder}`] = (fronts.tally[`spent{holder}`] or 0) + 1
		end
	end
	if by and holder == by then
		fronts.tally[`took{by}`] = (fronts.tally[`took{by}`] or 0) + 1
	end
	if by and was then
		-- (the sector it took: its holders dig in there, Config/Bots.Offensive.dig)
		for i, o in owner do
			if o == by and (was :: { string })[i] ~= by then
				fronts.took[by] = { sector = i, at = now }
			end
		end
	end
	local now1 = Orders.initiative(holder, by, spent)
	if now1 ~= holder then
		for _, side in { "West", "East" } do
			local fs = fronts.sides[side]
			if fs then
				fs.off = nil
			end
		end
		fronts.initiative = now1
	end
	if now1 then
		local fs = fronts.sides[now1]
		local target = FrontRules.target(state, now1)
		if fs and target and (not fs.off or (fs.off :: Orders.Offensive).sector ~= target) then
			local lost = (fronts.lostAt[now1] or {})[target]
			fs.off = Orders.newOffensive(target, now, lost ~= nil and now - lost <= OF.counterWithin)
			lives[now1] = {}
			fronts.tally[`began{now1}`] = (fronts.tally[`began{now1}`] or 0) + 1
		elseif fs and not target then
			fs.off = nil
		end
	end
	-- (the readouts: each side's line, and the [Bots] line's summary)
	for _, side in { "West", "East" } do
		local fs = fronts.sides[side]
		if fs then
			local o = fs.off
			if not now1 then
				fs.note = "race for the first capture"
			elseif o then
				local t = math.floor(now - o.since)
				local extra = if o.phase == "Gather"
					then `, {math.floor(100 * (fs.gathered or 0) / math.max(fs.attackers or 0, 1))}% at the jump-off`
					elseif Orders.going(o) then `, {o.lost} lost of {o.went} in`
					else ""
				local counter = if o.counter then " (counter)" else ""
				fs.note = `offensive on S{o.sector}{counter}: {string.lower(o.phase)} {t} s{extra}`
			else
				fs.note = `holding: {now1} has the initiative`
			end
		end
	end
	local T = fronts.tally
	fronts.summary = string.format(
		"initiative %s; offensives W %d begun, %d went, %d spent, %d took; E %d begun, %d went, %d spent, %d took; %d assault squads restarted",
		now1 or "none (race)",
		T.beganWest or 0,
		T.goWest or 0,
		T.spentWest or 0,
		T.tookWest or 0,
		T.beganEast or 0,
		T.goEast or 0,
		T.spentEast or 0,
		T.tookEast or 0,
		T.restarts or 0
	)
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
		-- (by head: Config/Frontline.HeadsSuffix; the "West" / "East" weights count a bot as half for the capture)
		local w = sf and sf:GetAttribute("West" .. FrontCfg.HeadsSuffix)
		local e = sf and sf:GetAttribute("East" .. FrontCfg.HeadsSuffix)
		counts[i] = { West = if type(w) == "number" then w else 0, East = if type(e) == "number" then e else 0 }
	end
	local state = { owner = owner, control = control }
	ByTrench.counts = counts
	-- (a new match: no initiative yet, the race for the middle)
	if not fronts.owners then
		fronts.initiative = nil
		table.clear(fronts.lostAt)
		table.clear(fronts.strong)
		table.clear(fronts.tally)
		table.clear(fronts.took)
		table.clear(fronts.attacks)
		table.clear(fronts.arcs)
		table.clear(fronts.mg)
		table.clear(fronts.mgLikely)
		table.clear(lives)
	end
	-- (a capture is contact for both sides; each side's plan: Rules/BotFront)
	local captured = BotFront.captured(fronts.owners, owner)
	for _, side in { "West", "East" } do
		local fs = fronts.sides[side] or { plan = "open" }
		fronts.sides[side] = fs
		if captured and not fs.contactAt then
			fs.contactAt = os.clock()
			stats.contacts += 1
		end
	end
	initiativeTick(owner, counts, state, os.clock())
	fronts.owners = owner
	for _, side in { "West", "East" } do
		local fs = fronts.sides[side]
		fs.plan = BotFront.plan(fs.contactAt, fs.forced, Orders.going(fs.off))
	end
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
		-- (the initiative: the side with it holds its front lighter; the other defends, but for a screen)
		local lead = fronts.initiative == side
		local plan = Orders.plan(
			side,
			owner,
			control,
			counts,
			target,
			NV.defendShare,
			front,
			if lead then OF.hold else TR.hold,
			if LN.on then LN.danger else nil
		)
		if fronts.initiative and not lead then
			plan = Orders.holdBack(plan, front, OF, SQ.size)
		end
		local given = Orders.assign(ids, current, Orders.defendersFor(plan, #ids))
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
		-- its gunners (src/server/Bots/Crew): at the enemies its squads know, else the sector it attacks (or the
		-- enemy's next to its front)
		local known = {}
		for _, sq in squads do
			if sq.side == side then
				for _, kn in sq.known do
					if os.clock() - kn.at <= SQ.knownFor then
						table.insert(known, kn.pos)
					end
				end
			end
		end
		local shell = plan.attack or (front and front + (if side == "West" then 1 else -1))
		local foe = buildLists[if side == "West" then "East" else "West"]
		-- (its offensive: known MG nests and guns first, then its barrage on the zone: Config/Bots.Offensive)
		knowStrong(side, owner, known, os.clock())
		local fsd = fronts.sides[side]
		local first = shellFirst(side, fsd and fsd.off)
		local barrage = first ~= nil
			and fsd ~= nil
			and fsd.off ~= nil
			and (fsd.off :: Orders.Offensive).phase == "Barrage"
		Tactics.crew.command(
			side,
			owner,
			known,
			if shell and Map.sectors[shell] then sectorPoint(shell) else nil,
			if foe and not barrage then foe.squares else {},
			first,
			mgLikely(side, front, shell, foe, os.clock())
		)
		arcTick(side, os.clock())
		formSquads(side, counts)
		-- (which guns on its ground can still reach the enemy: those that can't aren't fixed first, Crew.useful)
		local reachAt = if shell and Map.sectors[shell] then sectorPoint(shell) else nil
		local fightX, fightZ = 0, 0
		if front then
			fightX, fightZ = BotBuild.fightPoint(Map.sectors, front, side, Cfg.Crew.MG.fightAt)
		end
		Tactics.crew.useful(side, owner, if front then reachAt else nil, function(g, k, a, t, arc)
			return Guns.flyShot(g, k, a, t, arc, true)
		end, function(at)
			return BotCrew.inReach(at.X, at.Z, { { x = fightX, z = fightZ } }, 0, Cfg.Crew.MG.reach)
		end)
		buildList(side, owner, FrontRules.held(state, side))
		Tactics.fell.list(side, buildLists[side])
		pioneers(side) -- (after the trees in its lines' way are on the list)
		-- the enemy's guns on its ground: used, wrecked or let be (src/server/Bots/Crew)
		local aimAt = if shell and Map.sectors[shell] then sectorPoint(shell) else nil
		-- (safe: no enemy its squads know of close, not out past its sector's middle toward the enemy)
		local enemies = {}
		for _, p in known do
			table.insert(enemies, { x = p.X, z = p.Z })
		end
		Tactics.crew.judge(side, owner, aimAt, function(g, k, a, t, arc)
			return Guns.flyShot(g, k, a, t, arc, true)
		end, function(at)
			local i = BotCrew.sectorAt(at.X, at.Z, Map.sectors)
			if not i then
				return false
			end
			local sec = Map.sectors[i]
			local ex, ez = BotBuild.toward(Map.sectors, i, side)
			return BotCrew.safeSpot(at.X, at.Z, sec.x, sec.z, ex, ez, enemies, Cfg.Crew.captured.safe)
		end)
		Tactics.crew.wrecks(side, buildLists[side])
		Tactics.crew.fixes(side, buildLists[side])
	end
	markTrenches()
	label()
	-- squads no longer formed go
	for key, sq in squads do
		if sq.seen ~= commandTick then
			squads[key] = nil
		end
	end
	debug.profileend()
end

return {
	commandTick = commandTick,
	standPoint = standPoint,
	holdSpot = holdSpot,
	indoorHold = indoorHold,
	trenchPost = trenchPost,
	sapTick = sapTick,
	formSquads = formSquads,
	Guns = Guns,
	buildList = buildList,
	command = command,
	markTrenches = markTrenches,
}
