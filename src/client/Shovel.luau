--!strict
-- Digging with the shovel on the local client (docs/MILESTONES.md SV1; Config/Shovel): with a shovel in the hands
-- (Config/Weapons class "Shovel"), holding the fire key (Settings Key_Fire) swings it: the character attribute
-- "Digging" names the shovel's mode (src/client/Build: "Build" or "Destroy") while the key is held, and
-- src/client/Locomotion (seen by everyone) loops that mode's swing, the dig or the chip, marking each strike with
-- "DugAt" and "DugMode" (src/client/Build sends the hit). Let go and the swing playing goes on to its rest, then
-- settles to the ready (user 2026-10-24). In build mode (src/client/Build) a click lays a piece instead, and never
-- digs too; swinging, the soldier stands still (src/client/Stance).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local W = require(Shared.Config.Weapons)
local Build = require(script.Parent.Build)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Shovel = {}

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

	-- while the fire key is held: "Digging" follows the mode (R switches it mid swing), gone when the shovel can't swing
	local function run()
		running = true
		local character = player.Character
		while held do
			character = player.Character
			if character then
				character:SetAttribute("Digging", if ready(character) then Build.mode() else nil)
			end
			task.wait()
		end
		if character then
			character:SetAttribute("Digging", nil)
		end
		running = false
	end

	-- build mode as it was last frame: the click that lays a plan also leaves build mode, and may reach here after
	-- src/client/Build has handled it (user 2026-10-24: "if you left click to accept a plan, you dig as well")
	local building = false
	RunService.Heartbeat:Connect(function()
		building = Build.active()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) or building or not ready(player.Character) then
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
