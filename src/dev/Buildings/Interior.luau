--!strict
-- Furniture inside a building (a template's or a landmark block's `interior`; sizes in Config/Buildings.Furniture,
-- placement checked by Rules/Interior). Every piece is made of shaped parts (legs, tops, rails, posts, hoops), never a
-- lone block, and is a destruction section of its own on its story: shot apart piece by piece, gone when its story
-- falls (src/server/Destruction).

local Geometry = require(script.Parent.Geometry)

local Interior = {}

local function part(sec: Instance, ctx: any, name: string, cf: CFrame, size: Vector3, paint: string): BasePart
	return Geometry.part(sec, ctx, name, cf, size, paint)
end

-- a cylinder `length` long along the frame's y, `d` across
local function post(sec: Instance, ctx: any, name: string, cf: CFrame, length: number, d: number, paint: string)
	local p = Geometry.part(sec, ctx, name, cf * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(length, d, d), paint)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function legs(sec: Instance, ctx: any, at: CFrame, w: number, d: number, h: number, leg: number, paint: string)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				sec,
				ctx,
				"Leg",
				at * CFrame.new(sx * (w / 2 - leg), h / 2, sz * (d / 2 - leg)),
				Vector3.new(leg, h, leg),
				paint
			)
		end
	end
end

local function table_(sec: Instance, ctx: any, at: CFrame, f: any, w: number, d: number)
	local top = f.top
	part(sec, ctx, "Top", at * CFrame.new(0, f.h - top / 2, 0), Vector3.new(w, top, d), "Wood")
	-- the apron under the top, set in from its edge, and the legs
	part(sec, ctx, "Apron", at * CFrame.new(0, f.h - top - 0.3, 0), Vector3.new(w - 1.2, 0.6, d - 1.2), "Stairs")
	legs(sec, ctx, at, w - 0.6, d - 0.6, f.h - top, f.leg, "Stairs")
end

local function bench(sec: Instance, ctx: any, at: CFrame, f: any, w: number, d: number)
	part(sec, ctx, "Seat", at * CFrame.new(0, f.h - f.top / 2, 0), Vector3.new(w, f.top, d), "Wood")
	for _, sx in { -1, 1 } do
		-- a trestle at each end: a slab leg, splayed a little, on a foot
		part(
			sec,
			ctx,
			"Trestle",
			at * CFrame.new(sx * (w / 2 - 0.8), (f.h - f.top) / 2, 0) * CFrame.Angles(0, 0, math.rad(sx * 6)),
			Vector3.new(f.leg, f.h - f.top, d - 0.2),
			"Stairs"
		)
		part(sec, ctx, "Foot", at * CFrame.new(sx * (w / 2 - 0.8), 0.15, 0), Vector3.new(0.7, 0.3, d), "Stairs")
	end
	part(sec, ctx, "Stretcher", at * CFrame.new(0, 0.5, 0), Vector3.new(w - 1.6, 0.3, 0.3), "Stairs")
end

local function bed(sec: Instance, ctx: any, at: CFrame, f: any, w: number, d: number)
	-- the head at +z (against a wall before the yaw)
	local frame = 0.9
	for _, sx in { -1, 1 } do
		part(sec, ctx, "Rail", at * CFrame.new(sx * (w / 2 - 0.15), frame, 0), Vector3.new(0.3, 0.6, d), "Stairs")
	end
	part(sec, ctx, "Headboard", at * CFrame.new(0, f.head / 2, d / 2 - 0.2), Vector3.new(w, f.head, 0.4), "Wood")
	part(sec, ctx, "Footboard", at * CFrame.new(0, 1.3, -d / 2 + 0.2), Vector3.new(w, 2.6 - 0.4, 0.4), "Wood")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local h = if sz > 0 then f.head + 0.4 else 2.8
			post(sec, ctx, "Post", at * CFrame.new(sx * (w / 2 - 0.2), h / 2, sz * (d / 2 - 0.2)), h, f.post, "Stairs")
		end
	end
	part(sec, ctx, "Mattress", at * CFrame.new(0, 1.45, 0), Vector3.new(w - 0.6, 0.9, d - 0.8), "Linen")
	part(sec, ctx, "Blanket", at * CFrame.new(0, 1.75, -d * 0.12), Vector3.new(w - 0.4, 0.4, d * 0.6), "Cloth")
	part(sec, ctx, "Pillow", at * CFrame.new(0, 2.05, d / 2 - 1.2), Vector3.new(w - 1.4, 0.5, 1.2), "Linen")
end

local function hearth(sec: Instance, ctx: any, at: CFrame, f: any, w: number, d: number)
	-- a stone chimney breast against the wall (+z), a wide mouth with a timber lintel, a hearthstone and logs
	local jamb = (w - f.mouth) / 2
	for _, sx in { -1, 1 } do
		part(
			sec,
			ctx,
			"Jamb",
			at * CFrame.new(sx * (f.mouth / 2 + jamb / 2), f.mouthH / 2, 0),
			Vector3.new(jamb, f.mouthH, d),
			"Foundation"
		)
	end
	part(sec, ctx, "Lintel", at * CFrame.new(0, f.mouthH + 0.4, -0.2), Vector3.new(w + 0.4, 0.8, d + 0.2), "Stairs")
	part(
		sec,
		ctx,
		"Breast",
		at * CFrame.new(0, (f.mouthH + 0.8 + f.h) / 2, 0.3),
		Vector3.new(w - 0.6, f.h - f.mouthH - 0.8, d - 0.6),
		"Foundation"
	)
	part(sec, ctx, "Back", at * CFrame.new(0, f.mouthH / 2, d / 2 - 0.3), Vector3.new(f.mouth, f.mouthH, 0.6), "Metal")
	part(sec, ctx, "Hearthstone", at * CFrame.new(0, 0.15, -d / 2 - 0.4), Vector3.new(w + 1, 0.3, 1.6), "Quoin")
	for i = -1, 1, 2 do
		post(
			sec,
			ctx,
			"Log",
			at * CFrame.new(i * 0.6, 0.5, 0) * CFrame.Angles(math.pi / 2, 0, math.rad(i * 20)),
			2.6,
			0.6,
			"Stairs"
		)
	end
end

local function pillar(sec: Instance, ctx: any, at: CFrame, f: any, H: number)
	part(sec, ctx, "Base", at * CFrame.new(0, 0.4, 0), Vector3.new(f.base, 0.8, f.base), "Quoin")
	part(sec, ctx, "Plinth", at * CFrame.new(0, 1.0, 0), Vector3.new(f.base - 0.4, 0.4, f.base - 0.4), "Quoin")
	post(sec, ctx, "Shaft", at * CFrame.new(0, H / 2, 0), H - 1.2 - f.cap, f.shaft, "Quoin")
	part(sec, ctx, "Capital", at * CFrame.new(0, H - f.cap / 2, 0), Vector3.new(f.base, f.cap, f.base), "Quoin")
end

local function hay(sec: Instance, ctx: any, at: CFrame, f: any, levels: number)
	for lv = 0, levels - 1 do
		-- bales in a stack, each level turned a little and set back
		for i = -1, 1, 2 do
			local c = at
				* CFrame.new(i * f.w / 4 + lv * 0.3, lv * f.h + f.h / 2, (lv % 2) * 0.3)
				* CFrame.Angles(0, math.rad((lv * 13 + i * 5) % 11 - 5), 0)
			part(sec, ctx, "Bale", c, Vector3.new(f.w / 2 - 0.1, f.h, f.d), "Hay")
			for _, t in { -0.25, 0.25 } do
				part(
					sec,
					ctx,
					"Twine",
					c * CFrame.new(t * f.w / 2, 0, 0),
					Vector3.new(0.12, f.h + 0.04, f.d + 0.04),
					"Stairs"
				)
			end
		end
	end
end

local function pew(sec: Instance, ctx: any, at: CFrame, f: any, w: number, d: number)
	part(sec, ctx, "Seat", at * CFrame.new(0, f.seat, 0), Vector3.new(w, 0.3, d * 0.55), "Wood")
	part(
		sec,
		ctx,
		"Back",
		at * CFrame.new(0, (f.seat + f.h) / 2, d / 2 - 0.2),
		Vector3.new(w, f.h - f.seat, 0.3),
		"Wood"
	)
	for _, sx in { -1, 1 } do
		part(sec, ctx, "End", at * CFrame.new(sx * (w / 2 - 0.15), f.h / 2, 0), Vector3.new(0.3, f.h, d), "Stairs")
	end
end

local function barrels(sec: Instance, ctx: any, at: CFrame, f: any, count: number)
	for i = 1, count do
		local x = (i - (count + 1) / 2) * (2 * f.r + f.gap)
		local c = at * CFrame.new(x, f.h / 2, 0)
		post(sec, ctx, "Barrel", c, f.h, 2 * f.r, "Wood")
		for _, y in { -0.32, 0.32 } do
			post(sec, ctx, "Hoop", c * CFrame.new(0, y * f.h, 0), 0.2, 2 * f.r + 0.12, "Metal")
		end
		post(sec, ctx, "Lid", c * CFrame.new(0, f.h / 2 + 0.03, 0), 0.06, 2 * f.r - 0.3, "Stairs")
	end
end

-- a linear piece from a to b: a frame on the floor at its middle, its x along a->b
local function linear(sec: Instance, ctx: any, p: any, f: any, y: number, H: number)
	local a, b = Vector3.new(p.a[1], y, p.a[2]), Vector3.new(p.b[1], y, p.b[2])
	local L = (b - a).Magnitude
	local at = CFrame.fromMatrix((a + b) / 2, (b - a).Unit, Vector3.yAxis)
	local d = p.d or f.d
	local h = math.min(p.h or f.h, H)
	if p.kind == "Counter" then
		part(sec, ctx, "Top", at * CFrame.new(0, h - f.top / 2, 0), Vector3.new(L, f.top, d + 0.4), "Wood")
		part(
			sec,
			ctx,
			"Body",
			at * CFrame.new(0, (h - f.top) / 2, 0),
			Vector3.new(L - 0.3, h - f.top, d - 0.3),
			"Stairs"
		)
		-- boarded front with battens, and a brass foot rail
		for x = -L / 2 + 1, L / 2 - 1, 2 do
			part(
				sec,
				ctx,
				"Batten",
				at * CFrame.new(x, (h - f.top) / 2, -d / 2),
				Vector3.new(0.3, h - f.top - 0.4, 0.2),
				"Wood"
			)
		end
		post(
			sec,
			ctx,
			"FootRail",
			at * CFrame.new(0, 0.6, -d / 2 - 0.5) * CFrame.Angles(0, 0, math.pi / 2),
			L - 0.6,
			0.25,
			"Metal"
		)
	elseif p.kind == "Shelf" then
		for _, x in { -L / 2 + f.post / 2, L / 2 - f.post / 2 } do
			part(sec, ctx, "Upright", at * CFrame.new(x, h / 2, 0), Vector3.new(f.post, h, d), "Stairs")
		end
		part(sec, ctx, "Back", at * CFrame.new(0, h / 2, d / 2 - 0.1), Vector3.new(L, h, 0.2), "Stairs")
		for i = 0, f.boards - 1 do
			local by = 0.4 + i * (h - 0.6) / (f.boards - 1)
			part(sec, ctx, "Board", at * CFrame.new(0, by, 0), Vector3.new(L - 0.2, 0.25, d), "Wood")
			-- jars and boxes on the board
			if i < f.boards - 1 then
				for k = 1, math.floor(L / 2.2) do
					local jx = -L / 2 + 1 + (k - 1) * 2.2 + ((k * 7 + i * 3) % 5) * 0.12
					local jh = 0.6 + ((k + i) % 3) * 0.25
					if (k + i) % 2 == 0 then
						post(sec, ctx, "Jar", at * CFrame.new(jx, by + 0.12 + jh / 2, 0), jh, 0.7, "Quoin")
					else
						part(
							sec,
							ctx,
							"Box",
							at * CFrame.new(jx, by + 0.12 + jh / 2, 0.1),
							Vector3.new(1.1, jh, d - 0.5),
							"Wood"
						)
					end
				end
			end
		end
	else
		-- a boarded wall (a stall's side, a half wall, a room's wall): posts, planks with a gap low down, a top rail
		local postEvery = 4
		local n = math.max(1, math.ceil(L / postEvery))
		for i = 0, n do
			local x = -L / 2 + i * L / n
			part(sec, ctx, "Post", at * CFrame.new(x, h / 2, 0), Vector3.new(0.6, h, d + 0.2), "Stairs")
		end
		local planks = math.max(2, math.floor(h / 1.3))
		for k = 0, planks - 1 do
			local py = 0.5 + k * (h - 0.8) / planks + (h - 0.8) / planks / 2
			part(
				sec,
				ctx,
				"Plank",
				at * CFrame.new(0, py, 0),
				Vector3.new(L, (h - 0.8) / planks - 0.12, d - 0.1),
				"Wood"
			)
		end
		part(sec, ctx, "Rail", at * CFrame.new(0, h - 0.2, 0), Vector3.new(L + 0.2, 0.4, d + 0.3), "Stairs")
	end
end

-- builds the block's `interior` into `model` (the block's own frame); floorTop = its ground floor's top, H its story
function Interior.build(model: Instance, ctx: any, t: any, floorTop: number, H: number)
	local F = ctx.B.Furniture
	for i, p in t.interior or {} do
		local story = p.story or 0
		local y = floorTop + story * H
		local f = F[p.kind]
		assert(f, `unknown furniture {p.kind}`)
		local sec = Geometry.section(model, ctx, "Furniture", if p.kind == "Pillar" then "Stone" else "Wood", story)
		sec.Name = `{p.kind}{i}`
		if p.a then
			linear(sec, ctx, p, f, y, H)
		else
			local at = CFrame.new(p.x, y, p.z) * CFrame.Angles(0, math.rad(p.yaw or 0), 0)
			local w, d = p.w or f.w, p.d or f.d
			if p.kind == "Table" then
				table_(sec, ctx, at, f, w, d)
			elseif p.kind == "Bench" then
				bench(sec, ctx, at, f, w, d)
			elseif p.kind == "Bed" then
				bed(sec, ctx, at, f, w, d)
			elseif p.kind == "Hearth" then
				hearth(sec, ctx, at, f, w, d)
			elseif p.kind == "Pillar" then
				pillar(sec, ctx, at, f, H)
			elseif p.kind == "HayBales" then
				hay(sec, ctx, at, f, p.levels or f.levels)
			elseif p.kind == "Pew" then
				pew(sec, ctx, at, f, w, d)
			elseif p.kind == "Barrels" then
				barrels(sec, ctx, at, f, p.count or f.count)
			else
				error(`no builder for furniture {p.kind}`)
			end
		end
	end
end

return Interior
