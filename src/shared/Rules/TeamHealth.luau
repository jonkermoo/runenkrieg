--!strict
-- Teammates' health bars (Config/TeamHealth): who gets one and how it looks. Pure.

local Healing = if typeof(script) == "Instance" then require(script.Parent.Healing) else require("./Healing")

local TeamHealth = {}

export type Look = "Ok" | "Low" | "Down"

-- Whether a soldier `distance` studs away gets a bar: a living teammate within `range`.
function TeamHealth.shown(mate: boolean, health: number, distance: number, range: number): boolean
	return mate and health > 0 and distance <= range
end

-- The bar's fill (0..1) and look at `health` of `max`: Down when knocked down, Low when hurt enough for a bandage
-- (Rules/Healing.kind), else Ok.
function TeamHealth.look(health: number, max: number, down: boolean, healCfg: Healing.Cfg): (number, Look)
	local share = if max > 0 then math.clamp(health / max, 0, 1) else 0
	if down then
		return share, "Down"
	end
	return share, if Healing.kind(health, max, healCfg) == "Bandage" then "Low" else "Ok"
end

return TeamHealth
