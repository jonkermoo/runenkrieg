--!strict
-- First-person arms and weapon (user 2026-10-11: "once you are in first person, you play a first person client side
-- animation"; and with nothing equipped, arm animations of their own: Config/Locomotion.FirstPerson). While the camera is in first person or aiming (src/client/WeaponCamera), the player's own body arms
-- and weapon are hidden and this viewmodel is shown instead: a client-only R6 copy (invisible torso, the character's
-- arms with its shirt and body colours, a copy of the held weapon joined to the torso like the real one) fixed to the
-- camera so the camera is its eye. It plays the weapon's first-person holds (Config/Weapons firstPerson) by the
-- same "Hold" state as the body (src/client/Locomotion), and moves by the global sway layer (src/client/Sway).
-- Nothing here replicates; others see the third-person holds.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local Locomotion = require(Shared.Config.Locomotion)
local W = require(Shared.Config.Weapons)
local Held = require(script.Parent.Held)
local LookTilt = require(script.Parent.LookTilt)
local Sway = require(script.Parent.Sway)

local Viewmodel = {}

-- R6 joints (the stock rig's C0 / C1)
local ROOT = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local SHOULDERS = {
	["Right Arm"] = {
		joint = "Right Shoulder",
		c0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		c1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	},
	["Left Arm"] = {
		joint = "Left Shoulder",
		c0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		c1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	},
}

-- the torso relative to the eye: the eye is Config/Camera.Eye on the head, whose centre is 1.5 above the torso's
local EYE = Vector3.new(Cfg.Eye[1], 1.5 + Cfg.Eye[2], Cfg.Eye[3])

local function ghost(p: BasePart)
	p.Anchored = false
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	-- the Humanoid turns CanCollide back on for "Torso"; this group collides with nothing (src/server init)
	p.CollisionGroup = "Viewmodel"
	p.CastShadow = false
	p.Massless = true
	p.LocalTransparencyModifier = 0
end

type Rig = { model: Model, root: BasePart, tracks: { [string]: AnimationTrack }, tool: Tool? }

-- `weapon` nil: empty hands (Config/Locomotion.FirstPerson arm animations)
local function build(character: Model, weapon: Held.Weapon?): Rig
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	ghost(root)
	root.Anchored = true
	root.Parent = model
	local torso = root:Clone()
	torso.Name = "Torso"
	torso.Anchored = false
	torso.Parent = model
	local rootJoint = Instance.new("Motor6D")
	rootJoint.Name = "RootJoint"
	rootJoint.Part0, rootJoint.Part1 = root, torso
	rootJoint.C0, rootJoint.C1 = ROOT, ROOT
	rootJoint.Parent = root
	model.PrimaryPart = root

	for name, s in SHOULDERS do
		local source = character:FindFirstChild(name) :: BasePart?
		local arm = if source then source:Clone() else Instance.new("Part")
		arm:ClearAllChildren()
		arm.Name = name
		arm.Size = Vector3.new(1, 2, 1)
		ghost(arm)
		arm.Parent = model
		local m = Instance.new("Motor6D")
		m.Name = s.joint
		m.Part0, m.Part1 = torso, arm
		m.C0, m.C1 = s.c0, s.c1
		m.Parent = torso
	end
	-- the sleeves and skin: R6 clothing draws on parts named like the body's, under a Humanoid
	for _, c in character:GetChildren() do
		if c:IsA("Shirt") or c:IsA("BodyColors") then
			c:Clone().Parent = model
		end
	end

	-- the weapon: a copy of the held one, joined to this torso by its own "Hold" motor
	if weapon then
		local copy = weapon.tool:Clone()
		for _, d in copy:GetDescendants() do
			if d:IsA("BasePart") then
				local visible = d.Transparency
				ghost(d)
				d.Transparency = visible
			end
		end
		for _, c in copy:GetChildren() do
			c.Parent = model
		end
		copy:Destroy()
		local hold = model:FindFirstChild("Hold", true) :: Motor6D
		hold.Part0 = torso
		hold.C0, hold.C1 = CFrame.identity, CFrame.identity
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.EvaluateStateMachine = false -- no physics or states: it only carries the clothing and the Animator
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	model.Parent = workspace.CurrentCamera -- tracks loaded outside the DataModel never play

	local tracks = {}
	local set: { [string]: number } = if weapon then W[weapon.name].firstPerson :: any else Locomotion.FirstPerson
	for state, id in set do
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		local t = animator:LoadAnimation(anim)
		t.Priority = if state == "equip" then Enum.AnimationPriority.Action2 else Enum.AnimationPriority.Action
		t.Looped = state ~= "equip"
		tracks[state] = t
	end
	-- drawn just now (src/client/Locomotion marks the moment): play the rest of the equip
	local drawn = character:GetAttribute("EquippedAt")
	local since = if type(drawn) == "number" then os.clock() - drawn else math.huge
	if weapon and since < 0.55 then
		tracks.equip:Play(0)
		tracks.equip.TimePosition = since
	end
	return { model = model, root = root, tracks = tracks, tool = weapon and weapon.tool }
end

function Viewmodel.start()
	local player = Players.LocalPlayer
	-- download every weapon animation up front: a hold or equip loading late shows the gun frozen in the torso
	task.spawn(function()
		local anims = {}
		for _, w in W do
			for _, set in { w.holds, w.firstPerson } do
				for _, id in set :: any do
					local a = Instance.new("Animation")
					a.AnimationId = "rbxassetid://" .. id
					table.insert(anims, a)
				end
			end
		end
		for _, id in Locomotion.FirstPerson do
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			table.insert(anims, a)
		end
		ContentProvider:PreloadAsync(anims)
	end)
	local rig: Rig? = nil
	local playing: AnimationTrack? = nil

	local function drop()
		if rig then
			rig.model:Destroy()
			rig, playing = nil, nil
		end
	end

	-- the body's walk / sprint cycle that is playing, to keep the empty-hand arms in step with it
	local CYCLES = {
		["rbxassetid://" .. Locomotion.Animations.walk.id] = "walk",
		["rbxassetid://" .. Locomotion.Animations.sprint.id] = "sprint",
	}
	local function cycle(character: Model): (string, AnimationTrack?)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in animator:GetPlayingAnimationTracks() do
				local kind = t.Animation and CYCLES[t.Animation.AnimationId]
				if kind and t.WeightTarget > 0.5 then
					return kind, t
				end
			end
		end
		return "idle", nil
	end

	-- after WeaponCamera has placed the camera
	RunService:BindToRenderStep("Viewmodel", LookTilt.Priority + 2, function()
		local character = player.Character
		local camera = workspace.CurrentCamera
		local weapon = character and Held.weapon(character)
		local view = character and character:GetAttribute("CameraMode")
		-- empty hands in Roblox's own first person (zoomed all the way in, the camera on its focus; not measured
		-- against the head, which the sprint's lean carries forward): the arm animations
		local bare = character ~= nil
			and not character:FindFirstChildOfClass("Tool")
			and camera.CameraType == Enum.CameraType.Custom
			and (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
		local shown = if weapon then (view == "First" or view == "Aim") else bare
		if not character or not shown then
			if rig then
				rig.model.Parent = nil
			end
			if rig and (rig.tool ~= nil) ~= (weapon ~= nil) then
				drop()
			end
			return
		end
		local tool = weapon and weapon.tool
		if rig and rig.tool ~= tool then
			drop()
		end
		if not rig then
			rig = build(character, weapon)
		end
		local r = rig :: Rig
		r.root.CFrame = camera.CFrame * Sway.viewmodel() * CFrame.new(-EYE)
		r.model.Parent = camera
		local state: any = character:GetAttribute("Hold")
		local base: AnimationTrack? = nil
		if not weapon then
			state, base = cycle(character)
		end
		local track = if type(state) == "string" then r.tracks[state] else nil
		if track ~= playing then
			if playing then
				playing:Stop(Locomotion.HoldFade)
			end
			if track then
				track:Play(Locomotion.HoldFade)
			end
			playing = track
		end
		-- empty-hand walk / sprint: in step with the legs (same keyed length as the cycle)
		if track and base and base.Length > 0 and track.Length > 0 then
			local want = base.TimePosition / base.Length * track.Length
			local off = math.abs(track.TimePosition - want)
			if math.min(off, track.Length - off) > 0.03 then
				track.TimePosition = want
			end
			track:AdjustSpeed(base.Speed)
		end
	end)
	player.CharacterRemoving:Connect(drop)
end

return Viewmodel
