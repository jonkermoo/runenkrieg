--!strict
-- The magic circle (Config/Vfx.Circle): two outer rings with a band of runes between them, an inner ring with crossed
-- petals and six orbs, and a centre, all glowing lines on a flat disc. It grows in with a bright flash, spins (the
-- rune band one way, the petals the other, the centre fast). It closes by shrinking to a point while it disintegrates:
-- its pieces fade one by one from the rim inward and glowing flecks break off and drift away (Config/Vfx.Circle.Close).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Vfx).Circle
local Runes = require(Shared.Config.Runes)
local Util = require(script.Parent.Util)
local Pool = require(script.Parent.Pool)
local Driver = require(script.Parent.Driver)
local Flecks = require(script.Parent.Flecks)

local Circle = {}

local FAR = CFrame.new(0, -10000, 0)
local ROOM = 1.25 -- the disc is this much bigger than the circle so it can grow while fading
local RUNE_NAMES = {}
for name in Runes do
	table.insert(RUNE_NAMES, name)
end
table.sort(RUNE_NAMES)

export type Handle = { part: Part, close: () -> (), move: (cf: CFrame) -> (), ready: () -> () }

-- One drawn piece: it fades on its own when the circle disintegrates (`at`: its turn, 0..1 of the dissolve).
type Piece = { frame: Frame, stroke: UIStroke?, base: number, at: number }
type Track = (f: Frame, r: number) -> ()

local function layer(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

-- Draws the circle into `art` (a square frame `size` pixels wide); returns the spinning layers. `track` gets every
-- piece with its distance from the centre (0..0.5 of the diameter).
local function draw(
	art: Frame,
	size: number,
	color: Color3,
	accent: Color3,
	haze: Color3,
	track: Track
): { [string]: Frame }
	local line = Cfg.Line * Cfg.PixelsPerStud
	track(Util.dot(art, 0.5, 0.5, 0.98, haze, Cfg.Haze.transparency), 0.3)

	local outer = layer(art, "Outer")
	track(Util.ring(outer, 0.5, 0.5, 0.99, line * 1.4, color), 0.5)
	track(Util.ring(outer, 0.5, 0.5, 0.85, line, color), 0.43)
	local rng = Random.new(7)
	local rh = Cfg.RuneSize
	local rw = rh * 0.7
	for i = 1, Cfg.Runes do
		local a = (i - 1) / Cfg.Runes * 2 * math.pi
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5 + 0.46 * math.cos(a), 0.5 + 0.46 * math.sin(a))
		box.Size = UDim2.fromScale(rw, rh)
		box.Rotation = math.deg(a) + 90 -- the rune's top faces out
		box.BackgroundTransparency = 1
		box.Parent = outer
		for _, s in Runes[RUNE_NAMES[rng:NextInteger(1, #RUNE_NAMES)]] do
			track(Util.line(box, s[1], s[2], s[3], s[4], line * 0.7, color, rw * size, rh * size), 0.46)
		end
	end

	local inner = layer(art, "Inner")
	track(Util.ring(inner, 0.5, 0.5, 0.66, line, color), 0.33)
	track(Util.petal(inner, 0.26, 0.84, 45, line, color), 0.3)
	track(Util.petal(inner, 0.26, 0.84, -45, line, color), 0.3)
	track(Util.petal(inner, 0.12, 0.64, 0, line * 0.8, color), 0.22)
	track(Util.petal(inner, 0.12, 0.64, 90, line * 0.8, color), 0.22)
	for k = 0, 5 do
		local a = math.rad(30 + 60 * k)
		local x, y = 0.5 + 0.3 * math.cos(a), 0.5 + 0.3 * math.sin(a)
		track(Util.dot(inner, x, y, 0.13, haze, 0.3), 0.3)
		track(Util.ring(inner, x, y, 0.13, line, color), 0.3)
		track(Util.ring(inner, x, y, 0.08, line * 0.7, color), 0.3)
		track(Util.dot(inner, x, y, 0.035, accent), 0.3)
	end

	local center = layer(art, "Center")
	track(Util.ring(center, 0.5, 0.5, 0.17, line, color), 0.09)
	track(Util.ring(center, 0.5, 0.5, 0.11, line * 0.7, color), 0.06)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local c, s = math.cos(a), math.sin(a)
		track(
			Util.line(
				center,
				0.5 + 0.055 * c,
				0.5 + 0.055 * s,
				0.5 + 0.085 * c,
				0.5 + 0.085 * s,
				line * 0.6,
				color,
				size,
				size
			),
			0.07
		)
	end
	track(Util.dot(center, 0.5, 0.5, 0.045, accent), 0)
	return { Outer = outer, Inner = inner, Center = center }
end

type Built = {
	part: Part,
	guis: { SurfaceGui },
	groups: { CanvasGroup },
	scales: { UIScale },
	spins: { Spin },
	pieces: { Piece },
}
type Spin = { frame: Frame, speed: number }

-- Drawn circles kept for reuse, by size and color: drawing one is the costly part, so a closed circle is hidden
-- and handed to the next caster (Config/Vfx.Quality).
local cache: { [string]: { Built } } = {}

local function build(d: number, color: Color3): Built
	local accent, haze = Util.color(Cfg.Accent), Util.color(Cfg.Haze.color)
	local size = d * Cfg.PixelsPerStud
	local scales: { UIScale } = {}
	local spins: { Spin } = {}
	local pieces: { Piece } = {}
	local C = Cfg.Close
	local disc = Util.disc(CFrame.identity, d * ROOM, Cfg.PixelsPerStud, Cfg.Brightness, function(root)
		local art = layer(root, "Art")
		art.Size = UDim2.fromScale(1 / ROOM, 1 / ROOM)
		local order = Random.new(11) -- the same order on both faces
		local layers = draw(art, size, color, accent, haze, function(f, r)
			local stroke = f:FindFirstChildOfClass("UIStroke")
			-- the rim goes first: a piece's turn comes from its distance in from the rim, plus some randomness
			local at = C.sweep * (0.5 - r) / 0.5 + (1 - C.sweep) * order:NextNumber()
			table.insert(pieces, {
				frame = f,
				stroke = stroke,
				base = if stroke then stroke.Transparency else f.BackgroundTransparency,
				at = at * (1 - C.soft),
			})
		end)
		local sc = Instance.new("UIScale")
		sc.Parent = art
		table.insert(scales, sc)
		table.insert(spins, { frame = layers.Outer, speed = Cfg.OuterSpin })
		table.insert(spins, { frame = layers.Inner, speed = Cfg.InnerSpin })
		table.insert(spins, { frame = layers.Center, speed = Cfg.CenterSpin })
	end)
	disc.part.Parent = Util.folder()
	return {
		part = disc.part,
		guis = disc.guis,
		groups = disc.groups,
		scales = scales,
		spins = spins,
		pieces = pieces,
	}
end

-- Sets each piece's fade for dissolve progress `d` (0 = whole, 1 = all gone).
local function dissolve(pieces: { Piece }, d: number)
	local soft = Cfg.Close.soft
	for _, p in pieces do
		local f = math.clamp((d - p.at) / soft, 0, 1)
		local tr = p.base + (1 - p.base) * f
		local s = p.stroke
		if s then
			s.Transparency = tr
		else
			p.frame.BackgroundTransparency = tr
		end
	end
end

local rng = Random.new()

-- Flecks breaking off a closing circle (Vfx/Flecks): `n` at random points on a ring of `radius` round cf, in its
-- plane, flying outward with a little drift.
local function shed(n: number, cf: CFrame, radius: number, color: Color3, accent: Color3)
	local C = Cfg.Close
	for _ = 1, n do
		local ang = rng:NextNumber(0, 2 * math.pi)
		local radial = cf.RightVector * math.cos(ang) + cf.UpVector * math.sin(ang)
		Flecks.spawn(
			cf.Position + radial * radius,
			radial * rng:NextNumber(C.fleckSpeed[1], C.fleckSpeed[2])
				+ cf.LookVector * rng:NextNumber(-1.5, 1.5)
				+ Vector3.yAxis * rng:NextNumber(0, 1.5),
			if rng:NextNumber() < 0.3 then accent else color,
			rng:NextNumber(C.fleckSize[1], C.fleckSize[2]),
			rng:NextNumber(C.fleckLife[1], C.fleckLife[2])
		)
	end
end

-- Opens a circle at `cf` (its face looks along cf.LookVector) and keeps it spinning until the handle's close().
-- `appear`: how fast it opens (default Circle.Appear). `assemble`: it builds up slowly over `appear` instead
-- (Circle.Assemble: pieces lighting up from the centre out, flecks flying in). The handle's ready() makes it flare
-- and keep pulsing (Circle.Ready).
function Circle.open(cf: CFrame, diameter: number?, colorName: string?, appear: number?, assemble: boolean?): Handle
	local d = diameter or Cfg.Diameter
	local open = appear or Cfg.Appear
	local name = colorName or Cfg.Color
	local key = `{d}/{name}`
	local list = cache[key]
	local c = list and table.remove(list)
	if not c or not c.part.Parent then
		c = build(d, Util.color(name))
	end
	assert(c, "circle")
	local built: Built = c
	local part = built.part
	part.CFrame = cf
	dissolve(built.pieces, if assemble then 1 else 0) -- a reused circle starts whole (or empty, to assemble)
	local light = Pool.light(cf.Position, Util.color(name), Cfg.Light.range, 0)
	local fleckColor, fleckAccent = Util.color(name), Util.color(Cfg.Accent)
	local shedCount = 0
	local gathered = 0 -- flecks flown in while assembling
	local assembled = if assemble then 0 else 1 -- how much of it is built (a close crumbles only what's there)
	local readyAt: number? = nil

	local now0 = os.clock()
	local closedAt: number? = nil
	local function done()
		part.CFrame = FAR
		if light then
			Pool.freeLight(light)
		end
		local keep = cache[key] or {}
		cache[key] = keep
		if #keep < 4 then
			table.insert(keep, built)
		else
			part:Destroy()
		end
	end
	Driver.add(function(now: number, dt: number): boolean
		if not part.Parent then
			return false
		end
		local closed = closedAt
		local C = Cfg.Close
		local closing = if closed then math.min((now - closed) / C.time, 1) else 0
		local spin = (1 + (C.spin - 1) * closing * closing) * (if readyAt then Cfg.Ready.spin else 1)
		for _, s in built.spins do
			s.frame.Rotation += s.speed * spin * dt
		end
		local scale, transparency, bright, lit
		if closed then
			local a = closing
			if a >= 1 then
				done()
				return false
			end
			-- back-in easing: swells a touch, then collapses to nothing, accelerating
			local k = C.anticipation
			scale = 1 - ((k + 1) * a * a * a - k * a * a)
			transparency = math.clamp((a - C.fadeFrom) / (1 - C.fadeFrom), 0, 1)
			-- crumbling from the rim in: pieces fade by turn, flecks break off the crumbling edge
			local dis = math.max(math.min(a / C.dissolve, 1), 1 - assembled)
			dissolve(built.pieces, dis)
			local want = math.floor(C.flecks * dis)
			if want > shedCount then
				local edge = math.max(0.5 * (1 - dis), 0.05) * d * math.max(scale, 0.1)
				shed(want - shedCount, part.CFrame, edge, fleckColor, fleckAccent)
				shedCount = want
			end
			bright = Cfg.Brightness * (1 + (C.flash - 1) * a)
			lit = 1 - a
		elseif assemble then
			local a = math.min((now - now0) / open, 1)
			local A = Cfg.Assemble
			assembled = a
			scale = A.from + (1 - A.from) * (1 - (1 - a) ^ 2)
			transparency = 0
			dissolve(built.pieces, 1 - a) -- the reverse of crumbling: the centre first, the rim last
			bright = Cfg.Brightness * (0.6 + 0.4 * a)
			lit = a
			-- flecks fly in from round it to its edge
			local want = math.floor(A.flecks * a)
			if want > gathered then
				local cfNow = part.CFrame
				local r = 0.5 * d * scale
				for _ = gathered + 1, want do
					local ang = rng:NextNumber(0, 2 * math.pi)
					local radial = cfNow.RightVector * math.cos(ang) + cfNow.UpVector * math.sin(ang)
					local start = cfNow.Position + radial * r * A.fleckFrom
					Flecks.spawn(
						start,
						-radial * r * (A.fleckFrom - 1) / A.fleckLife,
						if rng:NextNumber() < 0.3 then fleckAccent else fleckColor,
						rng:NextNumber(A.fleckSize[1], A.fleckSize[2]),
						A.fleckLife
					)
				end
				gathered = want
			end
		else
			local a = math.min((now - now0) / open, 1)
			-- grows with a little overshoot (back-out easing), the lines flashing bright at the end then settling
			local k = 1.7
			local x = a - 1
			scale = 1 + (k + 1) * x * x * x + k * x * x
			transparency = 1 - math.min(a / 0.6, 1)
			local settle = math.clamp((now - now0 - open) / 0.3, 0, 1)
			bright = Cfg.Brightness * (1 + (Cfg.Flash - 1) * a * (1 - settle))
			lit = a
		end
		local ready = readyAt
		if ready and not closed then
			-- ready: a flare and a bump that settle, then a steady pulse
			local R = Cfg.Ready
			local p = now - ready
			local pop = math.max(1 - p / R.flashTime, 0)
			bright *= (1 + (R.flash - 1) * pop) * (1 + R.pulse * math.sin(p * R.rate * 2 * math.pi))
			scale *= 1 + R.bump * pop
			lit *= 1 + pop
		end
		for _, sc in built.scales do
			sc.Scale = scale
		end
		for _, g in built.groups do
			g.GroupTransparency = transparency
		end
		for _, gui in built.guis do
			gui.Brightness = bright
		end
		if light then
			light.Brightness = Cfg.Light.brightness * lit
		end
		return true
	end)

	local function close()
		if not closedAt then
			closedAt = os.clock()
		end
	end
	-- follows the caster's aim while open
	local function move(to: CFrame)
		if closedAt then
			return
		end
		part.CFrame = to
		if light then
			(light.Parent :: Attachment).Position = to.Position
		end
	end
	local function ready()
		if not readyAt and not closedAt then
			readyAt = os.clock()
		end
	end
	return { part = part, close = close, move = move, ready = ready }
end

-- Opens a circle, holds it `hold` seconds, closes it.
function Circle.play(cf: CFrame, hold: number?, diameter: number?, colorName: string?)
	local h = Circle.open(cf, diameter, colorName)
	task.delay(Cfg.Appear + (hold or 1.2), h.close)
end

return Circle
