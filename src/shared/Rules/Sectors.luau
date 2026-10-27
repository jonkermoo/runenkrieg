--!strict
-- Frontline sectors on the ground (Config/Sectors, the map's sectors and dividers): the line each divider runs along,
-- the straight blocks it's built from, and which sector a spot is in. Pure: numbers and tables only.

local Sectors = {}

export type Piece = { x: number, z: number, dx: number, dz: number, length: number }

-- The divider's line as { x, z } points from the map's south edge to its north edge: its own points, or the river's
-- middle line in `segments` straight pieces.
function Sectors.path(map: any, MT: any, divider: any, segments: number): { { number } }
	if divider.river then
		local b, out = map.bounds, {}
		for i = 0, segments do
			local z = b.minZ + (b.maxZ - b.minZ) * i / segments
			table.insert(out, { MT.riverCenterX(map, z), z })
		end
		return out
	end
	return divider.points
end

-- The straight blocks along a path: centre, direction and length. Each is `overlap` longer than its stretch, half at
-- either end, so a bend leaves no gap.
function Sectors.pieces(path: { { number } }, overlap: number): { Piece }
	local out = {}
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		table.insert(out, {
			x = (a[1] + b[1]) / 2,
			z = (a[2] + b[2]) / 2,
			dx = dx / len,
			dz = dz / len,
			length = len + overlap,
		})
	end
	return out
end

-- Where the path crosses the line at `z` (paths run south to north, so there is one crossing); nil off its ends.
function Sectors.xAt(path: { { number } }, z: number): number?
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		if z >= a[2] and z <= b[2] then
			local t = if b[2] == a[2] then 0 else (z - a[2]) / (b[2] - a[2])
			return a[1] + (b[1] - a[1]) * t
		end
	end
	return nil
end

-- The id of the sector the spot is in: one past the dividers lying west of it (dividers run west to east in the order
-- of the sector chain).
function Sectors.sectorAt(map: any, MT: any, x: number, z: number, segments: number): string
	local k = 1
	for _, d in map.dividers do
		local dx = Sectors.xAt(Sectors.path(map, MT, d, segments), z)
		if dx and x > dx then
			k += 1
		end
	end
	return map.sectors[k].id
end

return Sectors
