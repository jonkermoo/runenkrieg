--!strict
-- Pure destruction rules (docs/DESTRUCTION.md): blast falloff, structural collapse, color schemes.

local Destruction = {}

-- Damage at distance d from a blast of `damage` with `radius`: full at the center, 0 at the edge.
function Destruction.blastDamage(d: number, radius: number, damage: number): number
	if d >= radius then
		return 0
	end
	return damage * (1 - d / radius) ^ 1.5
end

-- counts[story] = { initial = n, standing = m } for WALL sections. Returns the lowest story whose
-- standing walls fell below `fraction` of the original (it and everything above collapse), or nil.
-- a hash in [0, 1) for a cell (ix, iy) of a broken piece and a `seed` (the ragged edge of a hole)
function Destruction.noise(ix: number, iy: number, seed: number): number
	local h = (ix * 73856093 + iy * 19349663 + seed * 83492791) % 2147483647
	h = (h * 48271) % 2147483647
	h = (h * 48271) % 2147483647
	return h / 2147483647
end

export type Run = { u0: number, u1: number, v0: number, v1: number }

-- A face `w` x `h` (u across, v up, both from its corner) cut into a grid of about `cell` studs: the cells where
-- `gone(u, v)` (at the cell's centre) is true break off, the rest stay. Each row's neighbouring cells of a kind are
-- merged into runs, so a ragged edge costs a few parts. Returns the runs kept and the runs broken.
function Destruction.jag(w: number, h: number, cell: number, gone: (number, number) -> boolean): ({ Run }, { Run })
	local nu, nv = math.max(math.ceil(w / cell - 1e-9), 1), math.max(math.ceil(h / cell - 1e-9), 1)
	local cu, cv = w / nu, h / nv
	local kept, broken = {}, {}
	for j = 0, nv - 1 do
		local start, was = 0, nil
		for i = 0, nu do
			local now = if i < nu then gone((i + 0.5) * cu, (j + 0.5) * cv) else nil
			if now ~= was then
				if was ~= nil then
					table.insert(
						if was then broken else kept,
						{ u0 = start * cu, u1 = i * cu, v0 = j * cv, v1 = (j + 1) * cv }
					)
				end
				start, was = i, now
			end
		end
	end
	return kept, broken
end

function Destruction.collapseFrom(
	counts: { [number]: { initial: number, standing: number } },
	fraction: number
): number?
	local lowest: number? = nil
	for story, c in counts do
		if c.initial > 0 and c.standing / c.initial < fraction then
			if lowest == nil or story < lowest then
				lowest = story
			end
		end
	end
	return lowest
end

export type Scheme = { wall: string, roof: string, trim: number, door: number }

-- Deterministic color scheme for one copy of a template: wall + roof keys from the template's allowed
-- lists, trim/door indices into the palette lists.
function Destruction.scheme(template: any, palette: any, seed: number): Scheme
	-- independent digits of the seed per role, so wall/roof/door choices don't move together
	seed = math.abs(math.floor(seed))
	return {
		wall = template.walls[seed % #template.walls + 1],
		roof = template.roofs[(seed // 5) % #template.roofs + 1],
		trim = (seed // 23) % #palette.Buildings.Trim + 1,
		door = (seed // 3) % #palette.Buildings.Doors + 1,
	}
end

return Destruction
