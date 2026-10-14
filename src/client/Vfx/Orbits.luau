--!strict
-- Curves orbiting a magic circle (Config/Vfx.Orbits; user 2026-10-13: "additional curves that orbit the circles in
-- various locations and speeds ... flashing and staticky too like the laser"): each orbit is an arc of glowing dashes
-- on a ring a little wider than the circle, its plane tilted, set off along the circle's axis, sweeping round at its
-- own speed and direction. Redrawn `rate` times a second like the aiming laser (Vfx/Pointer): dashes flicker on and off,
-- their widths jump, a whole orbit blinks out now and then. move(cf) keeps them on the circle (cf: the circle's frame,
-- looking along its axis); veil(v) see-through; stop(linger) lets them run `linger` more seconds, then thin out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Orbits
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)

local Orbits = {}

export type Handle = { move: (cf: CFrame) -> (), veil: (v: number) -> (), stop: (linger: number?) -> () }

type Orbit = {
	atts: { Attachment },
	cores: { Beam },
	glows: { Beam },
	radius: number,
	tilt: CFrame, -- the orbit's plane relative to the circle's
	offset: number, -- along the circle's axis
	span: number, -- radians of arc
	speed: number, -- radians a second (signed)
	phase: number,
}

local rng = Random.new()
local function range(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

-- `count` orbits round a circle `diameter` studs across.
function Orbits.new(count: number, diameter: number, colorName: string?): Handle
	local glowColor, coreColor = Util.color(colorName or Cfg.color), Util.color(Cfg.core)
	local size = diameter / Cfg.reference -- widths and offsets scale with the circle
	local n = Cfg.segments
	local orbits: { Orbit } = {}
	for _ = 1, count do
		local atts, cores, glows = {}, {}, {}
		for i = 1, n + 1 do
			atts[i] = Pool.att(Vector3.zero)
		end
		for i = 1, n do
			local g = Pool.beam(atts[i], atts[i + 1], glowColor, 0, 0, Cfg.glowTransparency, Cfg.brightness, 0.3)
			local c = Pool.beam(atts[i], atts[i + 1], coreColor, 0, 0, 0, Cfg.brightness, 1)
			g.ZOffset, c.ZOffset = 1, 1.1
			g.Enabled, c.Enabled = false, false
			glows[i], cores[i] = g, c
		end
		local axisAngle = rng:NextNumber(0, 2 * math.pi)
		table.insert(orbits, {
			atts = atts,
			cores = cores,
			glows = glows,
			radius = diameter * 0.5 * range(Cfg.radius),
			-- tilted about an axis in the circle's plane
			tilt = CFrame.fromAxisAngle(
				Vector3.new(math.cos(axisAngle), math.sin(axisAngle), 0),
				math.rad(range(Cfg.tilt))
			),
			offset = range(Cfg.offset) * size,
			span = range(Cfg.span),
			speed = range(Cfg.speed) * (if rng:NextNumber() < 0.5 then -1 else 1),
			phase = rng:NextNumber(0, 2 * math.pi),
		})
	end

	local frame: CFrame? = nil
	local veil = 0
	local stopAt: number? = nil -- when it starts thinning out
	local nextDraw = 0
	local last = os.clock()
	Driver.add(function(now: number): boolean
		local dt = now - last
		last = now
		for _, o in orbits do
			o.phase += o.speed * dt
		end
		-- thinning out after stop: the widths shrink to nothing over Cfg.fade
		local fade = 1
		local s = stopAt
		if s and now >= s then
			fade = 1 - (now - s) / Cfg.fade
			if fade <= 0 then
				for _, o in orbits do
					for i = 1, n do
						Pool.freeBeam(o.cores[i])
						Pool.freeBeam(o.glows[i])
					end
					for _, a in o.atts do
						Pool.freeAtt(a)
					end
				end
				return false
			end
		end
		local cf = frame
		if not cf or now < nextDraw then
			return true
		end
		nextDraw = now + 1 / Cfg.rate
		local t = NumberSequence.new(veil)
		local tg = NumberSequence.new(1 - (1 - Cfg.glowTransparency) * (1 - veil))
		for _, o in orbits do
			local shown = rng:NextNumber() < Cfg.on
			local plane = cf * o.tilt * CFrame.new(0, 0, -o.offset)
			for i = 1, n + 1 do
				local a = o.phase + o.span * (i - 1) / n
				o.atts[i].WorldPosition = plane * Vector3.new(math.cos(a) * o.radius, math.sin(a) * o.radius, 0)
			end
			for i = 1, n do
				local on = shown and rng:NextNumber() < Cfg.dashOn
				local w = range(Cfg.flicker) * size * fade
				o.cores[i].Enabled, o.glows[i].Enabled = on, on
				o.cores[i].Width0, o.cores[i].Width1 = Cfg.width * w, Cfg.width * w
				o.glows[i].Width0, o.glows[i].Width1 = Cfg.glow * w, Cfg.glow * w
				o.cores[i].Transparency, o.glows[i].Transparency = t, tg
			end
		end
		return true
	end)

	return {
		move = function(cf: CFrame)
			frame = cf
		end,
		veil = function(v: number)
			veil = v
		end,
		stop = function(linger: number?)
			if not stopAt then
				stopAt = os.clock() + (linger or 0)
			end
		end,
	}
end

return Orbits
