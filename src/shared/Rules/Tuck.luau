--!strict
-- Folding the gun in when the barrel is blocked (Config/Locomotion.Tuck, src/client/Tuck). Pure: studs.

local Tuck = {}

-- How far from the shoulder the barrel reaches at the ready hold: the grip `gripAhead` in front of the shoulder plus
-- the muzzle's length ahead of the grip (modelled gun z, times the weapon's length scale).
function Tuck.reach(muzzleZ: number, gripZ: number, scaleZ: number, gripAhead: number): number
	return gripAhead + math.max(gripZ - muzzleZ, 0) * scaleZ
end

-- Whether the gun is folded in now: something `hit` studs along the sweep (nil: nothing) within the reach plus
-- `ahead` folds it; once folded it stays so until the way is clear by `clear` more.
function Tuck.blocked(hit: number?, reach: number, ahead: number, clear: number, was: boolean): boolean
	if hit == nil then
		return false
	end
	return hit < reach + ahead + (if was then clear else 0)
end

-- How far the gun is pulled back toward the shoulder, as a share of `give` (0: not at all, 1: all the way): from
-- `ahead` past the muzzle in, by how far the barrel would reach into what was hit.
function Tuck.pull(hit: number?, reach: number, ahead: number, give: number): number
	if hit == nil or give <= 0 then
		return 0
	end
	return math.clamp((reach + ahead - hit) / give, 0, 1)
end

-- Whether the gun folds: only against a surface the look meets head on (`facing`, the cosine between the look and
-- into the surface, at least `minFacing`; folded, down to minFacing - facingClear), and only when even pulled back by
-- `give` the barrel would be within `ahead` of it (folded: until clear by `clear` more).
function Tuck.folds(
	hit: number?,
	facing: number,
	reach: number,
	ahead: number,
	give: number,
	clear: number,
	minFacing: number,
	facingClear: number,
	was: boolean
): boolean
	if facing < minFacing - (if was then facingClear else 0) then
		return false
	end
	return Tuck.blocked(hit, reach - give, ahead, clear, was)
end

-- server: a pull share received from a client, clamped to 0..1 and quantized to `step`; nil if it isn't a number
function Tuck.sanitizePull(pull: any, step: number): number?
	if type(pull) ~= "number" or pull ~= pull then
		return nil
	end
	return math.floor(math.clamp(pull, 0, 1) / step + 0.5) * step
end

-- The same for trench dirt (its walls, floor, banks and the ground carved round them): only a surface the look meets
-- nearly head on (`facing`, the cosine between the look and into the surface, at least `minFacing`) within the
-- barrel's own reach folds it; the sloped walls, the floor and the parapet a look along or out of the trench glances
-- past don't (Studio round t1024-1602-59df: the rifle stayed folded inside a trench).
function Tuck.trenchBlocked(
	hit: number?,
	facing: number,
	reach: number,
	minFacing: number,
	clear: number,
	was: boolean
): boolean
	if hit == nil or facing < minFacing then
		return false
	end
	return hit < reach + (if was then clear else 0)
end

return Tuck
