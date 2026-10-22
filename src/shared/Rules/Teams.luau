--!strict
-- Teams (user 2026-10-22: "make healing only team allowed"). Until real teams (M13) a soldier's team is the uniform kit
-- they wear this life: the character's "Kit" attribute (src/server/Kits; DEV and showcase dummies carry their own).
-- Shared by everything that only works between teammates (healing: src/server/Healing, src/client/Healing).

local Teams = {}

-- Whether two soldiers wearing kits `a` and `b` are on the same team: both known and equal. An unknown kit (not
-- rolled yet) is nobody's teammate.
function Teams.same(a: unknown, b: unknown): boolean
	return type(a) == "string" and a ~= "" and a == b
end

return Teams
