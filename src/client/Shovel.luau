--!strict
-- Digging with the shovel on the local client (docs/MILESTONES.md SV1; Config/Shovel): with a shovel in the hands
-- (Config/Weapons class "Shovel"), the fire key (Settings Key_Fire) digs: the character attribute "DugAt" marks the
-- moment and "DugMode" the shovel's mode (src/client/Build), and src/client/Locomotion (third person, seen by everyone)
-- and src/client/Viewmodel (first person) play that mode's swing once over the hold: the dig in Build, the chip in
-- Destroy (user 2026-10-23). Held down, it keeps swinging, each swing running into the next (Config/Shovel `cycle`);
-- let go and the swing playing finishes (user 2026-10-24). A click before a swing's cycle is up is ignored, and in
-- build mode (src/client/Build) a click lays a piece instead. A swing builds or tears down the piece in front of you
-- (src/client/Build sends it).

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

local function spec(mode: unknown): { length: number, cycle: number, skip: number }
	return if mode == "Destroy" then Cfg.Chip else Cfg.Dig
end

-- whether this character can swing the shovel now
local function ready(character: Model?): boolean
	local weapon = Held.weapon(character)
	return character ~= nil
		and weapon ~= nil
		and W[weapon.name] ~= nil
		and W[weapon.name].class == "Shovel"
		and not Build.active()
end

function Shovel.start()
	local player = Players.LocalPlayer
	local held = false
	local running = false

	-- swings while the fire key is held: one at once, then one each cycle
	local function run()
		running = true
		while held do
			local character = player.Character
			if not character or not ready(character) then
				break
			end
			local last = character:GetAttribute("DugAt")
			local left = if type(last) == "number"
				then last + spec(character:GetAttribute("DugMode")).cycle - os.clock()
				else 0
			if left > 0 then
				task.wait(left)
			else
				-- the mode first: DugAt's change starts the swing
				character:SetAttribute("DugMode", Build.mode())
				character:SetAttribute("DugAt", os.clock())
			end
		end
		running = false
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) or not ready(player.Character) then
			return
		end
		held = true
		if not running then
			task.spawn(run)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if Settings.pressed("Key_Fire", input) then
			held = false
		end
	end)
end

return Shovel
