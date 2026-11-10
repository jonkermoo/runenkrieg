--!strict
-- A big gun's firing shockwave (Config/Vfx.FiringWave; user 2026-11-09: "add a shockkwave around teh artillery when its
-- fired? (like air and terrain dust in a circle around where the explosion to set off the artillery is)"): flat on the
-- ground round `center`, the air blown out in pale bands, a ring of dust puffs in the ground's own colour rolling out
-- and thinning, and chips of the ground flung out. All pooled flat-coloured parts and beams, moved by the one Driver.
--   FiringWave.play(center, scale?, { color?, tint? }): `color` the ground's (else plain mud); `tint` the air's colour
--   (a magic gun's glow), nil plain air

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Vfx).FiringWave
local Palette = require(Shared.Config.Palette)
local Driver = require(script.Parent.Driver)
local Pool = require(script.Parent.Pool)
local Ring = require(script.Parent.Ring)

local FiringWave = {}

local rng = Random.new()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function between(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- the pale bands of air racing out flat
local function air(center: Vector3, k: number, tint: Color3?)
	local A = Cfg.Air
	local color = rgb(A.color)
	if tint then
		color = color:Lerp(tint, A.tint)
	end
	for i = 1, A.rings do
		task.delay((i - 1) * A.gap, function()
			local ring = Ring.new(color, A.line * k, A.brightness, A.transparency[1])
			local t0 = os.clock()
			local at = center + Vector3.new(0, A.lift * k, 0)
			-- (each later band a little wider and fainter)
			local reach = A.to * k * (1 + (i - 1) * A.wider)
			Driver.add(function(now: number): boolean
				local a = (now - t0) / A.time
				if a >= 1 then
					Ring.free(ring)
					return false
				end
				local grow = 1 - (1 - a) ^ 3
				Ring.place(
					ring,
					at,
					Vector3.yAxis,
					lerp(A.from * k, reach, grow),
					1 - a * A.thin,
					lerp(A.transparency[1], A.transparency[2], a)
				)
				return true
			end, function()
				Ring.free(ring)
			end)
		end)
	end
end

type Puff = { part: Part, dir: Vector3, reach: number, time: number, size: number, turn: number }

-- the dust puffs rolling out round it
local function dust(center: Vector3, k: number, ground: Color3)
	local D = Cfg.Dust
	local color = ground:Lerp(Color3.new(1, 1, 1), D.light)
	local puffs: { Puff } = {}
	local offset = rng:NextNumber(0, math.pi * 2)
	for i = 1, D.count do
		local ang = offset + (i - 1) / D.count * math.pi * 2 + rng:NextNumber(-D.wander, D.wander)
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local size = between(D.size) * k
		local part = Pool.part(
			Enum.PartType.Ball,
			color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, D.shade)),
			Vector3.one * size,
			CFrame.new(center + dir * D.from * k),
			D.transparency[1],
			Enum.Material.SmoothPlastic
		)
		table.insert(puffs, {
			part = part,
			dir = dir,
			reach = D.to * k * (1 + rng:NextNumber(-D.jitter, D.jitter)),
			time = between(D.time),
			size = size,
			turn = rng:NextNumber(-D.spin, D.spin),
		})
	end
	local t0 = os.clock()
	local function free()
		for _, p in puffs do
			Pool.freePart(p.part)
		end
		table.clear(puffs)
	end
	Driver.add(function(now: number): boolean
		local live = false
		for _, p in puffs do
			local a = (now - t0) / p.time
			if a >= 1 then
				p.part.Transparency = 1
				continue
			end
			live = true
			local out = 1 - (1 - a) ^ 3
			local r = lerp(D.from * k, p.reach, out)
			local s = p.size * lerp(1, D.grow, out)
			p.part.Size = Vector3.new(s, s * D.squat, s) -- (squat: rolling along the ground)
			p.part.CFrame = CFrame.new(center + p.dir * r + Vector3.new(0, s * D.squat * 0.5 + D.rise * k * out, 0))
				* CFrame.Angles(0, math.rad(p.turn * a), 0)
			p.part.Transparency = lerp(D.transparency[1], D.transparency[2], a * a)
		end
		if not live then
			free()
		end
		return live
	end, free)
end

type Clod = { part: Part, at: Vector3, v: Vector3, life: number, spin: Vector3 }

-- chips of the ground flung out and falling
local function clods(center: Vector3, k: number, ground: Color3)
	local C = Cfg.Clods
	local list: { Clod } = {}
	for _ = 1, C.count do
		local ang = rng:NextNumber(0, math.pi * 2)
		local s = between(C.size) * math.sqrt(k)
		local at = center + Vector3.new(math.cos(ang), 0, math.sin(ang)) * k + Vector3.new(0, C.lift, 0)
		table.insert(list, {
			part = Pool.part(
				Enum.PartType.Block,
				ground:Lerp(Color3.new(0, 0, 0), rng:NextNumber(C.shade[1], C.shade[2])),
				Vector3.one * s,
				CFrame.new(at),
				0,
				Enum.Material.SmoothPlastic
			),
			at = at,
			v = Vector3.new(math.cos(ang), 0, math.sin(ang)) * between(C.speed) * math.sqrt(k)
				+ Vector3.new(0, between(C.up), 0),
			life = between(C.life),
			spin = Vector3.new(
				rng:NextNumber(-C.spin, C.spin),
				rng:NextNumber(-C.spin, C.spin),
				rng:NextNumber(-C.spin, C.spin)
			),
		})
	end
	local t0 = os.clock()
	local function free()
		for _, c in list do
			Pool.freePart(c.part)
		end
		table.clear(list)
	end
	Driver.add(function(now: number): boolean
		local t = now - t0
		local live = false
		for _, c in list do
			if t >= c.life then
				c.part.Transparency = 1
				continue
			end
			live = true
			local pos = c.at + c.v * t + Vector3.new(0, -0.5 * C.gravity * t * t, 0)
			c.part.CFrame = CFrame.new(pos) * CFrame.Angles(c.spin.X * t, c.spin.Y * t, c.spin.Z * t)
			c.part.Transparency = math.clamp((t / c.life - C.fade) / (1 - C.fade), 0, 1)
		end
		if not live then
			free()
		end
		return live
	end, free)
end

function FiringWave.play(center: Vector3, scale: number?, opts: { color: Color3?, tint: Color3? }?)
	local k = scale or 1
	local o = opts or {}
	local ground = o.color or rgb((Palette.Terrain :: any).Mud)
	air(center, k, o.tint)
	dust(center, k, ground)
	clods(center, k, ground)
end

return FiringWave
