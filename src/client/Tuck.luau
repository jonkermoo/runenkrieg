--!strict
-- Folding the gun in (Config/Locomotion.Tuck, Rules/Tuck; user 2026-10-21: "make avatars fold their gun inwards (as
-- if their hugging it against their chest but still at ready, just make it look like they have no space) whenever
-- the barrel is blocked or about to be collided with. make a first person animation for this too"): each frame a
-- sphere is swept from the right shoulder along the look, as far as the barrel reaches at the ready hold and a little
-- more; anything in the way sets the local "Blocked" attribute, and src/client/Locomotion and src/client/Viewmodel
-- play the weapon's "tuck" hold (the body's replicates). Folded, the soldier can't aim (src/client/Stance) or fire
-- (src/client/Firing), and the third-person turn onto the crosshair lets go (src/client/LookTilt). Only weapons that
-- have a tuck hold (Config/Weapons holds.tuck) fold.
-- Before folding the gun pulls back toward the shoulder along its line, still aimed and firing (user 2026-10-25): the
-- local "Pull" attribute (0..1, eased) poses it in src/client/Viewmodel and src/client/LookTilt, and goes to the other
-- players (Net "GunPull"). It folds only when even pulled all the way back it would be in the way, and only against a
-- surface faced head on (Rules/Tuck.folds).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion).Tuck
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Tuck)
local Net = require(Shared.Net)
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

	-- the pull-back share now (eased) and what others were last sent of it
	local pull, sent, sentAt = 0, -1, -math.huge
	local remote = Net.event("GunPull")

	RunService.Heartbeat:Connect(function(dt)
		local character = player.Character
		local want = 0
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
			local d = if hit then hit.Distance else nil
			local facing = if hit then -hit.Normal:Dot(look) else 0
			blocked = Rules.folds(d, facing, reach, Cfg.Ahead, Cfg.Give, Cfg.Clear, Cfg.Facing, Cfg.FacingClear, was)
			-- (folded, the tuck hold poses the gun: no pull on top)
			want = if blocked then 0 else Rules.pull(d, reach, Cfg.Ahead, Cfg.Give)
		end
		if blocked ~= was then
			character:SetAttribute("Blocked", blocked)
		end
		pull += (want - pull) * (1 - math.exp(-Cfg.Ease * dt))
		if pull < 1e-3 and want == 0 then
			pull = 0
		end
		if character:GetAttribute("Pull") ~= pull then
			character:SetAttribute("Pull", pull) -- src/client/Viewmodel, src/client/LookTilt
		end
		local now = os.clock()
		local q = Rules.sanitizePull(pull, Cfg.Send.Step) :: number
		if q ~= sent and now - sentAt >= 1 / Cfg.Send.Rate then
			sent, sentAt = q, now
			remote:FireServer(q)
		end
	end)
end

return Tuck
