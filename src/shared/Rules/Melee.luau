--!strict
-- A gun's butt stroke (Config/Melee, Config/Damage.Melee): when one may strike, whether the strike faces where the
-- striker looks, and what a hit does. Pure: numbers, strings and tables only.

local Damage = if typeof(script) == "Instance" then require(script.Parent.Damage) else require("./Damage")

local Melee = {}

-- What stops a strike: the gun's action under way (a bolt, a reload, single rounds going in), ragdolled, the gun folded
-- in against a wall, already striking.
export type Hands = { busy: boolean?, ragdolled: boolean?, blocked: boolean?, striking: boolean? }

function Melee.free(h: Hands): boolean
	return not (h.busy or h.ragdolled or h.blocked or h.striking)
end

-- A strike `cooldown` seconds after the last one (nil: none yet) at `now`, `slack` seconds early allowed (latency).
function Melee.ready(last: number?, now: number, cooldown: number, slack: number?): boolean
	return last == nil or now - last + (slack or 0) >= cooldown
end

-- Whether a strike along (dx, dz) faces within `cone` degrees of where the head looks (lx, lz), flat. A direction
-- with no flat part (straight up or down) never does.
function Melee.facing(dx: number, dz: number, lx: number, lz: number, cone: number): boolean
	local d, l = math.sqrt(dx * dx + dz * dz), math.sqrt(lx * lx + lz * lz)
	if d < 1e-3 or l < 1e-3 then
		return false
	end
	return (dx * lx + dz * lz) / (d * l) >= math.cos(math.rad(cone)) - 1e-9
end

-- A hit on `zone` ("Head" / "Torso" / "Limb" / "Helmet") of a soldier at `health`: the health left and the knock (a
-- Config/Ragdoll.Knocks name). A helmet hit leaves at least `floor` (Config/Damage.HelmetFloor).
function Melee.hit(
	zone: string,
	health: number,
	m: { Damage: Damage.Table, Knocks: { [string]: string } },
	killed: { [string]: string },
	floor: number
): (number, string?)
	local amount = Damage.amount(m.Damage, zone)
	local left = Damage.after(health, amount, if zone == "Helmet" then amount else 0, floor)
	return left, if left <= 0 then killed[zone] else m.Knocks[zone]
end

return Melee
