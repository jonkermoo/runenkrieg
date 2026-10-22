--!strict
-- Rigs (bandolier webbing, pouches only; docs/CHARACTERS.md; user 2026-10-22: "start using the random bandolier rigs
-- (use different coloring per team)"): every soldier wears one of Config/Uniforms.Rigs on the Torso, rolled once per
-- character (never the player's last life's: Rules/Looks.pick) and kept as the "Rig" attribute, colored by its kit
-- (Config/Palette.Rigs). Welded like the packs (src/server/Packs): purely visual.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local U = require(Shared.Config.Uniforms)
local Palette = require(Shared.Config.Palette)
local Looks = require(Shared.Rules.Looks)
local Packs = require(script.Parent.Packs)

local Rigs = {}

local last: { [Player]: number } = {}

-- This life's rig (the "Rig" attribute when it names one of Config/Uniforms.Rigs, else rolled now).
function Rigs.of(character: Model): string
	local current = character:GetAttribute("Rig")
	for _, r in U.Rigs do
		if r.name == current then
			return current
		end
	end
	local player = Players:GetPlayerFromCharacter(character)
	local i = Looks.pick(U.Rigs, math.random(), player and last[player])
	if player then
		last[player] = i
	end
	character:SetAttribute("Rig", U.Rigs[i].name)
	return U.Rigs[i].name
end

-- Puts this life's rig on the character in its kit's colors.
function Rigs.dress(character: Model, kitName: string)
	Packs.wear(character, "Rig", Rigs.of(character), Palette.Rigs[kitName] or {})
end

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)

return Rigs
