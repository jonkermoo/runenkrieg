--!strict
-- Trees with HP (Config/Damage.Trees; user 2026-10-17): what a hit or a blast does to one, how far a felled tree tilts
-- to lie on the ground, and where a bullet's line enters a canopy (the leaves let bullets through; the client shows
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

-- HP left after `amount`, and whether that fells it
function Trees.after(hp: number, amount: number): (number, boolean)
	local left = math.max(hp - math.max(amount, 0), 0)
	return left, left <= 0 and amount > 0
end

-- how far (degrees from upright) a felled tree of `height` tilts so its top rests on the ground, the ground at its
-- top `rise` studs above its base (negative: downhill); clamped to [minTilt, maxTilt]
function Trees.fallTilt(height: number, rise: number, minTilt: number, maxTilt: number): number
	if height <= 0 then
		return minTilt
	end
	return math.clamp(90 - math.deg(math.atan(rise / height)), minTilt, maxTilt)
end

-- where a line from (ox, oy, oz) along unit (dx, dy, dz), `length` long, first enters a ball at (cx, cy, cz) of
-- radius `r`: the distance along it, or nil (a start inside the ball counts as 0)
function Trees.enter(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	length: number,
	cx: number,
	cy: number,
	cz: number,
	r: number
): number?
	local lx, ly, lz = cx - ox, cy - oy, cz - oz
	local along = lx * dx + ly * dy + lz * dz
	local d2 = lx * lx + ly * ly + lz * lz - along * along
	if d2 > r * r then
		return nil
	end
	local t = along - math.sqrt(r * r - d2)
	if t > length or along + math.sqrt(r * r - d2) < 0 then
		return nil
	end
	return math.max(t, 0)
end

return Trees
