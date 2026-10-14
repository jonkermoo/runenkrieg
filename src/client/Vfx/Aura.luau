--!strict
-- A lightning aura (Config/Vfx.Aura, the Deku look): short crackling arcs hopping round a body for `duration`.
-- `around` is a part to follow or a fixed point. A fixed set of pooled arcs, re-laid every hop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vfx = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx)
local Cfg = Vfx.Aura
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Arc = require(script.Parent.Arc)

local Aura = {}

local rng = Random.new()

function Aura.play(around: BasePart | Vector3, duration: number, colorName: string?)
	local color = Util.color(colorName or Cfg.color)
	local core = Util.color(Vfx.Lightning.core)
	local function center(): Vector3
		return if typeof(around) == "Vector3" then around else (around :: BasePart).Position
	end
	local arcs: { Arc.Arc } = {}
	for _ = 1, Cfg.arcs do
		table.insert(arcs, Arc.new(4, color, core, 0.12, Vfx.Lightning.brightness))
	end
	local light = Pool.light(center(), color, Cfg.radius * 4, Cfg.light)
	local now0, nextHop = os.clock(), 0
	Driver.add(function(now: number): boolean
		if now - now0 >= duration then
			for _, a in arcs do
				Arc.free(a)
			end
			if light then
				Pool.freeLight(light)
			end
			return false
		end
		if now < nextHop then
			return true
		end
		nextHop = now + Cfg.hop
		local c = center()
		for _, arc in arcs do
			local a = c + rng:NextUnitVector() * Cfg.radius * rng:NextNumber(0.6, 1)
			local b = a + rng:NextUnitVector() * rng:NextNumber(Cfg.arcLength[1], Cfg.arcLength[2])
			Arc.zig(arc, a, b, 0.35)
			Arc.show(arc, rng:NextNumber() > 0.2)
		end
		if light then
			(light.Parent :: Attachment).Position = c
			light.Brightness = rng:NextNumber(0.4, 1) * Cfg.light
		end
		return true
	end)
end

return Aura
