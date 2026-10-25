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
-- Third person (Config/Camera.Aim3P; user 2026-10-21: "make the player's gun still aim towards your crosshair while in
-- third person"): on top of the pitch, the weapon turns about the right shoulder so the barrel (the staff's head) meets
-- the point under the crosshair (a ray from the camera through the screen centre), and each arm turns about its own
-- shoulder so its hand stays where it held the weapon (user 2026-10-21: "make it so the arms move the gun where it
-- aims"). The turn follows a critically damped spring, never a snap. It is taken from where the animation points the
-- weapon on average, so its breath, stride and recoil still move it around that line. Shots leave the barrel
-- (src/client/Firing), so they go there too. Others see the turn (Net "LookPitch").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local TuckCfg = Cfg.Tuck
local CameraCfg = require(Shared.Config.Camera)
local CameraRules = require(Shared.Rules.Camera)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.LookTilt)
local Held = require(script.Parent.Held)

local LookTilt = {}

local WAIST = Vector3.new(0, -1, 0) -- the hip line, in the torso's own space (R6 torso is 2 tall)
local SHOULDERS = Vector3.new(0, 0.5, 0) -- a point on the shoulder line (through both shoulder joints, along X)
local WAIT = 10 -- seconds to wait for another soldier's joints before giving up on it
local AIM = CameraCfg.Aim3P
local HAND = Vector3.new(0, -1, 0) -- the hand: the bottom of an R6 arm, in the arm's own space
-- after Roblox's camera (Free mode and no weapon) and before src/client/WeaponCamera places the camera
LookTilt.Priority = Enum.RenderPriority.Camera.Value + 1

-- c0 turned by `angle` (radians, + tips the top back) about `pivot`, in the parent part's axes
local function turned(c0: CFrame, pivot: Vector3, angle: number): CFrame
	return CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot) * c0
end

type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
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
		root = root,
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

-- The turn onto the crosshair, per soldier: where the animation points the weapon on average (degrees, in the torso's
-- space), the turn from there onto the crosshair's line (degrees: the local soldier's from its crosshair on a spring,
-- with its speed; another's as received), and the turn as a rotation.
type Aim = {
	gun: BasePart?,
	yaw: number,
	pitch: number,
	turnYaw: number,
	turnPitch: number,
	speedYaw: number,
	speedPitch: number,
	rot: CFrame,
}

local function newAim(): Aim
	return {
		gun = nil,
		yaw = 0,
		pitch = 0,
		turnYaw = 0,
		turnPitch = 0,
		speedYaw = 0,
		speedPitch = 0,
		rot = CFrame.identity,
	}
end

-- the shortest rotation taking direction `from` onto `to`
local function between(from: Vector3, to: Vector3): CFrame
	local axis = from:Cross(to)
	if axis.Magnitude < 1e-6 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(axis.Unit, math.atan2(axis.Magnitude, from:Dot(to)))
end

-- The weapon's extra turn onto the crosshair (a rotation in the torso's space, applied about `pivot`). `bend`: the
-- pitch turn about the shoulders already on it. `point` (the local soldier only): the crosshair's point in the world,
-- turned onto with `weight` on a spring; otherwise the turn already in `a` is used.
local function aimTurn(
	r: Rig,
	weapon: Held.Weapon,
	bend: CFrame,
	pivot: CFrame,
	a: Aim,
	dt: number,
	point: Vector3?,
	weight: number
)
	local muzzle = weapon.gun:FindFirstChild("Muzzle") :: Attachment?
	if not muzzle then
		a.gun, a.rot = nil, CFrame.identity
		return a.rot
	end
	local hold = weapon.hold
	-- the muzzle in the hold's space as the animation (and the recoil kick on C1) puts it
	local inHold = hold.Transform * hold.C1:Inverse() * muzzle.CFrame
	local look = (bend * inHold).LookVector
	local y, p = Rules.angles(look.X, look.Y, look.Z)
	if a.gun ~= weapon.gun then
		a.gun, a.yaw, a.pitch = weapon.gun, y, p
	else
		local k = Rules.ease(AIM.Settle, dt)
		a.yaw, a.pitch = Rules.settle(a.yaw, y, k), Rules.settle(a.pitch, p, k)
	end
	if point then
		local rootJoint = r.rootJoint
		local torso = r.root.CFrame * rootJoint.C0 * rootJoint.Transform * rootJoint.C1:Inverse()
		-- from the muzzle as last turned
		local from = torso * (pivot * a.rot * pivot:Inverse() * bend * inHold).Position
		local want = torso:VectorToObjectSpace(point - from)
		local wy, wp = Rules.angles(want.X, want.Y, want.Z)
		local ty, tp = Rules.aimTurn(a.yaw, a.pitch, wy, wp, AIM.Max)
		a.turnYaw, a.speedYaw = CameraRules.spring(a.turnYaw, a.speedYaw, ty * weight, AIM.Spring, dt)
		a.turnPitch, a.speedPitch = CameraRules.spring(a.turnPitch, a.speedPitch, tp * weight, AIM.Spring, dt)
	end
	-- turn the average pointing onto the line: yaw about the torso's up, pitch about the weapon's own side
	local ay, ap = math.rad(a.yaw), math.rad(a.pitch)
	a.rot = CFrame.Angles(0, ay + math.rad(a.turnYaw), 0)
		* CFrame.Angles(ap + math.rad(a.turnPitch), 0, 0)
		* CFrame.Angles(-ap, 0, 0)
		* CFrame.Angles(0, -ay, 0)
	return a.rot
end

-- the torso tilted by `angle`, with a weapon the arms + gun turned by `turn` (and onto the crosshair by `aim`), and the
-- head turned by `yaw` (degrees); the gun and arms slid `pull` studs back along the barrel (near a wall, src/client/Tuck)
local function pose(
	r: Rig,
	angle: number,
	turn: number,
	yaw: number,
	aim: Aim,
	dt: number,
	point: Vector3?,
	weight: number,
	pull: number
)
	local a = math.rad(angle)
	local rootJoint = r.rootJoint
	-- the waist where the animation currently puts it, in the root's space
	local waist = (r.rootC0 * rootJoint.Transform * rootJoint.C1:Inverse()) * WAIST
	rootJoint.C0 = turned(r.rootC0, waist, a)
	for i, hip in r.hips do
		hip.C0 = turned(r.hipC0[i], r.hipC0[i].Position, -a)
	end

	-- the weapon: the rest of the pitch about the shoulder line (arms and weapon as one), then the turn onto the
	-- crosshair: the weapon about the right shoulder, the right arm with it, the left arm about its own shoulder so its
	-- hand stays where it held the weapon
	local weapon = Held.weapon(r.character)
	if not weapon then
		turn = 0
	end
	local line = CFrame.new(SHOULDERS)
	local bend = line * CFrame.Angles(math.rad(turn), 0, 0) * line:Inverse()
	local pivot = CFrame.new(r.armC0[1].Position) -- the right shoulder (on the shoulder line: the bend keeps it put)
	local onto = if weapon then aimTurn(r, weapon, bend, pivot, aim, dt, point, weight) else CFrame.identity
	local swing = pivot * onto * pivot:Inverse()
	-- pulled back near a wall: the gun and both arms slide back along the barrel as one, still pointing the same way
	local back = CFrame.identity
	local muzzle = weapon and weapon.gun:FindFirstChild("Muzzle") :: Attachment?
	if weapon and muzzle and pull > 0 then
		local hold = weapon.hold
		back = CFrame.new(-(swing * bend * hold.Transform * hold.C1:Inverse() * muzzle.CFrame).LookVector * pull)
	end
	for i, arm in r.arms do
		local c0 = bend * r.armC0[i]
		if i == 1 then
			c0 = swing * c0
		elseif onto ~= CFrame.identity then
			local shoulder = c0.Position
			local hand = (c0 * arm.Transform * arm.C1:Inverse()) * HAND
			local to = between(hand - shoulder, swing * hand - shoulder)
			c0 = CFrame.new(shoulder) * to * CFrame.new(-shoulder) * c0
		end
		arm.C0 = back * c0
	end
	if weapon then
		weapon.hold.C0 = back * swing * bend
	end
	r.neck.C0 = turned(r.neckC0, r.neckC0.Position, math.rad(turn * CameraCfg.HeadFollow))
		* CFrame.Angles(0, 0, math.rad(yaw))
end

local count = 0

-- the crosshair's line: what it is over beyond the soldier (the camera, its own body and effects ignored; anything
-- between the camera and the body skipped), else Aim3P.Fallback out; returned as the distance from the camera
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
local function crosshairLine(character: Model, camera: Camera, body: Vector3): (Ray, number)
	local size = camera.ViewportSize
	local ray = camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	local along = math.max((body - ray.Origin):Dot(ray.Direction), 0) -- where the line passes the body
	local ignore: { Instance } = { character, camera }
	for _, name in { "GunFx", "Vfx" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	aimParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin + ray.Direction * along, ray.Direction * AIM.Fallback, aimParams)
	return ray, Rules.aimDistance(if hit then along + hit.Distance else nil, along, AIM.Fallback, AIM.MinDistance)
end

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
	-- a new body always sends
	local last = { pitch = math.huge, follow = math.huge, aimYaw = math.huge, aimPitch = math.huge, at = -math.huge }
	local lastYaw = { yaw = math.huge, at = -math.huge }
	local aim = newAim()
	local weight = 0 -- the turn onto the crosshair's share now (Aim3P.States, eased)
	local distance = AIM.Fallback -- how far along the crosshair's line the point is (eased)

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
		-- third person: the weapon onto the crosshair
		local mode = character:GetAttribute("CameraMode")
		local share = if Held.weapon(character)
				and type(mode) == "string"
				and AIM.Modes[mode]
				and type(state) == "string"
			then (AIM.States :: any)[state] or 0
			else 0
		weight += (share - weight) * Rules.ease(AIM.Ease, dt)
		local point: Vector3? = nil
		if weight < 1e-3 and share == 0 then
			weight, aim.turnYaw, aim.turnPitch = 0, 0, 0 -- (none: no ray cast either)
		elseif camera and humanoid.Health > 0 then
			local ray, d = crosshairLine(character, camera, root.Position)
			-- (eased in log space, so near and far settle alike)
			distance =
				math.exp(math.log(distance) + (math.log(d) - math.log(distance)) * Rules.ease(AIM.DistanceEase, dt))
			point = ray.Origin + ray.Direction * distance
		end
		local pulled = character:GetAttribute("Pull")
		local pull = if type(pulled) == "number" then pulled * TuckCfg.Body else 0
		pose(r, angle, Rules.weaponTurn(pitch, follow, angle), yaw, aim, dt, point, weight, pull)

		local now = os.clock()
		local y = Rules.yawToSend(yaw, lastYaw, now, H.Send, H.Max)
		if y then
			lastYaw.yaw, lastYaw.at = y, now
			headRemote:FireServer(y)
		end
		local p, f, ay, ap = Rules.toSend(pitch, follow, aim.turnYaw, aim.turnPitch, last, now, cfg.Send, AIM.Max)
		if p and f and ay and ap then
			last.pitch, last.follow, last.aimYaw, last.aimPitch, last.at = p, f, ay, ap, now
			remote:FireServer(p, f, ay, ap)
		end
	end)
	character.Destroying:Connect(function()
		RunService:UnbindFromRenderStep(name)
	end)
	humanoid.Died:Connect(function()
		RunService:UnbindFromRenderStep(name)
	end)
end

-- other players' soldiers: the pitch, follow share, head turn and turn onto the crosshair last received, and where each
-- is eased to now (kept until the body is destroyed, so its rest C0s are read once, before any tilt)
type Other = {
	rig: Rig?,
	target: number,
	targetFollow: number,
	targetYaw: number,
	targetAimYaw: number,
	targetAimPitch: number,
	pitch: number,
	follow: number,
	yaw: number,
	aim: Aim,
	targetPull: number,
	pull: number,
}

local function others(remote: RemoteEvent, headRemote: RemoteEvent, pullRemote: RemoteEvent)
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
		local new: Other = {
			rig = nil,
			target = 0,
			targetFollow = 0,
			targetYaw = 0,
			targetAimYaw = 0,
			targetAimPitch = 0,
			pitch = 0,
			follow = 0,
			yaw = 0,
			aim = newAim(),
			targetPull = 0,
			pull = 0,
		}
		list[character] = new
		task.spawn(function()
			new.rig = rig(character, WAIT) -- (nil for good if its joints never turned up)
		end)
		character.Destroying:Connect(function()
			list[character] = nil
		end)
		return new
	end
	remote.OnClientEvent:Connect(
		function(character: Model, pitch: number, follow: number, aimYaw: number?, aimPitch: number?)
			local o = entry(character)
			if o then
				o.target, o.targetFollow = pitch, follow
				o.targetAimYaw, o.targetAimPitch = aimYaw or 0, aimPitch or 0
			end
		end
	)
	headRemote.OnClientEvent:Connect(function(character: Model, yaw: number)
		local o = entry(character)
		if o then
			o.targetYaw = yaw
		end
	end)
	pullRemote.OnClientEvent:Connect(function(character: Model, pull: number)
		local o = entry(character)
		if o then
			o.targetPull = pull
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
				o.aim.turnYaw += (o.targetAimYaw - o.aim.turnYaw) * k
				o.aim.turnPitch += (o.targetAimPitch - o.aim.turnPitch) * k
				o.pull += (o.targetPull - o.pull) * k
				local angle = Rules.torso(o.pitch, cfg.Torso, cfg.TorsoMax)
				-- (the turn sent is already capped with the sender's glance; theirs here may differ a little)
				local yaw = math.clamp(o.yaw, -cfg.Head.Max - glance(r), cfg.Head.Max - glance(r))
				pose(
					r,
					angle,
					Rules.weaponTurn(o.pitch, o.follow, angle),
					yaw,
					o.aim,
					dt,
					nil,
					1,
					o.pull * TuckCfg.Body
				)
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
	others(remote, headRemote, Net.event("GunPull"))
end

return LookTilt
