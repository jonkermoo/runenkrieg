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

return Trees
