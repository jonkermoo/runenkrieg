--!strict
-- Damage, death and the knock a hit gives (M12, Config/Damage). Pure: numbers, strings and tables only.

local Damage = {}

export type Table = { Head: number, Torso: number, Limb: number, Helmet: number }
-- one ray's hit on a soldier: its zone ("Head" / "Torso" / "Limb" / "Helmet") and the damage it does
export type Hit = { zone: string, amount: number }

local ZONES: { [string]: string } = {
	Head = "Head",
	Torso = "Torso",
	HumanoidRootPart = "Torso",
	["Left Arm"] = "Limb",
	["Right Arm"] = "Limb",
	["Left Leg"] = "Limb",
	["Right Leg"] = "Limb",
}

-- The hit zone of a body part by its name, or nil for anything that isn't a body part.
function Damage.zone(partName: string): string?
	return ZONES[partName]
end

-- The share of a pellet's damage left at `distance`: 1 up to `full`, falling in a straight line to 0 at `none`.
function Damage.falloff(distance: number, full: number, none: number): number
	if distance <= full then
		return 1
	end
	if distance >= none or none <= full then
		return 0
	end
	return 1 - (distance - full) / (none - full)
end

-- The share of a bullet's damage left at `distance` (Config/Damage.Falloff): 1 up to `full`, falling in a straight line
-- to `least` at `far`, then `least`.
function Damage.fade(distance: number, full: number, far: number, least: number): number
	return least + (1 - least) * Damage.falloff(distance, full, far)
end

-- The zone of a hit on a helmet `distance` studs from the muzzle: "Head" within `lethal` (Config/Damage.HelmetLethal; nil:
-- never), else "Helmet".
function Damage.helmetZone(distance: number, lethal: number?): string
	return if lethal and distance <= lethal then "Head" else "Helmet"
end

-- One ray's damage: the class's number for the zone, times the falloff share (1 without one).
function Damage.amount(t: Table, zone: string, share: number?): number
	local base = (t :: any)[zone]
	if type(base) ~= "number" then
		return 0
	end
	return base * math.clamp(share or 1, 0, 1)
end

-- A shot's hits on one soldier: the total, the part of it from helmet hits, and the zone that took the most (ties go
-- to the earlier hit).
function Damage.sum(hits: { Hit }): (number, number, string?)
	local total, helmet = 0, 0
	local byZone: { [string]: number } = {}
	local order: { string } = {}
	for _, h in hits do
		total += h.amount
		if h.zone == "Helmet" then
			helmet += h.amount
		end
		if not byZone[h.zone] then
			table.insert(order, h.zone)
			byZone[h.zone] = 0
		end
		byZone[h.zone] += h.amount
	end
	local top, most = nil, 0
	for _, z in order do
		if byZone[z] > most then
			top, most = z, byZone[z]
		end
	end
	return total, helmet, top
end

-- Health after taking `total` damage of which `helmet` came from helmet hits. A helmet hit is never fatal by itself:
-- when the rest alone would not kill, `floor` health is left (Config/Damage.HelmetFloor). Never below 0.
function Damage.after(health: number, total: number, helmet: number, floor: number): number
	local left = health - math.max(total, 0)
	if left <= 0 and helmet > 0 and health - (total - helmet) > 0 then
		return math.min(floor, health)
	end
	return math.max(left, 0)
end

-- The knock (a Config/Ragdoll.Knocks name) for the zone that took the most: `knocks.Alive` or `knocks.Killed`.
function Damage.knock(
	zone: string?,
	killed: boolean,
	knocks: { Alive: { [string]: string }, Killed: { [string]: string } }
): string?
	if not zone then
		return nil
	end
	return if killed then knocks.Killed[zone] else knocks.Alive[zone]
end

-- The staff's damage and knock for a stage (Config/Damage.Staff); stages outside 1..#Damage are nil.
function Damage.staff(
	stage: number,
	health: number,
	s: { Damage: { number }, Knock: { string }, Killed: { string } }
): (number?, string?)
	local amount = s.Damage[stage]
	if not amount then
		return nil, nil
	end
	local left = math.max(health - amount, 0)
	return left, if left <= 0 then s.Killed[stage] else s.Knock[stage]
end

return Damage
