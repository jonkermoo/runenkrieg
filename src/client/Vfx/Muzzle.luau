--!strict
-- A gun's muzzle blast (Config/Vfx.Muzzle; the artillery, src/client/Artillery; docs/VFX.md "Artillery"), in beats
-- (user 2026-10-26: "make it super 'visual' and appealing"): a fireball of layered beams shooting out along the bore
-- with flame tongues fanned round it, a white-hot flash ball with a light and a star glint for a moment; a jet of grey
-- smoke thrown out along the bore that slows and spreads, a smoke ring flung forward round it (on the magic gun a
-- glowing rune ring rolling out inside it), a ring of side blast puffing out round the muzzle, burning grains
-- thrown forward and falling, dust kicked up off the ground under it and swept forward across the ground in front.
-- All of it scales with `scale` (the gun's size) and takes its colours from a look (Config/Vfx.Muzzle.Looks). Far
-- off (`full` false) only the flash, fireball, glint and jet. Pooled and driven like the rest of the library.
--   Muzzle.play(origin, direction, scale?, look?, full?)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx")).Muzzle
local Driver = require(script.Parent.Driver)
local Pool = require(script.Parent.Pool)
local Ring = require(script.Parent.Ring)
local Star = require(script.Parent.Star)
local Util = require(script.Parent.Util)

local Muzzle = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture (as the blast's column)

local rng = Random.new()

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function ease(k: number): number
	return 1 - (1 - math.clamp(k, 0, 1)) ^ 3
end

-- a smoke emitter at `cf` (its top face along the jet): Roblox's smoke in `color`, lit by the scene
local function smoke(cf: CFrame, box: Vector3, s: any, scale: number): ParticleEmitter
	local e = Pool.emitter(cf, box)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Texture = SMOKE
	e.EmissionDirection = Enum.NormalId.Top
	e.Speed = NumberRange.new(s.speed[1] * scale, s.speed[2] * scale)
	e.Lifetime = NumberRange.new(s.life[1], s.life[2])
	e.SpreadAngle = Vector2.new(s.spread, s.spread)
	e.Drag = s.drag
	e.Acceleration = Vector3.new(Cfg.wind[1], Cfg.wind[2], Cfg.wind[3])
	e.Size = sequence(s.size[1] * scale, s.size[2] * scale)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(Cfg.fadeIn, s.thick),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Util.color(s.color))
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Brightness = 1
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Squash = NumberSequence.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-Cfg.spin, Cfg.spin)
	return e
end

-- a frame at `at` whose up (+Y, an emitter's Top) points along `up`
local function facing(at: Vector3, up: Vector3): CFrame
	local right = up:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	return CFrame.fromMatrix(at, right, up)
end

type Flame = { tip: Attachment, beam: Beam, dir: Vector3, length: number, width: number }

function Muzzle.play(origin: Vector3, direction: Vector3, scale: number?, look: string?, full: boolean?)
	local k = scale or 1
	local L = (Cfg.Looks :: any)[look or "Field"] or Cfg.Looks.Field
	local near = full ~= false
	local dir = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis
	local along = facing(origin, dir)
	local F = Cfg.Flash
	local flash = Pool.part(
		Enum.PartType.Ball,
		Util.color(L.flash),
		Vector3.one * F.size * k,
		CFrame.new(origin + dir * F.size * k * 0.3)
	)
	local light = Pool.light(origin, Util.color(L.flash), F.light * k, F.brightness)

	-- the fireball: layered cones from the muzzle out along the bore (outer to core), and flame tongues round it
	local R = Cfg.Fire
	local root = Pool.att(origin)
	local flames: { Flame } = {}
	for i, name in L.fire do
		local w = R.width * k * R.layer ^ (i - 1)
		local core = i == #L.fire
		local tip = Pool.att(origin)
		local b = Pool.beam(root, tip, Util.color(name), w, 0, 0, R.brightness, if core then 1 else R.emission)
		b.ZOffset = i * 0.1
		table.insert(
			flames,
			{ tip = tip, beam = b, dir = dir, length = R.length * k * (1 - 0.12 * (i - 1)), width = w }
		)
	end
	for _ = 1, R.tongues do
		local roll = CFrame.fromAxisAngle(dir, rng:NextNumber(0, 2 * math.pi))
		local side = roll:VectorToWorldSpace(along.RightVector)
		local off = math.rad(rng:NextNumber(0.3, 1) * R.fan)
		local d = (dir * math.cos(off) + side * math.sin(off)).Unit
		local w = R.width * k * 0.35
		local tip = Pool.att(origin)
		local b = Pool.beam(root, tip, Util.color(L.fire[2]), w, 0, 0, R.brightness, R.emission)
		table.insert(flames, {
			tip = tip,
			beam = b,
			dir = d,
			length = R.length * k * R.tongue * rng:NextNumber(0.6, 1),
			width = w,
		})
	end
	Star.play(origin + dir * 0.5 * k, L.glint, Cfg.Glint.length * k)

	-- the jet along the bore
	local J, S, D = Cfg.Jet, Cfg.Side, Cfg.Dust
	local jet = smoke(along, Vector3.one * 0.4 * k, J, k)
	jet:Emit(J.count)
	local emitters: { ParticleEmitter } = { jet }
	local life = math.max(J.life[2], F.time, R.time)

	local rune: Ring.Ring? = nil
	local ticks: { { a0: Attachment, a1: Attachment, beam: Beam } } = {}
	if near then
		-- the side blast round the muzzle
		local side = smoke(along, Vector3.one * 0.3 * k, S, k)
		side:Emit(S.count)
		table.insert(emitters, side)
		-- the smoke ring: one puff at each point round it, flung forward and out
		local G = Cfg.Ring
		local ring = smoke(along, Vector3.one * 0.2 * k, G, k)
		ring.SpreadAngle = Vector2.new(4, 4)
		local p = ring.Parent :: Part
		for i = 1, G.count do
			local a = (i - 1) / G.count * 2 * math.pi
			local radial = along.RightVector * math.cos(a) + along.LookVector * math.sin(a)
			p.CFrame = facing(origin + radial * G.radius * k, (dir + radial * 0.55).Unit)
			ring:Emit(1)
		end
		table.insert(emitters, ring)
		-- burning grains thrown out along the bore, falling
		local E = Cfg.Embers
		local embers = Pool.emitter(along, Vector3.one * 0.3 * k)
		embers.Shape = Enum.ParticleEmitterShape.Box
		embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		embers.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		embers.Texture = Util.SPARKLE
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Speed = NumberRange.new(E.speed[1] * k, E.speed[2] * k)
		embers.Lifetime = NumberRange.new(E.life[1], E.life[2])
		embers.SpreadAngle = Vector2.new(E.spread, E.spread)
		embers.Drag = E.drag
		embers.Acceleration = Vector3.new(0, -E.gravity, 0)
		embers.Size = sequence(E.size * k, 0)
		embers.Transparency = sequence(0, 0.6)
		embers.Color = ColorSequence.new(Util.color(L.embers))
		embers.LightEmission = 1
		embers.LightInfluence = 0
		embers.Brightness = 3
		embers.Orientation = Enum.ParticleOrientation.FacingCamera
		embers.Squash = NumberSequence.new(0)
		embers.Rotation = NumberRange.new(0, 360)
		embers.RotSpeed = NumberRange.new(0, 0)
		embers:Emit(E.count)
		table.insert(emitters, embers)
		-- dust off the ground under the muzzle (when it's near the ground), and swept forward across it
		local hit = workspace:Raycast(origin, Vector3.new(0, -D.reach * k, 0))
		if hit then
			local e = smoke(CFrame.new(hit.Position), Vector3.new(D.width * k, 0.2, D.width * k), D, k)
			e:Emit(D.count)
			table.insert(emitters, e)
			local N = Cfg.Fan
			local flat = Vector3.new(dir.X, 0, dir.Z)
			flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
			local lift = math.rad(N.lift)
			local fan = smoke(
				facing(hit.Position, flat * math.cos(lift) + Vector3.yAxis * math.sin(lift)),
				Vector3.new(D.width * k * 0.5, 0.2, D.width * k * 0.5),
				N,
				k
			)
			fan:Emit(N.count)
			table.insert(emitters, fan)
			life = math.max(life, D.life[2], N.life[2])
		end
		life = math.max(life, S.life[2], G.life[2], E.life[2])
		-- the magic gun's rune ring rolling out inside the smoke ring
		if L.ring then
			local U = Cfg.Rune
			local color = Util.color(L.ring)
			rune = Ring.new(color, U.line * k, U.brightness)
			for _ = 1, U.ticks do
				local a0, a1 = Pool.att(origin), Pool.att(origin)
				table.insert(
					ticks,
					{ a0 = a0, a1 = a1, beam = Pool.beam(a0, a1, color, U.line * k, U.line * k, 0, U.brightness) }
				)
			end
			life = math.max(life, U.time)
		end
	end

	local now0 = os.clock()
	local flashGone, fireGone, runeGone = false, false, rune == nil
	Driver.add(function(now: number): boolean
		local t = now - now0
		if not flashGone and t >= F.time then
			flashGone = true
			Pool.freePart(flash)
			if light then
				Pool.freeLight(light)
			end
		elseif not flashGone then
			flash.Transparency = t / F.time
		end
		if not fireGone and t >= R.time then
			fireGone = true
			for _, f in flames do
				Pool.freeBeam(f.beam)
				Pool.freeAtt(f.tip)
			end
			Pool.freeAtt(root)
		elseif not fireGone then
			local a = t / R.time
			local grow = R.grow[1] + (R.grow[2] - R.grow[1]) * ease(a * 2)
			for _, f in flames do
				f.tip.Position = origin + f.dir * f.length * grow
				f.beam.Width0 = f.width * (1 - 0.4 * a)
				f.beam.Transparency = NumberSequence.new(a * a)
			end
		end
		local ring = rune
		if ring and not runeGone then
			local U = Cfg.Rune
			local a = t / U.time
			if a >= 1 then
				runeGone = true
				Ring.free(ring)
				for _, tk in ticks do
					Pool.freeBeam(tk.beam)
					Pool.freeAtt(tk.a0)
					Pool.freeAtt(tk.a1)
				end
			else
				local e = ease(a * 1.5)
				local c = origin + dir * U.ahead * k * e
				local r = U.radius * k * (0.2 + 0.8 * e)
				Ring.place(ring, c, dir, r, 1 - 0.5 * a, a * a)
				local spin = math.rad(U.spin * t)
				for i, tk in ticks do
					local ang = spin + (i - 1) / #ticks * 2 * math.pi
					local radial = along.RightVector * math.cos(ang) + along.LookVector * math.sin(ang)
					tk.a0.Position = c + radial * r
					tk.a1.Position = c + radial * (r + U.tick * k)
					tk.beam.Transparency = NumberSequence.new(a * a)
				end
			end
		end
		if t >= life then
			for _, e in emitters do
				Pool.freeEmitter(e)
			end
			return false
		end
		return true
	end)
end

return Muzzle
