--!strict
-- Building geometry primitives. Every part gets a "Paint" role attribute (Wall, Roof, Trim, Door,
-- Glass, Floor, Stairs, Foundation, Chimney, Metal, Sign, Wood) that Buildings.paint colors later.
-- Destructible units are SECTION Models (attributes Kind/Class/Story/MaxHP/HP, tagged).
-- Wall frames: CFrame at the wall's center line at the story base; local X runs along the wall,
-- local -Z points OUTSIDE.

local CollectionService = game:GetService("CollectionService")

local Geometry = {}

export type Ctx = {
	D: any, -- Config/Destruction
	M: any, -- Config/Metrics
	B: any, -- Config/Buildings
	T: number, -- wall thickness
	class: string, -- wall material class
	count: number, -- parts created
}

export type Opening = { kind: string, w: number, bottom: number, top: number }

function Geometry.part(
	parent: Instance,
	ctx: Ctx,
	name: string,
	cf: CFrame,
	size: Vector3,
	paint: string,
	className: string?
): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p:SetAttribute("Paint", paint)
	p.Parent = parent
	ctx.count += 1
	return p
end

function Geometry.section(parent: Instance, ctx: Ctx, kind: string, class: string, story: number): Model
	local m = Instance.new("Model")
	m.Name = kind
	local hp = ctx.D.Materials[class].hp
	m:SetAttribute("Kind", kind)
	m:SetAttribute("Class", class)
	m:SetAttribute("Story", story)
	m:SetAttribute("MaxHP", hp)
	m:SetAttribute("HP", hp)
	CollectionService:AddTag(m, ctx.D.SectionTag)
	m.Parent = parent
	return m
end

-- Section widths for a wall of length L: ~SectionWidth each; an optional wider center section
-- (for wide doors) is kept whole and the rest split evenly either side.
function Geometry.layout(L: number, sw: number, centerWidth: number?): ({ number }, number?)
	if not centerWidth or centerWidth <= sw then
		local n = math.max(1, math.floor(L / sw))
		local out = table.create(n, L / n)
		return out, if n >= 1 then math.floor(n / 2) + 1 else nil
	end
	local side = (L - centerWidth) / 2
	local k = math.max(1, math.floor(side / sw))
	local out = {}
	for _ = 1, k do
		table.insert(out, side / k)
	end
	table.insert(out, centerWidth)
	for _ = 1, k do
		table.insert(out, side / k)
	end
	return out, k + 1
end

local function glass(parent: Instance, ctx: Ctx, frame: CFrame, c: number, o: Opening, story: number)
	local g = Geometry.section(parent, ctx, "Glass", "Glass", story)
	local w, h = o.w, o.top - o.bottom
	local mid = (o.bottom + o.top) / 2
	local pane = Geometry.part(g, ctx, "Pane", frame * CFrame.new(c, mid, 0), Vector3.new(w, h, 0.2), "Glass")
	pane.Transparency = 0.35
	pane.CastShadow = false
	-- glazing bars
	Geometry.part(g, ctx, "Muntin", frame * CFrame.new(c, mid, -0.12), Vector3.new(0.18, h, 0.12), "Trim")
	Geometry.part(g, ctx, "Muntin", frame * CFrame.new(c, mid, -0.12), Vector3.new(w, 0.18, 0.12), "Trim")
end

local function door(parent: Instance, ctx: Ctx, frame: CFrame, c: number, o: Opening, story: number)
	local d = Geometry.section(parent, ctx, "Door", "Door", story)
	CollectionService:AddTag(d, ctx.D.DoorTag)
	local w, h = o.w - 0.2, o.top - 0.1
	local hingeU = c - o.w / 2 + 0.1
	local panel = Geometry.part(
		d,
		ctx,
		"Panel",
		frame * CFrame.new(hingeU + w / 2, h / 2 + 0.05, 0),
		Vector3.new(w, h, 0.35),
		"Door"
	)
	-- simple raised panels + knob (all move with the door)
	Geometry.part(
		d,
		ctx,
		"Rail",
		frame * CFrame.new(hingeU + w / 2, h * 0.5, -0.22),
		Vector3.new(w - 0.6, 0.25, 0.1),
		"Trim"
	)
	Geometry.part(d, ctx, "Knob", frame * CFrame.new(hingeU + w - 0.5, 3.6, -0.3), Vector3.new(0.3, 0.3, 0.3), "Metal")
	Geometry.part(d, ctx, "Knob", frame * CFrame.new(hingeU + w - 0.5, 3.6, 0.3), Vector3.new(0.3, 0.3, 0.3), "Metal")
	d.PrimaryPart = panel
	-- hinge = the panel's left edge, in panel space; src/server/Doors rotates the door about it
	-- (attribute rather than WorldPivot: pivots set from Studio tool contexts don't persist)
	d:SetAttribute("Hinge", Vector3.new(-w / 2, 0, 0))
	d:SetAttribute("Open", false)
	d:SetAttribute("SwingAngle", -90)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = "Door"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = panel
end

-- One wall, one story. sections[i] = width; openings[i] = Opening for that section (or nil).
function Geometry.wall(
	parent: Instance,
	ctx: Ctx,
	frame: CFrame,
	H: number,
	story: number,
	sections: { number },
	openings: { [number]: Opening? }
)
	local L = 0
	for _, w in sections do
		L += w
	end
	local T = ctx.T
	local u0 = -L / 2
	for i, sw in sections do
		local sec = Geometry.section(parent, ctx, "Wall", ctx.class, story)
		local o = openings[i]
		local function box(a: number, b: number, y0: number, y1: number)
			if b - a > 0.05 and y1 - y0 > 0.05 then
				Geometry.part(
					sec,
					ctx,
					"Wall",
					frame * CFrame.new((a + b) / 2, (y0 + y1) / 2, 0),
					Vector3.new(b - a, y1 - y0, T),
					"Wall"
				)
			end
		end
		if o then
			local w = math.min(o.w, sw - 0.8)
			local c = u0 + sw / 2
			local oo: Opening = { kind = o.kind, w = w, bottom = o.bottom, top = math.min(o.top, H - 0.5) }
			box(u0, c - w / 2, 0, H)
			box(c + w / 2, u0 + sw, 0, H)
			box(c - w / 2, c + w / 2, 0, oo.bottom)
			box(c - w / 2, c + w / 2, oo.top, H)
			-- trim: lintel + sill (outside face, slightly proud)
			Geometry.part(
				sec,
				ctx,
				"Lintel",
				frame * CFrame.new(c, oo.top + 0.2, -T / 2 - 0.1),
				Vector3.new(w + 0.8, 0.4, 0.3),
				"Trim"
			)
			if oo.kind == "door" then
				Geometry.part(
					sec,
					ctx,
					"Casing",
					frame * CFrame.new(c - w / 2 - 0.2, oo.top / 2, -T / 2 - 0.1),
					Vector3.new(0.4, oo.top, 0.3),
					"Trim"
				)
				Geometry.part(
					sec,
					ctx,
					"Casing",
					frame * CFrame.new(c + w / 2 + 0.2, oo.top / 2, -T / 2 - 0.1),
					Vector3.new(0.4, oo.top, 0.3),
					"Trim"
				)
				door(sec, ctx, frame, c, oo, story)
			else
				Geometry.part(
					sec,
					ctx,
					"Sill",
					frame * CFrame.new(c, oo.bottom - 0.15, -T / 2 - 0.2),
					Vector3.new(w + 0.8, 0.3, 0.6),
					"Trim"
				)
				glass(sec, ctx, frame, c, oo, story)
			end
		else
			box(u0, u0 + sw, 0, H)
		end
		u0 += sw
	end
end

-- Axis-aligned slab in building-local space: rect = {x0, x1, z0, z1}, top at yTop.
function Geometry.slab(
	parent: Instance,
	ctx: Ctx,
	cf: CFrame,
	rect: { number },
	yTop: number,
	kind: string,
	story: number,
	paint: string
)
	local sec = Geometry.section(parent, ctx, kind, "Wood", story)
	local x0, x1, z0, z1 = rect[1], rect[2], rect[3], rect[4]
	Geometry.part(
		sec,
		ctx,
		kind,
		cf * CFrame.new((x0 + x1) / 2, yTop - 0.5, (z0 + z1) / 2),
		Vector3.new(x1 - x0, 1, z1 - z0),
		paint
	)
	return sec
end

function Geometry.rectMinusHole(r: { number }, h: { number }): { { number } }
	local out = {}
	if h[3] > r[3] then
		table.insert(out, { r[1], r[2], r[3], h[3] })
	end
	if h[4] < r[4] then
		table.insert(out, { r[1], r[2], h[4], r[4] })
	end
	if h[1] > r[1] then
		table.insert(out, { r[1], h[1], h[3], h[4] })
	end
	if h[2] < r[2] then
		table.insert(out, { h[2], r[2], h[3], h[4] })
	end
	return out
end

-- Straight stair along the back wall, ascending toward +X. Returns the hole rect for the floor above.
function Geometry.stairs(
	parent: Instance,
	ctx: Ctx,
	cf: CFrame,
	W: number,
	Dp: number,
	baseY: number,
	H: number,
	story: number
): { number }
	local Bm = ctx.M.Building
	local steps = math.ceil(H / Bm.StairRise)
	local rise = H / steps
	local x0 = -W / 2 + ctx.T
	local z1 = Dp / 2 - ctx.T
	local z0 = z1 - Bm.StairWidthMin
	local sec = Geometry.section(parent, ctx, "Stairs", "Wood", story)
	for i = 1, steps do
		local top = baseY + i * rise
		local a, b = x0 + (i - 1) * Bm.StairRun, x0 + i * Bm.StairRun
		Geometry.part(
			sec,
			ctx,
			"Step",
			cf * CFrame.new((a + b) / 2, (baseY + top) / 2, (z0 + z1) / 2),
			Vector3.new(b - a, top - baseY, z1 - z0),
			"Stairs"
		)
	end
	return { x0, x0 + steps * Bm.StairRun, z0, z1 }
end

-- Gable triangle in a side-wall frame: two wedges meeting at the ridge (a WedgePart's tall face is +Z).
function Geometry.gable(parent: Instance, ctx: Ctx, frame: CFrame, L: number, h: number, story: number)
	local sec = Geometry.section(parent, ctx, "Gable", ctx.class, story)
	Geometry.part(
		sec,
		ctx,
		"Gable",
		frame * CFrame.new(-L / 4, h / 2, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(ctx.T, h, L / 2),
		"Wall",
		"WedgePart"
	)
	Geometry.part(
		sec,
		ctx,
		"Gable",
		frame * CFrame.new(L / 4, h / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector3.new(ctx.T, h, L / 2),
		"Wall",
		"WedgePart"
	)
end

-- Gabled roof with the ridge along local X. Returns the ridge height above wallTop.
function Geometry.roof(
	parent: Instance,
	ctx: Ctx,
	cf: CFrame,
	W: number,
	Dp: number,
	wallTop: number,
	pitch: number
): number
	local t = math.rad(pitch)
	local ov = ctx.B.RoofOverhang
	local h = (Dp / 2) * math.tan(t)
	local hd = Dp / 2 + ov
	local sl = hd / math.cos(t)
	local len = W + 2 * ov
	local n = math.max(1, math.ceil(len / 8))
	for _, side in { -1, 1 } do
		local zc = side * hd / 2
		local yc = wallTop + h - (hd / 2) * math.tan(t) + 0.4
		for i = 0, n - 1 do
			local sec = Geometry.section(parent, ctx, "Roof", "Tile", 99)
			local xc = -len / 2 + (i + 0.5) * len / n
			Geometry.part(
				sec,
				ctx,
				"Roof",
				cf * CFrame.new(xc, yc, zc) * CFrame.Angles(side * t, 0, 0),
				Vector3.new(len / n + 0.02, 0.8, sl),
				"Roof"
			)
		end
	end
	local cap = Geometry.section(parent, ctx, "Roof", "Tile", 99)
	Geometry.part(
		cap,
		ctx,
		"Ridge",
		cf * CFrame.new(0, wallTop + h + 0.75, 0) * CFrame.Angles(math.pi / 4, 0, 0),
		Vector3.new(len, 1, 1),
		"Roof"
	)
	return h
end

function Geometry.chimney(parent: Instance, ctx: Ctx, cf: CFrame, x: number, z: number, y0: number, y1: number)
	local sec = Geometry.section(parent, ctx, "Chimney", "Brick", 99)
	Geometry.part(sec, ctx, "Stack", cf * CFrame.new(x, (y0 + y1) / 2, z), Vector3.new(2.8, y1 - y0, 2.4), "Chimney")
	Geometry.part(sec, ctx, "Cap", cf * CFrame.new(x, y1 + 0.2, z), Vector3.new(3.2, 0.4, 2.8), "Chimney")
	for _, dx in { -0.65, 0.65 } do
		local pot = Geometry.part(
			sec,
			ctx,
			"Pot",
			cf * CFrame.new(x + dx, y1 + 0.9, z) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(1.1, 0.8, 0.8),
			"Chimney"
		)
		pot.Shape = Enum.PartType.Cylinder
	end
end

return Geometry
