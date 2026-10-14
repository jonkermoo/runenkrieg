--!strict
-- A shockwave ring (Config/Vfx.Shockwave): races outward round `center` in the plane facing `normal` (Vector3.yAxis
-- lays it flat on the ground), the line thinning as it fades. A pooled Ring (four curved beams).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Shockwave
local Util = require(script.Parent.Util)
local Driver = require(script.Parent.Driver)
local Ring = require(script.Parent.Ring)

local Shockwave = {}

function Shockwave.play(center: Vector3, normal: Vector3, colorName: string?, to: number?)
	local reach = to or Cfg.to
	local ring = Ring.new(Util.color(colorName or Cfg.color), Cfg.line, Cfg.brightness)
	local now0 = os.clock()
	Driver.add(function(now: number): boolean
		local a = (now - now0) / Cfg.time
		if a >= 1 then
			Ring.free(ring)
			return false
		end
		local grow = 1 - (1 - a) ^ 4
		Ring.place(ring, center, normal, Cfg.from + (reach - Cfg.from) * grow, 1 - a, a * a)
		return true
	end)
end

return Shockwave
