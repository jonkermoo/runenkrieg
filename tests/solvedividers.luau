--!strict
-- Solves a frontline map's dividers over its real ground (MAP_RULES §1: "Re-solve the dividers whenever the ground or a
-- point moves"): for each pair of neighbouring points, row by row from the south edge to the north, the spot where the
-- walk to the two points is equal (the map checker's walk grid: ground, river, trees, buildings). Prints each divider's
-- points in the map file's local studs, to paste over its `dividers`.
--   lune run tests/solvedividers <MapName> [rowStep] [middleZ]
local process = require("@lune/process")
local Check = require("../src/shared/Rules/MapCheck")
local grid = require("./mapgrid")

local name = process.args[1] or "LanternMeadows"
local step = tonumber(process.args[2]) or 70
local CZ = tonumber(process.args[3]) or 0
local map = (require :: any)(`../src/shared/Config/Maps/{name}`)
local S = grid(map)
local g = S.grid

local function field(s: any): { [number]: number }
	local c = g.cell * 1.5
	return Check.walk(g, Check.cellsIn(g, { minX = s.x - c, maxX = s.x + c, minZ = s.z - c, maxZ = s.z + c }), true)
end

local b = map.bounds
for k = 1, #map.sectors - 1 do
	local A, B = map.sectors[k], map.sectors[k + 1]
	local fa, fb = field(A), field(B)
	-- the straight bisector, the guess each row starts from
	local mx, mz = (A.x + B.x) / 2, (A.z + B.z) / 2
	local dx, dz = B.x - A.x, B.z - A.z
	local rows = {}
	local z = b.minZ
	while true do
		local guess = mx - (z - mz) * dz / dx
		local best, bestX = math.huge, guess
		for x = guess - 160, guess + 160, 3 do
			local c = Check.cellAt(g, x, z)
			if c and fa[c] and fb[c] then
				local gap = math.abs(fa[c] - fb[c])
				if gap < best or (math.abs(gap - best) < 1 and math.abs(x - guess) < math.abs(bestX - guess)) then
					best, bestX = gap, x
				end
			end
		end
		table.insert(rows, { math.round(bestX), z })
		if z >= b.maxZ then
			break
		end
		z = math.min(z + step, b.maxZ)
	end
	-- no row may turn back south (they don't), nor jump: smooth single outliers
	for i = 2, #rows - 1 do
		local avg = (rows[i - 1][1] + rows[i + 1][1]) / 2
		if math.abs(rows[i][1] - avg) > 40 then
			rows[i][1] = math.round(avg)
		end
	end
	-- then shift the whole divider until the mean gap along it (as tests/sectors.spec measures it) is ~0
	local R = require("../src/shared/Rules/Sectors")
	local L = S.cfg.Sectors
	for _ = 1, 4 do
		local path = {}
		for _, r in rows do
			table.insert(path, { r[1], r[2] })
		end
		local sum, n = 0, 0
		for zz = b.minZ, b.maxZ, L.step do
			local c = Check.cellAt(g, R.xAt(path, zz) :: number, zz)
			if c and fa[c] and fb[c] then
				sum += fa[c] - fb[c]
				n += 1
			end
		end
		local shift = -(sum / n) / 2 * (if dx > 0 then 1 else -1)
		for _, r in rows do
			r[1] = math.round(r[1] + shift)
		end
	end
	local parts = {}
	for _, r in rows do
		table.insert(parts, `\{ {r[1]}, {math.round(r[2] - CZ)} }`)
	end
	print(`\{ between = \{ "{A.id}", "{B.id}" }, points = points(\{ {table.concat(parts, ", ")} }) },`)
end
