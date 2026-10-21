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

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCfg = require(Shared.Config.Audio)
local Cfg = require(Shared.Config.Artillery)
local TreeSway = require(Shared.Config.TreeSway)
local Damage = require(Shared.Config.Damage)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.Artillery)
local Grenade = require(Shared.Rules.Grenade)
local Net = require(Shared.Net)
local ArtilleryCrystal = require(script.Parent.ArtilleryCrystal)
local ArtilleryFx = require(script.Parent.ArtilleryFx)
local Settings = require(script.Parent.Settings)
local SoundFx = require(script.Parent.SoundFx)
local Vfx = require(script.Parent.Vfx)

local Artillery = {}

type Pose = {
	gun: Cfg.Gun,
	rest: { [BasePart]: CFrame }, -- each moving part at rest, in gun space
	stage: { [BasePart]: number }, -- 1 mount, 2 cradle, 3 barrel, 4 breech
	crystal: BasePart?,
	fx: ArtilleryCrystal.State?, -- the howitzer's living crystal
	traverse: number,
	elevation: number,
}

local poses: { [Model]: Pose } = {}
local charging: { [Model]: () -> () } = {} -- a magic gun's charge-up running, its stop

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
		fx = nil,
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
	if p.crystal then
		p.fx = ArtilleryCrystal.new(model, p.crystal)
	end
	poses[model] = p
	-- the magic gun's charge-up as its gunner braces (the server's "BraceAt"), until the shot
	if gun.vfx.magic then
		model:GetAttributeChangedSignal("BraceAt"):Connect(function()
			local pose = poses[model]
			if not pose or charging[model] then
				return
			end
			local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, pose.traverse, pose.elevation)
			local frame = model:GetPivot()
			local at = frame:PointToWorldSpace(Vector3.new(mx, my, mz))
			local muzzle = CFrame.lookAt(at, at + frame:VectorToWorldSpace(Vector3.new(dx, dy, dz)))
			local stop = ArtilleryFx.charge(gun, muzzle, pose.crystal)
			charging[model] = stop
			task.delay(gun.charge + 0.5, function()
				if charging[model] == stop then
					charging[model] = nil
					stop()
				end
			end)
		end)
	end
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
	local open = if gun.breechOpens
		then Rules.breechAt(t, firedAt, readyAt, gun.breechTimes, Cfg.BreechSwing) * gun.breechOpen
		else 0

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
	if p.fx then
		local braceAt = (model:GetAttribute("BraceAt") :: number?) or -math.huge
		ArtilleryCrystal.update(p.fx, t, firedAt, readyAt, gun.reload, braceAt, gun.charge)
	end
end

-- the field gun's loading (Config/Artillery.Load): the gunner's own client plays the animation once a reload (it
-- replicates); every client shows the round at the gunner's right hand while it's carried
type Loading = { round: Model?, played: number? }
local loadings: { [Model]: Loading } = {}
local tracks: { [Model]: { [string]: AnimationTrack } } = {}

local function roundTemplate(): Model?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, sub in { "Weapons", "Shared", "Artillery", Cfg.Load.round } do
		f = f and f:FindFirstChild(sub)
	end
	return if f and f:IsA("Model") then f else nil
end

-- one of the gunner's tracks (`key`: "load", "brace", "crank"), made (and so fetched) ahead of its first play
local function oneTrack(character: Model, key: string, id: number?): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator or not id then
		return nil
	end
	local set = tracks[character]
	if not set then
		set = {}
		tracks[character] = set
		character.Destroying:Connect(function()
			tracks[character] = nil
		end)
	end
	local tr = (set :: any)[key]
	if not tr then
		local a = Instance.new("Animation")
		a.AnimationId = `rbxassetid://{id}`
		tr = animator:LoadAnimation(a);
		(set :: any)[key] = tr
	end
	return tr
end

local function loadTrack(character: Model): AnimationTrack?
	return oneTrack(character, "load", Cfg.Load.animation)
end

local function load(model: Model, p: Pose, mine: boolean)
	local L = Cfg.Load
	if not p.gun.loads or not L.animation then
		return
	end
	local s = loadings[model]
	if not s then
		s = {}
		loadings[model] = s
	end
	local firedAt = model:GetAttribute("FiredAt") :: number?
	local readyAt = model:GetAttribute("ReadyAt") :: number?
	local id = model:GetAttribute("Gunner") :: number?
	local gunner = id and Players:GetPlayerByUserId(id)
	local character = gunner and gunner.Character
	local arm = character and character:FindFirstChild("Right Arm") :: BasePart?
	local t = if firedAt and readyAt then now() - (readyAt - L.lead) else -math.huge
	-- the gunner plays it, once a reload, from where the loading is (user 2026-10-20: "make sure the reload animation
	-- resumes when players go on the cannon during the reload period")
	if mine and character and readyAt and t >= 0 and t < L.length - 0.1 and s.played ~= readyAt then
		s.played = readyAt
		local tr = loadTrack(character)
		if tr then
			tr:Play(0.15)
			tr.TimePosition = t
		end
	end
	-- the round at the right hand while carried: its base in the hand, level, along the gun
	if arm and t >= L.take and t < L.loaded then
		if not s.round then
			local template = roundTemplate()
			if template then
				local r = template:Clone()
				for _, d in r:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
						local c = (Palette.Artillery :: any)[d.Name]
						if c then
							d.Color = rgb(c)
							d.Material = Enum.Material.SmoothPlastic
						end
						d.Transparency = if d.Name == "Origin" then 1 else d.Transparency
					end
				end
				-- its pivot from its own shape (Studio round 2: once it hung vertical from the hand): at the case head,
				-- looking from the case to the fuze
				local origin = r:FindFirstChild("Origin", true) :: BasePart?
				local case = r:FindFirstChild("Case", true) :: BasePart?
				local fuze = r:FindFirstChild("Fuze", true) :: BasePart?
				if origin and case and fuze then
					r.PrimaryPart = nil
					r.WorldPivot = CFrame.lookAt(origin.Position, origin.Position + (fuze.Position - case.Position))
				end
				r.Parent = model
				s.round = r
			end
		end
		if s.round then
			local hand = arm.CFrame:PointToWorldSpace(Vector3.new(0, -1, 0))
			local along = model:GetPivot().Rotation * CFrame.Angles(0, math.rad(p.traverse), 0)
			s.round:PivotTo(CFrame.new(hand) * along)
		end
	elseif s.round then
		s.round:Destroy()
		s.round = nil
	end
end

-- the gunner's view -------------------------------------------------------------------------------------------------

local beam: Beam? = nil
local a0: Attachment? = nil
local a1: Attachment? = nil
local marker: BillboardGui? = nil
local rangeLabel: TextLabel? = nil
local ringFrame: Frame? = nil
-- the impact zone (user 2026-10-20: "the impact zone should be showed like a highlight on the surface the cannon is
-- going to hit"): a glowing disc lying on the ground there, as wide as the shell hurts, and a brighter core pulsing in it
local zone: { fill: Part, core: Part }? = nil

local function disc(name: string, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = rgb(Palette.Artillery.Marker)
	p.Transparency = transparency
	p.Parent = workspace.Terrain
	return p
end

local function zoneParts(): { fill: Part, core: Part }
	if not zone or not zone.fill.Parent or not zone.core.Parent then
		zone = { fill = disc("ArtilleryZone", Cfg.Zone.fill), core = disc("ArtilleryZoneCore", Cfg.Zone.core[1]) }
	end
	return zone :: { fill: Part, core: Part }
end

-- lays the zone on the ground at `at` (its surface's `normal`), `radius` studs across half
local function showZone(at: Vector3, normal: Vector3, radius: number)
	local z = zoneParts()
	local n = if normal.Magnitude > 1e-3 then normal.Unit else Vector3.yAxis
	local side = n:Cross(Vector3.zAxis)
	side = if side.Magnitude > 1e-3 then side.Unit else n:Cross(Vector3.xAxis).Unit
	local cf = CFrame.fromMatrix(at + n * Cfg.Zone.lift, n, side) -- a cylinder's axis is its X
	local t = Cfg.Zone.thickness
	z.fill.Size = Vector3.new(t, radius * 2, radius * 2)
	z.fill.CFrame = cf
	local k = Cfg.Zone.coreShare
	z.core.Size = Vector3.new(t * 1.5, radius * 2 * k, radius * 2 * k)
	z.core.CFrame = cf
end

local function hideZone()
	if zone then
		zone.fill.Transparency, zone.core.Transparency = 1, 1
	end
end

-- the core's pulse (every frame while it shows)
local function pulseZone(clock: number)
	if zone and zone.fill.Transparency < 1 then
		local c = Cfg.Zone.core
		zone.core.Transparency = c[1] + (c[2] - c[1]) * (0.5 + 0.5 * math.sin(clock * Cfg.Zone.pulse))
	end
end

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
		ringFrame = ring
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
	hideZone()
end

-- an attachment at `at` whose X axis points along `axis` (the Beam's curve leaves along it)
local function along(a: Attachment, at: Vector3, axis: Vector3)
	local x = if axis.Magnitude > 1e-6 then axis.Unit else Vector3.xAxis
	local y = x:Cross(Vector3.yAxis)
	y = if y.Magnitude > 1e-3 then y.Unit else Vector3.zAxis
	a.WorldCFrame = CFrame.fromMatrix(at, x, y)
end

-- where a shell from `o` at `v` would first hit, and when (nil: nowhere within MaxFlight / above Arc.floor), past
-- everything in `skip`
local function trace(o: Vector3, v: Vector3, g: number, skip: { Instance }): (Vector3?, number, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = false
	params.CollisionGroup = "Default"
	-- a cast that passes swaying trees: they sway here, not on the server, so the arc can't stop on one where the shell
	-- doesn't (Studio round 1: the marker on a trunk, the shell 70 studs past it); it shows where it lands beyond them
	local function cast(from: Vector3, line: Vector3): RaycastResult?
		for _ = 1, 8 do
			local hit = workspace:Raycast(from, line, params)
			local tree = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
			while tree and not CollectionService:HasTag(tree, TreeSway.Tag) do
				tree = tree:FindFirstAncestorWhichIsA("Model")
			end
			if not hit or not tree then
				return hit
			end
			table.insert(skip, tree)
			params.FilterDescendantsInstances = skip
		end
		return nil
	end
	local step = Cfg.Arc.step
	local prev, t, last = o, step, 0
	while t <= Cfg.MaxFlight and prev.Y > Cfg.Arc.floor do
		local x, y, z = Rules.at(t, o.X, o.Y, o.Z, v.X, v.Y, v.Z, g)
		local q = Vector3.new(x, y, z)
		local hit = cast(prev, q - prev)
		if hit then
			return hit.Position, t - step + step * hit.Distance / (q - prev).Magnitude, hit.Normal
		end
		last, prev = t, q
		t += step
	end
	return nil, last, nil
end

-- asks for the map round `at` to be streamed in (where the arc comes down out of sight); one request at a time, and
-- only for a place `Arc.restream` studs from the last one
local streaming, streamedAt = false, nil :: Vector3?
local function stream(at: Vector3)
	if streaming or (streamedAt and (streamedAt - at).Magnitude < Cfg.Arc.restream) then
		return
	end
	streaming, streamedAt = true, at
	task.spawn(function()
		pcall(function()
			Players.LocalPlayer:RequestStreamAroundAsync(at)
		end)
		streaming = false
	end)
end

-- the arc of a shot with the gun's lay as posed (no scatter), to where it would first hit
local function drawArc(model: Model, p: Pose, character: Model)
	local gun = p.gun
	local pivot = model:GetPivot()
	local mx, my, mz, dx, dy, dz = Rules.muzzle(gun, p.traverse, p.elevation)
	local o = pivot:PointToWorldSpace(Vector3.new(mx, my, mz))
	local v = pivot:VectorToWorldSpace(Vector3.new(dx, dy, dz)) * gun.speed
	local g = gun.gravity
	local finish, last, normal = trace(o, v, g, { model, character })
	local function at(t: number): Vector3
		local x, y, z = Rules.at(t, o.X, o.Y, o.Z, v.X, v.Y, v.Z, g)
		return Vector3.new(x, y, z)
	end
	-- nothing hit: far out the ground may not be streamed in here yet (Studio round 3: the arc fell through it while
	-- the server's shell hit it). Show where it would come down level with the gun meanwhile, and ask for that ground.
	local estimated = false
	if not finish then
		local base = pivot.Position.Y
		local t = Rules.fall(o.Y - base, v.Y, g)
		if t and t <= Cfg.MaxFlight then
			finish, last, estimated = at(t), t, true
			stream(finish)
		end
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
	if finish then
		showZone(finish, normal or Vector3.yAxis, gun.zone)
		local z = zoneParts()
		z.fill.Transparency = Cfg.Zone.fill
	else
		hideZone()
	end
	-- the ring over it only where the fog would hide the zone
	if ringFrame then
		ringFrame.Visible = finish ~= nil
			and (finish - workspace.CurrentCamera.CFrame.Position).Magnitude > Cfg.Zone.ringFrom
	end
	local flat = Vector3.new(p1.X - o.X, 0, p1.Z - o.Z).Magnitude
	label.Text = `{if estimated then "~" else ""}{math.round(flat * Damage.Blast.MetresPerStud)} m`
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
			local p = poses[c :: any]
			if p and p.fx then
				ArtilleryCrystal.destroy(p.fx)
			end
			poses[c :: any] = nil
			loadings[c :: any] = nil
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
	local bracing = false -- a brace on its way (the howitzer's waits for its charge-up)
	local wantYaw, wantElevation = 0, 0
	local sentAt, sentYaw, sentElevation = 0, math.huge, math.huge
	local snap = true
	local fov = camera.FieldOfView
	local arcAt = 0

	-- the character's own movement keys are off while on a gun (WASD lays it): sunk above the default controls (this
	-- place has no PlayerModule to disable: Studio round 12); the lay reads the keys itself (UserInputService)
	local function moveKeys(on: boolean)
		if on then
			ContextActionService:UnbindAction("ArtilleryKeys")
		else
			ContextActionService:BindActionAtPriority(
				"ArtilleryKeys",
				function()
					return Enum.ContextActionResult.Sink
				end,
				false,
				Enum.ContextActionPriority.High.Value,
				Enum.KeyCode.W,
				Enum.KeyCode.A,
				Enum.KeyCode.S,
				Enum.KeyCode.D
			)
		end
	end

	local function getOff()
		-- the loading stops with the gunner; whoever gets on next picks it up
		local was = mine
		if was and loadings[was] then
			loadings[was].played = nil
		end
		local character = player.Character
		for _, tr in (character and tracks[character]) or {} do
			if tr.IsPlaying then
				tr:Stop(0.2)
			end
		end
		mine = nil
		moveKeys(true)
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
		moveKeys(false)
		local character = player.Character
		if character then
			-- fetched now, ready by their first play (Studio round 2: the first reload played a 0-length track)
			if p.gun.loads then
				loadTrack(character)
			end
			oneTrack(character, "brace", Cfg.Brace.animation)
			oneTrack(character, "crank", Cfg.Turn.crank)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not mine or processed then
			return
		end
		if Settings.pressed("Key_Fire", input) then
			-- loaded: brace now (the server's shot follows Brace.delay later)
			local readyAt = mine:GetAttribute("ReadyAt") :: number?
			local character = player.Character
			if (not readyAt or now() >= readyAt) and character and Cfg.Brace.animation then
				local tr = oneTrack(character, "brace", Cfg.Brace.animation)
				local p = poses[mine]
				if tr and p and not tr.IsPlaying and not bracing then -- (a second click doesn't start it again)
					-- its pull ("Fire") lands on the shot: at once for the field gun, after the howitzer's charge-up
					bracing = true
					local wait = math.max(p.gun.charge - Cfg.Brace.pull, 0)
					task.delay(wait, function()
						tr:Play(0.1)
					end)
					task.delay(p.gun.charge + 0.2, function()
						bracing = false
					end)
				end
			end
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
			local me = model:GetAttribute("Gunner") == player.UserId
			if me then
				found = model
			end
			load(model, p, me)
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

		-- WASD lays it (A / D turn, W / S raise / lower) at the gun's own rates: held, the aim leads the lay a little;
		-- let go, it stops where the gun is
		local menu = player:GetAttribute("MenuOpen") == true
		local function held(key: Enum.KeyCode): number
			return if not menu and UserInputService:IsKeyDown(key) then 1 else 0
		end
		local turn = held(Enum.KeyCode.A) - held(Enum.KeyCode.D) -- (+ turns left)
		local raise = held(Enum.KeyCode.W) - held(Enum.KeyCode.S)
		local _, pivotYaw = model:GetPivot():ToOrientation()
		local layYaw = math.deg(pivotYaw) + p.traverse
		wantYaw = Rules.wrap(layYaw + turn * Cfg.Aim.lead)
		wantElevation = math.clamp(p.elevation + raise * Cfg.Aim.lead, gun.elevation[1], gun.elevation[2])

		-- the aim, sent at most Aim.rate a second when it changed
		local t = os.clock()
		if
			t - sentAt >= 1 / Cfg.Aim.rate
			and (math.abs(wantYaw - sentYaw) > 0.01 or math.abs(wantElevation - sentElevation) > 0.01)
		then
			sentAt, sentYaw, sentElevation = t, wantYaw, wantElevation
			Net.event("Artillery"):FireServer("Aim", wantYaw, wantElevation)
		end

		-- winding the hand wheel while the gun is being laid
		local crank = oneTrack(character, "crank", Cfg.Turn.crank)
		if crank then
			local off = math.abs(Rules.wrap(wantYaw - layYaw)) + math.abs(wantElevation - p.elevation)
			local turning = off > Cfg.Turn.moving
			if turning and not crank.IsPlaying then
				crank:Play(Cfg.Turn.fade)
			elseif not turning and crank.IsPlaying then
				crank:Stop(Cfg.Turn.fade)
			end
		end

		-- the camera: out at the gun's left, turned right past the aim onto the gun, up with the elevation
		local c = gun.camera
		local pivot = model:GetPivot()
		local rot = CFrame.Angles(0, math.rad(wantYaw), 0)
		local base = pivot.Position
		local at = base + rot:VectorToWorldSpace(Vector3.new(c.side, c.up, c.back))
		local goal = CFrame.new(at)
			* CFrame.Angles(0, math.rad(wantYaw - c.yaw), 0)
			* CFrame.Angles(math.rad(c.pitch + math.max(wantElevation, 0) * c.follow), 0, 0)
		camera.CFrame = if snap then goal else camera.CFrame:Lerp(goal, math.min(1, dt * Cfg.CameraEase))
		snap = false

		pulseZone(os.clock())
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

	-- a shot: the muzzle blast, its report, and the whistle where it comes down
	Net.event("ArtilleryShot").OnClientEvent:Connect(function(model: Model, origin: Vector3, velocity: Vector3)
		local gun = Cfg.Guns[model and model:GetAttribute("Gun") :: any]
		if not gun then
			return
		end
		Vfx.Muzzle.play(origin, velocity, gun.muzzleScale)
		-- the report: up close the gun itself, far off the distant boom
		local eye = camera.CFrame.Position
		local d = (eye - origin).Magnitude
		local delay, high, low = Grenade.heard(d, Cfg.Heard, AudioCfg.Heard.speed)
		local report = if d > Cfg.FarFrom then gun.sound.far else gun.sound.fire
		SoundFx.play(report :: any, origin, nil, { delay = delay, eq = { low, 0, high } })
		-- the incoming shell's whistle, for whoever is near where it lands (the path as the server flies it, unscattered
		-- from here: the server sent the scattered velocity)
		local landing, flight = trace(origin, velocity, gun.gravity, { model })
		-- the blast of air round the gun, and the shell itself flying its path
		ArtilleryFx.shot(gun, origin, velocity)
		ArtilleryFx.shell(gun, origin, velocity, if landing then flight else Cfg.MaxFlight)
		local stop = charging[model]
		if stop then
			charging[model] = nil
			stop()
		end
		local lead = gun.sound.whistleLead
		if landing and flight >= lead and (eye - landing).Magnitude <= Cfg.Whistle.reach then
			SoundFx.play(gun.sound.whistle :: any, landing, nil, { delay = flight - lead })
		end
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
		ArtilleryFx.blast(gun, position)
		local d = (camera.CFrame.Position - position).Magnitude
		local delay, high, low = Grenade.heard(d, Cfg.Heard, AudioCfg.Heard.speed)
		SoundFx.play(gun.sound.blast :: any, position, nil, { delay = delay, eq = { low, 0, high } })
	end)
end

return Artillery
