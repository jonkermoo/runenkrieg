--!strict
-- The dev test actions (Net "DevAction": action, value, aim point; Config/DevTools): which actions exist, which values
-- each takes, whether an aim point is close enough, the target dummies' patrol legs and their hit readout. Pure.

local DevActions = {}

-- actions that act at the aim point (the middle of the player's screen)
DevActions.Aimed = table.freeze({ BlastStage = true, BlastKg = true, Dummy = true, PlaceGun = true })

-- actions with no value (or a plain on/off)
local PLAIN = table.freeze({
	Kill = true,
	Respawn = true,
	KnockMe = true,
	HelmetOff = true,
	HealDummies = true,
	ClearDummies = true,
	UndoDestruction = true,
	ClearGuns = true,
})
local SWITCHES =
	table.freeze({ God = true, BlastHurts = true, Shooters = true, ClockPaused = true, WeatherCalm = true })

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function kitOf(cfg: any, kit: any): { kit: string, name: string }?
	for _, k in cfg.Dummies.Kits do
		if k.kit == kit then
			return k
		end
	end
	return nil
end

-- Whether `value` is one `action` takes.
function DevActions.valid(cfg: any, action: any, value: any): boolean
	if type(action) ~= "string" then
		return false
	end
	if PLAIN[action] then
		return value == nil
	elseif SWITCHES[action] then
		return type(value) == "boolean"
	elseif action == "Health" then
		return table.find(cfg.Admin.Health, value) ~= nil
	elseif action == "Team" then
		return value == cfg.Admin.Random or kitOf(cfg, value) ~= nil
	elseif action == "Grenade" then
		return table.find(cfg.Admin.Grenades, value) ~= nil
	elseif action == "Weather" then
		return table.find(cfg.Admin.Weather, value) ~= nil
	elseif action == "Clock" then
		for _, t in cfg.Admin.Times do
			if t.hours == value then
				return true
			end
		end
		return false
	elseif action == "DigStep" then
		for _, s in cfg.Admin.Dig.steps do
			if s.share == value then
				return true
			end
		end
		return false
	elseif action == "BlastStage" then
		return table.find(cfg.Blasts.Stages, value) ~= nil
	elseif action == "BlastKg" then
		return table.find(cfg.Blasts.Kg, value) ~= nil
	elseif action == "PlaceGun" then
		return table.find(cfg.Blasts.Guns, value) ~= nil
	elseif action == "Dummy" then
		return type(value) == "table"
			and kitOf(cfg, value.kit) ~= nil
			and type(value.helmet) == "boolean"
			and table.find(cfg.Dummies.Moves, value.move) ~= nil
	end
	return false
end

-- Whether an aim point `dx, dy, dz` away from the character is a real point within reach.
function DevActions.inReach(cfg: any, dx: any, dy: any, dz: any): boolean
	if not (finite(dx) and finite(dy) and finite(dz)) then
		return false
	end
	return dx * dx + dy * dy + dz * dz <= cfg.AimReach * cfg.AimReach
end

-- A dummy's patrol point for `move` on leg `leg` (+1 / -1), in its own axes: (right, forward) studs from where it was
-- put. Stand stays put.
function DevActions.leg(move: string, leg: number, patrol: number): (number, number)
	if move == "Walk" then
		return 0, leg * patrol
	elseif move == "Strafe" then
		return leg * patrol, 0
	end
	return 0, 0
end

-- The readout over a dummy after a hit: the damage (rounded), the knock it got (if any) and the health left.
function DevActions.readout(amount: number, knock: string?, left: number): string
	local head = if amount > 0 then `-{math.round(amount)}` else "0"
	local mid = if knock then ` {knock}` else ""
	local tail = if left <= 0 then "dead" else tostring(math.round(left))
	return `{head}{mid} -> {tail}`
end

-- The display name of a dummy kit ("Grey"), or nil.
function DevActions.kitName(cfg: any, kit: string): string?
	local k = kitOf(cfg, kit)
	return k and k.name
end

return DevActions
