--!strict
-- Loading a whole map (Config/JoinLoading, src/client/MapLoader, src/server/MapFocus): where to stream it in, where the
-- server holds it, how far along it is and when it counts as loaded.
--   JoinLoading.spots(bounds, points, spacing) -> { { x, z } }: the middle of each cell of a grid over the bounds,
--     no cell wider or deeper than `spacing`, then each point ({ x, z }) not already within half `spacing` of one.
--   JoinLoading.foci(bounds, margin, radius) -> { { x, z } }: the replication foci holding the bounds grown by
--     `margin`: the middle of each cell of a grid whose cells fit inside a circle of `radius` (side radius * √2).
--   JoinLoading.progress(done, total) -> 0..1 (nothing to do: done).
--   JoinLoading.held(held, parts, share) -> boolean: this client holds enough of the server's parts (no count: yes).
--   JoinLoading.status(progress) -> the words under the name ("Loading the front · 42%").

local JoinLoading = {}

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

local function grid(minX: number, maxX: number, minZ: number, maxZ: number, cell: number): { { number } }
	local w, d = maxX - minX, maxZ - minZ
	local nx, nz = math.max(1, math.ceil(w / cell)), math.max(1, math.ceil(d / cell))
	local out = {}
	for i = 1, nx do
		for j = 1, nz do
			table.insert(out, { minX + (i - 0.5) * w / nx, minZ + (j - 0.5) * d / nz })
		end
	end
	return out
end

function JoinLoading.spots(bounds: Rect, points: { { number } }, spacing: number): { { number } }
	local out = grid(bounds.minX, bounds.maxX, bounds.minZ, bounds.maxZ, spacing)
	for _, p in points do
		local near = false
		for _, o in out do
			if math.abs(o[1] - p[1]) <= spacing / 2 and math.abs(o[2] - p[2]) <= spacing / 2 then
				near = true
				break
			end
		end
		if not near then
			table.insert(out, { p[1], p[2] })
		end
	end
	return out
end

function JoinLoading.foci(bounds: Rect, margin: number, radius: number): { { number } }
	return grid(
		bounds.minX - margin,
		bounds.maxX + margin,
		bounds.minZ - margin,
		bounds.maxZ + margin,
		radius * math.sqrt(2)
	)
end

function JoinLoading.progress(done: number, total: number): number
	if total <= 0 then
		return 1
	end
	return math.clamp(done / total, 0, 1)
end

function JoinLoading.held(held: number, parts: number?, share: number): boolean
	if type(parts) ~= "number" or parts <= 0 then
		return true
	end
	return held >= parts * share
end

function JoinLoading.status(progress: number): string
	return `Loading the front · {math.floor(math.clamp(progress, 0, 1) * 100)}%`
end

return JoinLoading
