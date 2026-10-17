--!strict
-- The staff beam's explosion (Config/Vfx.Blast; user 2026-10-17: a bright explosion in the beam's own colours, not red
-- and orange): a white-hot fireball swelling and fading into a glow shell, a lingering glow dome, sparks flung out,
-- embers drifting up, shockwave rings on the ground, a big light, and the impact burst (with the debris of what was
-- hit) inside. Sized by the stage. Pooled pieces, one Driver step.

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

export type Opts = {
	scheme: string?, -- Config/Vfx.Schemes (default: Ray's)
	normal: Vector3?, -- the surface's normal (default up)
	debrisColor: Color3?, -- what was hit: chunks of it fly off
	stage: number?, -- 1..3 (default 1)
}

function Blast.play(pos: Vector3, opts: Opts?)
	local o: Opts = opts or {}
	local st = Cfg.Stages[math.clamp(o.stage or 1, 1, #Cfg.Stages)]
	local s = (Vfx.Schemes :: any)[o.scheme or Vfx.Ray.Scheme]
	local normal = (o.normal or Vector3.yAxis).Unit
	local flash, glow, core = Util.color(s.flash), Util.color(s.glow), Util.color(s.core)
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

	local F, Sh, Dm, L = Cfg.Fireball, Cfg.Shell, Cfg.Dome, Cfg.Light
	local fireball = Pool.part(Enum.PartType.Ball, flash, Vector3.one * F.start, CFrame.new(pos))
	local shell = Pool.part(Enum.PartType.Ball, glow, Vector3.one * F.start, CFrame.new(pos), Sh.transparency)
	local dome = Pool.part(Enum.PartType.Ball, glow, Vector3.one * d * Dm.size, CFrame.new(pos), 1)
	local light = Pool.light(pos + normal * L.lift, glow, math.min(L.range * d, L.max), L.brightness)

	-- sparks flung out along and off the surface, slowing
	local sp = Cfg.Sparks
	local sparks = Pool.emitter(CFrame.new(pos), Vector3.one * 0.2)
	sparks.Texture = Util.SPARKLE
	sparks.Shape = Enum.ParticleEmitterShape.Box
	sparks.Speed = NumberRange.new(sp.speed[1] * d, sp.speed[2] * d)
	sparks.Lifetime = NumberRange.new(sp.life[1], sp.life[2])
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = sp.drag
	sparks.Acceleration = Vector3.zero
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sp.size), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0)
	sparks.Color = ColorSequence.new(flash, glow)
	sparks.LightEmission = 1
	sparks.Brightness = sp.brightness
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Squash = NumberSequence.new(-1.5)
	sparks:Emit(math.round(sp.perStud * d))

	-- embers: glowing motes drifting up out of the blast
	local em = Cfg.Embers
	local embers = Pool.emitter(CFrame.new(pos), Vector3.one * d * em.box)
	embers.Texture = Util.SPARKLE
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.Speed = NumberRange.new(em.rise[1], em.rise[2])
	embers.Lifetime = NumberRange.new(em.life[1], em.life[2])
	embers.SpreadAngle = Vector2.new(em.spread, em.spread)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Drag = em.drag
	embers.Acceleration = Vector3.zero
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, em.size), NumberSequenceKeypoint.new(1, 0) })
	embers.Transparency = NumberSequence.new(0)
	embers.Color = ColorSequence.new(core, glow)
	embers.LightEmission = 1
	embers.Brightness = em.brightness
	embers.Orientation = Enum.ParticleOrientation.FacingCamera
	embers.Squash = NumberSequence.new(0)
	embers:Emit(math.round(em.perStud * d))

	local fireEnd = F.grow + F.hold + F.fade
	local total = math.max(fireEnd, Sh.fade + F.grow, Dm.fade, L.time, sp.life[2], em.life[2])
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			Pool.freePart(fireball)
			Pool.freePart(shell)
			Pool.freePart(dome)
			if light then
				Pool.freeLight(light)
			end
			Pool.freeEmitter(sparks)
			Pool.freeEmitter(embers)
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
		-- the dome glows on as the fireball goes, then fades slowly
		local domeIn = math.clamp((t - F.grow) / Dm.fadeIn, 0, 1)
		local domeOut = math.clamp(t / Dm.fade, 0, 1)
		dome.Transparency = 1 - (1 - Dm.transparency) * domeIn * (1 - domeOut) ^ 2
		if light then
			light.Brightness = L.brightness * (1 - math.min(t / L.time, 1)) ^ 2
		end
		return true
	end)
end

return Blast
