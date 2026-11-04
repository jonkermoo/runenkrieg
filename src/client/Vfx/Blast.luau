--!strict
-- Every explosion (Config/Vfx.Blast; user 2026-11-03: "lets do an explosion visual rework", picked the earth and smoke
-- column of three drafts, "but i want magic to still have their rune effects. perhaps improved"). A WW1 shell burst:
-- a blink of flash and a small fireball swallowed at once by earth, a faint air ring, a spout of earth and clods
-- shooting up and falling back, a few faceted sods arcing out, a dark column of earth-brown to grey smoke that widens
-- at the top and hangs on, and a low dust skirt rolling out along the ground and settling. Magic takes the cast's
-- colours for its fire (the smoke stays grey) and leaves a seal of runes lit round the foot that lift off and spiral
-- up through the smoke, more runes floating up at random, and static crackling between them. The grenade (`pop`) is
-- the same, small and short. Taller and longer with the blast's strength.
-- Only the flash, the fireball and the sods are parts; earth, smoke and dust are particles, runes are beams. Sized by a
-- staff stage, or by a charge in kg (its real fireball). Pooled pieces, one Driver step per explosion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Vfx = require(Shared.Config.Vfx)
local Palette = require(Shared.Config.Palette)
local Cfg = Vfx.Blast
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Arc = require(script.Parent.Arc)
local Ring = require(script.Parent.Ring)
local Shockwave = require(script.Parent.Shockwave)
local Spikes = require(script.Parent.Spikes)
local Star = require(script.Parent.Star)
local ScreenBlur = require(script.Parent.Parent.ScreenBlur)
local CameraShake = require(script.Parent.Parent.CameraShake)
local Flagpoles = require(script.Parent.Parent.Flagpoles)
local Suppression = require(script.Parent.Parent.Suppression)
local Concussion = require(script.Parent.Parent.Concussion)
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
	pop: boolean?, -- the grenade's small, short burst
}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture
local LN2 = math.log(2) -- (a ParticleEmitter's Drag halves the speed every 1 / Drag s)

local rng = Random.new()

type Sod = {
	part: Part,
	from: Vector3,
	vel: Vector3,
	axis: Vector3,
	spin: number,
	land: number,
	turn: CFrame,
}
type Stroke = { a0: Attachment, a1: Attachment, halo: Beam, line: Beam, p0: Vector3, p1: Vector3 }
type Rune = {
	strokes: { Stroke },
	start: number,
	life: number,
	show: number,
	now: Vector3,
	-- scattered: floating up from `at`, tilted `turn`, turning `spin`
	at: Vector3,
	turn: CFrame,
	spin: number,
	float: number,
	-- the seal's: round the foot at `angle` / `radius`, lifting off after `hold`
	seal: boolean,
	angle: number,
	radius: number,
	hold: number,
	rise: number,
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

-- a smoke-textured emitter lit by the scene (smoke, dust, earth)
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

local function freeAll(list: { ParticleEmitter })
	for _, e in list do
		freeEmitter(e)
	end
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

local function grows(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the colour of what's under the blast (else the hit thing's, else plain mud), mixed `soil` of the way to mud: a
-- blast on grass throws up the earth under it
local function dirtOf(pos: Vector3, normal: Vector3, given: Color3?): Color3
	local mud = rgb((Palette.Terrain :: any)[Cfg.Clods.dirt])
	local c = given
	if not c then
		local _, _, under = Util.cast(pos + normal * 1, -normal, 4)
		c = under
	end
	return if c then c:Lerp(mud, Cfg.Clods.soil) else mud
end

local function shaded(c: Color3, k: number): Color3
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end

-- two axes across the surface
local function across(normal: Vector3): (Vector3, Vector3)
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	return side, normal:Cross(side)
end

-- a frame on the hit whose top (+Y) faces along the normal: an emitter's Top
local function upright(pos: Vector3, normal: Vector3): CFrame
	local side = across(normal)
	return CFrame.fromMatrix(pos, side, normal)
end

-- a direction within `deg` degrees of the normal
local function cone(normal: Vector3, deg: number): Vector3
	local side, other = across(normal)
	local a, tilt = rng:NextNumber(0, 2 * math.pi), math.rad(deg) * math.sqrt(rng:NextNumber())
	return (normal * math.cos(tilt) + (side * math.cos(a) + other * math.sin(a)) * math.sin(tilt)).Unit
end

-- sparks flung out from `pos`, slowing, then falling
local function sparks(pos: Vector3, d: number, n: number, from: Color3, to: Color3): ParticleEmitter
	local sp = Cfg.Sparks
	local e = emitter(CFrame.new(pos), Vector3.one * 0.2)
	e.Texture = Util.SPARKLE
	e.Speed = NumberRange.new(sp.speed[1] * d, sp.speed[2] * d)
	e.Lifetime = NumberRange.new(sp.life[1], sp.life[2])
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = sp.drag
	e.Acceleration = Vector3.new(0, -sp.gravity, 0)
	e.Size = grows(sp.size, 0)
	e.Color = ColorSequence.new(from, to)
	e.Brightness = sp.brightness
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-1.5)
	e:Emit(math.clamp(math.round(n), 1, sp.max))
	return e
end

-- the smoke column: one emitter per shade, the earth low and first, the greys higher and wider; returns the emitters
-- and when the last puff is gone
local function column(
	pos: Vector3,
	normal: Vector3,
	d: number,
	dirt: Color3,
	strength: number,
	tall: number,
	life: number,
	lit: number
): ({ ParticleEmitter }, number)
	local CO = Cfg.Column
	local count = math.round(lerp(CO.count[1], CO.count[2], strength))
	local list: { ParticleEmitter } = {}
	local box = Vector3.new(CO.foot * d, 0.4, CO.foot * d)
	local shades = #CO.shades
	for k, shade in CO.shades do
		local f = if shades > 1 then (k - 1) / (shades - 1) else 0
		local color = if shade == "Earth" then shaded(dirt, CO.earth) else Util.color(shade)
		local e = smoky(upright(pos + normal * d * 0.1, normal), box, color)
		e.LightInfluence = lit
		-- each stops where Drag has used up its speed (v / (Drag x ln 2) studs on): its share of the column's height
		local lo, hi = tall * (0.12 + 0.55 * f), tall * math.min(0.4 + 0.6 * f, 1)
		local k2 = CO.drag * LN2
		e.Speed = NumberRange.new(lo * k2, hi * k2)
		e.Drag = CO.drag
		e.SpreadAngle = Vector2.new(CO.spread, CO.spread)
		e.Acceleration = Vector3.new(CO.wind[1], CO.wind[2], CO.wind[3])
		e.Lifetime = NumberRange.new(life * 0.7, life)
		local big = 1 + (CO.topSize - 1) * f
		e.Size = grows(d * CO.size[1] * big, d * CO.size[2] * big)
		e.Transparency = puffy(CO.thick, CO.fadeIn, CO.fade)
		e.RotSpeed = NumberRange.new(-CO.spin, CO.spin)
		local n = math.max(math.round(count / shades), 1) + (if k == 1 then count % shades else 0)
		task.delay(CO.appear * f, function()
			e:Emit(n)
		end)
		table.insert(list, e)
	end
	return list, CO.appear + life
end

-- the spout of thrown earth shooting up and falling back; returns it and its longest flight
local function spout(
	pos: Vector3,
	normal: Vector3,
	d: number,
	dirt: Color3,
	strength: number,
	tall: number
): (ParticleEmitter, number)
	local S = Cfg.Spout
	local e = smoky(upright(pos + normal * 0.3, normal), Vector3.new(d * 0.12, 0.2, d * 0.12), shaded(dirt, S.shade))
	local high = tall * lerp(S.high[1], S.high[2], strength) / lerp(Cfg.Column.tall[1], Cfg.Column.tall[2], strength)
	local fast = math.sqrt(2 * S.gravity * high)
	e.Speed = NumberRange.new(fast * math.sqrt(0.4), fast)
	e.SpreadAngle = Vector2.new(S.spread, S.spread)
	e.Acceleration = Vector3.new(0, -S.gravity, 0)
	local flight = 2 * fast / S.gravity
	e.Lifetime = NumberRange.new(flight * 0.55, flight)
	e.Size = grows(d * S.size[1], d * S.size[2])
	e.Transparency = puffy(0, 0.02, S.fade)
	e.RotSpeed = NumberRange.new(-60, 60)
	e:Emit(math.round(lerp(S.count[1], S.count[2], strength)))
	return e, flight
end

-- clods thrown up from the hit (`k` x the count, `fast` x the speed): soft clumps in two shades, falling back and
-- fading about as they land; returns the emitters and how long they last
local function clods(
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
	for i, shade in cl.shade do
		local e = smoky(upright(pos + normal * 0.3, normal), Vector3.new(d * 0.15, 0.2, d * 0.15), shaded(dirt, shade))
		e.Speed = NumberRange.new(lo, hi)
		e.SpreadAngle = Vector2.new(cl.spread, cl.spread)
		e.Acceleration = Vector3.new(0, -cl.gravity, 0)
		e.Lifetime = NumberRange.new(2 * lo / cl.gravity * cl.airtime, 2 * hi / cl.gravity * cl.airtime)
		e.Size = grows(cl.size[2] * size, cl.size[1] * size)
		e.Transparency = puffy(0, 0.02, cl.fade)
		e.RotSpeed = NumberRange.new(-cl.spin, cl.spin)
		e:Emit(math.max(math.round(n / #cl.shade), 1) + (if i == 1 then n % #cl.shade else 0))
		table.insert(list, e)
	end
	return list, 2 * hi / cl.gravity
end

-- the dust skirt rolling out low round the foot and settling; returns it and its life
local function skirt(
	pos: Vector3,
	normal: Vector3,
	d: number,
	dirt: Color3,
	strength: number,
	life: number
): ParticleEmitter
	local SK = Cfg.Skirt
	local root = math.sqrt(d)
	local e = smoky(
		upright(pos + normal * d * 0.05, normal),
		Vector3.new(d * 0.3, 0.2, d * 0.3),
		dirt:Lerp(Color3.new(1, 1, 1), SK.light)
	)
	e.Speed = NumberRange.new(SK.speed[1] * root, SK.speed[2] * root)
	e.SpreadAngle = Vector2.new(SK.spread, SK.spread)
	e.Drag = SK.drag
	e.Acceleration = -normal * SK.sink
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Size = grows(d * SK.size[1], d * SK.size[2])
	e.Transparency = puffy(SK.thick, SK.fadeIn, 1 - SK.fadeIn)
	e.RotSpeed = NumberRange.new(-SK.spin, SK.spin)
	e:Emit(math.round(lerp(SK.count[1], SK.count[2], strength)))
	return e
end

-- a few faceted sods arcing out and lying where they land; moved by the blast's own Driver step
local function sods(pos: Vector3, normal: Vector3, d: number, dirt: Color3, n: number): { Sod }
	local S = Cfg.Sods
	local grass = rgb((Palette.Terrain :: any)[S.grass])
	local list: { Sod } = {}
	for i = 1, n do
		local size = math.sqrt(d) * between(S.size)
		local dims = Vector3.new(size * rng:NextNumber(0.7, 1.3), size * rng:NextNumber(0.45, 0.7), size)
		local dir = cone(normal, S.spread)
		local vel = dir * math.sqrt(2 * S.gravity * d * between(S.high))
		-- where it comes down: one cast down at its flight's end on level ground, then the time it meets that height
		local flat = 2 * math.max(vel.Y, 1) / S.gravity
		local guess = pos + Vector3.new(vel.X, 0, vel.Z) * flat
		local at = Util.cast(guess + Vector3.yAxis * 30, -Vector3.yAxis, 60)
		local drop = math.clamp(at.Y - pos.Y, -20, vel.Y ^ 2 / (2 * S.gravity) * 0.9)
		local land = (vel.Y + math.sqrt(math.max(vel.Y ^ 2 - 2 * S.gravity * drop, 0))) / S.gravity
		local color = if i % S.grassy == 0 then grass else shaded(dirt, rng:NextNumber(0.6, 0.85))
		local part = Pool.part(Enum.PartType.Block, color, dims, CFrame.new(pos), 0, Enum.Material.SmoothPlastic)
		table.insert(list, {
			part = part,
			from = pos + normal * dims.Y,
			vel = vel,
			axis = cone(Vector3.yAxis, 90),
			spin = math.rad(rng:NextNumber(-S.spin, S.spin)),
			land = land,
			turn = CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), 0),
		})
	end
	return list
end

-- magic's leftover: a seal of runes round the foot that lift off and spiral up, more floating up at random, static
-- crackling between them
local function runes(pos: Vector3, normal: Vector3, d: number, strength: number, s: any)
	local R, S, SE = Cfg.Runes, Cfg.Static, Cfg.Seal
	local glow = Util.color(s[Cfg.Colors.rune] or s.glow)
	local window = lerp(R.life[1], R.life[2], strength)
	local side, other = across(normal)
	local count = math.round(lerp(R.count[1], R.count[2], strength))
	local inSeal = math.min(math.max(math.round(count * SE.share), SE.least), count)
	local radius = d * lerp(R.radius[1], R.radius[2], strength)
	local sealR = d * SE.radius
	local ground = CFrame.fromMatrix(Vector3.zero, side, normal, -other) -- y along the normal
	local list: { Rune } = {}
	local spin0 = rng:NextNumber(0, 2 * math.pi)
	for i = 1, count do
		local seal = i <= inSeal
		local size = math.clamp(d * lerp(R.size[1], R.size[2], strength) * rng:NextNumber(0.7, 1.2), R.least, R.most)
		local line = math.max(size * R.line, R.thinnest)
		local strokes: { Stroke } = {}
		local at = pos + normal * R.lift
		if not seal then
			local a, r = rng:NextNumber(0, 2 * math.pi), radius * math.sqrt(rng:NextNumber())
			at += (side * math.cos(a) + other * math.sin(a)) * r
		end
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
		local j = i - inSeal - 1
		local scattered = count - inSeal
		table.insert(list, {
			strokes = strokes,
			start = if seal
				then (i - 1) / inSeal * SE.light
				else SE.light + SE.hold + j / math.max(scattered - 1, 1) * math.max(
					window - R.each[2],
					window * 0.5
				) + rng:NextNumber(0, R.appear),
			life = if seal then SE.hold + between(SE.each) else between(R.each),
			show = 0,
			now = at,
			at = at,
			turn = ground
				* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
				* CFrame.Angles(math.rad(rng:NextNumber(-R.tilt, R.tilt)), 0, 0),
			spin = math.rad(rng:NextNumber(-R.turn, R.turn)),
			float = size * between(R.float),
			seal = seal,
			angle = spin0 + (i - 1) / inSeal * 2 * math.pi,
			radius = sealR,
			hold = SE.hold - (i - 1) / inSeal * SE.light * 0.5,
			rise = d * lerp(SE.rise[1], SE.rise[2], strength),
		})
	end
	local arcs: { Arc.Arc } = {}
	local color, core = Util.color(s[Cfg.Colors.static] or s.glow), Util.color(s[Cfg.Colors.staticCore] or s.flash)
	for _ = 1, math.round(lerp(S.arcs[1], S.arcs[2], strength)) do
		table.insert(arcs, Arc.new(S.segments, color, core, S.width, S.brightness))
	end
	local ring = Ring.new(glow, math.min(SE.ring * math.sqrt(d), SE.ringMost), R.brightness, 1)
	local ringOff = SE.light + SE.hold + SE.ringFade
	local light = Pool.light(pos + normal * 2, color, math.min(radius * 2 * S.range, 60), 0)
	local reach = d * S.reach
	local spiral = math.rad(SE.spiral)
	local total = ringOff
	for _, r in list do
		total = math.max(total, r.start + r.life)
	end
	local function finish()
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
		Ring.free(ring)
		if light then
			Pool.freeLight(light)
		end
	end
	local now0, nextDraw = os.clock(), 0
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			finish()
			return false
		end
		-- the ground ring, lit as the seal lights and fading once it lifts
		if t < ringOff then
			local on = math.min(t / SE.light, 1) * (1 - math.clamp((t - SE.light - SE.hold) / SE.ringFade, 0, 1))
			Ring.place(ring, pos + normal * R.lift, normal, sealR * (0.9 + 0.1 * ease(t / SE.light)), 1, 1 - on)
		elseif ring.beams[1].Enabled then
			for _, b in ring.beams do
				b.Enabled = false
			end
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
			local cf
			if r.seal then
				-- flat on the ground round the foot, then lifting off: standing up, spiralling out and up the column
				local up = math.max(rt - r.hold, 0)
				local lift = ease(up / 0.6)
				local a = r.angle + spiral * up
				local radial = side * math.cos(a) + other * math.sin(a)
				r.now = r.at + radial * r.radius * (1 + (SE.out - 1) * lift) + normal * r.rise * up
				cf = CFrame.new(r.now)
					* ground
					* CFrame.Angles(0, -a - math.pi / 2, 0)
					* CFrame.Angles(math.rad(SE.stand) * lift, 0, 0)
			else
				r.now = r.at + normal * r.float * rt
				cf = CFrame.new(r.now) * r.turn * CFrame.Angles(0, r.spin * rt, 0)
			end
			local see = 1 - r.show * (1 - R.flicker * rng:NextNumber())
			local seq = NumberSequence.new(see)
			-- a seal rune flares as it lights: its halo solid, thinning to the usual
			local haloSee = if r.seal then R.haloSee * math.min(rt / SE.flare, 1) else R.haloSee
			local haloSeq = NumberSequence.new(haloSee + (1 - haloSee) * see)
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
	end, finish)
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
	local kg = if charge then o.kg :: number else ShakeRules.stageKg(o.stage or 1, ShakeCfg.Stages)
	CameraShake.blast(pos, kg)
	Suppression.blast(pos, kg) -- (and rattles the own soldier: src/client/Suppression)
	Concussion.near(pos, kg) -- (and rings the own ears when it's close: src/client/Concussion)
	Flagpoles.blast(pos, kg) -- (capture-point flags near it whip)
	local dirt = dirtOf(pos, normal, o.debrisColor)
	-- the grenade: the same burst, small and short
	local P = Cfg.Pop
	local popping = o.pop == true
	if popping then
		st = { fireball = d, rings = 0, spikes = false }
		magic = false
	end

	local CO = Cfg.Colors
	local strength = Blast.strength(d)
	local hot, fire = Util.color(s[CO.hot] or s.flash), Util.color(s[CO.fire] or s.glow)
	local rimName = s.layers[CO.rim] or s.glow
	local rim = Util.color(rimName)
	local spark = s[CO.spark] or s.glow
	local now0 = os.clock()

	-- the flash, a light, magic's spikes and star, sparks and the air ring
	local F = Cfg.Flash
	local flash = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(pos + normal * d * 0.2))
	local glare = F.brightness * (if popping then P.light else 1)
	local light = Pool.light(pos + normal * F.lift, fire, math.min(F.range * d, F.max), glare)
	if st.spikes and magic then
		Spikes.play(pos + normal * d * 0.2, spark)
		Star.play(pos + normal * d * 0.2, spark, d * Cfg.Star)
	end
	local sp = Cfg.Sparks
	local sparked = sparks(pos, d, sp.perStud * d * (if popping then P.sparks else 1), hot, Util.color(spark))
	for i = 1, if magic then st.rings else 0 do
		task.delay((i - 1) * Cfg.Rings.gap, function()
			Shockwave.play(
				pos + normal * Cfg.Rings.lift,
				normal,
				rimName,
				d * Cfg.Rings.to * (1 + Cfg.Rings.grow * (i - 1))
			)
		end)
	end

	-- the fireball on the hit, swallowed by the earth
	local O = Cfg.Orb
	local orbAt = pos + normal * d * O.size * (0.5 - O.sink)
	local orb = Pool.part(Enum.PartType.Ball, fire, Vector3.one * 0.05, CFrame.new(orbAt))
	local core = Pool.part(Enum.PartType.Ball, hot, Vector3.one * 0.05, CFrame.new(orbAt))

	-- the earth and the smoke
	local CL = Cfg.Column
	local tall = d * (if popping then P.tall else lerp(CL.tall[1], CL.tall[2], strength))
	local life = if popping then P.columnLife else lerp(CL.life[1], CL.life[2], strength)
	-- (magic's smoke stays grey under its own coloured light: user 2026-10-17, "the actual explosion is blue, but not
	-- the smoke")
	local smokes, smokeEnd = column(pos, normal, d, dirt, strength, tall, life, if magic then CL.litMagic else 1)
	local spouted, spoutEnd = spout(pos, normal, d, dirt, strength, tall)
	local thrown, flight = clods(pos, normal, d, dirt, if popping then P.clods else 1, if popping then P.throw else 1)
	local SK = Cfg.Skirt
	local skirtLife = if popping then P.skirtLife else lerp(SK.life[1], SK.life[2], strength)
	local dust = skirt(pos, normal, d, dirt, strength, skirtLife)
	local SO = Cfg.Sods
	local flying = sods(pos, normal, d, dirt, math.round(lerp(SO.count[1], SO.count[2], strength)))
	if magic then
		task.delay(Cfg.Runes.delay, runes, pos, normal, d, strength, s)
	end

	local orbEnd = O.grow + O.hold + O.fade
	local sodEnd = 0
	for _, b in flying do
		sodEnd = math.max(sodEnd, b.land + SO.rest + SO.fade)
	end
	local total = math.max(F.light, orbEnd, smokeEnd, spoutEnd, sp.life[2], flight, skirtLife, sodEnd)
	local g = Vector3.new(0, -SO.gravity, 0)
	local orbDone = false
	local function finish()
		Pool.freePart(flash)
		if not orbDone then
			Pool.freePart(orb)
			Pool.freePart(core)
		end
		if light then
			Pool.freeLight(light)
		end
		for _, b in flying do
			Pool.freePart(b.part)
		end
		freeAll(smokes)
		freeAll(thrown)
		freeEmitter(spouted)
		freeEmitter(sparked)
		freeEmitter(dust)
	end
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			finish()
			return false
		end
		if t < F.time then
			flash.Size = Vector3.one * math.max(d * F.size * ease(t / F.time * 1.5), 0.05)
			flash.Transparency = t / F.time
		elseif flash.Transparency < 1 then
			flash.Transparency = 1
		end
		if light then
			light.Brightness = glare * (1 - math.min(t / F.light, 1)) ^ 2
		end

		-- the fireball: swells, holds white-hot a blink, then cools, shrinks and fades as the earth swallows it
		if not orbDone then
			if t >= orbEnd then
				orbDone = true
				Pool.freePart(orb)
				Pool.freePart(core)
			else
				local swell = ease(t / O.grow)
				local cool = math.clamp((t - O.grow - O.hold) / O.fade, 0, 1)
				local size = math.max(d * O.size * swell * (1 - (1 - O.shrink) * cool), 0.05)
				orb.Size = Vector3.one * size
				orb.Color = fire:Lerp(rim, cool)
				orb.Transparency = cool
				core.Size = Vector3.one * size * O.core * (1 - cool)
				core.Color = hot:Lerp(fire, cool)
				core.Transparency = cool
			end
		end

		-- the sods: flying, then lying where they landed, then fading
		for _, b in flying do
			local ft = math.min(t, b.land)
			local at = b.from + b.vel * ft + g * (ft * ft / 2)
			b.part.CFrame = CFrame.new(at) * CFrame.fromAxisAngle(b.axis, b.spin * ft) * b.turn
			b.part.Transparency = math.clamp((t - b.land - SO.rest) / SO.fade, 0, 1)
		end
		return true
	end, finish)
end

return Blast
