--!strict
-- Tilts the soldiers' torsos with their camera's pitch (Config/Locomotion.LookTilt): look up and the torso
-- leans back a little, look down and it leans forward. Only the torso (head and arms ride on it) tilts: it turns
-- about the waist, the hip line where the legs join, and the hips turn back by the same angle so the legs stay
-- planted. Applied on top of the animations through the RootJoint and hip C0s.
-- With a weapon in the hands (Config/Camera.Follow): the arms and the gun turn about the shoulder line for the rest
-- of the pitch, so the weapon points where the camera looks, and the head follows part of the way. (In first person
-- the player sees the viewmodel instead, src/client/Viewmodel.)
-- Other players see it too: the local soldier's pitch and the gun's follow share go to the server (Net "LookPitch",
-- quantized and throttled by Config/Locomotion.LookTilt.Send), which relays them; every other soldier is posed the
-- same way here, easing toward the last pitch received.
-- The head turns left and right toward the look (Config/Locomotion.LookTilt.Head; user 2026-10-20): the camera's yaw
-- from the torso's facing, capped with the animation's own neck turn, on the Neck on top of the animations. Soldiers
-- nearby see it (Net "HeadYaw", relayed only within range by src/server/LookTilt).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local CameraCfg = require(Shared.Config.Camera)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.LookTilt)
local Held = require(script.Parent.Held)

local LookTilt = {}

local WAIST = Vector3.new(0, -1, 0) -- the hip line, in the torso's own space (R6 torso is 2 tall)
local SHOULDERS = Vector3.new(0, 0.5, 0) -- a point on the shoulder line (through both shoulder joints, along X)
local WAIT = 10 -- seconds to wait for another soldier's joints before giving up on it
-- after Roblox's camera (Free mode and no weapon) and before src/client/WeaponCamera places the camera
LookTilt.Priority = Enum.RenderPriority.Camera.Value + 1

-- c0 turned by `angle` (radians, + tips the top back) about `pivot`, in the parent part's axes
local function turned(c0: CFrame, pivot: Vector3, angle: number): CFrame
	return CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot) * c0
end

type Rig = {
	character: Model,
	humanoid: Humanoid,
	rootJoint: Motor6D,
	hips: { Motor6D },
	arms: { Motor6D },
	neck: Motor6D,
	rootC0: CFrame,
	hipC0: { CFrame },
	armC0: { CFrame },
	neckC0: CFrame,
}

-- the soldier's joints and their rest C0s, or nil if they don't turn up within `timeout` seconds
local function rig(character: Model, timeout: number?): Rig?
	local function find(parent: Instance?, name: string): any
		return parent and (if timeout then parent:WaitForChild(name, timeout) else parent:WaitForChild(name))
	end
	local humanoid = find(character, "Humanoid")
	local root = find(character, "HumanoidRootPart")
	local torso = find(character, "Torso")
	local rootJoint = find(root, "RootJoint")
	local hips = { find(torso, "Left Hip"), find(torso, "Right Hip") }
	local arms = { find(torso, "Right Shoulder"), find(torso, "Left Shoulder") }
	local neck = find(torso, "Neck")
	if not (humanoid and rootJoint and hips[1] and hips[2] and arms[1] and arms[2] and neck) then
		return nil
	end
	return {
		character = character,
		humanoid = humanoid,
		rootJoint = rootJoint,
		hips = hips,
		arms = arms,
		neck = neck,
		rootC0 = rootJoint.C0,
		hipC0 = { hips[1].C0, hips[2].C0 },
		armC0 = { arms[1].C0, arms[2].C0 },
		neckC0 = neck.C0,
	}
end

-- the animation's own turn of the head left and right (degrees; the idle's glances): R6's Neck turns the head about
-- its joint Z, which the rest C0 points along the torso's up
local function glance(r: Rig): number
	local _, _, z = r.neck.Transform:ToEulerAnglesXYZ()
	return math.deg(z)
end

-- the torso tilted by `angle`, with a weapon the arms + gun turned by `turn`, and the head turned by `yaw` (degrees)
local function pose(r: Rig, angle: number, turn: number, yaw: number)
	local a = math.rad(angle)
	local rootJoint = r.rootJoint
	-- the waist where the animation currently puts it, in the root's space
	local waist = (r.rootC0 * rootJoint.Transform * rootJoint.C1:Inverse()) * WAIST
	rootJoint.C0 = turned(r.rootC0, waist, a)
	for i, hip in r.hips do
		hip.C0 = turned(r.hipC0[i], r.hipC0[i].Position, -a)
	end

	-- the weapon: the rest of the pitch about the shoulder line
	local weapon = Held.weapon(r.character)
	if not weapon then
		turn = 0
	end
	local swing = CFrame.new(SHOULDERS) * CFrame.Angles(math.rad(turn), 0, 0) * CFrame.new(-SHOULDERS)
	for i, arm in r.arms do
		arm.C0 = swing * r.armC0[i]
	end
	if weapon then
		weapon.hold.C0 = swing
	end
	r.neck.C0 = turned(r.neckC0, r.neckC0.Position, math.rad(turn * CameraCfg.HeadFollow))
		* CFrame.Angles(0, 0, math.rad(yaw))
end

local count = 0

-- yaw of a look direction (degrees, + to the left like CFrame.fromOrientation's)
local function yawOf(look: Vector3): number
	return math.deg(math.atan2(-look.X, -look.Z))
end

local function attach(character: Model, remote: RemoteEvent, headRemote: RemoteEvent)
	local cfg = Cfg.LookTilt
	local H = cfg.Head
	local r = rig(character) :: Rig
	local humanoid = r.humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local angle = 0
	local yaw = 0
	local last = { pitch = math.huge, follow = math.huge, at = -math.huge } -- a new body always sends
	local lastYaw = { yaw = math.huge, at = -math.huge }

	count += 1
	local name = "LookTilt" .. count
	RunService:BindToRenderStep(name, LookTilt.Priority, function(dt)
		local camera = workspace.CurrentCamera
		local pitch = if camera and humanoid.Health > 0
			then math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
			else 0
		angle += (Rules.torso(pitch, cfg.Torso, cfg.TorsoMax) - angle) * Rules.ease(cfg.Smoothing, dt)
		local state = character:GetAttribute("Hold")
		local follow = if Held.weapon(character) and type(state) == "string" then CameraCfg.Follow[state] or 0 else 0
		-- the head toward the look (straight ahead dead or ragdolled)
		local want = 0
		if camera and humanoid.Health > 0 and character:GetAttribute("Ragdolled") ~= true then
			local look = yawOf(camera.CFrame.LookVector) - yawOf(root.CFrame.LookVector)
			want = Rules.headYaw(look, glance(r), yaw, H.Max, H.Behind)
		end
		yaw += (want - yaw) * Rules.ease(H.Smoothing, dt)
		pose(r, angle, Rules.weaponTurn(pitch, follow, angle), yaw)

		local now = os.clock()
		local y = Rules.yawToSend(yaw, lastYaw, now, H.Send, H.Max)
		if y then
			lastYaw.yaw, lastYaw.at = y, now
			headRemote:FireServer(y)
		end
		local p, f = Rules.toSend(pitch, follow, last, now, cfg.Send)
		if p and f then
			last.pitch, last.follow, last.at = p, f, now
			remote:FireServer(p, f)
		end
	end)
	character.Destroying:Connect(function()
		RunService:UnbindFromRenderStep(name)
	end)
	humanoid.Died:Connect(function()
		RunService:UnbindFromRenderStep(name)
	end)
end

-- other players' soldiers: the pitch and follow share last received, and where each is eased to now (kept until the
-- body is destroyed, so its rest C0s are read once, before any tilt)
type Other = {
	rig: Rig?,
	target: number,
	targetFollow: number,
	targetYaw: number,
	pitch: number,
	follow: number,
	yaw: number,
}

local function others(remote: RemoteEvent, headRemote: RemoteEvent)
	local cfg = Cfg.LookTilt
	local list: { [Model]: Other } = {}

	-- the soldier's entry, made on its first message
	local function entry(character: Model): Other?
		if typeof(character) ~= "Instance" or character == Players.LocalPlayer.Character then
			return nil
		end
		local o = list[character]
		if o then
			return o
		end
		local new: Other = { rig = nil, target = 0, targetFollow = 0, targetYaw = 0, pitch = 0, follow = 0, yaw = 0 }
		list[character] = new
		task.spawn(function()
			new.rig = rig(character, WAIT) -- (nil for good if its joints never turned up)
		end)
		character.Destroying:Connect(function()
			list[character] = nil
		end)
		return new
	end
	remote.OnClientEvent:Connect(function(character: Model, pitch: number, follow: number)
		local o = entry(character)
		if o then
			o.target, o.targetFollow = pitch, follow
		end
	end)
	headRemote.OnClientEvent:Connect(function(character: Model, yaw: number)
		local o = entry(character)
		if o then
			o.targetYaw = yaw
		end
	end)

	RunService:BindToRenderStep("LookTiltOthers", LookTilt.Priority, function(dt)
		local k = Rules.ease(cfg.Send.Smoothing, dt)
		local ky = Rules.ease(cfg.Head.Send.Smoothing, dt)
		for character, o in list do
			local r = o.rig
			-- (dead: the body keeps its last pose, as the local one does)
			if r and character.Parent and r.humanoid.Health > 0 then
				o.pitch += (o.target - o.pitch) * k
				o.follow += (o.targetFollow - o.follow) * k
				o.yaw += (o.targetYaw - o.yaw) * ky
				local angle = Rules.torso(o.pitch, cfg.Torso, cfg.TorsoMax)
				-- (the turn sent is already capped with the sender's glance; theirs here may differ a little)
				local yaw = math.clamp(o.yaw, -cfg.Head.Max - glance(r), cfg.Head.Max - glance(r))
				pose(r, angle, Rules.weaponTurn(o.pitch, o.follow, angle), yaw)
			end
		end
	end)
end

function LookTilt.start()
	local player = Players.LocalPlayer
	local remote = Net.event("LookPitch")
	local headRemote = Net.event("HeadYaw")
	player.CharacterAdded:Connect(function(character)
		attach(character, remote, headRemote)
	end)
	if player.Character then
		task.spawn(attach, player.Character, remote, headRemote)
	end
	others(remote, headRemote)
end

return LookTilt
