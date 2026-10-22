--!strict
-- A gun's butt stroke on the local client (Config/Melee, Rules/Melee; the server decides in src/server/Melee): with a
-- gun in the hands (Config/Weapons `ammo`) the melee key (Settings Key_Melee) strikes, unless the action is under way
-- (src/client/Firing.busy), ragdolled, already striking or the cooldown hasn't passed; folded in (src/client/Tuck
-- "Blocked": someone close in front) it strikes all the same. Aiming or sprinting, the strike drops the aim and the
-- sprint (src/client/Stance reads "Striking") and they come back after it if still held.
-- "StruckAt" marks the moment: src/client/Locomotion (third person, seen by everyone) and src/client/Viewmodel (first
-- person) play the strike once over the hold. At the impact the direction goes to the server ("Melee"), unless the gun
-- was put away meanwhile; "Striking" lasts until the gun is back in the hold (no shot, bolt or reload meanwhile).
-- The swing sound (Config/Melee.Swing): the striker's own as the butt comes forward, everyone else's on the server's
-- "Struck".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Melee)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Melee)
local Net = require(Shared.Net)
local Firing = require(script.Parent.Firing)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)
local SoundFx = require(script.Parent.SoundFx)

local Melee = {}

function Melee.start()
	local player = Players.LocalPlayer
	SoundFx.preload({ Swing = Cfg.Swing })
	local last: number? = nil

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Melee", input) then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local weapon = character and Held.weapon(character)
		if not character or not humanoid or humanoid.Health <= 0 or not weapon or not W[weapon.name].ammo then
			return
		end
		local now = os.clock()
		if
			not Rules.ready(last, now, Cfg.Strike.cooldown)
			or not Rules.free({
				busy = Firing.busy(),
				ragdolled = character:GetAttribute("Ragdolled") == true,
				striking = character:GetAttribute("Striking") == true,
			})
		then
			return
		end
		last = now
		local tool = weapon.tool
		character:SetAttribute("Striking", true)
		character:SetAttribute("StruckAt", now)
		local head = character:FindFirstChild("Head")
		if head then
			SoundFx.play(Cfg.Swing, head, nil, { delay = Cfg.Swing.delay })
		end
		task.delay(Cfg.Strike.impact, function()
			if tool.Parent == character and character:GetAttribute("StruckAt") == now then
				Net.event("Melee"):FireServer(workspace.CurrentCamera.CFrame.LookVector)
			end
		end)
		task.delay(Cfg.Strike.length, function()
			if character:GetAttribute("StruckAt") == now then
				character:SetAttribute("Striking", false)
			end
		end)
	end)

	-- everyone else's strikes: the swing
	Net.event("Struck").OnClientEvent:Connect(function(striker: Model)
		if typeof(striker) ~= "Instance" or striker == player.Character then
			return
		end
		local head = striker:FindFirstChild("Head")
		if head then
			SoundFx.play(Cfg.Swing, head)
		end
	end)
end

return Melee
