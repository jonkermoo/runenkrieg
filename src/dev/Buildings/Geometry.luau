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
	-- a landmark block's own wall / roof colour (Palette.Buildings.Walls / Roofs keys), over the copy's scheme
	wallKey: string?,
	roofKey: string?,
}

export type Opening = { kind: string, w: number, bottom: number, top: number }

local TONED = {
	Wall = true,
	Roof = true,
	Door = true,
	DoorDark = true,
	Quoin = true,
	Foundation = true,
	Cloth = true,
	Hay = true,
}

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
	if paint == "Wall" and ctx.wallKey then
		p:SetAttribute("Swatch", ctx.wallKey)
	elseif paint == "Roof" and ctx.roofKey then
		p:SetAttribute("Swatch", ctx.roofKey)
	end
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
	prompt.Style = Enum.ProximityPromptStyle.Custom -- the game's own look; src/server/Doors sets its reach and tag
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
				top = s.opening.h or heights[s.opening.kind][2],
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

-- Straight stair along the back wall (or the front, `front`: a tower's flights alternate so each lands clear of the
-- next), ascending toward +X. Returns the hole rect for the floor above.
function Geometry.stairs(
	parent: Instance,
	ctx: Ctx,
	cf: CFrame,
	W: number,
	Dp: number,
	baseY: number,
	H: number,
	story: number,
	front: boolean?
): { number }
	local Bm = ctx.M.Building
	local steps = math.ceil(H / Bm.StairRise)
	local rise = H / steps
	local x0 = -W / 2 + ctx.T
	local z1 = Dp / 2 - ctx.T
	local z0 = z1 - Bm.StairWidthMin
	if front then
		z0 = -Dp / 2 + ctx.T
		z1 = z0 + Bm.StairWidthMin
	end
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

-- A flat roof walk's parapet (a church tower): a low wall on the wall tops all round, merlons along it with gaps to
-- shoot through. `top` = the roof walk's floor.
function Geometry.battlement(parent: Instance, ctx: Ctx, W: number, Dp: number, top: number)
	local q = ctx.B.Battlement
	local T = ctx.T
	local runs = {
		{ CFrame.new(0, 0, -Dp / 2 + T / 2), W },
		{ CFrame.new(0, 0, Dp / 2 - T / 2), W },
		{ CFrame.new(-W / 2 + T / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Dp - 2 * T },
		{ CFrame.new(W / 2 - T / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), Dp - 2 * T },
	}
	for _, r in runs do
		local sec = Geometry.section(parent, ctx, "Parapet", ctx.class, 99)
		local frame, L = r[1], r[2]
		Geometry.part(
			sec,
			ctx,
			"Parapet",
			frame * CFrame.new(0, top + q.wall / 2, 0),
			Vector3.new(L, q.wall, T),
			"Wall"
		)
		-- an odd count, so both ends carry a merlon
		local n = math.max(3, math.floor(L / q.merlon / 2) * 2 + 1)
		for i = 0, n - 1, 2 do
			Geometry.part(
				sec,
				ctx,
				"Merlon",
				frame * CFrame.new(-L / 2 + (i + 0.5) * L / n, top + q.wall + q.height / 2, 0),
				Vector3.new(L / n, q.height, T + 0.2),
				"Wall"
			)
		end
	end
end

-- A row of headstones (a churchyard), `count` of them `gap` apart along local X from `at`, each a little off true.
function Geometry.graves(parent: Instance, ctx: Ctx, at: CFrame, count: number, gap: number)
	local g = ctx.B.Graves
	for i = 0, count - 1 do
		local sec = Geometry.section(parent, ctx, "Grave", "Stone", 0)
		sec:SetAttribute("OnGround", true) -- set on the real ground where it's placed, not the building's level
		local tilt = math.rad(4 * jitter(ctx, 11))
		local h = g.height * (1 + 0.15 * jitter(ctx, 13))
		Geometry.part(
			sec,
			ctx,
			"Headstone",
			at * CFrame.new(i * gap, h / 2 - g.sink, 0) * CFrame.Angles(tilt, 0, 0),
			Vector3.new(g.width, h + g.sink, g.thick),
			"Quoin"
		)
	end
end

-- A roofed gateway (a lychgate): four oak posts, a tiled gable roof on them, open front to back along local Z.
function Geometry.lychgate(parent: Instance, ctx: Ctx, at: CFrame, W: number)
	local L = ctx.B.Lychgate
	local sec = Geometry.section(parent, ctx, "Lychgate", "Wood", 0)
	sec:SetAttribute("OnGround", true)
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		Geometry.part(
			sec,
			ctx,
			"Post",
			at * CFrame.new(c[1] * (W / 2 - 0.4), L.height / 2, c[2] * (L.depth / 2 - 0.4)),
			Vector3.new(0.8, L.height, 0.8),
			"Trim"
		)
	end
	for _, side in { -1, 1 } do
		Geometry.part(
			sec,
			ctx,
			"Beam",
			at * CFrame.new(side * (W / 2 - 0.4), L.height - 0.35, 0),
			Vector3.new(0.8, 0.7, L.depth),
			"Trim"
		)
	end
	-- the roof runs across the gateway, ridge along local X
	Geometry.roof(sec, ctx, at, W, L.depth, L.height, L.pitch, "Tile")
end

-- An upright triangle in `frame`'s XY plane (base `L` along X at y 0, tip `h` up), `thick` through: two wedges, as a
-- gable is made.
local function triangle(sec: Instance, ctx: Ctx, frame: CFrame, L: number, h: number, thick: number, paint: string)
	local out = {}
	for _, side in { -1, 1 } do
		table.insert(
			out,
			Geometry.part(
				sec,
				ctx,
				"Face",
				frame * CFrame.new(side * L / 4, h / 2, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
				Vector3.new(thick, h, L / 2),
				paint,
				"WedgePart"
			)
		)
	end
	return out
end

-- A round oast kiln (a hop kiln): an eight-sided brick drum `height` high on a foundation, a steep eight-sided cone
-- `cone` high on it, and a white cowl on the tip. Its own colours (Swatch), whatever the copy's scheme.
function Geometry.kiln(parent: Instance, ctx: Ctx, at: CFrame, r: number, height: number, cone: number)
	local K = ctx.B.Kiln
	local T = ctx.T
	local side = 2 * r * math.tan(math.pi / 8)
	local base = ctx.B.Foundation
	local depth = ctx.B.FoundationDepth
	Geometry.part(
		parent,
		ctx,
		"Foundation",
		at * CFrame.new(0, (base - 1 - depth) / 2, 0),
		Vector3.new(2 * r, base - 1 + depth, 2 * r),
		"Foundation"
	)
	for i = 0, 7 do
		local sec = Geometry.section(parent, ctx, "Kiln", "Brick", 0)
		local face = at * CFrame.Angles(0, i * math.pi / 4, 0)
		local p = Geometry.part(
			sec,
			ctx,
			"Drum",
			face * CFrame.new(0, (base - 1 + height) / 2, -(r - T / 2)),
			Vector3.new(side + T * 0.85, height - base + 1, T),
			"Wall"
		)
		p:SetAttribute("Swatch", K.wall)
	end
	local top = height
	local phi = math.atan(r / cone)
	local slant = math.sqrt(r * r + cone * cone)
	for i = 0, 7 do
		local sec = Geometry.section(parent, ctx, "Roof", "Tile", 99)
		local frame = at * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, top, -r) * CFrame.Angles(phi, 0, 0)
		for _, p in triangle(sec, ctx, frame, side * 1.06, slant, 0.8, "Roof") do
			p:SetAttribute("Swatch", K.roof)
		end
	end
	local cowl = Geometry.section(parent, ctx, "Cowl", "Wood", 99)
	local c = K.cowl
	local tip = at * CFrame.new(0, top + cone - 0.6, 0)
	local box =
		Geometry.part(cowl, ctx, "Cowl", tip * CFrame.new(0, c[2] / 2, 0), Vector3.new(c[1], c[2], c[1]), "Wall")
	box:SetAttribute("Swatch", K.cowlWall)
	local hood = Geometry.part(
		cowl,
		ctx,
		"Hood",
		tip * CFrame.new(0, c[2] + 0.6, 0.2),
		Vector3.new(c[1] + 0.4, 1.2, c[1] + 0.8),
		"Wall",
		"WedgePart"
	)
	hood:SetAttribute("Swatch", K.cowlWall)
end

-- An open-sided Dutch hay barn: posts round a `L` x `span` bay, a curved rust-red roof on them (flat panels along an
-- arc, ridge along local X), hay stacked inside to different heights.
function Geometry.hayBarn(parent: Instance, ctx: Ctx, at: CFrame, L: number, span: number, height: number)
	local H = ctx.B.HayBarn
	local half = span / 2 + H.overhang
	local R = (half * half + H.rise * H.rise) / (2 * H.rise)
	local cy = height + H.rise - R
	local function roofY(z: number): number
		return cy + math.sqrt(R * R - z * z)
	end
	local bays = math.max(1, math.round(L / H.bay))
	for i = 0, bays do
		local x = -L / 2 + i * L / bays
		for _, sz in { -1, 1 } do
			local z = sz * (span / 2 - 0.5)
			local top = roofY(z)
			local sec = Geometry.section(parent, ctx, "Post", "Wood", 0)
			Geometry.part(sec, ctx, "Post", at * CFrame.new(x, top / 2, z), Vector3.new(1, top, 1), "Trim")
		end
		local beam = Geometry.section(parent, ctx, "Beam", "Wood", 0)
		Geometry.part(beam, ctx, "Beam", at * CFrame.new(x, height - 0.4, 0), Vector3.new(0.7, 0.7, span), "Trim")
	end
	local a0 = math.asin(half / R)
	local n = H.segments * 2
	for k = 0, n - 1 do
		local t0, t1 = -a0 + 2 * a0 * k / n, -a0 + 2 * a0 * (k + 1) / n
		local z0, y0 = R * math.sin(t0), cy + R * math.cos(t0)
		local z1, y1 = R * math.sin(t1), cy + R * math.cos(t1)
		local len = math.sqrt((z1 - z0) ^ 2 + (y1 - y0) ^ 2)
		local slope = math.atan2(y1 - y0, z1 - z0)
		local sec = Geometry.section(parent, ctx, "Roof", "Tile", 99)
		local p = Geometry.part(
			sec,
			ctx,
			"Roof",
			at * CFrame.new(0, (y0 + y1) / 2 + 0.25, (z0 + z1) / 2) * CFrame.Angles(-slope, 0, 0),
			Vector3.new(L + 2 * H.overhang, 0.5, len + 0.08),
			"Roof"
		)
		p:SetAttribute("Swatch", H.roof)
	end
	-- the hay: one stack per bay, a few bales' worth each (some bays near empty)
	for i = 0, bays - 1 do
		local h = H.hay[i % #H.hay + 1]
		local x = -L / 2 + (i + 0.5) * L / bays
		local sec = Geometry.section(parent, ctx, "Hay", "Thatch", 0)
		local p = Geometry.part(
			sec,
			ctx,
			"Hay",
			at * CFrame.new(x, h / 2, 0),
			Vector3.new(L / bays - 1.4, h, span - 3),
			"Roof"
		)
		p:SetAttribute("Swatch", H.hayRoof)
	end
end

-- A dry-stone yard wall from `a` to `b` ({x, z} in the template's footprint), in pieces no longer than `piece`, each
-- standing on the real ground where it is (a wall over a slope steps down it).
function Geometry.yardWall(
	parent: Instance,
	ctx: Ctx,
	a: { number },
	b: { number },
	height: number?,
	thick: number?,
	swatch: string?
)
	local Y = table.clone(ctx.B.YardWall)
	Y.height, Y.thick = height or Y.height, thick or Y.thick
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.ceil(len / Y.piece))
	local yaw = math.atan2(-dz, dx)
	for i = 0, n - 1 do
		local t = (i + 0.5) / n
		local sec = Geometry.section(parent, ctx, "YardWall", "Stone", 0)
		sec:SetAttribute("OnGround", true)
		local p = Geometry.part(
			sec,
			ctx,
			"Wall",
			CFrame.new(a[1] + dx * t, Y.height / 2 - Y.sink, a[2] + dz * t) * CFrame.Angles(0, yaw, 0),
			Vector3.new(len / n + 0.1, Y.height + Y.sink, Y.thick),
			if swatch then "Wall" else "Quoin"
		)
		if swatch then
			p:SetAttribute("Swatch", swatch)
		end
	end
end

-- A brickworks' bottle kiln: an eight-sided brick drum `height` high, `r` across at its foot, narrowing through
-- `ctx.B.BottleKiln.tiers` shoulders to a chimney neck on top; an arched opening (a dark panel) at its foot on -Z.
-- Its own colours (Swatch). Solid: nobody climbs it.
function Geometry.bottleKiln(parent: Instance, ctx: Ctx, at: CFrame, r: number, height: number)
	local K = ctx.B.BottleKiln
	local T = ctx.T
	local base = ctx.B.Foundation
	local depth = ctx.B.FoundationDepth
	Geometry.part(
		parent,
		ctx,
		"Foundation",
		at * CFrame.new(0, (base - 1 - depth) / 2, 0),
		Vector3.new(2 * r, base - 1 + depth, 2 * r),
		"Foundation"
	)
	-- the drum, then each shoulder a step in and up, then the neck
	local rings = { { r, 0, height * K.drum } }
	local y = height * K.drum
	local per = height * (1 - K.drum - K.neck) / K.tiers
	for k = 1, K.tiers do
		local rk = r * (1 - (1 - K.neckRadius) * k / K.tiers)
		table.insert(rings, { rk, y, y + per })
		y += per
	end
	table.insert(rings, { r * K.neckRadius, y, height })
	for _, ring in rings do
		local rr, y0, y1 = ring[1], ring[2], ring[3]
		local side = 2 * rr * math.tan(math.pi / 8)
		for i = 0, 7 do
			local sec = Geometry.section(parent, ctx, "Kiln", "Brick", 0)
			local face = at * CFrame.Angles(0, i * math.pi / 4, 0)
			local p = Geometry.part(
				sec,
				ctx,
				"Drum",
				face * CFrame.new(0, (y0 + y1) / 2, -(rr - T / 2)),
				Vector3.new(side + T * 0.85, y1 - y0, T),
				"Wall"
			)
			p:SetAttribute("Swatch", K.wall)
		end
		-- a solid core so the shell reads closed from above and blocks shots through its middle
		local core = Geometry.section(parent, ctx, "Kiln", "Brick", 0)
		local c = Geometry.part(
			core,
			ctx,
			"Core",
			at * CFrame.new(0, (y0 + y1) / 2, 0),
			Vector3.new(2 * (rr - T), y1 - y0, 2 * (rr - T)),
			"Wall"
		)
		c:SetAttribute("Swatch", K.wall)
	end
	local mouth = Geometry.part(
		parent,
		ctx,
		"Mouth",
		at * CFrame.new(0, K.mouth[2] / 2, -r - 0.05),
		Vector3.new(K.mouth[1], K.mouth[2], 0.2),
		"Wall"
	)
	mouth:SetAttribute("Swatch", K.dark)
end

-- Map 1's beacon (Config/Buildings.Beacon): a square stone pier, an iron basket of rods on a plate on top, its fire.
-- Too tall and sheer to climb; one wall section, so shells knock it down like a wall.
function Geometry.beacon(parent: Instance, ctx: Ctx, at: CFrame)
	local K = ctx.B.Beacon
	local base = ctx.B.Foundation
	local depth = ctx.B.FoundationDepth
	Geometry.part(
		parent,
		ctx,
		"Foundation",
		at * CFrame.new(0, (base - 1 - depth) / 2, 0),
		Vector3.new(K.pier + 1, base - 1 + depth, K.pier + 1),
		"Foundation"
	)
	local sec = Geometry.section(parent, ctx, "Beacon", "Stone", 0)
	local pier = Geometry.part(
		sec,
		ctx,
		"Pier",
		at * CFrame.new(0, K.height / 2, 0),
		Vector3.new(K.pier, K.height, K.pier),
		"Wall"
	)
	pier:SetAttribute("Swatch", K.wall)
	local top = at * CFrame.new(0, K.height, 0)
	local plate =
		Geometry.part(sec, ctx, "Plate", top * CFrame.new(0, 0.2, 0), Vector3.new(K.basket, 0.4, K.basket), "Wall")
	plate:SetAttribute("Swatch", K.iron)
	local r = K.basket / 2 - 0.2
	for i = 0, K.rods - 1 do
		local a = i * 2 * math.pi / K.rods
		local rod = Geometry.part(
			sec,
			ctx,
			"Rod",
			top * CFrame.new(math.cos(a) * r, 0.4 + K.cage / 2, math.sin(a) * r),
			Vector3.new(0.3, K.cage, 0.3),
			"Wall"
		)
		rod:SetAttribute("Swatch", K.iron)
	end
	local ring = Geometry.part(
		sec,
		ctx,
		"Ring",
		top * CFrame.new(0, 0.4 + K.cage, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Vector3.new(0.3, K.basket, K.basket),
		"Wall",
		"Part"
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.9
	ring:SetAttribute("Swatch", K.iron)
	local fire = Geometry.part(
		sec,
		ctx,
		"Fire",
		top * CFrame.new(0, 0.4 + K.cage * 0.45, 0),
		Vector3.new(K.basket * 0.7, K.cage * 0.9, K.basket * 0.7),
		"Festival"
	)
	fire.Material = Enum.Material.Neon
	fire.CanCollide = false
	fire:SetAttribute("Swatch", K.fire)
end

-- A wooden waterwheel in `at`'s XY plane (its axle along local Z, into the wall behind it): a rim of `n` straight
-- pieces, spokes across, a paddle board at every rim joint `width` wide, and the axle. Not turning (a static prop).
function Geometry.waterwheel(parent: Instance, ctx: Ctx, at: CFrame, r: number, width: number)
	local Wh = ctx.B.Waterwheel
	local n = Wh.pieces
	local chord = 2 * r * math.sin(math.pi / n)
	local sec = Geometry.section(parent, ctx, "Waterwheel", "Wood", 0)
	for _, face in { -width / 2 + 0.3, width / 2 - 0.3 } do
		for i = 0, n - 1 do
			local a = (i + 0.5) * 2 * math.pi / n
			Geometry.part(
				sec,
				ctx,
				"Rim",
				at * CFrame.new(0, 0, face) * CFrame.Angles(0, 0, a) * CFrame.new(0, r * math.cos(math.pi / n), 0),
				Vector3.new(chord + 0.1, 0.6, 0.5),
				"Trim"
			)
		end
		for i = 0, Wh.spokes - 1 do
			Geometry.part(
				sec,
				ctx,
				"Spoke",
				at * CFrame.new(0, 0, face) * CFrame.Angles(0, 0, i * math.pi / Wh.spokes),
				Vector3.new(2 * r - 0.6, 0.45, 0.45),
				"Wood"
			)
		end
	end
	for i = 0, n - 1 do
		Geometry.part(
			sec,
			ctx,
			"Paddle",
			at * CFrame.Angles(0, 0, i * 2 * math.pi / n) * CFrame.new(0, r + Wh.paddle / 2 - 0.3, 0),
			Vector3.new(0.35, Wh.paddle, width),
			"Wood"
		)
	end
	local axle = Geometry.part(
		sec,
		ctx,
		"Axle",
		at * CFrame.new(0, 0, Wh.axle / 2 - width / 2) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(Wh.axle, 1.2, 1.2),
		"Metal"
	)
	axle.Shape = Enum.PartType.Cylinder
end

-- A station canopy over a platform, `L` long (local X), reaching `D` out from the wall behind it (local +Z): posts
-- along its front edge, a beam on them, a lean-to roof rising to the wall, a white valance board along the front.
function Geometry.canopy(parent: Instance, ctx: Ctx, at: CFrame, L: number, D: number, H: number)
	local C = ctx.B.Canopy
	local n = math.max(1, math.round(L / C.posts))
	for i = 0, n do
		local sec = Geometry.section(parent, ctx, "Post", "Wood", 0)
		Geometry.part(
			sec,
			ctx,
			"Post",
			at * CFrame.new(-L / 2 + i * L / n, H / 2, -D / 2 + 0.5),
			Vector3.new(0.7, H, 0.7),
			"Trim"
		)
	end
	local roof = Geometry.section(parent, ctx, "Roof", "Tile", 99)
	Geometry.part(roof, ctx, "Beam", at * CFrame.new(0, H - 0.35, -D / 2 + 0.5), Vector3.new(L + 0.6, 0.7, 0.7), "Trim")
	local tilt = math.atan(C.rise / D)
	local panel = Geometry.part(
		roof,
		ctx,
		"Roof",
		at * CFrame.new(0, H + C.rise / 2 + 0.2, 0) * CFrame.Angles(-tilt, 0, 0),
		Vector3.new(L + 1, 0.4, D / math.cos(tilt) + 0.6),
		"Roof"
	)
	panel:SetAttribute("Swatch", C.roof)
	local valance = Geometry.part(
		roof,
		ctx,
		"Valance",
		at * CFrame.new(0, H - 0.1, -D / 2 - 0.25),
		Vector3.new(L + 1, 1.2, 0.2),
		"Wall"
	)
	valance:SetAttribute("Swatch", C.valance)
end

-- A station platform: a stone slab `L` x `D`, its top `h` over the base, a coping edge along its front (local -Z). It
-- goes down into the ground under it (the ground slab: never collapses).
function Geometry.platform(parent: Instance, ctx: Ctx, at: CFrame, L: number, D: number, h: number)
	local depth = ctx.B.FoundationDepth
	local sec = Geometry.section(parent, ctx, "Platform", "Stone", -1)
	Geometry.part(
		sec,
		ctx,
		"Platform",
		at * CFrame.new(0, (h - depth) / 2, 0),
		Vector3.new(L, h + depth, D),
		"Foundation"
	)
	Geometry.part(sec, ctx, "Coping", at * CFrame.new(0, h + 0.1, -D / 2 + 0.6), Vector3.new(L, 0.3, 1.4), "Quoin")
end

-- A railway water tower: four legs `H` high under a square tarred tank `s` across, a lid, and a spout arm toward the
-- track (local -Z).
function Geometry.waterTower(parent: Instance, ctx: Ctx, at: CFrame, s: number, H: number)
	local W = ctx.B.WaterTower
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local sec = Geometry.section(parent, ctx, "Leg", "Wood", 0)
		Geometry.part(
			sec,
			ctx,
			"Leg",
			at * CFrame.new(c[1] * (s / 2 - 0.5), H / 2, c[2] * (s / 2 - 0.5)),
			Vector3.new(0.9, H, 0.9),
			"Trim"
		)
	end
	local tank = Geometry.section(parent, ctx, "Tank", "Wood", 99)
	local box = Geometry.part(tank, ctx, "Tank", at * CFrame.new(0, H + s * 0.4, 0), Vector3.new(s, s * 0.8, s), "Wall")
	box:SetAttribute("Swatch", W.tank)
	Geometry.part(
		tank,
		ctx,
		"Lid",
		at * CFrame.new(0, H + s * 0.8 + 0.2, 0),
		Vector3.new(s + 0.6, 0.4, s + 0.6),
		"Trim"
	)
	Geometry.part(
		tank,
		ctx,
		"Spout",
		at * CFrame.new(0, H + 0.6, -s / 2 - W.spout / 2),
		Vector3.new(0.8, 0.8, W.spout),
		"Metal"
	)
end

-- A railway signal: a white post `H` high, a red arm off its top along local X, a lamp, a cap.
function Geometry.signal(parent: Instance, ctx: Ctx, at: CFrame, H: number)
	local S = ctx.B.Signal
	local sec = Geometry.section(parent, ctx, "Signal", "Wood", 0)
	sec:SetAttribute("OnGround", true)
	local post = Geometry.part(sec, ctx, "Post", at * CFrame.new(0, H / 2, 0), Vector3.new(0.6, H, 0.6), "Wall")
	post:SetAttribute("Swatch", S.post)
	local arm = Geometry.part(
		sec,
		ctx,
		"Arm",
		at * CFrame.new(S.arm / 2 + 0.3, H - 1.4, -0.4),
		Vector3.new(S.arm, 0.6, 0.2),
		"Roof"
	)
	arm:SetAttribute("Swatch", S.armRoof)
	Geometry.part(sec, ctx, "Lamp", at * CFrame.new(0, H - 2.6, -0.5), Vector3.new(0.7, 0.9, 0.5), "Metal")
	Geometry.part(sec, ctx, "Cap", at * CFrame.new(0, H + 0.25, 0), Vector3.new(0.9, 0.5, 0.9), "Metal")
end

-- A festival piece (Palette.Buildings.Festival `key`: canvas, rune paint, a paper lantern).
local function festival(sec: Instance, ctx: Ctx, name: string, cf: CFrame, size: Vector3, key: string): BasePart
	local p = Geometry.part(sec, ctx, name, cf, size, "Festival")
	p:SetAttribute("Swatch", key)
	return p
end

-- A paper lantern on a cord, hanging from `y` (its top) at x, z in `at`; soldiers walk through it.
local function lantern(sec: Instance, ctx: Ctx, at: CFrame, x: number, y: number, z: number)
	for _, p in
		{
			Geometry.part(sec, ctx, "Cord", at * CFrame.new(x, y - 0.4, z), Vector3.new(0.12, 0.8, 0.12), "Metal"),
			Geometry.part(sec, ctx, "Cap", at * CFrame.new(x, y - 0.9, z), Vector3.new(1, 0.2, 1), "Metal"),
			festival(sec, ctx, "Lantern", at * CFrame.new(x, y - 1.6, z), Vector3.new(0.9, 1.2, 0.9), "Lantern"),
		}
	do
		p.CanCollide = false
	end
end

-- A festival stage, `W` across (local X) and `Dp` deep, its front -Z: a stone plinth whose wooden deck is `h` up, steps
-- up to it at the middle of its front and back (the lowest of each a Doorstep: VillageBuild adds steps down a bank),
-- timber posts `H` over the deck at its corners, a canvas backdrop between the back ones, a painted board with a rune
-- circle across the front ones, lanterns hanging under it and a striped canvas awning rising to the back.
function Geometry.stage(parent: Instance, ctx: Ctx, at: CFrame, W: number, Dp: number, h: number, H: number)
	local S = ctx.B.Stage
	local depth = ctx.B.FoundationDepth
	local plinth = Geometry.section(parent, ctx, "Platform", "Stone", -1)
	Geometry.part(
		plinth,
		ctx,
		"Plinth",
		at * CFrame.new(0, (h - 0.3 - depth) / 2, 0),
		Vector3.new(W, h - 0.3 + depth, Dp),
		"Foundation"
	)
	Geometry.part(
		plinth,
		ctx,
		"Coping",
		at * CFrame.new(0, h - 0.45, -Dp / 2 + 0.4),
		Vector3.new(W + 0.3, 0.3, 1),
		"Quoin"
	)
	local deck = Geometry.section(parent, ctx, "Deck", "Wood", 0)
	Geometry.part(deck, ctx, "Deck", at * CFrame.new(0, h - 0.15, 0), Vector3.new(W - 0.4, 0.3, Dp - 0.4), "Floor")
	-- steps: each solid down into the ground, the lowest of each flight turned outward and named Doorstep
	local St = S.step
	local n = math.max(1, math.ceil(h / St.rise) - 1)
	for _, side in { -1, 1 } do
		local sec = Geometry.section(parent, ctx, "Steps", "Stone", -1)
		for i = 1, n do
			local top = h - i * St.rise
			local z = side * (Dp / 2 + (i - 0.5) * St.run)
			local cf = at * CFrame.new(0, (top - depth) / 2, z) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
			local name = if i == n then "Doorstep" else "Step"
			Geometry.part(sec, ctx, name, cf, Vector3.new(St.width, top + depth, St.run), "Quoin")
		end
	end
	-- posts at the corners
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local sec = Geometry.section(parent, ctx, "Post", "Wood", 0)
		Geometry.part(
			sec,
			ctx,
			"Post",
			at * CFrame.new(c[1] * (W / 2 - 0.8), h + H / 2, c[2] * (Dp / 2 - 0.8)),
			Vector3.new(0.9, H, 0.9),
			"Trim"
		)
	end
	local back = Geometry.section(parent, ctx, "Backdrop", "Wood", 0)
	festival(
		back,
		ctx,
		"Backdrop",
		at * CFrame.new(0, h + (H - 0.5) / 2, Dp / 2 - 0.8),
		Vector3.new(W - 1.6, H - 0.5, 0.3),
		"Canvas"
	)
	-- the painted board over the front: rune-blue edges, a lantern-gold circle in a blue ring, brackets under its ends
	local board = Geometry.section(parent, ctx, "Board", "Wood", 99)
	local bz = -Dp / 2 + 0.35
	local by = h + H - S.board / 2
	Geometry.part(board, ctx, "Board", at * CFrame.new(0, by, bz), Vector3.new(W + 0.4, S.board, 0.5), "Wall")
	for _, dy in { -1, 1 } do
		festival(
			board,
			ctx,
			"Edge",
			at * CFrame.new(0, by + dy * (S.board / 2 - 0.175), bz - 0.3),
			Vector3.new(W + 0.6, 0.35, 0.2),
			"RunePaint"
		)
	end
	for _, dx in { -1, 1 } do
		festival(
			board,
			ctx,
			"Edge",
			at * CFrame.new(dx * (W / 2 + 0.1), by, bz - 0.3),
			Vector3.new(0.35, S.board, 0.2),
			"RunePaint"
		)
		Geometry.part(
			board,
			ctx,
			"Bracket",
			at
				* CFrame.new(dx * (W / 2 - 2.3), by - S.board / 2 - 0.9, bz + 0.4)
				* CFrame.Angles(0, 0, math.rad(dx * 40)),
			Vector3.new(3.2, 0.5, 0.4),
			"Wall"
		)
	end
	local disc = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis (X) turned to face the front
	local ring =
		festival(board, ctx, "Ring", at * CFrame.new(0, by, bz - 0.35) * disc, Vector3.new(0.2, 3, 3), "RunePaint")
	ring.Shape = Enum.PartType.Cylinder
	local sun =
		festival(board, ctx, "Rune", at * CFrame.new(0, by, bz - 0.45) * disc, Vector3.new(0.2, 2.3, 2.3), "Lantern")
	sun.Shape = Enum.PartType.Cylinder
	-- lanterns hanging under the board between the front posts
	local lanterns = Geometry.section(parent, ctx, "Lanterns", "Wood", 99)
	for i = 1, S.lanterns do
		lantern(lanterns, ctx, at, -W / 2 + 0.8 + i * (W - 1.6) / (S.lanterns + 1), by - S.board / 2, bz)
	end
	-- the awning: canvas stripes from the board's top rising to the back posts
	local roof = Geometry.section(parent, ctx, "Roof", "Wood", 99)
	local tilt = math.atan(S.rise / Dp)
	for i = 1, S.stripes do
		festival(
			roof,
			ctx,
			"Awning",
			at
				* CFrame.new(-W / 2 - 0.3 + (i - 0.5) * (W + 0.6) / S.stripes, h + H + S.rise / 2 + 0.2, 0)
				* CFrame.Angles(-tilt, 0, 0),
			Vector3.new((W + 0.6) / S.stripes + 0.02, 0.35, Dp / math.cos(tilt) + 0.6),
			if i % 2 == 1 then "Canvas" else "RunePaint"
		)
	end
end

-- An arcade along a wall (its back, local +Z, against the building's front): `bays` arches `L` along local X, `D` deep,
-- `H` to the top of its wall band. Chunky piers, each arch's head stepped in corbels (hand-made, not a true curve), a
-- stone floor, a lean-to roof rising `rise` to the wall behind, a lantern hanging in every bay. `raised`: a loggia on
-- an upper floor (a thin floor slab on the arcade below it, a parapet between its piers); `roof` false: none (another
-- arcade stands on it).
function Geometry.arcade(
	parent: Instance,
	ctx: Ctx,
	at: CFrame,
	L: number,
	D: number,
	H: number,
	bays: number,
	raised: boolean?,
	roof: boolean?
)
	local A = ctx.B.Arcade
	local depth = if raised then A.slab else ctx.B.FoundationDepth
	local story = if raised then 1 else 0
	local floor = Geometry.section(parent, ctx, "Floor", "Stone", story - 1)
	Geometry.part(
		floor,
		ctx,
		"Paving",
		at * CFrame.new(0, (A.floor - depth) / 2, 0),
		Vector3.new(L + 0.6, A.floor + depth, D),
		if raised then "Floor" else "Foundation"
	)
	local fz = -D / 2 + A.pier / 2 -- the front line of piers
	local bay = L / bays
	local span = bay - A.pier
	local top = H - A.band
	for i = 0, bays do
		local sec = Geometry.section(parent, ctx, "Pier", ctx.class, story)
		Geometry.part(
			sec,
			ctx,
			"Pier",
			at * CFrame.new(-L / 2 + i * bay, A.floor + (top - A.floor) / 2, fz),
			Vector3.new(A.pier, top - A.floor, A.pier),
			"Wall"
		)
	end
	local band = Geometry.section(parent, ctx, "Arcade", ctx.class, story)
	Geometry.part(
		band,
		ctx,
		"Band",
		at * CFrame.new(0, H - A.band / 2, fz),
		Vector3.new(L + A.pier, A.band, A.pier),
		"Wall"
	)
	local lanterns = Geometry.section(parent, ctx, "Lanterns", "Wood", 99)
	for i = 1, bays do
		local cx = -L / 2 + (i - 0.5) * bay
		-- the arch's head: corbels stepping in from each pier, narrowing down from the band
		for k, w in A.corbels do
			local y = top - (k - 0.5) * A.step
			for _, side in { -1, 1 } do
				Geometry.part(
					band,
					ctx,
					"Corbel",
					at * CFrame.new(cx + side * (span / 2 - w * span / 2), y, fz),
					Vector3.new(w * span, A.step, A.pier),
					"Wall"
				)
			end
		end
		lantern(lanterns, ctx, at, cx, top, fz + 1.2)
		if raised then
			Geometry.part(
				band,
				ctx,
				"Parapet",
				at * CFrame.new(cx, A.floor + A.parapet / 2, fz),
				Vector3.new(span + 0.05, A.parapet, A.pier * 0.7),
				"Wall"
			)
		end
	end
	if roof == false then
		return
	end
	-- the lean-to roof from the band up to the wall
	local cover = Geometry.section(parent, ctx, "Roof", "Tile", 99)
	local tilt = math.atan(A.rise / D)
	Geometry.part(
		cover,
		ctx,
		"Roof",
		at * CFrame.new(0, H + A.rise / 2 + 0.2, 0) * CFrame.Angles(-tilt, 0, 0),
		Vector3.new(L + A.pier + 1, 0.5, D / math.cos(tilt) + 0.8),
		"Roof"
	)
end

-- A river landing: a stone quay `L` along local X and `D` deep, its top at the base, its face to the water (local -Z)
-- with `steps` steps down from it, a coping along its edge and a mooring post with a lantern at each front corner.
function Geometry.landing(parent: Instance, ctx: Ctx, at: CFrame, L: number, D: number, steps: number)
	local S = ctx.B.Landing
	local depth = ctx.B.FoundationDepth
	local quay = Geometry.section(parent, ctx, "Platform", "Stone", -1)
	Geometry.part(
		quay,
		ctx,
		"Quay",
		at * CFrame.new(0, (S.top - depth) / 2, 0),
		Vector3.new(L, S.top + depth, D),
		"Foundation"
	)
	Geometry.part(quay, ctx, "Coping", at * CFrame.new(0, S.top + 0.1, -D / 2 + 0.6), Vector3.new(L, 0.3, 1.2), "Quoin")
	for i = 1, steps do
		local top = S.top - i * S.rise
		Geometry.part(
			quay,
			ctx,
			"Step",
			at * CFrame.new(0, (top - depth) / 2, -D / 2 - (i - 0.5) * S.run),
			Vector3.new(S.width, top + depth, S.run),
			"Quoin"
		)
	end
	local posts = Geometry.section(parent, ctx, "Posts", "Wood", 0)
	for _, side in { -1, 1 } do
		local x, z = side * (L / 2 - 1), -D / 2 + 1
		Geometry.part(
			posts,
			ctx,
			"Post",
			at * CFrame.new(x, S.top + S.post / 2, z),
			Vector3.new(0.8, S.post, 0.8),
			"Trim"
		)
		Geometry.part(
			posts,
			ctx,
			"Hook",
			at * CFrame.new(x, S.top + S.post - 0.3, z - 0.6),
			Vector3.new(0.3, 0.3, 1.2),
			"Metal"
		)
		lantern(posts, ctx, at, x, S.top + S.post - 0.45, z - 1.1)
	end
end

-- A rowing boat `L` long (local Z), its keel on the river's water line (the section is OnWater: VillageBuild puts it
-- there): a plank hull, two thwarts, a pair of oars.
function Geometry.boat(parent: Instance, ctx: Ctx, at: CFrame, L: number)
	local sec = Geometry.section(parent, ctx, "Boat", "Wood", 0)
	sec:SetAttribute("OnWater", true)
	local w = ctx.B.Landing.boat
	Geometry.part(sec, ctx, "Bottom", at * CFrame.new(0, 0.1, 0), Vector3.new(w - 0.8, 0.3, L - 1), "Wood")
	for _, side in { -1, 1 } do
		Geometry.part(
			sec,
			ctx,
			"Side",
			at * CFrame.new(side * (w / 2 - 0.2), 0.6, 0),
			Vector3.new(0.3, 1.1, L - 1),
			"Wood"
		)
		Geometry.part(
			sec,
			ctx,
			"Oar",
			at * CFrame.new(side * (w / 2 + 0.3), 1.2, 0.5),
			Vector3.new(0.2, 0.15, L * 0.6),
			"Trim"
		)
	end
	for _, z in { -1, 1 } do
		Geometry.part(
			sec,
			ctx,
			"End",
			at * CFrame.new(0, 0.6, z * (L / 2 - 0.3)),
			Vector3.new(w - 0.4, 1.1, 0.4),
			"Wood"
		)
		Geometry.part(sec, ctx, "Thwart", at * CFrame.new(0, 0.9, z * L / 5), Vector3.new(w - 0.6, 0.2, 0.8), "Trim")
	end
end

-- A brick lattice vent on a wall (a Selvaran hay barn's gable): a dark backing `W` x `H` and bricks over it in a
-- checker of `Lattice.cell` squares standing proud of it, so the gaps read as holes. `at` is its centre, the wall
-- behind it (local +Z).
function Geometry.lattice(parent: Instance, ctx: Ctx, at: CFrame, W: number, H: number)
	local c = ctx.B.Lattice.cell
	local sec = Geometry.section(parent, ctx, "Lattice", ctx.class, 1)
	Geometry.part(sec, ctx, "Backing", at * CFrame.new(0, 0, 0.1), Vector3.new(W, H, 0.2), "DoorDark")
	local cols, rows = math.floor(W / c), math.floor(H / c)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			if (i + j) % 2 == 0 or i == 0 or j == 0 or i == cols - 1 or j == rows - 1 then
				Geometry.part(
					sec,
					ctx,
					"Brick",
					at * CFrame.new((i + 0.5) * c - cols * c / 2, (j + 0.5) * c - rows * c / 2, -0.15),
					Vector3.new(c + 0.02, c + 0.02, 0.4),
					"Wall"
				)
			end
		end
	end
end

-- A soldiers' ridge tent `L` long (local Z), `W` wide and `H` high, standing on the real ground (OnGround): two canvas
-- sides, canvas ends (a dark door flap in the front one, local -Z), a ridge pole. Its canvas is a Festival key
-- (TentGrey for Katzmark, TentGreen for Selvara).
function Geometry.tent(parent: Instance, ctx: Ctx, at: CFrame, L: number, W: number, H: number, canvas: string?)
	local key = canvas or "TentGrey"
	local sec = Geometry.section(parent, ctx, "Tent", "Wood", 0)
	sec:SetAttribute("OnGround", true)
	local a = math.atan(H / (W / 2))
	local slant = math.sqrt((W / 2) ^ 2 + H * H)
	for _, side in { -1, 1 } do
		festival(
			sec,
			ctx,
			"Canvas",
			at * CFrame.new(side * W / 4, H / 2, 0) * CFrame.Angles(0, 0, -side * a),
			Vector3.new(slant, 0.25, L),
			key
		)
	end
	for _, z in { -L / 2, L / 2 } do
		for _, p in triangle(sec, ctx, at * CFrame.new(0, 0, z), W - 0.3, H - 0.15, 0.2, "Festival") do
			p:SetAttribute("Swatch", key)
		end
	end
	Geometry.part(
		sec,
		ctx,
		"Flap",
		at * CFrame.new(0, H * 0.3, -L / 2 - 0.15),
		Vector3.new(1.4, H * 0.6, 0.12),
		"DoorDark"
	)
	Geometry.part(sec, ctx, "Ridge", at * CFrame.new(0, H + 0.05, 0), Vector3.new(0.3, 0.3, L + 0.8), "Trim")
end

-- A stack of supply crates on the real ground (OnGround): `count` along the bottom, one on top.
function Geometry.crates(parent: Instance, ctx: Ctx, at: CFrame, count: number)
	local sec = Geometry.section(parent, ctx, "Crates", "Wood", 0)
	sec:SetAttribute("OnGround", true)
	local s = ctx.B.Crate
	for i = 1, count do
		local x = (i - (count + 1) / 2) * (s + 0.2)
		Geometry.part(
			sec,
			ctx,
			"Crate",
			at * CFrame.new(x, s / 2, 0) * CFrame.Angles(0, math.rad(i * 7), 0),
			Vector3.new(s, s, s),
			"Wood"
		)
	end
	Geometry.part(
		sec,
		ctx,
		"Crate",
		at * CFrame.new(-0.3, s * 1.5, 0.1) * CFrame.Angles(0, math.rad(-12), 0),
		Vector3.new(s, s, s),
		"Wood"
	)
end

-- A hanging inn sign: a post `height` high, an arm off its top along local X, a framed board hanging under the arm.
function Geometry.sign(parent: Instance, ctx: Ctx, at: CFrame, height: number)
	local S = ctx.B.InnSign
	local sec = Geometry.section(parent, ctx, "Sign", "Wood", 0)
	sec:SetAttribute("OnGround", true)
	Geometry.part(sec, ctx, "Post", at * CFrame.new(0, height / 2, 0), Vector3.new(0.8, height, 0.8), "Trim")
	Geometry.part(sec, ctx, "Arm", at * CFrame.new(S.arm / 2, height - 0.6, 0), Vector3.new(S.arm, 0.5, 0.5), "Trim")
	local w, h = S.board[1], S.board[2]
	local y = height - 1.2 - h / 2
	Geometry.part(sec, ctx, "Board", at * CFrame.new(S.arm - w / 2 - 0.2, y, 0), Vector3.new(w, h, 0.3), "Sign")
	Geometry.part(
		sec,
		ctx,
		"Frame",
		at * CFrame.new(S.arm - w / 2 - 0.2, y, 0),
		Vector3.new(w + 0.4, h + 0.4, 0.2),
		"Trim"
	)
	for _, dx in { -w / 2 + 0.3, w / 2 - 0.3 } do
		Geometry.part(
			sec,
			ctx,
			"Chain",
			at * CFrame.new(S.arm - w / 2 - 0.2 + dx, height - 0.95, 0),
			Vector3.new(0.12, 0.7, 0.12),
			"Metal"
		)
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

-- A part in its own colour (a Palette.Buildings.Walls / Roofs key for `paint` Wall / Roof), whatever the copy's scheme.
local function swatched(
	sec: Instance,
	ctx: Ctx,
	name: string,
	cf: CFrame,
	size: Vector3,
	paint: string,
	key: string
): BasePart
	local p = Geometry.part(sec, ctx, name, cf, size, paint)
	p:SetAttribute("Swatch", key)
	return p
end

-- Two roof slabs `pitch` degrees either side of a ridge along local X over `at` (its eaves at y 0), `half` out to each
-- eave and `L` long, and a ridge cap: a drying shed's or a ring kiln's roof. Returns the rise to the ridge.
local function pitchedRoof(
	sec: Instance,
	ctx: Ctx,
	at: CFrame,
	L: number,
	half: number,
	pitch: number,
	key: string
): number
	local a = math.rad(pitch)
	local rise = half * math.tan(a)
	for _, s in { -1, 1 } do
		swatched(
			sec,
			ctx,
			"Roof",
			at * CFrame.new(0, rise / 2 + 0.25, s * half / 2) * CFrame.Angles(s * a, 0, 0),
			Vector3.new(L, 0.5, half / math.cos(a) + 0.3),
			"Roof",
			key
		)
	end
	swatched(sec, ctx, "Ridge", at * CFrame.new(0, rise + 0.35, 0), Vector3.new(L + 0.2, 0.6, 0.9), "Roof", key)
	return rise
end

-- Fornace Aurelia's chimney (Config/Buildings.Smokestack): a square brick shaft `H` high on a stone plinth, `base`
-- across at its foot narrowing course by course to `top`, banded near the top, a dark flue and an iron rod on it.
-- Each course a section of its own, so shells bring it down where they hit; solid, nobody climbs it.
function Geometry.smokestack(parent: Instance, ctx: Ctx, at: CFrame, base: number, top: number, H: number)
	local S = ctx.B.Smokestack
	local depth = ctx.B.FoundationDepth
	local plinth = Geometry.section(parent, ctx, "Chimney", "Stone", 0)
	local pw = base + 2 * S.plinthOut
	swatched(
		plinth,
		ctx,
		"Plinth",
		at * CFrame.new(0, (S.plinth - depth) / 2, 0),
		Vector3.new(pw, S.plinth + depth, pw),
		"Wall",
		S.base
	)
	swatched(
		plinth,
		ctx,
		"Coping",
		at * CFrame.new(0, S.plinth + 0.3, 0),
		Vector3.new(pw - 0.8, 0.6, pw - 0.8),
		"Wall",
		S.base
	)
	local y0 = S.plinth + 0.6
	local per = (H - y0) / S.segments
	local function width(y: number): number
		return base + (top - base) * (y - y0) / (H - y0)
	end
	for i = 0, S.segments - 1 do
		local a, b = y0 + i * per, y0 + (i + 1) * per
		local w = width((a + b) / 2)
		local sec = Geometry.section(parent, ctx, "Chimney", "Brick", 0)
		swatched(sec, ctx, "Shaft", at * CFrame.new(0, (a + b) / 2, 0), Vector3.new(w, per + 0.05, w), "Wall", S.wall)
	end
	local bands = Geometry.section(parent, ctx, "Chimney", "Brick", 0)
	for _, share in S.bands do
		local y = math.min(H * share, H - S.band / 2)
		local w = width(y) + 2 * S.bandOut
		swatched(bands, ctx, "Band", at * CFrame.new(0, y, 0), Vector3.new(w, S.band, w), "Wall", S.trim)
	end
	swatched(
		bands,
		ctx,
		"Flue",
		at * CFrame.new(0, H + 0.05, 0),
		Vector3.new(top - 1.4, 0.2, top - 1.4),
		"Wall",
		S.dark
	)
	Geometry.part(
		bands,
		ctx,
		"Rod",
		at * CFrame.new(top / 2 - 0.3, H + S.rod / 2, top / 2 - 0.3),
		Vector3.new(0.25, S.rod, 0.25),
		"Metal"
	)
end

-- A Hoffmann ring kiln (Config/Buildings.RingKiln) `L` along local X, `D` deep and `H` to its cornice: a solid brick
-- mass on a foundation in `bays` bays, a pilaster between each two (through to the back) and at the ends, a dark
-- arched wicket in every bay front and back and one in each end, a cornice, a terracotta roof over it with brick
-- gables. Each bay a section of its own.
function Geometry.ringKiln(parent: Instance, ctx: Ctx, at: CFrame, L: number, D: number, H: number, bays: number)
	local K = ctx.B.RingKiln
	local depth = ctx.B.FoundationDepth
	local base = ctx.B.Foundation
	Geometry.part(
		parent,
		ctx,
		"Foundation",
		at * CFrame.new(0, (base - 1 - depth) / 2, 0),
		Vector3.new(L + K.pier + 2 * K.pierOut + 0.6, base - 1 + depth, D + 2 * K.pierOut + 0.6),
		"Foundation"
	)
	local bay = L / bays
	local w, h = K.wicket[1], K.wicket[2]
	-- a wicket on a face (`face`: the wall's outside frame, -Z out, at its foot), `cx` along it: the opening and its
	-- head stepping in, standing just proud of the brick
	local function wicket(sec: Instance, face: CFrame, cx: number)
		swatched(sec, ctx, "Wicket", face * CFrame.new(cx, h / 2, -0.06), Vector3.new(w, h, 0.2), "Wall", K.dark)
		swatched(
			sec,
			ctx,
			"Head",
			face * CFrame.new(cx, h + 0.3, -0.06),
			Vector3.new(w * 0.72, 0.6, 0.2),
			"Wall",
			K.dark
		)
		swatched(
			sec,
			ctx,
			"Head",
			face * CFrame.new(cx, h + 0.8, -0.06),
			Vector3.new(w * 0.4, 0.4, 0.2),
			"Wall",
			K.dark
		)
	end
	local front = at * CFrame.new(0, 0, -D / 2)
	local back = at * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, -D / 2)
	for i = 1, bays do
		local cx = -L / 2 + (i - 0.5) * bay
		local sec = Geometry.section(parent, ctx, "Kiln", "Brick", 0)
		swatched(sec, ctx, "Body", at * CFrame.new(cx, H / 2, 0), Vector3.new(bay + 0.05, H, D), "Wall", K.wall)
		wicket(sec, front, cx)
		wicket(sec, back, -cx)
	end
	for i = 0, bays do
		local sec = Geometry.section(parent, ctx, "Pier", "Brick", 0)
		swatched(
			sec,
			ctx,
			"Pier",
			at * CFrame.new(-L / 2 + i * bay, (H - K.cornice) / 2, 0),
			Vector3.new(K.pier, H - K.cornice, D + 2 * K.pierOut),
			"Wall",
			K.pierWall
		)
	end
	for _, s in { -1, 1 } do
		local sec = Geometry.section(parent, ctx, "Kiln", "Brick", 0)
		wicket(sec, at * CFrame.Angles(0, -s * math.pi / 2, 0) * CFrame.new(0, 0, -L / 2 - K.pier / 2), 0)
	end
	local top = Geometry.section(parent, ctx, "Kiln", "Brick", 0)
	swatched(
		top,
		ctx,
		"Cornice",
		at * CFrame.new(0, H - K.cornice / 2, 0),
		Vector3.new(L + K.pier + 2 * K.pierOut, K.cornice, D + 2 * K.pierOut + 0.4),
		"Wall",
		K.pierWall
	)
	local roof = Geometry.section(parent, ctx, "Roof", "Tile", 99)
	local half = D / 2 + K.pierOut + K.overhang
	local rise = pitchedRoof(roof, ctx, at * CFrame.new(0, H, 0), L + K.pier + 2 * K.overhang, half, K.pitch, K.roof)
	for _, s in { -1, 1 } do
		local frame = at * CFrame.new(s * (L / 2 + K.pier / 2 - 0.4), H, 0) * CFrame.Angles(0, math.pi / 2, 0)
		for _, p in triangle(top, ctx, frame, D + 2 * K.pierOut, rise * (D / 2 + K.pierOut) / half, 0.8, "Wall") do
			p:SetAttribute("Swatch", K.pierWall)
		end
	end
end

-- An open drying shed (Config/Buildings.DryingShed) `L` along local X, `span` across, its eaves `height` up: posts on a
-- brick floor, a low terracotta roof, two rows of green bricks drying in hacks (hoppable cover) and a canvas screen
-- hung along its back (+Z) eave.
function Geometry.dryingShed(parent: Instance, ctx: Ctx, at: CFrame, L: number, span: number, height: number)
	local S = ctx.B.DryingShed
	local depth = ctx.B.FoundationDepth
	local floor = Geometry.section(parent, ctx, "Platform", "Stone", -1)
	Geometry.part(
		floor,
		ctx,
		"Bed",
		at * CFrame.new(0, (0.4 - depth) / 2, 0),
		Vector3.new(L + 0.6, 0.4 + depth, span + 0.6),
		"Foundation"
	)
	local bays = math.max(1, math.round(L / S.bay))
	for i = 0, bays do
		local x = -L / 2 + i * L / bays
		local sec = Geometry.section(parent, ctx, "Post", "Wood", 0)
		for _, sz in { -1, 1 } do
			Geometry.part(
				sec,
				ctx,
				"Post",
				at * CFrame.new(x, height / 2, sz * (span / 2 - 0.5)),
				Vector3.new(1, height, 1),
				"Trim"
			)
		end
		Geometry.part(sec, ctx, "Beam", at * CFrame.new(x, height - 0.35, 0), Vector3.new(0.7, 0.7, span), "Trim")
	end
	for _, sz in { -1, 1 } do
		local sec = Geometry.section(parent, ctx, "Beam", "Wood", 0)
		Geometry.part(
			sec,
			ctx,
			"Plate",
			at * CFrame.new(0, height - 0.35, sz * (span / 2 - 0.5)),
			Vector3.new(L, 0.7, 0.8),
			"Trim"
		)
	end
	local roof = Geometry.section(parent, ctx, "Roof", "Tile", 99)
	pitchedRoof(roof, ctx, at * CFrame.new(0, height, 0), L + 2 * S.overhang, span / 2 + S.overhang, S.pitch, S.roof)
	-- the hacks: a row of brick stacks either side of the middle, a gap between each two
	local piece = L / bays - S.gap
	for _, sz in { -1, 1 } do
		for i = 1, bays do
			local sec = Geometry.section(parent, ctx, "Hack", "Brick", 0)
			swatched(
				sec,
				ctx,
				"Hack",
				at * CFrame.new(-L / 2 + (i - 0.5) * L / bays, 0.4 + S.hack[1] / 2, sz * span / 4),
				Vector3.new(piece, S.hack[1], S.hack[2]),
				"Wall",
				S.green
			)
		end
	end
	local screen = Geometry.section(parent, ctx, "Screen", "Wood", 0)
	festival(
		screen,
		ctx,
		"Canvas",
		at * CFrame.new(0, height - 0.7 - S.screen / 2, span / 2 - 0.2),
		Vector3.new(L - 1, S.screen, 0.15),
		S.canvas
	)
end

-- A flooded clay pit (Config/Buildings.ClayPit), an oval `L` along local X and `W` across, `depth` deep at its middle:
-- an invisible marker ("Pit", the oval's box) that VillageBuild digs into the terrain and floods, and spoil heaps of
-- clay on the real ground at its two ends.
function Geometry.clayPit(parent: Instance, ctx: Ctx, at: CFrame, L: number, W: number, depth: number)
	local K = ctx.B.ClayPit
	local sec = Geometry.section(parent, ctx, "ClayPit", "Stone", 0)
	sec:SetAttribute("Pit", depth)
	local marker = Geometry.part(sec, ctx, "Pit", at, Vector3.new(L, 1, W), "Foundation")
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CastShadow = false
	for _, s in { -1, 1 } do
		local heap = Geometry.section(parent, ctx, "Spoil", "Stone", 0)
		heap:SetAttribute("OnGround", true)
		local frame = at * CFrame.new(s * (L / 2 + 5), -0.4, 0) * CFrame.Angles(0, math.pi / 2, 0)
		for _, p in triangle(heap, ctx, frame, W * 0.6, K.spoil + 0.4, 4, "Wall") do
			p:SetAttribute("Swatch", K.clay)
		end
	end
end

-- A square pyramid `W` across at its foot (y 0 of `at`) and `h` high: four triangles leaning in to the apex, each `thick`
-- through (a campanile's cap). Returns the parts.
local function pyramid(sec: Instance, ctx: Ctx, at: CFrame, W: number, h: number, thick: number): { BasePart }
	local lean = math.atan((W / 2) / h)
	local slant = math.sqrt(h * h + (W / 2) ^ 2)
	local out = {}
	for k = 0, 3 do
		local frame = at * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -W / 2) * CFrame.Angles(lean, 0, 0)
		for _, p in triangle(sec, ctx, frame, W, slant, thick, "Roof") do
			table.insert(out, p)
		end
	end
	return out
end

-- Borgo Aurel's campanile above its tower block (Config/Buildings.BellTower): a square brick shaft `W` across from `y0`
-- (the block's wall top) in stages, each with a string course, corner pilasters and a slit a face; an open belfry of
-- two arches a face round a dark core with a bell in each arch; a cornice; a terracotta pyramid cap to `H`. Solid: the
-- stair inside the block below stops at its top floor.
function Geometry.bellTower(parent: Instance, ctx: Ctx, at: CFrame, W: number, y0: number, H: number)
	local K = ctx.B.BellTower
	local capY = H - K.cap
	local belfryY = capY - K.cornice - K.belfry
	local stages = math.max(1, math.round((belfryY - y0) / K.stage))
	local per = (belfryY - y0) / stages
	local faces = {}
	for k = 0, 3 do
		table.insert(faces, at * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -W / 2))
	end
	for i = 0, stages - 1 do
		local a, b = y0 + i * per, y0 + (i + 1) * per
		local sec = Geometry.section(parent, ctx, "Tower", "Brick", 4 + i)
		swatched(sec, ctx, "Shaft", at * CFrame.new(0, (a + b) / 2, 0), Vector3.new(W, per + 0.05, W), "Wall", K.wall)
		swatched(
			sec,
			ctx,
			"Course",
			at * CFrame.new(0, b - K.course / 2, 0),
			Vector3.new(W + 2 * K.out + 0.3, K.course, W + 2 * K.out + 0.3),
			"Wall",
			K.trim
		)
		for _, f in faces do
			for _, s in { -1, 1 } do
				swatched(
					sec,
					ctx,
					"Pilaster",
					f * CFrame.new(s * (W / 2 - K.pilaster / 2), (a + b) / 2, -K.out / 2),
					Vector3.new(K.pilaster, per, K.out + 0.05),
					"Wall",
					K.trim
				)
			end
			if i % 2 == 1 then
				swatched(
					sec,
					ctx,
					"Slit",
					f * CFrame.new(0, (a + b) / 2, -0.06),
					Vector3.new(K.slit[1], K.slit[2], 0.2),
					"Wall",
					K.dark
				)
			end
		end
	end
	-- the belfry: a sill, the dark core, piers at the corners and a mullion in each face, the arch heads, the bells
	local bel = Geometry.section(parent, ctx, "Belfry", "Brick", 4 + stages)
	local top = belfryY + K.belfry
	swatched(
		bel,
		ctx,
		"Core",
		at * CFrame.new(0, (belfryY + top) / 2, 0),
		Vector3.new(W - 2 * K.inset, K.belfry, W - 2 * K.inset),
		"Wall",
		K.dark
	)
	local span = (W - 2 * K.pier - K.mullion) / 2
	for _, f in faces do
		for _, s in { -1, 1 } do
			swatched(
				bel,
				ctx,
				"Pier",
				f * CFrame.new(s * (W / 2 - K.pier / 2), (belfryY + top) / 2, K.pier / 2),
				Vector3.new(K.pier, K.belfry, K.pier),
				"Wall",
				K.wall
			)
			local cx = s * (K.mullion / 2 + span / 2)
			-- the arch's head: two steps in from the piers under the cornice
			for k, share in { 0.28, 0.12 } do
				local y = top - (k - 0.5) * 0.8
				for _, side in { -1, 1 } do
					swatched(
						bel,
						ctx,
						"Head",
						f * CFrame.new(cx + side * (span / 2 - share * span / 2), y, K.inset / 2),
						Vector3.new(share * span, 0.8, K.inset),
						"Wall",
						K.wall
					)
				end
			end
			local bell = swatched(
				bel,
				ctx,
				"Bell",
				f * CFrame.new(cx, top - 3.4, K.inset - K.bell / 2 - 0.1),
				Vector3.new(K.bell, K.bell * 1.1, K.bell),
				"Wall",
				K.bronze
			)
			bell.CanCollide = false
		end
		swatched(
			bel,
			ctx,
			"Mullion",
			f * CFrame.new(0, (belfryY + top) / 2, K.inset / 2),
			Vector3.new(K.mullion, K.belfry, K.inset),
			"Wall",
			K.wall
		)
		swatched(
			bel,
			ctx,
			"Sill",
			f * CFrame.new(0, belfryY + 0.4, K.inset / 2),
			Vector3.new(W, 0.8, K.inset + 0.6),
			"Wall",
			K.trim
		)
	end
	swatched(
		bel,
		ctx,
		"Cornice",
		at * CFrame.new(0, top + K.cornice / 2, 0),
		Vector3.new(W + 2 * K.eave, K.cornice, W + 2 * K.eave),
		"Wall",
		K.trim
	)
	local cap = Geometry.section(parent, ctx, "Roof", "Tile", 99)
	for _, p in pyramid(cap, ctx, at * CFrame.new(0, capY, 0), W + 2 * K.eave, K.cap, 0.6) do
		p:SetAttribute("Swatch", K.roof)
	end
	Geometry.part(cap, ctx, "Finial", at * CFrame.new(0, H + 0.6, 0), Vector3.new(0.6, 1.6, 0.6), "Metal")
end

-- A church's front screen (Config/Buildings.Facade) standing before its front wall (local -Z out), `W` across: the
-- wall `H` up round the door's opening (the block's door, Metrics.Building's size, in the middle), pilasters, a
-- cornice, a pediment over the roof's gable (`pitch` degrees) with a cross, a rose window over the door.
function Geometry.facade(parent: Instance, ctx: Ctx, at: CFrame, W: number, H: number, pitch: number)
	local K = ctx.B.Facade
	local Bm = ctx.M.Building
	local floor = ctx.B.Foundation
	local ow, oh = Bm.DoorWidth + 0.4, floor + Bm.DoorHeight + 0.3
	local sec = Geometry.section(parent, ctx, "Facade", "Stone", 0)
	local side = (W - ow) / 2
	for _, s in { -1, 1 } do
		swatched(
			sec,
			ctx,
			"Screen",
			at * CFrame.new(s * (ow / 2 + side / 2), (H - 1) / 2, 0),
			Vector3.new(side, H + 1, K.thick),
			"Wall",
			K.wall
		)
		for _, x in { W / 2 - K.pilaster / 2, ow / 2 + K.pilaster / 2 + 0.6 } do
			swatched(
				sec,
				ctx,
				"Pilaster",
				at * CFrame.new(s * x, (H - 1) / 2, -K.thick / 2 - K.out / 2),
				Vector3.new(K.pilaster, H + 1, K.out + 0.05),
				"Wall",
				K.trim
			)
		end
	end
	swatched(
		sec,
		ctx,
		"Screen",
		at * CFrame.new(0, (oh + H) / 2, 0),
		Vector3.new(ow + 0.1, H - oh, K.thick),
		"Wall",
		K.wall
	)
	swatched(
		sec,
		ctx,
		"Lintel",
		at * CFrame.new(0, oh + 0.3, -K.thick / 2 - K.out / 2),
		Vector3.new(ow + 1.2, 0.6, K.out + 0.05),
		"Wall",
		K.trim
	)
	swatched(
		sec,
		ctx,
		"Cornice",
		at * CFrame.new(0, H + K.cornice / 2, -K.out / 2),
		Vector3.new(W + 0.6, K.cornice, K.thick + K.out + 0.4),
		"Wall",
		K.trim
	)
	-- the pediment: over the nave's gable (half the screen across at its pitch), a little taller
	local rise = (W / 2) * math.tan(math.rad(pitch)) + K.rise
	local ped = Geometry.section(parent, ctx, "Facade", "Stone", 1)
	for _, p in triangle(ped, ctx, at * CFrame.new(0, H + K.cornice, 0), W, rise, K.thick, "Wall") do
		p:SetAttribute("Swatch", K.wall)
	end
	local apex = H + K.cornice + rise
	Geometry.part(ped, ctx, "Cross", at * CFrame.new(0, apex + K.cross / 2, 0), Vector3.new(0.5, K.cross, 0.5), "Metal")
	Geometry.part(ped, ctx, "Cross", at * CFrame.new(0, apex + K.cross * 0.68, 0), Vector3.new(1.8, 0.5, 0.5), "Metal")
	-- the rose window between the door and the cornice
	local ry = (oh + 0.6 + H) / 2
	local ring = swatched(
		sec,
		ctx,
		"Ring",
		at * CFrame.new(0, ry, -K.thick / 2 - 0.15) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(0.3, K.rose + 2 * K.ring, K.rose + 2 * K.ring),
		"Wall",
		K.trim
	)
	ring.Shape = Enum.PartType.Cylinder
	local rose = Geometry.part(
		sec,
		ctx,
		"Rose",
		at * CFrame.new(0, ry, -K.thick / 2 - 0.3) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(0.2, K.rose, K.rose),
		"Glass"
	)
	rose.Shape = Enum.PartType.Cylinder
	for _, a in { 0, 45, 90, 135 } do
		Geometry.part(
			sec,
			ctx,
			"Tracery",
			at * CFrame.new(0, ry, -K.thick / 2 - 0.42) * CFrame.Angles(0, 0, math.rad(a)),
			Vector3.new(K.rose, 0.25, 0.1),
			"Trim"
		)
	end
end

-- A piazza fountain on the real ground (Config/Buildings.Fountain), `r` out to its rim: an eight-sided stone basin you
-- hop over, its water, a pillar with a bowl and a finial in the middle.
function Geometry.fountain(parent: Instance, ctx: Ctx, at: CFrame, r: number)
	local K = ctx.B.Fountain
	local sec = Geometry.section(parent, ctx, "Fountain", "Stone", 0)
	sec:SetAttribute("OnGround", true)
	local side = 2 * r * math.tan(math.pi / 8)
	for i = 0, 7 do
		swatched(
			sec,
			ctx,
			"Rim",
			at * CFrame.Angles(0, i * math.pi / 4, 0) * CFrame.new(0, (K.rim - 1) / 2, -(r - K.thick / 2)),
			Vector3.new(side + K.thick * 0.85, K.rim + 1, K.thick),
			"Wall",
			K.stone
		)
	end
	local function disc(name: string, y: number, h: number, d: number, paint: string): BasePart
		local p = Geometry.part(
			sec,
			ctx,
			name,
			at * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(h, d, d),
			paint
		)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	disc("Floor", -0.3, 1.4, 2 * r - 0.6, "Foundation")
	local water = disc("Water", K.water - 0.1, 0.2, 2 * r - 1.2, "Glass")
	water.Transparency = 0.25
	water.CanCollide = false
	local pillar = disc("Pillar", K.bowlY / 2, K.bowlY, K.pillar, "Wall")
	pillar.Size = Vector3.new(K.bowlY, K.pillar, K.pillar)
	pillar:SetAttribute("Swatch", K.stone)
	disc("Bowl", K.bowlY, 0.6, K.bowl, "Wall"):SetAttribute("Swatch", K.stone)
	disc("Spill", K.bowlY + 0.35, 0.15, K.bowl - 0.6, "Glass").CanCollide = false
	disc("Finial", (K.bowlY + K.top) / 2, K.top - K.bowlY, 0.8, "Wall"):SetAttribute("Swatch", K.stone)
end

-- A town gate tower (Config/Buildings.GateTower) `W` across, `D` deep (its way through along local Z) and `H` to its
-- merlons' tops: two piers, the way `way` { width, height } between them under a stepped arch head, the tower over it,
-- a string course, quoins, arrow slits front and back, a battlemented top. Solid; the road runs through.
function Geometry.gateTower(parent: Instance, ctx: Ctx, at: CFrame, W: number, D: number, H: number, way: { number })
	local K = ctx.B.GateTower
	local depth = ctx.B.FoundationDepth
	local ww, wh = way[1], way[2]
	local pw = (W - ww) / 2
	local body = H - K.merlon[2]
	for _, s in { -1, 1 } do
		local sec = Geometry.section(parent, ctx, "Pier", "Stone", 0)
		swatched(
			sec,
			ctx,
			"Pier",
			at * CFrame.new(s * (ww / 2 + pw / 2), (wh - depth) / 2, 0),
			Vector3.new(pw, wh + depth, D),
			"Wall",
			K.wall
		)
		for k, share in K.steps do
			swatched(
				sec,
				ctx,
				"Corbel",
				at * CFrame.new(s * (ww / 2 - share * ww / 2), wh + (k - 0.5) * K.corbel, 0),
				Vector3.new(share * ww, K.corbel, D),
				"Wall",
				K.wall
			)
		end
	end
	local headY = wh + #K.steps * K.corbel
	local tiers = 2
	local per = (body - wh) / tiers
	for i = 0, tiers - 1 do
		local a = wh + i * per
		local b = a + per
		local sec = Geometry.section(parent, ctx, "Tower", "Stone", 1 + i)
		for _, s in { -1, 1 } do
			swatched(
				sec,
				ctx,
				"Wall",
				at * CFrame.new(s * (ww / 2 + pw / 2), (a + b) / 2, 0),
				Vector3.new(pw, per + 0.05, D),
				"Wall",
				K.wall
			)
		end
		local a2 = math.max(a, headY)
		swatched(
			sec,
			ctx,
			"Wall",
			at * CFrame.new(0, (a2 + b) / 2, 0),
			Vector3.new(ww + 0.1, b - a2 + 0.05, D),
			"Wall",
			K.wall
		)
		-- arrow slits front and back: one over each pier, one over the way
		for _, face in { 0, math.pi } do
			local f = at * CFrame.Angles(0, face, 0) * CFrame.new(0, 0, -D / 2)
			for _, x in { -(ww / 2 + pw / 2), 0, ww / 2 + pw / 2 } do
				swatched(
					sec,
					ctx,
					"Slit",
					f * CFrame.new(x, (a + b) / 2 + 1, -0.06),
					Vector3.new(K.slit[1], K.slit[2], 0.2),
					"Wall",
					K.dark
				)
			end
		end
	end
	local trim = Geometry.section(parent, ctx, "Tower", "Stone", 3)
	swatched(
		trim,
		ctx,
		"Course",
		at * CFrame.new(0, wh + per, 0),
		Vector3.new(W + 0.5, K.course, D + 0.5),
		"Wall",
		K.trim
	)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			swatched(
				trim,
				ctx,
				"Quoin",
				at * CFrame.new(sx * (W / 2 - K.quoin / 2 + 0.15), body / 2, sz * (D / 2 - K.quoin / 2 + 0.15)),
				Vector3.new(K.quoin, body, K.quoin),
				"Wall",
				K.trim
			)
		end
	end
	-- the merlons round the top, a merlon at every corner
	local runs = { { CFrame.new(0, 0, -D / 2 + 0.6), W }, { CFrame.new(0, 0, D / 2 - 0.6), W } }
	table.insert(runs, { CFrame.new(-W / 2 + 0.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D })
	table.insert(runs, { CFrame.new(W / 2 - 0.6, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), D })
	for _, r in runs do
		local L = r[2]
		local n = math.max(3, math.floor(L / K.merlon[1] / 2) * 2 + 1)
		for i = 0, n - 1, 2 do
			swatched(
				trim,
				ctx,
				"Merlon",
				at * r[1] * CFrame.new(-L / 2 + (i + 0.5) * L / n, body + K.merlon[2] / 2, 0),
				Vector3.new(L / n, K.merlon[2], 1.2),
				"Wall",
				K.wall
			)
		end
	end
end

-- A stretch of old town wall (Config/Buildings.TownWall) along local X, `thick` thick: each piece { from, to, height }
-- on the real ground where it stands, a tall piece battlemented, a low one broken off in steps; gaps between them; a
-- round tower stump `tower` { x, radius, height } with a string course and merlons.
function Geometry.townWall(parent: Instance, ctx: Ctx, at: CFrame, thick: number, pieces: { any }, tower: any?)
	local K = ctx.B.TownWall
	for i, q in pieces do
		local a, b, h = q[1], q[2], q[3]
		local L = b - a
		local cx = (a + b) / 2
		local sec = Geometry.section(parent, ctx, "Wall", "Stone", 0)
		sec:SetAttribute("OnGround", true)
		swatched(sec, ctx, "Wall", at * CFrame.new(cx, (h - 1) / 2, 0), Vector3.new(L, h + 1, thick), "Wall", K.stone)
		if h >= K.crenel then
			local n = math.max(3, math.floor(L / K.merlon[1] / 2) * 2 + 1)
			for k = 0, n - 1, 2 do
				swatched(
					sec,
					ctx,
					"Merlon",
					at * CFrame.new(a + (k + 0.5) * L / n, h + K.merlon[2] / 2, 0),
					Vector3.new(L / n, K.merlon[2], thick),
					"Wall",
					K.stone
				)
			end
		else
			-- broken off: the rubble of the courses above in steps toward one end
			local side = if i % 2 == 0 then 1 else -1
			for k, share in { 0.55, 0.25 } do
				swatched(
					sec,
					ctx,
					"Rubble",
					at * CFrame.new(cx + side * L * (1 - share) / 2, h + (k - 0.5) * K.step, 0),
					Vector3.new(L * share, K.step, thick - 0.3 * k),
					"Wall",
					K.stone
				)
			end
		end
	end
	if tower then
		local r, h = tower.radius, tower.height
		local sec = Geometry.section(parent, ctx, "Tower", "Stone", 0)
		sec:SetAttribute("OnGround", true)
		local c = at * CFrame.new(tower.x, 0, 0)
		local n = K.sides
		local side = 2 * r * math.tan(math.pi / n)
		swatched(
			sec,
			ctx,
			"Core",
			c * CFrame.new(0, (h - 1) / 2, 0),
			Vector3.new(1.5 * r, h + 1, 1.5 * r),
			"Wall",
			K.stone
		)
		for k = 0, n - 1 do
			local face = c * CFrame.Angles(0, k * 2 * math.pi / n, 0)
			swatched(
				sec,
				ctx,
				"Drum",
				face * CFrame.new(0, (h - 1) / 2, -(r - 0.6)),
				Vector3.new(side + 0.5, h + 1, 1.2),
				"Wall",
				K.stone
			)
			if k % 2 == 0 then
				swatched(
					sec,
					ctx,
					"Merlon",
					face * CFrame.new(0, h + K.merlon[2] / 2, -(r - 0.6)),
					Vector3.new(side + 0.3, K.merlon[2], 1.2),
					"Wall",
					K.stone
				)
			end
			swatched(
				sec,
				ctx,
				"Course",
				face * CFrame.new(0, h * 0.6, -(r - 0.4)),
				Vector3.new(side + 0.7, K.course, 1.2),
				"Wall",
				K.trim
			)
		end
	end
end

return Geometry
