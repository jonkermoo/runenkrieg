--!strict
-- Digging with the shovel on the local client (docs/MILESTONES.md SV1; Config/Shovel): with a shovel in the hands
-- (Config/Weapons class "Shovel"), the fire key (Settings Key_Fire) digs: the character attribute "DugAt" marks the
-- moment and "DugMode" the shovel's mode (src/client/Build), and src/client/Locomotion (third person, seen by everyone)
-- and src/client/Viewmodel (first person) play that mode's swing once over the hold: the dig in Build, the chip in
-- Destroy (user 2026-10-23). A click during a swing is ignored, and in build mode (src/client/Build) a click lays a
-- piece instead. A swing builds or tears down the piece in front of you (src/client/Build sends it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Shovel)
local W = require(Shared.Config.Weapons)
local Build = require(script.Parent.Build)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Shovel = {}

function Shovel.start()
	local player = Players.LocalPlayer
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) or Build.active() then
			return
		end
		local character = player.Character
		local weapon = Held.weapon(character)
		if not character or not weapon or not W[weapon.name] or W[weapon.name].class ~= "Shovel" then
			return
		end
		local last = character:GetAttribute("DugAt")
		local length = if character:GetAttribute("DugMode") == "Destroy" then Cfg.Chip.length else Cfg.Dig.length
		if type(last) == "number" and os.clock() - last < length then
			return
		end
		-- the mode first: DugAt's change starts the swing
		character:SetAttribute("DugMode", Build.mode())
		character:SetAttribute("DugAt", os.clock())
	end)
end

return Shovel
