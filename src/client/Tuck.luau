--!strict
-- Folding the gun in (Config/Locomotion.Tuck, Rules/Tuck; user 2026-10-21: "make avatars fold their gun inwards (as
-- if their hugging it against their chest but still at ready, just make it look like they have no space) whenever
-- the barrel is blocked or about to be collided with. make a first person animation for this too"): each frame a
-- sphere is swept from the right shoulder along the look, as far as the barrel reaches at the ready hold and a little
-- more; anything in the way sets the local "Blocked" attribute, and src/client/Locomotion and src/client/Viewmodel
-- play the weapon's "tuck" hold (the body's replicates). Folded, the soldier can't aim (src/client/Stance) or fire
-- (src/client/Firing), and the third-person turn onto the crosshair lets go (src/client/LookTilt). Only weapons that
-- have a tuck hold (Config/Weapons holds.tuck) fold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion).Tuck
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Tuck)
local Held = require(script.Parent.Held)

local Tuck = {}

function Tuck.start()
	local player = Players.LocalPlayer
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local shoulder = Vector3.new(table.unpack(Cfg.Shoulder))
	local reaches: { [string]: number } = {}

	-- the weapon's reach from the shoulder (once per weapon)
	local function reachOf(name: string): number
		local r = reaches[name]
		if not r then
			local w = W[name] :: any
			local muzzle = w.attachments and w.attachments.Muzzle
			local scale = w.scale and w.scale[3] or 1
			r = if muzzle then Rules.reach(muzzle[3], w.grip[3], scale, Cfg.GripAhead) else 0
			reaches[name] = r
		end
		return r
	end

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local torso = character and character:FindFirstChild("Torso") :: BasePart?
		local weapon = character and Held.weapon(character)
		local camera = workspace.CurrentCamera
		if not character then
			return
		end
		local was = character:GetAttribute("Blocked") == true
		local blocked = false
		if
			humanoid
			and humanoid.Health > 0
			and torso
			and weapon
			and camera
			and (W[weapon.name] :: any).holds.tuck ~= nil
			and character:GetAttribute("Ragdolled") ~= true
		then
			local reach = reachOf(weapon.name)
			local from = torso.CFrame * shoulder
			local ignore: { Instance } = { character, camera }
			for _, name in { "GunFx", "Vfx" } do
				local f = workspace:FindFirstChild(name)
				if f then
					table.insert(ignore, f)
				end
			end
			params.FilterDescendantsInstances = ignore
			local length = reach + Cfg.Ahead + Cfg.Clear
			local hit = workspace:Spherecast(from, Cfg.Radius, camera.CFrame.LookVector * length, params)
			blocked = Rules.blocked(if hit then hit.Distance else nil, reach, Cfg.Ahead, Cfg.Clear, was)
		end
		if blocked ~= was then
			character:SetAttribute("Blocked", blocked)
		end
	end)
end

return Tuck
