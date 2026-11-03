--!strict
-- Concussion (Config/Concussion, Rules/Concussion): a helmet knocked off by a hit that doesn't kill, or a blast's throw
-- survived (src/server/Damage). Keeps one { at, strength } per soldier, nothing per frame: the get-up wait reads it
-- (src/server/Ragdoll.knock), bots read it for their reaction and aim (src/server/Bots), and a player's own client is
-- told to show it (Net "Concussed", src/client/Concussion).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Concussion)
local Rules = require(Shared.Rules.Concussion)
local Net = require(Shared.Net)

local Concussion = {}

local states: { [Model]: Rules.State } = setmetatable({} :: any, { __mode = "k" })

-- Concusses `character` with `strength` (0..1) of `kind`; a weaker one over a stronger one still going changes
-- nothing. `from`: the way the hit travelled (the own view's head snap), if any.
function Concussion.hit(character: Model, strength: number, kind: Rules.Kind, from: Vector3?)
	local now = os.clock()
	local s = Rules.add(states[character], strength, kind, now, Cfg)
	if not s then
		return
	end
	states[character] = s
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		Net.event("Concussed"):FireClient(player, strength, kind, from)
	end
end

-- A helmet knocked off `character` by a hit along `direction` that left it `left` health (alive).
function Concussion.helmet(character: Model, left: number, maxHealth: number, direction: Vector3?)
	Concussion.hit(character, Rules.helmet(left, maxHealth, Cfg.Helmet), "Helmet", direction)
end

-- A blast's throw survived by `character`; `fling` how hard it was, 0..1 (its damage over
-- Config/Damage.Blast.Soldier.max).
function Concussion.blast(character: Model, fling: number)
	Concussion.hit(character, Rules.blast(fling, Cfg.Blast), "Blast")
end

-- Seconds the concussion adds to `character`'s get-up wait now (0: none).
function Concussion.getUp(character: Model): number
	return Rules.getUp(states[character], os.clock(), Cfg)
end

-- A bot's difficulty `d` with `character`'s concussion on it (`d` itself when not concussed).
function Concussion.daze(character: Model, d: any, now: number?): any
	return Rules.daze(d, states[character], now or os.clock(), Cfg)
end

return Concussion
