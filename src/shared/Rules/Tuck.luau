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

return Tuck
