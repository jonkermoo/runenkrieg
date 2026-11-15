--!strict
-- Rigs (bandolier webbing, pouches only; docs/CHARACTERS.md): every soldier wears its kit's rig (Config/Uniforms.Kits
-- `rig`, one per team since 2026-11-14), or else one of Config/Uniforms.Rigs on the
-- Torso (one rig for every class since 2026-11-14; with more, rolled once per character, never the player's last
-- life's: Rules/Looks.pick), kept as the "Rig" attribute, colored by its kit (Config/Palette.Rigs) in its class's tone
-- (Config/Classes.Tones), so it matches the class's bag. Welded like the packs (src/server/Packs): purely visual.

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

-- Puts this life's rig on the character in its kit's colors, in class `class`'s tone as its bag (Config/Classes.Tones).
-- The kit's own rig (Config/Uniforms.Kits `rig`, user 2026-11-14) when it names one.
function Rigs.dress(character: Model, kitName: string, class: string?)
	local kit = U.Kits[kitName]
	local entry = kit and kit.rig or Rigs.of(character)
	Packs.wear(character, "Rig", entry, Packs.toned(Palette.Rigs[kitName] or {}, class))
end

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)

return Rigs
