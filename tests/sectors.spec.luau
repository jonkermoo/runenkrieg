--!strict
-- Frontline sectors on Map 1 (Rules/Sectors, Config/Sectors, the map's sectors and dividers): the dividers split the
-- map into the sector chain, each point is in its own sector, and neither side gets the better of a point or a divider.
local B = require("../src/shared/Config/Buildings")
local Cfg = require("../src/shared/Config/Sectors")
local Check = require("../src/shared/Rules/MapCheck")
local MT = require("../src/shared/Rules/MapTerrain")
local P = require("../src/shared/Config/Props")
local R = require("../src/shared/Rules/Sectors")
local S = require("./mapgrid")
local V = require("../src/shared/Rules/Village")

local g, map, M = S.grid, S.map, S.metrics
local L = S.cfg.Sectors
local SEG = Cfg.Divider.RiverSegments

local function path(d: any): { { number } }
	return R.path(map, MT, d, SEG)
end

-- the walk from every cell to a sector's point (studs)
local toPoint: { [string]: { [number]: number } } = {}
local function field(id: string): { [number]: number }
	if not toPoint[id] then
		for _, s in map.sectors do
			if s.id == id then
				local c = g.cell * 1.5
				toPoint[id] = Check.walk(
					g,
					Check.cellsIn(g, { minX = s.x - c, maxX = s.x + c, minZ = s.z - c, maxZ = s.z + c }),
					true
				)
			end
		end
	end
	return toPoint[id]
end

local function sprint(studs: number): number
	return studs / M.Movement.SprintSpeed
end

return {
	["one divider between each pair of neighbouring sectors, west to east"] = function()
		assert(#map.dividers == #map.sectors - 1, `{#map.dividers} dividers for {#map.sectors} sectors`)
		for i, d in map.dividers do
			assert(d.between[1] == map.sectors[i].id and d.between[2] == map.sectors[i + 1].id, `divider {i} order`)
		end
	end,
	["each divider runs south to north across the whole map, inside it"] = function()
		local b = map.bounds
		for _, d in map.dividers do
			local p = path(d)
			assert(p[1][2] == b.minZ and p[#p][2] == b.maxZ, `{d.between[1]}|{d.between[2]} doesn't span the map`)
			for i, q in p do
				assert(q[1] > b.minX and q[1] < b.maxX, "a divider point outside the bounds")
				assert(i == 1 or q[2] > p[i - 1][2], "a divider turns back south")
			end
		end
	end,
	["dividers never touch each other"] = function()
		local b = map.bounds
		for z = b.minZ, b.maxZ, 2 do
			local last = -math.huge
			for _, d in map.dividers do
				local x = R.xAt(path(d), z) :: number
				assert(x - last > Cfg.Divider.Thickness, `dividers meet at z={z}`)
				last = x
			end
		end
	end,
	["every capture zone lies wholly in its own sector"] = function()
		for _, s in map.sectors do
			for k = 0, 15 do
				local a = k * math.pi / 8
				local x, z = s.x + math.cos(a) * s.radius, s.z + math.sin(a) * s.radius
				z = math.clamp(z, map.bounds.minZ, map.bounds.maxZ)
				local id = R.sectorAt(map, MT, x, z, SEG)
				assert(id == s.id, `{s.id}'s zone reaches into {id}`)
			end
			assert(R.sectorAt(map, MT, s.x, s.z, SEG) == s.id)
		end
	end,
	["no divider cuts through a house"] = function()
		local layout = V.layout(map, B, M, MT, P)
		for _, d in map.dividers do
			local p = path(d)
			for _, l in layout.lots do
				local q = V.corners(l, 0)
				local z0, z1 = math.huge, -math.huge
				for _, c in q do
					z0, z1 = math.min(z0, c[2]), math.max(z1, c[2])
				end
				for z = math.ceil(z0), math.floor(z1) do
					local x = R.xAt(p, z) :: number
					local inside, j = false, #q
					for i = 1, #q do
						local a, c = q[i], q[j]
						if (a[2] > z) ~= (c[2] > z) and x < (c[1] - a[1]) * (z - a[2]) / (c[2] - a[2]) + a[1] then
							inside = not inside
						end
						j = i
					end
					assert(not inside, `{d.between[1]}|{d.between[2]} cuts a house at ({x}, {z})`)
				end
			end
		end
	end,
	["fair points: the same sprint to a point from the neighbouring point on each side"] = function()
		for i = 2, #map.sectors - 1 do
			local s = map.sectors[i]
			local c = Check.cellAt(g, s.x, s.z) :: number
			local a, b = field(map.sectors[i - 1].id)[c], field(map.sectors[i + 1].id)[c]
			assert(a and b, `{s.id} can't be reached from its neighbours`)
			local gap = math.abs(sprint(a) - sprint(b))
			assert(gap <= L.point, string.format("%s favours one side by %.1f s", s.id, gap))
		end
	end,
	["fair dividers: on average the same sprint to the two points from along it"] = function()
		local b = map.bounds
		for _, d in map.dividers do
			if not d.river then
				local fa, fb = field(d.between[1]), field(d.between[2])
				local p = path(d)
				local sum, n = 0, 0
				for z = b.minZ, b.maxZ, L.step do
					local c = Check.cellAt(g, R.xAt(p, z) :: number, z) :: number
					if fa[c] and fb[c] then
						sum += sprint(fa[c]) - sprint(fb[c])
						n += 1
					end
				end
				local mean = sum / n
				assert(
					math.abs(mean) <= L.divider,
					string.format("%s|%s favours one side by %.2f s", d.between[1], d.between[2], mean)
				)
			end
		end
	end,
	["pieces: each under the 2048-stud part limit, bends closed"] = function()
		for _, d in map.dividers do
			local p = path(d)
			local pieces = R.pieces(p, Cfg.Divider.Thickness)
			assert(#pieces == #p - 1)
			for i, q in pieces do
				assert(q.length < 2048)
				local ex, ez = q.x + q.dx * (q.length / 2), q.z + q.dz * (q.length / 2)
				assert((ex - p[i + 1][1]) ^ 2 + (ez - p[i + 1][2]) ^ 2 >= 0.24, "a piece stops short of its bend")
			end
		end
	end,
	["sectorAt and xAt: the chain in order along the front"] = function()
		local last = 0
		for x = map.bounds.minX + 1, map.bounds.maxX - 1, 10 do
			local id = R.sectorAt(map, MT, x, 0, SEG)
			local k
			for i, s in map.sectors do
				if s.id == id then
					k = i
				end
			end
			assert(k >= last, "sectors out of order along the front")
			last = k
		end
		assert(last == #map.sectors)
		assert(R.xAt({ { 0, 0 }, { 10, 10 } }, 5) == 5 and R.xAt({ { 0, 0 }, { 10, 10 } }, 11) == nil)
	end,
	["config sane"] = function()
		local D, Mk = Cfg.Divider, Cfg.Marker
		assert(D.BottomY < D.TopY and D.Thickness > 0 and D.RiverSegments >= 4)
		assert(D.EditTransparency < 1 and Mk.EditTransparency < 1)
		for _, owner in { "West", "East", "Neutral" } do
			assert(Mk.ColorRGB[owner], `no marker colour for {owner}`)
		end
	end,
}
