--!strict
-- The beam (Config/Vfx.Ray; the Zoltraak look, later a hitscan weapon's shot): a capsule of stacked camera-facing
-- layers (scheme colors, core out) with round glowing ends, widening away from the caster. The head shoots out, the
-- layers flicker, anime lightning crawls along it and leaps off it, crackles round the muzzle, sparkle mist streams
-- off, rings burst at the muzzle, lights follow it. It flashes as it fires (a wide bright flare and a
-- white pop at the muzzle) and pulses while it holds; then it dies out slowly (longer for a higher stage): a last
-- flare, then it crumbles into gaps from the caster's end toward the target, throwing off glowing flecks, sputtering
-- with random flashes and little star glints on what's left.
-- Everything is pooled and driven by the one frame loop (Vfx/Pool, Vfx/Driver); a far beam, or one past
-- Quality.MaxRays, draws only its layers and caps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vfx = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx)
local Cfg = Vfx.Ray
local Q = Vfx.Quality
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Arc = require(script.Parent.Arc)
local Ring = require(script.Parent.Ring)
local Burst = require(script.Parent.Burst)
local Flecks = require(script.Parent.Flecks)
local Star = require(script.Parent.Star)

local Ray = {}

export type Opts = {
	scheme: string?, -- Config/Vfx.Schemes (default Cfg.Scheme)
	hold: number?,
	impact: boolean?, -- false: no impact burst at the end
	normal: Vector3?, -- the hit surface's normal (default: back along the beam)
	hitColor: Color3?, -- the hit surface's color, for the debris (default: no debris)
	profile: string?, -- Config/Vfx.Beams (the quick tap...): overrides Ray's keys
}

local rng = Random.new()
local active = 0

-- Ray's config with a Config/Vfx.Beams profile's keys over it.
local function profile(name: string?): any
	if not name then
		return Cfg
	end
	local prof = (Vfx.Beams :: any)[name]
	assert(prof, "unknown beam profile " .. name)
	return setmetatable({}, {
		__index = function(_, k)
			local v = prof[k]
			if v == nil then
				return (Cfg :: any)[k]
			end
			return v
		end,
	})
end

local function distanceToSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local f = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (p - (a + ab * f)).Magnitude
end

-- Fires a beam from `from` to `to`.
function Ray.play(from: Vector3, to: Vector3, opts: Opts?)
	local o: Opts = opts or {}
	local P = profile(o.profile)
	local schemeName = o.scheme or P.Scheme
	local s = (Vfx.Schemes :: any)[schemeName]
	assert(s, "unknown scheme " .. schemeName)
	local hold = o.hold or P.Hold
	local total = P.Extend + hold + P.Fade
	local len = (to - from).Magnitude
	if len < 0.1 then
		return
	end
	local dir = (to - from).Unit
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 1e-3 then
		side = dir:Cross(Vector3.xAxis)
	end
	side = side.Unit
	local up = side:Cross(dir)
	local cam = workspace.CurrentCamera.CFrame.Position
	local full = active < Q.MaxRays and distanceToSegment(cam, from, to) < Q.FarDistance
	active += 1

	local L = P.Layers
	local D = P.Dissolve
	local K = D.keys
	local a0, a1 = Pool.att(from), Pool.att(from)
	local layers: { Beam } = {}
	-- each layer's transparency at the K points along it (soft layers fade out at both ends)
	local function sequence(l: any, gone: { number }?): NumberSequence
		local keys = {}
		for k = 0, K - 1 do
			local base = if l.soft and (k == 0 or k == K - 1) then 1 else l.transparency
			local g = if gone then gone[k + 1] else 0
			table.insert(keys, NumberSequenceKeypoint.new(k / (K - 1), 1 - (1 - base) * (1 - g)))
		end
		return NumberSequence.new(keys)
	end
	for i, l in L do
		local b =
			Pool.beam(a0, a1, Util.color(s.layers[i]), l.width0, l.width0, l.transparency, l.brightness, l.emission)
		b.Transparency = sequence(l)
		b.Segments = K -- a beam only samples its transparency at segment ends
		table.insert(layers, b)
	end
	-- each point's turn to crumble: mostly from the caster's end, partly random
	local turns: { number } = {}
	local gone: { number } = {}
	local shed: { boolean } = {}
	for k = 0, K - 1 do
		turns[k + 1] = (D.sweep * k / (K - 1) + (1 - D.sweep) * rng:NextNumber()) * (1 - D.soft)
		gone[k + 1] = 0
		shed[k + 1] = false
	end
	local flash = Pool.part(
		Enum.PartType.Ball,
		Util.color(s.layers[1]),
		Vector3.one * L[2].width0 * P.Flash.ball,
		CFrame.new(from)
	)
	local flashOn = true
	local nextSputter, sputterAt, sputterK = 0, -1, 0
	-- the capsule's round ends: a core ball inside a softer one, at the muzzle and at the head
	local caps: { { inner: Part, outer: Part, head: boolean } } = {}
	for _, head in { false, true } do
		table.insert(caps, {
			inner = Pool.part(Enum.PartType.Ball, Util.color(s.layers[1]), Vector3.one, CFrame.new(from)),
			outer = Pool.part(Enum.PartType.Ball, Util.color(s.layers[2]), Vector3.one, CFrame.new(from), 0.35),
			head = head,
		})
	end

	local B = P.Bolts
	local R = P.Rings
	local crawl: { Arc.Arc } = {}
	local leaps: { Arc.Arc } = {}
	local mist: ParticleEmitter? = nil
	local rings: { { ring: Ring.Ring, t0: number } } = {} -- the muzzle rings
	local arcColor, arcCore = Util.color(s.arc), Util.color(s.arcCore)
	local ringColor = Util.color(s.layers[2])
	local now0 = os.clock()
	if full then
		local n = math.clamp(math.ceil(len * 0.55 / B.crawlStep), 3, 10)
		for _ = 1, B.crawl do
			table.insert(crawl, Arc.new(n, arcColor, arcCore, B.width, B.brightness, B.zOffset))
		end
		for _ = 1, B.leap + B.muzzle do
			table.insert(leaps, Arc.new(3, arcColor, arcCore, B.width * 0.8, B.brightness, B.zOffset))
		end
		local m = P.Mist
		local e = Pool.emitter(CFrame.lookAt(from, to), Vector3.new(m.spread, m.spread, 0.1))
		e.Texture = Util.SPARKLE
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		e.Rate = math.min(m.perStud * len, m.maxRate)
		e.Lifetime = NumberRange.new(m.life * 0.5, m.life)
		e.Speed = NumberRange.new(m.speed * 0.3, m.speed)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 3
		e.Acceleration = Vector3.zero
		e.Squash = NumberSequence.new(0)
		e.Orientation = Enum.ParticleOrientation.FacingCamera
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, m.size), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0)
		e.Color = ColorSequence.new(ringColor, Util.color(s.mist))
		e.LightEmission = 1
		e.Brightness = 4
		mist = e
		for k = 1, R.muzzle do
			table.insert(rings, {
				ring = Ring.new(ringColor, R.width * 1.5, R.brightness),
				t0 = now0 + (k - 1) * 0.06,
			})
		end
	end
	local lc = P.Light
	local glow = Util.color(s.glow)
	local lights: { { light: PointLight, f: number } } = {}
	for _, f in { 0, 0.5, 1 } do
		local l = Pool.light(from, glow, lc.range, 0)
		if l then
			table.insert(lights, { light = l, f = f })
		end
	end

	local impacted = o.impact == false
	local nextBolt = 0
	local w2, w3 = L[2], L[3]

	local function cleanup()
		for _, b in layers do
			Pool.freeBeam(b)
		end
		Pool.freeAtt(a0)
		Pool.freeAtt(a1)
		for _, c in caps do
			Pool.freePart(c.inner)
			Pool.freePart(c.outer)
		end
		for _, a in crawl do
			Arc.free(a)
		end
		for _, a in leaps do
			Arc.free(a)
		end
		for _, r in rings do
			Ring.free(r.ring)
		end
		local e = mist
		if e then
			e.Enabled = false
			task.delay(P.Mist.life, function() -- let its sparkles die before another effect re-dresses it
				Pool.freeEmitter(e)
			end)
		end
		for _, l in lights do
			Pool.freeLight(l.light)
		end
		if flashOn then
			Pool.freePart(flash)
		end
		active -= 1
	end

	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			cleanup()
			return false
		end
		local reach = 1 - (1 - math.min(t / P.Extend, 1)) ^ 2
		local reached = len * reach
		local head = from + dir * reached
		a1.Position = head
		-- the fade: 0 while holding, 1 when gone
		local df = math.clamp((t - P.Extend - hold) / P.Fade, 0, 1)
		local fading = df > 0
		local thick = 1 - 0.35 * df -- it crumbles rather than thins: only a little narrower by the end
		-- size and brightness: the firing flash, the pulse while it holds, the flare as it starts to crumble
		local Fl = P.Flash
		local fire = math.max(1 - t / Fl.time, 0)
		local fadeT = (t - P.Extend - hold)
		local flare = if fading then math.max(1 - fadeT / D.flareTime, 0) else 0
		local grow = (1 + (Fl.width - 1) * fire) * (1 + (D.flare - 1) * flare)
		local glowK = (1 + (Fl.bright - 1) * fire) * (1 + (D.flare - 1) * flare)
		local Dy = P.Dying
		if not fading then
			glowK *= 1 + P.Pulse.amount * math.sin(t * P.Pulse.rate * 2 * math.pi)
		elseif now >= nextSputter then
			-- dying out: a random flash now and then, sometimes a little glint on a piece still there
			nextSputter = now + rng:NextNumber(0.5, 1.5) / Dy.sputter
			sputterAt, sputterK = now, rng:NextNumber(0.5, 1)
			if rng:NextNumber() < Dy.glints / Dy.sputter then
				local k = rng:NextInteger(1, K)
				if gone[k] < 0.5 then
					Star.play(from + dir * ((k - 1) / (K - 1) * reached), s.flash, Dy.glintLength)
				end
			end
		end
		if fading then
			local sp = math.max(1 - (now - sputterAt) / Dy.flashTime, 0) * sputterK
			glowK *= 1 + (Dy.flashBright - 1) * sp
			grow *= 1 + 0.15 * sp
		end
		if flashOn then
			if fire <= 0 then
				flashOn = false
				Pool.freePart(flash)
			else
				flash.Size = Vector3.one * L[2].width0 * Fl.ball * (1.6 - 0.6 * fire)
				flash.Transparency = 1 - fire
			end
		end
		local function widthAt(f: number): number -- layer 2's width f of the way to the head
			return (w2.width0 + (w2.width1 - w2.width0) * reach * f) * thick
		end
		local function outerAt(f: number): number -- layer 3's: the arcs crawl round this
			return (w3.width0 + (w3.width1 - w3.width0) * reach * f) * thick * B.radius
		end

		-- crumbling: each point fades on its turn; a point that starts to go throws off flecks
		if fading then
			for k = 1, K do
				gone[k] = math.clamp((df - turns[k]) / D.soft, 0, 1)
				if gone[k] > 0 and not shed[k] then
					shed[k] = true
					local f = (k - 1) / (K - 1)
					local at = from + dir * (f * reached)
					local w = widthAt(f) * 0.5
					for _ = 1, math.max(math.round(D.flecks / K), 1) do
						local ang = rng:NextNumber(0, 2 * math.pi)
						local radial = side * math.cos(ang) + up * math.sin(ang)
						Flecks.spawn(
							at + radial * w * rng:NextNumber(0, 1) + dir * rng:NextNumber(-0.5, 0.5) * len / K,
							radial * rng:NextNumber(D.fleckSpeed[1], D.fleckSpeed[2]) + dir * rng:NextNumber(-2, 2),
							Util.color(if rng:NextNumber() < 0.4 then s.layers[1] else s.layers[2]),
							rng:NextNumber(D.fleckSize[1], D.fleckSize[2]),
							rng:NextNumber(D.fleckLife[1], D.fleckLife[2])
						)
					end
				end
			end
		end
		for i, b in layers do
			local l = L[i]
			local flicker = P.Flicker + (P.Dying.flicker - P.Flicker) * df -- wilder as it dies
			local j = (1 + (rng:NextNumber() * 2 - 1) * flicker) * thick * grow
			b.Width0 = l.width0 * j
			b.Width1 = (l.width0 + (l.width1 - l.width0) * reach) * j
			b.Brightness = l.brightness * glowK
			if fading then
				b.Transparency = sequence(l, gone)
			end
		end
		for _, c in caps do
			local at = if c.head then head else from
			local w = (if c.head then widthAt(1) * P.CapBulge else widthAt(0)) * grow
			local left = 1 - (if c.head then gone[K] else gone[1]) -- a cap goes with its end of the beam
			c.inner.CFrame, c.outer.CFrame = CFrame.new(at), CFrame.new(at)
			c.inner.Size = Vector3.one * math.max(w * 0.6 * left, 0.05)
			c.outer.Size = Vector3.one * math.max(w * left, 0.05)
			c.inner.Transparency = 1 - left
			c.outer.Transparency = 1 - 0.65 * left
		end

		if not impacted and reach >= 1 then
			impacted = true
			Burst.play(
				to,
				{ scheme = schemeName, normal = o.normal or -dir, debrisColor = o.hitColor, scale = P.Impact }
			)
		end

		if full and now >= nextBolt then
			nextBolt = now + 1 / Q.BoltRate
			local on = rng:NextNumber() > df -- the lightning thins out as it crumbles
			for k, a in crawl do
				local span = rng:NextNumber(B.crawlSpan[1], B.crawlSpan[2])
				local s0 = rng:NextNumber(0, 1 - span)
				local phase = k / #crawl * 2 * math.pi + rng:NextNumber(0, 2 * math.pi)
				local points = {}
				for i = 0, a.n do
					local f = s0 + span * i / a.n
					local ang = phase + f * B.crawlTurns * 2 * math.pi + rng:NextNumber(-0.6, 0.6)
					local r = outerAt(f) * rng:NextNumber(0.85, 1.15)
					local radial = side * math.cos(ang) + up * math.sin(ang)
					points[i + 1] = from + dir * (f * reached) + radial * r + rng:NextUnitVector() * B.jag * 0.3
				end
				Arc.place(a, points)
				Arc.show(a, on and rng:NextNumber() > 0.12, thick)
			end
			for k, a in leaps do
				local ang = rng:NextNumber(0, 2 * math.pi)
				local radial = side * math.cos(ang) + up * math.sin(ang)
				local start, finish
				if k <= B.leap then -- off the beam's surface
					local f = rng:NextNumber(0.05, 1)
					start = from + dir * (f * reached) + radial * outerAt(f)
					local out = (radial + dir * rng:NextNumber(-0.6, 0.6) + rng:NextUnitVector() * 0.3).Unit
					finish = start + out * rng:NextNumber(B.leapLength[1], B.leapLength[2]) * thick
				else -- crackle round the muzzle
					start = from + radial * widthAt(0) * 0.5
					finish = from + (radial - dir * 0.3 + rng:NextUnitVector() * 0.5).Unit * B.muzzleLength * thick
				end
				Arc.zig(a, start, finish, B.jag * 0.6, radial)
				Arc.show(a, on and rng:NextNumber() > 0.3, thick)
			end
		end

		local e = mist
		if e then
			local m = P.Mist
			local p = e.Parent :: Part
			p.Size = Vector3.new(m.spread, m.spread, math.max(reached, 0.1))
			p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -reached / 2)
			e.Enabled = not fading
		end

		if full then
			local i = 1
			while i <= #rings do
				local r = rings[i]
				local a = math.clamp((now - r.t0) / 0.3, 0, 1)
				local done = a >= 1
				if not done then
					local out = 1 - (1 - a) ^ 3
					Ring.place(r.ring, from, dir, R.radius * (1 + out * (R.muzzleGrow - 1)), 1 - a, a)
				end
				if done then
					Ring.free(r.ring)
					rings[i] = rings[#rings]
					rings[#rings] = nil
				else
					i += 1
				end
			end
		end

		for _, l in lights do
			local light = l.light
			local att = light.Parent :: Attachment
			att.Position = from + dir * (reached * l.f)
			light.Brightness = if l.f <= reach then lc.brightness * glowK * (1 - df) else 0
		end
		return true
	end)
end

-- How long Ray.play takes to reach its end and to finish (when the impact lands; when it's gone).
function Ray.times(profileName: string?): (number, number)
	local P = profile(profileName)
	return P.Extend, P.Extend + P.Hold + P.Fade
end

return Ray
