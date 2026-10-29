--!strict
-- The uniform kit (Config/Uniforms.Kits) a soldier wears this life (user 2026-10-21: every team spawns with its own
-- gear and the looks rolled each life). A player's next kit is rolled when they join and again when they die
-- (src/server/Deploy, user 2026-10-27: the loadout menu shows exactly what you'll spawn as; where teams are kept,
-- Config/Teams, it is placed on the smallest team at the join and kept until a team change), and a character takes it
-- at whichever spawn step asks first (src/server/Armory on CharacterAdded, src/server/Bodies on the appearance): the
-- player's "Kit" attribute when it names a kit (testing), else the rolled one (Rules/Looks.kit). It stays on the
-- character as the "Kit" attribute. Anything else (showcase and dev dummies) wears its "Kit" attribute or the default
-- kit. In Normal mode only the match's two teams are rolled or kept (Workspace's MatchTeams, Rules/Teams.playing): a
-- planned kit of a team that isn't playing is rolled again from them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Front = require(Shared.Config.Frontline)
local U = require(Shared.Config.Uniforms)
local Looks = require(Shared.Rules.Looks)
local Teams = require(Shared.Rules.Teams)

local Kits = {}

-- each player's kit for their next life (rolled at the join and on each death)
local planned: { [Player]: string } = {}

-- The teams in play: the match's two in Normal mode, else all.
function Kits.playing(): { string }
	return Teams.playing(U.Teams, workspace:GetAttribute(Front.TeamsAttribute))
end

-- The kit `player` spawns in next: the "Kit" attribute (testing) when it names one, else the rolled one.
function Kits.next(player: Player): string
	local pool = Kits.playing()
	local kit = planned[player]
	if not kit or not table.find(pool, kit) then
		kit = Looks.kit(nil, nil, pool, math.random(), U.Kits)
	end
	planned[player] = kit
	return Looks.kit(nil, player:GetAttribute("Kit"), { kit }, 0, U.Kits)
end

-- Puts `player` on team `kit` from their next life on (kept teams, src/server/Deploy), dropping a testing pin.
function Kits.place(player: Player, kit: string)
	planned[player] = kit
	player:SetAttribute("Kit", nil)
end

-- Rolls `player`'s next kit afresh (on a death, where teams aren't kept).
function Kits.reroll(player: Player)
	planned[player] = nil
	Kits.next(player)
end

function Kits.of(character: Model): string
	local player = Players:GetPlayerFromCharacter(character)
	local pool = if player then { Kits.next(player) } else { U.Default }
	local kit = Looks.kit(character:GetAttribute("Kit"), nil, pool, 0, U.Kits)
	character:SetAttribute("Kit", kit)
	return kit
end

Players.PlayerRemoving:Connect(function(p)
	planned[p] = nil
end)

return Kits
