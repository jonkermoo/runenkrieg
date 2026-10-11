--!strict
-- First-person arms and weapon (user 2026-10-11: "once you are in first person, you play a first person client side
-- animation"). While the camera is in first person or aiming (src/client/WeaponCamera), the player's own body arms
-- and weapon are hidden and this viewmodel is shown instead: a client-only R6 copy (invisible torso, the character's
-- arms with its shirt and body colours, a copy of the held weapon joined to the torso like the real one) fixed to the
-- camera so the camera is its eye. It plays the weapon's first-person holds (Config/Weapons firstPerson) by the
-- same "Hold" state as the body (src/client/Locomotion), and moves by the global sway layer (src/client/Sway).
-- Aiming starts with a brief aim-in (firstPerson.aimIn, 0.3 s: the rifle comes up into the sights) over the aim hold,
-- while the body plays its third-person aim for everyone. Coming into view (into first person, or aiming from the
-- shoulder camera) the viewmodel starts in its pose at once: fading in from the rig's rest pose showed the gun rising
-- from the middle of the screen (user 2026-10-11).
-- Nothing here replicates; others see the third-person holds.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
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

type Rig = { model: Model, root: BasePart, tracks: { [string]: AnimationTrack }, tool: Tool }

local function build(character: Model, weapon: Held.Weapon): Rig
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
	for state, id in W[weapon.name].firstPerson do
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		local t = animator:LoadAnimation(anim)
		-- the equip and the aim-in are one shots over the holds
		local once = state == "equip" or state == "aimIn"
		t.Priority = if once then Enum.AnimationPriority.Action2 else Enum.AnimationPriority.Action
		t.Looped = not once
		tracks[state] = t
	end
	-- drawn just now (src/client/Locomotion marks the moment): play the rest of the equip
	local drawn = character:GetAttribute("EquippedAt")
	local since = if type(drawn) == "number" then os.clock() - drawn else math.huge
	if since < 0.55 then
		tracks.equip:Play(0)
		tracks.equip.TimePosition = since
	end
	return { model = model, root = root, tracks = tracks, tool = weapon.tool }
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

	-- after WeaponCamera has placed the camera
	RunService:BindToRenderStep("Viewmodel", LookTilt.Priority + 2, function()
		local character = player.Character
		local weapon = character and Held.weapon(character)
		local view = character and character:GetAttribute("CameraMode")
		if not character or not weapon or (view ~= "First" and view ~= "Aim") then
			if rig then
				rig.model.Parent = nil
				-- out of view the holds stop, so coming back (aiming again) starts afresh with the aim-in
				for _, t in rig.tracks do
					t:Stop(0)
				end
				playing = nil
			end
			if not weapon then
				drop()
			end
			return
		end
		if rig and rig.tool ~= weapon.tool then
			drop()
		end
		local appearing = not rig or (rig :: Rig).model.Parent == nil
		if not rig then
			rig = build(character, weapon)
		end
		local r = rig :: Rig
		local camera = workspace.CurrentCamera
		-- a track started now poses the rig only from the next frame: the frame it comes into view it waits out of
		-- sight below the camera, or that frame shows the rig's rest pose (the gun in the middle of the screen)
		local below = if appearing then CFrame.new(0, -50, 0) else CFrame.identity
		r.root.CFrame = camera.CFrame * below * Sway.viewmodel() * CFrame.new(-EYE)
		r.model.Parent = camera
		local state = character:GetAttribute("Hold")
		local track = if type(state) == "string" then r.tracks[state] else nil
		local aimIn = r.tracks.aimIn
		if track ~= playing then
			-- coming into view: straight into the pose, never faded in from the rig's rest pose
			local fade = if appearing then 0 else Cfg.ViewmodelFade
			if state == "aim" and aimIn then
				-- aiming starts: the brief aim-in carries the gun up into the sights over the aim hold
				fade = 0
				aimIn:Play(0)
			elseif aimIn and aimIn.IsPlaying then
				aimIn:Stop(fade) -- let go of aim before the gun reached the sights
			end
			if playing then
				playing:Stop(fade)
			end
			if track then
				track:Play(fade)
			end
			playing = track
		end
	end)
	player.CharacterRemoving:Connect(drop)
end

return Viewmodel
