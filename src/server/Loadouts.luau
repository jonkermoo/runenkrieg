--!strict
-- Classes and the match currency (Config/Classes, Rules/Classes; user 2026-10-27). Each player's points live here on
-- the server only (never an attribute: the player sees them only in the loadout menu while respawning). A soldier's
-- class is settled once per character, at whichever spawn step asks first (src/server/Armory for the weapons,
-- src/server/Bodies for the helmet): their pick if they can pay for it (paid then), else the free default. It stays on
-- the character as the "Class" attribute (src/client/Build reads it for the build gate). Anything that isn't a
-- player's character (showcase and dev dummies) is its "Class" attribute or the default, and pays nothing.
-- Points: Loadouts.hurt (src/server/Damage) notes who hurt whom; on a death the killer and the assists are paid
-- (Rules/Classes.credit). Loadouts.award pays the rest (src/server/Build: pieces and trench squares built; the zone
-- capture: "Capture"). Loadouts.resetMatch starts a new match: everyone's points back to Config/Classes.Start and the
-- picks back to the default. Until there are matches, a server is one match.
-- Net "Loadout": client -> server ("Pick", class) | ("Ask") | ("Deploy") | ("Team", kit: a team change where teams are
-- kept, Config/Teams: src/server/Deploy checks the balance again and moves them, and their points go back to
-- Config/Classes.Start, user 2026-10-27: "leaving your team will reset your battle points"); server -> client (Rules/Classes.State plus
-- src/server/Deploy's `wait` and `alive`) on each death (the menu opens while respawning) and in answer to each pick
-- or ask. src/server/Deploy spawns the player on "Deploy" and builds the menu's preview soldier (Loadouts.bind).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Classes)
local DevCfg = require(Shared.Config.DevTools)
local U = require(Shared.Config.Uniforms)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Classes)
local Kits = require(script.Parent.Kits)

local Loadouts = {}

local points: { [Player]: number } = {}
local picks: { [Player]: string } = {}
-- the hits each soldier took this life, by players (Rules/Classes.credit)
local hits: { [Model]: { Rules.Hit } } = setmetatable({}, { __mode = "k" }) :: any

function Loadouts.points(player: Player): number
	return points[player] or C.Start
end

-- The class `character` is this life (settled and paid at the first ask).
function Loadouts.classOf(character: Model): string
	local current = character:GetAttribute("Class")
	if type(current) == "string" and C.Defs[current] then
		return current
	end
	local player = Players:GetPlayerFromCharacter(character)
	local key = C.Default
	if player then
		local cost
		key, cost = Rules.resolve(
			picks[player],
			Loadouts.points(player),
			C.Defs,
			C.Default,
			player:GetAttribute(DevCfg.Admin.ClassAttribute)
		)
		points[player] = Loadouts.points(player) - cost
	end
	character:SetAttribute("Class", key)
	return key
end

-- The gear `character` carries this life (its class in its kit).
function Loadouts.gear(character: Model): Rules.Gear
	return Rules.gear(Loadouts.classOf(character), Kits.of(character), C.Defs, U.Kits, C.Gear)
end

-- Whether `character`'s class may build a piece of `kind` (Config/Build.Pieces).
function Loadouts.mayBuild(character: Model, kind: string): boolean
	return Rules.mayBuild(Loadouts.classOf(character), kind, C.Defs, C.Default)
end

-- src/server/Deploy's part (Loadouts.bind): what changed (a pick or a death) before the state goes out, a deploy, and
-- the state's spawn fields
type Deployer = {
	changed: (Player, string) -> (),
	deploy: (Player) -> (),
	team: (Player, any) -> boolean,
	fields: (Player) -> { [string]: any },
}
local deployer: Deployer? = nil

function Loadouts.bind(d: Deployer)
	deployer = d
end

-- The class `player` has picked for their next life.
function Loadouts.picked(player: Player): string
	return picks[player] or C.Default
end

local function state(player: Player): Rules.State
	local character = player.Character
	local current = character and character:GetAttribute("Class")
	return Rules.state(
		Loadouts.points(player),
		picks[player] or C.Default,
		if type(current) == "string" then current else nil,
		C.List,
		C.Defs
	)
end

local function send(player: Player)
	local s: any = state(player)
	if deployer then
		for k, v in deployer.fields(player) do
			s[k] = v
		end
	end
	Net.event("Loadout"):FireClient(player, s)
end

-- Pays `player` the Config/Classes.Earn for `reason` ("Kill", "Assist", "Capture", "Piece", ...), `times` over.
function Loadouts.award(player: Player, reason: string, times: number?)
	local amount = C.Earn[reason]
	assert(amount, "unknown award " .. reason)
	points[player] = Rules.earn(Loadouts.points(player), amount * (times or 1))
end

-- Admin (src/server/DevTools): `amount` match points for `player`, the loadout menu told.
function Loadouts.grant(player: Player, amount: number)
	points[player] = Rules.earn(Loadouts.points(player), amount)
	send(player)
end

-- A soldier hurt by `by` (src/server/Damage): `amount` health off, `zone` where (nil: a blast or a staff shot).
function Loadouts.hurt(victim: Model, by: Model?, amount: number, zone: string?)
	local player = by and Players:GetPlayerFromCharacter(by)
	if not player or by == victim or amount <= 0 then
		return
	end
	local list = hits[victim]
	if not list then
		list = {}
		hits[victim] = list
	end
	table.insert(list, { by = player.UserId, amount = amount, at = os.clock(), zone = zone })
end

-- `fn(killer, victim)` on each kill credited to a player (src/server/Frontline: Defend)
local killWatchers: { (Player, Model) -> () } = {}
function Loadouts.onKill(fn: (Player, Model) -> ())
	table.insert(killWatchers, fn)
end

local function died(character: Model)
	local victim = Players:GetPlayerFromCharacter(character)
	local A = C.Assist
	local killer, head, assists =
		Rules.credit(hits[character] or {}, victim and victim.UserId, os.clock(), A.window, A.least)
	hits[character] = nil
	local k = killer and Players:GetPlayerByUserId(killer)
	if k then
		Loadouts.award(k, "Kill")
		if head then
			Loadouts.award(k, "Headshot")
		end
		for _, fn in killWatchers do
			task.spawn(fn, k, character)
		end
	end
	for _, id in assists do
		local a = Players:GetPlayerByUserId(id)
		if a then
			Loadouts.award(a, "Assist")
		end
	end
	if victim then
		if deployer then
			deployer.changed(victim, "Died")
		end
		send(victim) -- the menu opens while respawning
	end
end

-- A new match: everyone's points back to the start, picks back to the default.
function Loadouts.resetMatch()
	table.clear(points)
	table.clear(picks)
end

Loadouts.send = send

function Loadouts.start()
	local function spawned(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Connect(function()
				died(character)
			end)
		end
	end
	local function hook(player: Player)
		player.CharacterAdded:Connect(spawned)
		if player.Character then
			task.spawn(spawned, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		points[p] = nil
		picks[p] = nil
	end)
	Net.event("Loadout").OnServerEvent:Connect(function(player: Player, action: any, key: any)
		if action == "Pick" and Rules.pickable(key, C.Defs) then
			picks[player] = key
			if deployer then
				deployer.changed(player, "Pick")
			end
		elseif action == "Team" then
			if deployer and deployer.team(player, key) then
				points[player] = C.Start
				deployer.changed(player, "Team")
			end
		elseif action == "Deploy" then
			if deployer then
				deployer.deploy(player)
			end
			return
		elseif action ~= "Ask" then
			return
		end
		send(player)
	end)
end

return Loadouts
