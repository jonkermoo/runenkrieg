--!strict
-- Normal: bots on the guns (Config/Bots.Crew, Rules/BotCrew; user 2026-11-02, stage 2g). The commander gives each
-- free gun on its side's sectors a gunner (Crew.command); the gunner walks there and mans it, then lays and fires it
-- (Crew.think, in place of its own think); a teammate taking it over (E) sends it back to duty (Artillery.onBotLeft).
-- Kept out of src/server/Bots; it hands over what it needs (Crew.init).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local ArtCfg = require(Shared.Config.Artillery)
local FrontCfg = require(Shared.Config.Frontline)
local Map = require(Shared.LiveMap).map -- (the match's map)
local Metrics = require(Shared.Config.Metrics)
local Loco = require(Shared.Config.Locomotion)
local Rules = require(Shared.Rules.BotCrew)
local Artillery = require(script.Parent.Parent.Artillery)

local Crew = {}

local C = Cfg.Crew
local M = Metrics.Movement

-- what src/server/Bots hands over (its own functions on a bot)
export type Context = {
	bots: { any },
	alive: (b: any) -> boolean,
	setGoal: (b: any, goal: Vector3?, now: number) -> (),
	follow: (b: any, now: number) -> (),
	finish: (b: any) -> (),
	dropCast: (b: any) -> (),
	putAway: (b: any, on: boolean) -> (),
	aimPart: (m: Model) -> BasePart?,
	friends: (b: any) -> { Rules.Spot }, -- every living soldier on its side
}

-- each gunner's own state: the gun's body it was given for, when, the field gun's aim, when it looks again, when its
-- MG's firing at a target began
type Gunning = {
	m: Model?,
	since: number,
	point: Vector3?,
	retargetAt: number,
	burstFrom: number?,
	blind: number?, -- its looks in a row that found targets in reach but every shot stopped short
}

local ctx: Context = nil :: any
local gunning: { [any]: Gunning } = setmetatable({}, { __mode = "k" }) :: any
-- each side's targets, from its commander's tick: known enemy groups (biggest first) and the sector to fall back on
local targets: { [string]: { groups: { Vector3 }, fallback: Vector3? } } = {}
local random = Random.new()
-- this report's counts
local stats = { shells = 0, bursts = 0, held = 0, kicked = 0, given = 0, gaveUp = 0, blocked = 0, blinded = 0 }
-- guns given no gunner until then: every shot they could lay stopped short (Config/Bots.Crew `blind`)
local blindUntil: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
-- the guns' list once a frame (Artillery.list, no point)
local listed: { [Model]: Artillery.GunInfo } = {}
local listedAt = -1

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function infoOf(gun: Model, now: number): Artillery.GunInfo?
	if listedAt ~= now then
		listedAt = now
		table.clear(listed)
		for _, g in Artillery.list() do
			listed[g.model] = g
		end
	end
	return listed[gun]
end

-- the side holding the sector nearest `p`
local function ownerAt(p: Vector3, owner: { string }): string?
	local i = Rules.sectorAt(p.X, p.Z, Map.sectors)
	return if i then owner[i] else nil
end

local function release(b: any, wait: number?)
	b.gun = nil
	gunning[b] = nil
	if wait then
		b.gunWait = os.clock() + wait
	end
	if b.m and b.away and not b.act then
		ctx.putAway(b, false)
	end
	if b.humanoid then
		(b.humanoid :: Humanoid).AutoRotate = true
	end
end

-- on the gun: no walking, no post, no squad, its own gun put away
local function seated(b: any)
	local nav = b.nav
	nav.goal, nav.direct, nav.waypoints = nil, nil, {}
	b.post, b.postKind, b.postFloor, b.postFace, b.postSector = nil, nil, nil, nil, nil
	b.goal, b.stop, b.squad, b.role = nil, nil, nil, nil
	ctx.finish(b)
	ctx.dropCast(b)
	ctx.putAway(b, true)
	if b.turn then
		(b.turn :: AlignOrientation).Enabled = false
	end
	(b.humanoid :: Humanoid).AutoRotate = false
end

-- a field gun's or howitzer's aim: the biggest known group it reaches, clear of its own side, else the sector
local function aim(b: any, g: Gunning, info: Artillery.GunInfo, now: number)
	local m = b.m :: Model
	local t = targets[b.side]
	g.point, g.retargetAt = nil, now + C.retarget
	if not t then
		return
	end
	local friends = ctx.friends(b)
	local radius = Rules.danger(ArtCfg.Guns[info.key].kg or 0, C.hold)
	-- (only where its shot comes down there: no hill or house in the way, Artillery.shotClearAs; user 2026-11-03: "AI
	-- still firing into hills")
	local blocked = false
	local function try(at: Vector3): boolean
		local clear, reach = Artillery.shotClearAs(m, at)
		blocked = blocked or (reach and not clear)
		return clear and Artillery.aimAtAs(m, at)
	end
	for _, at in t.groups do
		if Rules.clear(at.X, at.Z, friends, radius) and try(at) then
			g.point = at
			break
		end
	end
	local f = t.fallback
	if f and not g.point then
		for _ = 1, C.blind.tries do
			local x, z = Rules.scatter(f.X, f.Z, C.scatter, random:NextNumber(), random:NextNumber())
			local at = Vector3.new(x, f.Y, z)
			if try(at) then
				g.point = at
				break
			end
		end
	end
	if g.point or not blocked then
		g.blind = 0
	else
		g.blind = (g.blind or 0) + 1
		stats.blocked += 1
	end
end

-- a field gun or howitzer: laid, loaded and clear of its own side, fired
local function shell(b: any, g: Gunning, info: Artillery.GunInfo, now: number)
	if not g.point or now >= g.retargetAt then
		aim(b, g, info, now)
		-- every shot it can lay stopped short again and again: off it, the gun left without a gunner a while (bots
		-- can't move it)
		if (g.blind or 0) >= C.blind.looks then
			blindUntil[info.model] = now + C.blind.wait
			stats.blinded += 1
			Artillery.leaveAs(b.m)
			return
		end
	end
	local p = g.point
	if not p or not info.loaded or not Artillery.laidAs(b.m) then
		return
	end
	local radius = Rules.danger(ArtCfg.Guns[info.key].kg or 0, C.hold)
	if not Rules.clear(p.X, p.Z, ctx.friends(b), radius) then
		stats.held += 1
		g.retargetAt = math.min(g.retargetAt, now + 1)
		return
	end
	local ok, why = Artillery.fireAs(b.m)
	if ok then
		stats.shells += 1
		g.retargetAt = now -- (the next shot: a fresh look, a fresh spread)
	elseif why ~= "Reloading" then
		g.point = nil -- (refused: its own sector)
	end
end

-- an MG: bursts at a target it sees in range, a new box when empty (or low with nothing to shoot at)
local function mg(b: any, g: Gunning, info: Artillery.GunInfo, now: number)
	local m = b.m :: Model
	local gun = ArtCfg.Guns[info.key]
	local box = (gun.mg :: any).box :: number
	local rounds = info.rounds or 0
	local t = b.target
	local part = if t and t.visible and t.distance <= (gun.mg :: any).range then ctx.aimPart(t.model) else nil
	if rounds <= 0 then
		Artillery.triggerAs(m, false)
		Artillery.reloadAs(m)
		g.burstFrom = nil
		return
	end
	if not part then
		Artillery.triggerAs(m, false)
		g.burstFrom = nil
		if rounds < box * C.topUp and info.loaded then
			Artillery.reloadAs(m)
		end
		return
	end
	if not Artillery.aimAtAs(m, part.Position) or not Artillery.laidAs(m) then
		Artillery.triggerAs(m, false)
		return
	end
	if not g.burstFrom then
		g.burstFrom = now
		stats.bursts += 1
	end
	local held = Rules.burst(now - (g.burstFrom :: number), C.burst)
	Artillery.triggerAs(m, held)
end

-- The bot's think while it is given a gun: walking there, manning it, then laying and firing it. False when it has
-- none (or just lost it): its own think goes on.
function Crew.think(b: any, now: number): boolean
	local m = b.m :: Model?
	if not m then
		return false
	end
	local on = Artillery.gunOf(m)
	local g = gunning[b]
	if on then
		if not g then
			g = { m = m, since = now, retargetAt = 0 }
			gunning[b] = g
		end
		local info = infoOf(on, now)
		if info then
			seated(b)
			if b.anim then
				b.anim.update(0, "none", 0)
			end
			if info.mg then
				mg(b, g :: Gunning, info, now)
			else
				shell(b, g :: Gunning, info, now)
			end
		end
		return true
	end
	local gun = b.gun :: Model?
	if not gun then
		return false
	end
	local info = infoOf(gun, now)
	if not g or g.m ~= m or not info or not info.free or info.broken then
		release(b) -- (a new life, the gun gone, broken or taken)
		return false
	end
	if now - g.since > C.walkFor then
		stats.gaveUp += 1
		release(b, C.kicked)
		return false
	end
	local root = b.root :: BasePart
	local humanoid = b.humanoid :: Humanoid
	local away = flat(info.crew - root.Position).Magnitude
	if away <= info.reach * 0.8 and Artillery.manAs(m, gun) then
		seated(b)
		return true
	end
	ctx.finish(b)
	ctx.dropCast(b)
	ctx.setGoal(b, info.crew, now)
	ctx.follow(b, now)
	if b.turn then
		(b.turn :: AlignOrientation).Enabled = false
	end
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = if away > Cfg.Move.SprintFrom then M.SprintSpeed else M.WalkSpeed
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if b.anim then
		b.anim.update(
			speed,
			if speed > Loco.SprintAbove then "carry" elseif speed > Loco.IdleBelow then "walk" else "ready",
			0
		)
	end
	return true
end

-- `side`'s commander tick: its free guns on the sectors it holds given gunners (its defenders and Engineers on gun
-- duty), and its targets: the enemies its squads know (`known`) in groups, and the sector to fall back on
function Crew.command(side: string, owner: { string }, known: { Vector3 }, fallback: Vector3?)
	local now = os.clock()
	local have = 0
	local taken: { [Model]: boolean } = {}
	for _, b in ctx.bots do
		if b.side == side and b.gun then
			if not ctx.alive(b) or b.deadAt then
				release(b)
			else
				have += 1
				taken[b.gun] = true
			end
		end
	end
	local guns, gunModels = {}, {}
	for _, g in Artillery.list() do
		if
			g.free
			and not g.broken
			and not taken[g.model]
			and now >= (blindUntil[g.model] or 0)
			and g.model.Parent ~= nil
			and ownerAt(g.crew, owner) == side
		then
			table.insert(guns, { x = g.crew.X, z = g.crew.Z })
			table.insert(gunModels, g.model)
		end
	end
	if #guns > 0 and have < C.max then
		local gunners, gunnerBots = {}, {}
		for _, b in ctx.bots do
			local m = b.m :: Model?
			if
				b.side == side
				and m
				and ctx.alive(b)
				and not b.deadAt
				and not b.gun
				and not b.act
				and (b.order == "Defend" or b.crew)
				and now >= (b.gunWait or 0)
				and m:GetAttribute(FrontCfg.HoldAttribute) == nil
				and b.root
			then
				local p = (b.root :: BasePart).Position
				table.insert(gunners, { x = p.X, z = p.Z, crew = b.crew == true })
				table.insert(gunnerBots, b)
			end
		end
		for gi, bi in Rules.assign(guns, gunners, C.max - have, C) do
			local b = gunnerBots[bi]
			b.gun = gunModels[gi]
			gunning[b] = { m = b.m, since = now, retargetAt = 0 }
			b.post, b.postKind, b.postFloor, b.postFace = nil, nil, nil, nil
			stats.given += 1
		end
	end
	local pts = {}
	for _, p in known do
		table.insert(pts, { x = p.X, z = p.Z })
	end
	-- (each group's middle at the height of its nearest known enemy)
	local groups = {}
	for _, grp in Rules.groups(pts, C.cluster) do
		local y, bestD = 0, math.huge
		for _, p in known do
			local d = (p.X - grp.x) ^ 2 + (p.Z - grp.z) ^ 2
			if d < bestD then
				y, bestD = p.Y, d
			end
		end
		table.insert(groups, Vector3.new(grp.x, y, grp.z))
	end
	targets[side] = { groups = groups, fallback = fallback }
end

-- The report's piece: gunners on guns and walking to them, and what they did since the last
function Crew.report(): string
	local on, walking = 0, 0
	for _, b in ctx.bots do
		if b.m and Artillery.gunOf(b.m) then
			on += 1
		elseif b.gun then
			walking += 1
		end
	end
	local s = string.format(
		"crew %d manned, %d walking, %d given, %d gave up, %d shells, %d MG bursts, %d held (own near), %d taken over, %d blocked looks, %d left blind",
		on,
		walking,
		stats.given,
		stats.gaveUp,
		stats.shells,
		stats.bursts,
		stats.held,
		stats.kicked,
		stats.blocked,
		stats.blinded
	)
	for k in stats do
		stats[k] = 0
	end
	return s
end

-- The admin panel (Bots.dev "Gun"): bot `b` given `gun` now, as the commander gives one
function Crew.give(b: any, gun: Model)
	release(b)
	b.gun = gun
	gunning[b] = { m = b.m, since = os.clock(), retargetAt = 0 }
	b.post, b.postKind, b.postFloor, b.postFace = nil, nil, nil, nil
	stats.given += 1
end

-- A new match: every gunner back to duty
function Crew.clear()
	for _, b in ctx.bots do
		b.gun, b.gunWait = nil, nil
		gunning[b] = nil
	end
	table.clear(targets)
end

function Crew.init(c: Context)
	ctx = c
	Artillery.onBotLeft(function(model: Model, _gun: Model, why: string)
		for _, b in ctx.bots do
			if b.m == model then
				if why == "Kicked" then
					stats.kicked += 1
				end
				release(b, if why == "Kicked" then C.kicked else nil)
				return
			end
		end
	end)
end

return Crew
