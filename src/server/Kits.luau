--!strict
-- The uniform kit (Config/Uniforms.Kits) a soldier wears this life (user 2026-10-21: every team spawns with its own
-- gear and the looks rolled each life). A player's is rolled once per character, at whichever spawn step asks first
-- (src/server/Armory on CharacterAdded, src/server/Bodies on the appearance): the player's "Kit" attribute when it
-- names a kit (testing), else one of Config/Uniforms.Teams at random (Rules/Looks.kit). It stays on the character as
-- the "Kit" attribute. Anything else (showcase and dev dummies) wears its "Kit" attribute or the default kit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local U = require(Shared.Config.Uniforms)
local Looks = require(Shared.Rules.Looks)

local Kits = {}

function Kits.of(character: Model): string
	local player = Players:GetPlayerFromCharacter(character)
	local pool = if player then U.Teams else { U.Default }
	local kit =
		Looks.kit(character:GetAttribute("Kit"), player and player:GetAttribute("Kit"), pool, math.random(), U.Kits)
	character:SetAttribute("Kit", kit)
	return kit
end

return Kits
