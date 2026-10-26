--!strict
-- Teams (user 2026-10-22: "make healing only team allowed"). Until real teams (M13) a soldier's team is the uniform kit
-- they wear this life: the character's "Kit" attribute (src/server/Kits; DEV and showcase dummies carry their own).
-- Shared by everything that only works between teammates (healing: src/server/Healing, src/client/Healing) or spares
-- them (no friendly fire: src/server/Damage, Config/Damage.FriendlyFire).

local Teams = {}

-- Whether two soldiers wearing kits `a` and `b` are on the same team: both known and equal. An unknown kit (not
-- rolled yet) is nobody's teammate.
function Teams.same(a: unknown, b: unknown): boolean
	return type(a) == "string" and a ~= "" and a == b
end

-- Whether a hit from a soldier in kit `by` spares one in kit `on` (user 2026-10-26: no friendly fire from guns, melee,
-- the staff's beam or blasts): teammates are spared unless `friendlyFire` is on. Hits on yourself are the caller's.
function Teams.spared(by: unknown, on: unknown, friendlyFire: boolean): boolean
	return not friendlyFire and Teams.same(by, on)
end

return Teams
