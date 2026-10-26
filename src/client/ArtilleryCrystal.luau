--!strict
-- The magic howitzer's crystal, alive (Config/Artillery.Crystal, Rules/Artillery.crystal; src/client/Artillery runs it
-- per gun on every client; docs/VFX.md "Artillery"). User 2026-10-20: "make the howitzer loading just a empty colored
-- crystal and the color slowly returns (make it look nice, like its coming back to life)", "give the crystal more
-- design and effects. some runes on it works too":
-- - the crystal (and the barrel's and bed's rune bands with it) flares white-hot on the shot, drains near black, then
--   life creeps back: sputtering, a heartbeat quickening, the colour filling in; full, it blooms and then breathes;
-- - a light inside it, as bright as it glows;
-- - a ring of Elder Futhark runes (Config/Runes strokes, curved rounded brush strokes, facing the
--   camera) circling level round it, each waking in turn as it charges, flickering on; on the shot they scatter outward
--   and fade;
-- - motes of light drawn into it while it charges.
--   ArtilleryCrystal.new(model, crystal) -> state; .update(state, now, firedAt, readyAt, reload); .destroy(state)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery).Crystal
local RuneStrokes = require(Shared.Config.Runes)
local Rules = require(Shared.Rules.Artillery)

local ArtilleryCrystal = {}

local rng = Random.new()

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds" -- Roblox's own sparkle sprite
local NAMES = { "fehu", "uruz", "thurisaz", "ansuz", "kaunan", "algiz", "sowilo", "tiwaz", "eihwaz", "hagalaz" }

export type State = {
	crystal: BasePart,
	cracks: BasePart?,
	flickerUntil: number, -- a drop-out running until then
	flickerDepth: number,
	flareUntil: number, -- knocked out: a weak flare running until then
	seed: number,
	bands: { BasePart },
	light: PointLight,
	motes: ParticleEmitter,
	holder: Attachment,
	runes: { { gui: BillboardGui, strokes: { Frame } } },
	angle: number,
	last: number,
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- one rounded piece of a stroke from (x0, y0) to (x1, y1) (scale), `t` of the box's height thick, under `parent`
local function piece(parent: GuiObject, x0: number, y0: number, x1: number, y1: number, w: number, h: number, t: number)
	local dx, dy = (x1 - x0) * w, (y1 - y0) * h
	local len = math.sqrt(dx * dx + dy * dy)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromScale((len + t * h) / w, t)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = f
	f.Parent = parent
	return f
end

-- a rune's strokes in a box `w` x `h` studs (scale units, so they keep their shape at any distance): each bowed into a
-- curve of rounded pieces, swelling in the middle (Cfg.strokes)
local function drawRune(parent: GuiObject, name: string, w: number, h: number): { Frame }
	local strokes = {}
	local C = Cfg.strokes
	for k, s in RuneStrokes[name] do
		local du, dv = s[3] - s[1], s[4] - s[2]
		local length = math.sqrt(du * du + dv * dv)
		if length < 1e-4 then
			continue
		end
		local pu, pv = -dv / length, du / length
		local bow = C.bow * length * (if k % 2 == 1 then 1 else -1)
		local function at(t: number): (number, number)
			local b = bow * 4 * t * (1 - t)
			return s[1] + du * t + pu * b, s[2] + dv * t + pv * b
		end
		for i = 1, C.pieces do
			local t0, t1 = (i - 1) / C.pieces, i / C.pieces
			local x0, y0 = at(t0)
			local x1, y1 = at(t1)
			local thick = Cfg.stroke * (C.tip + (C.swell - C.tip) * math.sin(math.pi * (t0 + t1) / 2))
			table.insert(strokes, piece(parent, x0, y0, x1, y1, w, h, thick))
		end
	end
	return strokes
end

function ArtilleryCrystal.new(model: Model, crystal: BasePart): State
	local holder = Instance.new("Attachment")
	holder.Name = "CrystalFx"
	holder.Parent = crystal
	local light = Instance.new("PointLight")
	light.Shadows = false
	light.Parent = holder
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SPARKLE
	motes.Shape = Enum.ParticleEmitterShape.Sphere
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	motes.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	motes.Lifetime = NumberRange.new(0.8, 1.2)
	motes.Speed = NumberRange.new(Cfg.moteFrom / 1.1, Cfg.moteFrom / 0.9)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Cfg.moteSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Rate = 0
	-- (the sphere the motes start on: `moteFrom` studs out)
	local box = Instance.new("Part")
	box.Name = "CrystalMotes"
	box.Anchored, box.CanCollide, box.CanQuery, box.CanTouch = true, false, false, false
	box.Transparency = 1
	box.Size = Vector3.one * Cfg.moteFrom * 2
	box.Parent = model
	motes.Parent = box

	local runes = {}
	local h = Cfg.size
	local w = h * 0.7
	for i = 1, Cfg.runes do
		local gui = Instance.new("BillboardGui")
		gui.Name = "CrystalRune"
		gui.Size = UDim2.fromScale(w, h)
		gui.LightInfluence = 0
		gui.MaxDistance = 600
		gui.Adornee = holder
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = gui
		local strokes = drawRune(frame, NAMES[(i - 1) % #NAMES + 1], w, h)
		gui.Parent = holder
		table.insert(runes, { gui = gui, strokes = strokes })
	end

	local bands = {}
	for _, name in Cfg.alsoRunes do
		local b = model:FindFirstChild(name, true)
		if b and b:IsA("BasePart") then
			table.insert(bands, b)
		end
	end
	local cracks = model:FindFirstChild("CrystalCracks", true)
	return {
		crystal = crystal,
		cracks = if cracks and cracks:IsA("BasePart") then cracks else nil,
		flickerUntil = 0,
		flickerDepth = 0,
		flareUntil = 0,
		seed = math.random() * 100,
		bands = bands,
		light = light,
		motes = motes,
		holder = holder,
		runes = runes,
		angle = 0,
		last = os.clock(),
	}
end

-- the colour for a glow: empty -> ready, past 1 toward white-hot
local function colorAt(glow: number): Color3
	if glow <= 1 then
		return rgb(Cfg.empty):Lerp(rgb(Cfg.ready), math.clamp(glow, 0, 1))
	end
	return rgb(Cfg.ready):Lerp(rgb(Cfg.fired), math.clamp(glow - 1, 0, 1))
end

function ArtilleryCrystal.update(
	s: State,
	now: number,
	firedAt: number,
	readyAt: number,
	reload: number,
	braceAt: number,
	charge: number,
	hurt: number?, -- the share of its HP gone (Config/Artillery.Crystal.dying)
	broken: boolean? -- knocked out: no charge, a dying sputter
)
	local clock = os.clock()
	local dt = math.min(clock - s.last, 0.1)
	s.last = clock
	local state, glow, share = Rules.crystal(now, firedAt, readyAt, reload, Cfg)
	local Dy = Cfg.dying
	local dying = math.clamp(((hurt or 0) - Dy.from) / (1 - Dy.from), 0, 1)
	if broken then
		state, glow, share = "Ready", Dy.glow, 1
		braceAt = -math.huge
	end
	-- charging up for the shot (user 2026-10-21: "a cinematic magic charge up"): over-bright, the runes whirling in
	local up = now - braceAt
	local surge = if state ~= "Fired" and up >= 0 and up < charge then up / charge else 0
	glow += Cfg.surge.glow * surge
	-- the random flicker: drop-outs now and then (often as it starts to wake, rarely once ready) and a slow wobble
	local F = Cfg.flicker
	if state == "Charging" or state == "Ready" then
		local rate = if state == "Charging" then F.rate[1] + (F.rate[2] - F.rate[1]) * share else F.rate[3]
		rate += Dy.rate * dying
		if clock >= s.flickerUntil and rng:NextNumber() < rate * dt then
			s.flickerUntil = clock + rng:NextNumber(F.length[1], F.length[2])
			local deep = F.depth[2] + (Dy.depth[1] - F.depth[2]) * dying
			s.flickerDepth = rng:NextNumber(math.min(F.depth[1] + (Dy.depth[2] - F.depth[1]) * dying, deep), deep)
		end
		if clock < s.flickerUntil then
			glow *= 1 - s.flickerDepth
		end
		glow *= 1 - F.wobble * (0.5 + 0.5 * math.noise(clock * 2.3, s.seed))
	end
	if broken then
		-- knocked out: mostly black, a weak flare now and then
		if clock >= s.flareUntil and rng:NextNumber() < dt / Dy.flareEvery then
			s.flareUntil = clock + Dy.flareLength
		end
		if clock < s.flareUntil then
			glow = Dy.flare
		elseif math.noise(clock * 3.1, s.seed) * 0.5 + 0.5 < Dy.blackout then
			glow = 0
		end
	end
	local color = colorAt(glow)
	if dying > 0 then
		color = color:Lerp(rgb(Dy.tint), dying * 0.5)
	end
	s.crystal.Color = color
	if s.cracks then
		s.cracks.Color = colorAt(math.max(glow + Cfg.cracks, 0))
	end
	-- the rune bands follow it, never quite dark
	local bandColor = colorAt(math.max(math.min(glow, 1), Cfg.runesFloor))
	for _, b in s.bands do
		b.Color = bandColor
	end
	local lit = math.clamp(glow, 0, 1.5)
	s.light.Color = color
	s.light.Range = Cfg.light.range * math.max(lit, 0.05)
	s.light.Brightness = Cfg.light.brightness * lit

	-- motes drawn in while charging (more as it fills), a few while ready
	local box = s.motes.Parent :: BasePart
	box.CFrame = CFrame.new(s.crystal.Position)
	s.motes.Color = ColorSequence.new(rgb(Cfg.ready))
	s.motes.Rate = if state == "Charging" then Cfg.motes * (0.2 + 0.8 * share) elseif state == "Ready" then 2 else 0

	-- the runes circling it
	s.angle = (s.angle + Cfg.spin * (1 + Cfg.surge.spin * surge) * dt) % 360
	local since = now - firedAt
	local n = #s.runes
	for i, r in s.runes do
		local a = math.rad(s.angle + 360 * (i - 1) / n)
		local out = Cfg.orbit * (1 - Cfg.surge.tighten * surge)
		local fade: number
		if state == "Fired" then
			-- scattering outward and fading
			local k = math.clamp(since / Cfg.flare, 0, 1)
			out += Cfg.scatter * k
			fade = k
		else
			-- (user 2026-10-21: the runes "die when it's reloading"): dark through the reload, back when it's ready
			local on = if state == "Charging" then 0 else 1
			-- waking: a flicker before it holds
			local flick = if on > 0 and on < 1 then 0.5 + 0.5 * math.sin(clock * 40 + i) else 1
			fade = 1 - on * flick
		end
		local bob = Cfg.bob * math.sin(clock * 1.7 + i)
		r.gui.StudsOffsetWorldSpace = Vector3.new(math.cos(a) * out, bob, math.sin(a) * out)
		r.gui.Enabled = fade < 0.99
		local runeColor = colorAt(math.max(glow, 0.6))
		for _, f in r.strokes do
			f.BackgroundColor3 = runeColor
			f.BackgroundTransparency = fade
		end
	end
end

function ArtilleryCrystal.destroy(s: State)
	s.holder:Destroy()
	local box = s.motes.Parent
	if box then
		box:Destroy()
	end
end

return ArtilleryCrystal
