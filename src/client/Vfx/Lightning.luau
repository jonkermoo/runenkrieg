--!strict
-- Lightning (Config/Vfx.Lightning): a jagged bolt between two points, its zigzag redrawn every `refresh` seconds,
-- with side branches, a white core inside the colored glow and a flickering light. Pooled arcs, one Driver step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Lightning
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Arc = require(script.Parent.Arc)

local Lightning = {}

local rng = Random.new()

function Lightning.bolt(from: Vector3, to: Vector3, duration: number?, colorName: string?)
	local t = duration or Cfg.duration
	local color, core = Util.color(colorName or Cfg.color), Util.color(Cfg.core)
	local main = Arc.new(Cfg.segments, color, core, Cfg.width, Cfg.brightness)
	local side: { Arc.Arc } = {}
	for _ = 1, Cfg.branches do
		table.insert(side, Arc.new(math.max(Cfg.segments // 3, 2), color, core, Cfg.width * 0.6, Cfg.brightness))
	end
	local light = Pool.light((from + to) / 2, color, 16, 0)
	local now0, nextDraw = os.clock(), 0
	Driver.add(function(now: number): boolean
		if now - now0 >= t then
			Arc.free(main)
			for _, b in side do
				Arc.free(b)
			end
			if light then
				Pool.freeLight(light)
			end
			return false
		end
		if now < nextDraw then
			return true
		end
		nextDraw = now + Cfg.refresh
		Arc.zig(main, from, to, Cfg.jag)
		local on = rng:NextNumber() > 0.15 -- a flicker now and then
		Arc.show(main, on)
		for _, b in side do
			local start = main.atts[rng:NextInteger(2, main.n)].Position
			local dir = ((to - from).Unit + rng:NextUnitVector() * 0.9).Unit
			Arc.zig(b, start, start + dir * (to - from).Magnitude * Cfg.branchLength, Cfg.jag * 0.6)
			Arc.show(b, on)
		end
		if light then
			light.Brightness = rng:NextNumber(2, 8)
		end
		return true
	end)
end

return Lightning
