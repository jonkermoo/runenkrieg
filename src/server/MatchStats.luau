--!strict
-- What each player did this match, for the results screen (Rules/MatchStats, src/client/Results; user 2026-10-31):
-- kills (src/server/Loadouts.onKill), HP healed on others (src/server/Healing.onHealed), HP built
-- (src/server/Build.onBuilt) and points earned (src/server/Loadouts.onEarn). Cleared at each match's start; at its end
-- the match (src/server/Frontline, src/server/ZoneMatch) sends everyone the results (Net "MatchResults").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.MatchStats)

local MatchStats = {}

local KEYS = { "Kills", "Healed", "Built", "Earned" }
local rows: { [number]: Rules.Row } = {}

local function rowOf(player: Player): Rules.Row
	local r = rows[player.UserId]
	if not r then
		r = { id = player.UserId, name = player.Name }
		for _, k in KEYS do
			r[k] = 0
		end
		rows[player.UserId] = r
	end
	return r
end

function MatchStats.reset()
	table.clear(rows)
end

-- `player` did `n` more of `key` ("Kills", "Healed", "Built", "Earned")
function MatchStats.add(player: Player, key: string, n: number)
	local r = rowOf(player)
	r[key] += n
end

-- Sends each player the results: the honours from every row, their own row, and `extra` (the mode's: Normal's
-- capture log, FFA's scores). `kitOf(player)`: the team each row is shown in (nil: none). `extra.scores` (FFA,
-- { [id] = { name, score } }) makes each player's standings.
function MatchStats.send(extra: { [string]: any }, kitOf: (Player) -> string?)
	local list: { Rules.Row } = {}
	for _, p in Players:GetPlayers() do
		local r = rowOf(p)
		r.kit = kitOf(p)
		table.insert(list, r)
	end
	local honours = {
		Kills = Rules.best(list, "Kills"),
		Healed = Rules.best(list, "Healed"),
		Built = Rules.best(list, "Built"),
	}
	local scored: { Rules.Row } = {}
	if extra.scores then
		for id, s in extra.scores do
			table.insert(scored, { id = id, name = s.name, Score = s.score })
		end
	end
	for _, p in Players:GetPlayers() do
		local me = rowOf(p)
		local payload = table.clone(extra)
		payload.scores = nil
		payload.honours = honours
		payload.you = {
			Kills = me.Kills,
			Healed = math.floor(me.Healed + 0.5),
			Built = math.floor(me.Built + 0.5),
			Earned = math.floor(me.Earned + 0.5),
		}
		if extra.scores then
			payload.standings = Rules.standings(scored, "Score", payload.standingsTop or 8, p.UserId)
		end
		Net.event("MatchResults"):FireClient(p, payload)
	end
end

return MatchStats
