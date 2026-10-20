--!strict
-- Artillery on the client (docs/MILESTONES.md A2; Config/Artillery, Rules/Artillery; the server mans, lays and fires:
-- src/server/Artillery):
-- - every gun in the Workspace's Config/Artillery.Folder is posed here from its attributes: the mount traversed, the
--   cradle elevated about the trunnion, the barrel's recoil and run-out (cut short where the howitzer's breech would hit
--   its platform), the breech swinging open through the reload; the howitzer's crystal shows its state (flaring on the
--   shot, filling while it charges, pulsing ready).
-- - on a gun (its "Gunner" is me): a third-person camera behind it (user 2026-10-20: "third person cinematic camera
--   that shows an arc (like grenade) and where it will explode (it will be innacurate)"); the mouse lays it (Net
--   "Artillery" "Aim"), the fire key fires, E gets off. The arc is the gun's lay as it is, without the scatter; the
--   marker and the range show past the fog. A reload bar at the bottom.
-- - every shot flashes at the muzzle with its report, every shell's blast is the shared explosion (src/client/Vfx/Blast)
--   with its sound, heard late and duller far off.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCfg = require(Shared.Config.Audio)
local Cfg = require(Shared.Config.Artillery)
local Damage = require(Shared.Config.Damage)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Artillery)
local Grenade = require(Shared.Rules.Grenade)
local Net = require(Shared.Net)
local Settings = require(script.Parent.Settings)
local SoundFx = require(script.Parent.SoundFx)
local Vfx = require(script.Parent.Vfx)

local Artillery = {}

type Pose = {
	gun: Cfg.Gun,
	rest: { [BasePart]: CFrame }, -- each moving part at rest, in gun space
	stage: { [BasePart]: number }, -- 1 mount, 2 cradle, 3 barrel, 4 breech
	crystal: BasePart?,
	traverse: number,
	elevation: number,
}

local poses: { [Model]: Pose } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

-- start posing a gun: its moving parts' rest places (the server never moves them)
local function track(model: Model)
	local gun = Cfg.Guns[model:GetAttribute("Gun") :: any]
	if not gun or poses[model] then
		return
	end
	local pivot = model:GetPivot()
	local p: Pose = {
		gun = gun,
		rest = {},
		stage = {},
		crystal = nil,
		traverse = (model:GetAttribute("Traverse") :: number?) or 0,
		elevation = (model:GetAttribute("Elevation") :: number?) or 0,
	}
	for i, names in { gun.mount, gun.cradle, gun.barrel, gun.breech } do
		for _, name in names do
			local part = model:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				p.rest[part] = pivot:ToObjectSpace(part.CFrame)
				p.stage[part] = i
				if name == "Crystal" then
					p.crystal = part
				end
			end
		end
	end
	poses[model] = p
end

local function pose(model: Model, p: Pose, dt: number)
	local gun = p.gun
	local k = math.min(1, dt * Cfg.Smooth)
	p.traverse += (((model:GetAttribute("Traverse") :: number?) or 0) - p.traverse) * k
	p.elevation += (((model:GetAttribute("Elevation") :: number?) or 0) - p.elevation) * k
	local t = now()
	local firedAt = (model:GetAttribute("FiredAt") :: number?) or -math.huge
	local readyAt = (model:GetAttribute("ReadyAt") :: number?) or -math.huge
	local full = Rules.recoilLength(gun.recoil, p.elevation, gun.trunnion[2], gun.recoilClear)
	local recoil = Rules.recoilAt(t - firedAt, full, gun.recoilTimes)
	local open = Rules.breechAt(t, firedAt, readyAt, gun.breechTimes, Cfg.BreechSwing) * gun.breechOpen

	local pivot = model:GetPivot()
	local trunnion = CFrame.new(v3(gun.trunnion))
	local hinge = CFrame.new(v3(gun.hinge))
	local frames = {}
	frames[1] = pivot * CFrame.Angles(0, math.rad(p.traverse), 0)
	frames[2] = frames[1] * trunnion * CFrame.Angles(math.rad(p.elevation), 0, 0) * trunnion:Inverse()
	frames[3] = frames[2] * CFrame.new(0, 0, recoil)
	frames[4] = frames[3] * hinge * CFrame.Angles(0, math.rad(open), 0) * hinge:Inverse()
	for part, rest in p.rest do
		part.CFrame = frames[p.stage[part]] * rest
	end
	if p.crystal then
		local c = Cfg.Crystal
		local state, glow = Rules.crystal(t, firedAt, readyAt, gun.reload, c)
		p.crystal.Color = if state == "Fired"
			then rgb(c.ready):Lerp(rgb(c.fired), glow)
			else rgb(c.empty):Lerp(rgb(c.ready), glow)
	end
end

-- the gunner's view -------------------------------------------------------------------------------------------------

local beam: Beam? = nil
local a0: Attachment? = nil
local a1: Attachment? = nil
local marker: BillboardGui? = nil
local rangeLabel: TextLabel? = nil

local function arcParts(): (Beam, Attachment, Attachment, BillboardGui, TextLabel)
	if not beam or not beam.Parent then
		local A = Cfg.Arc
		local c = Palette.Artillery.Arc
		a0 = Instance.new("Attachment")
		a1 = Instance.new("Attachment")
		local b = Instance.new("Beam")
		b.Name = "ArtilleryArc"
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.Segments = A.segments
		b.Width0, b.Width1 = A.width, A.width
		b.Color = ColorSequence.new(rgb(c))
		b.Transparency = NumberSequence.new(A.transparency)
		b.Enabled = false
		local x0, x1 = a0 :: Attachment, a1 :: Attachment
		x0.Parent = workspace.Terrain
		x1.Parent = workspace.Terrain
		b.Parent = workspace.Terrain
		beam = b

		local gui = Instance.new("BillboardGui")
		gui.Name = "ArtilleryMarker"
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.Size = UDim2.fromOffset(A.marker * 4, A.marker + A.text * 1.6)
		gui.Enabled = false
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.fromScale(0.5, 0)
		ring.Size = UDim2.fromOffset(A.marker, A.marker)
		ring.BackgroundTransparency = 1
		Instance.new("UICorner", ring).CornerRadius = UDim.new(0.5, 0)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = A.ring
		stroke.Color = rgb(Palette.Artillery.Marker)
		stroke.Parent = ring
		ring.Parent = gui
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 1)
		label.Size = UDim2.new(1, 0, 0, A.text * 1.3)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextSize = A.text
		label.TextColor3 = rgb(Palette.UI.text)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui
		gui.Adornee = a1
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		marker, rangeLabel = gui, label
	end
	return beam :: Beam, a0 :: Attachment, a1 :: Attachment, marker :: BillboardGui, rangeLabel :: TextLabel
end

local function hideArc()
	if beam then
		beam.Enabled = false
	end
	if marker then
		marker.Enabled = false
	end
end

-- an attachment at `at` whose X axis points along `axis` (the Beam's curve leaves along it)
local function along(a: Attachment, at: Vector3, axis: Vector3)
	local x = if axis.Magnitude > 1e-6 then axis.Unit else Vector3.xAxis
	local y = x:Cross(Vector3.yAxis)
	y = if y.Magnitude > 1e-3 then y.Unit else Vector3.zAxis
	a.WorldCFrame = CFrame.fromMatrix(at, x, y)
end

-- the arc of a shot with the gun's lay as posed (no scatter), to where it would first hit
local function drawArc(model: Model, p: Pose, character: Model)
	local gun = p.gun
	local pivot = model:GetPivot()
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, p.traverse, p.elevation)
	local o = pivot:PointToWorldSpace(Vector3.new(mx, my, mz))
	local v = pivot:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed
	local g = workspace.Gravity
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model, character }
	params.IgnoreWater = false
	params.CollisionGroup = "Default"
	local function at(t: number): Vector3
		local x, y, z = Rules.at(t, o.X, o.Y, o.Z, v.X, v.Y, v.Z, g)
		return Vector3.new(x, y, z)
	end
	local step = Cfg.Arc.step
	local prev, t, last, finish = o, step, 0, nil :: Vector3?
	while t <= Cfg.MaxFlight and prev.Y > Cfg.Arc.floor do
		local q = at(t)
		local hit = workspace:Raycast(prev, q - prev, params)
		if hit then
			last = t - step + step * hit.Distance / (q - prev).Magnitude
			finish = hit.Position
			break
		end
		last, prev = t, q
		t += step
	end
	local b, s0, s1, gui, label = arcParts()
	local p1 = finish or at(last)
	local v1 = Vector3.new(v.X, v.Y - g * last, v.Z)
	local third = last / 3
	along(s0, o, v)
	along(s1, p1, v1)
	b.CurveSize0 = v.Magnitude * third
	b.CurveSize1 = v1.Magnitude * third
	b.Enabled = true
	gui.Enabled = finish ~= nil
	local flat = Vector3.new(p1.X - o.X, 0, p1.Z - o.Z).Magnitude
	label.Text = `{math.round(flat * Damage.Blast.MetresPerStud)} m`
end

function Artillery.start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera

	-- the guns
	local function watch(f: Instance)
		f.ChildAdded:Connect(function(c)
			if c:IsA("Model") then
				task.defer(track, c)
			end
		end)
		f.ChildRemoved:Connect(function(c)
			poses[c :: any] = nil
		end)
		for _, c in f:GetChildren() do
			if c:IsA("Model") then
				track(c)
			end
		end
	end
	local f = workspace:FindFirstChild(Cfg.Folder)
	if f then
		watch(f)
	else
		local conn: RBXScriptConnection
		conn = workspace.ChildAdded:Connect(function(c)
			if c.Name == Cfg.Folder then
				conn:Disconnect()
				watch(c)
			end
		end)
	end

	-- the reload bar (as the staff's mana bar: Palette.UI)
	local UI = Palette.UI
	local B = Cfg.Bar
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArtilleryBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -B.margin)
	bar.Size = UDim2.fromOffset(B.width, B.height)
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = rgb(UI.slot)
	local edge = Instance.new("UIStroke")
	edge.Thickness = UI.stroke
	edge.Color = rgb(UI.outline)
	edge.Parent = bar
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = rgb(UI.round)
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	local caption = Instance.new("TextLabel")
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 0, -4)
	caption.Size = UDim2.fromOffset(B.width, B.text * 1.3)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.GothamMedium
	caption.TextSize = B.text
	caption.TextColor3 = rgb(UI.text)
	caption.TextStrokeTransparency = 0.5
	caption.Parent = bar
	bar.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	-- on a gun
	local mine: Model? = nil
	local wantYaw, wantElevation = 0, 0
	local sentAt, sentYaw, sentElevation = 0, math.huge, math.huge
	local snap = true
	local fov = camera.FieldOfView
	local arcAt = 0

	local function getOff()
		mine = nil
		hideArc()
		gui.Enabled = false
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = fov
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	local function getOn(model: Model, p: Pose)
		mine = model
		local _, yaw = model:GetPivot():ToOrientation()
		wantYaw = math.deg(yaw) + p.traverse
		wantElevation = p.elevation
		snap = true
		fov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = p.gun.camera.fov
		gui.Enabled = true
	end

	UserInputService.InputChanged:Connect(function(input)
		if not mine or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if player:GetAttribute("MenuOpen") == true then
			return
		end
		local p = poses[mine]
		if not p then
			return
		end
		local s = Cfg.Aim.sensitivity
		wantYaw = Rules.wrap(wantYaw - input.Delta.X * s[1])
		wantElevation = math.clamp(wantElevation - input.Delta.Y * s[2], p.gun.elevation[1], p.gun.elevation[2])
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not mine or processed then
			return
		end
		if Settings.pressed("Key_Fire", input) then
			Net.event("Artillery"):FireServer("Fire")
		elseif input.KeyCode == Enum.KeyCode.E then
			Net.event("Artillery"):FireServer("Leave")
		end
	end)

	RunService:BindToRenderStep("Artillery", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local character = player.Character
		-- which gun is mine
		local found: Model? = nil
		for model, p in poses do
			if not model.Parent then
				poses[model] = nil
				continue
			end
			pose(model, p, dt)
			if model:GetAttribute("Gunner") == player.UserId then
				found = model
			end
		end
		if found ~= mine then
			if mine then
				getOff()
			end
			if found and poses[found] then
				getOn(found, poses[found])
			end
		end
		local model = mine
		local p = model and poses[model]
		if not model or not p or not character then
			return
		end
		local gun = p.gun

		-- the mouse stays locked in the middle (free while the settings menu is open)
		UserInputService.MouseBehavior = if player:GetAttribute("MenuOpen") == true
			then Enum.MouseBehavior.Default
			else Enum.MouseBehavior.LockCenter

		-- the aim, sent at most Aim.rate a second when it changed
		local t = os.clock()
		if
			t - sentAt >= 1 / Cfg.Aim.rate
			and (math.abs(wantYaw - sentYaw) > 0.01 or math.abs(wantElevation - sentElevation) > 0.01)
		then
			sentAt, sentYaw, sentElevation = t, wantYaw, wantElevation
			Net.event("Artillery"):FireServer("Aim", wantYaw, wantElevation)
		end

		-- the camera: behind and over the gun along the aim, pitched with it
		local c = gun.camera
		local pivot = model:GetPivot()
		local rot = CFrame.Angles(0, math.rad(wantYaw), 0)
		local base = pivot.Position + Vector3.new(0, gun.trunnion[2], 0)
		local at = base + rot:VectorToWorldSpace(Vector3.new(0, c.up, c.back))
		local goal = CFrame.new(at) * rot * CFrame.Angles(math.rad(c.pitch + wantElevation * c.follow), 0, 0)
		camera.CFrame = if snap then goal else camera.CFrame:Lerp(goal, math.min(1, dt * Cfg.CameraEase))
		snap = false

		-- the arc and its marker (a few times a second is plenty)
		if t - arcAt >= Cfg.Arc.refresh then
			arcAt = t
			drawArc(model, p, character)
		end

		-- the reload bar
		local readyAt = (model:GetAttribute("ReadyAt") :: number?) or -math.huge
		local share = Rules.loaded(now(), readyAt, gun.reload)
		fill.Size = UDim2.fromScale(share, 1)
		fill.BackgroundColor3 = rgb(if share >= 1 then UI.accent else UI.round)
		caption.Text = if share >= 1 then "Ready" else "Loading"
	end)

	-- a shot: the muzzle flash and its report
	Net.event("ArtilleryShot").OnClientEvent:Connect(function(model: Model, origin: Vector3, _velocity: Vector3)
		local gun = Cfg.Guns[model and model:GetAttribute("Gun") :: any]
		if not gun then
			return
		end
		local F = Cfg.Flash
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.one * F.size * gun.flash
		ball.CFrame = CFrame.new(origin)
		ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
		ball.CastShadow = false
		ball.Material = Enum.Material.Neon
		ball.Color = rgb(F.color)
		local light = Instance.new("PointLight")
		light.Range = F.light
		light.Brightness = F.brightness
		light.Color = rgb(F.color)
		light.Parent = ball
		ball.Parent = workspace
		Debris:AddItem(ball, F.time)
		local d = (camera.CFrame.Position - origin).Magnitude
		local delay, high, low = Grenade.heard(d, Cfg.Heard, AudioCfg.Heard.speed)
		SoundFx.play(Cfg.Sound.fire :: any, origin, nil, { delay = delay, eq = { low, 0, high } })
	end)

	-- a shell's blast
	Net.event("ArtilleryBlast").OnClientEvent:Connect(function(position: Vector3, key: string)
		local gun = Cfg.Guns[key]
		if not gun then
			return
		end
		Vfx.Blast.play(position, {
			normal = Vector3.yAxis,
			kg = gun.kg,
			scheme = gun.vfx.scheme,
			magic = gun.vfx.magic,
		})
		local d = (camera.CFrame.Position - position).Magnitude
		local delay, high, low = Grenade.heard(d, Cfg.Heard, AudioCfg.Heard.speed)
		SoundFx.play(Cfg.Sound.blast :: any, position, nil, { delay = delay, eq = { low, 0, high } })
	end)
end

return Artillery
