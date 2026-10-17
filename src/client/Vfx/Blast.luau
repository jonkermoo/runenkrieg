--!strict
-- The staff beam's explosion (Config/Vfx.Blast; user 2026-10-17: a bright explosion in the beam's own colours, not red
-- and orange, "extra realistic effect wise. kind of like my example (but blue)"): a white-hot fireball swelling and
-- fading into a glow shell, then a billowing cloud of pale puffs with glowing patches burning through them (a bright
-- rim round a deep centre) that burn out as the cloud rolls up and thins; flames licking round its foot, sparks flung
-- out, embers drifting up, shockwave rings, a big light, and the impact burst (with the debris of what was hit).
-- Sized by the stage. Pooled pieces, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vfx = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx)
local Cfg = Vfx.Blast
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Burst = require(script.Parent.Burst)
local Shockwave = require(script.Parent.Shockwave)
local Spikes = require(script.Parent.Spikes)
local Star = require(script.Parent.Star)

local Blast = {}

local FIRE = "rbxasset://textures/particles/fire_main.dds" -- Roblox's own flame texture

export type Opts = {
	scheme: string?, -- Config/Vfx.Schemes (default: Ray's)
	normal: Vector3?, -- the surface's normal (default up)
	debrisColor: Color3?, -- what was hit: chunks of it fly off
	stage: number?, -- 1..3 (default 1)
}

local rng = Random.new()

-- a glowing patch on a puff: the deep centre and the bright rim round it, along `dir` from the puff's centre
type Patch = { deep: Part, rim: Part, dir: Vector3, burn: number }
type Puff = { part: Part, at: Vector3, size: number, start: number, patches: { Patch } }

local function between(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

-- a pooled emitter reset for a one-off burst (the caller sets the rest)
local function emitter(cf: CFrame, box: Vector3): ParticleEmitter
	local e = Pool.emitter(cf, box)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Transparency = NumberSequence.new(0)
	e.LightEmission = 1
	e.Acceleration = Vector3.zero
	e.Rotation = NumberRange.new(0, 0)
	e.RotSpeed = NumberRange.new(0, 0)
	return e
end

function Blast.play(pos: Vector3, opts: Opts?)
	local o: Opts = opts or {}
	local st = Cfg.Stages[math.clamp(o.stage or 1, 1, #Cfg.Stages)]
	local s = (Vfx.Schemes :: any)[o.scheme or Vfx.Ray.Scheme]
	local normal = (o.normal or Vector3.yAxis).Unit
	local flash, glow, core = Util.color(s.flash), Util.color(s.glow), Util.color(s.core)
	local deep = Util.color(s.haze)
	local char = Util.color(s.char or Cfg.Cloud.char)
	local smoke = Util.color(s.smoke or Cfg.Cloud.smoke)
	local d = st.fireball
	local now0 = os.clock()

	Burst.play(pos, { scheme = o.scheme, normal = normal, debrisColor = o.debrisColor, scale = Cfg.Burst * d / 4 })
	if st.spikes then
		Spikes.play(pos, s.flash)
		Star.play(pos, s.flash, d * Cfg.Star)
	end
	for i = 1, st.rings do
		task.delay((i - 1) * Cfg.Rings.gap, function()
			Shockwave.play(
				pos + normal * Cfg.Rings.lift,
				normal,
				s.glow,
				d * Cfg.Rings.to * (1 + Cfg.Rings.grow * (i - 1))
			)
		end)
	end

	local F, Sh, L, C = Cfg.Fireball, Cfg.Shell, Cfg.Light, Cfg.Cloud
	local fireball = Pool.part(Enum.PartType.Ball, flash, Vector3.one * F.start, CFrame.new(pos))
	local shell = Pool.part(Enum.PartType.Ball, glow, Vector3.one * F.start, CFrame.new(pos), Sh.transparency)
	local light = Pool.light(pos + normal * L.lift, glow, math.min(L.range * d, L.max), L.brightness)

	-- the cloud: puffs in a flattened dome over the hit, each with patches burning through it
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local other = normal:Cross(side)
	local puffs: { Puff } = {}
	for _ = 1, st.puffs do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = C.spread * d * math.sqrt(rng:NextNumber())
		local up = C.height * d * rng:NextNumber(C.low, 1)
		local at = pos + (side * math.cos(a) + other * math.sin(a)) * r + normal * up
		local p: Puff = {
			part = Pool.part(
				Enum.PartType.Ball,
				smoke,
				Vector3.one * 0.05,
				CFrame.new(at),
				0,
				Enum.Material.SmoothPlastic
			),
			at = at,
			size = d * between(C.size),
			start = rng:NextNumber(0, C.appear * C.stagger), -- the puffs pop in one after another
			patches = {},
		}
		local out = if (at - pos).Magnitude > 1e-3 then (at - pos).Unit else normal
		for _ = 1, math.round(between(C.patches)) do
			table.insert(p.patches, {
				deep = Pool.part(
					Enum.PartType.Ball,
					char,
					Vector3.one * 0.05,
					CFrame.new(at),
					0,
					Enum.Material.SmoothPlastic
				),
				rim = Pool.part(Enum.PartType.Ball, deep, Vector3.one * 0.05, CFrame.new(at)),
				dir = (out + rng:NextUnitVector() * C.jitter).Unit,
				burn = between(C.burn),
			})
		end
		table.insert(puffs, p)
	end

	-- flames licking round the cloud's foot
	local fl = Cfg.Flames
	local flames = emitter(CFrame.new(pos + normal * d * fl.lift), Vector3.new(d, d * fl.depth, d) * fl.box)
	flames.Texture = FIRE
	flames.Speed = NumberRange.new(fl.speed[1], fl.speed[2])
	flames.Lifetime = NumberRange.new(fl.life[1], fl.life[2])
	flames.SpreadAngle = Vector2.new(fl.spread, fl.spread)
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Drag = fl.drag
	flames.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, fl.size[1]),
		NumberSequenceKeypoint.new(0.4, fl.size[2]),
		NumberSequenceKeypoint.new(1, 0),
	})
	flames.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	flames.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, glow),
		ColorSequenceKeypoint.new(0.4, deep),
		ColorSequenceKeypoint.new(1, char),
	})
	flames.Brightness = fl.brightness
	flames.LightEmission = fl.emission
	flames.Orientation = Enum.ParticleOrientation.FacingCamera
	flames.Squash = NumberSequence.new(0)
	flames.Rotation = NumberRange.new(0, 360)
	flames.RotSpeed = NumberRange.new(-fl.spin, fl.spin)
	flames:Emit(math.round(fl.perStud * d))
	task.delay(fl.life[1], function()
		flames:Emit(math.round(fl.perStud * d * fl.again)) -- a second lick as the first dies
	end)

	-- sparks flung out along and off the surface, slowing
	local sp = Cfg.Sparks
	local sparks = emitter(CFrame.new(pos), Vector3.one * 0.2)
	sparks.Texture = Util.SPARKLE
	sparks.Speed = NumberRange.new(sp.speed[1] * d, sp.speed[2] * d)
	sparks.Lifetime = NumberRange.new(sp.life[1], sp.life[2])
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = sp.drag
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sp.size), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(flash, glow)
	sparks.Brightness = sp.brightness
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Squash = NumberSequence.new(-1.5)
	sparks:Emit(math.round(sp.perStud * d))

	-- embers: glowing motes drifting up out of the blast
	local em = Cfg.Embers
	local embers = emitter(CFrame.new(pos), Vector3.one * d * em.box)
	embers.Texture = Util.SPARKLE
	embers.Speed = NumberRange.new(em.rise[1], em.rise[2])
	embers.Lifetime = NumberRange.new(em.life[1], em.life[2])
	embers.SpreadAngle = Vector2.new(em.spread, em.spread)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Drag = em.drag
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, em.size), NumberSequenceKeypoint.new(1, 0) })
	embers.Color = ColorSequence.new(core, glow)
	embers.Brightness = em.brightness
	embers.Orientation = Enum.ParticleOrientation.FacingCamera
	embers.Squash = NumberSequence.new(0)
	embers:Emit(math.round(em.perStud * d))

	local fireEnd = F.grow + F.hold + F.fade
	local total = math.max(fireEnd, Sh.fade + F.grow, C.life + C.appear, L.time, sp.life[2], em.life[2], fl.life[2] * 2)
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			Pool.freePart(fireball)
			Pool.freePart(shell)
			for _, p in puffs do
				Pool.freePart(p.part)
				for _, pa in p.patches do
					Pool.freePart(pa.deep)
					Pool.freePart(pa.rim)
				end
			end
			if light then
				Pool.freeLight(light)
			end
			Pool.freeEmitter(sparks)
			Pool.freeEmitter(embers)
			Pool.freeEmitter(flames)
			return false
		end
		-- the fireball swells fast, holds white-hot, then fades and takes the glow's colour
		local g = math.min(t / F.grow, 1)
		local swell = 1 - (1 - g) ^ 3
		local fadeA = math.clamp((t - F.grow - F.hold) / F.fade, 0, 1)
		fireball.Size = Vector3.one * math.max(d * swell * (1 + F.swell * fadeA), 0.05)
		fireball.Transparency = fadeA
		fireball.Color = flash:Lerp(glow, fadeA)
		-- the shell round it, fading out
		local shA = math.clamp((t - F.grow) / Sh.fade, 0, 1)
		shell.Size = Vector3.one * math.max(d * Sh.size * swell * (1 + Sh.swell * shA), 0.05)
		shell.Transparency = Sh.transparency + (1 - Sh.transparency) * shA
		-- the cloud: each puff pops in, swells and rolls up, thinning at the end; its patches burn out
		for _, p in puffs do
			local pt = t - p.start
			if pt <= 0 then
				continue
			end
			local pop = math.min(pt / C.appear, 1)
			local grow = C.from + (1 - C.from) * (1 - (1 - pop) ^ 3)
			local size = p.size * grow * (1 + (C.swell - 1) * math.min(pt / C.life, 1))
			local at = p.at + Vector3.yAxis * C.rise * d * pt
			local fade = math.clamp((pt / C.life - (1 - C.fade)) / C.fade, 0, 1)
			p.part.Size = Vector3.one * size
			p.part.CFrame = CFrame.new(at)
			p.part.Transparency = fade
			local radius = size / 2
			for _, pa in p.patches do
				local b = math.clamp(pt / pa.burn, 0, 1) -- burnt out at 1: sunk back in and gone
				local sink = 1 - C.sink * b
				local shrink = 1 - C.shrink * b
				local gone = math.max(math.clamp((b - C.hot) / (1 - C.hot), 0, 1), fade)
				pa.deep.Size = Vector3.one * math.max(size * C.deep * shrink, 0.05)
				pa.deep.CFrame = CFrame.new(at + pa.dir * radius * C.deepOut * sink)
				pa.deep.Transparency = gone
				pa.rim.Size = Vector3.one * math.max(size * C.rim * shrink, 0.05)
				pa.rim.CFrame = CFrame.new(at + pa.dir * radius * C.rimOut * sink)
				pa.rim.Transparency = gone
			end
		end
		if light then
			light.Brightness = L.brightness * (1 - math.min(t / L.time, 1)) ^ 2
		end
		return true
	end)
end

return Blast
