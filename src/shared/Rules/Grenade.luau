--!strict
-- A thrown grenade's maths (Config/Grenades; src/server/Grenades, src/client/Grenades): the throw's velocity from the
-- look, the path it flies (the arc preview and the server's throw agree), and its fragments' damage by distance.
-- Plain numbers (x, y, z), so Lune can test it.

local Grenade = {}

export type Fragments = { lethal: number, wound: number, max: number, near: number, far: number }

-- The launch velocity: the look direction (any length) lifted `loft` degrees toward straight up, at `speed`.
function Grenade.launch(lx: number, ly: number, lz: number, loft: number, speed: number): (number, number, number)
	local flat = math.sqrt(lx * lx + lz * lz)
	local pitch = math.atan2(ly, flat) + math.rad(loft)
	pitch = math.min(pitch, math.rad(89))
	local hx, hz = 0, 0
	if flat > 1e-6 then
		hx, hz = lx / flat, lz / flat
	end
	local c = math.cos(pitch)
	return hx * c * speed, math.sin(pitch) * speed, hz * c * speed
end

-- The hand it leaves from: `from` (right, up, back: camera space) in a frame looking along (lx, ly, lz) from the head
-- at (hx, hy, hz): the camera's own frame (right = look x up, up = right x look), which the server can rebuild.
function Grenade.hand(
	hx: number,
	hy: number,
	hz: number,
	lx: number,
	ly: number,
	lz: number,
	from: { number }
): (number, number, number)
	local m = math.sqrt(lx * lx + ly * ly + lz * lz)
	lx, ly, lz = lx / m, ly / m, lz / m
	-- right = look x (0, 1, 0)
	local rx, rz = -lz, lx
	local rm = math.sqrt(rx * rx + rz * rz)
	if rm < 1e-3 then
		rx, rz, rm = 1, 0, 1
	end
	rx, rz = rx / rm, rz / rm
	-- up = right x look
	local ux, uy, uz = -rz * ly, rz * lx - rx * lz, rx * ly
	local f1, f2, f3 = from[1], from[2], from[3]
	return hx + rx * f1 + ux * f2 - lx * f3, hy + uy * f2 - ly * f3, hz + rz * f1 + uz * f2 - lz * f3
end

-- The throw's start: the hand, or `gap` short of whatever lies between the head and the hand (`blocked`: how far from
-- the head, along the line to the hand, the first thing is; nil = clear). Returns the share of the way to the hand.
function Grenade.clearShare(toHand: number, blocked: number?, gap: number): number
	if not blocked or blocked >= toHand or toHand <= 1e-6 then
		return 1
	end
	return math.max(blocked - gap, 0) / toHand
end

-- Where it is `t` seconds after leaving (ox, oy, oz) at velocity (vx, vy, vz) under `gravity` (no drag).
function Grenade.at(
	t: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	gravity: number
): (number, number, number)
	return ox + vx * t, oy + vy * t - gravity * t * t / 2, oz + vz * t
end

-- How far it lands on level ground thrown at `degrees` above level.
function Grenade.range(speed: number, degrees: number, gravity: number): number
	return speed * speed * math.sin(math.rad(2 * degrees)) / gravity
end

-- The fragments' damage at `d` studs before cover: `max` within `lethal`, then `near` falling to `far` at `wound`,
-- none beyond.
function Grenade.fragments(d: number, f: Fragments): number
	if d <= f.lethal then
		return f.max
	elseif d > f.wound then
		return 0
	end
	local k = (d - f.lethal) / (f.wound - f.lethal)
	return f.near + (f.far - f.near) * k
end

-- The server's check of a throw: the direction must be a real one and the hand near the head.
function Grenade.throwOk(dx: number, dy: number, dz: number, fromHead: number, reach: number): boolean
	local m = math.sqrt(dx * dx + dy * dy + dz * dz)
	return m == m and m > 1e-3 and m < 1e6 and fromHead == fromHead and fromHead <= reach
end

return Grenade
