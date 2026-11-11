--!strict
-- Dev-only village prop generator (Config/Props, Palette.Props). Same chunky, slightly hand-made,
-- flat-color look as the houses. Every prop is a destructible section (Kind "Prop"). Stones, hedges, hay, barrels,
-- logs, posts, rails, pickets, signpost fingers, wheels and lanterns are low-poly faceted meshes from the PropKit
-- (Config/Assets.Entries.PropKit, tools/blender/village_props.py), each fitted to the box a plain part filled before;
-- boards and planks (cart bed, well roof) stay parts.
--   Props.build(kind, deps)                     -> Model at the origin (library sample; linear kinds
--                                                  are a straight SampleLength run along +X)
--   Props.linear(kind, parent, a, b, ground, deps) -> a wall/fence/hedge run from a to b on the ground
--   Props.wire(parent, p1, p2, deps)             -> a sagging telegraph wire
--   Props.paint(model, palette)                  -> colors by Paint role (+ per-piece Tone)
-- deps = { P = Config/Props, D = Config/Destruction, Kit = the PropKit model (src/dev/Library.ensure("PropKit")) }

local CollectionService = game:GetService("CollectionService")

local Props = {}

type Ctx = { n: number, D: any, kit: Instance }

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

local function tag(p: BasePart, ctx: Ctx, name: string, paint: string, parent: Instance)
	p.Name = name
	p:SetAttribute("Paint", paint)
	if TONED[paint] then
		p:SetAttribute("Tone", jitter(ctx, 3))
	end
	p.Parent = parent
	ctx.n += 1
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
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	tag(p, ctx, name, paint, parent)
	return p
end

-- a PropKit mesh as a piece: `kitName`'s mesh fitted to the box (cf, size). Kit meshes run long along Z and stand
-- along Y, so a mesh takes the same box a plain part would.
local function mesh(
	parent: Instance,
	ctx: Ctx,
	name: string,
	kitName: string,
	cf: CFrame,
	size: Vector3,
	paint: string
): BasePart
	local src = ctx.kit:FindFirstChild(kitName, true)
	assert(src and src:IsA("MeshPart"), "PropKit has no mesh " .. kitName)
	local p = src:Clone()
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cf
	tag(p, ctx, name, paint, parent)
	return p
end

-- one of a few variants, by the piece count
local function pick(ctx: Ctx, list: { string }): string
	return list[(ctx.n % #list) + 1]
end

-- turned end for end by hash (a bay or a mound looks different from the other side)
local function flip(ctx: Ctx, salt: number): CFrame
	return if jitter(ctx, salt) > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
end

-- a hewn post `w` thick from `y0` up to `y0 + h`, at (x, z) in `frame`
local function post(
	sec: Instance,
	ctx: Ctx,
	frame: CFrame,
	x: number,
	y0: number,
	z: number,
	w: number,
	h: number,
	paint: string
): BasePart
	return mesh(sec, ctx, "Post", "Post", frame * CFrame.new(x, y0 + h / 2, z), Vector3.new(w, h, w), paint)
end

-- a hewn beam along `frame`'s X (kit beams run along Z)
local ACROSS = CFrame.Angles(0, math.pi / 2, 0)

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
-- A dry-stone bay: a kit wall body (three courses of chamfered stones, its ends cut flat so bays join, from just below
-- the ground) under a row of coping slabs whose top is the wall's height, so the wall stays as hoppable as before.
local WALLS, CAPS = { "WallA", "WallB", "WallC" }, { "CapA", "CapB", "CapC" }
local COPING = 0.4 -- the coping's depth

local function stoneWallBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any, drop: number)
	local c = P.StoneWall
	local t = c.thickness
	local bottom, top = -0.4 - drop, c.height - COPING + 0.1
	local turn = flip(ctx, 1)
	mesh(
		sec,
		ctx,
		"Stones",
		pick(ctx, WALLS),
		frame * CFrame.new(0, (bottom + top) / 2, 0) * turn,
		Vector3.new(t, top - bottom, len + 0.02),
		if ctx.n % 2 == 0 then "Stone" else "StoneDark"
	)
	mesh(
		sec,
		ctx,
		"Coping",
		pick(ctx, CAPS),
		frame * CFrame.new(0, c.height - COPING / 2, 0) * turn,
		Vector3.new(t + 0.25, COPING, len + 0.05),
		"StoneDark"
	)
end

local function picketBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any, drop: number)
	local c = P.PicketFence
	post(sec, ctx, frame, 0, -1 - drop, -len / 2, 0.5, c.height + 1.2 + drop, "Wood")
	for _, y in { 0.6, c.height - 0.5 } do
		mesh(sec, ctx, "Rail", "Beam", frame * CFrame.new(0.3, y, 0), Vector3.new(0.18, 0.28, len), "WoodPale")
	end
	local n = math.max(1, math.floor(len / c.picketGap))
	for i = 0, n - 1 do
		local z = -len / 2 + (i + 0.5) * len / n
		local h = c.height - 0.15 + jitter(ctx, 6) * 0.12
		mesh(
			sec,
			ctx,
			"Picket",
			"Picket",
			frame * CFrame.new(0.45, (h - 0.6 - drop) / 2, z),
			Vector3.new(0.16, h + 0.6 + drop, 0.5),
			"WoodPale"
		)
	end
end

local function railBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any, drop: number)
	local c = P.RailFence
	mesh(
		sec,
		ctx,
		"Post",
		"Post",
		frame
			* CFrame.new(0, c.height / 2 - 0.2 - drop / 2, -len / 2)
			* CFrame.Angles(math.rad(jitter(ctx, 7) * 3), 0, math.rad(jitter(ctx, 8) * 3)),
		Vector3.new(0.6, c.height + 0.6 + drop, 0.6),
		"WoodDark"
	)
	for _, y in { 0.75, c.height - 0.35 } do
		mesh(
			sec,
			ctx,
			"Rail",
			"Beam",
			frame * CFrame.new(0, y + jitter(ctx, 9) * 0.08, 0) * CFrame.Angles(math.rad(jitter(ctx, 10) * 1.5), 0, 0),
			Vector3.new(0.32, 0.32, len + 0.4),
			"Wood"
		)
	end
end

-- a hedge bay: a kit mass of leaf clumps, its ends cut flat so the bays join into one hedge (it blocks)
local function hedgeBay(sec: Instance, ctx: Ctx, frame: CFrame, len: number, P: any, drop: number)
	local c = P.Hedge
	local h = c.height + jitter(ctx, 11) * 0.35
	mesh(
		sec,
		ctx,
		"Hedge",
		pick(ctx, { "HedgeA", "HedgeB" }),
		frame * CFrame.new(0, (h - 0.6 - drop) / 2, 0) * flip(ctx, 12),
		Vector3.new(c.thickness, h + 0.6 + drop, len + 0.15),
		if ctx.n % 2 == 0 then "Hedge" else "HedgeDark"
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

-- A run from a to b; ground(x, z) -> surface height. Each bay sits on the lowest ground along it and reaches down
-- past that by the drop to its highest, so no end hangs in the air on a slope or over a furrow (user 2026-11-11: "the
-- bricks and bushes dont rest properly on the terrain"; was the highest of its ends and middle).
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
	local ctx: Ctx = { n = math.floor(a.X * 7 + a.Z * 13) % 1000, D = deps.D, kit = deps.Kit }
	local run = Instance.new("Model")
	run.Name = kind
	for _, bay in bays(a, b, spec.bay) do
		local cf = bay[1] :: CFrame
		local len = bay[2] :: number
		-- the ground along the bay and across its width: the lowest seats it, its pieces reach down by the drop
		local p, dir = cf.Position, cf.LookVector
		local side = cf.RightVector * ((deps.P[kind].thickness or 0.6) / 2)
		local lo, hi = math.huge, -math.huge
		for _, k in { -0.5, -0.25, 0, 0.25, 0.5 } do
			for _, w in { -1, 1 } do
				local q = p + dir * (len * k) + side * w
				local g = ground(q.X, q.Z)
				lo, hi = math.min(lo, g), math.max(hi, g)
			end
		end
		local frame = CFrame.new(p.X, lo, p.Z) * cf.Rotation
		local sec = section(run, ctx, kind, deps.P[kind].class)
		spec.build(sec, ctx, frame, len, deps.P, hi - lo)
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
	local arm = mesh(sec, ctx, "Crossarm", "Beam", CFrame.new(0, h - 2, 0) * ACROSS, Vector3.new(0.4, 0.4, 5), "Wood")
	for i, x in { -2, 2 } do
		cyl(sec, ctx, "Insulator", CFrame.new(x, h - 1.55, 0) * UPRIGHT, 0.5, 0.35, "WoodPale")
		local att = Instance.new("Attachment")
		att.Name = "Wire" .. i
		att.Parent = arm
		att.WorldPosition = Vector3.new(x, h - 2 + 0.55, 0) -- the arm is turned a quarter: placed in the world
	end
	mesh(
		sec,
		ctx,
		"Brace",
		"Beam",
		CFrame.new(0.7, h - 2.7, 0) * CFrame.Angles(0, 0, math.rad(40)) * ACROSS,
		Vector3.new(0.2, 0.2, 1.6),
		"Wood"
	)
end

-- a festival lantern pole (Lantern Meadows): a dark post, a crossbar on top, a paper lantern hanging off each end
POINT.LanternPole = function(m: Model, ctx: Ctx, P: any)
	local sec = section(m, ctx, "LanternPole", "Wood")
	local h, arm = P.LanternPole.height, P.LanternPole.arm
	post(sec, ctx, CFrame.identity, 0, -1, 0, 0.5, h + 1, "WoodDark")
	mesh(sec, ctx, "Crossbar", "Beam", CFrame.new(0, h - 0.4, 0) * ACROSS, Vector3.new(0.3, 0.3, arm), "WoodDark")
	part(sec, ctx, "Cap", CFrame.new(0, h + 0.1, 0), Vector3.new(0.7, 0.25, 0.7), "WoodDark")
	for _, x in { -arm / 2 + 0.3, arm / 2 - 0.3 } do
		part(sec, ctx, "Cord", CFrame.new(x, h - 0.9, 0), Vector3.new(0.1, 0.7, 0.1), "Metal")
		mesh(sec, ctx, "Lantern", "Lantern", CFrame.new(x, h - 1.8, 0), Vector3.new(0.8, 1.1, 0.8), "Lantern")
	end
end

POINT.Signpost = function(m: Model, ctx: Ctx, P: any)
	local sec = section(m, ctx, "Signpost", "Wood")
	local h = P.Signpost.height
	post(sec, ctx, CFrame.identity, 0, -1, 0, 0.45, h + 1.25, "WoodDark")
	for i, ang in { 15, 115, -60 } do
		local y = h - 0.9 - (i - 1) * 0.9
		mesh(
			sec,
			ctx,
			"Finger",
			"Finger",
			CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(ang), 0) * CFrame.new(1.4, 0, 0),
			Vector3.new(2.6, 0.55, 0.12),
			"WoodPale"
		)
	end
end

POINT.Well = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Well", "Stone")
	mesh(sec, ctx, "Stones", "WellRing", CFrame.new(0, 1, 0), Vector3.new(5.9, 2.3, 5.9), "Stone")
	part(sec, ctx, "Water", CFrame.new(0, 0.6, 0), Vector3.new(3.6, 0.2, 3.6), "Water")
	for _, x in { -2.2, 2.2 } do
		post(sec, ctx, CFrame.identity, x, 1.0, 0, 0.4, 4.7, "WoodDark")
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
	mesh(sec, ctx, "Bucket", "Barrel", CFrame.new(0, 3.2, 0), Vector3.new(0.85, 0.8, 0.8), "Wood")
end

-- a hewn stone trough (hollow), long along X, water standing in it
POINT.Trough = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Trough", "Stone")
	mesh(sec, ctx, "Trough", "Trough", CFrame.new(0, 0.7, 0) * ACROSS, Vector3.new(2.2, 1.8, 5.2), "Stone")
	part(sec, ctx, "Water", CFrame.new(0, 1.3, 0), Vector3.new(4.4, 0.2, 1.4), "Water")
end

-- three bulged stave barrels, each with its two iron hoops, each turned its own way
POINT.Barrels = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Barrels", "Wood")
	for i, p in { { 0, 0 }, { 1.9, 0.4 }, { 0.8, 1.7 } } do
		local h = 2.2
		local cf = CFrame.new(p[1], h / 2, p[2]) * CFrame.Angles(0, (jitter(ctx, 2) + 1) * math.pi, 0)
		local size = Vector3.new(1.9, h, 1.81)
		mesh(sec, ctx, "Barrel", "Barrel", cf, size, if i == 2 then "WoodDark" else "Wood")
		mesh(sec, ctx, "Hoops", "Hoops", cf, size, "Metal")
	end
end

-- a stack of split logs (3 rows), pinned by two stakes
POINT.Woodpile = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Woodpile", "Wood")
	for row = 0, 2 do
		local count = 4 - row
		for i = 0, count - 1 do
			local x = (i - (count - 1) / 2) * 0.62
			mesh(
				sec,
				ctx,
				"Log",
				pick(ctx, { "LogA", "LogB" }),
				CFrame.new(x, 0.3 + row * 0.55, jitter(ctx, 4) * 0.15)
					* flip(ctx, 5)
					* CFrame.Angles(0, 0, jitter(ctx, 6) * math.pi),
				Vector3.new(0.62, 0.6, 3 + jitter(ctx, 2) * 0.3),
				if (i + row) % 2 == 0 then "Wood" else "WoodDark"
			)
		end
	end
	for _, x in { -1.6, 1.6 } do
		post(sec, ctx, CFrame.identity, x, -0.05, 0, 0.22, 1.9, "WoodDark")
	end
end

-- a faceted hay mound
POINT.Haystack = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Haystack", "Wood")
	mesh(
		sec,
		ctx,
		"Hay",
		"Haystack",
		CFrame.new(0, 2.1, 0) * CFrame.Angles(0, math.rad(jitter(ctx, 1) * 20), 0),
		Vector3.new(5.2, 4.4, 4.4),
		"Hay"
	)
end

POINT.Cart = function(m: Model, ctx: Ctx, _P: any)
	local sec = section(m, ctx, "Cart", "Wood")
	part(sec, ctx, "Bed", CFrame.new(0, 1.9, 0), Vector3.new(3.6, 0.3, 5.6), "Wood")
	for _, s in { -1, 1 } do
		part(sec, ctx, "Side", CFrame.new(s * 1.75, 2.45, 0), Vector3.new(0.2, 0.8, 5.6), "WoodDark")
		mesh(sec, ctx, "Wheel", "Wheel", CFrame.new(s * 2.05, 1.35, 0.6), Vector3.new(0.45, 2.7, 2.7), "WoodDark")
		mesh(
			sec,
			ctx,
			"Shaft",
			"Beam",
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
	local ctx: Ctx = { n = #kind * 37, D = deps.D, kit = deps.Kit }
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
