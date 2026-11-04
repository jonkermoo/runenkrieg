--!strict
-- Pure: the spots inside a building a soldier could use, from its wall pieces (src/server/Indoors reads them off the
-- built model: src/dev/Buildings), a doorway's way through, and the door reach rule. Points are plain {x, y, z};
-- numbers from Config/Indoors.Spots.

local Indoors = {}

export type P = { x: number, y: number, z: number }
-- one wall section, one story: `at` on the wall's centre line at floor level, in the middle of the piece (of its
-- opening, for a window or a door); `out` the flat unit normal out of the building
export type Piece = {
	kind: "window" | "door" | "solid",
	at: P,
	out: P,
	width: number, -- the opening's clear width, or the solid piece's length
	thick: number, -- the wall's thickness
	story: number,
}
export type Kind = "Window" | "Doorway" | "Cover"
-- where to stand (floor level) and which way to face (flat unit)
export type Spot = { kind: Kind, at: P, face: P, story: number }

local function p(x: number, y: number, z: number): P
	return { x = x, y = y, z = z }
end

local function add(a: P, b: P, k: number): P
	return p(a.x + b.x * k, a.y + b.y * k, a.z + b.z * k)
end

function Indoors.distance(a: P, b: P): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- along the wall (out turned a quarter about up)
local function along(out: P): P
	return p(-out.z, 0, out.x)
end

-- a point `stand` in from the piece's inner face, `offset` along the wall
local function inside(w: Piece, stand: number, offset: number): P
	return add(add(w.at, w.out, -(w.thick / 2 + stand)), along(w.out), offset)
end

-- Spots from a building's pieces: one at each window (stood back inside it), three at each doorway (in it, and either
-- side of it inside), and one behind each solid piece at least coverWidth long, all facing out; no cover spot within
-- `spacing` of a spot kept before it (windows and doorways are always kept). In the pieces' order, so the same
-- building always gives the same list.
function Indoors.spots(pieces: { Piece }, cfg: any): { Spot }
	local out: { Spot } = {}
	for _, w in pieces do
		if w.kind == "window" then
			table.insert(out, { kind = "Window", at = inside(w, cfg.stand, 0), face = w.out, story = w.story })
		elseif w.kind == "door" then
			local s = w.width / 2 + cfg.side
			for _, offset in { 0, -s, s } do
				table.insert(
					out,
					{ kind = "Doorway", at = inside(w, cfg.stand, offset), face = w.out, story = w.story }
				)
			end
		end
	end
	for _, w in pieces do
		if w.kind == "solid" and w.width >= cfg.coverWidth then
			local at = inside(w, cfg.stand, 0)
			local clear = true
			for _, o in out do
				if Indoors.distance(o.at, at) < cfg.spacing then
					clear = false
					break
				end
			end
			if clear then
				table.insert(out, { kind = "Cover", at = at, face = w.out, story = w.story })
			end
		end
	end
	return out
end

-- A doorway's way through (Config/Indoors.Links): the points `approach` out from its outer face and in from its inner
-- face, at floor level (the server drops the outside one onto the ground).
function Indoors.passage(door: Piece, links: any): (P, P)
	local d = door.thick / 2 + links.approach
	return add(door.at, door.out, d), add(door.at, door.out, -d)
end

-- A flight of stairs' way up (Config/Indoors.Links): `foot` the middle of its lowest step at floor level, `top` the
-- middle of its highest step's top, `up` the flat unit way it climbs, `room` the flat unit from it into the room, `width`
-- across it, `run` a step's depth. Returns the floor point beside its foot and the point just beyond its top step, and
-- the top step itself (for when there's no room beyond it: a tower's flights run wall to wall).
function Indoors.flight(foot: P, top: P, up: P, room: P, width: number, run: number, links: any): (P, P, P)
	local low = add(add(foot, up, links.up), room, width / 2 + links.out)
	return low, add(top, up, run / 2 + links.past), top
end

-- Whether a spot by doorway `door` is behind its door when open: the door swings into the room about its hinge
-- (`hinge`, on the doorway's edge), so a spot past that edge, along the wall, is shut in behind the open door
-- (user 2026-11-04 play test: "AI often get stuck in houses ... opening the door breaks their path finding").
function Indoors.behindDoor(door: Piece, hinge: P, at: P): boolean
	local a = along(door.out)
	local function offset(q: P): number
		return (q.x - door.at.x) * a.x + (q.z - door.at.z) * a.z
	end
	local h, s = offset(hinge), offset(at)
	return math.abs(s) > door.width / 2 and h * s > 0
end

-- The door prompt's rule for anyone: within `reach` studs of the door's panel.
function Indoors.reaches(from: P, panel: P, reach: number): boolean
	return Indoors.distance(from, panel) <= reach
end

-- The index of the point nearest `at` within `within` studs, or nil.
function Indoors.nearest(points: { P }, at: P, within: number): number?
	local best, bestD = nil, within
	for i, q in points do
		local d = Indoors.distance(q, at)
		if d <= bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- The spots within `within` of `at` (of one kind, if given), nearest first.
function Indoors.near(spots: { Spot }, at: P, within: number, kind: Kind?): { Spot }
	local found: { { spot: Spot, d: number } } = {}
	for _, s in spots do
		if kind == nil or s.kind == kind then
			local d = Indoors.distance(s.at, at)
			if d <= within then
				table.insert(found, { spot = s, d = d })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for i, f in found do
		out[i] = f.spot
	end
	return out
end

return Indoors
