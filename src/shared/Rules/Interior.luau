--!strict
-- Building interiors (a template's or a landmark block's `interior`, Config/Buildings.Furniture; built by
-- src/dev/Buildings/Interior): where each piece stands, what it keeps clear (the doors, the stairs and the holes they
-- climb through) and whether a soldier can still walk the floor between them. Pure: plain numbers and tables.
--
-- A building is in its own frame: x along its front (width), z front (-) to back (+), the floor at y 0 of each story.
-- A piece is { kind, x, z, yaw?, story?, w?, d?, h?, count?, levels? } (yaw 0/90/180/270), or a linear one
-- { kind, a = { x, z }, b = { x, z }, story?, h? } along an axis (Counter, Shelf, Partition, Stall).

local Interior = {}

export type Rect = { number } -- { x0, x1, z0, z1 }

local LINEAR = { Counter = true, Shelf = true, Partition = true, Stall = true }

function Interior.isLinear(kind: string): boolean
	return LINEAR[kind] == true
end

-- the piece's size before its yaw: width along x, depth along z
local function size(p: any, F: any): (number, number)
	local f = F[p.kind]
	assert(f, "unknown furniture " .. tostring(p.kind))
	if p.kind == "Barrels" then
		local n = p.count or f.count
		return n * 2 * f.r + (n - 1) * f.gap, 2 * f.r
	elseif p.kind == "Pillar" then
		return f.base, f.base
	end
	return p.w or f.w, p.d or f.d
end

-- its footprint on the floor (axis-aligned)
function Interior.footprint(p: any, F: any): Rect
	if LINEAR[p.kind] then
		local t = (p.d or F[p.kind].d) / 2
		local a, b = p.a, p.b
		assert(a[1] == b[1] or a[2] == b[2], `{p.kind} must run along x or z`)
		return {
			math.min(a[1], b[1]) - (if a[1] == b[1] then t else 0),
			math.max(a[1], b[1]) + (if a[1] == b[1] then t else 0),
			math.min(a[2], b[2]) - (if a[2] == b[2] then t else 0),
			math.max(a[2], b[2]) + (if a[2] == b[2] then t else 0),
		}
	end
	local w, d = size(p, F)
	local yaw = (p.yaw or 0) % 180
	assert(yaw == 0 or yaw == 90, `{p.kind} yaw must be a right angle`)
	if yaw == 90 then
		w, d = d, w
	end
	return { p.x - w / 2, p.x + w / 2, p.z - d / 2, p.z + d / 2 }
end

-- how high it stands (what a soldier must climb or hide behind); H = the story's height
function Interior.height(p: any, F: any, H: number): number
	local f = F[p.kind]
	if p.kind == "Pillar" then
		return H
	elseif p.kind == "HayBales" then
		return f.h * (p.levels or f.levels)
	elseif p.kind == "Bed" then
		return math.max(f.h, f.head)
	end
	return p.h or f.h
end

-- the stair flight from `story` up to the next (Buildings/Geometry.stairs: against the -x wall, up along +x, on the
-- back wall from even stories and the front wall from odd ones), or nil if there is none
function Interior.stairs(b: any, M: any, T: number, story: number): Rect?
	local top = b.stories - 1
	if story < 0 or story > top or (story == top and not b.climb) then
		return nil
	end
	local Bm = M.Building
	local H = b.storyHeight or Bm.StoryHeight
	local steps = math.ceil(H / Bm.StairRise)
	local x0 = -b.width / 2 + T
	local z0, z1
	if story % 2 == 1 then
		z0 = -b.depth / 2 + T
		z1 = z0 + Bm.StairWidthMin
	else
		z1 = b.depth / 2 - T
		z0 = z1 - Bm.StairWidthMin
	end
	return { x0, x0 + steps * Bm.StairRun, z0, z1 }
end

-- the block's doors on `story` (only the ground floor's here): { side, center, w }; side "front" | "back" | "left" |
-- "right", centre along that wall (front/back: x; left/right: z)
function Interior.doors(b: any, M: any, story: number): { any }
	local out = {}
	if story ~= 0 then
		return out
	end
	local Bm = M.Building
	for _, d in b.doors or { { center = 0 } } do
		table.insert(out, { side = "front", center = d.center, w = d.w or Bm.DoorWidth })
	end
	if b.backDoor then
		local list = if type(b.backDoor) == "table" then b.backDoor else { { center = 0 } }
		for _, d in list do
			-- (the back wall is built turned round: its centre is mirrored in x)
			table.insert(out, { side = "back", center = -d.center, w = d.w or Bm.DoorWidth })
		end
	end
	if b.leftDoor then
		table.insert(out, { side = "left", center = 0, w = Bm.DoorWidth })
	end
	if b.rightDoor then
		table.insert(out, { side = "right", center = 0, w = Bm.DoorWidth })
	end
	return out
end

-- the inner floor (inside the walls)
function Interior.inner(b: any, T: number): Rect
	return { -b.width / 2 + T, b.width / 2 - T, -b.depth / 2 + T, b.depth / 2 - T }
end

-- a door's clear strip just inside it, `deep` studs into the room
local function doorStrip(b: any, T: number, d: any, deep: number): Rect
	local r = Interior.inner(b, T)
	local h = d.w / 2
	if d.side == "front" then
		return { d.center - h, d.center + h, r[3], r[3] + deep }
	elseif d.side == "back" then
		return { d.center - h, d.center + h, r[4] - deep, r[4] }
	elseif d.side == "left" then
		return { r[1], r[1] + deep, d.center - h, d.center + h }
	end
	return { r[2] - deep, r[2], d.center - h, d.center + h }
end

-- where nothing may stand on `story`: inside each door, the flight up (and a landing at each end of it), the hole the
-- flight from below climbs through
function Interior.keepOuts(b: any, M: any, T: number, story: number, cfg: any): { Rect }
	local out = {}
	for _, d in Interior.doors(b, M, story) do
		local s = doorStrip(b, T, d, cfg.doorClear)
		table.insert(out, { s[1] - cfg.doorSide, s[2] + cfg.doorSide, s[3], s[4] })
	end
	for _, s in { story, story - 1 } do
		local f = Interior.stairs(b, M, T, s)
		if f then
			-- (on its own story a flight needs room to step on beside its low end; on the story above, room to step off
			-- past its top)
			local z0, z1 = f[3], f[4]
			if s == story then
				local open = if s % 2 == 1 then { z1, z1 + cfg.landing } else { z0 - cfg.landing, z0 }
				table.insert(out, { f[1], f[2], z0, z1 })
				table.insert(out, { f[1], f[1] + cfg.landing, open[1], open[2] })
			else
				table.insert(out, { f[1], f[2] + cfg.landing, z0, z1 })
			end
		end
	end
	return out
end

local function overlap(a: Rect, b: Rect, eps: number): boolean
	return a[1] < b[2] - eps and b[1] < a[2] - eps and a[3] < b[4] - eps and b[3] < a[4] - eps
end
Interior.overlap = overlap

-- Can a soldier walk this story's floor? A grid `cfg.grid` studs across over the inner floor; a cell is open when
-- nothing too high to hop (Metrics.Cover.HopableLedgeMax) nor a wall stands within `cfg.clearance` of it, and no stair
-- flight or hole covers it. From the first target (inside a door, or off the top of the stairs) the open cells are
-- flooded: returns how many open cells, how many reached, and the targets not reached (each { name, x, z }).
function Interior.walk(b: any, M: any, F: any, T: number, story: number, cfg: any): (number, number, { any })
	local H = b.storyHeight or M.Building.StoryHeight
	local r = Interior.inner(b, T)
	local g, c = cfg.grid, cfg.clearance
	local blocks: { Rect } = {}
	for _, p in b.interior or {} do
		if (p.story or 0) == story and Interior.height(p, F, H) > M.Cover.HopableLedgeMax then
			local f = Interior.footprint(p, F)
			table.insert(blocks, { f[1] - c, f[2] + c, f[3] - c, f[4] + c })
		end
	end
	for _, s in { story, story - 1 } do
		local f = Interior.stairs(b, M, T, s)
		if f then
			table.insert(blocks, { f[1] - c, f[2] + c, f[3] - c, f[4] + c })
		end
	end
	local nx, nz = math.floor((r[2] - r[1]) / g), math.floor((r[4] - r[3]) / g)
	local open: { [number]: boolean } = {}
	local count = 0
	local function key(i: number, k: number): number
		return i * 100000 + k
	end
	for i = 0, nx - 1 do
		local x = r[1] + (i + 0.5) * g
		for k = 0, nz - 1 do
			local z = r[3] + (k + 0.5) * g
			local ok = x > r[1] + c and x < r[2] - c and z > r[3] + c and z < r[4] - c
			if ok then
				for _, q in blocks do
					if x > q[1] and x < q[2] and z > q[3] and z < q[4] then
						ok = false
						break
					end
				end
			end
			if ok then
				open[key(i, k)] = true
				count += 1
			end
		end
	end
	-- the places every floor must reach
	local targets = {}
	for _, d in Interior.doors(b, M, story) do
		local s = doorStrip(b, T, d, 2 * (c + g))
		table.insert(targets, { name = `{d.side} door at {d.center}`, x = (s[1] + s[2]) / 2, z = (s[3] + s[4]) / 2 })
	end
	local up = Interior.stairs(b, M, T, story)
	if up then
		local z = if story % 2 == 1 then up[4] + c + g else up[3] - c - g
		table.insert(targets, { name = "the foot of the stairs", x = up[1] + 1, z = z })
	end
	local down = Interior.stairs(b, M, T, story - 1)
	if down then
		table.insert(targets, { name = "the top of the stairs", x = down[2] + c + g, z = (down[3] + down[4]) / 2 })
	end
	local function cellOf(x: number, z: number): (number, number)
		return math.floor((x - r[1]) / g), math.floor((z - r[3]) / g)
	end
	-- (a target counts if any open cell within a cell of it is reached)
	local function near(t: any): { number }
		local i, k = cellOf(t.x, t.z)
		local out = {}
		for di = -1, 1 do
			for dk = -1, 1 do
				if open[key(i + di, k + dk)] then
					table.insert(out, key(i + di, k + dk))
				end
			end
		end
		return out
	end
	local seen: { [number]: boolean } = {}
	local reached = 0
	local start = targets[1] and near(targets[1])[1]
	if start then
		local queue = { start }
		seen[start] = true
		local head = 1
		while head <= #queue do
			local q = queue[head]
			head += 1
			reached += 1
			local i, k = q // 100000, q % 100000
			for _, n in { key(i + 1, k), key(i - 1, k), key(i, k + 1), key(i, k - 1) } do
				if open[n] and not seen[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	local missing = {}
	for _, t in targets do
		local hit = false
		for _, n in near(t) do
			hit = hit or seen[n] == true
		end
		if not hit then
			table.insert(missing, t)
		end
	end
	return count, reached, missing
end

return Interior
