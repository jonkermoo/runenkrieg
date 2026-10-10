--!strict
-- Pure wall layout: places a centered door and as many windows as fit into the free stretches of a
-- wall, never overlapping keep-out zones (corner quoins, chimney breasts) or each other, then splits
-- the wall into destructible sections. Wall-local coordinate u runs from -L/2 to L/2.

local Openings = {}

export type Opening = { kind: string, w: number, center: number, extent: number }
export type Section = { w: number, opening: Opening? }

-- cfg: { margin, post, sectionWidth }. keepOuts: { {a, b} } in wall-local u.
-- door = clear door width or nil; win = clear window width; maxWindows = cap for this wall.
function Openings.layout(
	L: number,
	keepOuts: { { number } },
	door: number?,
	win: number,
	maxWindows: number,
	cfg: any
): ({ Section }, { Opening })
	local m, post = cfg.margin, cfg.post
	local lo, hi = -L / 2, L / 2
	local blocked: { { number } } = {}
	for _, k in keepOuts do
		table.insert(blocked, { k[1] - m, k[2] + m })
	end
	local openings: { Opening } = {}
	if door then
		local ext = door + 2 * post
		table.insert(openings, { kind = "door", w = door, center = 0, extent = ext })
		table.insert(blocked, { -ext / 2 - m, ext / 2 + m })
	end
	table.sort(blocked, function(a, b)
		return a[1] < b[1]
	end)
	-- free spans between blocked intervals
	local spans: { { number } } = {}
	local cursor = lo
	for _, b in blocked do
		if b[1] > cursor then
			table.insert(spans, { cursor, math.min(b[1], hi) })
		end
		cursor = math.max(cursor, b[2])
	end
	if cursor < hi then
		table.insert(spans, { cursor, hi })
	end
	-- windows: as many as fit per span (one per side when there is a door), longest spans first
	local wext = win + 2 * post
	local perSpan = if door then 1 else maxWindows
	table.sort(spans, function(a, b)
		return (a[2] - a[1]) > (b[2] - b[1])
	end)
	local placed = 0
	for _, s in spans do
		local len = s[2] - s[1]
		local fit = math.floor((len + m) / (wext + m))
		local n = math.min(fit, perSpan, maxWindows - placed)
		for k = 1, n do
			local c = s[1] + len * (k - 0.5) / n
			table.insert(openings, { kind = "window", w = win, center = c, extent = wext })
		end
		placed += math.max(n, 0)
	end
	table.sort(openings, function(a, b)
		return a.center < b.center
	end)
	-- sections: one per opening (its extent plus half the margin each side), solid fillers between,
	-- each filler split into pieces no wider than sectionWidth
	local sections: { Section } = {}
	local function filler(a: number, b: number)
		local len = b - a
		if len <= 0.05 then
			return
		end
		local n = math.max(1, math.ceil(len / cfg.sectionWidth))
		for _ = 1, n do
			table.insert(sections, { w = len / n })
		end
	end
	cursor = lo
	for _, o in openings do
		local a = math.max(cursor, o.center - o.extent / 2 - m / 2)
		local b = math.min(hi, o.center + o.extent / 2 + m / 2)
		filler(cursor, a)
		table.insert(sections, { w = b - a, opening = o })
		cursor = b
	end
	filler(cursor, hi)
	return sections, openings
end

return Openings
