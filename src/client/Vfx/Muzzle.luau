--!strict
-- A gun's muzzle blast (Config/Vfx.Muzzle; the artillery, src/client/Artillery; docs/VFX.md "Artillery"): a white-hot
-- flash ball with a light for a moment, a jet of grey smoke thrown out along the bore that slows and spreads, a ring
-- of side blast puffing out round the muzzle, and dust kicked up off the ground under it. All of it scales with
-- `scale` (the gun's size). Pooled and driven like the rest of the library.
--   Muzzle.play(origin, direction, scale?)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Vfx")).Muzzle
local Driver = require(script.Parent.Driver)
local Pool = require(script.Parent.Pool)
local Util = require(script.Parent.Util)

local Muzzle = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture (as the blast's column)

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
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
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Brightness = 1
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Squash = NumberSequence.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-Cfg.spin, Cfg.spin)
	return e
end

function Muzzle.play(origin: Vector3, direction: Vector3, scale: number?)
	local k = scale or 1
	local dir = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis
	-- a frame whose up (+Y, the emitters' Top) points along the bore
	local right = dir:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local along = CFrame.fromMatrix(origin, right, dir)
	local F = Cfg.Flash
	local flash = Pool.part(
		Enum.PartType.Ball,
		Util.color(F.color),
		Vector3.one * F.size * k,
		CFrame.new(origin + dir * F.size * k * 0.3)
	)
	local light = Pool.light(origin, Util.color(F.color), F.light * k, F.brightness)

	-- the jet along the bore, and the side blast round the muzzle
	local J, S, D = Cfg.Jet, Cfg.Side, Cfg.Dust
	local jet = smoke(along, Vector3.one * 0.4 * k, J, k)
	jet:Emit(J.count)
	local side = smoke(along, Vector3.one * 0.3 * k, S, k)
	side:Emit(S.count)
	-- dust off the ground under the muzzle (when it's near the ground)
	local hit = workspace:Raycast(origin, Vector3.new(0, -D.reach * k, 0))
	local dust: ParticleEmitter? = nil
	if hit then
		local e = smoke(CFrame.new(hit.Position), Vector3.new(D.width * k, 0.2, D.width * k), D, k)
		e:Emit(D.count)
		dust = e
	end

	local now0 = os.clock()
	local total = math.max(J.life[2], S.life[2], D.life[2], F.time)
	local flashGone = false
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
		if t >= total then
			Pool.freeEmitter(jet)
			Pool.freeEmitter(side)
			if dust then
				Pool.freeEmitter(dust)
			end
			return false
		end
		return true
	end)
end

return Muzzle
