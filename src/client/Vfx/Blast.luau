--!strict
-- Every explosion (Config/Vfx.Blast; user 2026-10-25, with a stylised explosion clip: grenades "a quick explosion, less
-- aggressive and 'fiery' looking"; shells and magic "taller longer lasting clouds the stronger they are"; magic leaves
-- "rune / electricity static that stays behind"; dirt falling back, "realistic"). Two looks:
-- - the pop (grenades): a short flash, a few sparks, a brown dust puff and clods of the ground;
-- - the cluster (the staff's stages, shells): a white flash and spikes, sparks, ground rings, a cluster of round balls
--   white-hot then burning, cooling dark with a glowing rim, crumbling away into falling dirt; clods thrown up and
--   settling, dust round the foot. Magic keeps the cast's colours and leaves glowing runes on the ground with static
--   crackling between them. Taller and longer with the blast's strength.
-- Sized by a staff stage, or by a charge in kg (its real fireball). Pooled pieces, one Driver step per explosion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Vfx = require(Shared.Config.Vfx)
local Palette = require(Shared.Config.Palette)
local Cfg = Vfx.Blast
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Arc = require(script.Parent.Arc)
local Shockwave = require(script.Parent.Shockwave)
local Spikes = require(script.Parent.Spikes)
local Star = require(script.Parent.Star)
local ScreenBlur = require(script.Parent.Parent.ScreenBlur)
local CameraShake = require(script.Parent.Parent.CameraShake)
local ShakeCfg = require(Shared.Config.CameraShake)
local ShakeRules = require(Shared.Rules.CameraShake)

local Blast = {}

export type Opts = {
	scheme: string?, -- Config/Vfx.Schemes (default: Ray's)
	normal: Vector3?, -- the surface's normal (default up)
	debrisColor: Color3?, -- what was hit: the clods take its colour
	stage: number?, -- a staff stage 1..3 (default 1): Config/Vfx.Blast.Stages
	kg: number?, -- or a charge of this many kg of TNT: sized as its real fireball (Config/Vfx.Blast.Charge)
	magic: boolean?, -- a charge with the magic glint, spikes and runes (default: a plain explosion; a stage is magic)
	pop: boolean?, -- the grenade's quick pop instead of the cluster
}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture

local rng = Random.new()

type Ball = {
	rim: Part,
	body: Part,
	from: Vector3,
	at: Vector3,
	size: number,
	start: number,
	shift: number,
	flaked: boolean,
}
type Clod = { part: Part, p0: Vector3, v: Vector3, spin: Vector3, size: Vector3, floor: number?, landed: number? }
type Stroke = { part: Part, length: number }

local function between(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function ease(t: number): number
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 3
end

-- a `kg` charge's fireball, studs across (Config/Vfx.Blast.Charge: D = a x W^b metres)
function Blast.fireball(kg: number): number
	local K = Cfg.Charge
	return K.a * kg ^ K.b / K.metresPerStud
end

-- how strong a fireball `d` studs across reads, 0..1 (Config/Vfx.Blast.Scale)
function Blast.strength(d: number): number
	local S = Cfg.Scale
	return math.clamp(math.log(d / S.small) / math.log(S.big / S.small), 0, 1)
end

-- a pooled emitter reset for one-off bursts (the caller sets the rest)
local function emitter(cf: CFrame, box: Vector3): ParticleEmitter
	local e = Pool.emitter(cf, box)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Transparency = NumberSequence.new(0)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 1
	e.Acceleration = Vector3.zero
	e.Drag = 0
	e.Rotation = NumberRange.new(0, 0)
	e.RotSpeed = NumberRange.new(0, 0)
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Squash = NumberSequence.new(0)
	e.SpreadAngle = Vector2.new(0, 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	return e
end

local function freeEmitter(e: ParticleEmitter)
	e.LightInfluence = 0 -- (the pool's default for the other effects)
	Pool.freeEmitter(e)
end

-- the colour of what's under the blast (else the hit thing's, else plain mud)
local function dirtOf(pos: Vector3, normal: Vector3, given: Color3?): Color3
	if given then
		return given
	end
	local _, _, c = Util.cast(pos + normal * 1, -normal, 4)
	if c then
		return c
	end
	local m = (Palette.Terrain :: any)[Cfg.Clods.dirt]
	return Color3.fromRGB(m[1], m[2], m[3])
end

local function shaded(c: Color3, k: number): Color3
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end

-- sparks flung out from `pos`, slowing, then falling
local function sparks(pos: Vector3, d: number, n: number, life: { number }, from: Color3, to: Color3): ParticleEmitter
	local sp = Cfg.Sparks
	local e = emitter(CFrame.new(pos), Vector3.one * 0.2)
	e.Texture = Util.SPARKLE
	e.Speed = NumberRange.new(sp.speed[1] * d, sp.speed[2] * d)
	e.Lifetime = NumberRange.new(life[1], life[2])
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = sp.drag
	e.Acceleration = Vector3.new(0, -sp.gravity, 0)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sp.size), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(from, to)
	e.Brightness = sp.brightness
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-1.5)
	e:Emit(math.clamp(math.round(n), 1, sp.max))
	return e
end

-- dust kicked out low round the foot, settling (`k` x the count)
local function dust(pos: Vector3, normal: Vector3, d: number, dirt: Color3, k: number, longer: number): ParticleEmitter
	local du = Cfg.Dust
	local root = math.sqrt(d)
	local e = emitter(CFrame.new(pos + normal * d * 0.05), Vector3.new(d * 0.3, 0.2, d * 0.3))
	e.Texture = SMOKE
	e.Speed = NumberRange.new(du.speed[1] * root, du.speed[2] * root)
	e.Lifetime = NumberRange.new(du.life[1] * longer, du.life[2] * longer)
	e.SpreadAngle = Vector2.new(du.spread, du.spread)
	e.Drag = du.drag
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, d * du.size[1]),
		NumberSequenceKeypoint.new(1, d * du.size[2]),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(du.fadeIn, du.thick),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(dirt:Lerp(Color3.new(1, 1, 1), du.light))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-du.spin, du.spin)
	e:Emit(math.clamp(math.round(du.count * root * k), 2, du.max))
	return e
end

-- clods of the ground thrown up (`k` x the count); they tumble, land and sink away
local function clods(pos: Vector3, normal: Vector3, d: number, dirt: Color3, k: number): { Clod }
	local cl = Cfg.Clods
	local floor = if normal.Y > 0.5 then pos.Y else nil
	local list: { Clod } = {}
	local scale = d ^ cl.sizePow
	for _ = 1, math.clamp(math.round(cl.perStud * d * k), cl.min, cl.max) do
		local dir = (normal * cl.up + rng:NextUnitVector() * (1 - cl.up)).Unit
		local size = Vector3.new(between(cl.size), between(cl.size), between(cl.size)) * scale
		table.insert(list, {
			part = Pool.part(
				Enum.PartType.Block,
				shaded(dirt, between(cl.shade)),
				size,
				CFrame.new(pos),
				0,
				Enum.Material.SmoothPlastic
			),
			p0 = pos + normal * 0.3,
			v = dir * math.min(between(cl.speed) * math.sqrt(d), cl.fastest),
			spin = rng:NextUnitVector() * cl.spin,
			size = size,
			floor = floor,
		})
	end
	return list
end

-- moves the clods; true while any is still showing
local function moveClods(list: { Clod }, t: number): boolean
	local cl = Cfg.Clods
	local any = false
	for _, c in list do
		local p: Vector3
		local tt = if c.landed then c.landed else t
		p = c.p0 + c.v * tt + Vector3.new(0, -0.5 * cl.gravity * tt * tt, 0)
		local floor = c.floor
		if floor and not c.landed and tt > 0.05 and p.Y < floor + c.size.Y / 2 then
			c.landed = t
			p = Vector3.new(p.X, floor + c.size.Y / 2, p.Z)
		elseif floor and c.landed then
			p = Vector3.new(p.X, floor + c.size.Y / 2, p.Z)
		end
		local r = c.spin * tt
		local gone = if c.landed then math.clamp((t - c.landed - cl.rest) / cl.sink, 0, 1) else 0
		-- no floor (a wall): it falls until its time is up
		if not floor and t > cl.rest * 2 then
			gone = math.clamp((t - cl.rest * 2) / cl.sink, 0, 1)
		end
		c.part.CFrame = CFrame.new(p) * CFrame.Angles(r.X, r.Y, r.Z)
		c.part.Size = c.size * math.max(1 - gone, 0.01)
		c.part.Transparency = if gone >= 1 then 1 else 0
		any = any or gone < 1
	end
	return any
end

local function freeClods(list: { Clod })
	for _, c in list do
		Pool.freePart(c.part)
	end
end

-- the grenade's pop: quick and not fiery
local function pop(pos: Vector3, normal: Vector3, d: number, s: any, dirt: Color3)
	local P = Cfg.Pop
	local hot = Util.color(s.flash)
	local now0 = os.clock()
	local flash = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(pos + normal * d * 0.15))
	local light = Pool.light(pos + normal * Cfg.Flash.lift, hot, math.min(P.range * d, Cfg.Flash.max), P.brightness)
	local sp = sparks(pos, d, P.sparks * d, P.sparkLife, hot, Util.color(s.glow))
	local du = dust(pos, normal, d, dirt, P.dust, 1)
	local thrown = clods(pos, normal, d, dirt, P.clods)
	local cl = Cfg.Clods
	local total = math.max(P.light, P.sparkLife[2], Cfg.Dust.life[2])
	Driver.add(function(now: number): boolean
		local t = now - now0
		local a = math.min(t / P.time, 1)
		flash.Size = Vector3.one * math.max(d * P.flash * ease(a * 1.6), 0.05)
		flash.Transparency = a
		if light then
			light.Brightness = P.brightness * (1 - math.min(t / P.light, 1)) ^ 2
		end
		local showing = moveClods(thrown, t)
		if t >= total and (not showing or t > total + cl.rest * 3) then
			Pool.freePart(flash)
			if light then
				Pool.freeLight(light)
			end
			freeEmitter(sp)
			freeEmitter(du)
			freeClods(thrown)
			return false
		end
		return true
	end)
end

-- magic's leftover: runes on the ground, static crackling between them, for `life` s from now
local function runes(pos: Vector3, normal: Vector3, d: number, strength: number, s: any)
	local R, S = Cfg.Runes, Cfg.Static
	local glow = Util.color(s[Cfg.Colors.rune] or s.glow)
	local life = lerp(R.life[1], R.life[2], strength)
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local other = normal:Cross(side)
	local count = math.round(lerp(R.count[1], R.count[2], strength))
	local radius = d * lerp(R.radius[1], R.radius[2], strength)
	local size = math.clamp(d * lerp(R.size[1], R.size[2], strength), R.least, R.most)
	local line = math.max(size * R.line, R.thinnest)
	local strokes: { Stroke } = {}
	local centres: { Vector3 } = {}
	local turn = rng:NextNumber(0, 2 * math.pi)
	for i = 1, count do
		local a = turn + (i - 1) / count * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		local out = side * math.cos(a) + other * math.sin(a)
		local along = normal:Cross(out)
		local c = pos + out * radius * rng:NextNumber(0.8, 1.1) + normal * R.lift
		table.insert(centres, c)
		local glyph = Cfg.Glyphs[rng:NextInteger(1, #Cfg.Glyphs)]
		for _, st in glyph do
			local p0 = c + (along * st[1] + out * st[2]) * size
			local p1 = c + (along * st[3] + out * st[4]) * size
			local length = (p1 - p0).Magnitude + line
			local part = Pool.part(
				Enum.PartType.Block,
				glow,
				Vector3.new(line, line * 0.4, length),
				CFrame.lookAt((p0 + p1) / 2, p1, normal),
				1
			)
			table.insert(strokes, { part = part, length = length })
		end
	end
	local arcs: { Arc.Arc } = {}
	local color, core = Util.color(s[Cfg.Colors.static] or s.glow), Util.color(s[Cfg.Colors.staticCore] or s.flash)
	for _ = 1, math.round(lerp(S.arcs[1], S.arcs[2], strength)) do
		table.insert(arcs, Arc.new(S.segments, color, core, S.width, S.brightness))
	end
	local light = Pool.light(pos + normal * S.lift * 4, color, math.min(radius * 2 * S.range, 60), 0)
	local now0, nextDraw = os.clock(), 0
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= life then
			for _, st in strokes do
				Pool.freePart(st.part)
			end
			for _, a in arcs do
				Arc.free(a)
			end
			if light then
				Pool.freeLight(light)
			end
			return false
		end
		local show = math.min(t / R.appear, 1) * (1 - math.clamp((t / life - (1 - R.fade)) / R.fade, 0, 1))
		for _, st in strokes do
			st.part.Transparency = 1 - show * (1 - R.flicker * rng:NextNumber())
		end
		if now >= nextDraw then
			nextDraw = now + S.refresh
			for _, a in arcs do
				local i = rng:NextInteger(1, #centres)
				local j = if rng:NextNumber() < 0.5 then i % #centres + 1 else (i - 2) % #centres + 1
				local lift = normal * S.lift
				Arc.zig(a, centres[i] + lift, centres[j] + lift, S.jag, normal)
				Arc.show(a, show > 0.15 and rng:NextNumber() < S.on, show)
			end
			if light then
				light.Brightness = S.light * show * rng:NextNumber(0.3, 1)
			end
		end
		return true
	end)
end

function Blast.play(pos: Vector3, opts: Opts?)
	local o: Opts = opts or {}
	local charge = o.kg ~= nil and o.kg > 0
	local st: any = Cfg.Stages[math.clamp(o.stage or 1, 1, #Cfg.Stages)]
	local magic = not charge or o.magic == true
	if charge then
		st = { fireball = Blast.fireball(o.kg :: number), rings = Cfg.Charge.rings, spikes = true }
	end
	local d = st.fireball
	local s = (Vfx.Schemes :: any)[o.scheme or Vfx.Ray.Scheme]
	local normal = (o.normal or Vector3.yAxis).Unit
	ScreenBlur.blast(pos, d) -- the screen blur when it's close (src/client/ScreenBlur)
	-- every explosion shakes the camera once, by its charge (a staff stage's as Config/CameraShake.Stages)
	CameraShake.blast(pos, if charge then o.kg :: number else ShakeRules.stageKg(o.stage or 1, ShakeCfg.Stages))
	local dirt = dirtOf(pos, normal, o.debrisColor)
	if o.pop then
		pop(pos, normal, d, s, dirt)
		return
	end

	local CO = Cfg.Colors
	local strength = Blast.strength(d)
	local hot, fire = Util.color(s[CO.hot] or s.flash), Util.color(s[CO.fire] or s.glow)
	local rimName = s.layers[CO.rim] or s.glow
	local rim = Util.color(rimName)
	local dark = rim:Lerp(Color3.new(), if magic then CO.darkMagic else CO.dark)
	local spark = s[CO.spark] or s.glow
	local now0 = os.clock()

	-- the flash, spikes, sparks and rings
	local F = Cfg.Flash
	local flash = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(pos + normal * d * 0.2))
	local light = Pool.light(pos + normal * F.lift, fire, math.min(F.range * d, F.max), F.brightness)
	if st.spikes then
		Spikes.play(pos + normal * d * 0.2, spark)
		if magic then
			Star.play(pos + normal * d * 0.2, spark, d * Cfg.Star)
		end
	end
	local sp = Cfg.Sparks
	local sparked = sparks(pos, d, sp.perStud * d, sp.life, hot, Util.color(spark))
	for i = 1, st.rings do
		task.delay((i - 1) * Cfg.Rings.gap, function()
			Shockwave.play(
				pos + normal * Cfg.Rings.lift,
				normal,
				rimName,
				d * Cfg.Rings.to * (1 + Cfg.Rings.grow * (i - 1))
			)
		end)
	end

	-- the ball cluster: a column over the hit, rolling up
	local C = Cfg.Cluster
	local life = lerp(C.life[1], C.life[2], strength)
	local tall = d * lerp(C.tall[1], C.tall[2], strength)
	local stagger = lerp(C.stagger[1], C.stagger[2], strength)
	local rise = d * lerp(C.rise[1], C.rise[2], strength)
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local other = normal:Cross(side)
	local n = math.clamp(math.round(C.perStud * d), C.min, C.max)
	local balls: { Ball } = {}
	for i = 1, n do
		local f = if n > 1 then (i - 1) / (n - 1) else 0
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = C.spread * d * (1 - (1 - C.narrow) * f) * math.sqrt(rng:NextNumber())
		local size = d * between(C.size) * (1 + C.topSwell * f)
		local at = pos + (side * math.cos(a) + other * math.sin(a)) * r + normal * (size * 0.35 + tall * f)
		table.insert(balls, {
			rim = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(pos)),
			body = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(pos)),
			from = pos + normal * size * 0.3,
			at = at,
			size = size,
			start = f * stagger,
			shift = rng:NextNumber(-C.jitter, C.jitter),
			flaked = false,
		})
	end

	-- fine dirt raining out of the cloud, and the flakes of the crumbling balls
	local R = Cfg.Rain
	local footprint = C.spread * d * 2
	local rain =
		emitter(CFrame.new(pos + normal * tall * 0.6), Vector3.new(footprint, math.max(tall * 0.6, 1), footprint))
	rain.Texture = SMOKE
	rain.Speed = NumberRange.new(0, 1)
	rain.SpreadAngle = Vector2.new(180, 180)
	rain.Lifetime = NumberRange.new(R.life[1], R.life[2])
	rain.Acceleration = Vector3.new(0, -R.gravity, 0)
	rain.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, R.size[2]),
		NumberSequenceKeypoint.new(1, R.size[1]),
	})
	rain.Color = ColorSequence.new(shaded(dirt, R.shade))
	rain.LightEmission = 0
	rain.LightInfluence = 1
	rain.Rotation = NumberRange.new(0, 360)
	rain.Rate = math.min(R.rate * d, R.max)
	local flakes = emitter(CFrame.new(pos), Vector3.one * 0.5)
	flakes.Texture = SMOKE
	flakes.Speed = NumberRange.new(0, 2)
	flakes.SpreadAngle = Vector2.new(180, 180)
	flakes.Lifetime = NumberRange.new(R.life[1], R.life[2])
	flakes.Acceleration = Vector3.new(0, -R.gravity, 0)
	flakes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, R.size[2] * 1.5),
		NumberSequenceKeypoint.new(1, R.size[1]),
	})
	flakes.Color = ColorSequence.new(dark)
	flakes.LightEmission = 0
	flakes.Rotation = NumberRange.new(0, 360)

	local du = dust(pos, normal, d, dirt, 1, lerp(1, Cfg.Dust.longer, strength))
	local thrown = clods(pos, normal, d, dirt, 1)
	if magic then
		task.delay(Cfg.Runes.delay, runes, pos, normal, d, strength, s)
	end

	local rainOn, rainOff = R.from * life, (R.from + R.last) * life
	local total = math.max(
		F.light,
		stagger + life + C.grow,
		sp.life[2],
		rainOff + R.life[2],
		Cfg.Dust.life[2] * lerp(1, Cfg.Dust.longer, strength)
	)
	Driver.add(function(now: number): boolean
		local t = now - now0
		local showing = moveClods(thrown, t)
		if t >= total and (not showing or t > total + Cfg.Clods.rest * 3) then
			Pool.freePart(flash)
			if light then
				Pool.freeLight(light)
			end
			for _, b in balls do
				Pool.freePart(b.rim)
				Pool.freePart(b.body)
			end
			freeEmitter(sparked)
			freeEmitter(rain)
			freeEmitter(flakes)
			freeEmitter(du)
			freeClods(thrown)
			return false
		end
		local fa = math.min(t / F.time, 1)
		flash.Size = Vector3.one * math.max(d * F.size * ease(fa * 1.5), 0.05)
		flash.Transparency = fa
		if light then
			light.Brightness = F.brightness * (1 - math.min(t / F.light, 1)) ^ 2
		end
		rain.Enabled = t >= rainOn and t < rainOff

		local eye = workspace.CurrentCamera.CFrame.Position
		for _, b in balls do
			local bt = t - b.start
			if bt <= 0 then
				continue
			end
			local u = math.clamp(bt / life + b.shift, 0, 1)
			local out = ease(bt / C.grow)
			local at = b.from:Lerp(b.at, out) + Vector3.yAxis * rise * bt
			-- white-hot, burning, the body cooling dark inside a glowing rim, the rim dimming, then crumbling away
			local rimColor, bodyColor
			if u < C.hot then
				rimColor = hot:Lerp(fire, u / C.hot)
				bodyColor = rimColor
			elseif u < C.burn then
				local k = (u - C.hot) / (C.burn - C.hot)
				rimColor = fire:Lerp(rim, k)
				bodyColor = fire:Lerp(dark, ease(k))
			else
				local k = math.clamp((u - C.burn) / (C.crumble - C.burn), 0, 1)
				rimColor = rim:Lerp(dark, C.rimFade * k)
				bodyColor = dark
			end
			local gone = math.clamp((u - C.crumble) / (1 - C.crumble), 0, 1)
			if gone > 0 and not b.flaked then
				b.flaked = true
				local box = flakes.Parent :: Part
				box.CFrame = CFrame.new(at)
				box.Size = Vector3.one * b.size * 0.7
				flakes:Emit(R.flakes)
			end
			local size = math.max(b.size * (0.35 + 0.65 * out) * (1 - gone ^ 2), 0.05)
			b.rim.Size = Vector3.one * size
			b.rim.CFrame = CFrame.new(at)
			b.rim.Color = rimColor
			b.rim.Transparency = if gone >= 1 then 1 else gone * 0.5
			local toEye = eye - at
			toEye = if toEye.Magnitude > 1e-3 then toEye.Unit else Vector3.zero
			b.body.Size = Vector3.one * size * C.inner
			b.body.CFrame = CFrame.new(at + toEye * C.toward * size / 2)
			b.body.Color = bodyColor
			b.body.Transparency = if gone >= 1 then 1 else gone * 0.5
		end
		return true
	end)
end

return Blast
