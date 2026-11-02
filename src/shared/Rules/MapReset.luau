--!strict
-- Putting the map back between matches (src/server/DevWorld) only where it changed (user 2026-11-02: "occasionally the
-- entire map refreshes"): the terrain is kept in square chunks `size` studs across (columns, full height) and only the
-- chunks a terrain write touched are pasted back; a building, section or tree is put back only when its fingerprint
-- (Rules: plain numbers) no longer matches the one saved.

local MapReset = {}

-- The chunk a point is in (x and z chunk indices).
function MapReset.chunkOf(x: number, z: number, size: number): (number, number)
	return math.floor(x / size), math.floor(z / size)
end

function MapReset.key(ix: number, iz: number): string
	return `{ix},{iz}`
end

-- The keys of every chunk a box from (x0, z0) to (x1, z1) reaches (either corner first).
function MapReset.chunksIn(x0: number, z0: number, x1: number, z1: number, size: number): { string }
	local ax, az = MapReset.chunkOf(math.min(x0, x1), math.min(z0, z1), size)
	local bx, bz = MapReset.chunkOf(math.max(x0, x1), math.max(z0, z1), size)
	local out = {}
	for ix = ax, bx do
		for iz = az, bz do
			table.insert(out, MapReset.key(ix, iz))
		end
	end
	return out
end

-- A chunk's columns in studs ({ minX, minZ, maxX, maxZ }), cut to the box it belongs to.
function MapReset.chunkRect(ix: number, iz: number, size: number, box: { number }): { number }
	return {
		math.max(ix * size, box[1]),
		math.max(iz * size, box[2]),
		math.min((ix + 1) * size, box[3]),
		math.min((iz + 1) * size, box[4]),
	}
end

-- A fingerprint of a saved thing: its piece count, the sum of its hit points, how many doors stand open and where it
-- is (to a tenth of a stud). Equal fingerprints: nothing about it changed that a reset would put back.
function MapReset.fingerprint(count: number, hp: number, open: number, x: number, y: number, z: number): string
	local function r(v: number): number
		return math.round(v * 10) / 10
	end
	return `{count}|{r(hp)}|{open}|{r(x)},{r(y)},{r(z)}`
end

return MapReset
