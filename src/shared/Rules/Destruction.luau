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

-- A flying debris chunk (Config/Destruction.Debris.Rest) moving slower than `still` studs/s and turning slower than
-- `spin` rad/s for `time` s is at rest and freezes; one still moving after `maxFly` s freezes anyway. Returns how long
-- it has been still and whether to freeze it now.
function Destruction.rested(
	speed: number,
	spin: number,
	stillFor: number,
	flying: number,
	dt: number,
	r: { still: number, spin: number, time: number, maxFly: number }
): (number, boolean)
	stillFor = if speed <= r.still and spin <= r.spin then stillFor + dt else 0
	return stillFor, stillFor >= r.time or flying >= r.maxFly
end

-- Whether a frozen chunk `dx, dy, dz` studs from the centre of something gone (`radius` its bounding radius) may have
-- rested on it: within `radius` + `margin` of it and not below its bottom. Such a chunk wakes and falls again.
function Destruction.leanedOn(dx: number, dy: number, dz: number, radius: number, margin: number): boolean
	return dy >= -radius and dx * dx + dy * dy + dz * dz <= (radius + margin) ^ 2
end

-- Support (user 2026-10-23: "anything not supported should fall"): `n` pieces, `links[i]` the pieces touching piece i,
-- `grounded[i]` true for a piece on the ground. Returns the pieces with no chain of touching pieces to the ground.
function Destruction.unsupported(n: number, links: { { number } }, grounded: { [number]: boolean }): { number }
	local seen: { [number]: boolean } = {}
	local queue = {}
	for i = 1, n do
		if grounded[i] then
			seen[i] = true
			table.insert(queue, i)
		end
	end
	local head = 1
	while head <= #queue do
		for _, j in links[queue[head]] or {} do
			if not seen[j] then
				seen[j] = true
				table.insert(queue, j)
			end
		end
		head += 1
	end
	local out = {}
	for i = 1, n do
		if not seen[i] then
			table.insert(out, i)
		end
	end
	return out
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
