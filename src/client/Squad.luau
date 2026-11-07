--!strict
-- What this client knows about the player squads (Config/Squads, Rules/Squads; src/server/Squads keeps them): your team
-- and squad (the server's "SquadTeam" / "Squad" attributes on your Player), every soldier in a squad (players, and the
-- admin panel's test mates: bots' or dummies' models with the squad attribute) and each one's status, read from their
-- soldier in the world (dead, knocked down: "Ragdolled", in the wave line: Config/Frontline.HoldAttribute). Shared by
-- the panel (src/client/SquadPanel), the markers (src/client/SquadMarkers) and the admin panel's readout.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cfg = require(Shared.Config.Squads)
local BotsCfg = require(Shared.Config.Bots)
local DevCfg = require(Shared.Config.DevTools)
local FrontCfg = require(Shared.Config.Frontline)
local Rules = require(Shared.Rules.Squads)

local Squad = {}

export type Entry = {
	name: string,
	key: string?,
	me: boolean?,
	model: Model?, -- the soldier in the world (a player's character), if any
	status: string, -- a Config/Squads.Status key
}

function Squad.team(): string?
	local t = Players.LocalPlayer:GetAttribute(Cfg.TeamAttribute)
	return if type(t) == "string" then t else nil
end

function Squad.key(): string?
	local k = Players.LocalPlayer:GetAttribute(Cfg.Attribute)
	return if type(k) == "string" then k else nil
end

-- A soldier's status from its model (none: not in the field).
function Squad.status(model: Model?): string
	local h = model and model:IsDescendantOf(workspace) and model:FindFirstChildOfClass("Humanoid")
	if not model or not h then
		return Rules.status({ exists = false, alive = false, down = false, wave = false })
	end
	return Rules.status({
		exists = true,
		alive = h.Health > 0,
		down = model:GetAttribute("Ragdolled") == true,
		wave = model:GetAttribute(FrontCfg.HoldAttribute) ~= nil,
	})
end

-- Everyone in a squad: players (by display name) and test mates.
function Squad.everyone(): { Entry }
	local me = Players.LocalPlayer
	local out: { Entry } = {}
	for _, p in Players:GetPlayers() do
		local key = p:GetAttribute(Cfg.Attribute)
		if type(key) == "string" then
			table.insert(out, {
				name = p.DisplayName,
				key = key,
				me = p == me,
				model = p.Character,
				status = Squad.status(p.Character),
			})
		end
	end
	local seen: { [Instance]: boolean } = {}
	for _, tag in { BotsCfg.Tag, DevCfg.Dummies.Tag } do
		for _, m in CollectionService:GetTagged(tag) do
			local key = m:GetAttribute(Cfg.Attribute)
			if m:IsA("Model") and type(key) == "string" and not seen[m] then
				seen[m] = true
				local name = m:GetAttribute(Cfg.NameAttribute)
				table.insert(out, {
					name = if type(name) == "string" then name else m.Name,
					key = key,
					model = m,
					status = Squad.status(m),
				})
			end
		end
	end
	return out
end

-- Your team's squads in order (Rules/Squads.list), each member an Entry.
function Squad.rows(): { Rules.Row }
	local team = Squad.team()
	if not team then
		return {}
	end
	return Rules.list(Cfg, team, Squad.everyone() :: any)
end

-- Your squad's row, if you are in one.
function Squad.mine(): Rules.Row?
	local key = Squad.key()
	for _, row in Squad.rows() do
		if row.key == key then
			return row
		end
	end
	return nil
end

-- "Raidho 4/6: Name (In action), ..." for the admin readout
function Squad.describe(): string
	local row = Squad.mine()
	if not row then
		local team = Squad.team()
		return if team then `Squad: none ({#Squad.rows()} on your team)` else "Squad: no team (free-for-all?)"
	end
	local parts = {}
	for _, m in row.members do
		table.insert(parts, `{m.name} ({Cfg.Status[(m :: any).status].text})`)
	end
	return `Squad: {row.name} {#row.members}/{Cfg.Max}: {table.concat(parts, ", ")}`
end

return Squad
