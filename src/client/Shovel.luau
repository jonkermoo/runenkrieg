--!strict
-- Digging with the shovel on the local client (docs/MILESTONES.md SV1; Config/Shovel): with a shovel in the hands
-- (Config/Weapons class "Shovel"), the fire key (Settings Key_Fire) digs: the character attribute "DugAt" marks the
-- moment and src/client/Locomotion (third person, seen by everyone) and src/client/Viewmodel (first person) play the
-- dig once over the hold. A click during a dig is ignored. The animation only: the ground isn't changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Shovel)
local W = require(Shared.Config.Weapons)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Shovel = {}

function Shovel.start()
	local player = Players.LocalPlayer
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) then
			return
		end
		local character = player.Character
		local weapon = Held.weapon(character)
		if not character or not weapon or not W[weapon.name] or W[weapon.name].class ~= "Shovel" then
			return
		end
		local last = character:GetAttribute("DugAt")
		if type(last) == "number" and os.clock() - last < Cfg.Dig.length then
			return
		end
		character:SetAttribute("DugAt", os.clock())
	end)
end

return Shovel
