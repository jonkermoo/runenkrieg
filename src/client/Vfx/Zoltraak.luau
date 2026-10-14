--!strict
-- Zoltraak (Config/Vfx.Zoltraak / Cast), the effects together.
-- - play: the full spell: a magic circle opens ahead of the staff tip, a charge gathers in its centre, a star glints
--   as it releases, the beam fires through the circle and its impact (burst, shockwave, debris of what it hit) lands
--   where it ends; the circle closes after the beam.
-- - begin: the staff cast held on left click (Config/Spells stages): the first circle opens at once, each stage
--   reached opens its larger circle further out along the aim (the last assembles slowly, with a build-up and a
--   flash when ready), the circles follow the aim, and release fires the reached stage's beam from the first circle
--   through the others; then they disintegrate, outermost first. pulse fires the first stage and keeps the circle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vfx = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx)
local Cfg = Vfx.Zoltraak
local Util = require(script.Parent.Util)
local Circle = require(script.Parent.Circle)
local Charge = require(script.Parent.Charge)
local Star = require(script.Parent.Star)
local Ray = require(script.Parent.Ray)
local Spikes = require(script.Parent.Spikes)
local Shockwave = require(script.Parent.Shockwave)
local Arc = require(script.Parent.Arc)
local Driver = require(script.Parent.Driver)
local Orbits = require(script.Parent.Orbits)

local Zoltraak = {}

-- `tip`: the staff tip, looking where the spell goes; `ignore`: what the beam passes through (the caster).
function Zoltraak.play(tip: CFrame, ignore: { Instance }?, scheme: string?)
	local look = tip.LookVector
	local c = tip.Position + look * Cfg.CircleAhead
	local circle = Circle.open(CFrame.lookAt(c, c + look), Cfg.CircleDiameter)
	Charge.play(c, Cfg.Charge)
	task.delay(Cfg.Charge, function()
		local to, normal, color = Util.cast(c, look, Cfg.Range, ignore)
		Star.play(c)
		Ray.play(c, to, { scheme = scheme, normal = normal, hitColor = color })
		local _, total = Ray.times()
		task.delay(total - Vfx.Ray.Fade + Cfg.CloseAfter, circle.close)
	end)
end

export type Cast = {
	aim: (tip: CFrame) -> (), -- the circles (and the charge) follow the tip
	-- see-through by v while held (0 = solid): the caster's own cast in first person (Config/Spells.Staff.Veil), or
	-- each stage's circle its own (`each`, by stage); each circle opened before the newest one `older` more again
	-- (compounding); firing shows everything solid again
	veil: (v: number, older: number?, each: { number }?) -> (),
	update: (held: number) -> (), -- opens / builds the circles for how long it has been held
	release: (stage: number, ignore: { Instance }?) -> Vector3?, -- fires that stage's beam; where it landed
	-- fires the first stage's beam and stays open (quick shots in a row from one circle): any later circle that had
	-- started opening closes and the hold starts over; where it landed
	pulse: (ignore: { Instance }?) -> Vector3?,
	cancel: () -> (), -- closes everything without firing
}

local function circleFrame(tip: CFrame, ahead: number): CFrame
	local c = tip.Position + tip.LookVector * ahead
	return CFrame.lookAt(c, c + tip.LookVector)
end

local rng = Random.new()

-- Starts a held cast at the staff tip (`holds`: each stage's hold time, Config/Spells): the first circle opens at
-- once; update(held) opens each later stage's circle as it's reached, the last one assembling over its `lead`
-- with the build-up (a charge in the first circle, lightning between the first and last) and a flash when ready.
-- `scale` sizes the circles and their spacing, `spread` spaces them further still (the caster's own cast in first
-- person is drawn smaller and further apart, Config/Spells.Staff.ViewScale / ViewSpread; the beam is the same).
-- Each circle has its orbiting curves (Vfx/Orbits, Config/Vfx.Cast.Stages `orbits`), lingering after the shot.
function Zoltraak.begin(tip: CFrame, holds: { number }, scheme: string?, scale: number?, spread: number?): Cast
	local k = scale or 1
	local sp = spread or 1
	local C = Vfx.Cast
	local S = C.Stages
	local schemeCfg = (Vfx.Schemes :: any)[scheme or Vfx.Ray.Scheme]
	local current = tip
	local circles: { Circle.Handle } = {}
	local orbits: { Orbits.Handle } = {}
	local done = false
	local isReady = false
	local charge: Charge.Handle? = nil
	local arcs: { Arc.Arc } = {}
	local buildFrom = 0 -- when the last circle started assembling (held time)
	local held = 0
	local nextArc = 0
	local last = #S
	local veil, older = 0, 0
	local each: { number }? = nil
	local function applyVeil()
		for i, c in circles do
			-- the newest circle at the veil (or its stage's), each before it `older` more see-through again
			local base = if each and each[i] then each[i] else veil
			local v = if veil > 0 then 1 - (1 - base) * (1 - older) ^ (#circles - i) else 0
			c.veil(v)
			if orbits[i] then
				orbits[i].veil(v)
			end
		end
		local ch = charge
		if ch then
			ch.veil(veil)
		end
		for _, a in arcs do
			Arc.veil(a, veil)
		end
	end

	local function opensAt(i: number): number
		return holds[i] - ((S[i] :: any).lead or 0)
	end
	local function centre(i: number): Vector3
		return circleFrame(current, S[i].ahead * k * sp).Position
	end
	local function freeBuild()
		for _, a in arcs do
			Arc.free(a)
		end
		table.clear(arcs)
		local ch = charge
		if ch then
			charge = nil
			ch.release()
		end
	end

	local function update(h: number)
		if done then
			return
		end
		held = h
		for i = #circles + 1, last do
			if h < opensAt(i) then
				break
			end
			local s = S[i] :: any
			if s.assemble then
				local lead = holds[i] - h -- whatever is left of it (a late update still finishes on time)
				circles[i] = Circle.open(
					circleFrame(current, s.ahead * k * sp),
					s.diameter * k,
					schemeCfg.circle,
					math.max(lead, 0.05),
					true,
					schemeCfg.accent,
					schemeCfg.haze
				)
				buildFrom = h
				charge = Charge.start(centre(1), math.max(lead, 0.05), schemeCfg.charge, schemeCfg.core)
				local B = C.Build
				for _ = 1, B.arcs do
					table.insert(
						arcs,
						Arc.new(
							B.segments,
							Util.color(schemeCfg.arc),
							Util.color(schemeCfg.arcCore),
							B.width,
							B.brightness,
							2
						)
					)
				end
			else
				circles[i] = Circle.open(
					circleFrame(current, s.ahead * k * sp),
					s.diameter * k,
					schemeCfg.circle,
					s.appear,
					false,
					schemeCfg.accent,
					schemeCfg.haze
				)
			end
			orbits[i] = Orbits.new(s.orbits or 0, s.diameter * k, schemeCfg.orbit, schemeCfg.core)
			orbits[i].move(circleFrame(current, s.ahead * k * sp))
			applyVeil()
		end
		if not isReady and circles[last] and h >= holds[last] then
			isReady = true
			for _, c in circles do
				c.ready()
			end
			local c1, cl = centre(1), centre(last)
			Star.play(c1, schemeCfg.flash, C.Ready.star)
			Spikes.play(c1, schemeCfg.flash)
			Shockwave.play(cl, current.LookVector, schemeCfg.glow, C.Ready.shockwave)
		end
	end

	-- the build-up's lightning, between the first and last circles' rims, more of it as the charge builds
	Driver.add(function(now: number): boolean
		if done then
			freeBuild()
			return false
		end
		if #arcs == 0 or now < nextArc then
			return true
		end
		nextArc = now + 1 / C.Build.rate
		local lead = holds[last] - buildFrom
		local p = if isReady then 1 else math.clamp((held - buildFrom) / math.max(lead, 0.05), 0, 1)
		local look = current.LookVector
		local c1, cl = centre(1), centre(last)
		local x = look:Cross(Vector3.yAxis)
		if x.Magnitude < 1e-3 then
			x = look:Cross(Vector3.xAxis)
		end
		x = x.Unit
		local y = look:Cross(x)
		for _, a in arcs do
			local a1, a2 = rng:NextNumber(0, 2 * math.pi), rng:NextNumber(0, 2 * math.pi)
			local from = c1 + (x * math.cos(a1) + y * math.sin(a1)) * S[1].diameter * k * 0.5
			local to = cl + (x * math.cos(a2) + y * math.sin(a2)) * S[last].diameter * k * 0.5 * (0.6 + 0.4 * p)
			Arc.zig(a, from, to, C.Build.jag * k)
			Arc.show(a, rng:NextNumber() < p, 0.5 + 0.5 * p)
		end
		return true
	end)

	local function aim(t: CFrame)
		current = t
		for i, c in circles do
			c.move(circleFrame(t, S[i].ahead * k * sp))
		end
		for i, o in orbits do
			o.move(circleFrame(t, S[i].ahead * k * sp))
		end
		local ch = charge
		if ch then
			ch.move(centre(1))
		end
	end

	-- closes the circles: those past the fired stage crumble at once, the rest after `after`, outermost first
	-- (their orbits linger after their circle's close by the fired stage's `linger`, then thin out)
	local function closeAll(stage: number, after: number)
		local linger = if stage > 0 then (S[stage] :: any).linger or 0 else 0
		for i, c in circles do
			if i > stage then
				c.close()
				orbits[i].stop(0)
			else
				local at = after + (stage - i) * C.CloseStagger
				task.delay(at, c.close)
				orbits[i].stop(at + linger)
			end
		end
	end

	update(0)
	return {
		aim = aim,
		veil = function(v: number, o: number?, e: { number }?)
			if not done and (v ~= veil or (o or 0) ~= older or e ~= each) then
				veil, older, each = v, o or 0, e
				applyVeil()
			end
		end,
		update = update,
		release = function(stage: number, ignore: { Instance }?): Vector3?
			if done then
				return nil
			end
			done = true
			veil = 0 -- fired: everything shows solid (user 2026-10-13)
			applyVeil()
			freeBuild()
			local n = math.clamp(stage, 1, #circles)
			local beam = S[n].beam
			local from = centre(1)
			local to, normal, color = Util.cast(from, current.LookVector, C.Range, ignore)
			if n == last then
				Star.play(from, schemeCfg.flash, C.FireStar)
			end
			Ray.play(from, to, { scheme = scheme, normal = normal, hitColor = color, profile = beam })
			local _, total = Ray.times(beam)
			closeAll(n, total - (Vfx.Beams :: any)[beam].Fade + C.CloseAfter)
			return to
		end,
		pulse = function(ignore: { Instance }?): Vector3?
			if done or not circles[1] then
				return nil
			end
			freeBuild()
			for i = #circles, 2, -1 do
				circles[i].close()
				orbits[i].stop(0)
				circles[i], orbits[i] = nil, nil
			end
			held, buildFrom, isReady = 0, 0, false
			applyVeil()
			local beam = S[1].beam
			local from = centre(1)
			local to, normal, color = Util.cast(from, current.LookVector, C.Range, ignore)
			Ray.play(from, to, { scheme = scheme, normal = normal, hitColor = color, profile = beam })
			return to
		end,
		cancel = function()
			if not done then
				done = true
				freeBuild()
				closeAll(0, 0)
			end
		end,
	}
end

-- A whole cast at once (the showcase): opens, held up to stage `stageN`'s hold time (plus a moment), released.
function Zoltraak.cast(tip: CFrame, stageN: number, holds: { number }, ignore: { Instance }?, scheme: string?)
	local c = Zoltraak.begin(tip, holds, scheme)
	local t0 = os.clock()
	local stop = holds[stageN] + 0.3
	task.spawn(function()
		while os.clock() - t0 < stop do
			c.update(os.clock() - t0)
			task.wait()
		end
		c.release(stageN, ignore)
	end)
end

return Zoltraak
