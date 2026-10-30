--!strict
-- The server's game mode (Config/Modes; src/server/Modes). Pure.

local Modes = {}

-- The mode a server starts in: the place's saved mode if it is one that's ready, else FFA when the legacy switch is
-- saved on, else the default.
function Modes.initial(cfg: any, saved: unknown, legacy: unknown): string
	local d = if type(saved) == "string" then cfg.Defs[saved] else nil
	if d and d.ready then
		return saved :: string
	end
	if legacy == true then
		return cfg.Legacy.mode
	end
	return cfg.Default
end

-- Whether the server can switch from `current` to `key`: a known, ready mode that isn't live already.
function Modes.switchable(cfg: any, key: unknown, current: string): boolean
	local d = if type(key) == "string" then cfg.Defs[key] else nil
	return d ~= nil and d.ready == true and key ~= current
end

-- Whether mode `key` opens the admin panel to everyone (Config/Modes.openAdmin); an unknown mode doesn't.
function Modes.openAdmin(cfg: any, key: unknown): boolean
	local d = if type(key) == "string" then cfg.Defs[key] else nil
	return d ~= nil and d.openAdmin == true
end

-- Whether mode `key` keeps teams (Config/Modes `teams`, Config/Teams): `dev` is the admin panel's test switch.
function Modes.keptTeams(cfg: any, key: unknown, dev: unknown): boolean
	local d = if type(key) == "string" then cfg.Defs[key] else nil
	return dev == true or (d ~= nil and d.teams == true)
end

-- How many times over mode `key` pays battle points (Config/Modes `earn`; Config/Classes.Earn): 1 when it doesn't say.
function Modes.earnBoost(cfg: any, key: unknown): number
	local d = if type(key) == "string" then cfg.Defs[key] else nil
	return if d and type(d.earn) == "number" then d.earn else 1
end

-- The zone match's end after `delta` more seconds: never before `now`.
function Modes.extend(endsAt: number, delta: number, now: number): number
	return math.max(endsAt + delta, now)
end

return Modes
