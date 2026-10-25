--!strict
-- Every explosion (Config/Vfx.Blast; user 2026-10-25, with a stylised explosion clip, then a second round: "i liked
-- the inital blast orb", "more variety of gray smoke", runes that "float and fade", grenades "exaggerate it a bit
-- more"; then "for the actual explosion, we can use the orbs. but for smoke and other effects ... not blocks"). Two
-- looks:
-- - the pop (grenades; then "the grenade needs more blast and effects"): the cluster below at the grenade's small
--   size, no spikes, one ring, with more dirt, sparks and light, a short grey smoke, a brown dust puff and a dust ring;
-- - the cluster (the staff's stages, shells): a white flash and spikes, sparks, ground rings, the orb sitting on the
--   hit inside a low dome of round balls that burn, cool dark with a glowing rim and dissolve into dark smoke and
--   falling dirt; grey smoke of several shades rolling up and drifting off; dirt thrown up, dust round the foot.
--   Magic keeps the cast's colours and leaves runes (glowing beam lines) floating up off the ground and fading, with
--   static crackling between them. Taller and longer with the blast's strength.
-- The orb and the balls are parts; smoke, dirt and dust are particles. Sized by a staff stage, or by a charge in kg
-- (its real fireball). Pooled pieces, one Driver step per explosion.

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
	debrisColor: Color3?, -- what was hit: the dirt takes its colour
	stage: number?, -- a staff stage 1..3 (default 1): Config/Vfx.Blast.Stages
	kg: number?, -- or a charge of this many kg of TNT: sized as its real fireball (Config/Vfx.Blast.Charge)
	magic: boolean?, -- a charge with the magic glint, spikes and runes (default: a plain explosion; a stage is magic)
	pop: boolean?, -- the grenade's pop instead of the cluster
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
	crumbled: boolean,
}
type Stroke = { a0: Attachment, a1: Attachment, halo: Beam, line: Beam, p0: Vector3, p1: Vector3 }
type Rune = {
	strokes: { Stroke },
	at: Vector3,
	turn: CFrame,
	spin: number,
	float: number,
	start: number,
	life: number,
	show: number,
	now: Vector3,
}

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
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
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

-- a smoke-textured emitter lit by the scene (smoke, dust, dirt)
local function smoky(cf: CFrame, box: Vector3, color: Color3): ParticleEmitter
	local e = emitter(cf, box)
	e.Texture = SMOKE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Rotation = NumberRange.new(0, 360)
	return e
end

local function freeEmitter(e: ParticleEmitter)
	-- (the pool's defaults for the other effects)
	e.LightInfluence = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	Pool.freeEmitter(e)
end

-- fades in over `fadeIn`, holds at `thick`, thins over the last `fade`
local function puffy(thick: number, fadeIn: number, fade: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(fadeIn, thick),
		NumberSequenceKeypoint.new(math.max(1 - fade, fadeIn + 0.01), thick),
		NumberSequenceKeypoint.new(1, 1),
	})
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

-- two axes across the surface
local function across(normal: Vector3): (Vector3, Vector3)
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	return side, normal:Cross(side)
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

-- dust kicked out low round the foot, settling (`k` x the count, `big` x the size, `longer` x the life)
local function dust(
	pos: Vector3,
	normal: Vector3,
	d: number,
	dirt: Color3,
	k: number,
	big: number,
	longer: number
): ParticleEmitter
	local du = Cfg.Dust
	local root = math.sqrt(d)
	local e = smoky(
		CFrame.new(pos + normal * d * 0.05),
		Vector3.new(d * 0.3, 0.2, d * 0.3),
		dirt:Lerp(Color3.new(1, 1, 1), du.light)
	)
	e.Speed = NumberRange.new(du.speed[1] * root, du.speed[2] * root)
	e.Lifetime = NumberRange.new(du.life[1] * longer, du.life[2] * longer)
	e.SpreadAngle = Vector2.new(du.spread, du.spread)
	e.Drag = du.drag
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, d * du.size[1] * big),
		NumberSequenceKeypoint.new(1, d * du.size[2] * big),
	})
	e.Transparency = puffy(du.thick, du.fadeIn, 1 - du.fadeIn)
	e.RotSpeed = NumberRange.new(-du.spin, du.spin)
	e:Emit(math.clamp(math.round(du.count * root * k), 2, du.max))
	return e
end

-- dirt thrown up from the hit (`k` x the count, `fast` x the speed): soft clumps in two shades, falling back and
-- fading about as they land; returns the emitters and how long they last
local function dirtUp(
	pos: Vector3,
	normal: Vector3,
	d: number,
	dirt: Color3,
	k: number,
	fast: number
): ({ ParticleEmitter }, number)
	local cl = Cfg.Clods
	local root = math.sqrt(d)
	local lo = math.min(cl.speed[1] * root * fast, cl.fastest)
	local hi = math.min(cl.speed[2] * root * fast, cl.fastest)
	local size = d ^ cl.sizePow
	local n = math.clamp(math.round(cl.perStud * d * k), cl.min, cl.max)
	local list: { ParticleEmitter } = {}
	local side = across(normal)
	local up = CFrame.fromMatrix(pos + normal * 0.3, side, normal) -- the emitter's top faces along the normal
	for i, shade in cl.shade do
		local e = smoky(up, Vector3.new(d * 0.15, 0.2, d * 0.15), shaded(dirt, shade))
		e.Speed = NumberRange.new(lo, hi)
		e.SpreadAngle = Vector2.new(cl.spread, cl.spread)
		e.Acceleration = Vector3.new(0, -cl.gravity, 0)
		e.Lifetime = NumberRange.new(2 * lo / cl.gravity * cl.airtime, 2 * hi / cl.gravity * cl.airtime)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, cl.size[2] * size),
			NumberSequenceKeypoint.new(1, cl.size[1] * size),
		})
		e.Transparency = puffy(0, 0.02, cl.fade)
		e.RotSpeed = NumberRange.new(-cl.spin, cl.spin)
		e:Emit(math.max(math.round(n / #cl.shade), 1) + (if i == 1 then n % #cl.shade else 0))
		table.insert(list, e)
	end
	return list, 2 * hi / cl.gravity
end

local function freeAll(list: { ParticleEmitter })
	for _, e in list do
		freeEmitter(e)
	end
end

-- the grenade's faint dust ring racing out flat (Config/Vfx.Blast.Pop)
local function dustRing(pos: Vector3, normal: Vector3, d: number, dirt: Color3): ParticleEmitter
	local P, D = Cfg.Pop, Cfg.Dust
	local side = across(normal)
	local ring = smoky(
		CFrame.fromMatrix(pos + normal * 0.3, side, normal),
		Vector3.new(d * 0.2, 0.1, d * 0.2),
		dirt:Lerp(Color3.new(1, 1, 1), D.light)
	)
	ring.Shape = Enum.ParticleEmitterShape.Cylinder
	ring.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	ring.Speed = NumberRange.new(P.ringSpeed * math.sqrt(d) * 0.8, P.ringSpeed * math.sqrt(d))
	ring.Drag = D.drag
	ring.Lifetime = NumberRange.new(D.life[1], D.life[2])
	ring.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, d * D.size[1]),
		NumberSequenceKeypoint.new(1, d * D.size[2]),
	})
	ring.Transparency = puffy((1 + D.thick) / 2, D.fadeIn, 1 - D.fadeIn)
	ring:Emit(P.ring)
	return ring
end

-- magic's leftover: runes spawning at random round the hit, floating up and fading, static crackling between them
local function runes(pos: Vector3, normal: Vector3, d: number, strength: number, s: any)
	local R, S = Cfg.Runes, Cfg.Static
	local glow = Util.color(s[Cfg.Colors.rune] or s.glow)
	local window = lerp(R.life[1], R.life[2], strength)
	local side, other = across(normal)
	local count = math.round(lerp(R.count[1], R.count[2], strength))
	local radius = d * lerp(R.radius[1], R.radius[2], strength)
	local ground = CFrame.fromMatrix(Vector3.zero, side, normal, -other) -- y along the normal
	local list: { Rune } = {}
	for i = 1, count do
		local size = math.clamp(d * lerp(R.size[1], R.size[2], strength) * rng:NextNumber(0.7, 1.2), R.least, R.most)
		local line = math.max(size * R.line, R.thinnest)
		local a, r = rng:NextNumber(0, 2 * math.pi), radius * math.sqrt(rng:NextNumber())
		local at = pos + (side * math.cos(a) + other * math.sin(a)) * r + normal * R.lift
		-- lying on the ground (the rune drawn in its x-z), tilted up to `tilt` off it
		local turn = ground
			* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
			* CFrame.Angles(math.rad(rng:NextNumber(-R.tilt, R.tilt)), 0, 0)
		local strokes: { Stroke } = {}
		for _, st in Cfg.Glyphs[rng:NextInteger(1, #Cfg.Glyphs)] do
			local a0, a1 = Pool.att(at), Pool.att(at)
			table.insert(strokes, {
				a0 = a0,
				a1 = a1,
				halo = Pool.beam(a0, a1, glow, line * R.halo, line * R.halo, 1, R.brightness, 0.6),
				line = Pool.beam(a0, a1, glow, line, line, 1, R.brightness),
				p0 = Vector3.new(st[1], 0, -st[2]) * size,
				p1 = Vector3.new(st[3], 0, -st[4]) * size,
			})
		end
		table.insert(list, {
			strokes = strokes,
			at = at,
			turn = turn,
			spin = math.rad(rng:NextNumber(-R.turn, R.turn)),
			float = size * between(R.float),
			start = (i - 1) / math.max(count - 1, 1) * math.max(window - R.each[2], window * 0.5)
				+ rng:NextNumber(0, R.appear),
			life = between(R.each),
			show = 0,
			now = at,
		})
	end
	local arcs: { Arc.Arc } = {}
	local color, core = Util.color(s[Cfg.Colors.static] or s.glow), Util.color(s[Cfg.Colors.staticCore] or s.flash)
	for _ = 1, math.round(lerp(S.arcs[1], S.arcs[2], strength)) do
		table.insert(arcs, Arc.new(S.segments, color, core, S.width, S.brightness))
	end
	local light = Pool.light(pos + normal * 2, color, math.min(radius * 2 * S.range, 60), 0)
	local reach = d * S.reach
	local total = 0
	for _, r in list do
		total = math.max(total, r.start + r.life)
	end
	local now0, nextDraw = os.clock(), 0
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			for _, r in list do
				for _, st in r.strokes do
					Pool.freeBeam(st.halo)
					Pool.freeBeam(st.line)
					Pool.freeAtt(st.a0)
					Pool.freeAtt(st.a1)
				end
			end
			for _, a in arcs do
				Arc.free(a)
			end
			if light then
				Pool.freeLight(light)
			end
			return false
		end
		local live: { Rune } = {}
		local bright = 0
		for _, r in list do
			local rt = t - r.start
			local u = rt / r.life
			local was = r.show
			r.show = if rt <= 0 or u >= 1
				then 0
				else math.min(rt / R.appear, 1) * (1 - math.clamp((u - (1 - R.fade)) / R.fade, 0, 1))
			if r.show <= 0 then
				if was > 0 then
					for _, st in r.strokes do
						st.halo.Enabled, st.line.Enabled = false, false
					end
				end
				continue
			end
			r.now = r.at + normal * r.float * rt
			local cf = CFrame.new(r.now) * r.turn * CFrame.Angles(0, r.spin * rt, 0)
			local see = 1 - r.show * (1 - R.flicker * rng:NextNumber())
			local seq = NumberSequence.new(see)
			local haloSeq = NumberSequence.new(R.haloSee + (1 - R.haloSee) * see)
			for _, st in r.strokes do
				st.a0.Position = cf * st.p0
				st.a1.Position = cf * st.p1
				st.line.Transparency = seq
				st.halo.Transparency = haloSeq
			end
			if r.show > 0.3 then
				table.insert(live, r)
			end
			bright = math.max(bright, r.show)
		end
		if now >= nextDraw then
			nextDraw = now + S.refresh
			for _, a in arcs do
				local r = live[rng:NextInteger(1, math.max(#live, 1))]
				if not r then
					Arc.show(a, false)
					continue
				end
				-- to another showing rune within reach, else down to the ground under it
				local near: { Rune } = {}
				for _, q in live do
					if q ~= r and (q.now - r.now).Magnitude <= reach then
						table.insert(near, q)
					end
				end
				local to = if #near > 0
					then near[rng:NextInteger(1, #near)].now
					else r.now - normal * (r.now - pos):Dot(normal) + side * rng:NextNumber(-1, 1)
				Arc.zig(a, r.now, to, S.jag)
				Arc.show(a, rng:NextNumber() < S.on, r.show)
			end
			if light then
				light.Brightness = S.light * bright * rng:NextNumber(0.3, 1)
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
	-- the grenade: the same explosion, small, with more dirt, sparks and light, its own smoke time and a dust ring
	local P = Cfg.Pop
	local popping = o.pop == true
	if popping then
		st = { fireball = d, rings = P.rings, spikes = false }
		magic = false
	end

	local CO = Cfg.Colors
	local strength = Blast.strength(d)
	local hot, fire = Util.color(s[CO.hot] or s.flash), Util.color(s[CO.fire] or s.glow)
	local rimName = s.layers[CO.rim] or s.glow
	local rim = Util.color(rimName)
	local dark = rim:Lerp(Color3.new(), if magic then CO.darkMagic else CO.dark)
	local spark = s[CO.spark] or s.glow
	local now0 = os.clock()
	local side, other = across(normal)

	-- the flash, spikes, sparks and rings
	local F = Cfg.Flash
	local flash = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(pos + normal * d * 0.2))
	local glare = F.brightness * (if popping then P.light else 1)
	local light = Pool.light(pos + normal * F.lift, fire, math.min(F.range * d, F.max), glare)
	if st.spikes then
		Spikes.play(pos + normal * d * 0.2, spark)
		if magic then
			Star.play(pos + normal * d * 0.2, spark, d * Cfg.Star)
		end
	end
	local sp = Cfg.Sparks
	local sparked = sparks(pos, d, sp.perStud * d * (if popping then P.sparks else 1), sp.life, hot, Util.color(spark))
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

	-- the orb on the hit: a white-hot core in a burning shell
	local O = Cfg.Orb
	local orbAt = pos + normal * d * O.size * (0.5 - O.sink)
	local orb = Pool.part(Enum.PartType.Ball, fire, Vector3.one * 0.05, CFrame.new(orbAt))
	local core = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(orbAt))

	-- the low dome of balls round it
	local C = Cfg.Cluster
	local life = lerp(C.life[1], C.life[2], strength)
	local tall = d * lerp(C.tall[1], C.tall[2], strength)
	local stagger = lerp(C.stagger[1], C.stagger[2], strength)
	local rise = d * lerp(C.rise[1], C.rise[2], strength)
	local n = math.clamp(math.round(C.perStud * d), C.min, C.max)
	local balls: { Ball } = {}
	for i = 1, n do
		local f = if n > 1 then (i - 1) / (n - 1) else 0
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = C.spread * d * (1 - (1 - C.narrow) * f) * math.sqrt(rng:NextNumber(0.2, 1))
		local size = d * between(C.size)
		local at = pos + (side * math.cos(a) + other * math.sin(a)) * r + normal * (size * 0.3 + tall * f)
		table.insert(balls, {
			rim = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(orbAt)),
			body = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(orbAt)),
			from = orbAt,
			at = at,
			size = size,
			start = f * stagger,
			shift = rng:NextNumber(-C.jitter, C.jitter),
			crumbled = false,
		})
	end

	-- grey smoke of several shades over the dome, rolling up and drifting off: one emitter per shade
	local SM = Cfg.Smoke
	local smokeLife = if popping then P.smokeLife else lerp(SM.life[1], SM.life[2], strength)
	local smokeRise = d * lerp(SM.rise[1], SM.rise[2], strength)
	local smokeCount = math.round(lerp(SM.count[1], SM.count[2], strength))
	local smokeBox = CFrame.new(pos + normal * tall * (1 + SM.low) / 2 + normal * d * 0.2)
	local smokes: { ParticleEmitter } = {}
	for _, shade in SM.shades do
		local e = smoky(
			smokeBox,
			Vector3.new(SM.spread * d, math.max(tall * (1 - SM.low), 1), SM.spread * d),
			Util.color(shade)
		)
		e.Speed = NumberRange.new(smokeRise * 0.6, smokeRise * 1.4)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Drag = SM.drag
		e.Acceleration = Vector3.new(SM.wind[1], SM.wind[2], SM.wind[3])
		e.Lifetime = NumberRange.new(smokeLife * 0.75, smokeLife)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, d * SM.size[1]),
			NumberSequenceKeypoint.new(1, d * SM.size[2]),
		})
		e.Transparency = puffy(SM.thick, SM.fadeIn, SM.fade)
		e.RotSpeed = NumberRange.new(-SM.spin, SM.spin)
		table.insert(smokes, e)
	end
	-- let out a few at a time over `appear` s
	local smokeSteps = math.max(math.ceil(smokeCount / #smokes), 1)
	for k = 1, smokeSteps do
		task.delay(SM.from * life + (k - 1) / smokeSteps * SM.appear, function()
			for _, e in smokes do
				e:Emit(1)
			end
		end)
	end

	-- fine dirt raining out of the cloud
	local R = Cfg.Rain
	local footprint = C.spread * d * 2
	local rain = smoky(
		CFrame.new(pos + normal * tall * 0.7),
		Vector3.new(footprint, math.max(tall * 0.5, 1), footprint),
		shaded(dirt, R.shade)
	)
	rain.Speed = NumberRange.new(0, 1)
	rain.SpreadAngle = Vector2.new(180, 180)
	rain.Lifetime = NumberRange.new(R.life[1], R.life[2])
	rain.Acceleration = Vector3.new(0, -R.gravity, 0)
	rain.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, R.size[2]),
		NumberSequenceKeypoint.new(1, R.size[1]),
	})
	rain.Rate = math.min(R.rate * d, R.max)
	-- the balls dissolving: dark smoke puffs and dirt flakes where each crumbles
	local flakes = smoky(CFrame.new(pos), Vector3.one * 0.5, dark)
	flakes.Speed = NumberRange.new(0, 2)
	flakes.SpreadAngle = Vector2.new(180, 180)
	flakes.Lifetime = NumberRange.new(R.life[1], R.life[2])
	flakes.Acceleration = Vector3.new(0, -R.gravity, 0)
	flakes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, R.size[2] * 1.5),
		NumberSequenceKeypoint.new(1, R.size[1]),
	})
	flakes.LightInfluence = 0
	local puffs = smoky(CFrame.new(pos), Vector3.one * 0.5, dark)
	puffs.SpreadAngle = Vector2.new(180, 180)
	puffs.Lifetime = NumberRange.new(C.puffLife[1], C.puffLife[2])
	puffs.Transparency = puffy(0.1, 0.05, 0.6)
	puffs.RotSpeed = NumberRange.new(-SM.spin, SM.spin)
	puffs.LightInfluence = 0

	local longer = lerp(1, Cfg.Dust.longer, strength)
	local du = if popping
		then dust(pos, normal, d, dirt, P.dust, P.dustSize, P.dustLife)
		else dust(pos, normal, d, dirt, 1, 1, longer)
	local ring = if popping then dustRing(pos, normal, d, dirt) else nil
	local thrown, flight = dirtUp(pos, normal, d, dirt, if popping then P.clods else 1, if popping then P.throw else 1)
	if magic then
		task.delay(Cfg.Runes.delay, runes, pos, normal, d, strength, s)
	end

	local rainOn, rainOff = R.from * life, (R.from + R.last) * life
	local orbEnd = O.grow + O.hold + O.fade
	local total = math.max(
		F.light,
		orbEnd,
		stagger + life + C.grow + C.puffLife[2],
		SM.from * life + SM.appear + smokeLife,
		sp.life[2],
		rainOff + R.life[2],
		Cfg.Dust.life[2] * (if popping then P.dustLife else longer),
		flight
	)
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			Pool.freePart(flash)
			Pool.freePart(orb)
			Pool.freePart(core)
			if light then
				Pool.freeLight(light)
			end
			for _, b in balls do
				Pool.freePart(b.rim)
				Pool.freePart(b.body)
			end
			freeAll(smokes)
			freeAll(thrown)
			freeEmitter(sparked)
			freeEmitter(rain)
			freeEmitter(flakes)
			freeEmitter(puffs)
			freeEmitter(du)
			if ring then
				freeEmitter(ring)
			end
			return false
		end
		local fa = math.min(t / F.time, 1)
		flash.Size = Vector3.one * math.max(d * F.size * ease(fa * 1.5), 0.05)
		flash.Transparency = fa
		if light then
			light.Brightness = glare * (1 - math.min(t / F.light, 1)) ^ 2
		end
		rain.Enabled = t >= rainOn and t < rainOff

		-- the orb: swells, holds white-hot, then cools into the rim colour and fades
		local swell = ease(t / O.grow)
		local cool = math.clamp((t - O.grow - O.hold) / O.fade, 0, 1)
		local orbSize = math.max(d * O.size * swell * (1 + O.swell * cool), 0.05)
		orb.Size = Vector3.one * orbSize
		orb.Color = fire:Lerp(rim, cool)
		orb.Transparency = cool
		core.Size = Vector3.one * orbSize * O.core * (1 - cool)
		core.Color = hot:Lerp(fire, cool)
		core.Transparency = if cool >= 1 then 1 else cool

		local eye = workspace.CurrentCamera.CFrame.Position
		for _, b in balls do
			local bt = t - b.start
			if bt <= 0 then
				b.rim.Transparency, b.body.Transparency = 1, 1
				continue
			end
			local u = math.clamp(bt / life + b.shift, 0, 1)
			local out = ease(bt / C.grow)
			local at = b.from:Lerp(b.at, out) + Vector3.yAxis * rise * bt
			-- white-hot, burning, the body cooling dark inside a glowing rim, the rim dimming, then dissolving away
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
			if gone > 0 and not b.crumbled then
				b.crumbled = true
				for _, e in { flakes, puffs } do
					local box = e.Parent :: Part
					box.CFrame = CFrame.new(at)
					box.Size = Vector3.one * b.size * 0.6
				end
				flakes:Emit(R.flakes)
				puffs.Speed = NumberRange.new(b.size * C.rising * 0.5, b.size * C.rising)
				puffs.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0, b.size * C.puff),
					NumberSequenceKeypoint.new(1, b.size * C.puff * C.grow2),
				})
				puffs:Emit(C.puffs)
			end
			local size = math.max(b.size * (0.35 + 0.65 * out) * (1 - gone ^ 2), 0.05)
			local see = if gone >= 1 then 1 else gone * 0.5
			b.rim.Size = Vector3.one * size
			b.rim.CFrame = CFrame.new(at)
			b.rim.Color = rimColor
			b.rim.Transparency = see
			local toEye = eye - at
			toEye = if toEye.Magnitude > 1e-3 then toEye.Unit else Vector3.zero
			b.body.Size = Vector3.one * size * C.inner
			b.body.CFrame = CFrame.new(at + toEye * C.toward * size / 2)
			b.body.Color = bodyColor
			b.body.Transparency = see
		end
		return true
	end)
end

return Blast
