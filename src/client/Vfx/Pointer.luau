--!strict
-- The aiming laser (Config/Vfx.Pointer; user 2026-10-13: "a small flashing staticky laser to where you are pointing
-- (warning for enemies and a way to aim in first person)", and the reference frames: a straight line broken into
-- glowing white dashes of every length with dark gaps, the pattern changing every moment and the whole line blinking
-- out now and then). Redrawn `rate` times a second: a new random run of dashes along the line from the cast to where
-- it points, each a white core in a soft glow, as thick on screen near or far. One per caster: set(from, to) shows it,
-- hide() / free().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Pointer
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Pointer = {}

export type Handle = { set: (from: Vector3, to: Vector3) -> (), hide: () -> (), free: () -> () }

type Dash = { a0: Attachment, a1: Attachment, glow: Beam, core: Beam }

local rng = Random.new()

local function range(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

-- `colorName` / `coreName`: a scheme's pointer and core colors (default Pointer.color / core).
function Pointer.new(colorName: string?, coreName: string?): Handle
	local glowColor, coreColor = Util.color(colorName or Cfg.color), Util.color(coreName or Cfg.core)
	local dashes: { Dash } = {}
	for i = 1, Cfg.dashes do
		local a0, a1 = Pool.att(Vector3.zero), Pool.att(Vector3.zero)
		local glow = Pool.beam(a0, a1, glowColor, Cfg.glow, Cfg.glow, Cfg.glowTransparency, Cfg.brightness, 0.3)
		local core = Pool.beam(a0, a1, coreColor, Cfg.width, Cfg.width, 0, Cfg.brightness, 1)
		glow.ZOffset, core.ZOffset = 1, 1.1
		glow.Enabled, core.Enabled = false, false
		dashes[i] = { a0 = a0, a1 = a1, glow = glow, core = core }
	end
	local function off()
		for _, d in dashes do
			d.glow.Enabled, d.core.Enabled = false, false
		end
	end

	local from: Vector3?, to: Vector3? = nil, nil
	local alive = true
	local nextDraw = 0
	Driver.add(function(now: number): boolean
		if not alive then
			for _, d in dashes do
				Pool.freeBeam(d.glow)
				Pool.freeBeam(d.core)
				Pool.freeAtt(d.a0)
				Pool.freeAtt(d.a1)
			end
			return false
		end
		local a, b = from, to
		if not a or not b then
			off()
			return true
		end
		if now < nextDraw then
			return true
		end
		nextDraw = now + 1 / Cfg.rate
		off()
		if rng:NextNumber() > Cfg.on then
			return true -- blinked out
		end
		-- a fresh run of dashes and gaps along the line (shares of its length)
		local cam = workspace.CurrentCamera.CFrame.Position
		local d = b - a
		local f = range(Cfg.gap)
		for _, dash in dashes do
			if f >= 1 then
				break
			end
			local f1 = math.min(f + range(Cfg.dash), 1)
			local p0, p1 = a + d * f, a + d * f1
			dash.a0.Position, dash.a1.Position = p0, p1
			-- as thick on screen near or far: width in proportion to the distance from the camera
			local k0 = (p0 - cam).Magnitude * Cfg.perStud
			local k1 = (p1 - cam).Magnitude * Cfg.perStud
			local flick = range(Cfg.flicker)
			dash.core.Width0, dash.core.Width1 = Cfg.width * k0 * flick, Cfg.width * k1 * flick
			dash.glow.Width0, dash.glow.Width1 = Cfg.glow * k0 * flick, Cfg.glow * k1 * flick
			dash.glow.Enabled, dash.core.Enabled = true, true
			f = f1 + range(Cfg.gap)
		end
		return true
	end)
	return {
		set = function(x: Vector3, y: Vector3)
			from, to = x, y
		end,
		hide = function()
			from, to = nil, nil
		end,
		free = function()
			alive = false
		end,
	}
end

return Pointer
