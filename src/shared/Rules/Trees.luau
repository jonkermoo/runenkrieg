--!strict
-- Trees with HP (Config/Damage.Trees; user 2026-10-17): what a hit or a blast does to one, how far a felled tree tilts
-- to lie on the ground, and where a bullet's line enters a canopy's box (the leaves let bullets through; the client shows
-- falling leaves there). Pure: numbers only.

local Trees = {}

-- a tree's full HP: its kind's HP x its scale (an unknown kind: the smallest)
function Trees.maxHP(kind: string, scale: number, cfg: { HP: { [string]: number } }): number
	local hp = cfg.HP[kind]
	if not hp then
		hp = math.huge
		for _, v in cfg.HP do
			hp = math.min(hp, v)
		end
	end
	return hp * math.max(scale, 0)
end

-- a bullet's (or one pellet's) damage to a trunk by the weapon class; 0 for anything else
function Trees.shotDamage(class: string?, cfg: { Weapons: { [string]: number } }): number
	return class and cfg.Weapons[class] or 0
end

-- what a blast of `kpa` at the trunk base does: everything at `fail` (felled whole, `whole` = true), MaxHP x
-- (kpa / fail)^weaken below it
function Trees.blastDamage(kpa: number, fail: number, maxHP: number, weaken: number): (number, boolean)
	if kpa <= 0 then
		return 0, false
	end
	if kpa >= fail then
		return maxHP, true
	end
	return maxHP * (kpa / fail) ^ weaken, false
end

-- the leaves' damage from a staff beam of `stage` passing `through` the canopy or only near it
function Trees.beamLeafDamage(
	stage: number,
	through: boolean,
	leaves: { through: { number }, near: { number } }
): number
	return (if through then leaves.through[stage] else leaves.near[stage]) or 0
end

-- HP left after `amount`, and whether that fells it
function Trees.after(hp: number, amount: number): (number, boolean)
	local left = math.max(hp - math.max(amount, 0), 0)
	return left, left <= 0 and amount > 0
end

-- The tilt (degrees from upright) at which a felled tree lies on the ground without sinking into it: `samples` are
-- { x, need } pairs, `x` studs out along the fall from its hinge and `need` the height the trunk must clear there (the
-- ground's rise over the hinge plus the trunk's half thickness). The steepest need wins; clamped to [minTilt, maxTilt].
function Trees.clearTilt(samples: { { number } }, minTilt: number, maxTilt: number): number
	local tilt = maxTilt
	for _, s in samples do
		if s[1] > 0 then
			tilt = math.min(tilt, 90 - math.deg(math.atan(s[2] / s[1])))
		end
	end
	return math.clamp(tilt, minTilt, maxTilt)
end

-- the distance from (px, pz) to the segment (ax, az) - (bx, bz), and which side of it (+1 left of a -> b, -1 right)
function Trees.offSegment(px: number, pz: number, ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = px - (ax + dx * t), pz - (az + dz * t)
	local side = if dx * (pz - az) - dz * (px - ax) >= 0 then 1 else -1
	return math.sqrt(cx * cx + cz * cz), side
end

-- a direct staff hit of `stage` on a trunk: its damage, and whether it shatters the trunk (Trees.Direct)
function Trees.directHit(stage: number, d: { damage: { number }, shatterFrom: number }): (number, boolean)
	if stage >= d.shatterFrom then
		return math.huge, true
	end
	return d.damage[stage] or 0, false
end

-- where a line from (ox, oy, oz) along unit (dx, dy, dz), `length` long, first enters a box centred on the origin with
-- half sizes (hx, hy, hz), all in the box's own frame: the distance along it, or nil (a start inside counts as 0)
function Trees.enterBox(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	length: number,
	hx: number,
	hy: number,
	hz: number
): number?
	local near, far = 0, length
	for _, a in { { ox, dx, hx }, { oy, dy, hy }, { oz, dz, hz } } do
		local o, d, h = a[1], a[2], a[3]
		if math.abs(d) < 1e-9 then
			if o < -h or o > h then
				return nil
			end
		else
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			near, far = math.max(near, t1), math.min(far, t2)
			if near > far then
				return nil
			end
		end
	end
	return near
end

-- the leaf shapes (Config/TreeShapes) of a canopy part of size (sx, sy, sz): the variant whose proportions are closest,
-- or the fallback when none is within cfg.matchTolerance
function Trees.canopyShapes(sx: number, sy: number, sz: number, cfg: any): { any }
	local best, gap = nil, math.huge
	if sy > 0 then
		for _, v in cfg.Variants do
			local s = v.size
			local d = math.max(math.abs(sx / sy - s[1] / s[2]), math.abs(sz / sy - s[3] / s[2]))
			if d < gap then
				best, gap = v, d
			end
		end
	end
	return if best and gap <= cfg.matchTolerance then best.shapes else cfg.Fallback
end

-- where t (from 0 to `length`) the line o + t d first lies inside one shape, or nil; a start inside counts as 0.
-- o and d are in the shapes' units (shares of the canopy's half size), so t stays in studs.
local function enterShape(
	s: any,
	grow: number,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	length: number
): number?
	if s.shape == "Ellipsoid" then
		local rx, ry, rz = s.rx * grow, s.ry * grow, s.rz * grow
		local qx, qy, qz = (ox - s.x) / rx, (oy - s.y) / ry, (oz - s.z) / rz
		local ex, ey, ez = dx / rx, dy / ry, dz / rz
		local c = qx * qx + qy * qy + qz * qz - 1
		if c <= 0 then
			return 0
		end
		local a = ex * ex + ey * ey + ez * ez
		local b = 2 * (qx * ex + qy * ey + qz * ez)
		local disc = b * b - 4 * a * c
		if a < 1e-12 or disc < 0 then
			return nil
		end
		local t = (-b - math.sqrt(disc)) / (2 * a)
		return if t >= 0 and t <= length then t else nil
	end
	-- a cone with its axis along Y: u, w across it in base radii, h up it in heights (0 at the base, 1 at the apex);
	-- inside where 0 <= h <= 1 and u^2 + w^2 <= (1 - h)^2. Grown about its own middle.
	local height = s.height * grow
	local base = s.y + s.height / 2 - height / 2
	local rx, rz = s.rx * grow, s.rz * grow
	local u0, w0, h0 = (ox - s.x) / rx, (oz - s.z) / rz, (oy - base) / height
	local du, dw, dh = dx / rx, dz / rz, dy / height
	-- the slab 0 <= h <= 1, clipped to the line
	local lo, hi = 0, length
	if math.abs(dh) < 1e-12 then
		if h0 < 0 or h0 > 1 then
			return nil
		end
	else
		local t1, t2 = -h0 / dh, (1 - h0) / dh
		lo, hi = math.max(lo, math.min(t1, t2)), math.min(hi, math.max(t1, t2))
	end
	if lo > hi then
		return nil
	end
	-- f(t) = u^2 + w^2 - (1 - h)^2 <= 0: inside the double cone; within the slab only this one's nappe counts
	local k0 = 1 - h0
	local a = du * du + dw * dw - dh * dh
	local b = 2 * (u0 * du + w0 * dw + k0 * dh)
	local c = u0 * u0 + w0 * w0 - k0 * k0
	local function inside(t: number): boolean
		return a * t * t + b * t + c <= 1e-9
	end
	if inside(lo) then
		return lo
	end
	-- the first root of f inside (lo, hi] where f turns negative
	local roots = {}
	if math.abs(a) < 1e-12 then
		if math.abs(b) > 1e-12 then
			table.insert(roots, -c / b)
		end
	else
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			local r = math.sqrt(disc)
			local t1, t2 = (-b - r) / (2 * a), (-b + r) / (2 * a)
			table.insert(roots, math.min(t1, t2))
			table.insert(roots, math.max(t1, t2))
		end
	end
	for _, t in roots do
		if t > lo and t <= hi and inside(math.min(t + 1e-6, hi)) then
			return t
		end
	end
	return nil
end

-- where a line from (ox, oy, oz) along unit (dx, dy, dz), `length` long, first enters the leaves `shapes` of a canopy
-- with half sizes (hx, hy, hz), all in the canopy's own frame: the distance along it, or nil (a start inside counts as 0)
function Trees.enterLeaves(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	length: number,
	hx: number,
	hy: number,
	hz: number,
	shapes: { any },
	grow: number
): number?
	local first: number? = nil
	for _, s in shapes do
		local t = enterShape(s, grow, ox / hx, oy / hy, oz / hz, dx / hx, dy / hy, dz / hz, first or length)
		if t and (not first or t < first) then
			first = t
		end
	end
	return first
end

return Trees
