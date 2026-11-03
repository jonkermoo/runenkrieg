--!strict
-- The machine gun's firing smoke (Config/Vfx.Gunsmoke; src/client/Artillery's MGShot, a bot's shots as a player's;
-- user 2026-11-03: "add better smoke effects to the MG. i dont like the sparkle"): a short flat flame out of the
-- muzzle for a moment (no glowing ball, no light), thin grey-white puffs thrown out along the bore each shot, and a
-- light haze building round the gun in a long burst (Rules/Gunsmoke: the gun's heat) that clears once it stops.
-- Each gun keeps two pooled emitters while it fires and gives them back when its haze has died away.
--   Gunsmoke.shot(gun, origin, direction)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Vfx).Gunsmoke
local Rules = require(Shared.Rules.Gunsmoke)
local Driver = require(script.Parent.Driver)
local Pool = require(script.Parent.Pool)
local Util = require(script.Parent.Util)

local Gunsmoke = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture (as Vfx/Muzzle's)

local rng = Random.new()

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- a frame at `at` whose up (+Y, an emitter's Top) points along `up`
local function facing(at: Vector3, up: Vector3): CFrame
	local right = up:Cross(Vector3.yAxis)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	return CFrame.fromMatrix(at, right, up)
end

-- Roblox's smoke in `s.color`, lit by the scene
local function smoke(s: any, rise: number): ParticleEmitter
	local e = Pool.emitter(CFrame.identity, Vector3.one * 0.1)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Texture = SMOKE
	e.EmissionDirection = Enum.NormalId.Top
	e.Speed = NumberRange.new(s.speed[1], s.speed[2])
	e.Lifetime = NumberRange.new(s.life[1], s.life[2])
	e.SpreadAngle = Vector2.new(s.spread, s.spread)
	e.Drag = s.drag or 0
	e.Acceleration = Vector3.new(Cfg.wind[1], Cfg.wind[2] + rise, Cfg.wind[3])
	e.Size = sequence(s.size[1], s.size[2])
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
	e.Rate = 0
	e.Enabled = false
	return e
end

-- the short flat flame: a tapered ribbon out along the bore in flat flame colour with a hot shorter one inside it (only
-- the core glows), gone after `time`
local function flash(origin: Vector3, dir: Vector3)
	local F = Cfg.Flash
	local long = F.long * (0.7 + 0.3 * rng:NextNumber())
	local base, tip, coreTip =
		Pool.att(origin), Pool.att(origin + dir * long), Pool.att(origin + dir * long * F.coreShare)
	local outer = Pool.beam(base, tip, Util.color(F.color), F.wide, 0, 0, 1, 0)
	local inner = Pool.beam(base, coreTip, Util.color(F.core), F.wide * F.coreShare, 0, 0, 1, 1)
	inner.ZOffset = 0.05
	local gone = os.clock() + F.time
	Driver.add(function(now: number): boolean
		if now < gone then
			return true
		end
		Pool.freeBeam(outer)
		Pool.freeBeam(inner)
		Pool.freeAtt(base)
		Pool.freeAtt(tip)
		Pool.freeAtt(coreTip)
		return false
	end)
end

type Nest = { puff: ParticleEmitter, haze: ParticleEmitter, heat: number, last: number }

local nests: { [any]: Nest } = {}

local function nestOf(gun: any): Nest
	local n = nests[gun]
	if n then
		return n
	end
	local H = Cfg.Haze
	local made: Nest = { puff = smoke(Cfg.Puff, 0), haze = smoke(H, H.rise), heat = 0, last = os.clock() }
	nests[gun] = made
	-- its haze follows the heat; its emitters go back once it is cold and its last puffs have died
	local keep = math.max(Cfg.Puff.life[2], H.life[2])
	Driver.add(function(now: number, dt: number): boolean
		made.heat = Rules.heat(made.heat, dt, 0, H.decay, H.cap)
		local rate = Rules.haze(made.heat, H.start, H.full, H.rate)
		made.haze.Rate = rate
		made.haze.Enabled = rate > 0
		if made.heat > 0 or now - made.last < keep then
			return true
		end
		nests[gun] = nil
		Pool.freeEmitter(made.puff)
		Pool.freeEmitter(made.haze)
		return false
	end)
	return made
end

-- one shot of `gun` (any key: the gun's model) from `origin` along `direction`
function Gunsmoke.shot(gun: any, origin: Vector3, direction: Vector3)
	local dir = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.zAxis
	flash(origin, dir)
	local camera = workspace.CurrentCamera
	local near = not camera or (origin - camera.CFrame.Position).Magnitude <= Cfg.far
	local n = nestOf(gun)
	n.last = os.clock()
	local puff = n.puff
	local box = puff.Parent :: Part
	box.CFrame = facing(origin, dir)
	puff:Emit(if near then Cfg.Puff.count else 1)
	-- far off no haze builds
	n.heat = if near then Rules.heat(n.heat, 0, 1, Cfg.Haze.decay, Cfg.Haze.cap) else 0
	local hbox = n.haze.Parent :: Part
	hbox.CFrame = facing(origin + dir * Cfg.Haze.ahead, Vector3.yAxis)
	hbox.Size = Vector3.new(1, 0.2, 1)
end

return Gunsmoke
