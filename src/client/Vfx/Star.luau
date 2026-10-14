--!strict
-- A star glint (Config/Vfx.Star): four long thin spikes and four short ones from a point, always square to the
-- camera, popping out and back with a twist, over a white flash. Pooled pieces, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Star
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Star = {}

function Star.play(pos: Vector3, colorName: string?, length: number?)
	local color = Util.color(colorName or Cfg.color)
	local len = length or Cfg.length
	local a0 = Pool.att(pos)
	local tips: { { a: Attachment, b: Beam, angle: number, len: number } } = {}
	for k = 0, 7 do
		local long = k % 2 == 0
		local a = Pool.att(pos)
		local w = if long then Cfg.width else Cfg.width * 0.6
		table.insert(tips, {
			a = a,
			b = Pool.beam(a0, a, color, w, 0, 0, Cfg.brightness),
			angle = k * math.pi / 4,
			len = if long then len else len * 0.4,
		})
	end
	local flash = Pool.part(Enum.PartType.Ball, Util.color("Core"), Vector3.one * Cfg.flash, CFrame.new(pos))
	local now0 = os.clock()
	Driver.add(function(now: number): boolean
		local a = (now - now0) / Cfg.time
		if a >= 1 then
			for _, tip in tips do
				Pool.freeBeam(tip.b)
				Pool.freeAtt(tip.a)
			end
			Pool.freeAtt(a0)
			Pool.freePart(flash)
			return false
		end
		local cam = workspace.CurrentCamera.CFrame
		local pop = math.sin(a * math.pi) ^ 0.6
		local twist = math.rad(Cfg.twist) * a
		for _, tip in tips do
			local ang = tip.angle + twist
			local d = cam.RightVector * math.cos(ang) + cam.UpVector * math.sin(ang)
			tip.a.Position = pos + d * tip.len * pop
		end
		flash.Size = Vector3.one * Cfg.flash * (1 + 1.5 * a)
		flash.Transparency = a
		return true
	end)
end

return Star
