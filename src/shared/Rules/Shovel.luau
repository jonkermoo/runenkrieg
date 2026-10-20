--!strict
-- The shovel's dig maths (Config/Shovel; src/server/Shovel). Pure functions, tested in tests/shovel.spec.

local Shovel = {}

-- where the blade lands: `forward` ahead of (x, z) along the level look (lx, lz)
function Shovel.spot(x: number, z: number, lx: number, lz: number, forward: number): (number, number)
	local len = math.sqrt(lx * lx + lz * lz)
	if len < 1e-6 then
		return x, z
	end
	return x + lx / len * forward, z + lz / len * forward
end

-- how much to lower ground at height `h` whose first height was `first`: `step`, or less so it never goes deeper than
-- `max` below `first`; 0 once there
function Shovel.lower(h: number, first: number, step: number, max: number): number
	return math.clamp(h - (first - max), 0, step)
end

-- whether ground at height `h` is in reach of feet at `feet` (`above` over them, `below` under them)
function Shovel.inReach(h: number, feet: number, above: number, below: number): boolean
	return h <= feet + above and h >= feet - below
end

-- the cell key for (x, z) in `cell`-wide cells
function Shovel.cell(x: number, z: number, cell: number): string
	return `{math.floor(x / cell)},{math.floor(z / cell)}`
end

return Shovel
