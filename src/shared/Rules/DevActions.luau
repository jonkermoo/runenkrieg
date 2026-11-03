--!strict
-- The dev test actions (Net "DevAction": action, value, aim point; Config/DevTools): which actions exist, which values
-- each takes, whether an aim point is close enough, the target dummies' patrol legs and their hit readout. Pure.

local DevActions = {}

-- actions that act at the aim point (the middle of the player's screen)
DevActions.Aimed = table.freeze({
	BlastStage = true,
	Shells = true,
	BeamStage = true,
	BlastKg = true,
	Dummy = true,
	PlaceGun = true,
	PlacePiece = true,
	GunHp = true,
	BotPush = true,
	BotStrike = true,
	BotGun = true,
	BotWork = true,
	BotDown = true,
})

-- actions with no value (or a plain on/off)
local PLAIN = table.freeze({
	BotsAuto = true,
	Kill = true,
	Respawn = true,
	KnockMe = true,
	HelmetOff = true,
	HelmetShot = true,
	HealDummies = true,
	KnockDummies = true,
	SayDummies = true,
	ClearDummies = true,
	UndoDestruction = true,
	ClearGuns = true,
	MatchEnd = true,
	MatchRestart = true,
	ZoneSkip = true,
	RespawnAll = true,
	FrontTake = true,
	FrontStart = true,
	BotPush = true,
	BotStrike = true,
	BotGun = true,
	BotWork = true,
	BotDown = true,
	RebuildMaps = true,
	HitchReport = true,
})
local SWITCHES = table.freeze({
	God = true,
	BlastHurts = true,
	Shooters = true,
	ClockPaused = true,
	WeatherCalm = true,
	BuildAll = true,
	Ammo = true,
	KeptTeams = true,
	Sectors = true,
	BotState = true,
	GunArcs = true,
	FreeEngineer = true,
	FreeGrenadier = true,
	HitchLog = true,
})

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

-- Whether `value` is one `action` takes. `defs`: the game modes (Config/Modes.Defs) and classes (Config/Classes.Defs)
-- the "Mode" and "Class" actions name; without them those are refused.
function DevActions.valid(cfg: any, action: any, value: any, defs: { modes: any, classes: any }?): boolean
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
	elseif action == "Mode" then
		return defs ~= nil and type(value) == "string" and defs.modes[value] ~= nil
	elseif action == "Map" then
		return defs ~= nil and defs.maps ~= nil and type(value) == "string" and table.find(defs.maps, value) ~= nil
	elseif action == "Class" then
		return defs ~= nil and type(value) == "string" and (value == cfg.Admin.Normal or defs.classes[value] ~= nil)
	elseif action == "MatchTime" then
		return table.find(cfg.Admin.MatchSeconds, value) ~= nil
	elseif action == "Bots" then
		return table.find(cfg.Admin.BotCounts, value) ~= nil
	elseif action == "BotDifficulty" then
		return table.find(cfg.Admin.BotDifficulties, value) ~= nil
	elseif action == "BotDig" then
		return table.find(cfg.Admin.BotDig.steps, value) ~= nil
	elseif action == "BotShell" or action == "FrontPush" then
		return table.find(cfg.Admin.Sides, value) ~= nil
	elseif action == "BotPlan" then
		-- (a side's fighting plan forced, or "auto": Rules/BotFront, src/server/Bots.dev "Plan")
		return type(value) == "table"
			and table.find(cfg.Admin.Sides, value.side) ~= nil
			and (value.plan == "auto" or table.find(cfg.Admin.BotPlans, value.plan) ~= nil)
	elseif action == "FrontCapture" then
		return type(value) == "table"
			and table.find(cfg.Admin.Sides, value.side) ~= nil
			and type(value.index) == "number"
			and value.index == math.floor(value.index)
			and value.index >= 1
			and value.index <= cfg.Admin.MaxSectors
	elseif action == "ZoneScore" then
		return table.find(cfg.Admin.ZoneScore, value) ~= nil
	elseif action == "Points" then
		return table.find(cfg.Admin.Points, value) ~= nil
	elseif action == "Grenade" then
		return table.find(cfg.Admin.Grenades, value) ~= nil
	elseif action == "ShockAt" then
		if type(value) ~= "table" or table.find(cfg.Admin.Shock.Distances, value.distance) == nil then
			return false
		end
		for _, s in cfg.Admin.Shock.Sources do
			if s.key == value.source then
				return true
			end
		end
		return false
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
	elseif action == "BlastStage" or action == "BeamStage" then
		return table.find(cfg.Blasts.Stages, value) ~= nil
	elseif action == "BlastKg" then
		return table.find(cfg.Blasts.Kg, value) ~= nil
	elseif action == "PlaceGun" or action == "Shells" then
		return table.find(cfg.Blasts.Guns, value) ~= nil
	elseif action == "PlacePiece" then
		return table.find(cfg.Blasts.Pieces, value) ~= nil
	elseif action == "GunHp" then
		return table.find(cfg.Blasts.GunHp, value) ~= nil
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

export type BotState = {
	order: string?,
	sector: number?,
	phase: string?,
	role: string?,
	post: string?,
	act: string?,
	gun: string?,
	danger: boolean?,
}

-- The admin panel's label over a bot (Config/DevTools.Admin.BotState): "Attack S3 · Bound/Assault" over
-- "step · Build · gun field gun · DANGER"; a missing part is left out ("-" for a missing first line).
function DevActions.botLabel(s: BotState): string
	local top = {}
	if s.order then
		table.insert(top, if s.sector then `{s.order} S{s.sector}` else s.order)
	end
	if s.phase or s.role then
		table.insert(top, `{s.phase or "?"}/{s.role or "?"}`)
	end
	local bottom = {}
	if s.post then
		table.insert(bottom, s.post)
	end
	if s.act then
		table.insert(bottom, s.act)
	end
	if s.gun then
		table.insert(bottom, `gun {s.gun}`)
	end
	if s.danger then
		table.insert(bottom, "DANGER")
	end
	local first = if #top > 0 then table.concat(top, " · ") else "-"
	return if #bottom > 0 then `{first}\n{table.concat(bottom, " · ")}` else first
end

-- The display name of a dummy kit ("Grey"), or nil.
function DevActions.kitName(cfg: any, kit: string): string?
	local k = kitOf(cfg, kit)
	return k and k.name
end

return DevActions
