--!strict
-- Comet streaks (Config/Vfx.Burst.Streaks; the white arcs flung off in the references): short bowed white strokes
-- thrown out from a point off a surface, thin tail to bright head, slowing and fading. Pooled beams, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Burst.Streaks
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Streaks = {}

local rng = Random.new()

type Streak = { tail: Attachment, head: Attachment, beam: Beam, dir: Vector3, bow: Vector3, reach: number }

-- `normal`: the surface they fly off (they spray over its side); `scale`: speeds, length and count x this.
function Streaks.play(pos: Vector3, normal: Vector3, scale: number?)
	local k = scale or 1
	local color = Util.color(Cfg.color)
	local list: { Streak } = {}
	for _ = 1, math.max(math.round(Cfg.count * k), 1) do
		local dir = (normal.Unit + rng:NextUnitVector() * 0.9).Unit
		local bow = dir:Cross(rng:NextUnitVector()).Unit -- the side it curves toward
		local tail, head = Pool.att(pos), Pool.att(pos)
		local b = Pool.beam(tail, head, color, 0, Cfg.width * k, 0, 3)
		b.Segments = 8
		table.insert(list, {
			tail = tail,
			head = head,
			beam = b,
			dir = dir,
			bow = bow,
			reach = rng:NextNumber(Cfg.speed[1], Cfg.speed[2]) * k * Cfg.life * 0.5,
		})
	end
	local now0 = os.clock()
	Driver.add(function(now: number): boolean
		local a = (now - now0) / Cfg.life
		if a >= 1 then
			for _, s in list do
				Pool.freeBeam(s.beam)
				Pool.freeAtt(s.tail)
				Pool.freeAtt(s.head)
			end
			return false
		end
		local function at(x: number): number -- distance flown by fraction x of the life (slowing down)
			local c = math.clamp(x, 0, 1)
			return 1 - (1 - c) ^ 2
		end
		for _, s in list do
			local hp = pos + s.dir * s.reach * at(a)
			local tp = pos + s.dir * math.max(s.reach * at(a) - Cfg.length * k, 0)
			-- the attachments' Axis (X) points to the bow side: both control points pull the stroke that way
			s.head.CFrame = CFrame.fromMatrix(hp, s.bow, s.dir)
			s.tail.CFrame = CFrame.fromMatrix(tp, s.bow, s.dir)
			local bend = Cfg.bend * k * (hp - tp).Magnitude / (Cfg.length * k)
			s.beam.CurveSize0, s.beam.CurveSize1 = bend, -bend
			s.beam.Transparency = NumberSequence.new(a * a)
		end
		return true
	end)
end

return Streaks
