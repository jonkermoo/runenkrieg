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
	local aimFrom = Vector3.new(table.unpack(Cfg.TrenchFrom))
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
			-- anything but trench dirt: pulled back first, folded only head on and only when even pulled back it would be
			-- in the way (Rules/Tuck.folds)
			local function general(h: RaycastResult?)
				local d = if h then h.Distance else nil
				local facing = if h then -h.Normal:Dot(look) else 0
				blocked =
					Rules.folds(d, facing, reach, Cfg.Ahead, Cfg.Give, Cfg.Clear, Cfg.Facing, Cfg.FacingClear, was)
				-- (folded, the tuck hold poses the gun: no pull on top)
				want = if blocked then 0 else Rules.pull(d, reach, Cfg.Ahead, Cfg.Give)
			end
			if hit and trenchDirt(hit) then
				-- near trench dirt the sweep runs along the shouldered gun's line instead (over a parapet the soldier rests
				-- the rifle on), and trench dirt folds the gun only head on and at the barrel's reach; past it, the sweep
				-- goes on without the ground and the trenches for anything else in the way
				from = torso.CFrame * aimFrom
				hit = workspace:Spherecast(from, Cfg.Radius, look * length, params)
				if hit and not trenchDirt(hit) then
					general(hit)
				else
					blocked = hit ~= nil
						and Rules.trenchBlocked(
							hit.Distance,
							-hit.Normal:Dot(look),
							reach,
							Cfg.TrenchFacing,
							Cfg.Clear,
							was
						)
				end
				if hit and not blocked and trenchDirt(hit) then
					local built = workspace:FindFirstChild(BuildCfg.Folder)
					table.insert(ignore, workspace.Terrain)
					for _, m in (if built then built:GetChildren() else {}) do
						if m:GetAttribute("Kind") == "TrenchBlock" then
							table.insert(ignore, m)
						end
					end
					params.FilterDescendantsInstances = ignore
					hit = workspace:Spherecast(from, Cfg.Radius, look * length, params)
					general(hit)
				end
			else
				general(hit)
			end
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
