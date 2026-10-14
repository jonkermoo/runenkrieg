--!strict
-- Pure, deterministic grass tuft candidates per chunk. The client then raycasts each candidate onto
-- the terrain for its exact height and material. A tuft's identity depends only on its cell, so
-- raising the quality only ADDS tufts (lower levels are subsets of higher ones).

local Grass = {}

-- 32-bit integer hash -> [0, 1). Same scheme as MapTerrain.hash01 (kept local: Rules modules don't
-- require each other, so they work in both Lune and Roblox).
local function mul32(a: number, b: number): number
	a, b = a % 4294967296, b % 4294967296
	local hi, lo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	return ((hi * b % 65536) * 65536 + lo * b) % 4294967296
end

local function hash01(a: number, b: number, c: number): number
	local h = bit32.bxor(mul32(a, 374761393), mul32(b, 668265263), mul32(c, 2246822519))
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 1274126177)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

export type Tuft = { x: number, z: number, variant: number, scale: number, yaw: number, shade: number }

-- Tufts for chunk (cx, cz) at a given density (0..1). `cfg.Salt` (optional) gives a layer its own cells.
function Grass.chunk(cx: number, cz: number, density: number, cfg: any): { Tuft }
	local out: { Tuft } = {}
	if density <= 0 then
		return out
	end
	local n = math.floor(cfg.ChunkSize / cfg.Cell)
	local x0, z0 = cx * cfg.ChunkSize, cz * cfg.ChunkSize
	local salt = cfg.Salt or 0
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local gx, gz = cx * n + i, cz * n + j -- global cell ids
			if hash01(gx, gz, 101 + salt) < density then
				local s = cfg.ScaleRange
				table.insert(out, {
					x = x0 + (i + 0.1 + 0.8 * hash01(gx, gz, 102 + salt)) * cfg.Cell,
					z = z0 + (j + 0.1 + 0.8 * hash01(gx, gz, 103 + salt)) * cfg.Cell,
					variant = math.floor(hash01(gx, gz, 104 + salt) * 1000),
					scale = s[1] + (s[2] - s[1]) * hash01(gx, gz, 105 + salt),
					yaw = hash01(gx, gz, 106 + salt) * 360,
					shade = math.floor(hash01(gx, gz, 107 + salt) * 1000),
				})
			end
		end
	end
	return out
end

-- Chunks within radius of (x, z), nearest first.
function Grass.chunksAround(x: number, z: number, radius: number, size: number): { { number } }
	local out = {}
	if radius <= 0 then
		return out
	end
	local r = math.ceil(radius / size)
	local ccx, ccz = math.floor(x / size), math.floor(z / size)
	for i = ccx - r, ccx + r do
		for j = ccz - r, ccz + r do
			local mx, mz = (i + 0.5) * size, (j + 0.5) * size
			local d = math.sqrt((mx - x) ^ 2 + (mz - z) ^ 2)
			if d <= radius + size * 0.71 then
				table.insert(out, { i, j, d })
			end
		end
	end
	table.sort(out, function(a, b)
		return a[3] < b[3]
	end)
	return out
end

return Grass
