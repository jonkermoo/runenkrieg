--!strict
-- First-person arms and weapon (user 2026-10-11: "once you are in first person, you play a first person client side
-- animation"). While the camera is in first person or aiming (src/client/WeaponCamera), the player's own body arms
-- and weapon are hidden and this viewmodel is shown instead: a client-only R6 copy (invisible torso, the character's
-- arms with its shirt and body colours, a copy of the held weapon joined to the torso like the real one) fixed to the
-- camera so the camera is its eye. It plays the weapon's first-person holds (Config/Weapons firstPerson) by the
-- same "Hold" state as the body (src/client/Locomotion), and moves by the global sway layer (src/client/Sway).
-- It is on while WeaponCamera says "CameraInside" and fades in by its "Handover": gliding in from the shoulder it
-- fades in over the last stretch to the eye as the body fades out (user 2026-10-11: ADS looked choppy). It never
-- shows the rig's rest pose (the gun rising from the middle of the screen). Aiming plays a brief aim-in
-- (firstPerson.aimIn, 0.3 s: the rifle comes up from the ready hold into the sights) over the aim hold, as long as the
-- camera's glide, while the body plays its third-person aim for everyone. Writes "ViewmodelShown" (local) for
-- WeaponCamera to hide the body.
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
-- at the hip the rifle sits this far from where the ready hold puts it (Config/Camera.HipShift: the action in frame)
local HIP_SHIFT = Vector3.new(Cfg.HipShift[1], Cfg.HipShift[2], Cfg.HipShift[3])

-- Aimed, a rifle's own sight line goes onto the eye. A rifle borrowing another's holds (Config/Weapons `holdsOf`)
-- is posed where that rifle's sights sit on the eye; its own Aim is off by the difference (the SMLE's sights are 0.05
-- stud higher in game than the Carcano's), so the rig moves by it. From the configs, not measured: known before the
-- first aim and never read off a pose in motion.
local function aimFix(name: string): Vector3
	local w = W[name]
	local ref = w.holdsOf and W[w.holdsOf]
	if not ref then
		return Vector3.zero
	end
	local a, b = w.attachments.Aim, ref.attachments.Aim
	return Vector3.new(b[1] * ref.scale[1] - a[1] * w.scale[1], b[2] * ref.scale[2] - a[2] * w.scale[2], 0)
end

local function ghost(p: BasePart)
	p.Anchored = false
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	-- the Humanoid turns CanCollide back on for "Torso"; this group collides with nothing (src/server init)
	p.CollisionGroup = "Viewmodel"
	p.CastShadow = false
	p.Massless = true
	p.LocalTransparencyModifier = 0
end

type Rig = {
	model: Model,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	tool: Tool,
	clear: number,
	hip: CFrame, -- the turn that points the barrel at the screen centre (not aiming), eased
	aimFix: Vector3, -- aimed: the shift that puts this rifle's own sight line on the eye (see aimFix)
	animator: Animator,
}

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
	return {
		model = model,
		root = root,
		tracks = tracks,
		tool = weapon.tool,
		clear = -1,
		hip = CFrame.identity,
		aimFix = aimFix(weapon.name),
		animator = animator,
	}
end

function Viewmodel.start()
	local player = Players.LocalPlayer
	-- download every weapon animation up front: a hold or equip loading late shows the gun frozen in the torso
	task.spawn(function()
		local anims = {}
		for _, w in W do
			for _, set in { w.holds, w.firstPerson, { w.reload.body, w.reload.firstPerson, w.bolt.aim, w.bolt.ready } } do
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
	RunService:BindToRenderStep("Viewmodel", LookTilt.Priority + 2, function(dt)
		local character = player.Character
		local weapon = character and Held.weapon(character)
		if character then
			character:SetAttribute("ViewmodelShown", rig ~= nil and rig.model.Parent ~= nil)
		end
		if not character or not weapon or character:GetAttribute("CameraInside") ~= true then
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
		-- not aiming, the rifle turns about the eye until its barrel meets the centre line Config/Camera.HipConverge
		-- out (hip fire goes about where the screen centre is); measured in the rig's own frame, so the sway on top
		-- and the turn never feed back into each other
		local want = r.hip
		local gun = r.model:FindFirstChild("Gun")
		local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
		local rising = r.tracks.aimIn
		-- (reloading, the rifle is posed by the reload: the turn holds still, src/client/GunFx "Reloading")
		local atHip = character:GetAttribute("Hold") == "ready"
			and not (rising and rising.IsPlaying)
			and character:GetAttribute("Reloading") ~= true
		if muzzle and atHip then
			-- the barrel in the rig's own eye frame: its pose, before the turn is applied (the turn rotates that frame),
			-- moved by the hip shift
			local frame = r.root.CFrame * CFrame.new(EYE)
			local p = frame:PointToObjectSpace(muzzle.WorldPosition) + HIP_SHIFT
			local d = frame:VectorToObjectSpace(muzzle.WorldCFrame.LookVector)
			-- the point on the barrel's line HipConverge from the eye; turning it onto the centre line puts the whole
			-- line through the screen centre there (turning only the barrel's direction leaves the muzzle swung aside)
			local D = Cfg.HipConverge
			local b = p:Dot(d)
			local disc = b * b - (p:Dot(p) - D * D)
			want = CFrame.identity
			if disc > 0 then
				local q = (p + d * (-b + math.sqrt(disc))).Unit
				local axis = q:Cross(Vector3.new(0, 0, -1))
				if axis.Magnitude > 1e-5 then
					want = CFrame.fromAxisAngle(axis.Unit, math.asin(math.clamp(axis.Magnitude, -1, 1)))
				end
			end
		end
		r.hip = r.hip:Lerp(want, 1 - math.exp(-Cfg.HipEase * math.min(dt, 0.1)))
		-- how much of the pose is the hip (ready) hold and how much the aim, from the tracks themselves, so the hip
		-- shift and turn and the aimed sight fix blend exactly as the poses crossfade (user 2026-10-13: eased on their
		-- own they twitched starting to move and going in and out of the sights). The aim-in starts at the ready pose and
		-- ends in the sights: its progress hands one over to the other.
		local progress = if rising
				and rising.IsPlaying
				and rising.Length > 0
			then math.clamp(rising.TimePosition / rising.Length, 0, 1)
			else nil
		local hipness, aimness = 1 - (progress or 0), progress or 0
		if not progress then
			-- each hold's share of the pose: the holds share one priority, so the pose is their weights' mix. Only the
			-- tracks the animator still plays count (a stopped one keeps reporting its last weight; one fading out reads
			-- IsPlaying false but still poses), and a hold starting reads full weight at once: the one fading out sets
			-- the pace (KNOWN_TRAPS).
			local live = {}
			for _, t in r.animator:GetPlayingAnimationTracks() do
				live[t] = true
			end
			local function weight(t: AnimationTrack?): number
				return if t and live[t] then t.WeightCurrent else 0
			end
			local wReady, wAim, wCarry = weight(r.tracks.ready), weight(r.tracks.aim), weight(r.tracks.carry)
			local total = wReady + wAim + wCarry
			hipness = if total > 0 then wReady / total else 0
			aimness = if total > 0 then wAim / total else 0
		end
		r.root.CFrame = camera.CFrame
			* below
			* Sway.viewmodel()
			* CFrame.new():Lerp(r.hip, hipness)
			* CFrame.new(HIP_SHIFT * hipness + r.aimFix * aimness)
			* CFrame.new(-EYE)
		r.model.Parent = camera
		-- fading in (and out) with the camera's glide to the eye (WeaponCamera's "Handover")
		local handover = character:GetAttribute("Handover")
		local clear = 1 - (if type(handover) == "number" then handover else 1)
		if r.clear ~= clear then
			r.clear = clear
			for _, d in r.model:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = clear
				end
			end
		end
		local state = character:GetAttribute("Hold")
		local track = if type(state) == "string" then r.tracks[state] else nil
		local aimIn = r.tracks.aimIn
		if track ~= playing then
			-- coming into view: straight into the pose, never faded in from the rig's rest pose
			local fade = if appearing then 0 else Cfg.ViewmodelFade
			local out = fade
			if state == "aim" and aimIn then
				-- aiming starts: the brief aim-in carries the gun up into the sights over the aim hold
				fade = 0
				aimIn:Play(0)
				-- the hold left behind fades out under the aim-in (which covers it) rather than stopping dead: a track
				-- stopped with no fade keeps weight 1 and, played again, would start from it, snapping the pose when
				-- aiming ends (KNOWN_TRAPS)
				out = aimIn.Length * 0.8
			elseif aimIn and aimIn.IsPlaying then
				aimIn:Stop(fade) -- let go of aim before the gun reached the sights
			end
			if playing then
				playing:Stop(out)
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
