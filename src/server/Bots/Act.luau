--!strict
-- What a bot does besides moving and shooting, kept out of src/server/Bots: weighing its actions (Rules/BotActions:
-- throws, heals, drags, builds, dugouts), carrying them out, and a Mage's staff.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local DamageCfg = require(Shared.Config.Damage)
local DragCfg = require(Shared.Config.Dragging)
local BuildCfg = require(Shared.Config.Build)
local GrenadeCfg = require(Shared.Config.Grenades)
local HealCfg = require(Shared.Config.Healing)
local W = require(Shared.Config.Weapons)
local SpellsCfg = require(Shared.Config.Spells)
local Map = require(Shared.LiveMap).map -- (the match's map)
local Metrics = require(Shared.Config.Metrics)
local F = require(Shared.Rules.Firing)
local Actions = require(Shared.Rules.BotActions)
local BotBuild = require(Shared.Rules.BotBuild)
local BotStaff = require(Shared.Rules.BotStaff)
local BotTrenches = require(Shared.Rules.BotTrenches)
local Rules = require(Shared.Rules.Bots)
local Artillery = require(script.Parent.Parent.Artillery)
local Build = require(script.Parent.Parent.Build)
local DevDummies = require(script.Parent.Parent.DevDummies)
local Dragging = require(script.Parent.Parent.Dragging)
local Grenades = require(script.Parent.Parent.Grenades)
local Healing = require(script.Parent.Parent.Healing)
local Loadouts = require(script.Parent.Parent.Loadouts)
local Ragdoll = require(script.Parent.Parent.Ragdoll)
local StaffCast = require(script.Parent.Parent.StaffCast)
local Animate = require(script.Parent.Animate)
local Routes = require(script.Parent.Routes)

local M = Metrics.Movement
local MV = Cfg.Move
local SQ = Cfg.Squads
local CV = MV.Cover
local brainCfg = Cfg.Brain :: any
local AC = Cfg.Actions
local IN = Cfg.Indoors
local BD = Cfg.Build
local ST = Cfg.Staff
local PN = BD.Pinned

local Types = require(script.Parent.Types)
type Target = Types.Target
type BuildJob = Types.BuildJob
type Sap = Types.Sap
type Act = Types.Act
type Bot = Types.Bot
type Known = Types.Known
type SquadState = Types.SquadState
type Soldier = Types.Soldier
type Arms = Types.Arms

local State = require(script.Parent.State)
local Clear, bots, Tactics, random, stats, squads, buildLists, Kinds, budget, rescue =
	State.Clear,
	State.bots,
	State.Tactics,
	State.random,
	State.stats,
	State.squads,
	State.buildLists,
	State.Kinds,
	State.budget,
	State.rescue

local Move = require(script.Parent.Move)
local flat, alive, say, hidden, exclusions, rayParams, aimPart, soldiersNow, friendly, knownSpot, findCover, indoorNear, coverStep, shakenNow, inside, setGoal, follow, putAway, face, holdShovel, finish =
	Move.flat,
	Move.alive,
	Move.say,
	Move.hidden,
	Move.exclusions,
	Move.rayParams,
	Move.aimPart,
	Move.soldiersNow,
	Move.friendly,
	Move.knownSpot,
	Move.findCover,
	Move.indoorNear,
	Move.coverStep,
	Move.shakenNow,
	Move.inside,
	Move.setGoal,
	Move.follow,
	Move.putAway,
	Move.face,
	Move.holdShovel,
	Move.finish

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

local function pickFrom(
	b: Bot,
	open: { BuildJob },
	any: boolean,
	fixOnly: boolean?,
	far: number?,
	share: boolean?
): BuildJob?
	local engineer = any or Loadouts.classOf(b.m :: Model) == "Engineer"
	local root = (b.root :: BasePart).Position
	local held: { [BuildJob]: boolean } = {}
	for _, o in bots do
		local a = o.act
		if a and a.kind == "Build" and a.job then
			held[a.job :: BuildJob] = true
		end
		if o.work then
			held[o.work.job] = true -- (on its way to it)
		end
	end
	local list: { BotBuild.Job } = {}
	local taken: { [number]: boolean } = {}
	for k, r in open do
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
		local fits = engineer or Kinds.small[j.key] or (j.key == "Wire" and r.model ~= nil and d <= BD.help)
		-- (`share`: a square wanting swings may have more than one digger)
		local busy = held[r] == true and not (share and r.model ~= nil)
		taken[k] = busy or not fits or (j.key == "Tree" and not Tactics.fell.ready(b.id))
	end
	-- a gun of its side out of service (Rules/BotCrew.repairOrder): the nearest anywhere first, fixed before it is manned
	local notFix: { [number]: boolean } = {}
	for k, r in open do
		notFix[k] = taken[k] or not r.fix
	end
	local f = BotBuild.pick(list, root.X, root.Z, math.huge, notFix, {}, nil)
	if f or fixOnly then
		return if f then open[f] else nil
	end
	-- on gun duty (Config/Bots.Build.Crews) or dugout duty (Config/Bots.Dugouts.engineers): the nearest such job
	-- anywhere on the list first
	if b.crew or b.dugouts then
		local notGun: { [number]: boolean } = {}
		for k, r in open do
			notGun[k] = taken[k] or not (if b.crew then Kinds.gun[r.job.key] else r.job.key == "Dugout")
		end
		local g = BotBuild.pick(list, root.X, root.Z, math.huge, notGun, {}, nil)
		if g then
			return open[g]
		end
	end
	-- (an Engineer any job on its side's front, from where its squad is: Build.engineerTake)
	local reach = far or (if engineer and not any then BD.engineerTake else BD.take)
	local k = BotBuild.pick(list, root.X, root.Z, reach, taken, {}, nil)
	return if k then open[k] else nil
end

-- the build job a bot takes on its side's list: an Engineer any; a digger (half a holding squad, any class) a trench
-- run or square, a sandbag pile or barrier, wire wanting swings within Build.help; a defender a gun out of service;
-- nil if none (and why, for the admin panel's readout)
local function pickJob(b: Bot): (BuildJob?, string?)
	local sb = buildLists[b.side :: string]
	if not sb or not sb.front then
		return nil, "no front"
	end
	if #sb.open == 0 then
		return nil, "no jobs open"
	end
	if not b.digger and Loadouts.classOf(b.m :: Model) ~= "Engineer" then
		-- a defender (who would crew it: src/server/Bots/Crew) fixes a gun of its side out of service, nothing else
		if b.order == "Defend" then
			return pickFrom(b, sb.open, true, true), nil
		end
		return nil, "not a builder"
	end
	local r = pickFrom(b, sb.open, false)
	local reach = if Loadouts.classOf(b.m :: Model) == "Engineer" then BD.engineerTake else BD.take
	return r, if r then nil else `none within {reach} studs`
end

-- a pioneer's trench job (Config/Bots.Trenches.pioneers): the nearest trench run or square on its side's list, or a
-- tree in the way of its lines (Config/Bots.Build.Trees: a run refused for a tree waits on it)
local function pickTrench(b: Bot): BuildJob?
	local sb = buildLists[b.side :: string]
	if not sb or not sb.front then
		return nil
	end
	local trench = {}
	for _, r in sb.open do
		if r.job.key == "Trench" or r.job.key == "Tree" then
			table.insert(trench, r)
		end
	end
	return if #trench > 0 then pickFrom(b, trench, true, false, Cfg.Trenches.pioneerTake, true) else nil
end

-- an enemy dugout's steps to throw down, if its squad `sq` knows someone is in it (Rules/BotTrenches.occupied): within
-- Dugouts.Bomb.min-max of `at`, no teammate near the steps
local function bombOut(b: Bot, sq: SquadState, at: Vector3, now: number): Vector3?
	local B = Cfg.Dugouts.Bomb
	local known = {}
	for _, k in sq.known do
		if now - k.at <= SQ.knownFor then
			table.insert(known, { x = k.pos.X, y = k.pos.Y, z = k.pos.Z })
		end
	end
	if #known == 0 then
		return nil
	end
	for _, w in Clear.every do
		local foot = w.key == "Dugout" and w.team ~= b.kit and w.built and w.hp > 0 and Tactics.dug.foot(w.model)
		if foot then
			local steps = (foot :: Vector3):Lerp(w.at, 0.35) -- (part way down them)
			local d = flat(steps - at).Magnitude
			if d >= B.min and d <= B.max and BotTrenches.occupied(known, { x = w.at.X, z = w.at.Z }, foot.Y, B) then
				local clear = true
				for _, o in bots do
					if
						o.side == b.side
						and o.root
						and flat((o.root :: BasePart).Position - steps).Magnitude < AC.Grenade.safe
					then
						clear = false
						break
					end
				end
				if clear then
					return steps
				end
			end
		end
	end
	return nil
end

-- where a build job is worked from: the piece's spot (laid: swung at), else behind the spot to lay it; and how near
-- counts as there
local function workAt(r: BuildJob): (Vector3, number)
	if r.model and r.at then
		return r.at :: Vector3, BuildCfg.SwingReach - 1
	end
	local job = r.job
	return Routes.ground(job.x, job.z) - Vector3.new(job.fx, 0, job.fz) * BD.stand, BD.stand + 2
end

-- whether `b` may put its gun away and work where it is (Rules/BotBuild.safeToWork; `brave`: a sapper, under fire too)
local function safeHere(b: Bot, r: BuildJob, brave: boolean, now: number): boolean
	local sinceThreat = if b.threatAt then now - (b.threatAt :: number) else math.huge
	local sinceHurt = if b.hurtAt then now - (b.hurtAt :: number) else math.huge
	local seen = b.target ~= nil and (b.target :: Target).visible
	local hid = false
	if not seen and b.threatFrom and sinceThreat < BD.calm and budget.rays > 0 then
		hid = hidden(b.threatFrom :: Vector3, (b.root :: BasePart).Position, exclusions(b))
	end
	-- (a trench is dug under fire, as a sap: only a hit stops it, Config/Bots.Trenches.pioneers)
	local dig = r.job.key == "Trench"
	return BotBuild.safeToWork(r.underFire == true or brave or dig, seen, sinceThreat, sinceHurt, hid, BD.calm)
end

-- a build job taken (or gone back to): worked now if it is there and safe, else walked to with the gun out, fighting on
-- the way (b.work: think's goal; Config/Bots.Build.Work)
local function takeJob(b: Bot, r: BuildJob, now: number, brave: boolean?)
	local at, reach = workAt(r)
	local w = b.work
	if not w or w.job ~= r then
		w = { job = r, at = at, since = now, brave = brave == true }
		b.work = w
		stats.workTaken += 1
	else
		w.at = at
	end
	local near = flat(at - (b.root :: BasePart).Position).Magnitude <= reach + BD.Work.near
	if near and safeHere(b, r, (w :: any).brave, now) then
		b.act = { kind = "Build", job = r, started = now }
		b.workState = "working"
		stats.workStarted += 1
	else
		b.workState = if near then "waiting" else "going"
	end
end

-- who rescues casualty `c` now (Config/Bots.Actions.Rescue): its claim holds while the rescuer lives and still means
-- them (guarding, dragging or healing them); else let go
local function rescuerOf(c: Model, now: number): Bot?
	local cl = rescue.claims[c]
	if not cl then
		return nil
	end
	local r = cl.by
	local on = r.m ~= nil
		and alive(r)
		and not r.deadAt
		and ((r.guard ~= nil and r.guard.who == c) or (r.act ~= nil and r.act.who == c))
	if on then
		return r
	end
	rescue.claims[c] = nil
	rescue.freed[c] = now
	stats.rescuesLet += 1
	return nil
end

-- whether `b` is the one to rescue casualty `c` (Rules/BotActions.rescuer): free bots of its side, its squad first
local function mineToRescue(b: Bot, c: Model, at: Vector3, now: number): boolean
	local by = rescuerOf(c, now)
	if by then
		return by == b
	end
	if now - (rescue.freed[c] or -math.huge) < AC.Rescue.wait then
		return false
	end
	local squadOf: string? = nil
	for _, o in bots do
		if o.m == c then
			squadOf = o.squad
			break
		end
	end
	local cands: { { distance: number, sameSquad: boolean } } = {}
	local mine: number? = nil
	for _, o in bots do
		local om = o.m
		local sq = o.squad and squads[o.squad :: string]
		local free = om ~= nil
			and o.root ~= nil
			and om ~= c
			and o.side == b.side
			and alive(o)
			and not o.deadAt
			and not o.gun
			and not Ragdoll.active(om)
			and (o.act == nil or o.act.who == c)
			and (o.guard == nil or o.guard.who == c)
			and not (sq and (sq :: SquadState).sq.phase == "Assault")
		if free then
			table.insert(cands, {
				distance = flat((o.root :: BasePart).Position - at).Magnitude,
				sameSquad = squadOf ~= nil and o.squad == squadOf,
			})
			if o == b then
				mine = #cands
			end
		end
	end
	return mine ~= nil and Actions.rescuer(cands, AC.Rescue.range) == mine
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
	-- one rescuer a casualty: the others leave it to them (Config/Bots.Actions.Rescue)
	for i, mt in mates do
		local wants = (mt.down and mt.distance <= AC.Drag.within) or mt.health < AC.Heal.below
		if wants and not mt.busy and not mineToRescue(b, who[i].model, who[i].pos, now) then
			mt.busy = true
		end
	end
	-- a downed teammate in sight of where the enemy is
	if spot then
		local eyeAt = (spot :: Vector3) + Vector3.yAxis * Cfg.Eye
		for i, mt in mates do
			local wants = (mt.down and mt.distance <= AC.Drag.within) or mt.health < AC.Heal.below
			if wants and not mt.busy and budget.rays > 0 then
				rayParams.FilterDescendantsInstances = { m }
				local hit = workspace:Raycast(eyeAt, who[i].pos - eyeAt, rayParams)
				stats.rays += 1
				budget.rays -= 1
				mt.exposed = hit == nil or hit.Instance:IsDescendantOf(who[i].model)
			end
		end
	end
	-- in a fight only from cover or to a teammate in cover; else it guards them, gun out, until it may
	-- (Config/Bots.Actions.Guard)
	local sinceThreat = if b.threatAt then now - (b.threatAt :: number) else math.huge
	local sinceHurt = if b.hurtAt then now - (b.hurtAt :: number) else math.huge
	local seen = b.target ~= nil and (b.target :: Target).visible
	local safe = BotBuild.safeToWork(false, seen, sinceThreat, sinceHurt, false, BD.calm)
	local selfHidden: boolean? = nil
	local function mayTend(k: number): boolean
		local c = who[k].model
		if not rescue.claims[c] then
			rescue.claims[c] = { by = b, at = now }
			stats.rescues += 1
		end
		if not safe and selfHidden == nil then
			selfHidden = b.threatFrom ~= nil
				and budget.rays > 0
				and hidden(b.threatFrom :: Vector3, root.Position, exclusions(b))
		end
		if Actions.mayTend(safe, selfHidden == true, mates[k].exposed) then
			b.guard = nil
			return true
		end
		if not b.guard or b.guard.who ~= who[k].model then
			b.guard = { who = who[k].model, since = now }
			stats.guarded += 1
		end
		return false
	end
	local g = b.guard
	if g and (now - g.since > AC.Guard.keep or not g.who.Parent) then
		b.guard = nil
	end
	local i = Actions.dragPick(mates, AC.Drag)
	if i and spot and mayTend(i) then
		b.act = { kind = "Drag", who = who[i].model, from = spot, started = now }
		return
	end
	local sq = b.squad and squads[b.squad :: string]
	local pushing = sq ~= nil and (sq :: SquadState).sq.phase == "Assault"
	if not pushing and not i then
		i = Actions.healPick(mates, AC.Heal)
		if i and mayTend(i) then
			b.act = { kind = "Heal", who = who[i].model, started = now }
			return
		end
	end
	if not i then
		b.guard = nil -- (nobody to guard: up, healed, or gone)
	end
	-- on its way to a job it took (or back to one danger stopped): worked once there and safe, else kept a while; a
	-- sapper lets any other go for its squad's sap
	local sap = sq and (sq :: SquadState).sap
	local sapping = b.sapper == true and sap ~= nil and #(sap :: Sap).open > 0
	local w = b.work
	if w and (not w.job.open or now - w.since > BD.Work.keep or (sapping and not w.brave)) then
		b.work, b.workState, w = nil, nil, nil
	end
	-- a pioneer leaves any other job for its side's trench lines, and digs them under fire too
	-- (Config/Bots.Trenches.pioneers)
	if b.pioneer and not pushing and not (w and (w.job.job.key == "Trench" or w.job.job.key == "Tree")) then
		local r = pickTrench(b)
		if r then
			b.work, b.workState, w = nil, nil, nil
			takeJob(b, r, now, true)
			return
		end
	end
	if w then
		takeJob(b, w.job, now, w.brave)
		if b.act then
			return
		end
	end
	-- a sapper digs its squad's sap, under fire too (Rules/BotSap: only a hit stops it)
	if b.sapper and sap and #(sap :: Sap).open > 0 and not w then
		local r = pickFrom(b, (sap :: Sap).open, true)
		if r then
			takeJob(b, r, now, true)
			return
		end
	end
	-- pinned down in the open with no cover: a sandbag pile in front of itself, filled under fire
	-- (cover counts only near: a pinned bot with its cover far off lays a pile where it is)
	local hasCover = b.coverJob ~= nil
		or (b.cover ~= nil and flat((b.cover :: Vector3) - root.Position).Magnitude <= PN.near)
	if
		b.side
		and b.threatFrom
		and BotBuild.pinned(
			sinceThreat,
			shakenNow(b, now),
			hasCover,
			b.postFloor ~= nil,
			now - (b.pileAt or -math.huge),
			PN
		)
	then
		-- (a foxhole at its feet, Config/Bots.Dugouts: a pile instead where the ground refuses one, doBuild)
		local to = flat((b.threatFrom :: Vector3) - root.Position)
		to = if to.Magnitude > 1e-3 then to.Unit else flat(root.CFrame.LookVector)
		local at = root.Position
		local job = { key = "Foxhole", x = at.X, z = at.Z, fx = to.X, fz = to.Z }
		local r = { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = true, underFire = true }
		b.pileAt = now
		stats.pinnedHoles += 1
		takeJob(b, r, now)
		return
	end
	-- a job on its side's build list, when calm and it sees no enemy (Config/Bots.Build)
	-- holding an open post with no trench near: a foxhole there, facing the enemy (Config/Bots.Dugouts.Fox)
	local post = b.post
	if
		b.role == "Hold"
		and not w
		and b.postKind == "open"
		and post
		and b.side
		and not seen
		and Actions.calm(sinceThreat, sinceHurt, BD.calm)
		and now - (Tactics.dug.tried[b.id] or -math.huge) >= BD.retry
		and flat(post - root.Position).Magnitude <= BD.stand + 4
	then
		local own = buildLists[b.side :: string]
		if
			BotTrenches.foxholeWanted(
				post.X,
				post.Z,
				if own then own.squares else {},
				Tactics.dug.holes,
				Cfg.Dugouts.Fox
			)
		then
			Tactics.dug.tried[b.id] = now
			local tx, tz = BotBuild.toward(Map.sectors, b.sector or 1, b.side)
			local job = { key = "Foxhole", x = post.X, z = post.Z, fx = tx, fz = tz }
			local r = { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = true }
			takeJob(b, r, now)
			return
		end
	end
	-- (an Engineer's job, or why it has none: the admin panel's readout)
	if Loadouts.classOf(m) == "Engineer" then
		b.buildWhy = if w
			then "on its job"
			elseif pushing then "pushing"
			elseif seen then "enemy in sight"
			elseif not Actions.calm(sinceThreat, sinceHurt, BD.calm) then "under fire"
			else nil
	end
	if not pushing and not seen and not w and b.side and Actions.calm(sinceThreat, sinceHurt, BD.calm) then
		local r, why = pickJob(b)
		if Loadouts.classOf(m) == "Engineer" then
			b.buildWhy = if r then r.job.key else why
		end
		if r then
			takeJob(b, r, now)
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
	-- a pushing squad's Grenadier bombs out an enemy dugout it knows someone is in (Config/Bots.Dugouts.Bomb)
	local bomb = if pushing then bombOut(b, sq :: SquadState, root.Position, now) else nil
	if bomb then
		stats.bombed += 1
		b.act = { kind = "Throw", at = bomb, started = now }
		return
	end
	-- its squad pushing a group it outnumbers: the grenade at the group first (Config/Bots.Squads.Push)
	local bombAt = sq and (sq :: SquadState).bomb
	if bombAt then
		local d = flat(bombAt - root.Position).Magnitude
		local clear = d >= G.min and d <= G.max
		for k = 1, n do
			local o = all[k]
			if clear and o.model ~= m and friendly(m, kit, o) and flat(o.pos - bombAt).Magnitude < G.safe then
				clear = false
			end
		end
		if clear then
			(sq :: SquadState).bomb = nil
			stats.pushBombs += 1
			b.act = { kind = "Throw", at = bombAt, started = now }
			return
		end
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
	for _, w in (Tactics.dug.works(b.kit, Loadouts.classOf(b.m :: Model))) do
		local d = math.sqrt((w.at.X - job.x) ^ 2 + (w.at.Z - job.z) ^ 2)
		if w.key == job.key and d <= bestD then
			best, bestD = w, d
		end
	end
	return best
end

-- (Trenches.plan's refusal for a tree in the way)
local TREE = "A tree is in the way"

-- a refused lay: its spot moved across (Rules/BotBuild.nudge), after Build.tries the planned spot again a while later
local function refused(r: BuildJob, now: number, reason: string?)
	stats.refused += 1
	-- (a tree in a trench run's way: it waits for the tree to be felled, Config/Bots.Trenches.Tree)
	local TT = Cfg.Trenches.Tree
	if r.run and reason == TREE and (r.treeWaits or 0) < TT.waits then
		r.treeWaits = (r.treeWaits or 0) + 1
		r.waitUntil, r.open = now + TT.wait, false
		return
	end
	r.tries += 1
	local base = r.base
	if r.tries >= BD.tries then
		r.tries, r.job, r.waitUntil, r.open = 0, base, now + BD.retry, false
		r.gaveUp = true
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

-- whether a bot's swing of `mode` at `target` is due: a player's cadence holding the key (Build.nextSwing), the first
-- at the swing's strike once it stands at the target
local function swingDue(act: Act, target: Instance, mode: string, now: number): boolean
	if act.swingOn ~= target then
		act.swingOn, act.swingAt = target, Build.nextSwing(mode, nil, now)
	end
	return now >= (act.swingAt or 0)
end

-- a build, one think of it: to the job, the piece laid (once), then Build swings at it until it wants none, the
-- shovel in hand; given up when it's shot at, sees an enemy, the job leaves the list or takes too long
-- the job over (done, refused, gone): nothing to go back to
local function quit(b: Bot)
	b.work, b.workState = nil, nil
	finish(b)
end

local function doBuild(b: Bot, act: Act, now: number): boolean
	local r = act.job :: BuildJob
	local m, humanoid, root = b.m :: Model, b.humanoid :: Humanoid, b.root :: BasePart
	if not r.open or now - act.started > BD.seconds then
		quit(b)
		return false
	end
	-- danger mid-work: the tool dropped, the gun out, the job kept to go back to once safe (Config/Bots.Build.Work)
	local work = b.work
	local hurt = b.hurtAt ~= nil and (b.hurtAt :: number) > act.started
	if hurt or not safeHere(b, r, work ~= nil and work.brave, now) then
		stats.workStopped += 1
		finish(b)
		if work then
			work.since = math.max(work.since, now - BD.Work.keep / 2) -- (a while yet to get back to it)
			b.workState = "going"
		end
		return false
	end
	local job = r.job
	local f = Vector3.new(job.fx, 0, job.fz)
	-- a trench run's way cleared first: a piece in it torn down, or the run swung aside round it
	local tear: Build.Work? = nil
	if not r.model and job.key == "Trench" and job.ex then
		local w, how = Clear.inWay(b.kit, job)
		if w and how == "around" then
			stats.around += 1
			refused(r, now)
			quit(b)
			return false
		end
		tear = w
	end
	local swingAt = if tear then tear.at elseif r.model and r.at then r.at :: Vector3 else nil
	local spot = swingAt or Routes.ground(job.x, job.z)
	-- (it lays a piece from behind it, its own side; it swings at one from where it is)
	local reach = if job.key == "Tree" then BD.Trees.stand elseif swingAt then BuildCfg.SwingReach - 1 else BD.stand + 2
	if flat(spot - root.Position).Magnitude > reach then
		if work and flat(spot - root.Position).Magnitude > reach + BD.Work.near * 2 then
			-- (far off still: walked to with the gun out, fighting on the way)
			finish(b)
			b.workState = "going"
			return false
		end
		humanoid.WalkSpeed = M.WalkSpeed
		act.swingOn = nil -- (back in reach, its first swing at the strike again)
		setGoal(b, if swingAt then spot else spot - f * BD.stand, now)
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
	standFacing(b, if swingAt then spot else spot + f, now)
	if tear then
		if swingDue(act, tear.model, "Destroy", now) then
			local reason = Build.workAs(m, tear.model, "Destroy")
			if reason == nil then
				stats.torn += 1
				act.swingAt = Build.nextSwing("Destroy", act.swingAt, now)
			elseif reason ~= "Too soon" then
				quit(b) -- (gone, or out of reach)
				return false
			end
		end
		return true
	end
	-- pinned down where the ground refuses a foxhole: a sandbag pile in front of itself instead (Config/Bots.Dugouts)
	local function pileInstead(): boolean
		if job.key ~= "Foxhole" or not r.underFire then
			return false
		end
		local j =
			{ key = "SandbagPile", x = job.x + f.X * PN.ahead, z = job.z + f.Z * PN.ahead, fx = job.fx, fz = job.fz }
		r.job, r.base, r.tries = j, j, 0
		stats.pinnedPiles += 1
		return true
	end
	if not r.model then
		if not Clear.inside[job.key] and not Clear.ofLines(b.side :: string, job.key, spot) then
			if pileInstead() then
				return true
			end
			stats.keptOff += 1
			refused(r, now)
			quit(b)
			return false
		end
		local reason = if job.key == "Trench"
			then Build.planAs(m, spot, Routes.ground(job.ex :: number, job.ez :: number))
			else Build.placeAs(m, job.key, spot, f)
		-- a run of its side's lines refused whole: planned as far as it goes, halving down to a square, the rest of it
		-- from there on (Config/Bots.Trenches.Tree; a measured match's runs on Map 1 met a tree 69 times in 78 tries)
		if reason and r.run then
			local far = Routes.ground(job.ex :: number, job.ez :: number)
			local along = flat(far - spot)
			local step = along.Magnitude / 2
			while step >= BuildCfg.Trench.block do
				local to = Routes.ground(spot.X + along.Unit.X * step, spot.Z + along.Unit.Z * step)
				if Build.planAs(m, spot, to) == nil then
					stats.partRuns += 1
					r.from = r.from or { x = job.x, z = job.z }
					r.job = { key = job.key, x = to.X, z = to.Z, ex = job.ex, ez = job.ez, fx = job.fx, fz = job.fz }
					reason = nil
					break
				end
				step /= 2
			end
		end
		if reason and pileInstead() then
			return true
		end
		if reason then
			refused(r, now, reason)
			quit(b)
			return false
		end
		stats.laid += 1
		if r.run then
			stats.runs += 1
		end
		local w = laidFor(b, job)
		if not w then
			quit(b) -- (it is on the next tick's list)
			return false
		end
		r.model, r.at, r.left = w.model, w.at, w.left
		return true
	end
	-- (a tree is chopped, a captured enemy MG nest wrecked: src/server/Bots/Crew)
	local mode = if job.key == "Tree" or job.key == "Wreck" then "Destroy" else "Build"
	if swingDue(act, r.model :: Model, mode, now) then
		local reason = if job.key == "Tree"
			then Tactics.fell.chop(m, b.id, b.side :: string, r)
			else Build.workAs(m, r.model :: Model, mode)
		if reason == nil and job.key == "Foxhole" then
			-- one swing digs it: into it (pinned: its cover; holding: its post, facing the enemy)
			stats.swings += 1
			stats.holes += 1
			local floor = Tactics.dug.dug(r.at or spot)
			if r.underFire then
				b.cover, b.coverFrom, b.coverAt, b.coverJob = floor, b.threatFrom, now, nil
			elseif b.postKind == "open" and b.post and flat((b.post :: Vector3) - floor).Magnitude <= BD.stand + 4 then
				b.post, b.postFloor, b.goal = floor, floor, floor
			end
			quit(b)
			return false
		elseif reason == nil then
			stats.swings += 1
			act.swingAt = Build.nextSwing(mode, act.swingAt, now)
		elseif reason ~= "Too soon" then
			quit(b) -- (whole now, or gone)
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

-- Mage bots (Rules/BotStaff, Config/Bots.Staff) ----------------------------------------------------------------------

local function arms(b: Bot, entry: any, now: number): Arms
	if entry then
		local s = entry.state
		F.settle(s, now)
		return {
			magazine = s.magazine,
			chambered = s.chambered,
			spent = s.spent,
			busy = F.busy(s, now, 0),
			loading = s.load ~= nil,
			capacity = entry.gun.capacity + 1,
			auto = entry.gun.auto == true,
		}
	end
	local m = b.m :: Model
	local mana, _, locked = StaffCast.manaOf(m)
	local whole = math.floor(mana)
	return {
		magazine = whole,
		chambered = whole > 0,
		spent = false,
		busy = b.cast ~= nil or StaffCast.readyIn(m) > 0,
		loading = locked or mana < 1,
		capacity = SpellsCfg.Mana.max + 1,
		auto = true,
	}
end

-- where a shot from `origin` at `part` goes: led by the difficulty, off by its aim error (as the gun bots aim)
local function aimPoint(b: Bot, part: BasePart, origin: Vector3, d: Rules.Difficulty, now: number): Vector3
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
	return origin + dir * line.Magnitude
end

-- its open circle closed without a shot
local function dropCast(b: Bot)
	if not b.cast then
		return
	end
	b.cast = nil
	stats.dropped += 1
	if b.m then
		StaffCast.dropAs(b.m :: Model)
	end
	if b.anim then
		(b.anim :: Animate.Handle).stop()
	end
end

-- a strongpoint at `at`: in a building, on an MG nest, by a gun (Config/Bots.Staff `gun`)
local function strongpoint(at: Vector3): boolean
	if Build.onNest(at) or #indoorNear(at, IN.clearWithin) > 0 then
		return true
	end
	for _, g in Artillery.list() do
		if flat(g.crew - at).Magnitude <= ST.gun then
			return true
		end
	end
	return false
end

-- the staff, one think: an open circle aimed and released once charged (dropped once its seen target has been out
-- of sight a while); else, when the brain fires, the stage Rules/BotStaff.stage picks at the target (or a known
-- enemy's cover): a quick shot at once, a medium or mega shot's circle opened
-- whether a staff beam from `b`'s head to `at` (the target's body, or a spot) is clear (user 2026-11-03 play test:
-- "mages frequently gets stuck in this loop where they shoot their own trench by accident, then repair it"): anything
-- in the way short of `Sight.near` studs of the point holds it (it casts once it peeks out). Blocked close by
-- (`Staff.ownWithin` studs: its own trench's wall or bank, a sandbag): counted.
local function clearBeam(b: Bot, at: Vector3, target: Model?): boolean
	local head = (b.head :: BasePart).Position
	local line = at - head
	rayParams.FilterDescendantsInstances = { b.m :: Model }
	local hit = workspace:Raycast(head, line, rayParams)
	stats.rays += 1
	if
		not hit
		or (target and hit.Instance:IsDescendantOf(target))
		or hit.Distance >= line.Magnitude - Cfg.Sight.near
	then
		return true
	end
	if hit.Distance <= ST.ownWithin then
		stats.selfHits += 1
	end
	return false
end

local function staffFire(b: Bot, fire: boolean, target: Target?, coverAt: Vector3?, facing: boolean, d, now: number)
	local m, head = b.m :: Model, b.head :: BasePart
	local part = if target and target.visible then aimPart(target.model) else nil
	local c = b.cast
	if c then
		if part then
			c.seenAt, c.at = now, aimPoint(b, part :: BasePart, head.Position, d, now)
		elseif c.visible and now - c.seenAt > ST.lost then
			dropCast(b)
			return
		end
		StaffCast.aimAs(m, c.at)
		local hold = SpellsCfg.Stages[c.stage].hold
		local ready = facing and BotStaff.release(now - c.openedAt, hold, StaffCast.readyIn(m))
		if ready and clearBeam(b, c.at, if target then target.model else nil) then
			if StaffCast.castAs(m, c.stage, c.at) then
				(stats :: any)[`casts{c.stage}`] += 1
			end
			b.cast = nil
			if b.anim then
				(b.anim :: Animate.Handle).stop()
			end
		end
		return
	end
	if not fire or not facing or StaffCast.readyIn(m) > 0 then
		return
	end
	local at = if part then aimPoint(b, part :: BasePart, head.Position, d, now) else coverAt
	if not at then
		return
	end
	local _, affordable, locked = StaffCast.manaOf(m)
	if locked or affordable < 1 then
		return
	end
	local p = at :: Vector3
	if not clearBeam(b, p, if part then (target :: Target).model else nil) then
		return -- (nothing in the way it would hit: its own cover)
	end
	local all, n = soldiersNow()
	local kit = m:GetAttribute("Kit")
	local mates = {}
	local group = 0
	for k = 1, n do
		local o = all[k]
		if o.model ~= m then
			if friendly(m, kit, o) then
				table.insert(mates, { x = o.pos.X, z = o.pos.Z })
			elseif not o.down and flat(o.pos - p).Magnitude <= ST.cluster then
				group += 1
			end
		end
	end
	local onLine, nearBlast = BotStaff.mates(mates, head.Position.X, head.Position.Z, p.X, p.Z, ST.line, ST.blast)
	local stage = BotStaff.stage({
		distance = (p - head.Position).Magnitude,
		visible = part ~= nil,
		affordable = affordable,
		group = group,
		strong = strongpoint(p),
		mateOnLine = onLine,
		mateNearBlast = nearBlast,
	}, DamageCfg.Staff.Range, ST)
	if stage == 1 then
		if StaffCast.castAs(m, 1, p) then
			stats.casts1 += 1
		end
	elseif stage > 1 and StaffCast.openAs(m) then
		b.cast = { stage = stage, openedAt = now, seenAt = now, at = p, visible = part ~= nil }
		if b.anim then
			(b.anim :: Animate.Handle).play(W[b.weapon].holds.charge, true)
		end
	end
end

return {
	throwLook = throwLook,
	pickFrom = pickFrom,
	pickJob = pickJob,
	weigh = weigh,
	actPose = actPose,
	throwSequence = throwSequence,
	healAnimations = healAnimations,
	standFacing = standFacing,
	laidFor = laidFor,
	refused = refused,
	doBuild = doBuild,
	doAct = doAct,
	arms = arms,
	aimPoint = aimPoint,
	dropCast = dropCast,
	strongpoint = strongpoint,
	staffFire = staffFire,
	bombOut = bombOut,
	takeJob = takeJob,
}
