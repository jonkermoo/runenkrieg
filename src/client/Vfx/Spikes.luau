--!strict
-- Light spikes (Config/Vfx.Spikes): rays shooting out from a point in every direction, then thinning away. Pooled
-- pieces, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Spikes
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Spikes = {}

local rng = Random.new()

function Spikes.play(pos: Vector3, colorName: string?)
	local color = Util.color(colorName or Cfg.color)
	local a0 = Pool.att(pos)
	local rays: { { a: Attachment, b: Beam, to: Vector3 } } = {}
	for _ = 1, Cfg.count do
		local a = Pool.att(pos)
		table.insert(rays, {
			a = a,
			b = Pool.beam(a0, a, color, Cfg.width, 0, 0, Cfg.brightness),
			to = pos + rng:NextUnitVector() * rng:NextNumber(Cfg.length[1], Cfg.length[2]),
		})
	end
	local core = Pool.part(Enum.PartType.Ball, Util.color("Core"), Vector3.one * 1.2, CFrame.new(pos))
	local now0 = os.clock()
	Driver.add(function(now: number): boolean
		local a = (now - now0) / Cfg.time
		if a >= 1 then
			for _, r in rays do
				Pool.freeBeam(r.b)
				Pool.freeAtt(r.a)
			end
			Pool.freeAtt(a0)
			Pool.freePart(core)
			return false
		end
		local out = 1 - (1 - math.min(a / 0.35, 1)) ^ 3 -- shoot out in the first third
		local thin = 1 - math.max(a - 0.35, 0) / 0.65
		for _, r in rays do
			r.a.Position = pos + (r.to - pos) * out
			r.b.Width0 = Cfg.width * thin
		end
		core.Size = Vector3.one * (1.2 + 1.8 * a)
		core.Transparency = a
		return true
	end)
end

return Spikes
