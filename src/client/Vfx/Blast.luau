--!strict
-- The staff beam's explosion (Config/Vfx.Blast; user 2026-10-17: a bright explosion in the beam's own colours, not red
-- and orange, "extra realistic effect wise. kind of like my example (but blue)"; then "make sure the actual explosion is
-- blue, but not the smoke"): a fireball in the scheme's colours (Blast.Colors) swelling and fading into a shell, then a
-- billowing cloud of puffs, each a bright inside in a darker rim, cooling as the cloud rolls up and thins; flames
-- licking round its foot, sparks flung out, embers drifting up, shockwave rings, a big light, and the impact burst
-- (with the debris of what was hit). Then a column of real-looking smoke (Roblox's smoke texture, plain grey) rolls up
-- and drifts off over several seconds.
-- Sized by a staff stage, or by a charge in kg (the real fireball's size: cannon shells later, user 2026-10-17:
-- "explosions will come from cannons later too ... make sure explosion smokes look realistic"). Pooled pieces, one
-- Driver step.

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
local ScreenBlur = require(script.Parent.Parent.ScreenBlur)

local Blast = {}

local FIRE = "rbxasset://textures/particles/fire_main.dds" -- Roblox's own flame texture

export type Opts = {
	scheme: string?, -- Config/Vfx.Schemes (default: Ray's)
	normal: Vector3?, -- the surface's normal (default up)
	debrisColor: Color3?, -- what was hit: chunks of it fly off
	stage: number?, -- a staff stage 1..3 (default 1): Config/Vfx.Blast.Stages
	kg: number?, -- or a charge of this many kg of TNT: sized as its real fireball (Config/Vfx.Blast.Charge)
	magic: boolean?, -- a charge with the magic glint and light spikes too (default: a plain explosion)
}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture

local rng = Random.new()

-- a puff: its rim and the bright inside shown in front of it
type Puff = { part: Part, inside: Part, at: Vector3, size: number, start: number }

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

-- a `kg` charge's fireball, studs across (Config/Vfx.Blast.Charge: D = a x W^b metres)
function Blast.fireball(kg: number): number
	local K = Cfg.Charge
	return K.a * kg ^ K.b / K.metresPerStud
end

function Blast.play(pos: Vector3, opts: Opts?)
	local o: Opts = opts or {}
	local st: any = Cfg.Stages[math.clamp(o.stage or 1, 1, #Cfg.Stages)]
	if o.kg and o.kg > 0 then
		local K = Cfg.Charge
		local d = Blast.fireball(o.kg)
		st = {
			fireball = d,
			rings = K.rings,
			spikes = o.magic == true,
			puffs = math.max(math.round(d * K.puffsPerStud), 3),
			life = 1,
		}
	end
	local s = (Vfx.Schemes :: any)[o.scheme or Vfx.Ray.Scheme]
	local normal = (o.normal or Vector3.yAxis).Unit
	local CO = Cfg.Colors
	local function role(name: string): string
		return s[name] or s.glow
	end
	local function color(name: string): Color3
		return Util.color(role(name))
	end
	local fire, shellColor = color(CO.fireball), color(CO.shell)
	local inside, rim, spark = color(CO.inside), color(CO.rim), color(CO.spark)
	local glow = Util.color(s.glow)
	local d = st.fireball
	ScreenBlur.blast(pos, d) -- the screen blur when it's close (src/client/ScreenBlur)
	local now0 = os.clock()

	Burst.play(pos, { scheme = o.scheme, normal = normal, debrisColor = o.debrisColor, scale = Cfg.Burst * d / 4 })
	if st.spikes then
		Spikes.play(pos, role(CO.spark))
		Star.play(pos, role(CO.spark), d * Cfg.Star)
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
	local lives = st.life or 1 -- the smaller stages' cloud and smoke go sooner
	local cloudLife = C.life * lives
	local fireball = Pool.part(Enum.PartType.Ball, fire, Vector3.one * F.start, CFrame.new(pos))
	local shell = Pool.part(Enum.PartType.Ball, shellColor, Vector3.one * F.start, CFrame.new(pos), Sh.transparency)
	local light = Pool.light(pos + normal * L.lift, glow, math.min(L.range * d, L.max), L.brightness)

	-- the cloud: puffs in a flattened dome over the hit, each a bright inside in a darker rim
	local side = normal:Cross(if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local other = normal:Cross(side)
	local puffs: { Puff } = {}
	for _ = 1, st.puffs do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = C.spread * d * math.sqrt(rng:NextNumber())
		local up = C.height * d * rng:NextNumber(C.low, 1)
		local at = pos + (side * math.cos(a) + other * math.sin(a)) * r + normal * up
		table.insert(puffs, {
			part = Pool.part(Enum.PartType.Ball, rim, Vector3.one * 0.05, CFrame.new(at)),
			inside = Pool.part(Enum.PartType.Ball, inside, Vector3.one * 0.05, CFrame.new(at)),
			at = at,
			size = d * between(C.size),
			start = rng:NextNumber(0, C.appear * C.stagger), -- the puffs pop in one after another
		})
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
		ColorSequenceKeypoint.new(0, color(CO.flames[1])),
		ColorSequenceKeypoint.new(1, color(CO.flames[2])),
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
	sparks.Color = ColorSequence.new(spark, glow)
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
	embers.Color = ColorSequence.new(color(CO.embers[1]), color(CO.embers[2]))
	embers.Brightness = em.brightness
	embers.Orientation = Enum.ParticleOrientation.FacingCamera
	embers.Squash = NumberSequence.new(0)
	embers:Emit(math.round(em.perStud * d))

	-- the smoke column: grey smoke rolling up out of the cloud and drifting off, outliving it
	local sm = Cfg.Smoke
	local ash = Util.color(sm.color)
	local column = Pool.emitter(CFrame.new(pos + normal * d * sm.lift), Vector3.new(d, d * sm.depth, d) * sm.box)
	column.Shape = Enum.ParticleEmitterShape.Box
	column.Texture = SMOKE
	column.Speed = NumberRange.new(sm.rise[1] * d, sm.rise[2] * d)
	column.Lifetime = NumberRange.new(sm.life[1] * lives, sm.life[2] * lives)
	column.SpreadAngle = Vector2.new(sm.spread, sm.spread)
	column.EmissionDirection = Enum.NormalId.Top
	column.Drag = sm.drag
	column.Acceleration = Vector3.new(sm.wind[1], sm.wind[2], sm.wind[3])
	column.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, d * sm.size[1]),
		NumberSequenceKeypoint.new(1, d * sm.size[2]),
	})
	column.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(sm.fadeIn, sm.thick),
		NumberSequenceKeypoint.new(1, 1),
	})
	column.Color = ColorSequence.new(ash)
	column.LightEmission = 0
	column.LightInfluence = 1
	column.Brightness = 1
	column.Orientation = Enum.ParticleOrientation.FacingCamera
	column.Squash = NumberSequence.new(0)
	column.Rotation = NumberRange.new(0, 360)
	column.RotSpeed = NumberRange.new(-sm.spin, sm.spin)
	task.delay(sm.delay, function()
		column:Emit(math.max(math.round(sm.perStud * d), 2))
	end)

	local fireEnd = F.grow + F.hold + F.fade
	local total = math.max(
		fireEnd,
		Sh.fade + F.grow,
		cloudLife + C.appear,
		L.time,
		sp.life[2],
		em.life[2],
		fl.life[2] * 2,
		sm.delay + sm.life[2] * lives
	)
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			Pool.freePart(fireball)
			Pool.freePart(shell)
			for _, p in puffs do
				Pool.freePart(p.part)
				Pool.freePart(p.inside)
			end
			if light then
				Pool.freeLight(light)
			end
			Pool.freeEmitter(sparks)
			Pool.freeEmitter(embers)
			Pool.freeEmitter(flames)
			column.LightInfluence = 0 -- (the pool's default for the other effects)
			Pool.freeEmitter(column)
			return false
		end
		-- the fireball swells fast, holds, then fades and takes the shell's colour
		local g = math.min(t / F.grow, 1)
		local swell = 1 - (1 - g) ^ 3
		local fadeA = math.clamp((t - F.grow - F.hold) / F.fade, 0, 1)
		fireball.Size = Vector3.one * math.max(d * swell * (1 + F.swell * fadeA), 0.05)
		fireball.Transparency = fadeA
		fireball.Color = fire:Lerp(shellColor, fadeA)
		-- the shell round it, fading out
		local shA = math.clamp((t - F.grow) / Sh.fade, 0, 1)
		shell.Size = Vector3.one * math.max(d * Sh.size * swell * (1 + Sh.swell * shA), 0.05)
		shell.Transparency = Sh.transparency + (1 - Sh.transparency) * shA
		-- the cloud: each puff pops in, swells and rolls up, thinning at the end; its bright inside, turned to the
		-- camera, cools into the rim
		local eye = workspace.CurrentCamera.CFrame.Position
		for _, p in puffs do
			local pt = t - p.start
			if pt <= 0 then
				continue
			end
			local pop = math.min(pt / C.appear, 1)
			local grow = C.from + (1 - C.from) * (1 - (1 - pop) ^ 3)
			local fade = math.clamp((pt / cloudLife - (1 - C.fade)) / C.fade, 0, 1)
			local size = p.size * grow * (1 + (C.swell - 1) * math.min(pt / cloudLife, 1)) * (1 - C.shrink * fade)
			local at = p.at + Vector3.yAxis * C.rise * d * pt
			p.part.Size = Vector3.one * size
			p.part.CFrame = CFrame.new(at)
			p.part.Transparency = fade
			local cool = math.clamp((pt / cloudLife - C.hot) / (1 - C.hot), 0, 1)
			p.part.Color = rim:Lerp(Color3.new(), C.rimDark * cool)
			local toEye = eye - at
			toEye = if toEye.Magnitude > 1e-3 then toEye.Unit else Vector3.zero
			p.inside.Size = Vector3.one * size * C.inner
			p.inside.CFrame = CFrame.new(at + (toEye * C.toward + Vector3.yAxis * C.up) * size / 2)
			p.inside.Color = inside:Lerp(rim, cool)
			p.inside.Transparency = fade
		end
		if light then
			light.Brightness = L.brightness * (1 - math.min(t / L.time, 1)) ^ 2
		end
		return true
	end)
end

return Blast
