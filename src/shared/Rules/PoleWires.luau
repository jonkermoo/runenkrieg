--!strict
-- The telegraph wires' spans (src/server/PoleWires; user 2026-11-03: "make sure the telephone pole wires disappear
-- too"): the map's wire is loose straight segments (src/dev/Props.wire), each span between two poles a run of them end
-- to end. Points are plain { x, y, z }.

local PoleWires = {}

export type Point = { number }
export type Segment = { a: Point, b: Point }
export type Span = { members: { number }, a: Point, b: Point }

local function key(p: Point, eps: number): string
	return `{math.round(p[1] / eps)},{math.round(p[2] / eps)},{math.round(p[3] / eps)}`
end

-- The spans the segments make: runs joined end to end (ends within `eps` studs are the same point), never through one
-- of the `stops` (the poles' insulators: the spans either side of a pole meet there), each with its segments' indices
-- and its two ends (a ring has none: its first point both ends).
function PoleWires.spans(segs: { Segment }, eps: number, stops: { Point }): { Span }
	local stop: { [string]: boolean } = {}
	for _, p in stops do
		stop[key(p, eps)] = true
	end
	local at: { [string]: { number } } = {}
	for i, s in segs do
		for _, p in { s.a, s.b } do
			local k = key(p, eps)
			at[k] = at[k] or {}
			table.insert(at[k], i)
		end
	end
	local seen: { [number]: boolean } = {}
	local out: { Span } = {}
	for i in segs do
		if seen[i] then
			continue
		end
		local members, ends = {}, {}
		local stack = { i }
		seen[i] = true
		while #stack > 0 do
			local j = table.remove(stack) :: number
			table.insert(members, j)
			for _, p in { segs[j].a, segs[j].b } do
				local k = key(p, eps)
				local here = at[k]
				if #here == 1 or stop[k] then
					table.insert(ends, p)
					continue
				end
				for _, n in here do
					if not seen[n] then
						seen[n] = true
						table.insert(stack, n)
					end
				end
			end
		end
		table.sort(members)
		local a = ends[1] or segs[i].a
		table.insert(out, { members = members, a = a, b = ends[2] or a })
	end
	return out
end

-- Whether a span's end at `p` still hangs from a pole: an insulator point within `reach` studs.
function PoleWires.held(p: Point, points: { Point }, reach: number): boolean
	for _, q in points do
		local dx, dy, dz = p[1] - q[1], p[2] - q[2], p[3] - q[3]
		if dx * dx + dy * dy + dz * dz <= reach * reach then
			return true
		end
	end
	return false
end

return PoleWires
