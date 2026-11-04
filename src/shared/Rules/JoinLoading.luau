--!strict
-- The join's loading screen (Config/JoinLoading, src/client/Menus): where to stream the map in and how far along it is.
--   JoinLoading.spots(bounds, points, spacing) -> { { x, z } }: the middle of each cell of a grid over the bounds,
--     no cell wider or deeper than `spacing`, then each point ({ x, z }) not already within half `spacing` of one.
--   JoinLoading.progress(done, total) -> 0..1 (nothing to do: done).
--   JoinLoading.status(progress) -> the words under the name ("Loading the front · 42%").

local JoinLoading = {}

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

function JoinLoading.spots(bounds: Rect, points: { { number } }, spacing: number): { { number } }
	local w, d = bounds.maxX - bounds.minX, bounds.maxZ - bounds.minZ
	local nx, nz = math.max(1, math.ceil(w / spacing)), math.max(1, math.ceil(d / spacing))
	local out = {}
	for i = 1, nx do
		for j = 1, nz do
			table.insert(out, { bounds.minX + (i - 0.5) * w / nx, bounds.minZ + (j - 0.5) * d / nz })
		end
	end
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

function JoinLoading.progress(done: number, total: number): number
	if total <= 0 then
		return 1
	end
	return math.clamp(done / total, 0, 1)
end

function JoinLoading.status(progress: number): string
	return `Loading the front · {math.floor(math.clamp(progress, 0, 1) * 100)}%`
end

return JoinLoading
