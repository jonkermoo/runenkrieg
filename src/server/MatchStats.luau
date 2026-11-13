--!strict
-- What each player did this match, for the results screen (Rules/MatchStats, src/client/Results; user 2026-10-31):
-- kills (src/server/Loadouts.onKill), HP healed on others (src/server/Healing.onHealed), HP built
-- (src/server/Build.onBuilt) and points earned (src/server/Loadouts.onEarn). Cleared at each match's start; at its end
-- the match (src/server/Frontline, src/server/ZoneMatch) sends everyone the results (Net "MatchResults"). Bot
-- soldiers have rows too (src/server/Bots: their kills; user 2026-11-01: bots may win the honours, under their shown
-- names). Assists (src/server/Loadouts.onAssist) count too, and the bots' building and healing (src/server/Bots). While
-- Tab is held each client asks for the live scoreboard (Net "Scores", MatchStats.board; src/client/Scoreboard; user
-- 2026-11-12): every soldier on the field, by side, with their kills, assists, HP healed and HP built.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.MatchStats)

local MatchStats = {}

local KEYS = { "Kills", "Assists", "Healed", "Built", "Earned" }
local rows: { [number]: Rules.Row } = {}
-- the bots on the field now (src/server/Bots): each one's id, shown name and side, so the scoreboard lists them all
local roster: () -> { { id: number, name: string, kit: string? } } = function()
	return {}
end

local function rowOf(player: Player): Rules.Row
	local r = rows[player.UserId]
	if not r then
		r = { id = player.UserId, name = player.DisplayName }
		for _, k in KEYS do
			r[k] = 0
		end
		rows[player.UserId] = r
	end
	return r
end

local function botRow(id: number, name: string): Rules.Row
	local r = rows[id]
	if not r then
		r = { id = id, name = name }
		for _, k in KEYS do
			r[k] = 0
		end
		rows[id] = r
	end
	return r
end

-- `fn()`: the bots on the field now (src/server/Bots)
function MatchStats.bots(fn: () -> { { id: number, name: string, kit: string? } })
	roster = fn
end

function MatchStats.reset()
	table.clear(rows)
end

-- bot `id` (its negative id) did `n` more of `key`; `name` and `kit` as shown (its latest life's)
function MatchStats.addBot(id: number, name: string, kit: string?, key: string, n: number)
	local r = botRow(id, name)
	r.name, r.kit = name, kit
	r[key] += n
end

-- `player` did `n` more of `key` ("Kills", "Assists", "Healed", "Built", "Earned")
function MatchStats.add(player: Player, key: string, n: number)
	local r = rowOf(player)
	r[key] += n
end

-- The live scoreboard (Net "Scores"): every player and every bot on the field, each `{ id, name, kit, Kills, Assists,
-- Healed, Built }` (health whole), `kit` their side now (nil: not on one yet).
function MatchStats.board(): { Rules.Row }
	local out: { Rules.Row } = {}
	local function row(r: Rules.Row, kit: string?)
		table.insert(out, {
			id = r.id,
			name = r.name,
			kit = kit,
			Kills = r.Kills,
			Assists = r.Assists,
			Healed = math.floor(r.Healed + 0.5),
			Built = math.floor(r.Built + 0.5),
		})
	end
	for _, p in Players:GetPlayers() do
		local r = rowOf(p)
		r.name = p.DisplayName
		local character = p.Character
		local kit = character and character:GetAttribute("Kit")
		if type(kit) == "string" then
			r.kit = kit -- (kept while respawning)
		end
		row(r, r.kit)
	end
	for _, b in roster() do
		local r = botRow(b.id, b.name)
		r.name, r.kit = b.name, b.kit or r.kit
		row(r, r.kit)
	end
	return out
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
	for id, r in rows do
		if id < 0 then
			table.insert(list, r)
		end
	end
	local honours = {
		Kills = Rules.best(list, "Kills"),
		Healed = Rules.best(list, "Healed"),
		Built = Rules.best(list, "Built"),
	}
	-- the best `extra.top` by battle points (the war table's report: each one's kills, healing, building)
	local top = {}
	if type(extra.top) == "number" then
		for i, r in Rules.ranked(list, "Earned") do
			if i > extra.top then
				break
			end
			table.insert(top, {
				name = r.name,
				Kills = r.Kills or 0,
				Healed = math.floor((r.Healed or 0) + 0.5),
				Built = math.floor((r.Built or 0) + 0.5),
			})
		end
	end
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
		payload.top = if type(extra.top) == "number" then top else nil
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
