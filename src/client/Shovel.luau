--!strict
-- Digging with the shovel on the local client (docs/MILESTONES.md SV1; Config/Shovel): with a shovel in the hands
-- (Config/Weapons class "Shovel"), the fire key (Settings Key_Fire) digs: the character attribute "DugAt" marks the
-- moment and src/client/Locomotion (third person, seen by everyone) and src/client/Viewmodel (first person) play the
-- dig once over the hold. When the blade strikes (Dig.strike in) the server is told (Net "Dig") and lowers the ground
-- there (src/server/Shovel); every client throws up dirt where it was dug (Net "Dug"). A click during a dig is ignored.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Shovel)
local W = require(Shared.Config.Weapons)
local Net = require(Shared.Net)
local Held = require(script.Parent.Held)
local Impacts = require(script.Parent.Impacts)
local Settings = require(script.Parent.Settings)

local Shovel = {}

local function holdsShovel(character: Model?): boolean
	local weapon = Held.weapon(character)
	return weapon ~= nil and W[weapon.name] ~= nil and W[weapon.name].class == "Shovel"
end

function Shovel.start()
	local player = Players.LocalPlayer
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) then
			return
		end
		local character = player.Character
		if not character or not holdsShovel(character) then
			return
		end
		local last = character:GetAttribute("DugAt")
		if type(last) == "number" and os.clock() - last < Cfg.Dig.length then
			return
		end
		local at = os.clock()
		character:SetAttribute("DugAt", at)
		task.delay(Cfg.Dig.strike, function()
			-- still the same dig, the shovel still in the hands
			if player.Character == character and character:GetAttribute("DugAt") == at and holdsShovel(character) then
				Net.event("Dig"):FireServer()
			end
		end)
	end)
	Net.event("Dug").OnClientEvent:Connect(function(position: Vector3)
		if typeof(position) == "Vector3" then
			Impacts.dirt(position, Cfg.Chips)
		end
	end)
end

return Shovel
