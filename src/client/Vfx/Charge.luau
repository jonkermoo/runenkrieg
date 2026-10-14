--!strict
-- A gathering charge (Config/Vfx.Charge): sparkles drawn in from all round to a white orb that swells inside a soft
-- shell while the light rises; on release the orb snaps out. Pooled pieces, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Charge
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Charge = {}

-- veil(v): see-through by v (0 = solid; the caster's own charge in first person, Config/Spells.Staff.Veil)
export type Handle = { release: () -> (), move: (pos: Vector3) -> (), veil: (v: number) -> () }

function Charge.start(pos: Vector3, duration: number?, colorName: string?): Handle
	local t = duration or Cfg.Duration
	local color, core = Util.color(colorName or Cfg.Color), Util.color(Cfg.Core)
	local g = Cfg.Gather
	local orb = Pool.part(Enum.PartType.Ball, core, Vector3.one * 0.05, CFrame.new(pos))
	local shell = Pool.part(Enum.PartType.Ball, color, Vector3.one * 0.05, CFrame.new(pos), Cfg.ShellTransparency)

	-- sparkles start on a sphere and fly in to the centre in their lifetime
	local e = Pool.emitter(CFrame.new(pos), Vector3.one * g.radius * 2)
	e.Texture = Util.SPARKLE
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	e.Speed = NumberRange.new(g.radius / g.life)
	e.Lifetime = NumberRange.new(g.life)
	e.SpreadAngle = Vector2.zero
	e.Drag = 0
	e.Acceleration = Vector3.zero
	e.Rate = g.rate
	e.Size = NumberSequence.new(g.size * 0.4, g.size)
	e.Transparency = NumberSequence.new(0.4, 0)
	e.Color = ColorSequence.new(color, core)
	e.LightEmission = 1
	e.Brightness = 5
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-1)
	e.Enabled = true
	local light = Pool.light(pos, color, Cfg.Light.range, 0)

	local now0 = os.clock()
	local releasedAt: number? = nil
	local veil = 0
	local function seen(x: number): number -- a transparency through the veil
		return 1 - (1 - x) * (1 - veil)
	end
	Driver.add(function(now: number): boolean
		local rel = releasedAt
		if rel then
			local a = (now - rel) / Cfg.Pop
			if a >= 2 then
				Pool.freePart(orb)
				Pool.freePart(shell)
				if light then
					Pool.freeLight(light)
				end
				return false
			end
			local pop = math.min(a, 1)
			orb.Size = Vector3.one * Cfg.Orb * (1 + 1.2 * pop)
			orb.Transparency = seen(pop)
			shell.Size = Vector3.one * Cfg.Shell * (1 + 0.8 * pop)
			shell.Transparency = seen(Cfg.ShellTransparency + (1 - Cfg.ShellTransparency) * pop)
			if light then
				light.Brightness = Cfg.Light.brightness * (1 - a / 2)
			end
			return true
		end
		local a = math.min((now - now0) / t, 1)
		local swell = a * a
		orb.Size = Vector3.one * math.max(Cfg.Orb * swell, 0.05)
		shell.Size = Vector3.one * math.max(Cfg.Shell * swell, 0.05)
		orb.Transparency = seen(0)
		shell.Transparency = seen(Cfg.ShellTransparency)
		if light then
			light.Brightness = Cfg.Light.brightness * swell * (1 - veil)
		end
		return true
	end)

	local function release()
		if releasedAt then
			return
		end
		releasedAt = os.clock()
		e.Enabled = false
		task.delay(g.life, function()
			Pool.freeEmitter(e)
		end)
	end
	-- follows a moving caster
	local function move(to: Vector3)
		if releasedAt then
			return
		end
		local box = e.Parent :: Part
		orb.CFrame, shell.CFrame, box.CFrame = CFrame.new(to), CFrame.new(to), CFrame.new(to)
		if light then
			(light.Parent :: Attachment).Position = to
		end
	end
	return {
		release = release,
		move = move,
		veil = function(v: number)
			veil = v
			e.Transparency = NumberSequence.new(seen(0.4), seen(0))
			e.Brightness = 5 * (1 - v)
		end,
	}
end

-- Charges for `duration`, then releases.
function Charge.play(pos: Vector3, duration: number?, colorName: string?)
	local h = Charge.start(pos, duration, colorName)
	task.delay(duration or Cfg.Duration, h.release)
end

return Charge
