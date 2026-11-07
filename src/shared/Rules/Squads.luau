--!strict
-- Player squads (Config/Squads): pure rules shared by src/server/Squads (who joins what) and the client's panel and
-- markers (src/client/SquadPanel, src/client/SquadMarkers). No Instances.
-- A squad is "<team>:<number>": the team (a uniform kit, Rules/Teams) and its place in Config/Squads.Names.

local Squads = {}

export type Cfg = { Max: number, Names: { string } }

-- A squad's key from its team and number.
function Squads.key(team: string, n: number): string
	return `{team}:{n}`
end

-- A key's team and number, or nil when it isn't one.
function Squads.parse(key: unknown): (string?, number?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local team, n = string.match(key, "^(.+):(%d+)$")
	if not team then
		return nil, nil
	end
	return team, tonumber(n)
end

-- A squad's name (its rune, capitalised: "fehu" -> "Fehu"), or "?" past the list.
function Squads.name(cfg: Cfg, n: number): string
	local rune = cfg.Names[n]
	if not rune then
		return "?"
	end
	return string.upper(string.sub(rune, 1, 1)) .. string.sub(rune, 2)
end

-- How many soldiers are in each squad: `of` is every soldier's squad key (nil: in none).
function Squads.counts(of: { unknown }): { [string]: number }
	local counts: { [string]: number } = {}
	for _, key in of do
		if type(key) == "string" and key ~= "" then
			counts[key] = (counts[key] or 0) + 1
		end
	end
	return counts
end

-- The lowest squad number on `team` that nobody is in, or nil when every name is taken.
function Squads.free(cfg: Cfg, counts: { [string]: number }, team: string): number?
	for n = 1, #cfg.Names do
		if (counts[Squads.key(team, n)] or 0) == 0 then
			return n
		end
	end
	return nil
end

-- Why a soldier on `team`, now in `current` (a key or nil), can't join squad `key` ("NoTeam": not on a team that has
-- squads, "Unknown": not a squad, "Other": another team's, "Already": in it, "Full": Max in it, "Empty": nobody in it
-- (a new squad goes through `free`)), or nil when they can.
function Squads.blocked(cfg: Cfg, counts: { [string]: number }, team: unknown, current: unknown, key: unknown): string?
	if type(team) ~= "string" or team == "" then
		return "NoTeam"
	end
	local t, n = Squads.parse(key)
	if not t or not n or n < 1 or n > #cfg.Names then
		return "Unknown"
	end
	if t ~= team then
		return "Other"
	end
	if key == current then
		return "Already"
	end
	local c = counts[key :: string] or 0
	if c == 0 then
		return "Empty"
	end
	if c >= cfg.Max then
		return "Full"
	end
	return nil
end

-- Whether a soldier in squad `key` still belongs in it while on `team` (a team change leaves the squad).
function Squads.keeps(key: unknown, team: unknown): boolean
	local t = Squads.parse(key)
	return t ~= nil and type(team) == "string" and t == team
end

export type Soldier = {
	exists: boolean, -- a character in the world
	alive: boolean, -- its health above 0
	down: boolean, -- knocked down (ragdolled)
	wave: boolean, -- standing in the wave line
}

-- A soldier's status (a Config/Squads.Status key): Fallen, Down, Wave, Action or Awaiting.
function Squads.status(s: Soldier): string
	if not s.exists then
		return "Awaiting"
	end
	if not s.alive then
		return "Fallen"
	end
	if s.down then
		return "Down"
	end
	if s.wave then
		return "Wave"
	end
	return "Action"
end

export type Member = { name: string, key: string?, me: boolean? }
export type Row = { key: string, n: number, name: string, members: { Member } }

-- `team`'s squads in number order, each with its members by name (yourself first in your own).
function Squads.list(cfg: Cfg, team: string, members: { Member }): { Row }
	local rows: { [number]: Row } = {}
	for _, m in members do
		local t, n = Squads.parse(m.key)
		if t == team and n then
			local row = rows[n]
			if not row then
				row = { key = m.key :: string, n = n, name = Squads.name(cfg, n), members = {} }
				rows[n] = row
			end
			table.insert(row.members, m)
		end
	end
	local out: { Row } = {}
	for _, row in rows do
		table.sort(row.members, function(a, b)
			if (a.me == true) ~= (b.me == true) then
				return a.me == true
			end
			return string.lower(a.name) < string.lower(b.name)
		end)
		table.insert(out, row)
	end
	table.sort(out, function(a, b)
		return a.n < b.n
	end)
	return out
end

return Squads
