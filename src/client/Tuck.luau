--!strict
-- Folding the gun in (Config/Locomotion.Tuck, Rules/Tuck; user 2026-10-21: "make avatars fold their gun inwards (as
-- if their hugging it against their chest but still at ready, just make it look like they have no space) whenever
-- the barrel is blocked or about to be collided with. make a first person animation for this too"): each frame a
-- sphere is swept from the right shoulder along the look, as far as the barrel reaches at the ready hold and a little
-- more; anything in the way sets the local "Blocked" attribute, and src/client/Locomotion and src/client/Viewmodel
-- play the weapon's "tuck" hold (the body's replicates). Folded, the soldier can't aim (src/client/Stance) or fire
-- (src/client/Firing), and the third-person turn onto the crosshair lets go (src/client/LookTilt). Only weapons that
-- have a tuck hold (Config/Weapons holds.tuck) fold. A trench's dirt folds it only head on at the barrel's reach
-- (Rules/Tuck.trenchBlocked), so a soldier in a trench can aim along it or out of it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion).Tuck
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Tuck)
local BuildCfg = require(Shared.Config.Build)
local BuildRules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local Held = require(script.Parent.Held)

local T = BuildCfg.Trench
local TOP = BuildRules.trenchTop(T)

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

	-- whether a sweep's hit is a trench's dirt: one of its pieces, or the ground in its hole, walls or banks
	local function trenchDirt(hit: RaycastResult): boolean
		local built = workspace:FindFirstChild(BuildCfg.Folder)
		if not built then
			return false
		end
		if hit.Instance ~= workspace.Terrain then
			local m = hit.Instance:FindFirstAncestorWhichIsA("Model")
			return m ~= nil and m.Parent == built and m:GetAttribute("Kind") == "TrenchBlock"
		end
		for _, m in built:GetChildren() do
			local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
			if
				typeof(a) == "Vector3"
				and typeof(b) == "Vector3"
				and Survey.toSegment(hit.Position, a, b) <= TOP + T.bank.width + T.shotSlack
			then
				return true
			end
		end
		return false
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
			local look = camera.CFrame.LookVector
			local hit = workspace:Spherecast(from, Cfg.Radius, look * length, params)
			if hit and trenchDirt(hit) then
				-- trench dirt folds the gun only head on and at the barrel's reach; past it, the sweep goes on without the
				-- ground and the trenches for anything else in the way
				blocked =
					Rules.trenchBlocked(hit.Distance, -hit.Normal:Dot(look), reach, Cfg.TrenchFacing, Cfg.Clear, was)
				if not blocked then
					local built = workspace:FindFirstChild(BuildCfg.Folder)
					table.insert(ignore, workspace.Terrain)
					for _, m in (if built then built:GetChildren() else {}) do
						if m:GetAttribute("Kind") == "TrenchBlock" then
							table.insert(ignore, m)
						end
					end
					params.FilterDescendantsInstances = ignore
					hit = workspace:Spherecast(from, Cfg.Radius, look * length, params)
					blocked = Rules.blocked(if hit then hit.Distance else nil, reach, Cfg.Ahead, Cfg.Clear, was)
				end
			else
				blocked = Rules.blocked(if hit then hit.Distance else nil, reach, Cfg.Ahead, Cfg.Clear, was)
			end
		end
		if blocked ~= was then
			character:SetAttribute("Blocked", blocked)
		end
	end)
end

return Tuck
