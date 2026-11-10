--!strict
-- The bots' log line (Config/Bots.ReportEvery), the admin panel's labels over them and its bot tests (Bots.dev),
-- kept out of src/server/Bots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local Build = require(Shared.Config.Build)
local DevCfg = require(Shared.Config.DevTools)
local FrontCfg = require(Shared.Config.Frontline)
local W = require(Shared.Config.Weapons)
local Net = require(Shared.Net)
local Map = require(Shared.LiveMap).map -- (the match's map)
local BotBuild = require(Shared.Rules.BotBuild)
local BotTrenches = require(Shared.Rules.BotTrenches)
local BotWait = require(Shared.Rules.BotWait)
local MapTerrain = require(Shared.Rules.MapTerrain)
local Trenches = require(script.Parent.Parent.Trenches)
local BuildServer = require(script.Parent.Parent.Build)
local Artillery = require(script.Parent.Parent.Artillery)
local Damage = require(script.Parent.Parent.Damage)
local Indoors = require(script.Parent.Parent.Indoors)
local Ragdoll = require(script.Parent.Parent.Ragdoll)
local Animate = require(script.Parent.Animate)
local Routes = require(script.Parent.Routes)

local Types = require(script.Parent.Types)
type Bot = Types.Bot

local State = require(script.Parent.State)
local bots, Tactics, random, stats, squads, buildLists, fronts, rescue =
	State.bots, State.Tactics, State.random, State.stats, State.squads, State.buildLists, State.fronts, State.rescue

local Move = require(script.Parent.Move)
local flat, alive, finish = Move.flat, Move.alive, Move.finish

local Act = require(script.Parent.Act)

local function report(now: number, governor: { cap: number })
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
			"[Bots] %d bots (W %d, E %d; %d alive: %s; cap %d): frame avg %.3f ms, p95 %.3f ms, max %.2f ms; think %.3f ms avg, %.2f ms max; %d frames out of time; %.1f rays/frame, %d sights put off; %.1f paths/s (%d failed, %d put off, %d shared); %d stuck, %d sidesteps; %d bodies taken back, %d stood up; %d squads pushed in, %d covering shots, roles %s; %d callouts (%.1f/min); %d grenades, %d heals, %d drags; %d laid, %d swings, %d refused, %d jobs open; trenches %d runs planned, %d on fire steps, %d in reserve, %d lines lost; cover %d piles pinned down, %d breastworks, %d walls, %d moved off trench lines; trench ways %d tear-down swings, %d runs swung round; %d saps, %d sap runs dug, %d given up; %d squads pressed on out of the open; by trench %d danger paths, %d down into trenches, %d over the top; work %d jobs taken, %d started safe, %d stopped by danger, %d left with no way there, %d with no swing, %d begun and broken off, %d out of reach for the side, %d idle resets, waits %d in trenches, %d in cover, %d spread out, %d where they stood, %d teammates guarded first, %d rescues claimed, %d let go; front %d moved on, %d contacts, %d parallels, runs %d zig-zag, %d straight; team %d pushes (%d grenades first), %d butt strokes, %d shots held (no line), %d spread steps, %d wire spots moved, %d swings waited; dugouts %d planned (%d squares without the ground), %d sheltered, %d came up, %d lifted out, %d bombed out; foxholes %d dug (%d pinned), %d into one; staff %d/%d/%d casts, %d dropped, %d held off its own cover; %d doors opened (%d walked into, %d paths again after a swing, %d doorway spots behind a door, %d steps along a flight), %d waypoints walked on between thinks, %d at windows, %d squads clearing; %d shots, %d deaths, %d covers found, %d peeks, %d upgrades; %s; %s; %s; %d saps due, %d at a ford; to the zone %.1f s avg (%d); physics %.0f fps, heartbeat %.2f ms; thinking near %d, middle %d, distant %d; sending %.0f KB/s",
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
			stats.callouts * 60 / math.max(span, 1),
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
			stats.pinnedPiles,
			stats.breastworks,
			stats.walls,
			stats.keptOff,
			stats.torn,
			stats.around,
			stats.saps,
			stats.sapRuns,
			stats.sapsFailed,
			stats.pressed,
			stats.dangerPaths,
			stats.intoTrench,
			stats.overTop,
			stats.workTaken,
			stats.workStarted,
			stats.workStopped,
			stats.workStalled,
			stats.workNoSwing,
			stats.workFlapped,
			stats.workOutOfReach,
			stats.idleResets,
			stats.waitTrench,
			stats.waitCover,
			stats.waitSpread,
			stats.waitHere,
			stats.guarded,
			stats.rescues,
			stats.rescuesLet,
			stats.movedOn,
			stats.contacts,
			stats.parallels,
			stats.zigzags,
			stats.straights,
			stats.pushes,
			stats.pushBombs,
			stats.strikes,
			stats.blocked,
			stats.spread,
			stats.wireMoved,
			stats.waited,
			stats.dugouts,
			stats.dugoutsRefused,
			stats.sheltered,
			stats.cameUp,
			stats.dugLifted,
			stats.bombed,
			stats.holes,
			stats.pinnedHoles,
			stats.intoHole,
			stats.casts1,
			stats.casts2,
			stats.casts3,
			stats.dropped,
			stats.selfHits,
			stats.doors,
			stats.doorsBumped,
			stats.doorRepaths,
			Indoors.behind,
			stats.stairSteps,
			stats.arrivals,
			windows,
			clearing,
			stats.shots,
			stats.deaths,
			stats.covers,
			stats.peeks,
			stats.upgrades,
			Tactics.crew.report(),
			Tactics.fell.report(),
			fronts.summary or "no offensives",
			stats.sapsDue,
			stats.sapFords,
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

-- the admin panel's labels over the bots (Config/DevTools.Admin.BotState), once a commander tick while asked for; taken
-- off once it is off
-- who rescues whom now, for the admin panel's readout (Config/DevTools.Admin.BotRescuesAttribute); claims on bodies
-- gone and old let-gos dropped
local function rescues()
	local lines = {}
	for c, cl in rescue.claims do
		if not c.Parent then
			rescue.claims[c] = nil
		else
			local r = cl.by
			local doing = if r.act and r.act.who == c then r.act.kind else "covering"
			table.insert(lines, `{r.name} > {c.Name} ({doing})`)
		end
	end
	local now = os.clock()
	for c, at in rescue.freed do
		if not c.Parent or now - at > Cfg.Actions.Rescue.wait then
			rescue.freed[c] = nil
		end
	end
	table.sort(lines)
	workspace:SetAttribute(DevCfg.Admin.BotRescuesAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each side's bot classes now, for the admin panel's readout (Config/DevTools.Admin.BotClassesAttribute)
local function classMix()
	local by: { [string]: { [string]: number } } = {}
	for _, b in bots do
		local class = b.m and b.side and (b.m :: Model):GetAttribute("Class")
		if type(class) == "string" then
			local side = by[b.side :: string] or {}
			by[b.side :: string] = side
			side[class] = (side[class] or 0) + 1
		end
	end
	local lines = {}
	for _, side in { "West", "East" } do
		local parts = {}
		for _, c in Cfg.Classes do
			local n = by[side] and by[side][c.key]
			if n then
				table.insert(parts, `{c.key} {n}`)
			end
		end
		if #parts > 0 then
			table.insert(lines, `{side}: {table.concat(parts, ", ")}`)
		end
	end
	workspace:SetAttribute(DevCfg.Admin.BotClassesAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each side's Engineer bots: what each builds, or why nothing (Config/DevTools.Admin.BotEngineersAttribute)
local function engineers()
	local lines = {}
	for _, side in { "West", "East" } do
		local parts = {}
		for _, b in bots do
			local m = b.m
			if m and b.side == side and m:GetAttribute("Class") == "Engineer" then
				local act = b.act
				local what = if act and act.job
					then `building {act.job.job.key}`
					elseif act then act.kind
					elseif b.gun or Artillery.gunOf(m) then "on a gun"
					elseif b.work then `{b.workState or "going"} to {b.work.job.job.key}`
					else (b.buildWhy or "not weighed yet")
				table.insert(parts, `{b.name}: {what}`)
			end
		end
		if #parts > 0 then
			table.insert(lines, `{side}: {table.concat(parts, "; ")}`)
		end
		local sb = buildLists[side]
		if sb and sb.gunNote then
			table.insert(lines, `{side} guns: {sb.gunNote}`)
		end
		-- (its guns in its front sector against its share there, captured ones it uses counted: Config/Bots.Build.caps)
		if sb and sb.inFront then
			local had = {}
			for _, key in { "FieldGun", "Howitzer", "MGNest" } do
				table.insert(had, `{key} {sb.inFront[key] or 0}/{Cfg.Build.caps[key] or 0}`)
			end
			table.insert(lines, `{side} front sector guns (share): {table.concat(had, ", ")}`)
		end
		-- (the guns on its ground it looked at: src/server/Bots/Crew.judge)
		if Tactics.crew.judged[side] then
			table.insert(lines, `{side} captured look: {Tactics.crew.judged[side]}`)
		end
		-- (its gun jobs refused where they were to go, and why: Build.placeAs)
		local refusedGuns = {}
		for _, r in if sb then sb.lay else {} do
			local key = r.base.key
			if (key == "FieldGun" or key == "Howitzer" or key == "MGNest") and r.why and not r.model then
				table.insert(refusedGuns, `{key} {r.why}{if r.gaveUp then " (gave up for now)" else ""}`)
			end
		end
		if #refusedGuns > 0 then
			table.insert(lines, `{side} gun jobs refused: {table.concat(refusedGuns, "; ")}`)
		end
	end
	-- (the last shells' miss, bots' and players' alike: Config/Artillery `miss`)
	local shots = {}
	for _, m in Artillery.misses() do
		table.insert(shots, `{m.key} {if m.bot then "bot" else "player"} {math.round(m.off)}`)
	end
	if #shots > 0 then
		table.insert(lines, `Shells off their aim (studs, newest first): {table.concat(shots, ", ")}`)
	end
	workspace:SetAttribute(DevCfg.Admin.BotEngineersAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- every bot with a build job, the longest without a swing landed first (Config/DevTools.Admin.BotJobsAttribute)
local function jobs()
	local A = DevCfg.Admin
	local now = os.clock()
	local rows = {}
	for _, b in bots do
		local act = b.act
		local r = if act and act.job then act.job elseif b.work then b.work.job else nil
		local n = b.jobNote
		if r and n and n.job == r and b.m and alive(b) then
			local state = if act and act.job then "working" else (b.workState or "going")
			local on, idle = math.floor(now - n.since), math.floor(now - n.landed)
			local line = `{b.name} ({b.side or "?"}) {r.job.key} {state}: on it {on}s, no swing {idle}s, `
				.. `began {n.starts}, broke off {n.stops}, swings {n.swings}, last: {n.why}`
			table.insert(rows, { idle = now - n.landed, line = line })
		end
	end
	table.sort(rows, function(x, y)
		return x.idle > y.idle
	end)
	local lines = {}
	for i = 1, math.min(#rows, A.jobsShown) do
		table.insert(lines, rows[i].line)
	end
	workspace:SetAttribute(A.BotJobsAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each side's fighting plan and what its attacking squads do (Config/DevTools.Admin.BotFrontAttribute)
local function frontLine()
	local lines = {}
	for _, side in { "West", "East" } do
		local fs = fronts.sides[side]
		if fs then
			local parts = {}
			for _, sq in squads do
				if sq.side == side and sq.approach then
					local lane = if sq.flank == -1
						then "left flank"
						elseif sq.flank == 1 then "right flank"
						elseif sq.lane == 0 then "centre"
						else "side"
					local sap = sq.sap
					local doing = if sap and sap.parallel
						then "parallel"
						elseif sap then `sap run {sap.k}`
						elseif sq.jump then "jump-off"
						else string.lower(sq.sq.phase)
					table.insert(parts, `S{sq.sector} {lane}: {doing}`)
				end
			end
			table.sort(parts)
			local plan = fs.plan .. (if fs.forced then " (forced)" else "") .. (if fs.note then `, {fs.note}` else "")
			table.insert(lines, `{side} {plan}: {if #parts > 0 then table.concat(parts, "; ") else "no attack"}`)
		end
	end
	workspace:SetAttribute(DevCfg.Admin.BotFrontAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each squad (Config/DevTools.Admin.BotSquadsAttribute): its side, order and sector, phase, what it is doing, how long
-- its middle has stood still, shot at or not, and its members in cover (user 2026-11-04: "bot groups often stay in
-- place")
local function squadLines()
	local now = os.clock()
	local lines = {}
	for _, sq in squads do
		local members, alive2, order = 0, 0, "Attack"
		local sum = Vector3.zero
		for _, b in bots do
			if b.squad and squads[b.squad :: string] == sq then
				members += 1
				order = b.order or order
				if alive(b) and b.root then
					alive2 += 1
					sum += (b.root :: BasePart).Position
				end
			end
		end
		-- where it is and where it gathers (its jump-off, else its approach spot), x and z, and how far apart
		local where = ""
		local gather: Vector3? = sq.jump or sq.gather or sq.approach
		if alive2 > 0 then
			local m = sum / alive2
			where = ` at {math.floor(m.X)},{math.floor(m.Z)}`
			if gather then
				local g = gather :: Vector3
				local off = Vector3.new(g.X - m.X, 0, g.Z - m.Z).Magnitude
				where ..= `, gathers at {math.floor(g.X)},{math.floor(g.Z)} ({math.floor(off)} studs)`
			end
		end
		if members > 0 then
			local sap = sq.sap
			local doing = if sq.pressUntil and now < sq.pressUntil
				then "pressing on"
				elseif sap and sap.parallel then "parallel"
				elseif sap then `sap run {sap.k}`
				elseif sq.jump then "jump-off"
				elseif sq.noSapUntil and now < sq.noSapUntil then "sap given up"
				else "-"
			local still = if sq.stillAt then math.floor(now - sq.stillAt) else 0
			local shot = sq.firedAt ~= nil and now - sq.firedAt < Cfg.Brain.ThreatMemory
			table.insert(
				lines,
				`{sq.side} {order} S{sq.sector}: {string.lower(sq.sq.phase)}, {doing}, still {still}s{if shot
					then ", SHOT AT"
					else ""}, cover {sq.inCover or 0}/{alive2}{where}`
			)
		end
	end
	table.sort(lines)
	workspace:SetAttribute(DevCfg.Admin.BotSquadsAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each side's latest runs toward the enemy: straight or a zig-zag, and why (Config/DevTools.Admin.BotRunsAttribute)
local function runLines()
	local lines = {}
	for _, side in { "West", "East" } do
		local sb = buildLists[side]
		if sb and #sb.runNotes > 0 then
			table.insert(lines, `{side}: {table.concat(sb.runNotes, "; ")}`)
		end
		-- (the shape of its trenches: joints, sharp joints and short squares, bots' and players'; bot plans refused for
		-- a sharp bend; Config/Bots.Trenches.Shape)
		local SH = Cfg.Trenches.Shape
		local kit: string? = nil
		for _, b in bots do
			if b.side == side and b.kit then
				kit = b.kit
				break
			end
		end
		local sh = Trenches.shapes(kit or side, SH.sharp, SH.short)
		local bent = State.ByTrench.runs[`{side} refused: Too sharp a bend`] or 0
		table.insert(
			lines,
			`{side} shape: bots {sh.bots.joints} joints, {sh.bots.sharp} sharp, {sh.bots.short} short; players {sh.players.joints}/{sh.players.sharp}/{sh.players.short}; bot plans refused sharp {bent}`
		)
	end
	workspace:SetAttribute(DevCfg.Admin.BotRunsAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- what a bot is doing now (the admin panel's "What bots are doing"), and why, when it is doing nothing
local DOING = {
	"fighting",
	"digging",
	"reinforcing",
	"building",
	"crewing",
	"tending",
	"moving",
	"stood to",
	"assaulting",
	"on guard",
	"holding",
	"waiting",
	"idle",
}
local function doing(b: Bot, now: number): (string, string?)
	local m = b.m :: Model
	if m:GetAttribute(FrontCfg.HoldAttribute) ~= nil then
		return "waiting" -- (the wave line)
	end
	if b.gun or Artillery.gunOf(m) then
		return "crewing"
	end
	local a = b.act
	-- (at its job, between swings too)
	local r: any = if a and a.kind == "Build"
		then a.job
		elseif not a and b.work and b.workState == "working" then b.work.job
		else nil
	if r then
		local key = r.job.key
		if key == "Trench" or key == "Foxhole" then
			return if r.reinforce or r.care then "reinforcing" else "digging"
		end
		return "building"
	elseif a and a.kind ~= "Build" then
		return "tending"
	end
	local state = b.brain.state
	if
		b.sight == "sees"
		or state == "Cover"
		or state == "Peek"
		or state == "Retreat"
		or now - (b.threatAt or -math.huge) < Cfg.Build.calm
	then
		return "fighting"
	end
	local root = b.root :: BasePart
	if flat(root.AssemblyLinearVelocity).Magnitude > 2 then
		return "moving"
	end
	local still = if b.stillSince then now - b.stillSince :: number else 0
	local sb = b.side and buildLists[b.side :: string]
	if sb and sb.standTo and b.postFloor ~= nil then
		return "stood to"
	end
	if still < Cfg.Build.Duty.after then
		return "holding"
	end
	if b.work then
		return "idle", `at a stop on its way to its job ({b.workState or "?"})`
	end
	if b.buildWhy == "pushing" then
		return "assaulting" -- (its squad's assault, stopped where it got to)
	end
	if b.role == "Hold" and b.buildWhy and string.sub(b.buildWhy, 1, 12) == "none within " then
		return "on guard" -- (a digger or Engineer on hold, no work within its reach)
	end
	return "idle", b.buildWhy or "no job looked for"
end

local function activityLines(now: number)
	local lines = {}
	local ByTrench = State.ByTrench
	for _, side in DevCfg.Admin.Sides do
		local tally = ByTrench.activity[side]
		if not tally then
			tally = {}
			ByTrench.activity[side] = tally
		end
		local idle = {}
		local nowIdle = 0
		for _, b in bots do
			if b.side == side and alive(b) then
				local what, why = doing(b, now)
				tally[what] = (tally[what] or 0) + 1
				if what == "idle" then
					nowIdle += 1
					local whys = ByTrench.idleWhy[side]
					if not whys then
						whys = {}
						ByTrench.idleWhy[side] = whys
					end
					whys[why :: string] = (whys[why :: string] or 0) + 1
					if #idle < 6 then
						table.insert(idle, `{b.name} ({b.role or "-"}): {why}`)
					end
				end
			end
		end
		local all = 0
		for _, n in tally do
			all += n
		end
		local parts = {}
		for _, what in DOING do
			table.insert(parts, `{what} {math.floor(100 * (tally[what] or 0) / math.max(all, 1) + 0.5)}%`)
		end
		table.insert(lines, `{side}: {table.concat(parts, ", ")}`)
		if nowIdle > 0 then
			table.insert(lines, `  idle now {nowIdle}: {table.concat(idle, "; ")}`)
		end
		local whys = ByTrench.idleWhy[side]
		if whys then
			local list = {}
			for why, n in whys do
				table.insert(list, { why = why, n = n })
			end
			table.sort(list, function(x, y)
				return x.n > y.n
			end)
			local top = {}
			for k = 1, math.min(4, #list) do
				table.insert(top, `{list[k].why} {list[k].n}`)
			end
			table.insert(lines, `  idle why: {table.concat(top, "; ")}`)
		end
		local seen = ByTrench.inSight[side]
		if seen then
			local total = 0
			for _, s in seen do
				total += s
			end
			local bits = {}
			for _, what in { "fired", "between shots", "loading", "reacting", "turning", "blocked", "not aiming" } do
				table.insert(bits, `{what} {math.floor(100 * (seen[what] or 0) / math.max(total, 1) + 0.5)}%`)
			end
			table.insert(lines, `  enemy in sight {math.floor(total)} bot-s: {table.concat(bits, ", ")}`)
		end
	end
	workspace:SetAttribute(DevCfg.Admin.BotActivityAttribute, table.concat(lines, "\n"))
end

-- where each side's holders, MG nests and guns are (Config/DevTools.Admin.Spots; Config/Bots.OffPoint), and the map's
-- marked spots drawn while the admin panel's toggle is on
local Marks: { [number]: any } = (if (Map :: any).legs then MapTerrain.tactics(Map) else (Map :: any).tactics) or {}
local function nearSector(x: number, z: number): (any, number)
	local best, bestD = nil, math.huge
	for _, s in Map.sectors do
		local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
		if d < bestD then
			best, bestD = s, d
		end
	end
	return best, bestD
end
local spotsDrawn = false
local function spotLines()
	local OP = Cfg.OffPoint
	local lines = {}
	for _, side in DevCfg.Admin.Sides do
		local h = State.ByTrench.holders[side]
		if not h then
			h = { all = 0, flag = 0, zone = 0 }
			State.ByTrench.holders[side] = h
		end
		local kit: string? = nil
		for _, b in bots do
			if b.side == side and alive(b) then
				kit = kit or b.kit
				if b.role == "Hold" then
					local p = (b.root :: BasePart).Position
					local s, d = nearSector(p.X, p.Z)
					h.all += 1
					h.flag += if d < OP.clear then 1 else 0
					h.zone += if d <= s.radius then 1 else 0
				end
			end
		end
		-- (where its living bots stand now and this match, and what those behind its front do there: Rules/BotBuild.whereIs)
		local owners = fronts.owners
		local front = if owners then BotBuild.front(Map.sectors, owners, side) else nil
		local where = State.ByTrench.where[side] or {}
		State.ByTrench.where[side] = where
		local whyBehind = State.ByTrench.behindWhy[side] or {}
		State.ByTrench.behindWhy[side] = whyBehind
		local nowWhere: { [string]: number } = { front = 0, behind = 0, ahead = 0 }
		local now = os.clock()
		for _, b in bots do
			local m = b.m
			if b.side == side and m and alive(b) and owners then
				local p = (b.root :: BasePart).Position
				local at, best = nil, math.huge
				for i, s in Map.sectors do
					local d = (s.x - p.X) ^ 2 + (s.z - p.Z) ^ 2
					if d < best then
						at, best = i, d
					end
				end
				local w = BotBuild.whereIs(at, front, owners, side)
				nowWhere[w] += 1
				where[w] = (where[w] or 0) + 1
				if w == "behind" then
					local job = if b.act and b.act.job then b.act.job elseif b.work then b.work else nil
					local why = if Artillery.gunOf(m)
						then "manning a gun"
						elseif b.gun then "walking to a gun"
						elseif job and job.fix then "fixing a gun"
						elseif job and job.job.key == "Trench" then "digging"
						elseif job then "building"
						elseif b.pioneer then "pioneer"
						elseif now - b.spawnedAt < 30 then "just spawned"
						elseif b.sector and b.sector ~= at then "walking to its order"
						else `other ({b.order or "-"} {b.role or "-"})`
					whyBehind[why] = (whyBehind[why] or 0) + 1
				end
			end
		end
		local seen = math.max((where.front or 0) + (where.behind or 0) + (where.ahead or 0), 1)
		local whys = {}
		for why, n in whyBehind do
			table.insert(whys, { why = why, n = n })
		end
		table.sort(whys, function(a, b)
			return a.n > b.n
		end)
		local whyText = {}
		for _, e in whys do
			table.insert(whyText, `{e.why} {math.floor(100 * e.n / math.max(where.behind or 0, 1) + 0.5)}%`)
		end
		local whereNote =
			`bots now: {nowWhere.front} at its front S{front or "-"}, {nowWhere.behind} behind it, {nowWhere.ahead} ahead; this match {math.floor(
				100 * (where.front or 0) / seen + 0.5
			)}% front, {math.floor(100 * (where.behind or 0) / seen + 0.5)}% behind, {math.floor(
				100 * (where.ahead or 0) / seen + 0.5
			)}% ahead; behind: {table.concat(whyText, ", ")}`
		-- (how near its living bots stand to their nearest teammate, by role, now and this match: Rules/BotWait.nearest)
		local pts, roles = {}, {}
		for _, b in bots do
			if b.side == side and b.m and alive(b) then
				local p = (b.root :: BasePart).Position
				table.insert(pts, { x = p.X, z = p.Z })
				table.insert(roles, if b.role == "Hold" then `Hold {b.postKind or "-"}` else b.role or "none")
			end
		end
		local gaps = State.ByTrench.gaps[side] or {}
		State.ByTrench.gaps[side] = gaps
		local nowGaps: { [string]: { number } } = {}
		for k, d in BotWait.nearest(pts) do
			local g = gaps[roles[k]] or { n = 0, under4 = 0, under8 = 0 }
			gaps[roles[k]] = g
			g.n += 1
			g.under4 += if d < 4 then 1 else 0
			g.under8 += if d < 8 then 1 else 0
			nowGaps[roles[k]] = nowGaps[roles[k]] or {}
			table.insert(nowGaps[roles[k]], d)
		end
		local gapText = {}
		for role, g in gaps do
			local list = nowGaps[role] or {}
			table.sort(list)
			local mid = list[math.max(math.ceil(#list / 2), 1)]
			table.insert(
				gapText,
				`{role} {if mid and mid < math.huge then math.floor(mid + 0.5) else "-"} now, this match {math.floor(
					100 * g.under4 / math.max(g.n, 1) + 0.5
				)}% under 4, {math.floor(100 * g.under8 / math.max(g.n, 1) + 0.5)}% under 8`
			)
		end
		table.sort(gapText)
		local gapNote = `nearest teammate (studs, middle): {table.concat(gapText, "; ")}`
		local nests, guns, onFlag, marked, frames = 0, 0, 0, 0, 0
		local nestsAt = {}
		for _, w in if kit then BuildServer.worksOf(kit) else {} do
			frames += if w.key == "MGNest" and not w.built then 1 else 0
			if w.key == "MGNest" then
				table.insert(nestsAt, { x = w.at.X, z = w.at.Z })
			end
			if w.built and (w.key == "MGNest" or w.key == "FieldGun" or w.key == "Howitzer") then
				nests += if w.key == "MGNest" then 1 else 0
				guns += if w.key == "MGNest" then 0 else 1
				local _, d = nearSector(w.at.X, w.at.Z)
				onFlag += if d < OP.clear then 1 else 0
				local found = false
				for _, t in Marks do
					for _, sp in if w.key == "MGNest" then t.mg else t.guns do
						found = found or (sp.x - w.at.X) ^ 2 + (sp.z - w.at.Z) ^ 2 <= OP.nestGap ^ 2
					end
				end
				marked += if found then 1 else 0
			end
		end
		local n = math.max(h.all, 1)
		-- (its nests, standing or going up: the nearest two, the pairs within Build.Nest.gap, and the spots passed over
		-- for that this match: Rules/BotBuild.spaced)
		local gap = Cfg.Build.Nest.gap
		local near, tight = BotBuild.closest(nestsAt, gap)
		-- (its guns out of service: its own being fixed, its own left for being of no use, the enemy's it uses being
		-- fixed: Crew.useful, Crew.fixes)
		local bk = Tactics.crew.broken[side] or { fixing = 0, left = 0, captured = 0 }
		local brokenNote =
			`broken guns: {bk.fixing} of its own to fix, {bk.left} of its own left (can't reach the enemy), {bk.captured} captured to fix; of no use: {table.concat(
				Tactics.crew.useless(side),
				", "
			)}`
		local spacing = if near
			then `nearest two {math.floor(near + 0.5)} studs apart, {tight} pairs within {gap}`
			else "fewer than two"
		table.insert(
			lines,
			`{side}: holders this match {math.floor(100 * h.flag / n + 0.5)}% within {OP.clear} studs of a flag, {math.floor(
				100 * h.zone / n + 0.5
			)}% in a zone; {nests} MG nests ({frames} more going up, {Tactics.crew.nestsOut[side] or 0} at its front too far from the fight to count; {spacing}; {Tactics.crew.nestsTight[side] or 0} spots passed over too close), {guns} guns standing, {marked} of them on marked spots, {onFlag} within {OP.clear} of a flag; {brokenNote}; {whereNote}; {gapNote}`
		)
	end
	workspace:SetAttribute(DevCfg.Admin.Spots.readout, table.concat(lines, "\n"))
	local A = DevCfg.Admin.Spots
	local on = workspace:GetAttribute(A.attribute) == true
	if on == spotsDrawn then
		return
	end
	spotsDrawn = on
	local old = workspace:FindFirstChild(A.folder)
	if old then
		old:Destroy()
	end
	if not on then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = A.folder
	for _, t in Marks do
		for kind, c in A.colors do
			for _, sp in t[kind] or {} do
				local x, z = sp.x or (sp.ax + sp.bx) / 2, sp.z or (sp.az + sp.bz) / 2
				local part = Instance.new("Part")
				part.Shape = Enum.PartType.Ball
				part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
				part.Material = Enum.Material.Neon
				part.Color = Color3.fromRGB(c[1], c[2], c[3])
				part.Size = Vector3.one * A.size
				part.Position = Routes.ground(x, z) + Vector3.yAxis * A.size
				part.Parent = folder
			end
		end
	end
	folder.Parent = workspace
end

-- how each side's machine guns fire and what they do to the other side (Config/DevTools.Admin.BotMGs; Config/Bots.Crew.MG,
-- Fear, Arcs), and, while it is on, each gun's line of fire and the arcs known drawn
local function mgLines()
	local T = DevCfg.Admin.BotMGs
	local lines = {}
	local fire = Tactics.crew.mgCounts()
	local now = os.clock()
	for _, side in DevCfg.Admin.Sides do
		local enemy = if side == "West" then "East" else "West"
		local f = fire[side]
			or {
				seen = 0,
				area = 0,
				known = 0,
				manned = 0,
				noArea = 0,
				far = 0,
				left = 0,
				why = { range = 0, own = 0, lay = 0, ground = 0 },
			}
		local t = fronts.mg[side] or { pinned = 0, far = 0, detours = 0, walked = 0 }
		local far = Cfg.Crew.MG.far
		local d = State.ByTrench.deaths[enemy] or { all = 0, trench = 0, shell = 0, zone = 0, mg = 0 }
		local rounds = f.seen + f.area
		local known = 0
		for _, arc in fronts.arcs[side] or {} do
			known += if now - arc.at <= Cfg.Crew.Arcs.forget then 1 else 0
		end
		table.insert(
			lines,
			`{side}: {rounds} rounds ({f.seen} at seen targets, {f.area} at areas, {f.known} of those where enemies were known, {f.far} from past {far} studs; {f.noArea} looks found no area; areas passed over: {f.why.range} out of range, {f.why.own} own side in the line, {f.why.lay} gun can't lay, {f.why.ground} ground in the way), {math.floor(
				rounds / math.max(f.manned, 1) * 60
			)} a minute per manned MG, {math.floor(f.manned)} s manned, {f.left} gunners left a gun with nothing to fire at; killed {d.mg} of {enemy} ({if d.all
					> 0
				then math.floor(100 * d.mg / d.all + 0.5)
				else 0}%). Under fire: pinned {t.pinned} times ({t.far} from past {far} studs), knows {known} arcs, went round {t.detours} times, walked into one {t.walked} times`
		)
	end
	workspace:SetAttribute(T.readout, table.concat(lines, "\n"))
	local old = workspace:FindFirstChild(T.folder)
	if old then
		old:Destroy()
	end
	if workspace:GetAttribute(T.attribute) ~= true then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = T.folder
	local function line(from: Vector3, to: Vector3, c: { number })
		local part = Instance.new("Part")
		part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(c[1], c[2], c[3])
		part.Size = Vector3.new(T.width, T.width, (to - from).Magnitude)
		part.CFrame = CFrame.lookAt((from + to) / 2, to)
		part.Parent = folder
	end
	for _, l in Tactics.crew.mgLines() do
		line(l.from + Vector3.yAxis * 3, l.to, if l.kind == "seen" then T.seen else T.area)
	end
	for _, side in DevCfg.Admin.Sides do
		for gun, arc in fronts.arcs[side] or {} do
			local from = gun:GetPivot().Position + Vector3.yAxis * 3
			for _, sign in { -1, 1 } do
				local a = math.rad(arc.yaw + sign * arc.half)
				line(from, from + Vector3.new(math.sin(a), 0, math.cos(a)) * Cfg.Crew.Arcs.reach, T.arc)
			end
		end
	end
	folder.Parent = workspace
end

-- how each side's offensives go (Config/DevTools.Admin.BotAttacks; Config/Bots.Offensive.Forward, Roll): the match so far,
-- each attacking squad's distance to where it forms up, and those points drawn while the marked spots are
local function attackLines()
	local T = DevCfg.Admin.BotAttacks
	local lines = {}
	local on = workspace:GetAttribute(DevCfg.Admin.Spots.attribute) == true
	local old = workspace:FindFirstChild(T.folder)
	if old then
		old:Destroy()
	end
	local folder = if on then Instance.new("Folder") else nil
	if folder then
		folder.Name = T.folder
	end
	local latest = 0
	for _, sq in squads do
		latest = math.max(latest, sq.seen)
	end
	for _, side in DevCfg.Admin.Sides do
		local A = fronts.attacks[side]
		if A then
			local g = math.max(A.goes, 1)
			table.insert(
				lines,
				`{side}: {A.goes} went, {math.floor(A.toGo / g)} s to Go, {math.floor(100 * A.fill / g)}% gathered, formed up {math.floor(
					A.gatherDist / math.max(A.gatherN, 1)
				)} studs off the zone; {A.waves} waves, {A.sent} squads sent; longest no squad attacking {math.floor(
					A.maxQuiet
				)} s ({math.floor(A.goQuiet)} s from Go); one blast caught at most {A.blastMost}, {A.blast3} caught 3+; {A.lostGather} sectors lost gathering`
			)
			local fs = fronts.sides[side]
			local dists = {}
			for key, sq in squads do
				local off = fs and fs.off
				local at = sq.jump or sq.gather
				if off and sq.side == side and sq.sector == off.sector and at and sq.seen >= latest - 1 then
					local sx, sz, n = 0, 0, 0
					for _, b in bots do
						if b.squad == key and alive(b) then
							local p = (b.root :: BasePart).Position
							sx, sz, n = sx + p.X, sz + p.Z, n + 1
						end
					end
					if n > 0 then
						local spot = at :: Vector3
						local d = math.sqrt((sx / n - spot.X) ^ 2 + (sz / n - spot.Z) ^ 2)
						table.insert(dists, `{math.floor(d)}{if sq.sq.phase == "Assault" then "*" else ""}`)
						if folder then
							local part = Instance.new("Part")
							part.Shape = Enum.PartType.Ball
							part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
							part.Material = Enum.Material.Neon
							part.Color = Color3.fromRGB(T.color[1], T.color[2], T.color[3])
							part.Size = Vector3.one * T.size
							part.Position = spot + Vector3.yAxis * T.size
							part.Parent = folder
						end
					end
				end
			end
			if #dists > 0 then
				table.insert(lines, `  now: studs to gather point {table.concat(dists, ", ")} (* gone in)`)
			end
		end
	end
	if folder then
		folder.Parent = workspace
	end
	workspace:SetAttribute(T.readout, table.concat(lines, "\n"))
end

-- the bots standing still (Config/DevTools.Admin.BotStuckAttribute): alive, not on a gun, at work or on a post, none
-- moved `stuckFor` s
-- (studs over the ground), with what they are doing; where each last moved and when
-- a bot's squad as the stuck readout shows it: its phase, and how far the bot is from its approach spot, waypoint and
-- jump-off
local function squadNote(b: Bot, p: Vector3): string
	local sq = b.squad and squads[b.squad :: string]
	if not sq then
		return "no squad"
	end
	local parts = { `squad {sq.sq.phase}` }
	for _, w in
		{
			{ "approach", sq.approach },
			{ "waypoint", sq.mid },
			{ "jump", sq.jump },
			{ "gather", sq.gather },
			{ "push", sq.push },
		}
	do
		local at = w[2] :: Vector3?
		if at then
			table.insert(parts, `{w[1]} {math.floor(flat(at - p).Magnitude)}`)
		end
	end
	if sq.sap then
		table.insert(parts, "sapping")
	end
	return table.concat(parts, " ")
end

local still: { [Bot]: { at: Vector3, since: number } } = setmetatable({}, { __mode = "k" }) :: any
-- (shuffling about in a few studs, never quite standing still: Config/Bots.Move.Wait.mill)
local milling: { [Bot]: { at: Vector3, since: number } } = setmetatable({}, { __mode = "k" }) :: any
local WT = Cfg.Move.Wait
local function stuckLine()
	local A = DevCfg.Admin
	local now = os.clock()
	local lines = {}
	local points: { BotWait.Point } = {}
	for _, b in bots do
		local root = b.root
		local m = b.m
		if not root or not m or not alive(b) or b.deadAt or b.gun or Artillery.gunOf(m) then
			still[b] = nil
			continue
		end
		local p = (root :: BasePart).Position
		table.insert(points, { x = p.X, z = p.Z })
		-- (standing meant: building, healing or dragging, on its post or at its wait spot)
		local post = b.post
		local wt = b.wait
		if
			b.act
			or (post and flat((post :: Vector3) - p).Magnitude <= 4)
			or (wt and flat(wt.at - p).Magnitude <= 4)
		then
			still[b], milling[b] = nil, nil
			continue
		end
		local mi = milling[b]
		if not mi or flat(p - mi.at).Magnitude > WT.mill.radius then
			milling[b] = { at = p, since = now }
		elseif now - mi.since >= WT.mill.seconds then
			local sv = still[b]
			if not sv or now - sv.since < A.stuckFor then
				local waitNote = if wt
					then `waiting {wt.kind} {math.floor(flat(wt.at - p).Magnitude)} studs off`
					else "no wait"
				table.insert(
					lines,
					`{b.name} milling {math.floor(now - mi.since)}s within {WT.mill.radius} studs, {b.side or "?"} {b.order or "-"} S{b.sector or "-"}, role {b.role or "-"}, brain {b.brain.state}, {waitNote}, {squadNote(
						b,
						p
					)}`
				)
			end
		end
		local s = still[b]
		if not s or flat(p - s.at).Magnitude > 1.5 then
			still[b] = { at = p, since = now }
		elseif now - s.since >= A.stuckFor then
			local act = b.act
			local goal = b.nav.goal
			local parts = {
				`{b.name} {math.floor(now - s.since)}s`,
				`{b.side or "?"} {b.order or "-"} S{b.sector or "-"}`,
				`role {b.role or "-"}`,
				`brain {b.brain.state}`,
				if act then `act {act.kind}{if act.job then " " .. act.job.job.key else ""}` else "no act",
				if b.work then `work {b.workState or "?"} {b.work.job.job.key}` else "",
				if goal then `goal {math.floor(flat((goal :: Vector3) - p).Magnitude)} studs` else "no goal",
				if b.post then `post {math.floor(flat((b.post :: Vector3) - p).Magnitude)} studs` else "",
				if (root :: BasePart).Anchored then "ANCHORED" else "",
				squadNote(b, p),
				if b.stop then `stop {math.floor(flat((b.stop :: Vector3) - p).Magnitude)} studs` else "",
				if b.guard then `guarding {b.guard.who.Name}` else "",
				`path {#b.nav.waypoints} pts{if b.nav.computing then " computing" else ""}`,
				if m:GetAttribute(FrontCfg.HoldAttribute) ~= nil then "held in the wave line" else "",
				`think in {string.format("%.1f", b.nextThink - now)}s`,
				if wt then `waiting {wt.kind} {wt.why}, {math.floor(flat(wt.at - p).Magnitude)} studs off` else "",
			}
			local kept = {}
			for _, x in parts do
				if x ~= "" then
					table.insert(kept, x)
				end
			end
			table.insert(lines, table.concat(kept, ", "))
		end
	end
	local C = WT.clump
	local clumped = BotWait.clumped(points, C.within, C.count)
	if clumped > 0 then
		table.insert(lines, `{clumped} bots in clumps ({C.count}+ others within {C.within} studs)`)
	end
	workspace:SetAttribute(A.BotStuckAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each side's dugouts (Config/DevTools.Admin.BotDugoutsAttribute; Config/Bots.Dugouts.Heat): each one's holders down
-- in it now, how many went down into it this match, how hot it is, and who went last and why; and the holders resting
-- (up to fight after a stay)
local function dugoutLines()
	local HT = Cfg.Dugouts.Heat
	local now = os.clock()
	local lines = {}
	for _, side in { "West", "East" } do
		local sb = buildLists[side]
		local parts = {}
		for i, rm in (if sb then sb.rooms else {}) do
			local inside = 0
			for _, b in bots do
				if b.side == side and b.postKind == "dugout" and b.post == rm.room then
					inside += 1
				end
			end
			local h = BotTrenches.heat(now, rm.x, rm.z, side, Tactics.dug.heat, sb.enemies, HT)
			local u = Tactics.dug.use[rm.model]
			local last = if u then `; last {u.who}: {u.why}` else ""
			table.insert(
				parts,
				string.format("D%d: %d in, used %d, heat %.1f", i, inside, if u then u.count else 0, h) .. last
			)
		end
		local resting = 0
		for _, b in bots do
			if b.side == side and b.dugRest and now < b.dugRest then
				resting += 1
			end
		end
		if sb and (#parts > 0 or sb.digging > 0) then
			table.insert(
				lines,
				`{side} ({sb.digging} to dig, {resting} up from a stay): {if #parts > 0
					then table.concat(parts, " | ")
					else "none standing"}`
			)
		end
	end
	workspace:SetAttribute(DevCfg.Admin.BotDugoutsAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- each side's trench stats (Config/DevTools.Admin.BotTrenchStatsAttribute): its squares dug (and only planned), the
-- dug ones blasts and bullets buried this match, its fire steps and the bots on them, its pioneers, and its bots'
-- deaths: in a trench, in the open, by a shell (Rules/BotTrenches.deathKind)
local captures = { key = nil :: string?, at = 0, what = "" }
local function trenchStats()
	local lines = {}
	for _, side in { "West", "East" } do
		local sb = buildLists[side]
		local dug, planned, pioneers, kit = 0, 0, 0, nil
		-- (reinforced past 100, and their extra on average: Config/Build.Trench.hp.extra)
		local reinforced, extra = 0, 0
		for _, t in (if sb then sb.trench else {}) do
			if t.built then
				dug += 1
			else
				planned += 1
			end
			if t.extra > 0 then
				reinforced += 1
				extra += t.extra
			end
		end
		-- (manned: its listed fire steps with a living bot posted to them; a bot posted to a step the list has dropped
		-- since, its trench lost or the front moved on, counted no more: "3 manned of 2", 2026-11-04 match test)
		local listed: { [Vector3]: boolean } = {}
		for _, tp in (if sb then sb.steps else {}) do
			listed[tp.pos] = true
		end
		local manned: { [Vector3]: boolean } = {}
		for _, b in bots do
			if b.side == side then
				kit = kit or b.kit
				if b.postKind == "step" and not b.deadAt and b.post and listed[b.post :: Vector3] then
					manned[b.post :: Vector3] = true
				end
				pioneers += if b.pioneer then 1 else 0
			end
		end
		local onStep = 0
		for _ in manned do
			onStep += 1
		end
		local d = State.ByTrench.deaths[side] or { all = 0, trench = 0, shell = 0, zone = 0, mg = 0 }
		local function pct(n: number): string
			return if d.all > 0 then `{math.floor(n / d.all * 100 + 0.5)}%` else "-"
		end
		table.insert(
			lines,
			`{side}: {dug} dug ({planned} planned, {reinforced} reinforced{if reinforced > 0
				then ` +{math.floor(extra / reinforced + 0.5)} avg`
				else ""}), {if kit then Trenches.buried(kit) else 0} buried by fire; fire steps {onStep} manned of {if sb
				then #sb.steps
				else 0}; {pioneers} pioneers; deaths {d.all}: {d.trench} in a trench ({pct(d.trench)}), {d.all - d.trench} in the open, {d.shell} by shells ({pct(
				d.shell
			)}), {d.zone} in a zone ({pct(d.zone)})`
		)
		-- (its run plans this match: State.ByTrench.runs)
		local runs = State.ByTrench.runs
		local function n(what: string): number
			return runs[`{side} {what}`] or 0
		end
		local why = {}
		local pre = `{side} refused: `
		for k, v in runs do
			if string.sub(k, 1, #pre) == pre then
				table.insert(why, { k = string.sub(k, #pre + 1), v = v })
			end
		end
		table.sort(why, function(x, y)
			return x.v > y.v
		end)
		local parts = {}
		for _, w in why do
			table.insert(parts, `{w.k} {w.v}`)
		end
		table.insert(
			lines,
			`  runs {n("laid")} laid, {n("refused")} refused ({table.concat(parts, "; ")}); {n("chained")} started at the real end; {n(
				"redug"
			)} buried squares planned again`
		)
		-- (looking after them, Config/Bots.Trenches.Care: each dug square's decision now, new squares held off shelled
		-- ground, ways up dug whole, its base standing, the squares lost and how long they stood, joins, the gates)
		local c = (if sb then sb.care else nil) or {}
		local lives = table.clone(State.ByTrench.lives[side] or {})
		table.sort(lives)
		local median = if #lives > 0 then lives[math.ceil(#lives / 2)] else 0
		local gates = {}
		for key, sys in (if sb then sb.systems else {}) do
			if sys.gate then
				table.insert(gates, `{key} {sys.gate}`)
			end
		end
		table.sort(gates)
		local function k(what: string): number
			return c[what] or 0
		end
		table.insert(
			lines,
			`  care: {k("reinforce")} reinforce, {k("fix")} fix, {k("patch")} patch, {k("ignore")} ignore, {k("wait")} wait; {k(
				"hotSkips"
			)} held off shelled ground; {k("routes")} ways up dug; base {k("baseUp")}/{k("baseAll")} standing; {#lives} lost (median {math.floor(
				median + 0.5
			)} s), {k("lost")} left; {n("joins")} joins; gates {if #gates > 0 then table.concat(gates, ", ") else "-"}`
		)
		-- (seeing an enemy: from the open and from cover, bot-seconds; in the open by fresh shells; foxholes dug seen in
		-- the open, both sides; Config/Bots.Brain.SeenSpots, Build.Exposed)
		local ex = State.ByTrench.exposure[side] or { open = 0, covered = 0, shelledOpen = 0 }
		local seenAll = ex.open + ex.covered
		table.insert(
			lines,
			`  exposure: seeing an enemy {math.floor(seenAll)} bot-s, {if seenAll > 0
				then math.floor(100 * ex.covered / seenAll + 0.5)
				else 0}% from cover; {math.floor(ex.shelledOpen)} bot-s in the open by fresh shells; {stats.exposedHoles} foxholes dug exposed (both sides)`
		)
		-- (players' plans waiting and dug, how long each took; reinforcing: squares at the full extra of those dug, the
		-- slots it had this time; dugouts standing; Config/Bots.Trenches.Plans, Care.Reinforce, Dugouts.perBays)
		local times = table.clone(State.ByTrench.planTimes[side] or {})
		table.sort(times)
		local mid = if #times > 0 then math.floor(times[math.ceil(#times / 2)] + 0.5) else 0
		local full = 0
		for _, t in (if sb then sb.trench else {}) do
			if t.built and t.extra >= Build.Trench.hp.extra - 1e-3 then
				full += 1
			end
		end
		table.insert(
			lines,
			`  plans: {k("plansWaiting")} players' squares waiting, {#times} dug (median {mid} s); reinforced to the full extra {full} of {dug}, {k(
				"reinforceSlots"
			)} slots now; {#(if sb then sb.rooms else {})} dugouts standing`
		)
	end
	-- (minutes since a sector last changed hands, or since the match began: how stale the fighting is)
	local owners = fronts.owners
	local key = if owners then table.concat(owners, ",") else nil
	if key ~= captures.key then
		captures.at = os.clock()
		captures.what = if key == nil or captures.key == nil then "the match began" else "the last capture"
		captures.key = key
	end
	if key then
		table.insert(lines, string.format("%.1f min since %s", (os.clock() - captures.at) / 60, captures.what))
	end
	workspace:SetAttribute(DevCfg.Admin.BotTrenchStatsAttribute, table.concat(lines, "\n"))
end

-- the admin panel's walks through a house (Config/DevTools.Admin.House; Bots.dev "House"): each bot's next spot, else
-- nil when it is done or gave up (its result kept for the readout)
local houseDone: { string } = {}
local function houseEnd(b: Bot, how: string, now: number)
	local w = b.devHouse :: any
	b.devHouse = nil
	table.insert(houseDone, 1, `{b.name} {how} {w.house}: {w.i - 1}/{#w.spots} spots in {math.floor(now - w.from)}s`)
	houseDone[DevCfg.Admin.House.keep + 1] = nil
end

local function houseGoal(b: Bot, now: number): Vector3?
	local w = b.devHouse
	local root = b.root
	if not w or not root then
		return nil
	end
	local H = DevCfg.Admin.House
	if not alive(b) or b.deadAt then
		houseEnd(b, "died in", now)
		return nil
	end
	if now > w.till then
		houseEnd(b, "GAVE UP in", now)
		return nil
	end
	local feet = (root :: BasePart).Position - Vector3.new(0, 3, 0)
	local at = w.spots[w.i]
	if flat(at - feet).Magnitude < H.arrive and math.abs(at.Y - feet.Y) < 4 then
		w.i += 1
		if w.i > #w.spots then
			houseEnd(b, "walked through", now)
			return nil
		end
		at = w.spots[w.i]
	end
	return at
end

local function houseLine()
	local H = DevCfg.Admin.House
	local now = os.clock()
	local lines = {}
	for _, b in bots do
		local w = b.devHouse
		if w and b.root then
			local s = still[b]
			local stood = if s then now - s.since else 0
			local off = math.floor(flat(w.spots[w.i] - (b.root :: BasePart).Position).Magnitude)
			local standing = if stood >= 3 then `, STILL {math.floor(stood)}s` else ""
			table.insert(
				lines,
				`{b.name} {w.house}: spot {w.i}/{#w.spots} {off} studs off, {math.floor(now - w.from)}s{standing}`
			)
		end
	end
	for _, r in houseDone do
		table.insert(lines, r)
	end
	workspace:SetAttribute(H.attribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

-- where a bot is going, for its label: studs to its squad's goal, to the step it walks to now, or its wait
local function goalWord(b: Bot): string?
	local root = b.root
	if not root then
		return nil
	end
	local p = (root :: BasePart).Position
	local parts = {}
	if b.goal then
		table.insert(parts, `goal {math.floor(Vector3.new(b.goal.X - p.X, 0, b.goal.Z - p.Z).Magnitude)}`)
	end
	local g = b.nav and b.nav.goal
	if g then
		table.insert(parts, `walk {math.floor(Vector3.new(g.X - p.X, 0, g.Z - p.Z).Magnitude)}`)
	end
	if b.wait then
		table.insert(parts, `wait {b.wait.kind}/{b.wait.why}`)
	end
	return if #parts > 0 then table.concat(parts, " ") else nil
end

local function label()
	activityLines(os.clock())
	spotLines()
	attackLines()
	mgLines()
	trenchStats()
	dugoutLines()
	squadLines()
	stuckLine()
	houseLine()
	frontLine()
	runLines()
	rescues()
	classMix()
	engineers()
	jobs()
	Tactics.fell.readout()
	local S = DevCfg.Admin.BotState
	local on = workspace:GetAttribute(S.attribute) == true
	if not on and not Tactics.dev.labelled then
		return
	end
	Tactics.dev.labelled = on
	for _, b in bots do
		local m = b.m
		if m then
			local text: string? = nil
			if on then
				local sqs = b.squad and squads[b.squad :: string]
				local act = b.act
				local what = act and act.kind
				if act and act.job then
					what = `{act.kind} {act.job.job.key}`
				elseif act and act.who then
					what = `{act.kind} {act.who.Name}`
				elseif not act and b.guard and b.guard.who.Parent then
					what = `covering {b.guard.who.Name}`
				elseif not act and b.work then
					-- (on its way to a job, gun out, or there and waiting until it is safe: Config/Bots.Build.Work)
					what = `{b.workState or "going"} to {b.work.job.job.key}`
				end
				text = Tactics.dev.rules.botLabel({
					order = b.order,
					sector = b.sector,
					phase = sqs and sqs.sq.phase,
					role = b.role,
					post = b.postKind,
					act = what,
					gun = if b.gun then (b.gun :: Model).Name elseif Artillery.gunOf(m) then "on" else nil,
					danger = b.danger,
					sight = b.sight,
					goal = goalWord(b),
				})
			end
			m:SetAttribute(S.label, text)
		end
	end
end

-- The admin panel's bot tests (src/server/DevTools; Config/DevTools.Admin): "Shell" a barrage on side `value`'s dug
-- trench squares; at the point `value`: "Push" the nearest squad pushes there now (its Grenadier throwing first),
-- "Strike" the nearest bot butt-strokes toward it, "Gun" the nearest free gun goes to the nearest bot to crew, "Work"
-- the nearest bot takes a foxhole job there (walked to with the gun out, dug once safe: Config/Bots.Build.Work), "Down"
-- the nearest bot is knocked down there, hurt (its teammates guard it until they may drag or heal it:
-- Config/Bots.Actions.Guard). Why not, else nil and what was done.
local function dev(action: string, value: any): (string?, string?)
	local A = DevCfg.Admin
	if action == "Plan" then
		-- (a side's fighting plan forced, or "auto": Config/Bots.Front)
		local fs = fronts.sides[value.side]
		if not fs then
			fs = { plan = "open" }
			fronts.sides[value.side] = fs
		end
		fs.forced = if value.plan == "auto" then nil else value.plan
		return nil, `{value.side}: {value.plan}`
	end
	if action == "Shell" or action == "ShellHere" then
		-- (a side's dug squares; or, at the aim point, either side's dug squares within Shell.here of the nearest one)
		local S = A.Shell
		local dug: { Vector3 } = {}
		if action == "Shell" then
			local sb = buildLists[value :: string]
			for _, t in (if sb then sb.trench else {}) do
				if t.built then
					table.insert(dug, t.at)
				end
			end
		else
			local aim = value :: Vector3
			local all: { Vector3 } = {}
			local nearest, best = nil, S.reach
			for _, side in A.Sides do
				local sb = buildLists[side]
				for _, t in (if sb then sb.trench else {}) do
					if t.built then
						table.insert(all, t.at)
						local d = flat(t.at - aim).Magnitude
						if d < best then
							nearest, best = t.at, d
						end
					end
				end
			end
			for _, at in all do
				if nearest and flat(at - nearest).Magnitude <= S.here then
					table.insert(dug, at)
				end
			end
		end
		if #dug == 0 then
			return "no dug trench", nil
		end
		task.spawn(function()
			for _ = 1, S.count do
				local at = dug[random:NextInteger(1, #dug)]
				local r, a = random:NextNumber() * S.spread, random:NextNumber() * math.pi * 2
				local p = Routes.ground(at.X + math.cos(a) * r, at.Z + math.sin(a) * r)
				Net.event("DevBlast"):FireAllClients(p, nil, S.kg)
				Damage.blast(p, S.kg, nil)
				task.wait(S.every)
			end
		end)
		return nil, `{A.Shell.count} shells on {#dug} squares`
	end
	local at = value :: Vector3
	local near = at
	local gun: Model? = nil
	if action == "Gun" then
		local best = math.huge
		for _, g in Artillery.list() do
			local d = flat(g.crew - at).Magnitude
			if g.free and not g.broken and g.model.Parent and d < best then
				gun, best, near = g.model, d, g.crew
			end
		end
		if not gun then
			return "no free gun", nil
		end
	end
	local pick: Bot? = nil
	local bestD = if gun then math.huge else A.BotNear
	for _, b in bots do
		local ok = b.root ~= nil and b.m ~= nil and alive(b) and not b.deadAt
		if action == "Push" then
			ok = ok and b.order == "Attack" and b.squad ~= nil and squads[b.squad :: string] ~= nil
		elseif action == "Gun" then
			ok = ok and b.mode == "Normal" and not b.gun and not Artillery.gunOf(b.m :: Model)
		elseif action == "Work" or action == "Down" or action == "House" then
			ok = ok and b.mode == "Normal" and b.side ~= nil and not b.gun and not Artillery.gunOf(b.m :: Model)
		end
		local d = if ok then flat((b.root :: BasePart).Position - near).Magnitude else math.huge
		if d < bestD then
			pick, bestD = b, d
		end
	end
	if action == "House" then
		-- (the house nearest the point: its indoor spots, each walk starting at a different one)
		local H = A.House
		local found = Indoors.near(at, H.within)
		if #found == 0 then
			return "no house here", nil
		end
		local house = found[1].building
		local spots = Indoors.spots(house)
		local picked: { Bot } = {}
		for _, b in bots do
			local free = b.root ~= nil and b.m ~= nil and alive(b) and not b.deadAt and b.mode == "Normal"
			free = free and not b.gun and not b.devHouse and not Artillery.gunOf(b.m :: Model)
			if free and flat((b.root :: BasePart).Position - at).Magnitude <= A.BotNear then
				table.insert(picked, b)
			end
		end
		table.sort(picked, function(x, y)
			return flat((x.root :: BasePart).Position - at).Magnitude
				< flat((y.root :: BasePart).Position - at).Magnitude
		end)
		local now = os.clock()
		local names = {}
		for k = 1, math.min(H.bots, #picked) do
			local b = picked[k]
			local route = {}
			for j = 0, math.min(H.spots, #spots) - 1 do
				table.insert(route, spots[(k - 1 + j * H.bots) % #spots + 1].at)
			end
			table.insert(route, (b.root :: BasePart).Position - Vector3.new(0, 3, 0))
			finish(b)
			b.work = nil
			b.devHouse = { spots = route, i = 1, from = now, till = now + H.seconds, house = house.Name }
			table.insert(names, b.name)
		end
		if #names == 0 then
			return "no bot near", nil
		end
		return nil, `{table.concat(names, ", ")} into {house.Name}`
	end
	if not pick then
		return "no bot near", nil
	end
	local b = pick :: Bot
	if action == "Push" then
		local sqs = squads[b.squad :: string]
		sqs.devPush = { at = Routes.ground(at.X, at.Z), till = os.clock() + A.PushSeconds }
	elseif action == "Strike" then
		-- (its act given up, its gun in its hands and the body turned to the point at once: the stroke's cone)
		local m, root = b.m :: Model, b.root :: BasePart
		finish(b)
		local dir = flat(at - root.Position)
		if dir.Magnitude < 1e-3 then
			return "no stroke", nil
		end
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		if not Tactics.melee.strikeAs(m, dir.Unit) then
			return "no stroke", nil
		end
		stats.strikes += 1
		b.meleeAt = os.clock() + Cfg.Melee.every
		local holds = W[b.weapon] and (W[b.weapon].holds :: any)
		if b.anim and holds and holds.strike then
			(b.anim :: Animate.Handle).play(holds.strike)
		end
	elseif action == "Gun" then
		Tactics.crew.give(b, gun :: Model)
	elseif action == "Work" then
		local tx, tz = BotBuild.toward(Map.sectors, b.sector or 1, b.side :: string)
		local job = { key = "Foxhole", x = at.X, z = at.Z, fx = tx, fz = tz }
		local r = { job = job, base = job, left = 0, tries = 0, waitUntil = 0, open = true }
		finish(b)
		b.work = nil
		Act.takeJob(b, r, os.clock())
		return nil, `{b.name} ({b.workState})`
	elseif action == "Down" then
		local m, root, h = b.m :: Model, b.root :: BasePart, b.humanoid :: Humanoid
		finish(b)
		h.Health = math.min(h.Health, h.MaxHealth * A.DownHealth)
		Ragdoll.knock(m, A.SelfKnock, -root.CFrame.LookVector)
	end
	return nil, b.name
end

return {
	report = report,
	label = label,
	houseGoal = houseGoal,
	dev = dev,
}
