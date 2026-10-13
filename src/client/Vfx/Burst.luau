--!strict
-- Impact (Config/Vfx.Burst): a white flash ball inside a wider glow, a flash of light, spark streaks thrown out and
-- slowing, glowing shards, a shockwave ring on the surface, and chunks of whatever was hit (its color) thrown off
-- under gravity. Pooled pieces, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vfx = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx)
local Cfg = Vfx.Burst
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Shockwave = require(script.Parent.Shockwave)
local Streaks = require(script.Parent.Streaks)

local Burst = {}

export type Opts = {
	scheme: string?, -- Config/Vfx.Schemes (default: Ray's)
	normal: Vector3?, -- the surface's normal (default up)
	debrisColor: Color3?, -- chunks of this color fly off (none without it)
	scale: number?, -- sizes, speeds and counts x this (a small beam's small impact)
}

local rng = Random.new()

type Flyer = { part: Part, p0: Vector3, v: Vector3, spin: Vector3, size: Vector3, gravity: number, floor: number? }

function Burst.play(pos: Vector3, opts: Opts?)
	local o: Opts = opts or {}
	local s = (Vfx.Schemes :: any)[o.scheme or Vfx.Ray.Scheme]
	local normal = (o.normal or Vector3.yAxis).Unit
	local flash, glow = Util.color(s.flash), Util.color(s.glow)
	local k = o.scale or 1
	local now0 = os.clock()
	local function count(n: number): number
		return math.max(math.round(n * k), 1)
	end

	local balls = {
		{
			cfg = Cfg.Flash,
			part = Pool.part(Enum.PartType.Ball, flash, Vector3.one * Cfg.Flash.from * k, CFrame.new(pos)),
		},
		{
			cfg = Cfg.Glow,
			part = Pool.part(
				Enum.PartType.Ball,
				glow,
				Vector3.one * Cfg.Glow.from * k,
				CFrame.new(pos),
				Cfg.Glow.transparency
			),
		},
	}
	local l = Cfg.Light
	local light = Pool.light(pos + normal, glow, l.range * k, l.brightness)

	local sp = Cfg.Sparks
	local e = Pool.emitter(CFrame.new(pos), Vector3.one * 0.2)
	e.Texture = Util.SPARKLE
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Speed = NumberRange.new(sp.speed[1] * k, sp.speed[2] * k)
	e.Lifetime = NumberRange.new(sp.life[1], sp.life[2])
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = sp.drag
	e.Acceleration = Vector3.zero
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sp.size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0)
	e.Color = ColorSequence.new(flash, glow)
	e.LightEmission = 1
	e.Brightness = 6
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-1.5) -- stretched along the flight: streaks
	e:Emit(count(sp.count))
	task.delay(sp.life[2], function()
		Pool.freeEmitter(e)
	end)

	Shockwave.play(pos + normal * 0.2, normal, s.glow, Vfx.Shockwave.to * k)
	Streaks.play(pos, normal, k)

	local flyers: { Flyer } = {}
	local sh = Cfg.Shards
	for _ = 1, count(sh.count) do
		local d = (rng:NextUnitVector() + normal * 0.5).Unit
		local size = Vector3.new(sh.size * 0.5, sh.size * 0.5, sh.size * 1.6) * k
		table.insert(flyers, {
			part = Pool.part(Enum.PartType.Block, glow, size, CFrame.new(pos)),
			p0 = pos,
			v = d * rng:NextNumber(sh.speed[1], sh.speed[2]) * k,
			spin = rng:NextUnitVector() * 8,
			size = size,
			gravity = 0,
			floor = nil,
		})
	end
	local db = Cfg.Debris
	if o.debrisColor then
		local floor = if normal.Y > 0.5 then pos.Y else nil
		for _ = 1, count(db.count) do
			local d = (normal * db.up + rng:NextUnitVector() * (1 - db.up)).Unit
			local size = Vector3.one * rng:NextNumber(db.size[1], db.size[2]) * math.sqrt(k)
			table.insert(flyers, {
				part = Pool.part(
					Enum.PartType.Block,
					o.debrisColor,
					size,
					CFrame.new(pos),
					0,
					Enum.Material.SmoothPlastic
				),
				p0 = pos + normal * 0.3,
				v = d * rng:NextNumber(db.speed[1], db.speed[2]),
				spin = rng:NextUnitVector() * db.spin,
				size = size,
				gravity = db.gravity,
				floor = floor,
			})
		end
	end

	local total = math.max(Cfg.Glow.time, l.time, sh.life, if o.debrisColor then db.life else 0)
	Driver.add(function(now: number): boolean
		local t = now - now0
		if t >= total then
			for _, b in balls do
				Pool.freePart(b.part)
			end
			for _, f in flyers do
				Pool.freePart(f.part)
			end
			if light then
				Pool.freeLight(light)
			end
			return false
		end
		for _, b in balls do
			local a = math.min(t / b.cfg.time, 1)
			local ease = 1 - (1 - a) ^ 2
			b.part.Size = Vector3.one * (b.cfg.from + (b.cfg.to - b.cfg.from) * ease) * k
			local base = (b.cfg :: any).transparency or 0
			b.part.Transparency = base + (1 - base) * a
		end
		if light then
			light.Brightness = l.brightness * (1 - math.min(t / l.time, 1)) ^ 2
		end
		for _, f in flyers do
			local life = if f.gravity > 0 then db.life else sh.life
			local a = math.min(t / life, 1)
			local p
			if f.gravity > 0 then
				p = f.p0 + f.v * t + Vector3.new(0, -0.5 * f.gravity * t * t, 0)
				if f.floor and p.Y < f.floor + f.size.Y / 2 then
					p = Vector3.new(p.X, f.floor + f.size.Y / 2, p.Z)
				end
			else
				local slow = (1 - (1 - a) ^ 2) * life * 0.5 -- the shard decelerates to a stop
				p = f.p0 + f.v * slow
			end
			local r = f.spin * t
			f.part.CFrame = CFrame.new(p) * CFrame.Angles(r.X, r.Y, r.Z)
			f.part.Size = f.size * math.min(1, (1 - a) / 0.3) -- shrinks away over its last 30%
		end
		return true
	end)
end

return Burst
