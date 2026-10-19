--!strict
-- Healing in first person (H1; user 2026-10-19: "we just need a first person animation as well"). Only when the player
-- is already zoomed into first person (the free camera within Config/Healing.First.Zoom of the head; user: "only if
-- already in first person"), where Roblox hides the body: a client-only pair of arms fixed to the eye (the character's
-- arm parts with its shirt and colours, like src/client/Viewmodel's rig, no weapon) plays the first-person healing
-- animations (Config/Healing.First) and carries client copies of the items through the same steps as the body's
-- (src/shared/HealItems: taken from the pack, the strip unrolling, the med pack opened), the hands low in the view at
-- the patient. Nothing here replicates; others see the third-person animations (src/client/Healing).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CamCfg = require(Shared.Config.Camera)
local Cfg = require(Shared.Config.Healing)
local HealItems = require(Shared.HealItems)
local LookTilt = require(script.Parent.LookTilt)

local HealView = {}

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
-- the torso below the eye (Config/Camera.Eye on the head, the head's centre 1.5 above the torso's)
local EYE = Vector3.new(CamCfg.Eye[1], 1.5 + CamCfg.Eye[2], CamCfg.Eye[3])

local function ghost(p: BasePart)
	p.Anchored = false
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CollisionGroup = "Viewmodel" -- collides with nothing (src/server init)
	p.CastShadow = false
	p.Massless = true
	p.LocalTransparencyModifier = 0
end

type Rig = {
	model: Model,
	root: BasePart,
	right: BasePart,
	left: BasePart,
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	items: HealItems.State,
}

local function build(character: Model): Rig
	local model = Instance.new("Model")
	model.Name = "HealView"
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
	local right: BasePart, left: BasePart = root, root
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
		if name == "Right Arm" then
			right = arm
		else
			left = arm
		end
	end
	for _, c in character:GetChildren() do
		if c:IsA("Shirt") or c:IsA("BodyColors") then
			c:Clone().Parent = model
		end
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.EvaluateStateMachine = false
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	model.Parent = workspace.CurrentCamera -- tracks loaded outside the DataModel never play
	local tracks = {}
	for name, a in Cfg.First.Animations do
		if a.id ~= 0 then
			local anim = Instance.new("Animation")
			anim.AnimationId = "rbxassetid://" .. a.id
			tracks[name] = animator:LoadAnimation(anim)
		end
	end
	return {
		model = model,
		root = root,
		right = right,
		left = left,
		animator = animator,
		tracks = tracks,
		items = HealItems.new(),
	}
end

-- Whether the local player is in first person on the free camera (its zoom, camera to focus, under
-- Config/Healing.First.Zoom; measured from the camera's own focus, not the head, which the crouch moves away: Studio
-- round 2; a weapon camera is its own thing): the first-person heal shows, and the body isn't turned for them.
function HealView.isFirst(character: Model?): boolean
	if not character or character:GetAttribute("CameraMode") ~= nil then
		return false
	end
	local camera = workspace.CurrentCamera
	return (camera.CFrame.Position - camera.Focus.Position).Magnitude < Cfg.First.Zoom
end

function HealView.start()
	local player = Players.LocalPlayer
	local rig: Rig? = nil
	local token = 0

	local function drop()
		if rig then
			rig.model:Destroy()
			rig = nil
		end
	end

	-- the heal's tracks from `since` seconds into it (the grab, then the wrap, or the opening then the press)
	local function play(r: Rig, kind: string, since: number)
		token += 1
		local mine = token
		local seq = if kind == "Bandage"
			then { { "grab", 0 }, { "wrap", Cfg.Grab.time } }
			else { { "grab", 0 }, { "open", Cfg.Grab.time }, { "press", Cfg.Grab.time + Cfg.Open.time } }
		for i, step in seq do
			local name, at = step[1], step[2]
			local nextAt = if seq[i + 1] then seq[i + 1][2] else math.huge
			local t = r.tracks[name]
			if t and since < nextAt then
				task.delay(math.max(at - since - Cfg.Fade, 0), function()
					if token == mine and rig == r then
						t:Play(Cfg.Fade)
						if since > at then
							t.TimePosition = math.min(since - at, math.max(t.Length - 0.01, 0))
						end
					end
				end)
			end
		end
	end

	local shownKind: string? = nil
	local character: Model? = nil
	local function watch(c: Model)
		character = c
		drop()
		c:GetAttributeChangedSignal("Healing"):Connect(function()
			drop() -- a new heal starts afresh
			shownKind = nil
		end)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end

	-- after the camera is placed (as src/client/Viewmodel)
	RunService:BindToRenderStep("HealView", LookTilt.Priority + 3, function()
		local c = character
		local kind = c and c:GetAttribute("Healing")
		local camera = workspace.CurrentCamera
		local at = c and c:GetAttribute("HealAt")
		-- (HealAt comes with Healing: until it's here the heal's moment isn't known)
		if not c or type(kind) ~= "string" or type(at) ~= "number" or not HealView.isFirst(c) then
			drop()
			shownKind = nil
			return
		end
		if not rig then
			rig = build(c)
		end
		local r = rig :: Rig
		local elapsed = workspace:GetServerTimeNow() - (at :: number)
		if shownKind ~= kind then
			shownKind = kind
			play(r, kind, elapsed) -- (zoomed in partway through: pick up where the heal is)
		end
		r.root.CFrame = camera.CFrame * CFrame.new(-EYE)
		-- the items on these arms, through the same steps as the body's (src/shared/HealItems)
		HealItems.update(r.items, kind, elapsed, r.right, r.left, r.model, true)
		local pin = HealItems.pin(c)
		if kind == "Bandage" and r.items.held and pin then
			HealItems.strip(r.items.held, pin, HealItems.unrolled(elapsed))
		end
	end)
end

return HealView
