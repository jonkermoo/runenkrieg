--!strict
-- The uniform kit (Config/Uniforms.Kits) a soldier wears this life (user 2026-10-21: every team spawns with its own
-- gear and the looks rolled each life). A player's next kit is rolled when they join and again when they die
-- (src/server/Deploy, user 2026-10-27: the loadout menu shows exactly what you'll spawn as), and a character takes it
-- at whichever spawn step asks first (src/server/Armory on CharacterAdded, src/server/Bodies on the appearance): the
-- player's "Kit" attribute when it names a kit (testing), else the rolled one (Rules/Looks.kit). It stays on the
-- character as the "Kit" attribute. Anything else (showcase and dev dummies) wears its "Kit" attribute or the default
-- kit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local U = require(Shared.Config.Uniforms)
local Looks = require(Shared.Rules.Looks)

local Kits = {}

-- each player's kit for their next life (rolled at the join and on each death)
local planned: { [Player]: string } = {}

-- The kit `player` spawns in next: the "Kit" attribute (testing) when it names one, else the rolled one.
function Kits.next(player: Player): string
	local kit = planned[player] or Looks.kit(nil, nil, U.Teams, math.random(), U.Kits)
	planned[player] = kit
	return Looks.kit(nil, player:GetAttribute("Kit"), { kit }, 0, U.Kits)
end

-- Rolls `player`'s next kit afresh (on a death).
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
