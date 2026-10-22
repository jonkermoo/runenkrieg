--!strict
-- A gun's butt stroke on the local client (Config/Melee, Rules/Melee; the server decides in src/server/Melee): with a
-- gun in the hands (Config/Weapons `ammo`) the melee key (Settings Key_Melee) strikes, unless the action is under way
-- (src/client/Firing.busy), ragdolled, already striking or the cooldown hasn't passed; folded in (src/client/Tuck
-- "Blocked": someone close in front) it strikes all the same. Aiming or sprinting, the strike drops the aim and the
-- sprint (src/client/Stance reads "Striking") and they come back after it if still held.
-- "StruckAt" marks the moment: src/client/Locomotion (third person, seen by everyone) and src/client/Viewmodel (first
-- person) play the strike once over the hold. At the impact the direction goes to the server ("Melee"), unless the gun
-- was put away meanwhile; "Striking" lasts until the gun is back in the hold (no shot, bolt or reload meanwhile).
-- Everyone's sounds come from the server's "Struck": the swing, then what it hit.

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

-- a sound entry, or nil while it has no file yet (id 0)
local function sound(name: string): SoundFx.Entry?
	local e = (Cfg.Sounds :: any)[name]
	return if e and e.id ~= 0 then e else nil
end

function Melee.start()
	local player = Players.LocalPlayer
	local picked = {}
	for name in Cfg.Sounds do
		picked[name] = sound(name) -- (none while its id is 0)
	end
	SoundFx.preload(picked)
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

	-- everyone's strikes: the swing, then what it hit
	Net.event("Struck").OnClientEvent:Connect(function(striker: Model, point: Vector3, what: string?)
		if typeof(striker) ~= "Instance" or typeof(point) ~= "Vector3" then
			return
		end
		local head = striker:FindFirstChild("Head")
		local swing = sound("Swing")
		if head and swing then
			SoundFx.play(swing, head)
		end
		local hit = if type(what) == "string" then sound(what) else nil
		if hit then
			SoundFx.play(hit, point)
		end
	end)
end

return Melee
