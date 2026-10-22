--!strict
-- How long a knocked-down soldier stays down (Config/Ragdoll.ByDamage, src/server/Ragdoll). Pure: seconds.

local Ragdoll = {}

export type ByDamage = { floor: number, ceiling: number, full: number }

-- The get-up wait after the body settles: the knock's own `getUp` for a knock that did no `damage` (nil or 0),
-- else from `by.floor` at no damage up to `by.ceiling` at `by.full` damage and more, never under `getUp`.
function Ragdoll.getUp(getUp: number, damage: number?, by: ByDamage): number
	if not damage or damage <= 0 then
		return getUp
	end
	local t = math.clamp(damage / by.full, 0, 1)
	return math.max(getUp, by.floor + (by.ceiling - by.floor) * t)
end

return Ragdoll
