--!strict
-- The bots' log line (Config/Bots.ReportEvery), the admin panel's labels over them and its bot tests (Bots.dev),
-- kept out of src/server/Bots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Bots)
local DevCfg = require(Shared.Config.DevTools)
local W = require(Shared.Config.Weapons)
local Net = require(Shared.Net)
local Artillery = require(script.Parent.Parent.Artillery)
local Damage = require(script.Parent.Parent.Damage)
local Animate = require(script.Parent.Animate)
local Routes = require(script.Parent.Routes)

local Types = require(script.Parent.Types)
type Bot = Types.Bot

local State = require(script.Parent.State)
local bots, Tactics, random, stats, squads, buildLists, fronts =
	State.bots, State.Tactics, State.random, State.stats, State.squads, State.buildLists, State.fronts

local Move = require(script.Parent.Move)
local flat, alive, finish = Move.flat, Move.alive, Move.finish

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
			"[Bots] %d bots (W %d, E %d; %d alive: %s; cap %d): frame avg %.3f ms, p95 %.3f ms, max %.2f ms; think %.3f ms avg, %.2f ms max; %d frames out of time; %.1f rays/frame, %d sights put off; %.1f paths/s (%d failed, %d put off, %d shared); %d stuck, %d sidesteps; %d bodies taken back, %d stood up; %d squads pushed in, %d covering shots, roles %s; %d callouts; %d grenades, %d heals, %d drags; %d laid, %d swings, %d refused, %d jobs open; trenches %d runs planned, %d on fire steps, %d in reserve, %d lines lost; cover %d piles pinned down, %d breastworks, %d walls, %d moved off trench lines; trench ways %d tear-down swings, %d runs swung round; %d saps, %d sap runs dug; by trench %d danger paths, %d down into trenches, %d over the top; front %d contacts, %d parallels; team %d pushes (%d grenades first), %d butt strokes, %d shots held (no line), %d spread steps, %d wire spots moved, %d swings waited; dugouts %d planned, %d sheltered, %d came up, %d bombed out; foxholes %d dug (%d pinned), %d into one; staff %d/%d/%d casts, %d dropped; %d doors opened, %d at windows, %d squads clearing; %d shots, %d deaths, %d covers found, %d peeks, %d upgrades; %s; to the zone %.1f s avg (%d); physics %.0f fps, heartbeat %.2f ms; thinking near %d, middle %d, distant %d; sending %.0f KB/s",
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
			stats.dangerPaths,
			stats.intoTrench,
			stats.overTop,
			stats.contacts,
			stats.parallels,
			stats.pushes,
			stats.pushBombs,
			stats.strikes,
			stats.blocked,
			stats.spread,
			stats.wireMoved,
			stats.waited,
			stats.dugouts,
			stats.sheltered,
			stats.cameUp,
			stats.bombed,
			stats.holes,
			stats.pinnedHoles,
			stats.intoHole,
			stats.casts1,
			stats.casts2,
			stats.casts3,
			stats.dropped,
			stats.doors,
			windows,
			clearing,
			stats.shots,
			stats.deaths,
			stats.covers,
			stats.peeks,
			stats.upgrades,
			Tactics.crew.report(),
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
					else (b.buildWhy or "not weighed yet")
				table.insert(parts, `{b.name}: {what}`)
			end
		end
		if #parts > 0 then
			table.insert(lines, `{side}: {table.concat(parts, "; ")}`)
		end
	end
	workspace:SetAttribute(DevCfg.Admin.BotEngineersAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
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
			local plan = fs.plan .. (if fs.forced then " (forced)" else "")
			table.insert(lines, `{side} {plan}: {if #parts > 0 then table.concat(parts, "; ") else "no attack"}`)
		end
	end
	workspace:SetAttribute(DevCfg.Admin.BotFrontAttribute, if #lines > 0 then table.concat(lines, "\n") else nil)
end

local function label()
	frontLine()
	engineers()
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
				})
			end
			m:SetAttribute(S.label, text)
		end
	end
end

-- The admin panel's bot tests (src/server/DevTools; Config/DevTools.Admin): "Shell" a barrage on side `value`'s dug
-- trench squares; at the point `value`: "Push" the nearest squad pushes there now (its Grenadier throwing first),
-- "Strike" the nearest bot butt-strokes toward it, "Gun" the nearest free gun goes to the nearest bot to crew. Why
-- not, else nil and what was done.
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
	if action == "Shell" then
		local sb = buildLists[value :: string]
		local dug: { Vector3 } = {}
		for _, t in (if sb then sb.trench else {}) do
			if t.built then
				table.insert(dug, t.at)
			end
		end
		if #dug == 0 then
			return "no dug trench", nil
		end
		local S = A.Shell
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
		end
		local d = if ok then flat((b.root :: BasePart).Position - near).Magnitude else math.huge
		if d < bestD then
			pick, bestD = b, d
		end
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
	end
	return nil, b.name
end

return {
	report = report,
	label = label,
	dev = dev,
}
