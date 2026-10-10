--!strict
-- Dev-only village prop generator (Config/Props, Palette.Props). Same chunky, slightly hand-made,
-- flat-color look as the houses. Every prop is a destructible section (Kind "Prop").
--   Props.build(kind, deps)                     -> Model at the origin (library sample; linear kinds
--                                                  are a straight SampleLength run along +X)
--   Props.linear(kind, parent, a, b, ground, deps) -> a wall/fence/hedge run from a to b on the ground
--   Props.wire(parent, p1, p2, deps)             -> a sagging telegraph wire
--   Props.paint(model, palette)                  -> colors by Paint role (+ per-piece Tone)
-- deps = { P = Config/Props, D = Config/Destruction }

local CollectionService = game:GetService("CollectionService")

local Props = {}

type Ctx = { n: number, D: any }

local TONED = {
	Stone = true,
	StoneDark = true,
	Wood = true,
	WoodDark = true,
	WoodPale = true,
	Hedge = true,
	HedgeDark = true,
	Hay = true,
}

local function jitter(ctx: Ctx, salt: number): number
	local h = (ctx.n * 7919 + salt * 104729) % 2003
	return h / 1001.5 - 1
end

local function part(
	parent: Instance,
	ctx: Ctx,
	name: string,
	cf: CFrame,
	size: Vector3,
	paint: string,
	shape: Enum.PartType?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p:SetAttribute("Paint", paint)
	if TONED[paint] then
		p:SetAttribute("Tone", jitter(ctx, 3))
	end
	p.Parent = parent
	ctx.n += 1
	return p
end

local function section(parent: Instance, ctx: Ctx, name: string, class: string): Model
	local m = Instance.new("Model")
	m.Name = name
	local hp = ctx.D.Materials[class].hp
	m:SetAttribute("Kind", "Prop")
	m:SetAttribute("Class", class)
	m:SetAttribute("Story", 0)
	m:SetAttribute("MaxHP", hp)
	m:SetAttribute("HP", hp)
	CollectionService:AddTag(m, ctx.D.SectionTag)
	m.Parent = parent
	return m
end

local function cyl(
	parent: Instance,
	ctx: Ctx,
	name: string,
	cf: CFrame,
	length: number,
	diameter: number,
	paint: string
): BasePart
	-- Roblox cylinders run along X; callers pass cf with X along the cylinder axis
	return part(parent, ctx, name, cf, Vector3.new(length, diameter, diameter), paint, Enum.PartType.Cylinder)
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's X axis to vertical

---------------------------------------------------------------------------------------------------
-- Linear props: one section per bay, each bay sitting on the ground at its midpoint
---------------------------------------------------------------------------------------------------

local function bays(a: Vector3, b: Vector3, bay: number): { { CFrame | number } }
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local L = flat.Magnitude
	local dir = flat.Unit
	local n = math.max(1, math.round(L / bay))
	local out = {}
	for i = 0, n - 1 do
		local mid = a + dir * ((i + 0.5) * L / n)
		table.insert(out, { CFrame.lookAt(mid, mid + dir), L / n })
	end
	return out
end

-- frame: bay center on the ground, -Z along the run (lookAt). len = bay length.
local function stoneWallBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any)
	local c = P.StoneWall
	local t = c.thickness
	local h1 = c.height * 0.55
	local h2 = c.height - h1 - 0.35
	-- two irregular courses of stones, then a rough coping
	local stones = math.max(1, math.round(len / c.stone))
	local sl = len / stones
	for i = 0, stones - 1 do
		local z = -len / 2 + (i + 0.5) * sl
		part(
			sec,
			ctx,
			"Stone",
			frame * CFrame.new(jitter(ctx, 1) * 0.08, h1 / 2 - 0.3, z),
			Vector3.new(t, h1 + 0.6, sl - 0.06),
			if i % 2 == 0 then "Stone" else "StoneDark"
		)
		local z2 = z + sl * 0.5 * (if i % 2 == 0 then 1 else -1) * 0.4
		part(
			sec,
			ctx,
			"Stone",
			frame
				* CFrame.new(jitter(ctx, 2) * 0.1, h1 + h2 / 2, z2)
				* CFrame.Angles(0, math.rad(jitter(ctx, 4) * 2), 0),
			Vector3.new(t * 0.9, h2, sl * 0.9),
			if i % 2 == 0 then "StoneDark" else "Stone"
		)
	end
	part(
		sec,
		ctx,
		"Coping",
		frame * CFrame.new(0, c.height - 0.18, 0) * CFrame.Angles(math.rad(jitter(ctx, 5) * 1.5), 0, 0),
		Vector3.new(t + 0.25, 0.36, len + 0.05),
		"StoneDark"
	)
end

local function picketBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any)
	local c = P.PicketFence
	part(sec, ctx, "Post", frame * CFrame.new(0, c.height / 2, -len / 2), Vector3.new(0.5, c.height + 0.4, 0.5), "Wood")
	for _, y in { 0.6, c.height - 0.5 } do
		part(sec, ctx, "Rail", frame * CFrame.new(0.3, y, 0), Vector3.new(0.18, 0.28, len), "WoodPale")
	end
	local n = math.max(1, math.floor(len / c.picketGap))
	for i = 0, n - 1 do
		local z = -len / 2 + (i + 0.5) * len / n
		local h = c.height - 0.15 + jitter(ctx, 6) * 0.12
		part(sec, ctx, "Picket", frame * CFrame.new(0.45, h / 2, z), Vector3.new(0.16, h, 0.5), "WoodPale")
	end
end

local function railBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any)
	local c = P.RailFence
	part(
		sec,
		ctx,
		"Post",
		frame
			* CFrame.new(0, c.height / 2 - 0.2, -len / 2)
			* CFrame.Angles(math.rad(jitter(ctx, 7) * 3), 0, math.rad(jitter(ctx, 8) * 3)),
		Vector3.new(0.6, c.height + 0.6, 0.6),
		"WoodDark"
	)
	for _, y in { 0.75, c.height - 0.35 } do
		part(
			sec,
			ctx,
			"Rail",
			frame * CFrame.new(0, y + jitter(ctx, 9) * 0.08, 0) * CFrame.Angles(math.rad(jitter(ctx, 10) * 1.5), 0, 0),
			Vector3.new(0.32, 0.32, len + 0.4),
			"Wood"
		)
	end
end

local function hedgeBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any)
	local c = P.Hedge
	local h = c.height + jitter(ctx, 11) * 0.35
	part(
		sec,
		ctx,
		"Hedge",
		frame * CFrame.new(0, h / 2 - 0.3, 0),
		Vector3.new(c.thickness, h + 0.6, len + 0.15),
		if ctx.n % 2 == 0 then "Hedge" else "HedgeDark"
	)
	part(
		sec,
		ctx,
		"Hedge",
		frame
			* CFrame.new(jitter(ctx, 12) * 0.2, h + 0.15, jitter(ctx, 13) * len * 0.15)
			* CFrame.Angles(0, math.rad(jitter(ctx, 14) * 8), 0),
		Vector3.new(c.thickness * 0.8, 0.8, len * 0.6),
		"HedgeDark"
	)
end

local LINEAR = {
	StoneWall = { bay = 6, build = stoneWallBay },
	PicketFence = { bay = 6, build = picketBay },
	RailFence = { bay = 5, build = railBay },
	Hedge = { bay = 4, build = hedgeBay },
}

function Props.isLinear(kind: string): boolean
	return LINEAR[kind] ~= nil
end

-- A run from a to b; ground(x, z) -> surface height. Each bay sits on the ground at its midpoint.
function Props.linear(
	kind: string,
	parent: Instance,
	a: Vector3,
	b: Vector3,
	ground: (number, number) -> number,
	deps: any
): Model
	local spec = LINEAR[kind]
	assert(spec, "not a linear prop: " .. kind)
	local ctx: Ctx = { n = math.floor(a.X * 7 + a.Z * 13) % 1000, D = deps.D }
	local run = Instance.new("Model")
	run.Name = kind
	for _, bay in bays(a, b, spec.bay) do
		local cf = bay[1] :: CFrame
		local len = bay[2] :: number
		local y = ground(cf.Position.X, cf.Position.Z)
		local frame = CFrame.new(cf.Position.X, y, cf.Position.Z) * cf.Rotation
		local sec = section(run, ctx, kind, deps.P[kind].class)
		spec.build(sec, ctx, frame, len, deps.P)
	end
	run.Parent = parent
	return run
end

---------------------------------------------------------------------------------------------------
-- Point props (built at the origin, ground at y 0, "front" toward -Z)
---------------------------------------------------------------------------------------------------

local POINT = {}

POINT.Pole = function(m: Model, ctx: Ctx, P: any)
	local sec = section(m, ctx, "Pole", "Wood")
	local h = P.Pole.height
	cyl(sec, ctx, "Post", CFrame.new(0, h / 2 - 1, 0) * UPRIGHT, h, 0.8, "WoodDark")
	local arm = part(sec, ctx, "Crossarm", CFrame.new(0, h - 2, 0), Vector3.new(5, 0.4, 0.4), "Wood")
	for i, x in { -2, 2 } do
		cyl(sec, ctx, "Insulator", CFrame.new(x, h - 1.55, 0) * UPRIGHT, 0.5, 0.35, "WoodPale")
		local att = Instance.new("Attachment")
		att.Name = "Wire" .. i
		att.Position = Vector3.new(x, 0.55, 0)
		att.Parent = arm
	end
	part(
		sec,
		ctx,
		"Brace",
		CFrame.new(0.7, h - 2.7, 0) * CFrame.Angles(0, 0, math.rad(40)),
		Vector3.new(1.6, 0.2, 0.2),
		"Wood"
	)
end

POINT.Signpost = function(m: Model, ctx: Ctx, P: any)
	local sec = section(m, ctx, "Signpost", "Wood")
	local h = P.Signpost.height
	part(sec, ctx, "Post", CFrame.new(0, h / 2 - 0.5, 0), Vector3.new(0.45, h + 1, 0.45), "WoodDark")
	part(sec, ctx, "Cap", CFrame.new(0, h + 0.1, 0), Vector3.new(0.7, 0.25, 0.7), "WoodDark")
	for i, ang in { 15, 115, -60 } do
		local y = h - 0.9 - (i - 1) * 0.9
		part(
			sec,
			ctx,
			"Finger",
			CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(ang), 0) * CFrame.new(1.4, 0, 0),
			Vector3.new(2.6, 0.55, 0.12),
			"WoodPale"
		)
	end
end

POINT.Well = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Well", "Stone")
	local r = 2.4
	for i = 0, 7 do
		local a = i * math.pi / 4
		part(
			sec,
			ctx,
			"Stone",
			CFrame.new(math.cos(a) * r, 1, math.sin(a) * r) * CFrame.Angles(0, -a, 0),
			Vector3.new(0.9, 2.2 + jitter(ctx, 1) * 0.15, 2.1),
			if i % 2 == 0 then "Stone" else "StoneDark"
		)
	end
	part(sec, ctx, "Water", CFrame.new(0, 0.6, 0), Vector3.new(3.6, 0.2, 3.6), "Water")
	for _, x in { -2.2, 2.2 } do
		part(sec, ctx, "Post", CFrame.new(x, 3.4, 0), Vector3.new(0.4, 4.4, 0.4), "WoodDark")
	end
	cyl(sec, ctx, "Winch", CFrame.new(0, 4.4, 0), 4.6, 0.4, "Wood")
	for _, s in { -1, 1 } do
		part(
			sec,
			ctx,
			"Roof",
			CFrame.new(0, 6.0, s * 1.05) * CFrame.Angles(math.rad(35) * -s, 0, 0),
			Vector3.new(5.6, 0.3, 2.8),
			"WoodDark"
		)
	end
	cyl(sec, ctx, "Bucket", CFrame.new(0, 3.2, 0) * UPRIGHT, 0.8, 0.8, "Wood")
end

POINT.Trough = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Trough", "Stone")
	part(sec, ctx, "Base", CFrame.new(0, 0.55, 0), Vector3.new(5, 1.5, 2), "StoneDark")
	part(sec, ctx, "Rim", CFrame.new(0, 1.4, 0), Vector3.new(5.2, 0.3, 2.2), "Stone")
	part(sec, ctx, "Water", CFrame.new(0, 1.3, 0), Vector3.new(4.4, 0.2, 1.4), "Water")
end

POINT.Barrels = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Barrels", "Wood")
	for i, p in { { 0, 0 }, { 1.9, 0.4 }, { 0.8, 1.7 } } do
		local h = 2.2
		cyl(sec, ctx, "Barrel", CFrame.new(p[1], h / 2, p[2]) * UPRIGHT, h, 1.7, if i == 2 then "WoodDark" else "Wood")
		for _, y in { 0.45, h - 0.45 } do
			cyl(sec, ctx, "Hoop", CFrame.new(p[1], y, p[2]) * UPRIGHT, 0.18, 1.78, "Metal")
		end
	end
end

POINT.Woodpile = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Woodpile", "Wood")
	for row = 0, 2 do
		local count = 4 - row
		for i = 0, count - 1 do
			local x = (i - (count - 1) / 2) * 0.62
			cyl(
				sec,
				ctx,
				"Log",
				CFrame.new(x, 0.3 + row * 0.55, 0) * CFrame.Angles(0, math.pi / 2, 0),
				3 + jitter(ctx, 2) * 0.3,
				0.6,
				if (i + row) % 2 == 0 then "Wood" else "WoodDark"
			)
		end
	end
	for _, x in { -1.6, 1.6 } do
		part(sec, ctx, "Stake", CFrame.new(x, 0.9, 0), Vector3.new(0.2, 1.9, 0.2), "WoodDark")
	end
end

POINT.Haystack = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Haystack", "Wood")
	part(sec, ctx, "Hay", CFrame.new(0, 1.3, 0), Vector3.new(5, 2.6, 4.2), "Hay")
	part(
		sec,
		ctx,
		"Hay",
		CFrame.new(0.2, 3.0, 0) * CFrame.Angles(0, math.rad(12), 0),
		Vector3.new(3.8, 1.2, 3.2),
		"Hay"
	)
	part(
		sec,
		ctx,
		"Hay",
		CFrame.new(-0.1, 3.9, 0.1) * CFrame.Angles(0, math.rad(-8), 0),
		Vector3.new(2.2, 0.8, 2),
		"Hay"
	)
end

POINT.Cart = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Cart", "Wood")
	part(sec, ctx, "Bed", CFrame.new(0, 1.9, 0), Vector3.new(3.6, 0.3, 5.6), "Wood")
	for _, s in { -1, 1 } do
		part(sec, ctx, "Side", CFrame.new(s * 1.75, 2.45, 0), Vector3.new(0.2, 0.8, 5.6), "WoodDark")
		cyl(sec, ctx, "Wheel", CFrame.new(s * 2.05, 1.35, 0.6), 0.3, 2.7, "WoodDark")
		part(
			sec,
			ctx,
			"Shaft",
			CFrame.new(s * 1.1, 1.6, -4.3) * CFrame.Angles(math.rad(-8), 0, 0),
			Vector3.new(0.25, 0.25, 3.6),
			"Wood"
		)
	end
	part(sec, ctx, "Back", CFrame.new(0, 2.45, 2.75), Vector3.new(3.6, 0.8, 0.2), "WoodDark")
end

POINT.Car = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Car", "Wood")
	part(sec, ctx, "Chassis", CFrame.new(0, 1.55, 0), Vector3.new(4.2, 0.6, 10.4), "Metal")
	part(sec, ctx, "Body", CFrame.new(0, 2.5, 0.8), Vector3.new(4.2, 1.5, 6.2), "CarBody")
	part(sec, ctx, "Hood", CFrame.new(0, 2.55, -3.4), Vector3.new(3.0, 1.3, 3.4), "CarBody")
	part(sec, ctx, "Grille", CFrame.new(0, 2.55, -5.15), Vector3.new(2.4, 1.3, 0.2), "Metal")
	part(sec, ctx, "Cabin", CFrame.new(0, 3.95, 1.2), Vector3.new(3.9, 1.5, 4.0), "CarBody")
	part(sec, ctx, "Windows", CFrame.new(0, 4.0, 1.2), Vector3.new(4.0, 0.9, 3.6), "Glass")
	part(sec, ctx, "Roof", CFrame.new(0, 4.8, 1.2), Vector3.new(4.0, 0.25, 4.2), "CarBody")
	for _, s in { -1, 1 } do
		part(sec, ctx, "RunningBoard", CFrame.new(s * 2.3, 1.45, 0.2), Vector3.new(0.6, 0.18, 4.4), "Metal")
		cyl(sec, ctx, "Headlamp", CFrame.new(s * 1.15, 3.3, -4.9) * CFrame.Angles(0, math.pi / 2, 0), 0.5, 0.7, "Metal")
		for _, z in { -3.4, 3.4 } do
			cyl(sec, ctx, "Wheel", CFrame.new(s * 1.95, 1.2, z), 0.7, 2.4, "Rubber")
			part(sec, ctx, "Fender", CFrame.new(s * 2.0, 2.15, z), Vector3.new(1.0, 0.35, 3.0), "CarBody")
		end
	end
	cyl(sec, ctx, "Spare", CFrame.new(0, 2.5, 5.4) * CFrame.Angles(0, math.pi / 2, 0), 0.6, 2.2, "Rubber")
end

function Props.build(kind: string, deps: any): Model
	local m = Instance.new("Model")
	m.Name = kind
	local ctx: Ctx = { n = #kind * 37, D = deps.D }
	if LINEAR[kind] then
		local L = deps.P.SampleLength
		Props.linear(kind, m, Vector3.new(-L / 2, 0, 0), Vector3.new(L / 2, 0, 0), function()
			return 0
		end, deps).Parent =
			m
	else
		local f = POINT[kind]
		assert(f, "unknown prop " .. kind)
		f(m, ctx, deps.P)
	end
	m.WorldPivot = CFrame.identity
	return m
end

-- A telegraph wire between two points, sagging in the middle (a few straight segments).
function Props.wire(parent: Instance, p1: Vector3, p2: Vector3, deps: any)
	local W = deps.P.Wire
	local n = W.segments
	local function at(t: number): Vector3
		return p1:Lerp(p2, t) - Vector3.new(0, W.sag * 4 * t * (1 - t), 0)
	end
	for i = 0, n - 1 do
		local a, b = at(i / n), at((i + 1) / n)
		local p = Instance.new("Part")
		p.Name = "Wire"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = Vector3.new(0.08, 0.08, (b - a).Magnitude)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p:SetAttribute("Paint", "Metal")
		p.Parent = parent
	end
end

function Props.paint(model: Instance, palette: any, carIndex: number?)
	local P = palette.Props
	local function rgb(c: { number }): Color3
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local colors: { [string]: Color3 } = {}
	for role, c in P do
		if type(c) == "table" and type(c[1]) == "number" then
			colors[role] = rgb(c)
		end
	end
	colors.CarBody = rgb(P.CarBodies[((carIndex or 0) % #P.CarBodies) + 1])
	local jit = P.ToneJitter or 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Paint")
			local c = role and colors[role]
			if c then
				local k = 1 + jit * (d:GetAttribute("Tone") or 0)
				d.Color = Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
			end
			if role == "Glass" or role == "Water" then
				d.Transparency = 0.3
			end
		end
	end
end

return Props
