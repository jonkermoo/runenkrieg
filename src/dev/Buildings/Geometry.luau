--!strict
-- Building geometry primitives in the old-village / Pordier style: chunky, slightly hand-made.
-- Every part gets a "Paint" role (Wall, Roof, Trim, Door, DoorDark, Glass, Floor, Stairs, Foundation,
-- Quoin, Chimney, Metal, Wood) that Buildings.paint colors later, plus a "Tone" in [-1, 1] on walls,
-- roofs and doors so pieces sit a few % off each other.
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
	count: number, -- parts created (also seeds the deterministic tone/jitter)
}

export type Opening = { kind: string, w: number, bottom: number, top: number }

local TONED = { Wall = true, Roof = true, Door = true, DoorDark = true, Quoin = true, Foundation = true }

-- Deterministic pseudo-random in [-1, 1] from the part counter.
local function jitter(ctx: Ctx, salt: number): number
	local h = (ctx.count * 7919 + salt * 104729) % 2003
	return h / 1001.5 - 1
end
Geometry.jitter = jitter

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
	if TONED[paint] then
		p:SetAttribute("Tone", jitter(ctx, 3))
	end
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

-- Small deep-set window: glass recessed toward the inside, one chunky cross bar.
local function glass(parent: Instance, ctx: Ctx, frame: CFrame, c: number, o: Opening, story: number)
	local g = Geometry.section(parent, ctx, "Glass", "Glass", story)
	local w, h = o.w, o.top - o.bottom
	local mid = (o.bottom + o.top) / 2
	local z = ctx.T * 0.2 -- recessed
	local pane = Geometry.part(g, ctx, "Pane", frame * CFrame.new(c, mid, z), Vector3.new(w, h, 0.2), "Glass")
	pane.Transparency = 0.4
	pane.CastShadow = false
	Geometry.part(g, ctx, "Bar", frame * CFrame.new(c, mid, z - 0.15), Vector3.new(0.32, h, 0.2), "Trim")
	Geometry.part(g, ctx, "Bar", frame * CFrame.new(c, mid, z - 0.15), Vector3.new(w, 0.32, 0.2), "Trim")
end

-- Plank door: alternating plank tones, two battens, iron strap hinges, ring handle. Openable via the
-- server (src/server/Doors) about the Hinge attribute.
local function door(parent: Instance, ctx: Ctx, frame: CFrame, c: number, o: Opening, story: number)
	local d = Geometry.section(parent, ctx, "Door", "Door", story)
	CollectionService:AddTag(d, ctx.D.DoorTag)
	local w, h = o.w - 0.2, o.top - 0.1
	local planks = 3
	local pw = w / planks
	local left = c - w / 2
	local middle: BasePart? = nil
	for i = 1, planks do
		local px = left + (i - 0.5) * pw
		local p = Geometry.part(
			d,
			ctx,
			"Plank",
			frame * CFrame.new(px, h / 2 + 0.05, 0),
			Vector3.new(pw - 0.06, h - 0.1 * (i % 2), 0.4),
			if i % 2 == 0 then "DoorDark" else "Door"
		)
		if i == 2 then
			middle = p
		end
	end
	for _, y in { h * 0.25, h * 0.75 } do
		Geometry.part(d, ctx, "Batten", frame * CFrame.new(c, y, 0.3), Vector3.new(w - 0.3, 0.5, 0.2), "DoorDark")
		Geometry.part(
			d,
			ctx,
			"Strap",
			frame * CFrame.new(left + w * 0.3, y, -0.25),
			Vector3.new(w * 0.55, 0.22, 0.1),
			"Metal"
		)
	end
	local ring = Geometry.part(
		d,
		ctx,
		"Ring",
		frame * CFrame.new(left + w - 0.6, 3.6, -0.3) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(0.12, 0.6, 0.6),
		"Metal"
	)
	ring.Shape = Enum.PartType.Cylinder
	local panel = middle :: BasePart
	panel.Name = "Panel"
	d.PrimaryPart = panel
	-- hinge = the door's left edge, in the middle plank's space (the middle plank is centered on the door);
	-- an attribute rather than WorldPivot, which doesn't persist from Studio tool contexts
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
	sections: { any }, -- Rules/Openings.layout sections: { w, opening? }
	heights: { door: { number }, window: { number } } -- {bottom, top} per opening kind
)
	local L = 0
	for _, s in sections do
		L += s.w
	end
	local T = ctx.T
	local u0 = -L / 2
	for _, s in sections do
		local sw = s.w
		local sec = Geometry.section(parent, ctx, "Wall", ctx.class, story)
		local o: Opening? = if s.opening
			then {
				kind = s.opening.kind,
				w = s.opening.w,
				bottom = heights[s.opening.kind][1],
				top = heights[s.opening.kind][2],
			}
			else nil
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
			local w = o.w
			local c = u0 + sw / 2
			local oo: Opening = { kind = o.kind, w = w, bottom = o.bottom, top = math.min(o.top, H - 0.8) }
			box(u0, c - w / 2, 0, H)
			box(c + w / 2, u0 + sw, 0, H)
			box(c - w / 2, c + w / 2, 0, oo.bottom)
			box(c - w / 2, c + w / 2, oo.top, H)
			-- chunky timber frame on the outside face
			local f = -T / 2 - 0.15
			Geometry.part(
				sec,
				ctx,
				"Lintel",
				frame * CFrame.new(c, oo.top + 0.35, f),
				Vector3.new(w + 1.3, 0.7, 0.45),
				"Trim"
			)
			Geometry.part(
				sec,
				ctx,
				"Post",
				frame * CFrame.new(c - w / 2 - 0.25, (oo.bottom + oo.top) / 2, f),
				Vector3.new(0.5, oo.top - oo.bottom, 0.4),
				"Trim"
			)
			Geometry.part(
				sec,
				ctx,
				"Post",
				frame * CFrame.new(c + w / 2 + 0.25, (oo.bottom + oo.top) / 2, f),
				Vector3.new(0.5, oo.top - oo.bottom, 0.4),
				"Trim"
			)
			if oo.kind == "door" then
				Geometry.part(
					sec,
					ctx,
					"Doorstep",
					frame * CFrame.new(c, 0.2, -T / 2 - 0.6),
					Vector3.new(w + 1.6, 0.4, 1.2),
					"Foundation"
				)
				door(sec, ctx, frame, c, oo, story)
			else
				Geometry.part(
					sec,
					ctx,
					"Sill",
					frame * CFrame.new(c, oo.bottom - 0.25, -T / 2 - 0.35),
					Vector3.new(w + 1.1, 0.5, 0.9),
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

-- Gabled roof, ridge along local X. "Thatch": thick panels with slightly uneven thickness and tilt,
-- a rounded ridge roll and rounded eave rolls. "Tile": thin panels + ridge cap.
-- Returns the ridge height above wallTop.
function Geometry.roof(
	parent: Instance,
	ctx: Ctx,
	cf: CFrame,
	W: number,
	Dp: number,
	wallTop: number,
	pitch: number,
	style: string?
)
	local thatch = style == "Thatch"
	local class = if thatch then "Thatch" else "Tile"
	local t = math.rad(pitch)
	local ov = if thatch then ctx.B.RoofOverhang + 0.6 else ctx.B.RoofOverhang
	local th = if thatch then 2.2 else 0.8
	local gableOv = if thatch then 1.4 else ctx.B.RoofOverhang
	local h = (Dp / 2) * math.tan(t)
	local hd = Dp / 2 + ov
	local sl = hd / math.cos(t)
	local len = W + 2 * gableOv
	local n = math.max(1, math.ceil(len / 7))
	for _, side in { -1, 1 } do
		-- panel center on the roof plane, pushed out along the normal so the underside sits on the plane
		local zc = side * hd / 2
		local yc = wallTop + h - (hd / 2) * math.tan(t)
		local normal = Vector3.new(0, math.cos(t), side * math.sin(t))
		for i = 0, n - 1 do
			local sec = Geometry.section(parent, ctx, "Roof", class, 99)
			local xc = -len / 2 + (i + 0.5) * len / n
			local thick = th * (1 + 0.08 * jitter(ctx, 5))
			local tilt = if thatch then math.rad(0.6 * jitter(ctx, 7)) else 0
			local pos = Vector3.new(xc, yc, zc) + normal * (thick / 2)
			Geometry.part(
				sec,
				ctx,
				"Roof",
				cf * CFrame.new(pos) * CFrame.Angles(side * t + tilt, 0, 0),
				Vector3.new(len / n + 0.04, thick, sl),
				"Roof"
			)
		end
	end
	local cap = Geometry.section(parent, ctx, "Roof", class, 99)
	if thatch then
		local ridge = Geometry.part(
			cap,
			ctx,
			"RidgeRoll",
			cf * CFrame.new(0, wallTop + h + th * 0.75, 0),
			Vector3.new(len + 0.4, 3, 3),
			"Roof"
		)
		ridge.Shape = Enum.PartType.Cylinder
		for _, side in { -1, 1 } do
			local eaveY = wallTop + h - hd * math.tan(t) + th * 0.45
			local roll = Geometry.part(
				cap,
				ctx,
				"EaveRoll",
				cf * CFrame.new(0, eaveY, side * (hd - 0.2)),
				Vector3.new(len, th * 1.15, th * 1.15),
				"Roof"
			)
			roll.Shape = Enum.PartType.Cylinder
		end
	else
		Geometry.part(
			cap,
			ctx,
			"Ridge",
			cf * CFrame.new(0, wallTop + h + 0.75, 0) * CFrame.Angles(math.pi / 4, 0, 0),
			Vector3.new(len, 1, 1),
			"Roof"
		)
	end
	return h
end

-- Chimney through the roof (tile houses).
function Geometry.chimney(parent: Instance, ctx: Ctx, cf: CFrame, x: number, z: number, y0: number, y1: number)
	local sec = Geometry.section(parent, ctx, "Chimney", "Brick", 99)
	Geometry.part(sec, ctx, "Stack", cf * CFrame.new(x, (y0 + y1) / 2, z), Vector3.new(2.8, y1 - y0, 2.4), "Chimney")
	Geometry.part(sec, ctx, "Cap", cf * CFrame.new(x, y1 + 0.2, z), Vector3.new(3.2, 0.4, 2.8), "Chimney")
end

-- External chimney breast against a gable end (old cottages): wide base up the wall, narrower stack
-- above the ridge, chunky cap and pots. side = -1 (-X gable) or +1.
function Geometry.gableChimney(
	parent: Instance,
	ctx: Ctx,
	side: number,
	W: number,
	groundY: number,
	wallTop: number,
	ridgeTop: number
)
	local sec = Geometry.section(parent, ctx, "Chimney", "Brick", 0)
	local x = side * (W / 2 + 1.1)
	local breastTop = wallTop + 1.5
	Geometry.part(
		sec,
		ctx,
		"Breast",
		CFrame.new(x, (groundY + breastTop) / 2, 0),
		Vector3.new(2.2, breastTop - groundY, 4.2),
		"Chimney"
	)
	-- sloped shoulder from the breast to the stack
	Geometry.part(sec, ctx, "Shoulder", CFrame.new(x, breastTop + 0.6, 0), Vector3.new(2.2, 1.2, 3.4), "Chimney")
	local top = ridgeTop + 3
	Geometry.part(
		sec,
		ctx,
		"Stack",
		CFrame.new(x, (breastTop + top) / 2 + 0.6, 0),
		Vector3.new(2.2, top - breastTop, 2.8),
		"Chimney"
	)
	Geometry.part(sec, ctx, "Cap", CFrame.new(x, top + 0.8, 0), Vector3.new(2.8, 0.5, 3.4), "Chimney")
	for _, dz in { -0.7, 0.7 } do
		local pot = Geometry.part(
			sec,
			ctx,
			"Pot",
			CFrame.new(x, top + 1.6, dz) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(1.3, 0.9, 0.9),
			"Chimney"
		)
		pot.Shape = Enum.PartType.Cylinder
	end
end

-- Stone corner blocks, alternating long/short up each corner.
function Geometry.quoins(parent: Instance, ctx: Ctx, W: number, Dp: number, y0: number, y1: number)
	local sec = Geometry.section(parent, ctx, "Quoins", "Stone", 0)
	local q = ctx.B.Quoin
	local block = q.block
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local k = 0
		local y = y0
		while y + block <= y1 + 0.01 do
			local long = k % 2 == 0
			local sx = if long then q.long else q.short
			local sz = if long then q.short else q.long
			local px = c[1] * (W / 2 - sx / 2 + 0.25)
			local pz = c[2] * (Dp / 2 - sz / 2 + 0.25)
			Geometry.part(
				sec,
				ctx,
				"Quoin",
				CFrame.new(px, y + block / 2, pz),
				Vector3.new(sx, block - 0.12, sz),
				"Quoin"
			)
			y += block
			k += 1
		end
	end
end

-- Stone plinth band around the outside of the walls (not inside: it would poke through the floor).
function Geometry.plinth(parent: Instance, ctx: Ctx, W: number, Dp: number, yTop: number)
	local o, h = 0.45, yTop + 1.5
	local y = yTop - h / 2
	Geometry.part(parent, ctx, "Plinth", CFrame.new(0, y, -Dp / 2 - o / 2), Vector3.new(W + 2 * o, h, o), "Foundation")
	Geometry.part(parent, ctx, "Plinth", CFrame.new(0, y, Dp / 2 + o / 2), Vector3.new(W + 2 * o, h, o), "Foundation")
	Geometry.part(parent, ctx, "Plinth", CFrame.new(-W / 2 - o / 2, y, 0), Vector3.new(o, h, Dp), "Foundation")
	Geometry.part(parent, ctx, "Plinth", CFrame.new(W / 2 + o / 2, y, 0), Vector3.new(o, h, Dp), "Foundation")
end

return Geometry
