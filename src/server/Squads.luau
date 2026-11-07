--!strict
-- Player squads (Config/Squads, Rules/Squads; user 2026-11-06): who is in which squad. A player's squad is their
-- "Squad" attribute ("<team>:<number>"), so every client sees it (the panel: src/client/SquadPanel, the markers:
-- src/client/SquadMarkers). Every Check seconds each player's team is written as "SquadTeam" (their living
-- soldier's kit, else the kit their next life spawns in: src/server/Kits; none in a free-for-all), and a player whose
-- team is no longer their squad's leaves it. Net "Squad" (client -> server): ("New") starts a squad under the lowest
-- free rune and joins it, ("Join", key) joins one of your team's squads with room, ("Leave") leaves yours.
-- Players only: bots keep their own squads (src/server/Bots). The admin panel's test mates (fill / clear, Config/Squads.Fill)
-- put the squad attribute on bot soldiers' or dummies' models so one player can see the markers and statuses; they
-- count toward the six and go when no player is left in their squad.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Squads)
local BotsCfg = require(Shared.Config.Bots)
local DevCfg = require(Shared.Config.DevTools)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local Rules = require(Shared.Rules.Squads)
local Net = require(Shared.Net)
local Kits = require(script.Parent.Kits)

local Squads = {}

local lastAsk: { [Player]: number } = {}

-- the admin panel's test mates now in a squad (bot soldiers' and dummies' models)
local function testMates(): { Model }
	local out: { Model } = {}
	for _, tag in { BotsCfg.Tag, DevCfg.Dummies.Tag } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") and m:GetAttribute(Cfg.Attribute) ~= nil and not table.find(out, m) then
				table.insert(out, m)
			end
		end
	end
	return out
end

-- every squad's head count (players and test mates)
local function counts(): { [string]: number }
	local of: { unknown } = {}
	for _, p in Players:GetPlayers() do
		table.insert(of, p:GetAttribute(Cfg.Attribute))
	end
	for _, m in testMates() do
		table.insert(of, m:GetAttribute(Cfg.Attribute))
	end
	return Rules.counts(of)
end

-- the team whose squads `player` may join: their living soldier's kit, else their next life's; none in a free-for-all
local function teamOf(player: Player): string?
	if workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		local kit = character:GetAttribute("Kit")
		if type(kit) == "string" and kit ~= "" then
			return kit
		end
	end
	return Kits.next(player)
end

local function check()
	local withPlayers: { [string]: boolean } = {}
	for _, p in Players:GetPlayers() do
		local team = teamOf(p)
		p:SetAttribute(Cfg.TeamAttribute, team)
		local key = p:GetAttribute(Cfg.Attribute)
		if key ~= nil and not Rules.keeps(key, team) then
			p:SetAttribute(Cfg.Attribute, nil)
		elseif type(key) == "string" then
			withPlayers[key] = true
		end
	end
	for _, m in testMates() do
		local key = m:GetAttribute(Cfg.Attribute)
		local h = m:FindFirstChildOfClass("Humanoid")
		if type(key) ~= "string" or not withPlayers[key] or not h then
			m:SetAttribute(Cfg.Attribute, nil)
			m:SetAttribute(Cfg.NameAttribute, nil)
		end
	end
end

-- Starts a squad on `player`'s team under the lowest free rune and puts them in it; their new key, or nil.
function Squads.create(player: Player): string?
	local team = teamOf(player)
	if not team then
		return nil
	end
	local n = Rules.free(Cfg, counts(), team)
	if not n then
		return nil
	end
	local key = Rules.key(team, n)
	player:SetAttribute(Cfg.TeamAttribute, team)
	player:SetAttribute(Cfg.Attribute, key)
	return key
end

-- Puts `player` in squad `key` if Rules/Squads allows it; why not, or nil when they joined.
function Squads.join(player: Player, key: unknown): string?
	local team = teamOf(player)
	local why = Rules.blocked(Cfg, counts(), team, player:GetAttribute(Cfg.Attribute), key)
	if why then
		return why
	end
	player:SetAttribute(Cfg.Attribute, key :: string)
	return nil
end

function Squads.leave(player: Player)
	player:SetAttribute(Cfg.Attribute, nil)
end

-- Admin (Config/Squads.Fill): up to Max - (now in it) of `player`'s team's nearest living bot soldiers or dummies
-- become test mates of their squad (one is started if they have none). How many joined, or why none could.
function Squads.fill(player: Player): (number, string?)
	local key = player:GetAttribute(Cfg.Attribute)
	if type(key) ~= "string" then
		local made = Squads.create(player)
		if not made then
			return 0, "no team with squads (free-for-all?) or every rune taken"
		end
		key = made
	end
	local team = Rules.parse(key)
	local room = Cfg.Max - (counts()[key :: string] or 0)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local candidates: { { m: Model, d: number } } = {}
	local seen: { [Instance]: boolean } = {}
	for _, tag in { BotsCfg.Tag, DevCfg.Dummies.Tag } do
		for _, m in CollectionService:GetTagged(tag) do
			local h = m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
			local r = m:IsA("Model") and (m :: Model).PrimaryPart
			if
				h
				and h.Health > 0
				and r
				and m:GetAttribute("Kit") == team
				and m:GetAttribute(Cfg.Attribute) == nil
				and m:IsDescendantOf(workspace)
			then
				local d = if root then (r.Position - root.Position).Magnitude else 0
				if d <= Cfg.Fill.range and not seen[m] then
					seen[m] = true
					table.insert(candidates, { m = m :: Model, d = d })
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.d < b.d
	end)
	local n = 0
	for _, c in candidates do
		if n >= room then
			break
		end
		if c.m:GetAttribute(Cfg.Attribute) == nil then
			c.m:SetAttribute(Cfg.Attribute, key)
			c.m:SetAttribute(Cfg.NameAttribute, c.m.Name)
			n += 1
		end
	end
	if n == 0 then
		return 0, if room <= 0 then "squad full" else "no living soldier of your team in range"
	end
	return n, nil
end

-- Admin: every test mate leaves its squad.
function Squads.clearTestMates()
	for _, m in testMates() do
		m:SetAttribute(Cfg.Attribute, nil)
		m:SetAttribute(Cfg.NameAttribute, nil)
	end
end

function Squads.start()
	Net.event("Squad").OnServerEvent:Connect(function(player: Player, action: any, key: any)
		local now = os.clock()
		if lastAsk[player] and now - lastAsk[player] < Cfg.AskGap then
			return
		end
		lastAsk[player] = now
		if action == "New" then
			Squads.create(player)
		elseif action == "Join" then
			Squads.join(player, key)
		elseif action == "Leave" then
			Squads.leave(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastAsk[p] = nil
	end)
	task.spawn(function()
		while true do
			check()
			task.wait(Cfg.Check)
		end
	end)
end

return Squads
