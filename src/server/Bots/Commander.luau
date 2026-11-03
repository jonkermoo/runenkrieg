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
local ArtCfg = require(Shared.Config.Artillery)
local ArtRules = require(Shared.Rules.Artillery)
local FrontRules = require(Shared.Rules.Frontline)
local Orders = require(Shared.Rules.BotOrders)
local Buildings = require(Shared.Rules.BotBuildings)
local BotBuild = require(Shared.Rules.BotBuild)
local BotTrenches = require(Shared.Rules.BotTrenches)
local BotSap = require(Shared.Rules.BotSap)
local Survey = require(Shared.BuildSurvey)
local BotCrew = require(Shared.Rules.BotCrew)
local BotFront = require(Shared.Rules.BotFront)
local Build = require(script.Parent.Parent.Build)
local Frontline = require(script.Parent.Parent.Frontline)
local Indoors = require(script.Parent.Parent.Indoors)
local Routes = require(script.Parent.Routes)
local Squads = require(Shared.Rules.BotSquads)

local NV = Cfg.Normal
local SQ = Cfg.Squads
local RT = Cfg.Routes
local brainCfg = Cfg.Brain :: any
local IN = Cfg.Indoors
local BD = Cfg.Build
local TR = Cfg.Trenches
local TM = Cfg.TrenchMove
local SP = Cfg.Sap
local CV = Cfg.Move.Cover
local FR = Cfg.Front
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
	local tx, tz = BotBuild.toward(Map.sectors, i, side) -- (the enemy's way, from the live map's sector chain)
	local k = Buildings.pickHold(list, c.X, c.Z, within, tx, tz, rolls, IN)
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

local function sapTick(
	sqs: SquadState,
	members: { Bot },
	mid: Vector3,
	goalAt: Vector3,
	radius: number,
	now: number,
	plan: string
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
		if phase ~= "Move" and phase ~= "Bound" or not sb then
			sqs.markAt, sqs.markDist = now, d
			return
		end
		if not sqs.markAt or d < (sqs.markDist :: number) - SP.progress then
			sqs.markAt, sqs.markDist = now, d
		end
		local since, gained = now - (sqs.markAt :: number), (sqs.markDist :: number) - d
		-- (stuck under fire; fighting by trench, also once near the objective: Rules/BotFront.sapNow)
		local stalled = BotSap.stalled(since, gained, underFire, lost, SP)
		if d <= radius * SP.edge or not BotFront.sapNow(plan, stalled, d - radius, FR) then
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
		sqs.sap = { k = 0, head = head, goal = goalAt, open = {}, digs = {} }
		stats.saps += 1
	end
	local sap = sqs.sap :: Sap
	sap.goal = goalAt
	-- (fighting by trench it runs on through quiet spells, until its parallel is dug: Config/Bots.Front)
	local headTo = flat(sap.head - goalAt).Magnitude
	local over = if plan == "open"
		then BotSap.over(headTo, radius * SP.edge, now - (sqs.firedAt or now), SP.quiet)
		else (sap.parallel == true and not sap.run) or headTo <= radius * SP.edge or plan == "assault"
	if over or not sb or (sap.run and (sap.run :: BuildJob).gaveUp) then
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
				sap.head = Vector3.new(j.ex :: number, sap.head.Y, j.ez :: number)
				sap.run = nil
				stats.sapRuns += 1
			end
		else
			r.open = now >= r.waitUntil
			if r.open then
				table.insert(open, r)
			end
		end
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
		if b.side == side and (b.postFace or b.postKind == "reserve") and b.post then
			-- (windows, fire steps and support-line places held already)
			taken[b.post :: Vector3] = (taken[b.post :: Vector3] or 0) + 1
		end
	end
	local sb = buildLists[side]
	local enemyLines = buildLists[enemy]
	-- under shelling (Config/Bots.Dugouts): the places left in each dugout, the sentries kept up so far
	local free: { { x: number, z: number, free: number } } = {}
	local up = 0
	for _, rm in (if sb then sb.rooms else {}) do
		local n = Cfg.Dugouts.room
		for _, o in bots do
			if o.side == side and o.postKind == "dugout" and o.post == rm.room then
				n -= 1
			end
		end
		table.insert(free, { x = rm.x, z = rm.z, free = n })
	end
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
				-- (attacking: a share up the flanks, Rules/BotFront.flank)
				local flank: number? = nil
				if not defend then
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
			if front.plan == "assault" and not defend then
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
						if sqs.flank and home.Magnitude > 1 then
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
				local i = BotTrenches.jumpOff(dug, mid.X, mid.Z, c.X, c.Z, s.radius, TM.Jump)
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
			}, SQ)
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
			if not defend and sqs.sq.phase ~= "Assault" and lead then
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
			-- attacking: over the top together from its side's front trench (Rules/BotTrenches.jumpOff, overTop)
			if defend or sqs.sq.phase == "Assault" or not sb then
				sqs.jump, sqs.jumpAlong, sqs.jumpAt = nil, nil, nil
			end
			local route = sqs.push or sqs.jump or sqs.mid or sqs.approach or c
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
						-- shelled: one sentry a fire bay stays up, the rest down into a dugout with a place, until it
						-- stops or they stand to
						if want and not fallback and not s2.standTo and s2.shelled then
							if want == "step" and up < s2.bays then
								up += 1
							elseif
								b.postKind == "dugout"
								and b.postSector == sector
								and Tactics.dug.standing(s2, b.post)
							then
								want = "dugout"
							else
								local i = BotTrenches.seat(free, p.X, p.Z)
								if i then
									free[i].free -= 1
									want = "dugout"
									local room = s2.rooms[i].room
									b.post, b.postFace, b.postKind, b.postFloor = room, nil, "dugout", room
									b.postFoot = s2.rooms[i].foot
									b.postSector = sector
									stats.sheltered += 1
								end
							end
						end
					end
					local again = not b.post or b.postSector ~= sector or b.roleWas ~= "Hold"
					if b.postKind == "dugout" and want ~= "dugout" then
						-- (up to its post again: shelling over, standing to, or the dugout gone)
						stats.cameUp += 1
						again = true
					end
					local tp = if want
							and want ~= "dugout"
							and (again or b.postKind ~= want)
						then trenchPost(sb :: SideBuild, want :: string, taken, p)
						else nil
					if tp then
						b.post, b.postFace, b.postKind = tp.pos, tp.face, want
						b.postFloor = tp.floor
						b.postSector = sector
					elseif again and want ~= "dugout" then
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
					-- (in the jump-off trench: spread along it)
					local across = if sqs.jump and sqs.jumpAlong then sqs.jumpAlong :: Vector3 else right
					local slot = route + across * ((idx - (#members + 1) / 2) * SQ.spread)
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
			-- stuck under fire on the way: a sap forward (Rules/BotSap); a defending squad never saps
			if defend then
				sqs.sap = nil
			else
				sapTick(sqs, members, mid, c, s.radius, now, front.plan)
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
-- false when out of reach, or a hill, house or tree stops it short. Each one checked is kept for Admin.GunArcs.
function Guns.clearShot(gun: any, at: Vector3, target: Vector3): boolean
	local A = BD.Crews.arc
	-- (from its muzzle over the ground as it is now: a howitzer's pit is dug round it later)
	local frame = CFrame.lookAt(at, Vector3.new(target.X, at.Y, target.Z))
	local mx, my, mz = ArtRules.muzzle(gun, 0, 0)
	local origin = frame:PointToWorldSpace(Vector3.new(mx, my, mz))
	local off = target - origin
	local d = Vector3.new(off.X, 0, off.Z).Magnitude
	local e = if d <= ArtRules.reachCap(ArtRules.sectorSpan(Map.sectors), ArtCfg.Reach)
		then ArtRules.layFor(gun, d, off.Y)
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
	table.insert(Guns.drawn, { points = drawn, clear = clear })
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
	return BotBuild.gunSpots(zone, tx, tz, want, C, Guns.spacing, function(key, x, z)
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
		-- (ground it can be laid on, facing the target: no steeper than its `maxSlope`, the same survey as
		-- Build.placeAs's, which then levels or tilts it, Config/Build.Slope)
		local piece = Guns.piece[key]
		if piece then
			local report = Survey.ground(piece, Survey.box(piece, Survey.frame(at, target - at)))
			if not report.ground or report.water or report.slope > (piece.maxSlope or 90) then
				return no(key, if report.water then "water" else "too steep")
			end
		end
		-- (its shot flown: within its reach on this map, Config/Artillery.Reach, and nothing in the way)
		return Guns.clearShot(gun, at, target) or no(key, "shot blocked or out of reach")
	end)
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
			shelled = false,
			shelledOnce = false,
			bays = 0,
			digging = 0,
			hurt = {},
			runNotes = {},
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
		return
	end
	local s = Map.sectors[front :: number]
	local zone = { x = s.x, z = s.z, radius = s.radius }
	local tx, tz = BotBuild.toward(Map.sectors, front :: number, side) -- (the enemy's way, from the live map's chain)
	local spots = Routes.spots(front :: number, side, true)
	if front ~= sbs.front or fromEnd ~= sbs.held or (not sbs.holds and spots ~= nil) then
		local holds = {}
		for _, sp in spots or {} do
			table.insert(holds, { x = sp.pos.X, z = sp.pos.Z, hidden = sp.hidden })
		end
		local guns = {}
		for _, key in Guns.list do
			if FrontRules.gunLocked(FrontCfg.Artillery, key, fromEnd) == nil then
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
			local locked = FrontRules.gunLocked(FrontCfg.Artillery, key, fromEnd)
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
		-- (MG nests: those missing of Build.Nest.count, its side's standing ones at the front counted)
		local nests = 0
		for _, w in Build.worksOf(kit) do
			if
				w.key == "MGNest"
				and w.built
				and flat(w.at - Vector3.new(zone.x, w.at.Y, zone.z)).Magnitude <= zone.radius + BD.repair
			then
				nests += 1
			end
		end
		local missing = math.max(BD.Nest.count - nests, 0)
		for _, job in BotBuild.plan(zone, tx, tz, holds, if #spotted > 0 then unplaced else guns, Flanked.plan, missing) do
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
		for _, run in BotTrenches.layout(zone, tx, tz, TR) do
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
				local r = { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false, run = leg }
				table.insert(sbs.lay, r)
			end
		end
		if front ~= sbs.front then
			sbs.shelledOnce = false
		end
		sbs.front, sbs.held, sbs.holds = front, fromEnd, spots ~= nil
	end
	local works, roomOf = Tactics.dug.works(kit, BD.builder)
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
		if w.owner and (w.owner :: number) < 0 then
			mine += 1
			ofKey[w.key] = (ofKey[w.key] or 0) + 1
		end
	end
	-- (a trench run is matched by its squares, Rules/BotTrenches.laid; the rest by BotBuild.match)
	local jobs = {}
	local runs: { BotTrenches.Run } = {}
	local runLaid: { [number]: boolean } = {}
	local squares: { TrenchSquare } = {}
	local dug = 0
	for _, w in works do
		if w.key == "Trench" then
			dug += 1
			table.insert(
				squares,
				{ x = w.at.X, z = w.at.Z, at = w.at, model = w.model, left = w.left, built = w.built }
			)
		end
	end
	sbs.trench = squares
	if Clear.everyAt ~= commandTick then
		Clear.everyAt, Clear.every = commandTick, Build.worksOf(nil)
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
			-- (a run refused everywhere counts as done: a breastwork stands in for it, the next run goes on)
			runLaid[#runs] = r.gaveUp == true or BotTrenches.laid(run, squares, TR.on, TR.ends) ~= nil
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
		if r.run and r.gaveUp and not r.done and r.run.kind ~= "Comm" then
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
			r.open = not runLaid[ri] and now >= r.waitUntil and dug < TR.cap and BotTrenches.ready(runLaid, ri)
		elseif i then
			local w = works[i]
			r.model, r.at, r.left = w.model, w.at, w.left
			claimed[w.model] = true
			r.open = w.left > 0 and quiet(w.model)
		else
			r.model, r.at, r.left = nil, nil, 0
			local key = r.job.key
			r.open = now >= r.waitUntil and (key == "Trench" or BotBuild.allowed(key, mine, ofKey[key] or 0, BD.caps))
		end
		if r.open then
			table.insert(sbs.open, r)
		end
	end
	for _, job in more do
		table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
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
	local fixable = {}
	for i, w in works do
		local at = BotCrew.sectorAt(w.at.X, w.at.Z, Map.sectors)
		fixable[i] = {
			gun = w.kind == "Gun" or w.kind == "Nest",
			built = w.built,
			held = at ~= nil and owner[at] == side,
			hp = w.hp,
			max = w.max,
		}
	end
	local order, fix = BotCrew.repairOrder(fixable, BotBuild.repairs(pieces, zone, BD.repair, #pieces), ArtCfg.Man.keep)
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
			rr.at, rr.left, rr.open, rr.fix = w.at, w.left, true, fix[i] == true
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
	local support: { { x: number, z: number, share: number, len: number, w: Build.Work } } = {}
	for _, w in works do
		if w.key == "Trench" and w.built and w.hp >= TR.standHp then
			table.insert(sbs.squares, { x = w.at.X, z = w.at.Z, at = w.at })
			for k, run in runs do
				local d, t = BotTrenches.offRun(w.at.X, w.at.Z, run.ax, run.az, run.bx, run.bz)
				if d <= TR.on + 1 and t >= -0.05 and t <= 1.05 then
					if run.kind == "Fire" then
						-- (across its own line, turned with its tilt; its floor riding up as it is buried)
						local m = w.model
						local a, e, tilt = m:GetAttribute("BlockA"), m:GetAttribute("BlockB"), m:GetAttribute("Tilt")
						if typeof(a) == "Vector3" and typeof(e) == "Vector3" then
							local TB, B = BuildCfg.Trench, require(Shared.Rules.Build)
							local lean = if type(tilt) == "number" then tilt else 0
							local sq = { ax = a.X, ay = a.Y, az = a.Z, bx = e.X, by = e.Y, bz = e.Z, tilt = lean }
							local fill = B.trenchSink(B.trenchDepth(w.hp, true, TB.hp), TB)
							local p = BotTrenches.firePost(sq, tx, tz, STEP, TR.rise, TB.depth, fill)
							table.insert(sbs.steps, {
								pos = Vector3.new(p.sx, p.sy, p.sz),
								floor = Vector3.new(p.fx, p.fy, p.fz),
								face = Vector3.new(p.ox, 0, p.oz),
							})
							bays[k] = true
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
	-- dugouts (Config/Bots.Dugouts): shelled now and once at this front; the rooms that shelter; once shelled, room for
	-- its holders but one sentry a fire bay, dug in the support line's rear wall
	local DG = Cfg.Dugouts
	sbs.bays = 0
	for _ in bays do
		sbs.bays += 1
	end
	sbs.shelled = BotTrenches.shelled(now, ByTrench.blasts, sbs.squares, DG)
	sbs.shelledOnce = sbs.shelledOnce or sbs.shelled
	sbs.rooms = {}
	local have: { { x: number, z: number } } = {}
	for _, w in works do
		local room = roomOf[w.model]
		if room then
			table.insert(have, { x = w.at.X, z = w.at.Z })
			if w.built and w.hp > 0 then
				table.insert(sbs.rooms, { x = room.X, z = room.Z, room = room, foot = w.at })
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
	for _, i in BotTrenches.dugoutSquares(support, have, want, DG, long) do
		local w = support[i].w
		local a, c = w.model:GetAttribute("BlockA"), w.model:GetAttribute("BlockB")
		if typeof(a) == "Vector3" and typeof(c) == "Vector3" then
			-- its rear wall (away from the enemy), the dugout facing out of it into the trench
			local along = flat(c - a)
			local out = if along.Magnitude > 1e-3 then along.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
			if out.X * tx + out.Z * tz > 0 then
				out = -out
			end
			local at = w.at + out * (BuildCfg.Trench.floor + 0.5)
			local job = { key = "Dugout", x = at.X, z = at.Z, fx = -out.X, fz = -out.Z }
			table.insert(sbs.lay, { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = false })
			stats.dugouts += 1
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
	-- (a capture is contact for both sides; each side's plan: Rules/BotFront)
	local captured = BotFront.captured(fronts.owners, owner)
	fronts.owners = owner
	for _, side in { "West", "East" } do
		local fs = fronts.sides[side] or { plan = "open" }
		fronts.sides[side] = fs
		if captured and not fs.contactAt then
			fs.contactAt = os.clock()
			stats.contacts += 1
		end
		fs.plan = BotFront.plan(fs.contactAt, fs.forced)
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
		Tactics.crew.command(side, owner, known, if shell and Map.sectors[shell] then sectorPoint(shell) else nil)
		formSquads(side, counts)
		buildList(side, owner, FrontRules.held(state, side))
		Tactics.fell.list(side, buildLists[side])
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
